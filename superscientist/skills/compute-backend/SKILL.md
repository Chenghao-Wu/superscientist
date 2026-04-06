---
name: compute-backend
description: Use when a workflow stage subagent has prepared computation scripts and needs to submit the job to a local or HPC backend via DPDispatcher
---

# Compute Backend

## Overview

Unified dispatch interface for superscientist workflow stages. All computations — local and remote — go through DPDispatcher.

**Core principle:** One code path. No branching between local bash wrappers and HPC submission. DPDispatcher handles everything.

**NEVER run the computation command directly.** This means no `bash script.sh`, no `python run.py`, no `command < input`, no subprocess, no shell exec — nothing that bypasses `dpdisp submit`. Local backends use `batch_type: Shell`, which still runs through DPDispatcher. There are zero exceptions to this rule, regardless of how simple, local, or fast the job appears.

**REQUIRED CONTEXT:** The orchestrator includes the backend profile in the subagent prompt under "Backend". Read it before using this skill.

## Quick Reference

| Operation | Command |
|---|---|
| Schema docs | `uvx --with dpdispatcher dargs doc dpdispatcher.entrypoints.submit.submission_args` |
| Validate | `uvx --with dpdispatcher dargs check [--allow-ref] -f dpdispatcher.entrypoints.submit.submission_args stage-{id}/submission.json` |
| Dry-run | `uvx --from dpdispatcher dpdisp submit --dry-run [--allow-ref] stage-{id}/submission.json` |
| Submit | `uvx --from dpdispatcher dpdisp submit [--allow-ref] stage-{id}/submission.json` |

| Decision | Sync | Async |
|---|---|---|
| Backend | Local | Remote (always) |
| Runtime | < 2 min | > 2 min or remote |
| Method | `dpdisp submit` directly | Wrapper script in tmux |
| tmux session | None | `dpdisp_stage-{id}` |
| Markers | None | `DPDISP_DONE`, `DPDISP_EXIT_CODE` |

**`--allow-ref` is REQUIRED** on all `dargs check` and `dpdisp submit` commands when `$ref` is used in the machine block.

## Workflow

### Step 1: Resolve Backend Profile

Read the profile from the "Backend" section of the subagent prompt:
- Profile name (e.g., `"local"`, `"hpc-cluster"`)
- Type (`"local"` or `"remote"`)
- Machine config (inline for local, `config_path` for remote)
- Resource defaults (merged with any stage-level `resource_overrides`)

### Step 2: Acquire Schema (optional)

If using the templates below, skip this step. Otherwise, run:

```bash
uvx --with dpdispatcher dargs doc dpdispatcher.entrypoints.submit.submission_args
```

This defines valid fields, types, and defaults for `submission.json`.

### Step 3: Build submission.json

**Before building:** Copy any dependency outputs from prior stages into `stage-{id}/` so paths resolve correctly (see File Transfer Heuristics).

Write to `{workflow_root}/stage-{id}/submission.json`. The JSON is flat — **no `"submission": { ... }` wrapper** (causes `dargs check` to fail with "undefined key `submission`").

**Working directory:** The command runs in `{local_root}/{work_base}/{task_work_path}`, which for local jobs resolves to `{workflow_root}/stage-{id}/`.

#### Local backend template

```json
{
  "work_base": ".",
  "machine": {
    "batch_type": "Shell",
    "context_type": "LocalContext",
    "local_root": "/absolute/path/to/workflow/root",
    "remote_root": "/absolute/path/to/workflow/root"
  },
  "resources": {
    "number_node": 1,
    "cpu_per_node": 1,
    "gpu_per_node": 0,
    "group_size": 1,
    "queue_name": ""
  },
  "task_list": [
    {
      "command": "<command from stage parameters>",
      "task_work_path": "stage-1",
      "forward_files": ["<input files for this stage>"],
      "backward_files": ["<expected output files>", "log", "err"]
    }
  ]
}
```

- `task_list` field names above are descriptive placeholders, not literal filenames. Replace with actual files from the stage spec. `log` and `err` are DPDispatcher standard outputs — always include them. Add software-specific log files to `backward_files`.
- `local_root` and `remote_root`: REQUIRED even for LocalContext (without them, `dpdisp submit` crashes with `KeyError: 'remote_root'`). Both are the workflow root absolute path. Resolve via `$(pwd)`.
- `resources`: Start from the profile's `resource_defaults`. If none provided, use the values above as defaults. Apply any stage-level `resource_overrides` on top.

#### Remote backend template

```json
{
  "work_base": ".",
  "machine": {
    "$ref": "/home/user/.dpdisp/hpc_config.json"
  },
  "resources": {
    "queue_name": "gpu",
    "number_node": 4,
    "cpu_per_node": 16,
    "gpu_per_node": 2,
    "group_size": 1,
    "custom_flags": ["#SBATCH --qos=4gpus", "#SBATCH --mem-per-gpu=10G"],
    "module_list": ["cuda/12.0", "openmpi/4.1"],
    "source_list": ["/path/to/env_setup.sh"],
    "prepend_script": ["bash stage-3/validate_env.sh || exit 1"]
  },
  "task_list": [
    {
      "command": "<command from stage parameters>",
      "task_work_path": "stage-3",
      "forward_files": ["<input files>", "<dependency outputs>", "validate_env.sh"],
      "backward_files": ["<expected output files>", "<restart/checkpoint files>", "log", "err"]
    }
  ]
}
```

- `$ref` is a plain file path — NOT a JSON Pointer (`$ref:/path#/key` is WRONG). **NEVER read the referenced file** (contains credentials).
- **All `dargs check` and `dpdisp submit` commands MUST include `--allow-ref`** when `$ref` is used.
- `custom_flags`: Extra scheduler-header lines inserted **verbatim** by DPDispatcher. Each entry MUST include the scheduler prefix (e.g., `#SBATCH` for Slurm). See Custom Flags Validation below.
- `module_list`: HPC modules loaded before the command runs.
- `source_list`: Shell scripts sourced before the command. Does NOT abort on failure — use for non-critical environment setup only.
- `prepend_script`: Shell lines executed before the task command **at the submission root** (NOT inside `task_work_path`). Use `|| exit 1` to abort on failure. Since `forward_files` are placed under `task_work_path`, reference them with the path prefix: `bash stage-{id}/validate_env.sh`, not `bash validate_env.sh`. See Pre-flight Validation below.
- `validate_env.sh`: Include in `forward_files` so it is uploaded to the remote under `task_work_path`.

#### envsubst (conditional)

If non-machine fields use `${VAR}` placeholders (e.g., resource paths from env vars):
1. Write `stage-{id}/submission.template.json` with placeholders
2. Run: `envsubst '${VAR1} ${VAR2}' < stage-{id}/submission.template.json > stage-{id}/submission.json`
3. **NEVER read `submission.json` after `envsubst`** — it contains resolved secrets

#### Custom Flags Validation

DPDispatcher inserts `custom_flags` entries **verbatim** into the generated submission script. It does NOT auto-prepend the scheduler directive prefix. Entries without the correct prefix appear as bare shell lines and are silently ignored by the scheduler.

**Before building submission.json**, validate every `custom_flags` entry:

1. Look up `batch_type` from the backend profile:
   - Local: `config.batch_type` (inline in profile)
   - Remote: top-level `batch_type` field in the profile (set by `workflow-planning`)

2. Check the required prefix:

| `batch_type` | Required prefix | Example |
|---|---|---|
| `Slurm` / `SlurmJobArray` | `#SBATCH` | `"#SBATCH --qos=4gpus"` |
| `PBS` / `Torque` | `#PBS` | `"#PBS -l walltime=24:00:00"` |
| `LSF` | `#BSUB` | `"#BSUB -R rusage[mem=10000]"` |
| `SGE` | `#$` | `"#$ -l h_vmem=10G"` |
| `Shell` | N/A | Warn if `custom_flags` is non-empty (local Shell has no scheduler) |

3. If any entry lacks the correct prefix, **stop and report to the orchestrator.** Do not proceed to validation or submission.

**Auto-generated directive reference (Slurm):** These `resources` fields automatically generate Slurm directives. Do NOT duplicate them in `custom_flags`:

| Resource field | Auto-generated directive (as of DPDispatcher v0.6+) |
|---|---|
| `number_node` | `#SBATCH --nodes N` |
| `cpu_per_node` | `#SBATCH --ntasks-per-node N` |
| `gpu_per_node` | `#SBATCH --gres=gpu:N` |
| `queue_name` | `#SBATCH --partition NAME` |

This mapping is internal to DPDispatcher and may change across versions. It is a reference for human awareness, not automated validation.

#### Pre-flight Validation (remote backends)

For remote backend stages, generate a stage-specific validation script based on the stage's `parameters` (software, required packages, flags). This catches environment mismatches before the actual computation runs, inside the same Slurm allocation — zero extra jobs.

**How it works:**

1. Write a validation script to `stage-{id}/validate_env.sh` based on the stage's software and flags:

```bash
#!/bin/bash
# validate_env.sh — uploaded as forward_file, executed via prepend_script
# Checks generated from stage parameters — adapt per software

# Check binary exists (required for every stage)
command -v <binary> >/dev/null 2>&1 || { echo "FAIL: <binary> not found in PATH"; exit 1; }

# Check software-specific requirements (examples — adapt per tool):
#   lmp -h 2>&1 | grep -q "GPU"                                    # LAMMPS GPU package
#   python -c "import torch; assert torch.cuda.is_available()"      # PyTorch GPU
#   simpleFoam -help 2>&1 | head -1                                 # OpenFOAM binary
#   gmx --version 2>&1 | grep -q "GROMACS"                          # GROMACS availability

echo "ENV_VALIDATION_PASSED"
```

2. Add `validate_env.sh` to `forward_files` so DPDispatcher uploads it to the remote.
3. Add `"bash stage-{id}/validate_env.sh || exit 1"` to the `prepend_script` array in `resources`. The `stage-{id}` prefix is required because `prepend_script` runs at the submission root, while `forward_files` are placed under `task_work_path`.

**Why `prepend_script` and not `source_list`:** DPDispatcher renders `source_list` entries as bare `source {file}` lines with no error checking. A failing `source` does not abort execution. `prepend_script` lines run as shell commands with explicit `|| exit 1`, which aborts the job immediately on failure.

**When to generate:** For every remote backend stage. The validation checks are derived from:
- `parameters.software` → check binary exists in PATH
- Command flags that depend on optional features → check those features are available
- `[UNVERIFIED]` annotations in the experiment design → mandatory validation

**When to skip:** Local backend stages (`batch_type: Shell`) do not need pre-flight validation — `init.sh` already validates the local environment.

### Step 4: Validate & Dry-Run

Run both in sequence. If either fails, stop and report to the orchestrator.

```bash
# Schema validation
uvx --with dpdispatcher dargs check [--allow-ref] \
  -f dpdispatcher.entrypoints.submit.submission_args \
  stage-{id}/submission.json

# Dry-run: parses config, validates paths — does NOT submit
uvx --from dpdispatcher dpdisp submit --dry-run [--allow-ref] \
  stage-{id}/submission.json
```

The dry-run catches path resolution issues that schema validation misses (e.g., invalid `$ref` targets).

### Step 5: Dispatch

**Sync path** (local backend AND expected runtime < 2 min):

```bash
uvx --from dpdispatcher dpdisp submit [--allow-ref] stage-{id}/submission.json
```

Report results inline: exit code, output files, any warnings from logs.

**Async path** (remote backend always, OR local > 2 min):

Use these EXACT names — the orchestrator's poll protocol depends on them:

1. Write **`stage-{id}/dpdisp-run.sh`**:
   ```bash
   #!/bin/bash
   cd "$(dirname "$0")/.."
   uvx --from dpdispatcher dpdisp submit [--allow-ref] stage-{id}/submission.json
   echo $? > stage-{id}/DPDISP_EXIT_CODE
   touch stage-{id}/DPDISP_DONE
   ```

2. Launch in tmux as **`dpdisp_stage-{id}`**:
   ```bash
   tmux kill-session -t dpdisp_stage-{id} 2>/dev/null
   tmux new-session -d -s dpdisp_stage-{id} "bash stage-{id}/dpdisp-run.sh"
   ```

3. Verify: `tmux has-session -t dpdisp_stage-{id} 2>/dev/null && echo "Running" || echo "FAIL"`

4. Report to orchestrator: tmux session name, submission.json path.

## File Transfer Heuristics

All paths in `forward_files` and `backward_files` are **relative to `task_work_path`** (i.e., relative to `stage-{id}/`).

**forward_files** — everything the job reads:
- Scripts/configs prepared for this stage (e.g., input scripts, data files)
- Dependency outputs from prior stages — **copy into `stage-{id}/` first**, then list the copied filename:
  ```bash
  cp ../stage-2/output.data stage-{id}/input.data
  ```
- Auxiliary files referenced in scripts (parameter files, configuration files, data tables)

**backward_files** — everything that needs to come back:
- All expected output files from the stage spec's `outputs`
- Always include: `log`, `err` (DPDispatcher standard output)
- Restart/checkpoint files the computation produces

## Important Notes

- **DPDISP_EXIT_CODE** reflects DPDispatcher's exit code, NOT scientific correctness. The orchestrator always proceeds to `result-verification` regardless.
- **DPDispatcher polls internally** every 30 s in blocking mode. The tmux session keeps this alive across session boundaries.
- **Recovery:** If tmux dies without `DPDISP_DONE`, re-launch `dpdisp-run.sh` in a new tmux session. DPDispatcher's idempotent recovery resumes monitoring without re-submitting.

## Diagnostic Reproduction Run

When an HPC stage fails and DPDispatcher aborts the `backward_files` download (because a required output file doesn't exist on the remote), the orchestrator may dispatch a **diagnostic reproduction run** to obtain error logs.

**Key constraint:** This is a NEW job execution, not a file transfer. DPDispatcher creates a content-hashed remote directory per submission — it cannot access files from a previous job's directory. The reproduction run re-executes the command. This means:
- It consumes an HPC allocation
- It only works if the failure reproduces (configuration errors like missing packages, wrong flags, resource mismatches always reproduce)
- For intermittent failures, `dpdispatcher.log` (Level 1 diagnostics) may be the only option

**When the orchestrator prompt says "This is a diagnostic run":**

1. Write `stage-{id}/submission.diagnostic.json` — NOT `submission.json`. The original `submission.json` is preserved for the real fix retry.
2. Use the same `command` and `forward_files` as the original `submission.json`.
3. Set `backward_files` to `["log", "err"]` only — no output files that might be missing.
4. Validate and submit `submission.diagnostic.json` using the same steps (dargs check → dry-run → submit).
5. For the wrapper script, reference the diagnostic file:
   ```bash
   uvx --from dpdispatcher dpdisp submit [--allow-ref] stage-{id}/submission.diagnostic.json
   ```
6. After the diagnostic run completes, leave `submission.diagnostic.json` in place for debugging reference.

## Retry Modes

When `retry_count > 0`, the orchestrator prompt specifies one of two modes:

**Reuse mode** (default for retries after script-level fixes):
1. Check that `stage-{id}/submission.json` exists.
2. Validate and dry-run it (the fix was to the input script, not the submission configuration).
3. Submit the existing `submission.json` as-is.
4. Do NOT regenerate submission.json from scratch.

**Regenerate mode** (when the fix changes submission parameters):
1. Rebuild `submission.json` from the stage's updated `parameters` and `resource_overrides`.
2. Validate and dry-run.
3. Submit the new `submission.json`.

The orchestrator chooses the mode based on the nature of the fix:
- Input script fix (e.g., corrected a flag in the computation command) → **reuse**
- Submission parameter fix (e.g., change `gpu_per_node`, add `custom_flags`) → **regenerate**

## Security Guardrails

- **NEVER read external `$ref` config files** — they contain credentials
- **NEVER read `submission.json` after `envsubst`** — it contains resolved secrets
- **NEVER use direct SSH** — all remote operations through DPDispatcher only
- **NEVER run the computation command directly** — not even for local, not even once to "test" it

## Red Flags

| Thought | Reality |
|---------|---------|
| "I'll SSH to check the job" | All remote operations go through DPDispatcher. No direct SSH. |
| "Let me read the machine config to verify it" | NEVER read `$ref` config files. They contain credentials. |
| "I'll skip the dry-run, validation passed" | Dry-run catches path issues validation misses. Always run both. |
| "This local job is fast, skip tmux" | Only skip tmux for local backend AND < 2 min expected runtime. |
| "I'll set forward_files later" | Build the complete file list now. Missing files = failed job on remote. |
| "I'll call `bash validate_env.sh` from prepend_script" | `prepend_script` runs at the submission root, not `task_work_path`. Use `bash stage-{id}/validate_env.sh` with the full path prefix. |
| "Let me read submission.json to verify envsubst worked" | NEVER read after envsubst. It contains resolved secrets. |
| "I'll write my own wrapper script" | Use the EXACT template. The orchestrator depends on `dpdisp-run.sh`, `DPDISP_DONE`, `DPDISP_EXIT_CODE`, and `dpdisp_stage-{id}` naming. |
| "The key is `task` not `task_list`" | It is `task_list` (array). |
| "I'll wrap it in `{submission: {...}}`" | No wrapper. Flat JSON. `dargs check` rejects a `submission` key. |
| "It's just a local job, I'll run the command directly" | **NEVER.** Local backends use `batch_type: Shell` — still submitted via `dpdisp submit`. |
| "DPDispatcher is slow/complex for this simple script" | Complexity is irrelevant. Every job goes through `dpdisp submit`. No exceptions. |
| "I'll run it directly first to test, then use DPDispatcher for real" | **NEVER run directly.** Validate with `dargs check` and `--dry-run`. That is sufficient. |
| "I'll just `bash` the run script I wrote" | Only valid script to run is `dpdisp-run.sh` inside tmux. Never bash the simulation script directly. |
| "The submission.json is ready, but dpdisp seems broken — I'll just run the command" | Stop and debug DPDispatcher. Do not bypass it. Report the failure to the orchestrator. |
| "I'll overwrite submission.json for the diagnostic run" | Write `submission.diagnostic.json`. The original is needed for the fix retry. |
| "Let me regenerate submission.json for the retry" | Check the orchestrator prompt: reuse or regenerate? Reuse is the default. |
| "custom_flags don't need #SBATCH" | DPDispatcher inserts them verbatim. Missing prefix = silently ignored by scheduler. |
