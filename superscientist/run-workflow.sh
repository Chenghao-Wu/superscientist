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

# -- macOS-compatible timeout ---------------------------------------------
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout"
else
    # Fallback: use perl alarm signal (available on all macOS)
    TIMEOUT_CMD="_perl_timeout"
    _perl_timeout() {
        local secs="$1"; shift
        perl -e 'alarm shift @ARGV; exec @ARGV' "$secs" "$@"
    }
fi

# -- Pre-flight ----------------------------------------------------------
preflight() {
    command -v claude >/dev/null 2>&1 || { log "ERROR: claude CLI not found in PATH"; exit 1; }
    command -v python3 >/dev/null 2>&1 || { log "ERROR: python3 not found"; exit 1; }
    [ -f "$STATE_FILE" ] || { log "ERROR: $STATE_FILE not found"; exit 1; }
    python3 -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null \
        || { log "ERROR: $STATE_FILE is invalid JSON"; exit 1; }
}

# -- Status check --------------------------------------------------------
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

# -- Count completed stages ----------------------------------------------
count_completed() {
    python3 -c "
import json
with open('$STATE_FILE') as f:
    state = json.load(f)
print(sum(1 for s in state.get('stages', []) if s['status'] == 'completed'))
" 2>/dev/null || echo "0"
}

# -- Main loop -----------------------------------------------------------
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
    ( cd "$WORKFLOW_DIR" && $TIMEOUT_CMD "$SESSION_TIMEOUT" \
        claude -p "Invoke the session-resume skill for the workflow in this directory. The workflow-state.json and progress.log are in the current directory." \
        --allowedTools "Bash(*) Read Write Edit Glob Grep Agent Skill" ) || true

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
