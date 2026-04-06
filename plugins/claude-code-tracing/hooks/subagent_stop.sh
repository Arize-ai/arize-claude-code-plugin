#!/bin/bash
# SubagentStop - Create span for subagent completion
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

trace_id=$(resolve_trace_id)
[[ -z "$trace_id" ]] && exit 0

session_id=$(get_state "session_id")
agent_id=$(echo "$input" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
agent_type=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null || echo "")

# Guard: skip span creation for empty/unknown agent types
if [[ -z "$agent_type" || "$agent_type" == "unknown" || "$agent_type" == "null" ]]; then
  log "Skipping empty subagent span (agent_type='$agent_type')"
  exit 0
fi

# Guard: if post_tool_use already emitted the grouping AGENT span via the
# shutdown_response path, skip creating a duplicate here.
if [[ -n "$agent_id" && -n "$(get_state "agent_${agent_id}_shutdown_complete")" ]]; then
  del_state "agent_${agent_id}_shutdown_complete"
  log "Skipping SubagentStop span — grouping span already emitted by shutdown_response (agent_id=$agent_id)"
  exit 0
fi

end_time=$(get_timestamp_ms)
parent=$(resolve_parent_span_id)

transcript_path=$(echo "$input" | jq -r '.agent_transcript_path // empty' 2>/dev/null || echo "")
subagent_output=""
model="" in_tokens=0 out_tokens=0

# Check for pre-created grouping span (set by post_tool_use when agent used tools)
span_id=$(get_state "agent_${agent_id}_span_id")
team_name=$(get_state "team_name")

if [[ -z "$span_id" ]]; then
  # No tools fired during this work period — create grouping span now
  span_id=$(generate_span_id)
  set_state "agent_${agent_id}_span_id" "$span_id"

  # Estimate start_time
  if [[ -n "$team_name" ]]; then
    # Teammate: prefer previous turn's end time
    prev_stop=$(get_state "teammate_${agent_type}_last_stop_time")
    if [[ -n "$prev_stop" ]]; then
      set_state "agent_${agent_id}_start_time" "$prev_stop"
    elif [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
      file_birth=$(get_file_birth_ms "$transcript_path")
      set_state "agent_${agent_id}_start_time" "${file_birth:-$end_time}"
    else
      set_state "agent_${agent_id}_start_time" "$end_time"
    fi
  else
    # Subagent: estimate from transcript file birth time
    _sa_start=$(get_file_birth_ms "$transcript_path")
    set_state "agent_${agent_id}_start_time" "${_sa_start:-$end_time}"
  fi
fi

start_time=$(get_state "agent_${agent_id}_start_time")
[[ -z "$start_time" ]] && start_time="$end_time"

if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  _pt_offset=0
  [[ -n "$team_name" ]] && _pt_offset=$(get_state "teammate_${agent_type}_transcript_offset") && _pt_offset=${_pt_offset:-0}
  parse_transcript "$transcript_path" "$_pt_offset"
  subagent_output=$(echo "$_pt_all_text" | head -c "10000")
  model="$_pt_model"
  in_tokens=$_pt_in_tokens
  out_tokens=$_pt_out_tokens
  # Teammates: store transcript offset for next work period
  [[ -n "$team_name" ]] && set_state "teammate_${agent_type}_transcript_offset" "$(wc -l < "$transcript_path" | tr -d ' ')"
fi

total_tokens=$((in_tokens + out_tokens))

if [[ -n "$team_name" ]]; then
  _role="teammate"; span_name="Teammate: $agent_type"
else
  _role="subagent"; span_name="Subagent: $agent_type"
fi

user_id=$(get_state "user_id")

attrs=$(jq -nc \
  --arg sid "$session_id" \
  --arg agent_id "$agent_id" \
  --arg agent_type "$agent_type" \
  --arg output "$subagent_output" \
  --arg model "$model" \
  --arg role "$_role" \
  --arg tn "$team_name" \
  --arg uid "$user_id" \
  --argjson in_tok "$in_tokens" --argjson out_tok "$out_tokens" --argjson total_tok "$total_tokens" \
  '{"session.id":$sid,"openinference.span.kind":"AGENT","agent.id":$agent_id,"agent.name":$agent_type,"agent.role":$role,"llm.model_name":$model,"llm.token_count.prompt":$in_tok,"llm.token_count.completion":$out_tok,"llm.token_count.total":$total_tok}
   + (if $output != "" then {"output.value":$output} else {} end)
   + (if $tn != "" then {"team.name":$tn} else {} end)
   + (if $uid != "" then {"user.id":$uid} else {} end)')

span=$(build_span "$span_name" "AGENT" "$span_id" "$trace_id" "$parent" "$start_time" "$end_time" "$attrs")
send_span "$span" || true

del_states "agent_${agent_id}_span_id" "agent_${agent_id}_start_time"

# Clean up reverse mapping if still pointing to this agent
_current_active=$(get_state "active_agent_${agent_type}")
if [[ "$_current_active" == "$agent_id" || "$_current_active" == "spawning" || "$_current_active" == "waking" ]]; then
  del_state "active_agent_${agent_type}"
fi

if [[ -n "$team_name" ]]; then
  # Teammate: persist turn-end time for next work period's start estimate
  set_state "teammate_${agent_type}_last_stop_time" "$end_time"
fi
