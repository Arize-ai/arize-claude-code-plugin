#!/bin/bash
# PostToolUse - Create tool span
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

IFS=$'\x1f' read -r _input_sid tool_name tool_id agent_id agent_type < <(
  echo "$input" | jq -r '[.session_id // "", .tool_name // "unknown", .tool_use_id // "", .agent_id // "", .agent_type // ""] | join("\u001f")' 2>/dev/null
)

resolve_session "$input" "$_input_sid"

tool_input_raw=$(echo "$input" | jq -c '.tool_input // {}' 2>/dev/null || echo '{}')
tool_input=$(echo "$tool_input_raw" | head -c 5000)
raw_response=$(echo "$input" | jq -r '.tool_response // empty' 2>/dev/null || echo "")
tool_response=$(echo "$raw_response" | head -c 5000)

IFS=$'\x1f' read -r session_id _s_trace_id _s_last_trace_id \
  _s_trace_span_id _s_last_trace_span_id \
  _s_team_name user_id _s_tool_start < <(
  jq -r --arg tk "tool_${tool_id}_start" '[
    (.session_id // ""), (.current_trace_id // ""), (.last_trace_id // ""),
    (.current_trace_span_id // ""), (.last_trace_span_id // ""),
    (.team_name // ""), (.user_id // ""), (.[$tk] // "")
  ] | join("\u001f")' "$STATE_FILE" 2>/dev/null
)

[[ -z "$session_id" ]] && exit 0

trace_id="$_s_trace_id"
[[ -z "$trace_id" ]] && trace_id="$_s_last_trace_id"
[[ -z "$trace_id" ]] && exit 0

parent_span_id="$_s_trace_span_id"
[[ -z "$parent_span_id" ]] && parent_span_id="$_s_last_trace_span_id"

# team_name_check: frozen at read time for dedup/role checks.
# team_name: may be mutated below by TeamCreate/TeamDelete handling.
team_name_check="$_s_team_name"
team_name="$_s_team_name"

start_time="$_s_tool_start"
[[ -z "$start_time" ]] && start_time=$(get_timestamp_ms)

inc_state "tool_count"

# Track whether content was truncated
truncated="false"
[[ ${#tool_input_raw} -gt 5000 || ${#raw_response} -gt 5000 ]] && truncated="true"

IFS=$'\x1f' read -r _f_command _f_file_path _f_url _f_query _f_pattern _f_path \
  _f_description _f_to _f_message_str _f_name _f_task_subject _f_is_shutdown < <(
  echo "$tool_input_raw" | jq -r '[
    (.command // ""), (.file_path // .pattern // ""), (.url // ""),
    (.query // ""), (.pattern // ""), (.path // ""),
    (.description // ""), (.to // ""),
    ((.message // "") | if type == "string" then . else "" end),
    (.name // ""), (.task_subject // ""),
    (if (.message | type) == "object" then (.message.type // "") else "" end)
  ] | join("\u001f")' 2>/dev/null
)

tool_description=""
tool_command=""
tool_file_path=""
tool_url=""
tool_query=""

case "$tool_name" in
  Bash)
    tool_command="$_f_command"
    tool_description=$(echo "$tool_command" | head -c 200)
    ;;
  Read|Write|Edit|Glob)
    tool_file_path="$_f_file_path"
    tool_description=$(echo "$tool_file_path" | head -c 200)
    ;;
  WebSearch|ToolSearch)
    tool_query="$_f_query"
    tool_description=$(echo "$tool_query" | head -c 200)
    ;;
  WebFetch)
    tool_url="$_f_url"
    tool_description=$(echo "$tool_url" | head -c 200)
    ;;
  Grep)
    tool_query="$_f_pattern"
    tool_file_path="$_f_path"
    tool_description="grep: $(echo "$tool_query" | head -c 100)"
    ;;
  Agent)
    tool_description=$(echo "$_f_description" | head -c 200)
    ;;
  SendMessage)
    tool_description=$(echo "$_f_to" | head -c 200)
    sm_msg="$_f_message_str"
    [[ -n "$sm_msg" ]] && tool_input=$(printf 'to: %s\n%s' "$tool_description" "$sm_msg" | head -c 5000)
    ;;
  TaskCreate|TaskUpdate)
    tool_description=$(echo "$_f_task_subject" | head -c 200)
    ;;
  *)
    tool_description=$(echo "$tool_input" | head -c 200)
    [[ "$tool_description" == "{}" ]] && tool_description=""
    ;;
esac

is_shutdown="$_f_is_shutdown"

end_time=$(get_timestamp_ms)
del_state "tool_${tool_id}_start"

span_id=$(generate_span_id)

# Dedup: keep teammate's span, skip lead's duplicate
check_team_dedup "$tool_id" "seen_tool" "$agent_id" "$team_name_check" || exit 0

# Agent grouping: lazy-init an AGENT span for this agent's work period.
# Works for both subagents and teammates — keyed on agent_id (unique per instance).
if [[ -n "$agent_id" && -n "$agent_type" && "$agent_type" != "unknown" && "$agent_type" != "null" && "$is_shutdown" != "shutdown_response" ]]; then
  agent_parent=$(get_or_set_state "agent_${agent_id}_span_id" "$(generate_span_id)")
  if [[ "$(get_state "agent_${agent_id}_start_time")" == "" ]]; then
    set_state "agent_${agent_id}_start_time" "$start_time"
    set_state "active_agent_${agent_type}" "$agent_id"
  fi
  parent_span_id="$agent_parent"
elif [[ "$is_shutdown" == "shutdown_response" && -n "$agent_id" ]]; then
  shutdown_parent=$(get_state "agent_${agent_id}_span_id")
  [[ -z "$shutdown_parent" ]] && shutdown_parent=$(generate_span_id)
  shutdown_turn_parent="$parent_span_id"
  parent_span_id="$shutdown_parent"
fi

if [[ "$tool_name" == "TeamCreate" ]]; then
  team_from_response=$(echo "$raw_response" | jq -r '.team_name // empty' 2>/dev/null || echo "")
  if [[ -n "$team_from_response" ]]; then
    set_state "team_name" "$team_from_response"
    team_name="$team_from_response"
  fi
fi

# Race fix: preemptively mark agents active on the lead side so Stop
# sees active_agent_* > 0 before the worker's first tool fires.
if [[ -z "$agent_id" && -n "$team_name_check" ]]; then
  if [[ "$tool_name" == "Agent" ]]; then
    [[ -n "$_f_name" ]] && set_state "active_agent_${_f_name}" "spawning"
  elif [[ "$tool_name" == "SendMessage" ]]; then
    [[ -n "$_f_to" ]] && set_state "active_agent_${_f_to}" "waking"
  fi
fi

if [[ "$tool_name" == "TeamDelete" ]]; then
  # Only clean state if deletion succeeded — failed deletes keep the team active
  if [[ "$raw_response" != *"active member"* ]]; then
    set_state "turn_team_name" "$team_name"
    clean_team_state
    del_state "team_name"
    team_name=""
  else
    log "TeamDelete blocked (active members) — keeping team state"
  fi
fi

determine_role "$agent_id" "$team_name_check"

attrs=$(jq -nc \
  --arg sid "$session_id" --arg tool "$tool_name" \
  --arg in "$tool_input" --arg out "$tool_response" \
  --arg desc "$tool_description" --arg trunc "$truncated" \
  --arg cmd "$tool_command" --arg fpath "$tool_file_path" \
  --arg url "$tool_url" --arg query "$tool_query" \
  --arg aid "$agent_id" --arg aname "$agent_type" --arg role "$_role" \
  --arg tn "$team_name" \
  --arg uid "$user_id" \
  '{"session.id":$sid,"openinference.span.kind":"TOOL","tool.name":$tool,"input.value":$in,"output.value":$out,"tool.description":$desc,"tool.truncated":$trunc}
   + (if $cmd   != "" then {"tool.command":$cmd}     else {} end)
   + (if $fpath != "" then {"tool.file_path":$fpath}  else {} end)
   + (if $url   != "" then {"tool.url":$url}          else {} end)
   + (if $query != "" then {"tool.query":$query}       else {} end)
   + (if $aid   != "" then {"agent.id":$aid,"agent.name":$aname,"agent.role":$role}
      elif $role == "lead" then {"agent.role":"lead"}
      else {} end)
   + (if $tn    != "" then {"team.name":$tn}           else {} end)
   + (if $uid   != "" then {"user.id":$uid}            else {} end)')

span=$(build_span "$tool_name" "TOOL" "$span_id" "$trace_id" "$parent_span_id" "$start_time" "$end_time" "$attrs")
send_span "$span" "$tool_name" || true

if [[ -n "${shutdown_parent:-}" ]]; then
  _sd_start=$(get_state "agent_${agent_id}_start_time")
  [[ -z "$_sd_start" ]] && _sd_start="$start_time"
  _sd_attrs=$(jq -nc --arg sid "$session_id" --arg aid "$agent_id" --arg at "$agent_type" \
    --arg tn "$team_name" --arg uid "$user_id" \
    '{"session.id":$sid,"openinference.span.kind":"AGENT","agent.id":$aid,"agent.name":$at,"agent.role":"teammate"}
     + (if $tn != "" then {"team.name":$tn} else {} end)
     + (if $uid != "" then {"user.id":$uid} else {} end)')
  send_span "$(build_span "Teammate: $agent_type" "AGENT" "$shutdown_parent" "$trace_id" \
    "$shutdown_turn_parent" "$_sd_start" "$end_time" "$_sd_attrs")" "Teammate: $agent_type" || true
  del_states "agent_${agent_id}_span_id" "agent_${agent_id}_start_time"
  # Sentinel: tells SubagentStop that the grouping span was already emitted here,
  # so it must not create a second AGENT span for the same lifecycle.
  set_state "agent_${agent_id}_shutdown_complete" "1"
fi
