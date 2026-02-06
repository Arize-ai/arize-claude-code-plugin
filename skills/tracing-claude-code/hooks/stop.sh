#!/bin/bash
# Stop - Create trace span with input and output
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat)

session_id=$(get_state "session_id")
trace_id=$(get_state "current_trace_id")
[[ -z "$session_id" || -z "$trace_id" ]] && exit 0

trace_span_id=$(get_state "current_trace_span_id")
trace_start_time=$(get_state "current_trace_start_time")
user_prompt=$(get_state "current_trace_prompt")
project_name=$(get_state "project_name")
trace_count=$(get_state "trace_count")

# Parse transcript for AI response and tokens
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
output="" model="" in_tokens=0 out_tokens=0

if [[ -f "$transcript" ]]; then
  start_line=$(get_state "trace_start_line")
  line_num=0
  
  while IFS= read -r line; do
    ((line_num++))
    [[ $line_num -le ${start_line:-0} || -z "$line" ]] && continue
    
    [[ $(echo "$line" | jq -r '.type' 2>/dev/null) == "assistant" ]] || continue
    
    # Extract text
    text=$(echo "$line" | jq -r '.message.content | if type=="array" then [.[]|select(.type=="text")|.text]|join("\n") else . end' 2>/dev/null)
    [[ -n "$text" && "$text" != "null" ]] && output="${output:+$output\n}$text"
    
    # Extract model and tokens
    model=$(echo "$line" | jq -r '.message.model // empty' 2>/dev/null)
    in_tokens=$((in_tokens + $(echo "$line" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null)))
    out_tokens=$((out_tokens + $(echo "$line" | jq -r '.message.usage.output_tokens // 0' 2>/dev/null)))
  done < "$transcript"
fi

output=$(echo -e "$output" | head -c 2000)
[[ -z "$output" ]] && output="(No response)"

attrs=$(jq -nc \
  --arg sid "$session_id" --arg num "$trace_count" --arg proj "$project_name" \
  --arg in "$user_prompt" --arg out "$output" --arg model "$model" \
  --argjson in_tok "$in_tokens" --argjson out_tok "$out_tokens" \
  '{"session.id":$sid,"trace.number":$num,"project.name":$proj,"openinference.span.kind":"chain","llm.model_name":$model,"llm.token_count.prompt":$in_tok,"llm.token_count.completion":$out_tok,"input.value":$in,"output.value":$out}')

span=$(build_span "Trace #$trace_count" "CHAIN" "$trace_span_id" "$trace_id" "" "$trace_start_time" "$(get_timestamp_ms)" "$attrs")
send_span "$span" || true

del_state "current_trace_prompt"
log "Trace #$trace_count sent"
