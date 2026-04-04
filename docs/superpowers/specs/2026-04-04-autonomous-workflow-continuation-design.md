# Autonomous Workflow Continuation

**Date:** 2026-04-04
**Status:** Approved

## Problem

The superscientist orchestrator has two failure modes that prevent fully autonomous multi-stage workflow execution:

1. **Stage boundary stall:** After completing a stage, the orchestrator reports results to the user and waits for "continue" instead of automatically dispatching the next ready stage. The user approved the workflow plan, but the orchestrator treats each stage boundary as an implicit approval gate.

2. **Polling death:** For async jobs (HPC or long-running local), the manual poll loop (sleep 60, check DPDISP_DONE, decide to re-poll) breaks down. Claude must make a conscious decision each iteration to continue polling, and it stalls instead.

Both stem from Claude's conversational nature: it completes a unit of work, reports, and waits. Skill instructions say "loop automatically," but Claude's default behavior overrides them.

## Approach

**Language strengthening** for the stage-boundary stall (behavioral problem) + **blocking background wait** for polling death (structural problem).

The two intentional user gates remain unchanged: experiment-design approval and amendment approval.

## Files Modified

| File | Change |
|---|---|
| `superscientist/skills/executing-workflows/SKILL.md` | Iron law, anti-stall red flags, merged continuation protocol, background wait |
| `superscientist/skills/checkpoint-management/SKILL.md` | Update Poll Protocol to reference blocking background wait |
| `superscientist/skills/session-resume/SKILL.md` | Re-establish background monitoring after resume |

No new files. No architectural changes. No changes to compute-backend, result-verification, systematic-debugging, or the 9-state status model.

## Design

### 1. Autonomous Execution Law

Added to `executing-workflows` immediately after Overview. Prescriptive (tells Claude what to do) and prohibitive (tells it what not to do), with a tightened escape hatch.

```markdown
## The Autonomous Execution Law

AFTER EACH STAGE, YOU MUST IMMEDIATELY EXECUTE THE CONTINUATION STEPS IN STEP 5.
THERE IS NO PAUSE POINT BETWEEN STAGES.

The user approved the workflow plan. That approval covers ALL stages. Do not ask for
re-confirmation between stages. Do not report intermediate results in conversation.
Do not summarize what just happened. Log to progress.log and continue.

The ONLY reasons to pause and inform the user:
1. Retry limit exceeded (3 local / 5 remote)
2. Workflow blocked (no ready/running stages, uncompleted stages remain)
3. Amendment needed (definitional field change requires user approval)
4. Context limit — ONLY when the system has explicitly warned about approaching
   context limits. "The conversation feels long" is NOT a valid reason.
```

**Rationale:** Iron laws in session-resume and result-verification work because they govern bounded actions. The execution loop spans many tool calls, so the law must be prescriptive ("you MUST immediately execute continuation") not just prohibitive ("don't stop"). The context-limit exception is tightened to prevent rationalization — only system warnings count, not subjective judgment.

### 2. Anti-Stall Red Flags

Added to the existing Red Flags table in `executing-workflows`. Targets specific rationalizations Claude uses before stalling, including the async notification trigger (which the original table missed).

| Thought | Reality |
|---|---|
| "I've completed this stage, let me update the user" | Update progress.log. The user reads logs, not conversation. Continue. |
| "Let me show the user this result" | Log to progress.log and dispatch the next stage. |
| "I should check if the user wants to proceed" | The user approved the workflow plan. That approval covers all stages. Continue. |
| "Stage N is done, let me summarize" | Summarize in progress.log, not in conversation. Dispatch the next stage. |
| "The user might want to review before continuing" | If verification passed, the stage is done. The user reviews the final report. |
| "I'll wait for the user to acknowledge" | Acknowledgment is not a step in the execution loop. Continue. |
| "The background job just finished, let me tell the user" | Process the result. Update state. Continue the loop. The notification is for you, not the user. |

**Rationale:** Red flags are at the bottom of the skill (reference table, not active instruction). They prevent the behavior the first time Claude encounters it. The most common rationalization is "let me update the user on what happened" — framed as helpfulness, not waiting. The async notification case is a distinct trigger point that needs its own entry.

### 3. Continuation Merged Into Step 5 + Inline Reminders

Instead of a separate Post-Stage Continuation section (which creates a section boundary where Claude stalls), merge continuation logic into the end of Step 5 and add inline reminders at other decision points.

**Why merged, not separate:** The stall happens at section boundaries. Claude finishes Step 5 (Verify and Complete), sees the section end, and concludes "I'm done with this unit of work." Placing continuation inside Step 5 eliminates the boundary.

**Inline reminders at decision points:**

At the end of Step 3 (Process Subagent Result):
```
-> Continue to Step 4 (async) or Step 5 (sync). Do not report to the user.
```

At the end of dependency resolution:
```
-> After resolving dependencies, return to stage selection. Do not pause.
```

**Step 5 rewritten as "Verify, Complete, and Continue":**

```markdown
### 5. Verify, Complete, and Continue

Set status -> post_processing. Log and persist. Invoke result-verification.

- Passed: Status -> completed. Set completed_at. Log.
- Failed: Status -> failed. Set last_error. Log. Invoke systematic-debugging.

CONTINUATION (mandatory, no pauses):

After marking completed:
- Run dependency resolution (pending -> ready for stages whose dependencies are now met)
- Any ready stages? -> Return to Step 1 (Select Stage). Dispatch immediately.
- All stages completed or skipped? -> Invoke workflow-completion.
- No ready/running but uncompleted stages remain? -> Workflow is blocked. Log and inform user.

After systematic-debugging applies a fix and transitions failed -> ready (with retry_count incremented):
- Return to Step 1 (Select Stage). The retried stage is now ready.

After the background wait (Step 4) delivers a completion notification:
- Process the exit code per the table in Step 4. Then execute this same continuation block.

There is no "report to user" step. The loop continues until a terminal condition is reached.
```

**Rationale:** Uses bullets instead of numbered steps to avoid collision with Per-Stage Execution step numbers. Covers three entry points into continuation (completed, retry, async notification). Explicitly includes the retry loop-back path that was missing.

### 4. Replace Polling with Blocking Background Wait

Replace the manual poll loop in `executing-workflows` Step 4 with a `run_in_background` Bash command. Update `checkpoint-management` and `session-resume` to match.

**Why:** The manual poll loop requires Claude to make a conscious decision each iteration (run poll command -> interpret result -> decide to re-poll). This is the exact decision point where Claude stalls. Moving the loop into a bash process eliminates Claude from the loop — it launches once and gets auto-notified on completion.

**In `executing-workflows`, Step 4 replaced:**

```markdown
### 4. Monitor Background Process (async only)

DO NOT poll manually in a loop. Use a blocking background wait:

    # run_in_background: true, timeout: 600000
    while [ ! -f "stage-N/DPDISP_DONE" ]; do sleep 30; done; cat stage-N/DPDISP_EXIT_CODE

You will be auto-notified when the file appears. Do NOT sleep-and-check manually.
Do NOT ask the user if the job is done.

When you receive the completion notification:

| Exit code | Action |
|---|---|
| 0 | Status -> post_processing. Invoke result-verification. Execute continuation in Step 5. |
| non-zero | Status -> failed. Read stage-N/err and dpdispatcher.log. Invoke systematic-debugging. |

If the background wait times out or is lost (no notification after 10 minutes):

1. Run a single check: test -f stage-N/DPDISP_DONE && cat stage-N/DPDISP_EXIT_CODE || echo "NOT_DONE"
2. If done -> process the result (same as notification path above).
3. If not done -> the job is long-running. Log: "[timestamp] stage-N: async job still running.
   Ending session for session-resume." End session cleanly.
4. session-resume will pick up on next session start, check tmux state, and re-establish monitoring.

Do NOT dispatch other stages while waiting. Execution is sequential.
```

**In `checkpoint-management`, Poll Protocol updated:**

```markdown
### Poll Protocol

The orchestrator monitors async processes using a blocking background wait, not a manual poll loop:

    # run_in_background: true, timeout: 600000
    while [ ! -f "stage-N/DPDISP_DONE" ]; do sleep 30; done; cat stage-N/DPDISP_EXIT_CODE

The orchestrator is auto-notified on completion. Decision logic on notification:

    if DPDISP_DONE marker exists:
      read DPDISP_EXIT_CODE
      if 0: transition to post_processing
      else: transition to failed

If the background wait is lost (session boundary), session-resume Step 5 handles recovery:
- tmux alive -> re-establish background monitoring
- tmux gone + DPDISP_DONE -> process result immediately
- tmux gone + no DPDISP_DONE + recovery_attempted false -> re-launch, re-monitor
- tmux gone + no DPDISP_DONE + recovery_attempted true -> mark failed
```

**In `session-resume`, addition to Step 7:**

```markdown
If a running stage was identified in Step 5 with tmux still alive,
re-establish background monitoring before dispatching any new stages:

    # run_in_background: true, timeout: 600000
    while [ ! -f "stage-N/DPDISP_DONE" ]; do sleep 30; done; cat stage-N/DPDISP_EXIT_CODE
```

**Rationale:** The Bash tool `run_in_background` is designed for long-running processes. The max explicit timeout is 600000ms (10 minutes). For HPC jobs exceeding 10 minutes, the fallback path (single check -> end session -> session-resume) naturally spans sessions. Each session-resume re-establishes a 10-minute monitoring window. Parallel dispatch while waiting is excluded to preserve the sequential execution principle.

## What This Does NOT Change

- **Experiment-design approval gate** — intentional, stays
- **Amendment approval gate** — intentional, stays
- **compute-backend skill** — already launches tmux correctly, no changes
- **result-verification skill** — no changes
- **systematic-debugging skill** — no changes
- **9-state status model** — no changes
- **Retry limits** (3 local / 5 remote) — no changes
- **Session-resume Steps 1-6** — no changes (only Step 7 gets monitoring addition)
- **DPDispatcher integration** — no changes

## Validation

Two-phase validation: local test for stage-boundary stall (Problem A), then HPC test for polling death (Problem D).

### Phase 1: Local 6-Stage Test (Problem A)

Bead-spring polymer equilibration quality workflow. N=50 Kremer-Grest chain, 6 stages, all sync on local backend. Total runtime ~25 seconds.

| Stage | Name | Type | Runtime | Success Criteria |
|---|---|---|---|---|
| 1 | Structure generation | AutoPoly (sync) | ~5s | N50.data exists, 50 atoms, 49 bonds, max bond < 1.35 sigma |
| 2 | Energy minimization | LAMMPS CG (sync) | ~2s | Energy converged (etol < 1e-6), minimized.restart produced |
| 3 | NVT equilibration | LAMMPS 500k steps (sync) | ~3s | T within 1.0 +/- 0.1, no lost atoms, equil.restart produced |
| 4 | Equilibration validation | Python analysis (sync) | ~2s | Parse thermo: T_mean, T_std, PE drift < 5% over last half. Output: equil_check.json |
| 5 | NVT production | LAMMPS 2M steps (sync) | ~7s | 100+ R_g samples, no lost atoms, rg_timeseries.dat produced |
| 6 | R_g analysis + plot | Python/matplotlib (sync) | ~3s | Mean R_g, SEM, N_eff, autocorrelation computed. rg_plot.png + rg_statistics.json produced |

**Dependency chain:** 1 → 2 → 3 → 4 → 5 → 6 (linear)

**Pass criteria:**
1. All 6 stages complete without user input (5 stage-boundary transitions)
2. Orchestrator invokes workflow-completion after stage-6 without user input
3. progress.log shows continuous execution — no gaps between stages, no "waiting for user" entries
4. All success criteria met per workflow-state.json

### Phase 2: HPC 6-Stage Test (Problem D)

Same 6-stage workflow on HPC backend (Slurm, gpu4090 partition). Stages 3 and 5 dispatch via DPDispatcher to remote, triggering async mode with background wait.

| Stage | Mode | Tests |
|---|---|---|
| 1 | Local sync | sync → sync boundary |
| 2 | Local sync | sync → async transition (next stage is remote) |
| 3 | Remote async | Background wait → notification → continuation |
| 4 | Local sync | Post-async → sync boundary |
| 5 | Remote async | Background wait → notification → continuation |
| 6 | Local sync | Post-async → workflow-completion |

**Pass criteria:**
1. All 6 stages complete without user input
2. Stages 3 and 5 use blocking background wait (not manual poll loop)
3. After background wait notification, orchestrator immediately proceeds to verification and next stage
4. If background wait times out (job > 10 min), orchestrator ends session cleanly and session-resume picks up
5. progress.log shows continuous execution across sync/async boundaries
