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

# Clean up per-session state and lock
rm -f "$STATE_FILE"
rm -rf "$LOCK_DIR"
# Also clean up stale files from dead processes
for f in "$STATE_DIR"/state_*.json; do
  pid=$(basename "$f" | sed 's/state_//;s/\.json//')
  [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null && rm -f "$f" && rm -rf "$STATE_DIR/.lock_$pid"
done
