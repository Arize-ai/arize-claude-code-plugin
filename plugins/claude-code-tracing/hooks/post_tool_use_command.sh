#!/bin/bash
# PostToolUse - emit the command/skill span stashed by user_prompt_expansion.sh, ONCE per
# turn, into the turn's trace so it groups with the Turn LLM span and tool spans.
#
# Race-free: current_trace_id/current_trace_span_id are written at UserPromptSubmit (a
# prior, completed event) and stable until Stop. An atomic mkdir "claim" keyed by trace_id
# guarantees a single emission even when a batch of parallel tool calls fires PostToolUse.
# The span is back-dated to the expansion timestamp so it sorts at the start of the turn.
source "$(dirname "$0")/common.sh"
set +e # telemetry must never block or abort a turn

check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

command_name=$(get_state "pending_cmd_name")
[[ -z "$command_name" ]] && exit 0            # nothing stashed / already emitted

trace_id=$(get_state "current_trace_id")
[[ -z "$trace_id" ]] && exit 0                # no open turn yet; retry on the next tool

# Atomic once-per-turn claim (handles parallel PostToolUse for batched tool calls).
claim="${STATE_DIR}/.cmdclaim_${trace_id}"
mkdir "$claim" 2>/dev/null || exit 0

parent=$(get_state "current_trace_span_id")
session_id=$(get_state "session_id")
project_name=$(get_state "project_name")
user_id=$(get_state "user_id")
command_args=$(get_state "pending_cmd_args")
expansion_type=$(get_state "pending_cmd_type")
command_source=$(get_state "pending_cmd_source")
prompt=$(get_state "pending_cmd_prompt")

span_id=$(generate_uuid | tr -d '-' | cut -c1-16)
# Stamp at expansion time so the command span sorts at the start of the turn, not at the
# emit time (which is after the first tool). Fall back to now.
ts=$(get_state "pending_cmd_ts")
[[ -z "$ts" ]] && ts=$(get_timestamp_ms)

attrs=$(jq -nc \
  --arg sid "$session_id" --arg proj "$project_name" --arg uid "$user_id" \
  --arg cname "$command_name" --arg cargs "$command_args" \
  --arg etype "$expansion_type" --arg csrc "$command_source" --arg in "$prompt" \
  '{"session.id":$sid,"project.name":$proj,"openinference.span.kind":"CHAIN",
    "command.name":$cname,"command.args":$cargs,"expansion.type":$etype,
    "command.source":$csrc,"input.value":$in}
   + (if $uid != "" then {"user.id":$uid} else {} end)')

span=$(build_span "command: $command_name" "CHAIN" "$span_id" "$trace_id" "$parent" "$ts" "$ts" "$attrs")
send_span "$span" || true

del_state "pending_cmd_name"
del_state "pending_cmd_args"
del_state "pending_cmd_type"
del_state "pending_cmd_source"
del_state "pending_cmd_prompt"
del_state "pending_cmd_ts"

log "Emitted command span into turn trace ($trace_id): command: $command_name"
exit 0
