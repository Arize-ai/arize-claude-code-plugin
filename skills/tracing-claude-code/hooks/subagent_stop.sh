#!/bin/bash
# SubagentStop - Create span for subagent completion
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat)

trace_id=$(get_state "current_trace_id")
[[ -z "$trace_id" ]] && exit 0

session_id=$(get_state "session_id")
agent_id=$(echo "$input" | jq -r '.agent_id // empty')
agent_type=$(echo "$input" | jq -r '.agent_type // empty')

# Guard: skip span creation for empty/unknown agent types
if [[ -z "$agent_type" || "$agent_type" == "unknown" || "$agent_type" == "null" ]]; then
  log "Skipping empty subagent span (agent_type='$agent_type')"
  exit 0
fi

span_id=$(generate_uuid | tr -d '-' | cut -c1-16)
end_time=$(get_timestamp_ms)
parent=$(get_state "current_trace_span_id")

# Try to parse subagent transcript for output and timing
transcript_path=$(echo "$input" | jq -r '.agent_transcript_path // empty')
subagent_output=""
start_time=""

if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  # Use file modification time for start estimate (file created when subagent started)
  if stat -f %m "$transcript_path" &>/dev/null; then
    # macOS stat
    file_mtime_s=$(stat -f %m "$transcript_path")
    start_time=$((file_mtime_s * 1000))
  elif stat -c %Y "$transcript_path" &>/dev/null; then
    # Linux stat
    file_mtime_s=$(stat -c %Y "$transcript_path")
    start_time=$((file_mtime_s * 1000))
  fi

  # Extract last assistant message as subagent output
  subagent_output=$(tail -20 "$transcript_path" | while IFS= read -r line; do
    type=$(echo "$line" | jq -r '.type' 2>/dev/null)
    if [[ "$type" == "assistant" ]]; then
      echo "$line" | jq -r '.message.content | if type=="array" then [.[]|select(.type=="text")|.text]|join("\n") else . end' 2>/dev/null
    fi
  done | tail -1 | head -c 5000)
fi

# Fall back to current time if no start time found
[[ -z "$start_time" ]] && start_time="$end_time"

attrs=$(jq -n \
  --arg sid "$session_id" \
  --arg agent_id "$agent_id" \
  --arg agent_type "$agent_type" \
  --arg output "$subagent_output" \
  '{"session.id":$sid,"openinference.span.kind":"chain","subagent.id":$agent_id,"subagent.type":$agent_type} + (if $output != "" then {"output.value":$output} else {} end)')

span=$(build_span "Subagent: $agent_type" "CHAIN" "$span_id" "$trace_id" "$parent" "$start_time" "$end_time" "$attrs")
send_span "$span" || true
