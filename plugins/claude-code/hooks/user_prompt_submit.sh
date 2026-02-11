#!/bin/bash
# UserPromptSubmit - Store state for trace (span created at Stop)
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

session_id=$(get_state "session_id")
if [[ -z "$session_id" ]]; then
  log_always "WARNING: No session_id in state — SessionStart may not have fired"
  exit 0
fi

inc_state "trace_count"

# Generate trace IDs now, create span at Stop (so it has output)
set_state "current_trace_id" "$(generate_uuid | tr -d '-')"
set_state "current_trace_span_id" "$(generate_uuid | tr -d '-' | cut -c1-16)"
set_state "current_trace_start_time" "$(get_timestamp_ms)"
set_state "current_trace_prompt" "$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null | head -c 1000)"

# Track transcript position for parsing AI response later
transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
if [[ -n "$transcript" && -f "$transcript" ]]; then
  set_state "trace_start_line" "$(wc -l < "$transcript" | tr -d ' ')"
else
  set_state "trace_start_line" "0"
fi
