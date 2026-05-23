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
  "workflow_id": "<topic>-YYYY-MM-DD",
  "version": 1,
  "created": "<ISO-timestamp>",
  "updated": "<ISO-timestamp>",
  "experiment_design": "<relative-path-to-design-doc>",
  "workflow_plan": "<relative-path-to-plan-doc>",
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
      "name": "Human-readable name",
      "status": "pending",
      "depends_on": [],
      "backend": null,
      "inputs": ["path/to/input.file"],
      "outputs": [],
      "parameters": {
        "software": "SoftwareName",
        "key_param": "value"
      },
      "success_criteria": "Specific measurable criterion in a single string",
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
| `parameter_change` | Stage inputs or parameters | Change solver_tolerance from 1e-4 to 1e-6 |
| `criteria_change` | Stage success criteria | Tighten convergence threshold from 0.01 to 0.005 |
| `stage_insert` | Add a new stage | Insert validation stage between stages 2 and 3 |
| `stage_skip` | Mark stage as skipped | Skip optional analysis (not needed for this run) |
| `stage_rerun` | Invalidate completed stage | Re-run stage 2 with different parameters |

**Protocol steps:**

1. Agent proposes amendment to user in plain language:
   ```
   Amendment proposed: change solver_tolerance from 1e-4 to 1e-6 in stage-2.
   Reason: Stage-1 results show insufficient accuracy at current tolerance.
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
       "description": "Tighten solver_tolerance from 1e-4 to 1e-6 based on stage-1 results",
       "changes": {"parameters": {"solver_tolerance": {"old": "1e-4", "new": "1e-6"}}},
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

**All entries MUST be written via Bash tool using `$(date -Iseconds)`. Never generate timestamps as text — LLM timestamps drift by 5+ minutes.**

Canonical log command:
```bash
echo "[$(date -Iseconds)] <message>" >> progress.log
```

Examples:
```bash
echo "[$(date -Iseconds)] Session 1 started. Workflow: my-workflow-2026-04-01" >> progress.log
echo "[$(date -Iseconds)] Stage 1 (Stage name): status -> preparing" >> progress.log
echo "[$(date -Iseconds)] Stage 1: launched locally, PID 48291" >> progress.log
echo "[$(date -Iseconds)] Session 1 ended. Next: check stage-1 completion." >> progress.log
```

**Rules:**
- Append-only — NEVER modify or delete previous entries
- Each entry: `[ISO-8601-timestamp] message` (generated by `$(date -Iseconds)`)
- Session boundaries explicitly marked
- Every status transition logged

### 3. `init.sh` — Environment Bootstrap

```bash
#!/bin/bash
# Project-specific environment setup (created by workflow-planning)
# See workflow-planning/SKILL.md for init.sh template and conventions
set -e
# ... software checks derived from experiment design ...
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

The orchestrator monitors async processes using a **blocking background wait**, not a manual poll loop:

```bash
# run_in_background: true, timeout: 600000
while [ ! -f "stage-N/DPDISP_DONE" ]; do sleep 30; done; cat stage-N/DPDISP_EXIT_CODE
```

The orchestrator is auto-notified on completion. Decision logic on notification:

```
if DPDISP_DONE marker exists:
  read DPDISP_EXIT_CODE
  if 0: transition to post_processing
  else: transition to failed
```

If the background wait is lost (session boundary), `session-resume` Step 5 handles recovery:
- tmux alive → re-establish background monitoring
- tmux gone + `DPDISP_DONE` → process result immediately
- tmux gone + no `DPDISP_DONE` + `recovery_attempted: false` → re-launch, re-monitor
- tmux gone + no `DPDISP_DONE` + `recovery_attempted: true` → mark failed

### Quick Computations (sync path — local backend < 2 min)

Run `dpdisp submit` synchronously via the compute-backend skill. No tmux, no wrapper script. The subagent returns results inline.

## Red Flags

| Thought | Reality |
|---------|---------|
| "I'll just change this parameter" | Amendment protocol required. |
| "I'll update the log later" | Every status change logs immediately. |
| "I'll skip the JSON, too verbose" | If it's not in workflow-state.json, it doesn't exist. |
| "I remember the tmux session name" | Record it in running_process. Memory is unreliable. |
| "I'll write the log entry with Write/Edit" | Use Bash tool with `$(date -Iseconds)`. LLM timestamps drift by 5+ minutes. |
| "I'll count sessions from progress.log" | Read `session_count` from `workflow-state.json`. It's the single source of truth. |
