#!/bin/bash
# PreToolUse - capture the START time of a Read of a rule file (any **/rules/*.md), keyed
# by tool_use_id, so the rule-read span (emitted at PostToolUse) can be stamped with the
# read's real start instead of its completion time. Uses our own state key (rulestart_<id>)
# to avoid racing post_tool_use.sh, which deletes its own tool_<id>_start key.
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

tool_id=$(echo "$input" | jq -r '.tool_use_id // empty' 2>/dev/null || echo "")
[[ -z "$tool_id" ]] && exit 0

set_state "rulestart_${tool_id}" "$(get_timestamp_ms)"
exit 0
