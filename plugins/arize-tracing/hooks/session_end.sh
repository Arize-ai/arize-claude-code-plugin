#!/bin/bash
# SessionEnd - Print summary and clean up
source "$(dirname "$0")/common.sh"

check_requirements

session_id=$(get_state "session_id")
[[ -z "$session_id" ]] && exit 0

trace_count=$(get_state "trace_count")
tool_count=$(get_state "tool_count")

log_always "Session complete: ${trace_count:-0} traces, ${tool_count:-0} tools"
log_always "View in Arize/Phoenix: session.id = $session_id"

# Clean up state
echo '{}' > "$STATE_FILE"
