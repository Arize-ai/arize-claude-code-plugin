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

# Clean up this session's state
rm -f "$STATE_FILE" 2>/dev/null || true

# Clean up stale state files for PIDs that are no longer running
for f in "${STATE_DIR}"/state_*.json; do
  [[ -f "$f" ]] || continue
  local_pid=$(basename "$f" | sed 's/state_//;s/\.json//')
  if [[ "$local_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$local_pid" 2>/dev/null; then
    rm -f "$f"
  fi
done
