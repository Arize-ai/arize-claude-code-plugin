#!/bin/bash
# Stop - Create trace span with input and output
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

session_id=$(get_state "session_id")
trace_id=$(get_state "current_trace_id")
[[ -z "$session_id" || -z "$trace_id" ]] && exit 0

trace_span_id=$(get_state "current_trace_span_id")
trace_start_time=$(get_state "current_trace_start_time")
user_prompt=$(get_state "current_trace_prompt")
project_name=$(get_state "project_name")
trace_count=$(get_state "trace_count")

transcript=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

_tn=$(get_state 'team_name')
if [[ -n "$_tn" ]]; then
  # Team still alive — defer Turn span until TeamDelete clears team_name.
  # Flush happens via close_active_turn in user_prompt_submit / session_end.
  [[ -n "$transcript" ]] && set_state "deferred_transcript" "$transcript"
  set_state "deferred_turn_end_time" "$(get_timestamp_ms)"
  log "Turn $trace_count: team active, deferring"
  exit 0
fi

_turn_tn=$(get_state 'turn_team_name')
[[ -n "$_turn_tn" ]] && _tn="$_turn_tn"

# Parse transcript for AI response and tokens
output="" model="" in_tokens=0 out_tokens=0

if [[ -f "$transcript" ]]; then
  start_line=$(get_state "trace_start_line")
  parse_transcript "$transcript" "${start_line:-0}"
  output="$_pt_all_text"
  model="$_pt_model"
  in_tokens=$_pt_in_tokens
  out_tokens=$_pt_out_tokens
fi

output=$(printf '%s' "$output" | head -c "10000")
[[ -z "$output" ]] && output="(No response)"

total_tokens=$((in_tokens + out_tokens))

output_messages=$(jq -nc --arg out "$output" '[{"message.role":"assistant","message.content":$out}]')

user_id=$(get_state "user_id")

attrs=$(jq -nc \
  --arg sid "$session_id" --arg num "$trace_count" --arg proj "$project_name" \
  --arg in "$user_prompt" --arg out "$output" --arg model "$model" \
  --arg uid "$user_id" --arg tn "$_tn" \
  --argjson in_tok "$in_tokens" --argjson out_tok "$out_tokens" --argjson total_tok "$total_tokens" \
  --argjson out_msgs "$output_messages" \
  '{"session.id":$sid,"trace.number":$num,"project.name":$proj,"openinference.span.kind":"AGENT","llm.model_name":$model,"llm.token_count.prompt":$in_tok,"llm.token_count.completion":$out_tok,"llm.token_count.total":$total_tok,"input.value":$in,"output.value":$out,"llm.output_messages":$out_msgs}
   + (if $uid != "" then {"user.id":$uid} else {} end)
   + (if $tn != "" then {"team.name":$tn} else {} end)')

span=$(build_span "Turn $trace_count" "AGENT" "$trace_span_id" "$trace_id" "" "$trace_start_time" "$(get_timestamp_ms)" "$attrs")
send_span "$span" || true

# Preserve for late-arriving teammate hooks (SubagentStop, TaskCompleted)
set_state "last_trace_id" "$trace_id"
set_state "last_trace_span_id" "$trace_span_id"

del_states current_trace_id current_trace_span_id current_trace_start_time current_trace_prompt turn_team_name \
  deferred_transcript deferred_turn_end_time
log "Turn $trace_count sent"

# Opportunistic GC for environments without SessionEnd (e.g., Python Agent SDK)
if [[ $((trace_count % 5)) -eq 0 ]]; then
  gc_stale_state_files
fi
