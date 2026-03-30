#!/bin/bash
# Codex notify handler - creates OpenInference LLM spans from agent-turn-complete events.
#
# Codex calls: notify = ["bash", "/path/to/notify.sh"]
# The notify payload is passed as a single JSON command-line argument:
#   { "type": "agent-turn-complete", "thread-id": "...", "turn-id": "...",
#     "cwd": "...", "input-messages": [...], "last-assistant-message": "..." }

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_ENV="${HOME}/.codex/arize-env.sh"
[[ -f "$CODEX_ENV" ]] && source "$CODEX_ENV"
source "${HOOK_DIR}/common.sh"

check_requirements

input="${1:-'{}'}"
event_type=$(echo "$input" | jq -r '.type // empty' 2>/dev/null || echo "")
if [[ "$event_type" != "agent-turn-complete" ]]; then
  log "Ignoring event type: $event_type"
  exit 0
fi

thread_id=$(echo "$input" | jq -r '.["thread-id"] // empty' 2>/dev/null || echo "")
turn_id=$(echo "$input" | jq -r '.["turn-id"] // empty' 2>/dev/null || echo "")
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || echo "")
user_input=$(echo "$input" | jq -c '.["input-messages"] // ""' 2>/dev/null || echo '""')
assistant_message_json=$(echo "$input" | jq -c '.["last-assistant-message"] // ""' 2>/dev/null || echo '""')
debug_prefix="notify_${thread_id:-unknown}_${turn_id:-unknown}"
debug_dump "${debug_prefix}_raw" "$input"

assistant_output=$(printf '%s' "$assistant_message_json" | jq -r '
  def as_text($node):
    if $node == null then ""
    elif ($node | type) == "string" then $node
    elif ($node | type) == "array" then ($node | map(as_text(.)) | join("\n"))
    elif ($node | type) == "object" then ($node.text // as_text($node.content) // as_text($node.message) // as_text($node.data) // as_text($node.value) // tostring)
    else tostring end;
  as_text(.)
' 2>/dev/null || echo "")

resolve_session "$thread_id"
ensure_session_initialized "$thread_id" "${cwd:-$(pwd)}"

session_id=$(get_state "session_id")
inc_state "trace_count"
trace_count=$(get_state "trace_count")
project_name=$(get_state "project_name")

user_prompt=""
if printf '%s' "$user_input" | jq -e 'type == "array"' >/dev/null 2>&1; then
  user_prompt=$(printf '%s' "$user_input" | jq -r '
    def as_text($node):
      if $node == null then ""
      elif ($node | type) == "string" then $node
      elif ($node | type) == "array" then ($node | map(as_text(.)) | join("\n"))
      elif ($node | type) == "object" then ($node.text // as_text($node.content) // tostring)
      else tostring end;
    [.[] | select((.role // .["message.role"] // "") == "user") | as_text(.)] | join("\n")
  ' 2>/dev/null || echo "")
elif printf '%s' "$user_input" | jq -e 'type == "string"' >/dev/null 2>&1; then
  user_prompt=$(printf '%s' "$user_input" | jq -r '.' 2>/dev/null || echo "")
else
  user_prompt="$user_input"
fi

user_prompt=$(printf '%s' "$user_prompt" | head -c 5000)
assistant_output=$(printf '%s' "$assistant_output" | head -c 5000)
[[ -z "$assistant_output" ]] && assistant_output="(No response)"
debug_dump "${debug_prefix}_text" "$(jq -nc --arg user "$user_prompt" --arg assistant "$assistant_output" '{input:$user,assistant:$assistant}')"

trace_id=$(generate_uuid | tr -d '-')
span_id=$(generate_uuid | tr -d '-' | cut -c1-16)
start_time=$(get_timestamp_ms)
end_time="$start_time"

output_messages=$(jq -nc --arg out "$assistant_output" '[{"message.role":"assistant","message.content":$out}]')
attrs=$(jq -nc \
  --arg sid "$session_id" \
  --arg num "$trace_count" \
  --arg proj "$project_name" \
  --arg in "$user_prompt" \
  --arg out "$assistant_output" \
  --arg turn_id "$turn_id" \
  --arg thread_id "$thread_id" \
  --argjson out_msgs "$output_messages" \
  '{
    "session.id": $sid,
    "trace.number": $num,
    "project.name": $proj,
    "openinference.span.kind": "LLM",
    "input.value": $in,
    "output.value": $out,
    "codex.turn_id": $turn_id,
    "codex.thread_id": $thread_id,
    "llm.output_messages": $out_msgs
  }')

token_usage_json=$(echo "$input" | jq -c '
  def usage_from($obj):
    if $obj != null and ($obj | type) == "object" then
      ($obj.token_usage // $obj["token-usage"] // $obj.usage // $obj["usage"])
    else null end;
  usage_from(.)
  // usage_from(.["last-assistant-message"])
  // usage_from(.["last-assistant-message"].message)
' 2>/dev/null || echo "null")
if [[ -n "$token_usage_json" && "$token_usage_json" != "null" ]]; then
  attrs=$(echo "$attrs" | jq --arg usage "$token_usage_json" '. + {"codex.token_usage": $usage}')
  debug_dump "${debug_prefix}_token_usage" "$token_usage_json"
fi

tool_calls_json=$(echo "$input" | jq -c '
  def tool_list($obj):
    if $obj == null then null
    elif ($obj | type) == "array" then $obj
    elif ($obj | type) == "object" then
      ($obj.tool_calls // $obj["tool-calls"] // $obj.toolCalls // $obj.tool_invocations // $obj.toolInvocations // $obj.tools // $obj.tool_results)
      | (if . == null then null elif (.|type) == "array" then . else [.] end)
    else null end;
  tool_list(.)
  // tool_list(.["last-assistant-message"])
  // tool_list(.["last-assistant-message"].message)
' 2>/dev/null || echo "null")
if [[ -n "$tool_calls_json" && "$tool_calls_json" != "null" ]]; then
  tool_call_count=$(printf '%s' "$tool_calls_json" | jq 'length' 2>/dev/null || echo "")
  if [[ "$tool_call_count" =~ ^[0-9]+$ ]]; then
    attrs=$(echo "$attrs" | jq --argjson cnt "$tool_call_count" '. + {"llm.tool_call_count": $cnt}')
    debug_dump "${debug_prefix}_tool_calls" "$tool_calls_json"
  fi
fi

span=$(build_span "Turn $trace_count" "LLM" "$span_id" "$trace_id" "" "$start_time" "$end_time" "$attrs")
debug_dump "${debug_prefix}_span" "$span"
send_span "$span" || true
log "Turn $trace_count sent (thread=$thread_id, turn=$turn_id)"

if [[ $((trace_count % 10)) -eq 0 ]]; then
  gc_stale_state_files
fi
