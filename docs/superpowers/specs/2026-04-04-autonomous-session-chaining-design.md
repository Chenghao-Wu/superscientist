# Autonomous Session Chaining for Superscientist

**Objective:** Enable fully autonomous workflow execution across unlimited Claude Code sessions with zero human intervention, by adding a context budget mechanism and an external session-chaining wrapper.

**Problem:** The Superscientist harness is file-centric and cross-session by design, but session boundaries are manual. The orchestrator runs until context degrades, the user notices, starts a new session, and invokes session-resume. For multi-stage HPC workflows spanning hours or days, this human-in-the-loop restart is the bottleneck. Three failure modes compound the problem:

1. **Context decay within a session** — The orchestrator accumulates context across stage iterations (state reads, subagent returns, verification, retries). Auto-compaction fires unpredictably and lossy-summarizes skill instructions, causing behavioral drift (forgotten anti-stall rules, malformed state writes, incorrect status transitions).

2. **Manual handoff friction** — When context limits approach, the orchestrator logs "session ending" and stops. The user must manually start a new session and invoke session-resume. Each handoff costs 2-5 minutes and requires the user to be present.

3. **No context budget awareness** — The orchestrator cannot estimate its context consumption or make informed decisions about when to exit cleanly. It either waits for the system warning (too late — degradation has already occurred) or relies on subjective judgment (which the anti-stall rules explicitly forbid).

**Scope:** Two new components (session budget in `workflow-state.json`, external wrapper script) and minor changes to three existing skills (`executing-workflows`, `session-resume`, `workflow-planning`). No changes to `checkpoint-management`, `compute-backend`, `result-verification`, `systematic-debugging`, or `workflow-completion`. No changes to Claude Code itself.

## Design

### Component 1: Session Budget in `workflow-state.json`

A weighted stage counter that decides when the orchestrator should exit cleanly. Persisted in `workflow-state.json` under a new `session_config` field.

**Schema addition:**

```json
{
  "session_config": {
    "session_budget": 6,
    "session_id": "2026-04-04T03:15:00Z",
    "session_cost": 3.5,
    "exit_reason": null,
    "stage_weights": {
      "sync": 1,
      "async": 1.5,
      "error_cycle": 2,
      "diagnostic": 2
    }
  }
}
```

**Fields:**

- `session_budget` — Maximum weighted cost per session. Default: 6. Set during workflow-planning, tunable per workflow.
- `session_id` — ISO timestamp of the current session start. Written by session-resume on entry.
- `session_cost` — Cumulative weighted cost of stages completed in this session. Reset to 0 by session-resume. Incremented by executing-workflows after each stage.
- `exit_reason` — Why the last session ended. Values: `"budget_exhausted"`, `"completed"`, `"blocked"`, `null` (unclean exit / crash). Written by executing-workflows on exit.
- `stage_weights` — Weight assigned to each stage type. Determines how much budget a stage iteration consumes.

**Why a weighted stage counter, not token estimation:**

Claude cannot count its own tokens. Any token-based estimate requires tracking invisible overhead (tool framing, system messages, compaction summaries) and accumulates error across operations. A stage counter is:
- Observable: the user can inspect `session_cost` at any time
- Calibratable: run a few workflows, observe when context degrades, adjust `session_budget`
- Robust: no estimation drift, no maintenance when new operations are added
- Conservative by default: budget of 6 means ~4-6 stages per session for typical workflows

**Weight classification rules:**

The orchestrator classifies each completed stage iteration:
- `sync` — Local backend, no errors, completed in one attempt
- `async` — Remote/HPC backend or background wait, no errors
- `error_cycle` — Any stage that required at least one retry
- `diagnostic` — A diagnostic reproduction run (Level 2 HPC debugging)

If a stage has both async and error characteristics, use the higher weight (e.g., async stage with retry = `error_cycle` weight of 2, not `async` weight of 1.5).

**Decision logic in the execution loop:**

After each stage completion:
1. Classify the completed stage, look up its weight
2. Increment `session_cost` by the weight
3. Write updated `session_cost` to `workflow-state.json`
4. Estimate the next stage's weight (from its backend type; assume `sync` if local, `async` if remote)
5. If `session_cost + estimated_next_weight > session_budget` → clean exit
6. Otherwise → continue to next stage

**Bootstrap cost:** The default budget of 6 includes headroom for session bootstrap (skill loading, state reconstruction, init.sh, process checks). The budget check only counts stage iterations, and the ~30% headroom (budget threshold applied to context window) absorbs bootstrap overhead.

### Component 2: External Wrapper Script

A bash script that runs in tmux and chains Claude sessions until the workflow completes or blocks.

**`run-workflow.sh`:**

```bash
#!/bin/bash
set -euo pipefail

WORKFLOW_DIR="$(cd "${1:-.}" && pwd)"
STATE_FILE="$WORKFLOW_DIR/workflow-state.json"
LOG_FILE="$WORKFLOW_DIR/progress.log"
PAUSE_FILE="$WORKFLOW_DIR/PAUSE"
MAX_SESSIONS="${2:-20}"
MIN_SESSION_DURATION=60
MAX_RAPID_FAILURES=3
PAUSE_BETWEEN=15
SESSION_TIMEOUT=7200
SESSION_COUNT=0
RAPID_FAILURE_COUNT=0

log() { echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"; }

# ── Pre-flight ──────────────────────────────────────────────
preflight() {
    command -v claude >/dev/null 2>&1 || { log "ERROR: claude CLI not found in PATH"; exit 1; }
    command -v python3 >/dev/null 2>&1 || { log "ERROR: python3 not found"; exit 1; }
    [ -f "$STATE_FILE" ] || { log "ERROR: $STATE_FILE not found"; exit 1; }
    python3 -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null \
        || { log "ERROR: $STATE_FILE is invalid JSON"; exit 1; }
}

# ── Status check ────────────────────────────────────────────
get_status() {
    python3 -c "
import json, sys
try:
    with open('$STATE_FILE') as f:
        state = json.load(f)
except Exception:
    print('error:corrupt_state'); sys.exit(0)

if state.get('workflow_status') == 'completed':
    print('completed'); sys.exit(0)

stages = state.get('stages', [])
if not stages:
    print('error:no_stages'); sys.exit(0)

terminal = {'completed', 'skipped'}
if all(s['status'] in terminal for s in stages):
    print('all_stages_done'); sys.exit(0)

default_backend = state.get('default_backend', 'local')
for s in stages:
    if s['status'] == 'failed':
        backend = s.get('backend') or default_backend
        profiles = state.get('backend_profiles', {})
        is_remote = profiles.get(backend, {}).get('type') == 'remote'
        limit = 5 if is_remote else 3
        if s.get('retry_count', 0) >= limit:
            print('blocked:' + s['id']); sys.exit(0)

print('in_progress')
" 2>/dev/null || echo "error:parse_failed"
}

# ── Count completed stages ──────────────────────────────────
count_completed() {
    python3 -c "
import json
with open('$STATE_FILE') as f:
    state = json.load(f)
print(sum(1 for s in state.get('stages', []) if s['status'] == 'completed'))
" 2>/dev/null || echo "0"
}

# ── Main loop ───────────────────────────────────────────────
preflight
log "Autonomous workflow runner started (max_sessions=$MAX_SESSIONS)"

while true; do
    # Pause gate
    if [ -f "$PAUSE_FILE" ]; then
        log "PAUSED — remove $PAUSE_FILE to continue"
        while [ -f "$PAUSE_FILE" ]; do sleep 10; done
        log "Resumed"
    fi

    SESSION_COUNT=$((SESSION_COUNT + 1))
    if [ "$SESSION_COUNT" -gt "$MAX_SESSIONS" ]; then
        log "ERROR: Max sessions ($MAX_SESSIONS) exceeded — halting"
        exit 1
    fi

    STAGES_BEFORE=$(count_completed)
    SESSION_START=$(date +%s)
    log "Session $SESSION_COUNT starting (completed stages: $STAGES_BEFORE)"

    # Run Claude with session timeout
    ( cd "$WORKFLOW_DIR" && timeout "$SESSION_TIMEOUT" \
        claude -p "Resume the superscientist workflow." ) || true

    SESSION_END=$(date +%s)
    DURATION=$(( SESSION_END - SESSION_START ))
    STAGES_AFTER=$(count_completed)
    STAGES_DONE=$(( STAGES_AFTER - STAGES_BEFORE ))

    STATUS=$(get_status)
    log "Session $SESSION_COUNT ended: ${DURATION}s, +${STAGES_DONE} stages, status=$STATUS"

    # Rapid failure detection
    if [ "$DURATION" -lt "$MIN_SESSION_DURATION" ] && [ "$STAGES_DONE" -eq 0 ]; then
        RAPID_FAILURE_COUNT=$((RAPID_FAILURE_COUNT + 1))
        log "WARNING: Rapid exit with no progress ($RAPID_FAILURE_COUNT/$MAX_RAPID_FAILURES)"
        if [ "$RAPID_FAILURE_COUNT" -ge "$MAX_RAPID_FAILURES" ]; then
            log "ERROR: $MAX_RAPID_FAILURES consecutive rapid failures — halting"
            exit 1
        fi
    else
        RAPID_FAILURE_COUNT=0
    fi

    # Dispatch on status
    case "$STATUS" in
        completed|all_stages_done)
            log "Workflow completed after $SESSION_COUNT sessions"
            exit 0
            ;;
        blocked:*)
            log "Workflow blocked at ${STATUS#blocked:} — human intervention needed"
            exit 1
            ;;
        error:*)
            log "ERROR: $STATUS — halting"
            exit 1
            ;;
        in_progress)
            sleep "$PAUSE_BETWEEN"
            ;;
    esac
done
```

**Usage:**

```bash
# Start autonomous workflow runner in tmux
tmux new-session -d -s workflow "bash run-workflow.sh /path/to/workflow-dir"

# Monitor progress
tail -f /path/to/workflow-dir/progress.log

# Pause (clean intervention without killing anything)
touch /path/to/workflow-dir/PAUSE

# Resume
rm /path/to/workflow-dir/PAUSE
```

**Design decisions:**

- **`MAX_SESSIONS=20` safety cap.** Prevents infinite restart loops. A 6-stage workflow should complete in 1-3 sessions; 20 is generous for complex workflows with retries.
- **`SESSION_TIMEOUT=7200` (2 hours).** Safety net if Claude enters an infinite tool-call loop or stalls. Most sessions complete in minutes. This prevents the wrapper from hanging forever.
- **`|| true` after Claude invocation.** Claude may exit non-zero on context exhaustion. The wrapper doesn't care why it exited — it checks `workflow-state.json` for truth.
- **Rapid failure detection.** If a session runs < 60 seconds with 0 stage progress, something is fundamentally broken (missing permissions, broken environment, skill not found). Three consecutive rapid failures → halt instead of burning through MAX_SESSIONS.
- **`PAUSE` file gate.** Touch `PAUSE` in the workflow directory to freeze the loop. Remove to resume. Clean intervention without killing the wrapper or orphaning processes.
- **Progress tracking.** Completed stage count before/after each session, logged for budget calibration.
- **Status check reads `workflow-state.json`, not Claude's exit code.** The file is the single source of truth. Handles: explicit completion, all-stages-done (workflow_status not yet set), blocked (retries exhausted), corrupt state, in-progress.
- **Backend-aware retry limits.** Status check reads `backend_profiles` to determine 3 (local) vs 5 (remote) retry limit per stage.
- **15-second pause between sessions.** Prevents rapid-fire restarts. Long enough to be safe, short enough to not matter against HPC job runtimes.

### Component 3: Skill Changes

**3a. `executing-workflows` — Budget check in execution loop**

Add to the per-stage execution loop, after "update state" and before "continue to next stage":

```
After stage completion:
  1. Classify stage: sync | async | error_cycle | diagnostic
  2. Read session_config from workflow-state.json
  3. Increment session_cost by stage weight
  4. Write updated session_cost to workflow-state.json
  5. Estimate next stage weight (sync if local backend, async if remote)
  6. If session_cost + estimated_next_weight > session_budget:
       - Set exit_reason to "budget_exhausted"
       - Write to workflow-state.json
       - Log "[timestamp] Session ending: budget exhausted (cost=X, budget=Y)" to progress.log
       - Stop execution (do not dispatch next stage)
  7. Otherwise: continue to next stage
```

This replaces the current vague escape hatch ("ONLY when the system has explicitly warned about approaching context limits") with a concrete, deterministic decision. The Autonomous Execution Law remains intact — the orchestrator still runs without user gates between stages. Budget exhaustion is the only new exit condition.

**The anti-stall red flags table gets one new entry:**

| Thought | Reality |
|---|---|
| "I've been running for a while, maybe I should stop" | Check session_cost against session_budget. If under budget, continue. Your feelings about session length are not a valid exit condition. |

**3b. `session-resume` — Budget reset on entry**

Add to the session-resume protocol, after "Log and Resume" (step 7):

```
Step 8: Reset session budget
  - Read session_config from workflow-state.json
  - If exit_reason from previous session is not null, log it:
    "[timestamp] Previous session ended: exit_reason=budget_exhausted, cost=5.5/6"
  - Set session_id to current ISO timestamp
  - Set session_cost to 0
  - Set exit_reason to null
  - Write updated session_config to workflow-state.json
```

This ensures every session starts with a fresh budget. The previous session's exit_reason is logged before being cleared, preserving the audit trail in progress.log.

**3c. `workflow-planning` — Initialize session_config**

When workflow-planning creates `workflow-state.json`, include the `session_config` field with defaults:

```json
{
  "session_config": {
    "session_budget": 6,
    "session_id": null,
    "session_cost": 0,
    "exit_reason": null,
    "stage_weights": {
      "sync": 1,
      "async": 1.5,
      "error_cycle": 2,
      "diagnostic": 2
    }
  }
}
```

The user can adjust `session_budget` and `stage_weights` after planning and before starting the wrapper. Higher budget = fewer sessions, more context risk. Lower budget = more sessions, more restart overhead.

### Prerequisite: Permission Configuration

The wrapper runs `claude -p` which cannot answer interactive permission prompts. The project must have pre-approved permissions in `.claude/settings.json` or `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(cd:*)",
      "Bash(python3:*)",
      "Bash(lmp:*)",
      "Bash(tmux:*)",
      "Bash(conda:*)",
      "Bash(cat:*)",
      "Bash(timeout:*)",
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep",
      "Agent",
      "Skill"
    ]
  }
}
```

The exact permission list depends on the workflow's software requirements. This is a one-time setup before the first autonomous run.

**Open question:** Whether `claude -p` triggers session-start hooks. The `using-superscientist` hook bootstraps skill awareness. If hooks don't fire in `-p` mode, the resume prompt must explicitly invoke the skill: `"Invoke the session-resume skill for the superscientist workflow."` This must be verified during implementation.

## What This Design Does NOT Do

1. **No intra-session compaction.** The orchestrator does not invoke `/compact` or attempt to extend its own session. It runs until budget exhaustion, then dies cleanly. A fresh session is the most reliable form of context refresh.

2. **No changes to Claude Code itself.** Works within current CLI capabilities.

3. **No skill compression or cheatsheet.** Each session loads full skills normally via the Skill tool. The budget is conservative enough that skills remain in context for the duration of the session.

4. **No notification system.** The wrapper logs to `progress.log` and exits. Users can extend the wrapper script with notifications (email, Slack) if needed.

5. **No multi-workflow support.** One wrapper per workflow. Running two workflows requires two tmux sessions.

6. **No automatic budget calibration.** The default budget of 6 is empirical. Users tune it after observing session behavior. Session history (logged in progress.log) provides the data for calibration.

## Known Limitations

1. **Session budget is empirical.** The weighted stage counter is a heuristic, not a measurement. It may be too conservative (extra restarts) or too aggressive (hits compaction). Neither failure mode is catastrophic — extra restarts cost 2-5 minutes each, and compaction is recovered by the next session restart.

2. **`claude -p` + hooks is unverified.** Must be tested during implementation. Fallback: embed skill invocation in the prompt.

3. **Rapid failure heuristic has edge cases.** A session that legitimately completes a single fast stage in < 60 seconds would not trigger rapid failure detection (because `STAGES_DONE > 0`). But a session that runs init.sh for 50 seconds and exits before completing any stage would trigger the counter. The `STAGES_DONE == 0` condition mitigates most false positives.

4. **macOS/Linux only.** The wrapper uses tmux, bash, `date -Iseconds`, `timeout`. Windows would need a separate wrapper (consistent with existing platform split in superscientist hooks).

5. **No parallel stage dispatch.** The existing harness executes stages sequentially. This design doesn't change that. Parallel stages would need budget accounting for multiple in-flight stages.

## Summary

| Component | Location | Purpose |
|---|---|---|
| `session_config` in `workflow-state.json` | Workflow root | Budget tracking, session metadata, exit reason |
| Budget check in `executing-workflows` | Skill instructions | Deterministic exit decision at stage boundaries |
| Budget reset in `session-resume` | Skill instructions | Fresh budget per session, audit trail |
| `session_config` initialization in `workflow-planning` | Skill instructions | Default configuration at workflow creation |
| `run-workflow.sh` | Workflow root (or user tools) | External session chainer with safety mechanisms |
| Permission configuration | `.claude/settings.json` | Pre-approved tools for non-interactive mode |
