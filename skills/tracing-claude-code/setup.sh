#!/bin/bash
# Arize Claude Code Plugin - Interactive Setup
# Run after: claude plugin install tracing-claude-code@arize-claude-plugin

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${GREEN}▸ ARIZE${NC} Claude Code Tracing Setup"
echo ""

# Detect settings file location
SETTINGS_FILE=".claude/settings.local.json"

# Ask for target
echo "Which backend do you want to use?"
echo ""
echo "  1) Phoenix (self-hosted, no Python required)"
echo "  2) Arize AX (cloud, requires Python)"
echo ""
read -p "Enter choice [1/2]: " choice

case "$choice" in
  1|phoenix|Phoenix)
    echo ""
    read -p "Phoenix endpoint [http://localhost:6006]: " phoenix_endpoint
    phoenix_endpoint="${phoenix_endpoint:-http://localhost:6006}"
    
    # Create settings
    mkdir -p .claude
    cat > "$SETTINGS_FILE" << EOF
{
  "env": {
    "PHOENIX_ENDPOINT": "$phoenix_endpoint",
    "ARIZE_TRACE_ENABLED": "true"
  }
}
EOF
    echo ""
    echo -e "${GREEN}✓${NC} Configured for Phoenix at $phoenix_endpoint"
    ;;
    
  2|arize|ax|AX)
    echo ""
    read -p "Arize API Key: " api_key
    read -p "Arize Space ID: " space_id
    
    if [[ -z "$api_key" || -z "$space_id" ]]; then
      echo "Error: API key and Space ID are required for Arize AX"
      exit 1
    fi
    
    # Create settings
    mkdir -p .claude
    cat > "$SETTINGS_FILE" << EOF
{
  "env": {
    "ARIZE_API_KEY": "$api_key",
    "ARIZE_SPACE_ID": "$space_id",
    "ARIZE_TRACE_ENABLED": "true"
  }
}
EOF
    echo ""
    echo -e "${GREEN}✓${NC} Configured for Arize AX"
    echo ""
    echo -e "${YELLOW}Note:${NC} Arize AX requires Python dependencies:"
    echo "  pip install opentelemetry-proto grpcio"
    ;;
    
  *)
    echo "Invalid choice. Run setup again."
    exit 1
    ;;
esac

echo ""
echo "Configuration saved to $SETTINGS_FILE"
echo ""
echo "Start a new Claude Code session to begin tracing!"
echo ""
