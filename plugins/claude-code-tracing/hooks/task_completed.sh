#!/bin/bash
# TaskCompleted - Cache teammate_name and create span if active trace
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

# Cache teammate_name for subsequent spans
teammate_name=$(echo "$input" | jq -r '.teammate_name // empty' 2>/dev/null || echo "")
[[ -n "$teammate_name" ]] && set_state "team_agent_name" "$teammate_name"

# Only create span if there's an active trace (may fire after Stop cleared state)
trace_id=$(get_state "current_trace_id")
[[ -z "$trace_id" ]] && exit 0

session_id=$(get_state "session_id")
parent=$(get_state "current_trace_span_id")
span_id=$(generate_uuid | tr -d '-' | cut -c1-16)
end_time=$(get_timestamp_ms)

task_id=$(echo "$input" | jq -r '.task_id // empty' 2>/dev/null || echo "")
task_subject=$(echo "$input" | jq -r '.task_subject // empty' 2>/dev/null || echo "")
task_description=$(echo "$input" | jq -r '.task_description // empty' 2>/dev/null || echo "")

span_name="Task: ${task_subject:-completed}"

attrs=$(jq -nc \
  --arg sid "$session_id" \
  --arg task_id "$task_id" \
  --arg task_subject "$task_subject" \
  --arg task_desc "$task_description" \
  --arg teammate "$teammate_name" \
  '{"session.id":$sid,"openinference.span.kind":"chain","task.id":$task_id,"task.subject":$task_subject,"task.description":$task_desc} + (if $teammate != "" then {"teammate.name":$teammate} else {} end)')

span=$(build_span "$span_name" "CHAIN" "$span_id" "$trace_id" "$parent" "$end_time" "$end_time" "$attrs")
send_span "$span" || true
