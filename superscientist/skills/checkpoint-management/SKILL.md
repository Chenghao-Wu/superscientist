---
name: checkpoint-management
description: Use when creating, reading, or updating workflow checkpoint files (workflow-state.json, progress.log, init.sh) — the file-centric state system for cross-session computational workflows
---

# Checkpoint Management

## Overview

All workflow state lives in files, not in Claude's context. Three mandatory artifacts track every workflow. Users can monitor them at any time (`cat`, `tail -f`).

**Core principle:** If it's not in a file, it doesn't exist.

## The Three Artifacts

### 1. `workflow-state.json` — The Task List

```json
{
  "workflow_id": "mof-screening-2026-03-31",
  "version": 1,
  "created": "2026-03-31T10:00:00Z",
  "updated": "2026-03-31T14:32:00Z",
  "experiment_design": "docs/superscientist/specs/2026-03-31-mof-screening-design.md",
  "workflow_plan": "docs/superscientist/plans/2026-03-31-mof-screening.md",
  "amendments": [],
  "default_backend": "local",
  "backend_profiles": {
    "local": {
      "type": "local",
      "config": {
        "batch_type": "Shell",
        "context_type": "LocalContext"
      }
    }
  },
  "stages": [
    {
      "id": "stage-1",
      "name": "Structure optimization",
      "status": "pending",
      "depends_on": [],
      "backend": null,
      "inputs": ["structures/initial.cif"],
      "outputs": [],
      "parameters": {
        "software": "VASP",
        "ENCUT": 400,
        "KPOINTS": "4 4 4"
      },
      "success_criteria": "Forces converged below 0.01 eV/A",
      "started_at": null,
      "completed_at": null,
      "retry_count": 0,
      "last_error": null,
      "running_process": null
    }
  ]
}
```

### Status Model (v2 — 9 states)

| Status | Meaning |
|---|---|
| `pending` | Not started, dependencies not yet met |
| `ready` | Dependencies met, eligible for execution |
| `preparing` | Building inputs, writing scripts |
| `running` | Computation launched, waiting for finish |
| `post_processing` | Computation done, collecting/parsing outputs |
| `completed` | Outputs verified against success criteria |
| `failed` | Failed (error in `last_error`) |
| `invalidated` | Was completed, upstream change makes results stale |
| `skipped` | User decided stage is unnecessary |

### Valid Transitions

```
pending → ready           (all depends_on completed)
ready → preparing         (subagent picks up stage)
preparing → running       (computation launched)
preparing → failed        (input preparation failed)
running → post_processing (computation finished)
running → failed          (computation crashed/timed out)
post_processing → completed (verification passed)
post_processing → failed  (verification failed)
completed → invalidated   (upstream re-run; see Invalidation)
invalidated → ready       (eligible for re-execution)
failed → ready            (retry; retry_count incremented)
any → skipped             (user decision only)
```

### Iron Rules

**Agents CAN freely update** (operational fields):
- `status`, `checkpoint`, `outputs`, `running_process`
- `started_at`, `completed_at`, `retry_count`, `last_error`

**Agents CANNOT modify without amendment protocol** (definitional fields):
- `name`, `depends_on`, `inputs`, `parameters`, `success_criteria`
- `backend`, `parameters.resource_overrides`
- Adding or removing stages
- Skipping or invalidating stages

**Every status change MUST append to `progress.log`.**

### Amendment Protocol

When a workflow change is needed, agents MUST use this protocol. Silent modifications are forbidden.

**Amendment types:**

| Type | What changes | Example |
|---|---|---|
| `parameter_change` | Stage inputs or parameters | Change ENCUT from 400 to 520 |
| `criteria_change` | Stage success criteria | Tighten force convergence to 0.005 eV/A |
| `stage_insert` | Add a new stage | Insert equilibration between stages 2 and 3 |
| `stage_skip` | Mark stage as skipped | Skip phonon calculation (not needed) |
| `stage_rerun` | Invalidate completed stage | Re-run stage 2 with different parameters |

**Protocol steps:**

1. Agent proposes amendment to user in plain language:
   ```
   Amendment proposed: change ENCUT from 400 to 520 in stage-2.
   Reason: Stage-1 results show high-energy states require larger basis set.
   Impact: Stage-2 and all downstream stages will need re-execution.
   Approve? [y/n]
   ```
2. If approved:
   - Increment `version` field
   - Append to `amendments` array:
     ```json
     {
       "id": "amend-1",
       "version": 2,
       "timestamp": "2026-03-31T15:00:00Z",
       "type": "parameter_change",
       "stage_id": "stage-2",
       "description": "Increase ENCUT from 400 to 520 based on stage-1 results",
       "changes": {"inputs": {"ENCUT": {"old": 400, "new": 520}}},
       "invalidated_stages": ["stage-2", "stage-3", "stage-4"],
       "approved_by": "user"
     }
     ```
   - Update affected stage fields
   - Cascade invalidation to all downstream stages (see Invalidation Cascade)
   - Append to `progress.log`
3. If rejected: no changes; agent proceeds with current plan

**Enforcement:** The `executing-workflows` skill checks for pending amendments before each stage dispatch. `checkpoint-management` validates that definitional fields have not been modified without a corresponding amendment record.

### Invalidation Cascade

When stage X is invalidated, ALL stages that transitively depend on X are also invalidated:

```
invalidate(stage_id):
  stage.status = "invalidated"
  append to progress.log
  for each stage S where stage_id in S.depends_on:
    if S.status == "completed":
      invalidate(S.id)
```

Only `completed` stages change status to `invalidated` — pending/ready stages are unaffected because dependency resolution already blocks them until upstream completes again. The `invalidated_stages` field in the amendment record is an audit trail of all affected stages, not a status assignment.

Old outputs are preserved: `stage-2/` → `stage-2.v1/` before re-execution.

### 2. `progress.log` — Human-Readable Log

```
[2026-03-31 10:05] Session 1 started. Workflow: mof-screening-2026-03-31
[2026-03-31 10:06] Stage 1 (Structure optimization): status → preparing
[2026-03-31 10:12] Stage 1: launched locally, PID 48291
[2026-03-31 10:12] Session 1 ended. Next: check stage-1 completion.
```

**Rules:**
- Append-only — NEVER modify or delete previous entries
- Each entry: `[YYYY-MM-DD HH:MM] message`
- Session boundaries explicitly marked
- Every status transition logged

### 3. `init.sh` — Environment Bootstrap

```bash
#!/bin/bash
conda activate omnischolar
which python3 || { echo "FAIL: python3 not found"; exit 1; }
echo "Environment ready."
```

**Rules:**
- Created by `workflow-planning` during plan creation
- Must be idempotent
- Must exit non-zero on any failure

## Process Management

All computations are dispatched through DPDispatcher via the `superscientist:compute-backend` skill. Local jobs use `batch_type: "Shell"`, HPC jobs use the appropriate scheduler.

### Background Launch (async path — remote backend, or local > 2 min)

1. The subagent invokes `superscientist:compute-backend`, which:
   - Builds `stage-N/submission.json`
   - Validates and dry-runs it
   - Writes a wrapper script `stage-N/dpdisp-run.sh`:
     ```bash
     #!/bin/bash
     cd "$(dirname "$0")/.."
     uvx --from dpdispatcher dpdisp submit [--allow-ref] stage-N/submission.json
     echo $? > stage-N/DPDISP_EXIT_CODE
     touch stage-N/DPDISP_DONE
     ```
   - Launches in tmux: `tmux new-session -d -s dpdisp_stage-N "bash stage-N/dpdisp-run.sh"`

2. Record in `running_process` field and update status to `running`:
   ```json
   "running_process": {
     "tmux_session": "dpdisp_stage-N",
     "submission_json": "stage-N/submission.json",
     "wrapper_script": "stage-N/dpdisp-run.sh",
     "done_marker": "stage-N/DPDISP_DONE",
     "exit_code_file": "stage-N/DPDISP_EXIT_CODE",
     "recovery_attempted": false,
     "launched_at": "2026-03-31T14:00:00Z"
   }
   ```

### Poll Protocol

```
if DPDISP_DONE marker exists:
  read DPDISP_EXIT_CODE
  if 0: transition to post_processing
  else: transition to failed
else if tmux session alive (tmux has-session -t dpdisp_stage-N):
  still running — log progress note
else (tmux gone, no marker):
  if recovery_attempted is false:
    re-launch dpdisp-run.sh in new tmux session
    set recovery_attempted: true
    DPDispatcher idempotent recovery resumes monitoring
  else:
    transition to failed — "monitoring process died twice"
```

### Quick Computations (sync path — local backend < 2 min)

Run `dpdisp submit` synchronously via the compute-backend skill. No tmux, no wrapper script. The subagent returns results inline.

## Red Flags

| Thought | Reality |
|---------|---------|
| "I'll just change this parameter" | Amendment protocol required. |
| "I'll update the log later" | Every status change logs immediately. |
| "I'll skip the JSON, too verbose" | If it's not in workflow-state.json, it doesn't exist. |
| "I remember the tmux session name" | Record it in running_process. Memory is unreliable. |
