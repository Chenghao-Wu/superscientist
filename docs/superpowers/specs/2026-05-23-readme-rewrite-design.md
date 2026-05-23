# README Rewrite — Design Spec

**Date:** 2026-05-23
**Target file:** `/Users/bruce/Documents/superscientist/README.md`
**Status:** approved structure; awaiting user review of this spec before drafting the final README.

---

## 1. Goal

Rewrite `README.md` so it positions Superscientist as a **compute-grounded AI scientist for autonomous physics-based modeling** — contrasted with text-only research agents (papers, deep learning) — targeted at computational scientists, with concrete proof artifacts (lifecycle diagram, compute-backend matrix) on the first screen.

References that informed the framing:

- **[EvoScientist](https://github.com/EvoScientist/EvoScientist)** — self-evolving AI scientists / human-on-the-loop / confidence in positioning
- **[obra/superpowers](https://github.com/obra/superpowers)** — methodology-and-skills structure
- **[ARIS](https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep)** — autonomous workflow that runs while you sleep / methodology-not-platform framing

## 2. Decisions captured from brainstorming

| Question | Decision |
|---|---|
| Core framing | "Compute-grounded AI scientist" — physics-based modeling, not papers/DL |
| Primary audience | Computational scientists |
| Proof artifacts to feature early | Supported-backend matrix + lifecycle diagram |
| Stack scope | Two-track: backends shipped by superscientist (matrix); physics packages via companion repo (link) |
| Companion repo | [WuGroup-XJTLU/cc-skills-ZhenghaoWu-Group](https://github.com/WuGroup-XJTLU/cc-skills-ZhenghaoWu-Group) |
| Backend matrix scope | `local` + `slurm` only (drop PBS/LSF/Bohrium from the matrix; keep DPDispatcher mention) |
| Length target | Medium (~150–200 lines) |
| Structural approach | Approach 1 — positioning-first |

## 3. Section-by-section content

### 3.1 Opener (title + tagline + pitch)

```
# Superscientist

> Autonomous physics-based computational science — the AI scientist that
> runs the simulations, not just the literature.

Most agentic research tools stop at reading papers or tuning neural networks.
Superscientist closes the loop on physics-based modeling: a Claude Code
harness that designs experiments with you, submits jobs to local or HPC
backends, polls them across sessions, verifies the outputs, and resumes
after crashes — autonomously, until the workflow completes.
```

### 3.2 Lifecycle diagram

ASCII diagram showing the 5 phases, the session-chaining wrapper, and the checkpoint files.

```
## How it works

                      ┌─────────────────────────────────────┐
                      │   run-workflow.sh — session loop    │
                      │   resumes until workflow completes  │
                      └──────────────┬──────────────────────┘
                                     │
   ┌─────────┐   ┌────────┐   ┌────────────┐   ┌────────┐   ┌──────────┐
   │ Design  │──▶│  Plan  │──▶│  Execute   │──▶│ Verify │──▶│ Complete │
   └─────────┘   └────────┘   └────────────┘   └────────┘   └──────────┘
        │            │              │              │             │
        ▼            ▼              ▼              ▼             ▼
   experiment-  workflow-     executing-      result-       workflow-
   design       planning      workflows  +    verification  completion
                              compute-backend

   ┌─────────────────────────────────────────────────────────────────┐
   │  Checkpoint files (survive crashes, enable resumption):         │
   │  workflow-state.json  ·  progress.log  ·  init.sh               │
   └─────────────────────────────────────────────────────────────────┘
```

Caption (1–2 sentences):

> Every workflow runs through five phases. Three checkpoint files persist
> state across sessions, so any new Claude session can recover full context
> and continue — and `run-workflow.sh` chains sessions automatically until
> the workflow finishes.

### 3.3 Compute backends matrix

```
## Compute backends

| Backend          | Type           | Dispatch                                | Typical use                                              |
|------------------|----------------|-----------------------------------------|----------------------------------------------------------|
| `local` (Shell)  | Local          | Sync (≤2 min) / async (longer)          | Quick tests, structure prep, lightweight analysis        |
| `slurm`          | HPC scheduler  | Async via tmux + `DPDISP_DONE` marker   | Academic clusters                                        |

Both backends share one code path through [DPDispatcher](https://github.com/deepmodeling/dpdispatcher) —
the same stage subagent runs whether you target your laptop or a cluster.
Async jobs launch in a tmux session and signal completion with a `DPDISP_DONE`
marker file, so the orchestrator can poll without holding context.
```

### 3.4 Orchestration skills table

```
## Skills

Ten skills cover the full workflow. Subagents invoke them automatically — you don't call them directly.

| Group       | Skill                    | Purpose                                                          |
|-------------|--------------------------|------------------------------------------------------------------|
| Bootstrap   | `using-superscientist`   | Session-start awareness                                          |
| Bootstrap   | `session-resume`         | Recover full context from checkpoint files on a fresh session    |
| Design      | `experiment-design`      | Collaborative dialogue to define the experiment                  |
| Planning    | `workflow-planning`      | Convert the approved design into staged execution plan           |
| Execution   | `executing-workflows`    | Sequential subagent dispatch, one stage at a time                |
| Execution   | `compute-backend`        | Submit jobs to local or HPC backends via DPDispatcher            |
| Quality     | `result-verification`    | Verify each stage's outputs against success criteria             |
| Quality     | `systematic-debugging`   | Root-cause investigation when a stage fails                      |
| State       | `checkpoint-management`  | Read/write the three-file state system                           |
| Completion  | `workflow-completion`    | Summary report, archive, commit                                  |
```

### 3.5 Autonomous runner

```
## Run until done — `run-workflow.sh`

Workflows often span hours or days; Claude sessions are bounded.
`run-workflow.sh` is a thin shell wrapper that launches `claude -p "Invoke
session-resume"` in a loop and exits only when the workflow's state file
reports `completed`, `blocked`, or `error`.

```bash
./run-workflow.sh /path/to/workflow-dir
```

Built-in safeguards:

- **Max-session cap** (default 20) — prevents runaway loops
- **Per-session timeout** (default 2h)
- **Rapid-failure detection** — halts after 3 consecutive sessions under 60s that made no progress
- **Pause gate** — `touch PAUSE` in the workflow dir to suspend without killing

Drop the wrapper, and the workflow is still fully resumable — any human can
run `claude` in the directory, and `session-resume` will pick up the state
from the checkpoint files.
```

### 3.6 Crash survival

```
## How it survives crashes

All state lives in three plain files inside the workflow directory:

| File                  | Role                                                                            |
|-----------------------|---------------------------------------------------------------------------------|
| `workflow-state.json` | Structured state: stages, statuses, retry counts, backend profiles, success criteria |
| `progress.log`        | Append-only timeline of what happened, when                                      |
| `init.sh`             | Environment bootstrap — loads modules, activates envs, exports paths             |

No daemon, no database, no in-memory state. A `kill -9`, a laptop crash, a
session reset — none of them destroy progress. The next `session-resume`
reads the three files and continues exactly where the last session stopped,
including jobs already submitted to Slurm.
```

### 3.7 Pair with physics skills

```
## Pair with physics skills

Superscientist is the orchestration harness. The simulation packages it
drives — LAMMPS, GROMACS, CP2K, PySCF, MACE, ASE, RDKit, pymatgen, OVITO,
packmol, freud, and more — live in a companion skill marketplace:

🔗 **[WuGroup-XJTLU/cc-skills-ZhenghaoWu-Group](https://github.com/WuGroup-XJTLU/cc-skills-ZhenghaoWu-Group)**
— 22 installable skills covering molecular dynamics, quantum chemistry,
ML potentials, materials informatics, and analysis.

Install whichever you need; superscientist remains software-agnostic by design.
```

### 3.8 Installation

```
## Installation

```bash
git clone <repo-url>
cd superscientist
```

Then register with your editor:

- **Claude Code:** `/install-plugin /path/to/superscientist`
- **Cursor:** `/add-plugin /path/to/superscientist`
- **OpenCode:** point your config at `.opencode/plugins/superscientist.js`

A `SessionStart` hook auto-invokes `using-superscientist` so the agent knows
the harness is available.
```

### 3.9 Workflow-reviewer agent + references (combined tail)

```
## Health check — `workflow-reviewer` agent

A bundled agent that audits a workflow directory: JSON validity, stage-status
consistency, stale PIDs, missing outputs, dependency cycles. Returns a
verdict — `HEALTHY` / `NEEDS_ATTENTION` / `BROKEN`. Use after unexpected
termination, before resuming a stale workflow, or as a general spot check.

## References

- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Anthropic engineering
- [DPDispatcher](https://github.com/deepmodeling/dpdispatcher) — the unified job-submission library
- Related projects: [obra/superpowers](https://github.com/obra/superpowers) (agentic methodology), [EvoScientist](https://github.com/EvoScientist/EvoScientist) (self-evolving research agents), [ARIS](https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep) (in-sleep research methodology)
```

## 4. Section order (final)

1. Title + tagline + pitch
2. How it works (lifecycle diagram + caption)
3. Compute backends (matrix)
4. Skills (10-row table)
5. Run until done (`run-workflow.sh`)
6. How it survives crashes (checkpoint files)
7. Pair with physics skills (companion repo link)
8. Installation
9. Health check (`workflow-reviewer`)
10. References

## 5. What gets cut from the current README

- The "Features" bullet list — its content is absorbed into the pitch and section headers
- The "Workflow Lifecycle" prose — replaced by the diagram
- The "Compute Backend" deep dive on sync/async dispatch — collapsed into the matrix + a 2-sentence note
- The "Project Structure" tree — not useful to a computational scientist; lives in the repo tree itself
- Heavy detail on `workflow-reviewer` — collapsed to a short health-check section

## 6. Non-goals

- Marketing-grade copy or slogans beyond the tagline
- Step-by-step tutorial content (belongs in `docs/`, not the README)
- A comprehensive list of supported simulation packages (lives in the companion repo)
- Decisions about updating skills, agents, or hooks (README rewrite only)

## 7. Acceptance criteria

- New README replaces the current `README.md` in-place
- Length within 150–200 lines
- All section content matches §3 above; minor wording polish allowed during drafting
- ASCII diagram renders correctly in GitHub-flavored Markdown (no broken box-drawing characters)
- All hyperlinks resolve
- Commit message references this spec
