#!/bin/bash
# Install Arize tracing for OpenAI Codex CLI
#
# This script configures Codex to send OpenInference traces to Arize AX or Phoenix.
# It sets up:
#   1. The notify hook (creates OpenInference LLM spans per turn)
#   2. Optionally, native OTLP export (sends Codex's built-in telemetry events)
#
# Usage:
#   ./install.sh                  # Interactive setup
#   ./install.sh uninstall        # Remove tracing configuration
#   ./install.sh --target phoenix        # Non-interactive: Phoenix at localhost:6006
#   ./install.sh --target arize          # Non-interactive: Arize AX (requires env vars)
#   ./install.sh --target arize --otlp   # Also enable native OTLP export

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFY_SCRIPT="${SCRIPT_DIR}/hooks/notify.sh"
CODEX_CONFIG_DIR="${HOME}/.codex"
CODEX_CONFIG="${CODEX_CONFIG_DIR}/config.toml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[arize]${NC} $*"; }
warn() { echo -e "${YELLOW}[arize]${NC} $*"; }
err()  { echo -e "${RED}[arize]${NC} $*" >&2; }

# --- Uninstall ---
if [[ "${1:-}" == "uninstall" ]]; then
  info "Removing Arize tracing from Codex config..."

  if [[ -f "$CODEX_CONFIG" ]]; then
    # Remove notify line referencing our script
    if grep -q "arize" "$CODEX_CONFIG" 2>/dev/null; then
      # Create backup
      cp "$CODEX_CONFIG" "${CODEX_CONFIG}.bak"
      # Remove notify line that references our script
      sed -i.tmp '/notify.*arize.*notify\.sh/d' "$CODEX_CONFIG"
      rm -f "${CODEX_CONFIG}.tmp"
      info "Removed notify hook from config.toml (backup: config.toml.bak)"
    else
      info "No Arize notify hook found in config.toml"
    fi
  fi

  # Clean up state
  rm -rf "${HOME}/.arize-codex"
  info "Cleaned up state directory"
  info "Uninstall complete. Native OTLP settings (if any) were left in config.toml."
  exit 0
fi

# --- Prerequisites ---
command -v jq &>/dev/null || { err "jq is required. Install: brew install jq"; exit 1; }
command -v codex &>/dev/null || warn "codex CLI not found in PATH — make sure it's installed"

# --- Ensure config directory exists ---
mkdir -p "$CODEX_CONFIG_DIR"
[[ -f "$CODEX_CONFIG" ]] || touch "$CODEX_CONFIG"

# --- Parse flags ---
ENABLE_OTLP=false
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --otlp) ENABLE_OTLP=true; shift ;;
    *) shift ;;
  esac
done

# --- Determine target ---
if [[ -n "$TARGET" ]]; then
  # Non-interactive mode
  :
else
  echo ""
  echo "  Arize Codex Tracing Setup"
  echo "  ========================="
  echo ""
  echo "  Choose a tracing backend:"
  echo ""
  echo "  1) Phoenix (self-hosted) — No Python required"
  echo "  2) Arize AX (cloud)     — Requires Python + opentelemetry"
  echo ""
  read -rp "  Enter choice [1/2]: " choice
  case "$choice" in
    1) TARGET="phoenix" ;;
    2) TARGET="arize" ;;
    *) err "Invalid choice"; exit 1 ;;
  esac
fi

# --- Collect credentials ---
case "$TARGET" in
  phoenix)
    if [[ -z "${PHOENIX_ENDPOINT:-}" ]]; then
      read -rp "  Phoenix endpoint [http://localhost:6006]: " ep
      PHOENIX_ENDPOINT="${ep:-http://localhost:6006}"
    fi
    info "Target: Phoenix at $PHOENIX_ENDPOINT"
    ;;
  arize)
    if [[ -z "${ARIZE_API_KEY:-}" ]]; then
      read -rp "  Arize API key: " ARIZE_API_KEY
    fi
    if [[ -z "${ARIZE_SPACE_ID:-}" ]]; then
      read -rp "  Arize Space ID: " ARIZE_SPACE_ID
    fi
    [[ -z "$ARIZE_API_KEY" || -z "$ARIZE_SPACE_ID" ]] && { err "API key and Space ID required"; exit 1; }
    info "Target: Arize AX"
    ;;
  *)
    err "Unknown target: $TARGET (use 'phoenix' or 'arize')"
    exit 1
    ;;
esac

# --- Configure notify hook ---
NOTIFY_LINE="notify = [\"bash\", \"${NOTIFY_SCRIPT}\"]"

if grep -q "^notify" "$CODEX_CONFIG" 2>/dev/null; then
  # Replace existing notify line (wherever it is)
  cp "$CODEX_CONFIG" "${CODEX_CONFIG}.bak"
  sed -i.tmp "s|^notify.*|${NOTIFY_LINE}|" "$CODEX_CONFIG"
  rm -f "${CODEX_CONFIG}.tmp"
  info "Updated existing notify hook in config.toml"
else
  # Insert notify BEFORE the first [section] header so it stays top-level.
  # In TOML, keys after a [section] belong to that section.
  if grep -qn '^\[' "$CODEX_CONFIG" 2>/dev/null; then
    first_section=$(grep -n '^\[' "$CODEX_CONFIG" | head -1 | cut -d: -f1)
    cp "$CODEX_CONFIG" "${CODEX_CONFIG}.bak"
    {
      head -n $((first_section - 1)) "$CODEX_CONFIG.bak"
      echo ""
      echo "# Arize tracing — OpenInference spans per turn"
      echo "$NOTIFY_LINE"
      echo ""
      tail -n +${first_section} "$CODEX_CONFIG.bak"
    } > "$CODEX_CONFIG"
  else
    # No sections — safe to append
    echo "" >> "$CODEX_CONFIG"
    echo "# Arize tracing — OpenInference spans per turn" >> "$CODEX_CONFIG"
    echo "$NOTIFY_LINE" >> "$CODEX_CONFIG"
  fi
  info "Added notify hook to config.toml"
fi

# --- Write environment variables ---
# Store credentials in a shell env file that the notify script can source,
# and also show the user how to set them in their shell profile.

ENV_FILE="${CODEX_CONFIG_DIR}/arize-env.sh"

case "$TARGET" in
  phoenix)
    cat > "$ENV_FILE" <<EOF
# Arize Codex tracing environment (auto-generated)
export ARIZE_TRACE_ENABLED=true
export PHOENIX_ENDPOINT="${PHOENIX_ENDPOINT}"
${PHOENIX_API_KEY:+export PHOENIX_API_KEY="${PHOENIX_API_KEY}"}
export ARIZE_PROJECT_NAME="${ARIZE_PROJECT_NAME:-codex}"
EOF
    ;;
  arize)
    cat > "$ENV_FILE" <<EOF
# Arize Codex tracing environment (auto-generated)
export ARIZE_TRACE_ENABLED=true
export ARIZE_API_KEY="${ARIZE_API_KEY}"
export ARIZE_SPACE_ID="${ARIZE_SPACE_ID}"
${ARIZE_OTLP_ENDPOINT:+export ARIZE_OTLP_ENDPOINT="${ARIZE_OTLP_ENDPOINT}"}
export ARIZE_PROJECT_NAME="${ARIZE_PROJECT_NAME:-codex}"
EOF
    ;;
esac

chmod 600 "$ENV_FILE"
info "Wrote credentials to $ENV_FILE"

# --- Configure native OTLP export (optional) ---
enable_otlp="n"
if [[ "$ENABLE_OTLP" == "true" ]]; then
  enable_otlp="y"
elif [[ -t 0 ]]; then
  # Interactive mode: ask the user
  echo ""
  read -rp "  Also enable Codex native OTLP export for richer events? [y/N]: " enable_otlp
else
  # Non-interactive mode: skip (can be enabled with --otlp flag)
  info "Skipping native OTLP setup (non-interactive). Pass --otlp to enable."
fi
if [[ "$enable_otlp" =~ ^[Yy] ]]; then
  # Check if [otel] section exists
  if grep -q "^\[otel\]" "$CODEX_CONFIG" 2>/dev/null; then
    warn "[otel] section already exists in config.toml — please configure manually:"
  else
    case "$TARGET" in
      phoenix)
        cat >> "$CODEX_CONFIG" <<EOF

# Arize native OTLP export to Phoenix
[otel]
exporter = { otlp-http = { endpoint = "${PHOENIX_ENDPOINT}/v1/traces", protocol = "binary" } }
EOF
        ;;
      arize)
        cat >> "$CODEX_CONFIG" <<EOF

# Arize native OTLP export to Arize AX
[otel]
exporter = { otlp-grpc = { endpoint = "https://${ARIZE_OTLP_ENDPOINT:-otlp.arize.com:443}", headers = { "authorization" = "Bearer ${ARIZE_API_KEY}", "space_id" = "${ARIZE_SPACE_ID}" } } }
EOF
        ;;
    esac
    info "Added [otel] exporter to config.toml"
  fi
fi

# --- Summary ---
echo ""
info "Setup complete!"
echo ""
echo "  Add this to your shell profile (.zshrc / .bashrc):"
echo ""
echo "    source ${ENV_FILE}"
echo ""
echo "  Or export the variables before running codex:"
echo ""
case "$TARGET" in
  phoenix)
    echo "    export ARIZE_TRACE_ENABLED=true"
    echo "    export PHOENIX_ENDPOINT=${PHOENIX_ENDPOINT}"
    ;;
  arize)
    echo "    export ARIZE_TRACE_ENABLED=true"
    echo "    export ARIZE_API_KEY=<your-key>"
    echo "    export ARIZE_SPACE_ID=<your-space-id>"
    ;;
esac
echo ""
echo "  Test with: ARIZE_DRY_RUN=true codex"
echo ""
echo "  View traces:"
case "$TARGET" in
  phoenix) echo "    Open ${PHOENIX_ENDPOINT} in your browser" ;;
  arize)   echo "    Open https://app.arize.com and navigate to your space" ;;
esac
echo ""
