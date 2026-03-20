#!/bin/bash
# TeammateIdle - Cache teammate_name from hook input into state
# No span creation (fires after Stop clears trace state)
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

teammate_name=$(echo "$input" | jq -r '.teammate_name // empty' 2>/dev/null || echo "")
[[ -n "$teammate_name" ]] && set_state "team_agent_name" "$teammate_name"
