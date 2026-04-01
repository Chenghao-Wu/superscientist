---
name: session-resume
description: Use when starting a new session and workflow-state.json exists in the working directory — recovers full context from checkpoint files before any new work
---

# Session Resume

## Overview

Every new session recovers state from files. No guessing. No assumptions.

**Core principle:** No new work until the resume protocol completes.

**Violating the letter of this rule is violating the spirit of this rule.**

## The Iron Law

```
NO NEW WORK UNTIL RESUME PROTOCOL COMPLETES
```

## The Resume Protocol

You MUST complete every step in order:

### Step 1: Read `workflow-state.json`

Understand the workflow structure: how many stages, what status each is in, what the dependencies are.

### Step 2: Read `progress.log` (tail)

Read the last 30-50 lines. Understand what happened in the last session: what was being worked on, where it stopped, any errors.

### Step 3: Read git log (recent)

`git log --oneline -10` — understand any file changes since last session.

### Step 4: Run `init.sh`

Verify the environment is functional. If it fails → invoke `superscientist:systematic-debugging`.

### Step 5: Check Running Processes

For each stage with status `running` or (`preparing` with `running_process` populated):

| Condition | Action |
|---|---|
| tmux session alive (`tmux has-session -t {session} 2>/dev/null`) | Leave as `running` (or update `preparing` → `running`), log "Stage N still running (tmux: {session})" |
| tmux gone + `DPDISP_DONE` exists + exit code 0 | Transition to `post_processing`, invoke `superscientist:result-verification` |
| tmux gone + `DPDISP_DONE` exists + exit code non-zero | Mark `failed`, set `last_error` from DPDispatcher logs |
| tmux gone + no `DPDISP_DONE` + `recovery_attempted: false` | Re-launch: `tmux kill-session -t {session} 2>/dev/null && tmux new-session -d -s {session} "bash {wrapper_script}"`. Set `recovery_attempted: true`. Log "Recovering stage-N: re-launching DPDispatcher" |
| tmux gone + no `DPDISP_DONE` + `recovery_attempted: true` | Mark `failed`: "DPDispatcher monitoring process died twice. Check system stability and tmux." |
| No `running_process` data | Mark `failed`: "stale from previous session, no process info" |

For stages with status `preparing` and no `running_process` → mark `failed` (subagent died mid-preparation).

### Step 6: Identify Next Action

Find the next actionable item:
1. First `ready` stage (dependencies met)
2. Or a `failed` stage eligible for retry
3. Or a `running` stage to continue monitoring
4. Or all stages `completed` → invoke `superscientist:workflow-completion`

### Step 7: Log and Resume

Append session start entry to `progress.log`:
```
[TIMESTAMP] Session N started. Reading workflow-state.json... [summary of state]
```

Resume work via `superscientist:executing-workflows`.

## Failure Handling

| Failure | Action |
|---|---|
| `init.sh` fails | Invoke `superscientist:systematic-debugging` |
| `workflow-state.json` missing or corrupted | Alert the user, do not proceed |
| `progress.log` missing | Create it with recovery note, proceed |

## Red Flags

| Thought | Reality |
|---------|---------|
| "I remember what we were doing" | Read the files. Memory lies. |
| "Let me just continue from here" | Complete the full protocol first. |
| "init.sh passed last time, skip it" | Environment changes. Run it. |
| "That tmux session is probably still running" | Check with `tmux has-session`. Don't assume. |
