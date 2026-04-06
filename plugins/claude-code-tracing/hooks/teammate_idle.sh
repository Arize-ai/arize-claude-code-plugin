#!/bin/bash
# TeammateIdle - Cache team_name in session state
# No span emitted (SubagentStop already covers teammate turn-end events)
source "$(dirname "$0")/common.sh"
check_requirements

input=$(cat 2>/dev/null || echo '{}')
[[ -z "$input" ]] && input='{}'

resolve_session "$input"

team_name=$(echo "$input" | jq -r '.team_name // empty' 2>/dev/null || echo "")
teammate_name=$(echo "$input" | jq -r '.teammate_name // empty' 2>/dev/null || echo "")

if [[ -n "$team_name" ]]; then
  set_state "team_name" "$team_name"
  log "Cached team_name=$team_name (teammate=$teammate_name)"
fi
