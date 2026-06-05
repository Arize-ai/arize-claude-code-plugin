#!/bin/bash
# PostToolUse - emit a "rule-read: <name>" span whenever a Read targets a rule file (any
# **/rules/*.md, including plugin-provided rules a SKILL.md links to).
#
# This captures the "a skill consulted a rule" signal that InstructionsLoaded does NOT:
# SKILL.md markdown links don't auto-load; the rule only enters context when it is Read.
# The span is timed start = read start (captured at PreToolUse), end = now, so it sorts
# next to the underlying Read instead of at its completion time.
source "$(dirname "$0")/common.sh"
set +e # telemetry must never block or abort a turn

check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[[ "$tool_name" != "Read" ]] && exit 0

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
case "$file_path" in
  */rules/*.md) ;;
  *) exit 0 ;;
esac

resolve_session "$input"

trace_id=$(get_state "current_trace_id")
parent=$(get_state "current_trace_span_id")
if [[ -z "$trace_id" ]]; then
  trace_id=$(generate_uuid | tr -d '-')
  parent=""
fi
span_id=$(generate_uuid | tr -d '-' | cut -c1-16)

session_id=$(get_state "session_id")
project_name=$(get_state "project_name")
user_id=$(get_state "user_id")
base=$(basename "$file_path" 2>/dev/null || echo "$file_path")

# Span timing: start = read start (captured at PreToolUse), end = now. Falls back to
# now/now if the start was not captured.
tool_id=$(echo "$input" | jq -r '.tool_use_id // empty' 2>/dev/null || echo "")
start_ms=""
[[ -n "$tool_id" ]] && start_ms=$(get_state "rulestart_${tool_id}")
end_ms=$(get_timestamp_ms)
[[ -z "$start_ms" ]] && start_ms="$end_ms"

content=""
[[ -f "$file_path" ]] && content=$(head -c 4000 "$file_path" 2>/dev/null || echo "")

attrs=$(jq -nc \
  --arg sid "$session_id" --arg proj "$project_name" --arg uid "$user_id" \
  --arg fp "$file_path" --arg base "$base" --arg c "$content" \
  '{"session.id":$sid,"project.name":$proj,"openinference.span.kind":"CHAIN",
    "rule.file_path":$fp,"rule.name":$base,"rule.source":"read","tool.name":"Read",
    "output.value":$c}
   + (if $uid != "" then {"user.id":$uid} else {} end)')

span=$(build_span "rule-read: $base" "CHAIN" "$span_id" "$trace_id" "$parent" "$start_ms" "$end_ms" "$attrs")
send_span "$span" || true

[[ -n "$tool_id" ]] && del_state "rulestart_${tool_id}"
log "Emitted rule-read span: rule-read: $base"
exit 0
