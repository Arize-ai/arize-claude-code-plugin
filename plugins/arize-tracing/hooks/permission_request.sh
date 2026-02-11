#!/bin/bash
# PermissionRequest - Create span for permission requests
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat)

trace_id=$(get_state "current_trace_id")
[[ -z "$trace_id" ]] && exit 0

permission=$(echo "$input" | jq -r '.permission // empty')
tool=$(echo "$input" | jq -r '.tool_name // empty')

span_id=$(generate_uuid | tr -d '-' | cut -c1-16)
ts=$(get_timestamp_ms)
parent=$(get_state "current_trace_span_id")

attrs=$(jq -n --arg perm "$permission" --arg tool "$tool" \
  '{"openinference.span.kind":"chain","permission.type":$perm,"permission.tool":$tool}')

span=$(build_span "Permission Request" "CHAIN" "$span_id" "$trace_id" "$parent" "$ts" "$ts" "$attrs")
send_span "$span" || true
