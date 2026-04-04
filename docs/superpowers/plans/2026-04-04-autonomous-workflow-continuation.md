# Autonomous Workflow Continuation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two failure modes in the superscientist orchestrator — stage-boundary stall and polling death — so multi-stage workflows run autonomously without user intervention (except for experiment-design approval and amendment approval).

**Architecture:** Strengthen skill language in `executing-workflows/SKILL.md` to prevent stalling at stage boundaries (prescriptive iron law, inline reminders, anti-stall red flags). Replace the manual poll loop with a `run_in_background` blocking wait for async job monitoring. Update `checkpoint-management/SKILL.md` and `session-resume/SKILL.md` to match.

**Tech Stack:** Markdown skill files (no code, no dependencies)

**Spec:** `docs/superpowers/specs/2026-04-04-autonomous-workflow-continuation-design.md`

---

### Task 1: Add Autonomous Execution Law to executing-workflows

**Files:**
- Modify: `superscientist/skills/executing-workflows/SKILL.md:14-16` (insert after the Persistence rule, before Quick Reference)

- [ ] **Step 1: Insert the Autonomous Execution Law section**

After the line:

```
**Persistence rule:** Every status transition must be written to `workflow-state.json` AND appended to `progress.log` *before* the next action.
```

And before the line:

```
## Quick Reference
```

Insert:

```markdown

## The Autonomous Execution Law

```
AFTER EACH STAGE, YOU MUST IMMEDIATELY EXECUTE THE CONTINUATION STEPS IN STEP 5.
THERE IS NO PAUSE POINT BETWEEN STAGES.
```

The user approved the workflow plan. That approval covers ALL stages. Do not ask for re-confirmation between stages. Do not report intermediate results in conversation. Do not summarize what just happened. Log to `progress.log` and continue.

**The ONLY reasons to pause and inform the user:**
1. Retry limit exceeded (3 local / 5 remote)
2. Workflow blocked (no ready/running stages, uncompleted stages remain)
3. Amendment needed (definitional field change requires user approval)
4. Context limit — ONLY when the system has explicitly warned about approaching context limits. "The conversation feels long" is NOT a valid reason.

**Violating the letter of this rule is violating the spirit of this rule.**

```

- [ ] **Step 2: Verify the section is positioned correctly**

Read `superscientist/skills/executing-workflows/SKILL.md` and confirm:
- The Autonomous Execution Law appears between the Persistence rule and Quick Reference
- The three-backtick code block inside the section renders as a highlighted block
- No formatting errors

- [ ] **Step 3: Commit**

```bash
git add superscientist/skills/executing-workflows/SKILL.md
git commit -m "feat(superscientist): add Autonomous Execution Law to executing-workflows"
```

---

### Task 2: Update Execution Loop diagram and Quick Reference

**Files:**
- Modify: `superscientist/skills/executing-workflows/SKILL.md` (Quick Reference table and Execution Loop diagram)

- [ ] **Step 1: Update Quick Reference async description**

In the Quick Reference table, change:

```
| Dispatch (async) | `ready` -> `preparing` -> `running` -> `post_processing` -> `completed`/`failed` | tmux wrapper, poll for DPDISP_DONE |
```

To:

```
| Dispatch (async) | `ready` -> `preparing` -> `running` -> `post_processing` -> `completed`/`failed` | tmux wrapper, background wait for DPDISP_DONE |
```

- [ ] **Step 2: Update Execution Loop diagram**

In the `digraph execution` block, replace these three nodes and edges:

```
    "Poll (60s interval)" [shape=box];
```

With:

```
    "Background wait\n(run_in_background)" [shape=box];
```

And replace:

```
    "Launch async, record tmux" -> "Poll (60s interval)";
    "Poll (60s interval)" -> "Done?";
```

With:

```
    "Launch async, record tmux" -> "Background wait\n(run_in_background)";
    "Background wait\n(run_in_background)" -> "Done?";
```

And replace:

```
    "Done?" -> "Poll (60s interval)" [label="tmux alive"];
```

With:

```
    "Done?" -> "Background wait\n(run_in_background)" [label="timeout, re-wait"];
```

And rename the Step 5 node from:

```
    "Set post_processing,\ninvoke result-verification" [shape=box];
```

To:

```
    "Verify, complete,\nand continue" [shape=box];
```

And update both edges pointing to it:

```
    "Run sync, get result" -> "Verify, complete,\nand continue";
```

```
    "Done?" -> "Verify, complete,\nand continue" [label="DPDISP_DONE"];
```

And update the edge from it:

```
    "Verify, complete,\nand continue" -> "Passed?";
```

- [ ] **Step 3: Verify diagram consistency**

Read the full diagram and confirm all node names and edges are consistent — no dangling references to old names.

- [ ] **Step 4: Commit**

```bash
git add superscientist/skills/executing-workflows/SKILL.md
git commit -m "feat(superscientist): update execution loop diagram and quick reference for background wait"
```

---

### Task 3: Add inline continuation reminders

**Files:**
- Modify: `superscientist/skills/executing-workflows/SKILL.md` (Dependency Resolution section, Step 3)

- [ ] **Step 1: Add reminder at end of Dependency Resolution**

After the line:

```
**"First" stage:** When multiple stages are `ready`, select the first by array order in `workflow-state.json`.
```

Add:

```markdown

**→ After resolving dependencies, return to stage selection. Do not pause.**
```

- [ ] **Step 2: Add reminder at end of Step 3 (Process Subagent Result)**

After the current Step 3 content ending with:

```
**Async** (remote, or local > 2 min): Subagent reports tmux session name and submission.json path. Update status: `preparing` -> `running`. Record `running_process` in `workflow-state.json` per the schema in `checkpoint-management`. Log: `[timestamp] stage-N: status -> running (tmux: dpdisp_stage-N)`.
```

Add:

```markdown

**→ Continue to Step 4 (async) or Step 5 (sync). Do not report to the user.**
```

- [ ] **Step 3: Commit**

```bash
git add superscientist/skills/executing-workflows/SKILL.md
git commit -m "feat(superscientist): add inline continuation reminders at decision points"
```

---

### Task 4: Replace Step 4 with blocking background wait

**Files:**
- Modify: `superscientist/skills/executing-workflows/SKILL.md` (Step 4 section, lines 179-202)

- [ ] **Step 1: Replace the entire Step 4 section**

Replace from `### 4. Monitor Background Process (async only)` through the Session boundary note (ending at `**Session boundary:** If context is getting long, log...`) with:

```markdown
### 4. Monitor Background Process (async only)

**DO NOT poll manually in a loop.** Use a blocking background wait:

```bash
# run_in_background: true, timeout: 600000
while [ ! -f "stage-N/DPDISP_DONE" ]; do sleep 30; done; cat stage-N/DPDISP_EXIT_CODE
```

You will be auto-notified when the file appears. Do NOT sleep-and-check manually. Do NOT ask the user if the job is done.

**When you receive the completion notification:**

| Exit code | Action |
|---|---|
| `0` | Status → `post_processing`. Invoke `superscientist:result-verification`. Execute continuation in Step 5. |
| non-zero | Status → `failed`. Read `stage-N/err` (if exists) and `{workflow_root}/dpdispatcher.log`. Invoke `superscientist:systematic-debugging`. |

**If the background wait times out or is lost** (no notification after 10 minutes):

1. Run a single check: `test -f stage-N/DPDISP_DONE && cat stage-N/DPDISP_EXIT_CODE || echo "NOT_DONE"`
2. If done → process the result (same as notification path above).
3. If not done → the job is long-running. Log: `[timestamp] stage-N: async job still running. Ending session for session-resume.` End session cleanly.
4. `session-resume` will pick up on next session start, check tmux state, and re-establish monitoring.

**Do NOT dispatch other stages while waiting.** Execution is sequential.

**→ After receiving notification, execute Step 5 immediately. Do not report to the user.**
```

- [ ] **Step 2: Verify the old poll protocol content is fully removed**

Read the file and confirm there is no remaining reference to `sleep 60`, `STATUS=DONE`, `STATUS=ALIVE`, or `STATUS=DEAD` in Step 4.

- [ ] **Step 3: Commit**

```bash
git add superscientist/skills/executing-workflows/SKILL.md
git commit -m "feat(superscientist): replace manual polling with blocking background wait"
```

---

### Task 5: Rewrite Step 5 as "Verify, Complete, and Continue"

**Files:**
- Modify: `superscientist/skills/executing-workflows/SKILL.md` (Step 5 section, lines 204-211)

- [ ] **Step 1: Replace the entire Step 5 section**

Replace from `### 5. Verify and Complete` through the Note about sync/async flow with:

```markdown
### 5. Verify, Complete, and Continue

Set status → `post_processing`. Log and persist. Then invoke `superscientist:result-verification`.

- **Passed:** Status → `completed`. Set `completed_at`. Log.
- **Failed:** Status → `failed`. Set `last_error`. Log. Invoke `superscientist:systematic-debugging`.

Note: For sync flow, `post_processing` is set here (the only place). For async flow, it is set after the background wait detects `DPDISP_DONE` with exit 0.

**→ CONTINUATION (mandatory, no pauses):**

After marking `completed`:
- Run dependency resolution (`pending` → `ready` for stages whose dependencies are now met)
- Any `ready` stages? → Return to Step 1 (Select Stage). Dispatch immediately.
- All stages `completed` or `skipped`? → Invoke `superscientist:workflow-completion`.
- No `ready`/`running` but uncompleted stages remain? → Workflow is blocked. Log and inform user.

After `systematic-debugging` applies a fix and transitions `failed` → `ready` (with `retry_count` incremented):
- Return to Step 1 (Select Stage). The retried stage is now `ready`.

After the background wait (Step 4) delivers a completion notification:
- Process the exit code per the table in Step 4. Then execute this same continuation block.

**There is no "report to user" step. The loop continues until a terminal condition is reached.**
```

- [ ] **Step 2: Remove the now-redundant Workflow Termination section**

The "Workflow Termination" section (starting with `## Workflow Termination`) is now covered by the continuation block in Step 5. Remove it entirely:

```markdown
## Workflow Termination

**Check after each stage completes and dependency resolution runs:**

- **All stages `completed` or `skipped`:** Invoke `superscientist:workflow-completion`.
- **No `ready` or `running` stages, but uncompleted stages remain:** Workflow is blocked. Log and inform the user which stages are blocked and why.
```

This content is now in the "After marking `completed`" bullet list in Step 5.

- [ ] **Step 3: Verify cross-references**

Read the file and confirm:
- No remaining references to "Step 5: Verify and Complete" (old name) — all should say "Step 5: Verify, Complete, and Continue" or just "Step 5"
- The Retry Flow section still correctly references Step 5 behavior
- The HPC Failure Diagnostics section's references are still valid

- [ ] **Step 4: Commit**

```bash
git add superscientist/skills/executing-workflows/SKILL.md
git commit -m "feat(superscientist): rewrite Step 5 with merged continuation protocol"
```

---

### Task 6: Add anti-stall Red Flags

**Files:**
- Modify: `superscientist/skills/executing-workflows/SKILL.md` (Red Flags table at the end)

- [ ] **Step 1: Add 7 new entries to the Red Flags table**

After the last existing Red Flag entry:

```
| "The subagent already ran the job, I just need to check outputs" | If compute-backend was not invoked, the stage is not complete. The job must be re-run through DPDispatcher. |
```

Add these entries:

```markdown
| "I've completed this stage, let me update the user" | Update progress.log. The user reads logs, not conversation. Continue. |
| "Let me show the user this result" | Log to progress.log and dispatch the next stage. |
| "I should check if the user wants to proceed" | The user approved the workflow plan. That approval covers all stages. Continue. |
| "Stage N is done, let me summarize" | Summarize in progress.log, not in conversation. Dispatch the next stage. |
| "The user might want to review before continuing" | If verification passed, the stage is done. The user reviews the final report. |
| "I'll wait for the user to acknowledge" | Acknowledgment is not a step in the execution loop. Continue. |
| "The background job just finished, let me tell the user" | Process the result. Update state. Continue the loop. The notification is for you, not the user. |
```

- [ ] **Step 2: Verify the table renders correctly**

Read the full Red Flags table and confirm all rows have consistent `|` formatting and no broken pipes.

- [ ] **Step 3: Commit**

```bash
git add superscientist/skills/executing-workflows/SKILL.md
git commit -m "feat(superscientist): add anti-stall red flags to executing-workflows"
```

---

### Task 7: Update checkpoint-management Poll Protocol

**Files:**
- Modify: `superscientist/skills/checkpoint-management/SKILL.md` (Poll Protocol section, lines 231-247)

- [ ] **Step 1: Replace the Poll Protocol section**

Replace from `### Poll Protocol` through the end of the code block (ending at the line before `### Quick Computations`) with:

```markdown
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
```

- [ ] **Step 2: Verify the section is consistent with executing-workflows Step 4**

Read both files and confirm the bash command template matches exactly between them.

- [ ] **Step 3: Commit**

```bash
git add superscientist/skills/checkpoint-management/SKILL.md
git commit -m "feat(superscientist): update checkpoint-management poll protocol for background wait"
```

---

### Task 8: Update session-resume Step 7

**Files:**
- Modify: `superscientist/skills/session-resume/SKILL.md` (Step 7, lines 65-72)

- [ ] **Step 1: Add monitoring re-establishment to Step 7**

After the existing Step 7 content ending with:

```
Resume work via `superscientist:executing-workflows`.
```

Add:

```markdown

**If a `running` stage was identified in Step 5 with tmux still alive**, re-establish background monitoring before dispatching any new stages:

```bash
# run_in_background: true, timeout: 600000
while [ ! -f "stage-N/DPDISP_DONE" ]; do sleep 30; done; cat stage-N/DPDISP_EXIT_CODE
```

The orchestrator will be auto-notified when the job completes, then resume via `superscientist:executing-workflows` Step 5 continuation.
```

- [ ] **Step 2: Verify the bash command matches the template in executing-workflows and checkpoint-management**

Read all three files and confirm the `while [ ! -f ... ]; do sleep 30; done; cat ...` command is identical across:
- `executing-workflows/SKILL.md` Step 4
- `checkpoint-management/SKILL.md` Poll Protocol
- `session-resume/SKILL.md` Step 7

- [ ] **Step 3: Commit**

```bash
git add superscientist/skills/session-resume/SKILL.md
git commit -m "feat(superscientist): add background monitoring re-establishment to session-resume"
```

---

### Task 9: Final cross-reference verification

**Files:**
- Read: `superscientist/skills/executing-workflows/SKILL.md`
- Read: `superscientist/skills/checkpoint-management/SKILL.md`
- Read: `superscientist/skills/session-resume/SKILL.md`

- [ ] **Step 1: Verify executing-workflows internal consistency**

Read the full file and check:
- The Autonomous Execution Law references "Step 5" — confirm Step 5 is now "Verify, Complete, and Continue"
- Step 3 inline reminder references "Step 4 (async) or Step 5 (sync)" — confirm both exist
- Step 4 references "Step 5" — confirm it exists with the continuation block
- Step 5 continuation references "Step 1 (Select Stage)" — confirm it exists
- Step 5 continuation references "Step 4" background wait — confirm it exists
- The Retry Flow section references are still valid
- The HPC Failure Diagnostics section references are still valid
- No orphaned references to old section names ("Verify and Complete", "Poll Protocol", "Workflow Termination")

- [ ] **Step 2: Verify cross-skill consistency**

Check that:
- `checkpoint-management` Poll Protocol says "blocking background wait" (matches executing-workflows Step 4)
- `session-resume` Step 7 says "re-establish background monitoring" (matches executing-workflows Step 4)
- The bash command template `while [ ! -f "stage-N/DPDISP_DONE" ]; do sleep 30; done; cat stage-N/DPDISP_EXIT_CODE` is identical in all three files
- `session-resume` references "executing-workflows Step 5 continuation" (correct name)

- [ ] **Step 3: Fix any issues found**

If any broken references, inconsistent names, or mismatched templates are found, fix them in the affected file(s).

- [ ] **Step 4: Final commit (if fixes were needed)**

```bash
git add superscientist/skills/
git commit -m "fix(superscientist): fix cross-references in skill files"
```
