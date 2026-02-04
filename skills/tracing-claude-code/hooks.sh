#!/bin/bash
# Arize Claude Code Tracing - Hook Router

set -euo pipefail

HOOK_TYPE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hooks are in same directory (flat structure when installed)
[[ -z "$HOOK_TYPE" ]] && exit 1

case "$HOOK_TYPE" in
  SessionStart)      bash "${SCRIPT_DIR}/session_start.sh" ;;
  UserPromptSubmit)  bash "${SCRIPT_DIR}/user_prompt_submit.sh" ;;
  PreToolUse)        bash "${SCRIPT_DIR}/pre_tool_use.sh" ;;
  PostToolUse)       bash "${SCRIPT_DIR}/post_tool_use.sh" ;;
  Stop)              bash "${SCRIPT_DIR}/stop.sh" ;;
  SubagentStop)      bash "${SCRIPT_DIR}/subagent_stop.sh" ;;
  Notification)      bash "${SCRIPT_DIR}/notification.sh" ;;
  PermissionRequest) bash "${SCRIPT_DIR}/permission_request.sh" ;;
  SessionEnd)        bash "${SCRIPT_DIR}/session_end.sh" ;;
  *) exit 0 ;;
esac
