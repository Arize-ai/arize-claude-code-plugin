#!/bin/bash
# SubagentStop - Create span for subagent completion
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

trace_id=$(get_state "current_trace_id")
[[ -z "$trace_id" ]] && exit 0

session_id=$(get_state "session_id")
agent_id=$(echo "$input" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
agent_type=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null || echo "")

# Guard: skip span creation for empty/unknown agent types
if [[ -z "$agent_type" || "$agent_type" == "unknown" || "$agent_type" == "null" ]]; then
  log "Skipping empty subagent span (agent_type='$agent_type')"
  exit 0
fi

span_id=$(generate_uuid | tr -d '-' | cut -c1-16)
end_time=$(get_timestamp_ms)
parent=$(get_state "current_trace_span_id")

# Try to parse subagent transcript for output
transcript_path=$(echo "$input" | jq -r '.agent_transcript_path // empty' 2>/dev/null || echo "")
subagent_output=""
start_time=""
model=""
in_tokens=0 out_tokens=0 cache_read_tokens=0 cache_creation_tokens=0

if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  # Use file birth time (creation time) for start estimate
  if stat -f %B "$transcript_path" &>/dev/null; then
    # macOS: %B = birth time
    file_time_s=$(stat -f %B "$transcript_path")
    start_time=$((file_time_s * 1000))
  elif stat -c %W "$transcript_path" &>/dev/null; then
    # Linux: %W = birth time (may be 0 if unsupported)
    file_time_s=$(stat -c %W "$transcript_path")
    if [[ "$file_time_s" =~ ^[0-9]+$ && "$file_time_s" -gt 0 ]]; then
      start_time=$((file_time_s * 1000))
    fi
  fi

  # Parse subagent transcript for output and token usage
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ $(echo "$line" | jq -r '.type' 2>/dev/null) == "assistant" ]] || continue

    # Extract last assistant message as output
    text=$(echo "$line" | jq -r '.message.content | if type=="array" then [.[]|select(.type=="text")|.text]|join("\n") else . end' 2>/dev/null)
    [[ -n "$text" && "$text" != "null" ]] && subagent_output="$text"

    # Accumulate token counts
    model=$(echo "$line" | jq -r '.message.model // empty' 2>/dev/null)
    val=$(echo "$line" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null)
    [[ "$val" =~ ^[0-9]+$ ]] && in_tokens=$((in_tokens + val))
    val=$(echo "$line" | jq -r '.message.usage.output_tokens // 0' 2>/dev/null)
    [[ "$val" =~ ^[0-9]+$ ]] && out_tokens=$((out_tokens + val))
    val=$(echo "$line" | jq -r '.message.usage.cache_read_input_tokens // 0' 2>/dev/null)
    [[ "$val" =~ ^[0-9]+$ ]] && cache_read_tokens=$((cache_read_tokens + val))
    val=$(echo "$line" | jq -r '.message.usage.cache_creation_input_tokens // 0' 2>/dev/null)
    [[ "$val" =~ ^[0-9]+$ ]] && cache_creation_tokens=$((cache_creation_tokens + val))
  done < "$transcript_path"

  subagent_output=$(echo "$subagent_output" | head -c 5000)
fi

# Fall back to current time if no start time found
[[ -z "$start_time" ]] && start_time="$end_time"

# Compute total prompt tokens (all input-side) and overall total
prompt_tokens=$((in_tokens + cache_read_tokens + cache_creation_tokens))
total_tokens=$((prompt_tokens + out_tokens))

user_id=$(get_state "user_id")

attrs=$(jq -nc \
  --arg sid "$session_id" \
  --arg agent_id "$agent_id" \
  --arg agent_type "$agent_type" \
  --arg output "$subagent_output" \
  --arg model "$model" \
  --arg uid "$user_id" \
  --argjson out_tok "$out_tokens" \
  --argjson cache_read_tok "$cache_read_tokens" --argjson cache_creation_tok "$cache_creation_tokens" \
  --argjson prompt_tok "$prompt_tokens" --argjson total_tok "$total_tokens" \
  '{"session.id":$sid,"openinference.span.kind":"chain","subagent.id":$agent_id,"subagent.type":$agent_type,"llm.model_name":$model,"llm.token_count.prompt":$prompt_tok,"llm.token_count.completion":$out_tok,"llm.token_count.total":$total_tok,"llm.token_count.prompt_details.cache_read":$cache_read_tok,"llm.token_count.prompt_details.cache_write":$cache_creation_tok} + (if $output != "" then {"output.value":$output} else {} end) + (if $uid != "" then {"user.id":$uid} else {} end)')

span=$(build_span "Subagent: $agent_type" "CHAIN" "$span_id" "$trace_id" "$parent" "$start_time" "$end_time" "$attrs")
send_span "$span" || true
