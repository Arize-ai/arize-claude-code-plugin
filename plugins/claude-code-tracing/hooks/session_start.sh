#!/bin/bash
# SessionStart - Initialize session state
source "$(dirname "$0")/common.sh"

check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"
# Reset state for fresh session
_lock_state
echo '{}' > "$STATE_FILE"
_unlock_state
ensure_session_initialized "$input"

log "Session started: $(get_state 'session_id')"
