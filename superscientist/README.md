# Superscientist

A Claude Code plugin providing a file-centric, resumable, cross-session harness for computational science workflows. Workflows survive session boundaries via three checkpoint files — `workflow-state.json`, `progress.log`, and `init.sh` — so any new session can recover full context and continue where the last one left off.

## Features

- **File-centric** — structured checkpoint files (JSON state, progress log, init script) you can monitor at any time
- **Resumable** — new sessions recover full context from checkpoint files
- **Cross-session** — workflows survive session boundaries
- **Subagent-driven** — all work dispatched to subagents, executed sequentially
- **Software-agnostic** — harness pattern works for any computational software
- **Compute backend agnostic** — local Shell, Slurm, PBS, LSF, and Bohrium via DPDispatcher
- **Guided experiment design** — collaborative dialogue to define experiments before any computation begins
- **Automatic verification** — outputs checked against success criteria before marking stages done

## Workflow Lifecycle

Every workflow follows five phases:

1. **Design** — collaborative Q&A defines the experiment: system, method, parameters, success criteria (`experiment-design`)
2. **Plan** — convert the approved design into concrete stages with checkpoint files and an environment bootstrap script (`workflow-planning`)
3. **Execute** — dispatch a fresh subagent per stage, sequentially, submitting jobs to the configured compute backend (`executing-workflows` + `compute-backend`)
4. **Verify** — check each stage's outputs against its success criteria before marking it done (`result-verification`)
5. **Complete** — generate a summary report, update state, and commit (`workflow-completion`)

Three skills cut across all phases: `session-resume` recovers full context when a new session starts, `systematic-debugging` investigates root causes when any stage fails, and `checkpoint-management` manages reads and writes to the three state files.

## Skills

| Group | Skill | Purpose |
|---|---|---|
| Bootstrap | `using-superscientist` | Session start awareness |
| Bootstrap | `session-resume` | Cross-session recovery from checkpoint files |
| Design | `experiment-design` | Collaborative dialogue to define experiments |
| Planning | `workflow-planning` | Convert design into staged execution plan |
| Execution | `executing-workflows` | Sequential subagent dispatch |
| Execution | `compute-backend` | Submit jobs to any backend via DPDispatcher |
| Quality | `result-verification` | Verify outputs before marking done |
| Quality | `systematic-debugging` | Root cause investigation for failed stages |
| State | `checkpoint-management` | File-centric state system (JSON + log + init script) |
| Completion | `workflow-completion` | Summary report, archive, commit |

## Compute Backend

The `compute-backend` skill provides a unified interface for submitting computations to any backend — local Shell, Slurm, PBS, LSF, or Bohrium — through [DPDispatcher](https://github.com/deepmodeling/dpdispatcher). One code path handles both local and remote execution.

**How it works:**

1. The stage subagent prepares input scripts and files
2. `compute-backend` builds a `submission.json` describing the job (machine, resources, task, file transfers)
3. The submission is validated with a schema check and dry-run before dispatch
4. DPDispatcher handles submission, polling, and file transfer

**Sync vs. async dispatch:**

- **Sync** — local backend jobs expected to finish in under 2 minutes run inline; `dpdisp submit` blocks until complete
- **Async** — remote backends (or local jobs over 2 minutes) launch in a tmux session; a `DPDISP_DONE` marker file signals completion so the orchestrator can poll without holding context

Stage subagents invoke `compute-backend` automatically. Users do not call it directly.

## Workflow Reviewer

The `workflow-reviewer` agent audits workflow checkpoint files for correctness and health. Use it after unexpected session termination, before resuming a stale workflow, or as a general health check.

**What it checks:**

- JSON validity and required fields in `workflow-state.json`
- Stage status consistency (e.g., completed stages have `completed_at` timestamps)
- Stale processes (running stages whose PIDs are no longer alive)
- Output file existence for completed stages
- Dependency DAG validity (no cycles, no dangling references)

**Output:** categorized findings (Critical / Warning / Info) with a health verdict — HEALTHY, NEEDS_ATTENTION, or BROKEN.

## Installation

Clone or copy the plugin directory, then register it with your editor:

### Claude Code

```bash
git clone <repo-url> && cd superscientist
# Then register the plugin:
/install-plugin /path/to/superscientist
```

### Cursor

```
/add-plugin /path/to/superscientist
```

### OpenCode

Point your OpenCode configuration at the ESM entry point:

```
.opencode/plugins/superscientist.js
```

## Project Structure

```
superscientist/
  skills/          — 10 skill definitions (SKILL.md each)
  agents/          — workflow-reviewer agent
  hooks/           — SessionStart hooks (Claude Code + Cursor)
  .claude-plugin/  — Claude Code marketplace metadata
  .cursor-plugin/  — Cursor plugin config
  .opencode/       — OpenCode ESM plugin entry point
  package.json     — NPM package metadata
  README.md        — this file
```

## Reference

- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
