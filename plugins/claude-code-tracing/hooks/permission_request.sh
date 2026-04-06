#!/bin/bash
# PermissionRequest - Create span for permission requests
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

log "permission_request input: $(echo "$input" | jq -c .)"

trace_id=$(resolve_trace_id)
[[ -z "$trace_id" ]] && exit 0

permission=$(echo "$input" | jq -r '.permission // empty' 2>/dev/null || echo "")
tool=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
tool_input=$(echo "$input" | jq -c '.tool_input // empty' 2>/dev/null || echo "")

agent_type=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null || echo "")
agent_id=$(echo "$input" | jq -r '.agent_id // empty' 2>/dev/null || echo "")

span_id=$(generate_span_id)
ts=$(get_timestamp_ms)
parent=$(resolve_parent_span_id "$agent_id" "$agent_type")

session_id=$(get_state "session_id")

user_id=$(get_state "user_id")

team_name=$(get_state "team_name")
determine_role "$agent_id" "$team_name"

attrs=$(jq -nc --arg sid "$session_id" --arg perm "$permission" --arg tool "$tool" --arg tinput "$tool_input" \
  --arg aid "$agent_id" --arg aname "$agent_type" --arg role "$_role" \
  --arg tn "$team_name" --arg uid "$user_id" \
  '{"session.id":$sid,"openinference.span.kind":"CHAIN","permission.type":$perm,"permission.tool":$tool,"input.value":$tinput}
   + (if $aid  != "" then {"agent.id":$aid,"agent.name":$aname,"agent.role":$role}
      elif $role == "lead" then {"agent.role":"lead"}
      else {} end)
   + (if $tn   != "" then {"team.name":$tn}  else {} end)
   + (if $uid  != "" then {"user.id":$uid}   else {} end)')

span=$(build_span "Permission Request" "CHAIN" "$span_id" "$trace_id" "$parent" "$ts" "$ts" "$attrs")
send_span "$span" || true
