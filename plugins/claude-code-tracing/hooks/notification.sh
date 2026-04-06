#!/bin/bash
# Notification - Create span for system notifications
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

trace_id=$(resolve_trace_id)
[[ -z "$trace_id" ]] && exit 0

session_id=$(get_state "session_id")
message=$(echo "$input" | jq -r '.message // empty' 2>/dev/null || echo "")
title=$(echo "$input" | jq -r '.title // empty' 2>/dev/null || echo "")
notif_type=$(echo "$input" | jq -r '.notification_type // "info"' 2>/dev/null)
[[ "$notif_type" == "idle_prompt" ]] && exit 0

agent_type=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null || echo "")
agent_id=$(echo "$input" | jq -r '.agent_id // empty' 2>/dev/null || echo "")

span_id=$(generate_span_id)
ts=$(get_timestamp_ms)
parent=$(resolve_parent_span_id "$agent_id" "$agent_type")

team_name=$(get_state "team_name")
determine_role "$agent_id" "$team_name"

user_id=$(get_state "user_id")

attrs=$(jq -nc \
  --arg sid "$session_id" \
  --arg msg "$message" \
  --arg title "$title" \
  --arg type "$notif_type" \
  --arg aid "$agent_id" --arg aname "$agent_type" --arg role "$_role" \
  --arg tn "$team_name" \
  --arg uid "$user_id" \
  '{"session.id":$sid,"openinference.span.kind":"CHAIN","notification.message":$msg,"notification.title":$title,"notification.type":$type,"input.value":$msg}
   + (if $aid  != "" then {"agent.id":$aid,"agent.name":$aname,"agent.role":$role}
      elif $role == "lead" then {"agent.role":"lead"}
      else {} end)
   + (if $tn   != "" then {"team.name":$tn}  else {} end)
   + (if $uid  != "" then {"user.id":$uid}   else {} end)')

span=$(build_span "Notification: $notif_type" "CHAIN" "$span_id" "$trace_id" "$parent" "$ts" "$ts" "$attrs")
send_span "$span" || true
