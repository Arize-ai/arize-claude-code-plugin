#!/bin/bash
# SessionStart - Initialize session state
source "$(dirname "$0")/common.sh"

check_requirements

input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')
[[ -z "$session_id" ]] && session_id=$(generate_uuid)

project_name="${ARIZE_PROJECT_NAME:-}"
if [[ -z "$project_name" ]]; then
  cwd=$(echo "$input" | jq -r '.cwd // empty')
  project_name=$(basename "${cwd:-$(pwd)}")
fi

set_state "session_id" "$session_id"
set_state "session_start_time" "$(get_timestamp_ms)"
set_state "project_name" "$project_name"
set_state "trace_count" "0"
set_state "tool_count" "0"

log "Session started: $session_id"
