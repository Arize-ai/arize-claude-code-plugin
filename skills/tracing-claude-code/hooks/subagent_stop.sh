#!/bin/bash
# SubagentStop - Create span for subagent completion
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat)

trace_id=$(get_state "current_trace_id")
[[ -z "$trace_id" ]] && exit 0

session_id=$(get_state "session_id")
agent_id=$(echo "$input" | jq -r '.agent_id // empty')
agent_type=$(echo "$input" | jq -r '.agent_type // "unknown"')

span_id=$(generate_uuid | tr -d '-' | cut -c1-16)
ts=$(get_timestamp_ms)
parent=$(get_state "current_trace_span_id")

attrs=$(jq -n \
  --arg sid "$session_id" \
  --arg agent_id "$agent_id" \
  --arg agent_type "$agent_type" \
  '{"session.id":$sid,"openinference.span.kind":"chain","subagent.id":$agent_id,"subagent.type":$agent_type}')

span=$(build_span "Subagent: $agent_type" "CHAIN" "$span_id" "$trace_id" "$parent" "$ts" "$ts" "$attrs")
send_span "$span" || true
