# Superscientist

> *Autonomous physics-based computational science — the AI scientist that runs the simulations, not just the literature.*

Most agentic research tools stop at reading papers or tuning neural networks. Superscientist closes the loop on physics-based modeling: a Claude Code harness that designs experiments with you, submits jobs to local or HPC backends, polls them across sessions, verifies the outputs, and resumes after crashes — autonomously, until the workflow completes.

## How it works

```
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

Every workflow runs through five phases. Three checkpoint files persist state across sessions, so any new Claude session can recover full context and continue — and `run-workflow.sh` chains sessions automatically until the workflow finishes.

## Compute backends

| Backend          | Type           | Dispatch                                | Typical use                                              |
|------------------|----------------|-----------------------------------------|----------------------------------------------------------|
| `local` (Shell)  | Local          | Sync (≤2 min) / async (longer)          | Quick tests, structure prep, lightweight analysis        |
| `slurm`          | HPC scheduler  | Async via tmux + `DPDISP_DONE` marker   | Academic clusters                                        |

Both backends share one code path through [DPDispatcher](https://github.com/deepmodeling/dpdispatcher) — the same stage subagent runs whether you target your laptop or a cluster. Async jobs launch in a tmux session and signal completion with a `DPDISP_DONE` marker file, so the orchestrator can poll without holding context.

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

## Run until done — `run-workflow.sh`

Workflows often span hours or days; Claude sessions are bounded. `run-workflow.sh` is a thin shell wrapper that launches `claude -p "Invoke session-resume"` in a loop and exits only when the workflow's state file reports `completed`, `blocked`, or `error`.

```bash
./run-workflow.sh /path/to/workflow-dir
```

Built-in safeguards:

- **Max-session cap** (default 20) — prevents runaway loops
- **Per-session timeout** (default 2h)
- **Rapid-failure detection** — halts after 3 consecutive sessions under 60s that made no progress
- **Pause gate** — `touch PAUSE` in the workflow dir to suspend without killing

Drop the wrapper, and the workflow is still fully resumable — any human can run `claude` in the directory, and `session-resume` will pick up the state from the checkpoint files.

## How it survives crashes

All state lives in three plain files inside the workflow directory:

| File                  | Role                                                                                  |
|-----------------------|---------------------------------------------------------------------------------------|
| `workflow-state.json` | Structured state: stages, statuses, retry counts, backend profiles, success criteria  |
| `progress.log`        | Append-only timeline of what happened, when                                           |
| `init.sh`             | Environment bootstrap — loads modules, activates envs, exports paths                  |

No daemon, no database, no in-memory state. A `kill -9`, a laptop crash, a session reset — none of them destroy progress. The next `session-resume` reads the three files and continues exactly where the last session stopped, including jobs already submitted to Slurm.

## Pair with physics skills

Superscientist is the orchestration harness. The simulation packages it drives — LAMMPS, GROMACS, CP2K, PySCF, MACE, ASE, RDKit, pymatgen, OVITO, packmol, freud, and more — live in a companion skill marketplace:

🔗 **[WuGroup-XJTLU/cc-skills-ZhenghaoWu-Group](https://github.com/WuGroup-XJTLU/cc-skills-ZhenghaoWu-Group)** — 22 installable skills covering molecular dynamics, quantum chemistry, ML potentials, materials informatics, and analysis.

Install whichever you need; superscientist remains software-agnostic by design.

## Reproducible LAMMPS environment

A companion repo — **[Chenghao-Wu/examples-superscientist](https://github.com/Chenghao-Wu/examples-superscientist)** — provides a pinned LAMMPS conda environment. Clone and run the bootstrap script once:

```bash
git clone https://github.com/Chenghao-Wu/examples-superscientist
cd examples-superscientist
bash bootstrap.sh
```

The bootstrap script downloads `micromamba` (if needed) and creates a `superscientist` conda environment from platform-specific lockfiles. All LAMMPS and Python commands go through `micromamba run`:

```bash
micromamba run -n superscientist lmp -in input.lmp
micromamba run -n superscientist python analysis.py
```

The repo includes `superscientist.json` (machine-readable command argv arrays) and `AGENTS.md` (human/AI-readable setup guide). The `compute-backend` skill reads `superscientist.json` to discover how to invoke LAMMPS — no hardcoded wrappers needed.

Supports linux-64, osx-arm64, and osx-64. Windows users should use WSL or the native LAMMPS installer. See the companion repo for platform details and lockfile reproducibility guarantees.

## Quick install

Paste either prompt into Claude Code — it will add the marketplace(s) and install everything for you.

**Just the harness:**

> Install the Superscientist plugin from https://github.com/Chenghao-Wu/superscientist —
> add it as a Claude Code plugin marketplace and install the `superscientist` plugin.

**Harness + companion physics skills (LAMMPS, GROMACS, CP2K, MACE, …):**

> Install Superscientist from https://github.com/Chenghao-Wu/superscientist and the
> companion skills from https://github.com/WuGroup-XJTLU/cc-skills-ZhenghaoWu-Group.
> Add both as Claude Code plugin marketplaces, install the `superscientist` plugin,
> and install all the physics skills from cc-skills-ZhenghaoWu-Group.

## Manual install

```bash
git clone <repo-url>
cd superscientist
```

Then register with your editor:

- **Claude Code:** `/install-plugin /path/to/superscientist`
- **Cursor:** `/add-plugin /path/to/superscientist`
- **OpenCode:** point your config at `.opencode/plugins/superscientist.js`

A `SessionStart` hook auto-invokes `using-superscientist` so the agent knows the harness is available.

## Health check — `workflow-reviewer` agent

A bundled agent that audits a workflow directory: JSON validity, stage-status consistency, stale PIDs, missing outputs, dependency cycles. Returns a verdict — `HEALTHY` / `NEEDS_ATTENTION` / `BROKEN`. Use after unexpected termination, before resuming a stale workflow, or as a general spot check.

## References

- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Anthropic engineering
- [DPDispatcher](https://github.com/deepmodeling/dpdispatcher) — the unified job-submission library
- Related projects: [obra/superpowers](https://github.com/obra/superpowers) (agentic methodology), [EvoScientist](https://github.com/EvoScientist/EvoScientist) (self-evolving research agents), [ARIS](https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep) (in-sleep research methodology)
