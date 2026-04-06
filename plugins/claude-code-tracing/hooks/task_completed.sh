#!/bin/bash
# TaskCompleted - Create span for task completion with team context
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

trace_id=$(resolve_trace_id)
[[ -z "$trace_id" ]] && exit 0

session_id=$(get_state "session_id")
[[ -z "$session_id" ]] && exit 0

team_name=$(echo "$input" | jq -r '.team_name // empty' 2>/dev/null || echo "")
teammate_name=$(echo "$input" | jq -r '.teammate_name // empty' 2>/dev/null || echo "")
agent_id=$(echo "$input" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
agent_type=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null || echo "")
task_id=$(echo "$input" | jq -r '.task_id // empty' 2>/dev/null || echo "")
task_subject=$(echo "$input" | jq -r '.task_subject // empty' 2>/dev/null || echo "")
task_description=$(echo "$input" | jq -r '.task_description // empty' 2>/dev/null | head -c 5000)

[[ -n "$team_name" ]] && set_state "team_name" "$team_name"

# Dedup: keep teammate's span, skip lead's duplicate
check_team_dedup "$task_id" "tc_seen" "$agent_id" || exit 0

span_id=$(generate_span_id)
end_time=$(get_timestamp_ms)
# Nest under agent grouping span if available
parent=$(resolve_parent_span_id "$agent_id" "${agent_type:-$teammate_name}")

input_val="${task_description:-$task_subject}"
user_id=$(get_state "user_id")
attrs=$(jq -nc \
  --arg sid "$session_id" \
  --arg tn "$team_name" --arg tmate "$teammate_name" \
  --arg tid "$task_id" --arg tsubj "$task_subject" \
  --arg tdesc "$task_description" --arg inval "$input_val" \
  --arg uid "$user_id" \
  '{"session.id":$sid,"openinference.span.kind":"CHAIN"}
   + (if $tn    != "" then {"team.name":$tn}                            else {} end)
   + (if $tmate != "" then {"agent.name":$tmate,"agent.role":"teammate"} else {} end)
   + (if $tid   != "" then {"task.id":$tid}                              else {} end)
   + (if $tsubj != "" then {"task.subject":$tsubj}                       else {} end)
   + (if $tdesc != "" then {"task.description":$tdesc}                   else {} end)
   + (if $inval != "" then {"input.value":$inval}                        else {} end)
   + (if $uid   != "" then {"user.id":$uid}                              else {} end)')

span_name="Task Completed"
[[ -n "$task_subject" ]] && span_name="Task Completed: $task_subject"

span=$(build_span "$span_name" "CHAIN" "$span_id" "$trace_id" "$parent" "$end_time" "$end_time" "$attrs")
send_span "$span" || true
