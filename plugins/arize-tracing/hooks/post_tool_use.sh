#!/bin/bash
# PostToolUse - Create tool span
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

session_id=$(get_state "session_id")
[[ -z "$session_id" ]] && exit 0

trace_id=$(get_state "current_trace_id")
parent_span_id=$(get_state "current_trace_span_id")
inc_state "tool_count"

tool_name=$(echo "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
tool_id=$(echo "$input" | jq -r '.tool_use_id // empty' 2>/dev/null || echo "")
tool_input=$(echo "$input" | jq -c '.tool_input // {}' 2>/dev/null | head -c 1000)
tool_output=$(echo "$input" | jq -r '.tool_output // empty' 2>/dev/null | head -c 1000)

start_time=$(get_state "tool_${tool_id}_start")
[[ -z "$start_time" ]] && start_time=$(get_timestamp_ms)
end_time=$(get_timestamp_ms)
del_state "tool_${tool_id}_start"

span_id=$(generate_uuid | tr -d '-' | cut -c1-16)

attrs=$(jq -n \
  --arg sid "$session_id" --arg tool "$tool_name" \
  --arg in "$tool_input" --arg out "$tool_output" \
  '{"session.id":$sid,"openinference.span.kind":"tool","tool.name":$tool,"input.value":$in,"output.value":$out}')

span=$(build_span "$tool_name" "TOOL" "$span_id" "$trace_id" "$parent_span_id" "$start_time" "$end_time" "$attrs")
send_span "$span" || true
