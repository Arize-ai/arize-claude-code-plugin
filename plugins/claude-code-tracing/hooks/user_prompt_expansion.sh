#!/bin/bash
# UserPromptExpansion - STASH command/skill metadata for this turn (no span emitted here).
#
# The turn's trace is created at UserPromptSubmit, and hooks for an event run in parallel
# with no ordering guarantee, so current_trace_id is not reliably available at expansion
# time. We stash the command (plus the expansion timestamp) and emit the span on the first
# PostToolUse of the turn (post_tool_use_command.sh), where current_trace_id is guaranteed
# present -> the span shares the turn's trace and back-dates to when the command fired.
source "$(dirname "$0")/common.sh"
set +e # telemetry must never block or abort a turn

check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"
ensure_session_initialized "$input"

command_name=$(echo "$input" | jq -r '.command_name // "unknown"' 2>/dev/null || echo "unknown")
command_args=$(echo "$input" | jq -r '.command_args // empty' 2>/dev/null | head -c 2000 || echo "")
expansion_type=$(echo "$input" | jq -r '.expansion_type // empty' 2>/dev/null || echo "")
command_source=$(echo "$input" | jq -r '.command_source // empty' 2>/dev/null || echo "")
prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null | head -c 2000 || echo "")

set_state "pending_cmd_name" "$command_name"
set_state "pending_cmd_args" "$command_args"
set_state "pending_cmd_type" "$expansion_type"
set_state "pending_cmd_source" "$command_source"
set_state "pending_cmd_prompt" "$prompt"
# When the command actually fired -> used as the span start so it sorts at the turn start.
set_state "pending_cmd_ts" "$(get_timestamp_ms)"

log "Stashed UserPromptExpansion: command: $command_name"
exit 0
