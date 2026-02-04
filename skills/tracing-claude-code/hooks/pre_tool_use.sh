#!/bin/bash
# PreToolUse - Record start time for duration tracking
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat)
tool_id=$(echo "$input" | jq -r '.tool_use_id // empty')
[[ -z "$tool_id" ]] && tool_id=$(generate_uuid)

set_state "tool_${tool_id}_start" "$(get_timestamp_ms)"
