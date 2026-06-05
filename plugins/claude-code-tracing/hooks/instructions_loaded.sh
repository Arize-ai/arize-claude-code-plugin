#!/bin/bash
# InstructionsLoaded - emit a span per CLAUDE.md / .claude/rules/*.md (and plugin rules)
# loaded into context. Fires at session start and on lazy loads during a session.
#
# Nests under the current Turn when one is open; otherwise emits its own trace (session
# start loads happen before any turn exists). Race-free: this is not the same event as any
# hook that mutates current_trace_* state.
source "$(dirname "$0")/common.sh"
set +e # telemetry must never block or abort a turn

check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"
ensure_session_initialized "$input"

session_id=$(get_state "session_id")
project_name=$(get_state "project_name")
user_id=$(get_state "user_id")

trace_id=$(get_state "current_trace_id")
parent=$(get_state "current_trace_span_id")
if [[ -z "$trace_id" ]]; then
  trace_id=$(generate_uuid | tr -d '-')
  parent=""
fi
span_id=$(generate_uuid | tr -d '-' | cut -c1-16)

file_path=$(echo "$input" | jq -r '.file_path // "unknown"' 2>/dev/null || echo "unknown")
memory_type=$(echo "$input" | jq -r '.memory_type // empty' 2>/dev/null || echo "")
load_reason=$(echo "$input" | jq -r '.load_reason // empty' 2>/dev/null || echo "")

content=""
[[ -f "$file_path" ]] && content=$(head -c 4000 "$file_path" 2>/dev/null || echo "")

base=$(basename "$file_path" 2>/dev/null || echo "$file_path")
ts=$(get_timestamp_ms)

attrs=$(jq -nc \
  --arg sid "$session_id" --arg proj "$project_name" --arg uid "$user_id" \
  --arg fp "$file_path" --arg mt "$memory_type" --arg lr "$load_reason" --arg c "$content" \
  '{"session.id":$sid,"project.name":$proj,"openinference.span.kind":"CHAIN",
    "instructions.file_path":$fp,"instructions.memory_type":$mt,"instructions.load_reason":$lr,
    "output.value":$c}
   + (if $uid != "" then {"user.id":$uid} else {} end)')

span=$(build_span "rule: $base" "CHAIN" "$span_id" "$trace_id" "$parent" "$ts" "$ts" "$attrs")
send_span "$span" || true
log "Emitted InstructionsLoaded span: rule: $base"
exit 0
