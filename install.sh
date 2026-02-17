#!/bin/bash
# Arize Claude Code Tracing - Installer

set -euo pipefail

RED='\033[0;31m' GREEN='\033[0;32m' BLUE='\033[0;34m' NC='\033[0m'
log() { echo -e "${BLUE}[arize]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
PLUGIN_DIR="${SCRIPT_DIR}/plugins/claude-code-tracing"
SOURCE_HOOKS="${PLUGIN_DIR}/hooks"
YELLOW='\033[1;33m'

check_requirements() {
  command -v jq &>/dev/null || { error "jq required. Install: brew install jq"; exit 1; }
  command -v curl &>/dev/null || { error "curl required"; exit 1; }
  success "Requirements met"
}

check_existing() {
  if [[ -f "$SETTINGS_FILE" ]] && jq -e '.hooks' "$SETTINGS_FILE" &>/dev/null; then
    echo -e "${YELLOW}Existing hooks found in${NC} $SETTINGS_FILE"
    read -p "Overwrite hooks config? [y/N]: " overwrite
    [[ "$overwrite" =~ ^[Yy]$ ]] || { echo "Install cancelled."; exit 0; }
    echo ""
  fi
}

install_hooks() {
  mkdir -p "$HOOKS_DIR"
  mkdir -p "${CLAUDE_DIR}/scripts"

  # Copy all hook scripts
  cp "$SOURCE_HOOKS"/*.sh "$HOOKS_DIR/"
  cp "${PLUGIN_DIR}/scripts/send_span.py" "${CLAUDE_DIR}/scripts/send_span.py"
  chmod +x "$HOOKS_DIR"/*.sh
  chmod +x "${CLAUDE_DIR}/scripts/send_span.py"

  success "Hooks installed to $HOOKS_DIR"
}

configure_hooks() {
  mkdir -p "$CLAUDE_DIR"
  [[ -f "$SETTINGS_FILE" ]] || echo '{}' > "$SETTINGS_FILE"

  local hooks_config
  hooks_config=$(jq -n \
    --arg dir "$HOOKS_DIR" \
    '{
      SessionStart: [{hooks:[{type:"command",command:("bash " + $dir + "/session_start.sh")}]}],
      UserPromptSubmit: [{hooks:[{type:"command",command:("bash " + $dir + "/user_prompt_submit.sh")}]}],
      PreToolUse: [{hooks:[{type:"command",command:("bash " + $dir + "/pre_tool_use.sh")}]}],
      PostToolUse: [{hooks:[{type:"command",command:("bash " + $dir + "/post_tool_use.sh")}]}],
      Stop: [{hooks:[{type:"command",command:("bash " + $dir + "/stop.sh")}]}],
      SubagentStop: [{hooks:[{type:"command",command:("bash " + $dir + "/subagent_stop.sh")}]}],
      Notification: [{hooks:[{type:"command",command:("bash " + $dir + "/notification.sh")}]}],
      PermissionRequest: [{hooks:[{type:"command",command:("bash " + $dir + "/permission_request.sh")}]}],
      SessionEnd: [{hooks:[{type:"command",command:("bash " + $dir + "/session_end.sh")}]}]
    }')

  jq --argjson h "$hooks_config" '.hooks = (.hooks // {}) + $h' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
  mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

  success "Hooks configured in $SETTINGS_FILE"
}

print_config() {
  echo ""
  echo -e "Configure in ${GREEN}.claude/settings.local.json${NC}:"
  echo ""
  echo "Phoenix (self-hosted):"
  echo '  {"env": {"PHOENIX_ENDPOINT": "http://localhost:6006", "ARIZE_TRACE_ENABLED": "true"}}'
  echo ""
  echo "Arize AX (cloud):"
  echo '  {"env": {"ARIZE_API_KEY": "...", "ARIZE_SPACE_ID": "...", "ARIZE_TRACE_ENABLED": "true"}}'
  echo ""
}

uninstall() {
  log "Uninstalling..."
  rm -f "$HOOKS_DIR"/{session_start,session_end,user_prompt_submit,pre_tool_use,post_tool_use,stop,subagent_stop,notification,permission_request,common}.sh "${CLAUDE_DIR}/scripts/send_span.py"
  [[ -f "$SETTINGS_FILE" ]] && jq 'del(.hooks)' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  rm -rf "${HOME}/.arize-claude-code"
  success "Uninstalled"
}

main() {
  echo -e "\n${GREEN}▸ ARIZE${NC} Claude Code Tracing\n"
  
  case "${1:-install}" in
    install)
      check_requirements
      check_existing
      install_hooks
      configure_hooks
      print_config
      ;;
    uninstall) uninstall ;;
    *) echo "Usage: $0 [install|uninstall]" ;;
  esac
}

main "$@"
