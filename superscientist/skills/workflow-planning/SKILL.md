---
name: workflow-planning
description: Use when an experiment design is approved and needs to be turned into a concrete stage-by-stage execution plan with checkpoint files
---

# Workflow Planning

## Overview

Turn an approved experiment design into a concrete execution plan with all checkpoint artifacts created.

**Core principle:** The plan creates the harness. After this skill completes, `workflow-state.json`, `progress.log`, and `init.sh` exist and are ready.

## Process

### Step 1: Read the Experiment Design Doc

Read the full design doc. Extract: objectives, stages, parameters, success criteria, pitfalls, software, walltimes.

### Step 2: Define Concrete Stages

For each stage in the design, define:

| Field | Content |
|---|---|
| `id` | `stage-1`, `stage-2`, `stage-3`, ... (always sequential integers) |
| `name` | Human-readable name |
| `depends_on` | List of stage IDs this depends on |
| `inputs` | Exact file paths (relative to workflow root) as array of strings |
| `outputs` | Expected output file paths as array of strings |
| `parameters` | Software-specific parameters from the design (object) |
| `success_criteria` | Specific, measurable criteria as a single string |
| `backend` | Backend profile name (optional — omit to use `default_backend`) |

**Stage ID rules:**
- Always `stage-N` with sequential integers: `stage-1`, `stage-2`, `stage-3`, `stage-4`, `stage-5`
- Never use sub-labels like `stage-2a`, `stage-2b` — even for parallel branches
- If the design doc uses sub-labels (e.g., "Stage 2a, 2b, 2c"), renumber them to sequential integers
- Branching is expressed via `depends_on`, not via IDs

**Output directory convention:**
- Each stage writes outputs to a `stage-N/` subdirectory
- Example: `stage-2/isotherm.csv`, `stage-3/output.log`
- Stage 1 may write to a named directory if outputs are shared inputs (e.g., `structures/`)

### Step 2b: Ask About Autonomous Mode

After defining all stages, ask the user:

> "This workflow has N stages. Enable autonomous session chaining? If yes, `executing-workflows` will launch a background runner that automatically chains Claude sessions until the workflow completes or blocks. Requires: tmux installed, tool permissions pre-approved in `.claude/settings.json`."

- If the user says yes → set `session_config.autonomous: true` in the `workflow-state.json` created in Step 3.
- If the user says no or skips → leave `session_config.autonomous: false` (the default).

### Step 3: Create `workflow-state.json`

Create with all stages in `pending` status. Every stage MUST have all fields shown below — no optional fields, no extra fields.

```json
{
  "workflow_id": "<topic>-YYYY-MM-DD",
  "version": 1,
  "created": "<ISO-timestamp>",
  "updated": "<ISO-timestamp>",
  "experiment_design": "<relative-path-to-design-doc>",
  "workflow_plan": "<relative-path-to-plan-doc>",
  "amendments": [],
  "session_config": {
    "autonomous": false,
    "session_budget": 6,
    "session_count": 0,
    "session_id": null,
    "session_cost": 0,
    "exit_reason": null,
    "stage_weights": {
      "sync": 1,
      "async": 1.5,
      "error_cycle": 2,
      "diagnostic": 2
    }
  },
  "default_backend": "local",
  "backend_profiles": {
    "local": {
      "type": "local",
      "config": {
        "batch_type": "Shell",
        "context_type": "LocalContext"
      }
    },
    "hpc-cluster": {
      "type": "remote",
      "batch_type": "Slurm",
      "config_path": "/home/user/.dpdisp/hpc_config.json",
      "resource_defaults": {
        "number_node": 1,
        "cpu_per_node": 16,
        "gpu_per_node": 0,
        "queue_name": "",
        "group_size": 1
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
      "outputs": ["stage-1/output.file"],
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

**Schema rules:**
- `stages` is an **array**, not an object
- `inputs` and `outputs` are **arrays of strings** (file paths), not objects
- `success_criteria` is a **single string**, not an array
- `parameters` is an **object** with key-value pairs
- Every stage includes ALL operational fields (`started_at`, `completed_at`, `retry_count`, `last_error`, `running_process`) initialized to `null`/`0`
- Top-level MUST include `version: 1` and `amendments: []`
- Top-level MUST include `default_backend` and `backend_profiles` (at minimum a `"local"` profile)
- Stage `backend` field is optional — `null` means use `default_backend`
- `backend_profiles` with `type: "remote"` must include `batch_type` (the scheduler type from the machine config, e.g., `"Slurm"`, `"PBS"`, `"LSF"`, `"SGE"`), `config_path` (path to external machine config — validated for existence, never read), and `resource_defaults`
- Top-level MUST include `session_config` with `session_budget` (default 6), `session_count` (0), `session_id` (null), `session_cost` (0), `exit_reason` (null), and `stage_weights` (sync: 1, async: 1.5, error_cycle: 2, diagnostic: 2). `session_count` is incremented by session-resume at each session start — single source of truth for session numbering. User may adjust `session_budget` and `stage_weights` after planning.
- `session_config.autonomous` is a boolean (default `false`). Set to `true` during planning when the user opts in to autonomous session chaining.
- Do NOT add extra fields (`description`, `known_pitfalls`, `safeguards`, `expected_walltime`, `execution_order`) — those belong in the design doc or plan doc, not the state file

### Step 4: Create `progress.log`

Single line via Bash tool. No more.

```bash
echo "[$(date -Iseconds)] Workflow created: <workflow_id>. N stages. Purpose: <purpose>." > progress.log
```

Note: `>` (create) not `>>` (append) — this is the initial creation.

### Step 5: Create `init.sh`

Build environment checks for **every** software tool in the workflow. This script runs at every session resume — if it's wrong, the workflow breaks.

**Critical rules:**
- Use `set -e` — fail immediately on any error
- Use **direct conda env paths**, not `conda activate` (unreliable in non-interactive shells)
- Every check MUST `exit 1` on failure — never use WARNING for required software
- Check every software binary, every Python library, every tool

**Template:**

```bash
#!/bin/bash
set -e

# ── Infrastructure (always required) ──
command -v uvx >/dev/null 2>&1 || { echo "FAIL: uvx not found"; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "FAIL: tmux not found"; exit 1; }
uvx --from dpdispatcher dpdisp --help > /dev/null 2>&1 || { echo "FAIL: dpdispatcher not accessible via uvx"; exit 1; }

# ── Project-specific (derive ALL from design doc) ──
# Use direct conda/venv paths — `conda activate` is unreliable in non-interactive shells.
# Every check MUST `exit 1` on failure — never WARNING for required software.
#
# Examples (adapt to your software stack):
# CONDA_ENV="/path/to/conda/env"
# PYTHON="$CONDA_ENV/bin/python3"
# $PYTHON --version || { echo "FAIL: python3 not found at $PYTHON"; exit 1; }
# $PYTHON -c "import numpy; import torch" || { echo "FAIL: required Python libraries not available"; exit 1; }
# command -v lmp >/dev/null 2>&1 || { echo "FAIL: LAMMPS not found"; exit 1; }
# command -v simpleFoam >/dev/null 2>&1 || { echo "FAIL: OpenFOAM not found"; exit 1; }

echo "Environment ready."
```

**For each software in the design doc, add a check:**
- Computation binaries (e.g., LAMMPS, OpenFOAM, VASP, GROMACS, custom solvers): check binary path
- Python/R libraries (e.g., numpy, torch, MDAnalysis, pandas, scikit-learn): check import
- External tools (e.g., AutoPoly, samtools, PLUMED, ffmpeg): check binary if used in scripts

### Step 6: Write Plan Doc

Save to `docs/superscientist/plans/YYYY-MM-DD-<topic>.md`:

```markdown
# [Topic] Workflow Plan

**Experiment Design:** [relative path to design doc]
**Workflow ID:** [workflow_id]
**Stages:** N total

## Stage Execution Order

1. Stage 1: [name] — [brief description]
2. Stage 2: [name] (depends on: stage-1) — [brief description]
...

## Per-Stage Details

### Stage N: [Name]
- **Dependencies:** [list]
- **Inputs:** [file paths]
- **Commands:** [exact commands to run — not vague descriptions]
- **Outputs:** [expected files]
- **Success criteria:** [specific]
- **Estimated walltime:** [from design]
- **Backend:** [profile name, e.g., "local" or "hpc-cluster"]
- **Dispatch mode:** [sync (local < 2 min) or async (tmux)]
```

**Commands must be exact.** Not "Run the simulation at 298K" but the actual command: `lmp -in input.lammps` or `python train.py --config config.yaml`. If the exact command depends on stage preparation, describe the command template and what the subagent fills in.

**Backend and dispatch:** Each stage specifies which backend profile to use. The `superscientist:compute-backend` skill handles dispatch — sync for local short jobs (< 2 min), async via tmux for everything else (remote backends always, local long jobs).

### Step 7: Commit All Artifacts

```bash
git add workflow-state.json progress.log init.sh docs/superscientist/plans/
git commit -m "feat: create workflow plan for <topic>"
```

### Step 8: Transition

Announce: "Workflow plan created. Invoke `superscientist:executing-workflows` to begin execution, or review the plan first."

## Red Flags

| Thought | Reality |
|---------|---------|
| "I'll create the state files later" | Create them now. They ARE the plan. |
| "init.sh can be generic" | Add software-specific checks from the design. Every tool. |
| "Dependencies are obvious" | Write them explicitly in `depends_on`. |
| "I'll use stage-2a/2b/2c for parallel branches" | Always sequential integers. Branching is in `depends_on`. |
| "`conda activate` works fine" | Not in non-interactive shells. Use direct paths. |
| "A WARNING is enough for missing software" | Hard fail (`exit 1`). Session-resume depends on this. |
| "Commands can be vague in the plan" | Exact commands. The executing agent needs them. |
