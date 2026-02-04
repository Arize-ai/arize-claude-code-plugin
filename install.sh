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
SOURCE_HOOKS="${SCRIPT_DIR}/skills/tracing-claude-code/hooks"

check_requirements() {
  command -v jq &>/dev/null || { error "jq required. Install: brew install jq"; exit 1; }
  command -v curl &>/dev/null || { error "curl required"; exit 1; }
  success "Requirements met"
}

install_hooks() {
  mkdir -p "$HOOKS_DIR"

  # Copy all hook scripts
  cp "$SOURCE_HOOKS"/*.sh "$HOOKS_DIR/"
  cp "${SCRIPT_DIR}/skills/tracing-claude-code/hooks.sh" "$HOOKS_DIR/arize-tracing.sh"
  cp "${SCRIPT_DIR}/skills/tracing-claude-code/send_span.py" "$HOOKS_DIR/send_span.py"
  chmod +x "$HOOKS_DIR"/*.sh
  chmod +x "$HOOKS_DIR/send_span.py"

  success "Hooks installed to $HOOKS_DIR"
}

configure_hooks() {
  mkdir -p "$CLAUDE_DIR"
  [[ -f "$SETTINGS_FILE" ]] || echo '{}' > "$SETTINGS_FILE"
  
  local cmd="bash ${HOOKS_DIR}/arize-tracing.sh"
  local hooks_config
  hooks_config=$(jq -n \
    --arg cmd "$cmd" \
    '{
      SessionStart: [{hooks:[{type:"command",command:($cmd+" SessionStart")}]}],
      UserPromptSubmit: [{hooks:[{type:"command",command:($cmd+" UserPromptSubmit")}]}],
      PreToolUse: [{hooks:[{type:"command",command:($cmd+" PreToolUse")}]}],
      PostToolUse: [{hooks:[{type:"command",command:($cmd+" PostToolUse")}]}],
      Stop: [{hooks:[{type:"command",command:($cmd+" Stop")}]}],
      SubagentStop: [{hooks:[{type:"command",command:($cmd+" SubagentStop")}]}],
      SessionEnd: [{hooks:[{type:"command",command:($cmd+" SessionEnd")}]}]
    }')
  
  jq --argjson h "$hooks_config" '.hooks = $h' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
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
  rm -f "$HOOKS_DIR"/arize-tracing.sh "$HOOKS_DIR"/{session_start,session_end,user_prompt_submit,pre_tool_use,post_tool_use,stop,subagent_stop,notification,permission_request,common}.sh
  [[ -f "$SETTINGS_FILE" ]] && jq 'del(.hooks)' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  rm -rf "${HOME}/.arize-claude-code"
  success "Uninstalled"
}

main() {
  echo -e "\n${GREEN}▸ ARIZE${NC} Claude Code Tracing\n"
  
  case "${1:-install}" in
    install)
      check_requirements
      install_hooks
      configure_hooks
      print_config
      ;;
    uninstall) uninstall ;;
    *) echo "Usage: $0 [install|uninstall]" ;;
  esac
}

main "$@"
