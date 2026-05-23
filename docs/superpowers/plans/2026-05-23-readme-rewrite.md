# README Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `/Users/bruce/Documents/superscientist/README.md` with a new README that positions Superscientist as a compute-grounded AI scientist for autonomous physics-based modeling, per the approved spec at `docs/superpowers/specs/2026-05-23-readme-rewrite-design.md`.

**Architecture:** Single-file in-place replacement. Content is fully specified in the spec (§3.1–§3.9) and stitched into a 9-section README of ~150–180 lines. No code changes, no other file changes.

**Tech Stack:** GitHub-Flavored Markdown.

---

### Task 1: Replace `README.md` with the new content

**Files:**
- Modify (full replace): `/Users/bruce/Documents/superscientist/README.md`

**Reference spec:** `/Users/bruce/Documents/superscientist/docs/superpowers/specs/2026-05-23-readme-rewrite-design.md` (§3.1–§3.9)

- [ ] **Step 1: Confirm the current README is the one being replaced**

Run: `wc -l /Users/bruce/Documents/superscientist/README.md`
Expected: 117 lines (the pre-rewrite version, last edited 2026-05-23).

Run: `head -3 /Users/bruce/Documents/superscientist/README.md`
Expected output starts with `# Superscientist`. If it doesn't, stop and check `git status` — someone has touched it since the spec was written.

- [ ] **Step 2: Replace the file with the new content**

Use the Write tool to overwrite `/Users/bruce/Documents/superscientist/README.md` with exactly the content in the fenced block below. **Do not add, remove, or reword anything.** Wording polish was already applied during spec writing.

```markdown
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

## Installation

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
```

> ⚠️ **ASCII-diagram caveat for the Write tool:** the content above contains a fenced code block inside the README that holds the ASCII lifecycle diagram. When you call `Write`, pass the entire block verbatim. Do **not** "fix" the nested fences — GitHub renders the outer block as the diagram correctly because the fences delimit the diagram, not nested code. The README is plain Markdown, not a Markdown-inside-Markdown spec.

Note: the README's diagram is wrapped in a ```` ``` ```` fence (no language tag). GitHub-Flavored Markdown handles this correctly even though it sits inside what *looks like* an outer fence in this plan document. In the actual `README.md` file there is only one level of fencing.

- [ ] **Step 3: Verify the file was written**

Run: `wc -l /Users/bruce/Documents/superscientist/README.md`
Expected: between **100 and 200 lines** (target ~135–160). If outside this range, the content was truncated or duplicated — re-write from the spec.

Run: `head -5 /Users/bruce/Documents/superscientist/README.md`
Expected first three lines:
```
# Superscientist

> *Autonomous physics-based computational science — the AI scientist that runs the simulations, not just the literature.*
```

---

### Task 2: Verify acceptance criteria

**Files:** (read-only checks against `/Users/bruce/Documents/superscientist/README.md`)

- [ ] **Step 1: Confirm all 9 sections are present, in the right order**

Run:
```bash
grep -n '^## ' /Users/bruce/Documents/superscientist/README.md
```

Expected (exact match, in order):
```
## How it works
## Compute backends
## Skills
## Run until done — `run-workflow.sh`
## How it survives crashes
## Pair with physics skills
## Installation
## Health check — `workflow-reviewer` agent
## References
```

If any heading is missing, mis-ordered, or extra, fix the file before continuing.

- [ ] **Step 2: Confirm the ASCII lifecycle diagram is intact**

Run:
```bash
grep -c '─' /Users/bruce/Documents/superscientist/README.md
```
Expected: at least **8** (the box-drawing horizontal lines in the diagram). If 0, the unicode characters got corrupted on write — re-do Task 1 Step 2.

Run:
```bash
grep -c 'run-workflow.sh — session loop' /Users/bruce/Documents/superscientist/README.md
```
Expected: **1**.

- [ ] **Step 3: Confirm key links resolve syntactically (no broken Markdown)**

Run:
```bash
grep -nE '\]\([^)]*\)' /Users/bruce/Documents/superscientist/README.md
```
Expected output includes at least these URLs:
- `https://github.com/deepmodeling/dpdispatcher`
- `https://github.com/WuGroup-XJTLU/cc-skills-ZhenghaoWu-Group`
- `https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents`
- `https://github.com/obra/superpowers`
- `https://github.com/EvoScientist/EvoScientist`
- `https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep`

If any are missing or malformed (e.g., unmatched parens, trailing whitespace inside the link), fix them.

- [ ] **Step 4: Confirm no leftover content from the old README**

Run:
```bash
grep -nE 'File-centric, resumable, cross-session harness|Project Structure|Workflow Lifecycle$' /Users/bruce/Documents/superscientist/README.md
```
Expected: **no output** (these are old phrasings that should have been replaced). If anything matches, you partially overwrote the file — re-do Task 1 Step 2.

- [ ] **Step 5: Confirm only `local` and `slurm` appear in the backend matrix**

Run:
```bash
sed -n '/^## Compute backends/,/^## /p' /Users/bruce/Documents/superscientist/README.md | grep -E '^\| `(pbs|lsf|bohrium)`'
```
Expected: **no output**. The matrix should list only `local` and `slurm` (the user explicitly removed PBS/LSF/Bohrium from the matrix). Mentions of DPDispatcher's broader backend support are fine in prose; they just must not appear as rows in the matrix.

---

### Task 3: Commit

- [ ] **Step 1: Stage the README**

Run:
```bash
git -C /Users/bruce/Documents/superscientist add README.md
```

- [ ] **Step 2: Confirm only README.md is staged**

Run:
```bash
git -C /Users/bruce/Documents/superscientist diff --cached --name-only
```
Expected output:
```
README.md
```

If anything else is staged, unstage it with `git restore --staged <path>` and try again.

- [ ] **Step 3: Commit with a message that references the spec**

Run:
```bash
git -C /Users/bruce/Documents/superscientist commit -m "$(cat <<'EOF'
docs: rewrite README around autonomous physics-based computational science

Reposition as the compute-grounded AI scientist that runs simulations on
local/Slurm backends through autonomous, resumable session chains. Lead
with the lifecycle diagram and backend matrix; link the companion physics
skill marketplace at WuGroup-XJTLU/cc-skills-ZhenghaoWu-Group.

Spec: docs/superpowers/specs/2026-05-23-readme-rewrite-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Confirm the commit landed**

Run:
```bash
git -C /Users/bruce/Documents/superscientist log -1 --stat
```

Expected: a new commit titled `docs: rewrite README around autonomous physics-based computational science` with `README.md` listed as the only changed file.

---

## Done

When all checkboxes in Tasks 1–3 are checked, the README rewrite is complete. There is no follow-up work in this plan — other repo files (skills, agents, hooks, package.json) are intentionally out of scope per the spec's §6 (Non-goals).
