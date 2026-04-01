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
- `backend_profiles` with `type: "remote"` must include `config_path` (path to external machine config — validated for existence, never read) and `resource_defaults`
- Do NOT add extra fields (`description`, `known_pitfalls`, `safeguards`, `expected_walltime`, `execution_order`) — those belong in the design doc or plan doc, not the state file

### Step 4: Create `progress.log`

Single line. No more.

```
[YYYY-MM-DD HH:MM] Workflow created: <workflow_id>. Stages: N total, all pending.
```

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

# Direct conda env paths (conda activate unreliable in non-interactive shells)
CONDA_ENV="/Users/zhenghaowu/miniconda3/envs/omnischolar"
PYTHON="$CONDA_ENV/bin/python3"

# Check Python
$PYTHON --version || { echo "FAIL: python3 not found at $PYTHON"; exit 1; }

# Check software-specific tools (ADD ALL from design doc)
# Example for LAMMPS:
# LMP="$CONDA_ENV/bin/lmp"
# $LMP -h > /dev/null 2>&1 || { echo "FAIL: LAMMPS not found at $LMP"; exit 1; }

# Check Python libraries used in analysis stages
$PYTHON -c "import numpy; import matplotlib" || { echo "FAIL: required Python libraries not available"; exit 1; }

# Compute backend prerequisites
command -v uvx >/dev/null 2>&1 || { echo "FAIL: uvx not found"; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "FAIL: tmux not found"; exit 1; }
uvx --from dpdispatcher dpdisp --help > /dev/null 2>&1 || { echo "FAIL: dpdispatcher not accessible via uvx"; exit 1; }

echo "Environment ready."
```

**For each software in the design doc, add a check:**
- Simulation software (LAMMPS, VASP, RASPA2, GROMACS): check binary path
- Python libraries (AutoPoly, numpy, matplotlib, MDAnalysis): check import
- External tools (VESTA, Avogadro): check binary if used in scripts

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

**Commands must be exact.** Not "Run RASPA2 GCMC at 298K" but the actual command: `simulate -i simulation.input` or `lmp -in input.lammps`. If the exact command depends on stage preparation, describe the command template and what the subagent fills in.

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
