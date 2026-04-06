#!/bin/bash
# UserPromptSubmit - Store state for trace (span created at Stop)
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

# Lazy init: if SessionStart never fired (e.g., Python Agent SDK), initialize now
ensure_session_initialized "$input"

session_id=$(get_state "session_id")

transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

# Close any active turn from a prior prompt (team in-progress or orphaned)
close_active_turn "$transcript"

del_states last_trace_id last_trace_span_id

inc_state "trace_count"

# Generate trace IDs now, create span at Stop (so it has output)
set_state "current_trace_id" "$(generate_trace_id)"
set_state "current_trace_span_id" "$(generate_span_id)"
set_state "current_trace_start_time" "$(get_timestamp_ms)"
set_state "current_trace_prompt" "$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null | head -c 10000)"

# Track transcript position for parsing AI response later
if [[ -n "$transcript" && -f "$transcript" ]]; then
  set_state "trace_start_line" "$(wc -l < "$transcript" | tr -d ' ')"
else
  set_state "trace_start_line" "0"
fi
