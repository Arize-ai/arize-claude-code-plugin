# Arize Claude Code Plugins

Official Claude Code plugins from Arize AI for enhanced observability and platform integration.

## What's Included

This repository contains the following plugins:

1. **[claude-code-tracing](#claude-code-tracing)** — Automatic tracing of Claude Code sessions to Arize AX or Phoenix
2. **[arize-platform](#arize-platform)** — Skills for managing datasets and working with the Arize AX CLI

## Installation

Install all plugins from the marketplace:

```bash
claude plugin add https://github.com/Arize-ai/arize-claude-code-plugin.git
```

This installs:
- `claude-code-tracing@arize-claude-plugin`
- `arize-platform@arize-claude-plugin`

---

# Claude Code Tracing

Trace your Claude Code sessions to [Arize AX](https://arize.com) or [Phoenix](https://github.com/Arize-ai/phoenix) with OpenInference spans.

## Features

- **9 Hooks** — Most comprehensive tracing coverage available
  - SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStop, Notification, PermissionRequest, SessionEnd
- **Dual Target Support** — Send traces to Arize AX (cloud) or Phoenix (self-hosted)
- **OpenInference Format** — Standard span format compatible with any OpenInference tool
- **Guided Setup Skill** — `/setup-claude-code-tracing` walks you through configuration
- **DX Features** — Dry run mode, verbose output, session summaries
- **Automatic Cost Tracking** — Phoenix/Arize calculate costs from token counts automatically
- **Minimal Dependencies**
  - Phoenix: Pure bash (`jq` + `curl` only)
  - Arize AX: Requires Python with `opentelemetry-proto` and `grpcio`

## Configuration

### Quick Setup

Configure tracing from within Claude Code:

```
/setup-claude-code-tracing
```

This walks you through choosing a backend (Phoenix or Arize AX), collecting credentials, writing the config, and validating the setup.

### Manual Configuration

Add to your project's `.claude/settings.local.json`:

**For Phoenix (self-hosted) — No Python required:**

```json
{
  "env": {
    "PHOENIX_ENDPOINT": "http://localhost:6006",
    "ARIZE_TRACE_ENABLED": "true"
  }
}
```

If your Phoenix instance requires authentication, add the API key:

```json
{
  "env": {
    "PHOENIX_ENDPOINT": "http://localhost:6006",
    "PHOENIX_API_KEY": "your-phoenix-api-key",
    "ARIZE_TRACE_ENABLED": "true"
  }
}
```

**For Arize AX (cloud) — Requires Python:**

First install dependencies:
```bash
pip install opentelemetry-proto grpcio
```

Then configure:
```json
{
  "env": {
    "ARIZE_API_KEY": "your-api-key",
    "ARIZE_SPACE_ID": "your-space-id",
    "ARIZE_TRACE_ENABLED": "true"
  }
}
```

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ARIZE_API_KEY` | For AX | - | Arize AX API key |
| `ARIZE_SPACE_ID` | For AX | - | Arize AX space ID |
| `PHOENIX_ENDPOINT` | For Phoenix | - | Phoenix collector URL |
| `PHOENIX_API_KEY` | No | - | Phoenix API key for authentication |
| `ARIZE_PROJECT_NAME` | No | workspace name | Project name in Arize/Phoenix |
| `ARIZE_TRACE_ENABLED` | No | `true` | Enable/disable tracing |
| `ARIZE_DRY_RUN` | No | `false` | Print spans instead of sending |
| `ARIZE_VERBOSE` | No | `false` | Enable verbose logging |
| `ARIZE_LOG_FILE` | No | `/tmp/arize-claude-code.log` | Log file path (set empty to disable) |

## Usage

Once installed and configured, tracing happens automatically. After each session, you'll see:

```
[arize] Session complete: 3 traces, 12 tools
[arize] View in Arize/Phoenix: session.id = abc123-def456-...
```

### Dry Run Mode

Test without sending data:

```bash
ARIZE_DRY_RUN=true claude
```

### Verbose Mode

See what's being captured:

```bash
ARIZE_VERBOSE=true claude
```

## Hooks Supported

| Hook | Description | Captured Data |
|------|-------------|---------------|
| `SessionStart` | Session begins | Session ID, project name, timestamps |
| `UserPromptSubmit` | User sends prompt | Trace ID, prompt preview, transcript position |
| `PreToolUse` | Before tool executes | Tool ID, start time |
| `PostToolUse` | After tool executes | Tool name, input, output, duration, tool-specific metadata |
| `Stop` | Claude finishes responding | Model, token counts, input/output text |
| `SubagentStop` | Subagent completes | Agent type, model, token counts, output |
| `Notification` | System notification | Title, message, notification type |
| `PermissionRequest` | Permission requested | Permission type, tool name |
| `SessionEnd` | Session closes | Trace count, tool count |

## Troubleshooting

### "jq is required but not installed"

Install jq:
- macOS: `brew install jq`
- Ubuntu: `sudo apt-get install jq`
- Fedora: `sudo dnf install jq`

### Traces not appearing

1. Check `ARIZE_TRACE_ENABLED` is `true`
2. Verify API key/endpoint is correct
3. Check the log file: `tail -f /tmp/arize-claude-code.log`
4. Run with `ARIZE_VERBOSE=true` to enable verbose logging
5. Run with `ARIZE_DRY_RUN=true` to test locally

### Viewing hook logs

Claude Code discards hook stderr, so verbose output isn't visible in the terminal. Logs are written to `/tmp/arize-claude-code.log` by default:

```bash
tail -f /tmp/arize-claude-code.log
```

To change the log location, set `ARIZE_LOG_FILE` in your settings. Set to empty string to disable file logging.

### Arize AX: "Python with opentelemetry not found"

Install the required Python packages:
```bash
pip install opentelemetry-proto grpcio
```

Note: Phoenix does not require Python — it uses the REST API directly.

---

# Arize Platform

Skills for working with the Arize AX platform, including CLI setup and dataset management.

## Features

- **CLI Setup** — Install and configure the Arize AX CLI
- **Dataset Management** — Create, list, export, and delete datasets
- **Multiple Profiles** — Support for dev/staging/prod environments
- **Environment Variable Management** — Persist credentials securely
- **ID Extraction** — Find and use dataset IDs programmatically

## Skills

### `/setup-arize-cli`

Install and configure the Arize AX CLI for interacting with the Arize AI platform.

**Use when:**
- Installing the `ax` CLI for the first time
- Setting up authentication and API keys
- Creating configuration profiles
- Switching between environments
- Troubleshooting CLI setup issues

**Key capabilities:**
- Interactive installation guide
- Simple and advanced configuration modes
- Environment variable persistence
- Shell completion setup
- Multi-profile management

### `/arize-datasets`

Manage datasets in Arize AI using the `ax` CLI.

**Use when:**
- Listing all datasets
- Getting dataset details by name or ID
- Creating datasets from CSV/JSON/Parquet files
- Exporting dataset data
- Deleting datasets
- Working with datasets across multiple environments

**Key capabilities:**
- Dataset CRUD operations
- Format conversion (JSON, CSV, Parquet)
- ID extraction by name
- Pagination for large result sets
- Profile-specific operations

## Usage

### Setting up the CLI

```bash
# Use the skill to guide you through setup
/setup-arize-cli

# Or install manually
pip install arize-ax-cli
ax config init
```

### Managing Datasets

```bash
# List all datasets
ax datasets list

# Create a dataset
ax datasets create --file data.csv --name "Training Data"

# Get dataset by ID
ax datasets get ds_abc123

# Export dataset
ax datasets get ds_abc123 --output csv > export.csv

# Delete dataset
ax datasets delete ds_abc123
```

For comprehensive guidance, use the `/arize-datasets` skill which includes:
- Finding dataset IDs by name
- Complete workflows and examples
- Troubleshooting common issues
- Scripting patterns with jq

---

## Uninstall

**Plugin marketplace:**

```bash
# Uninstall tracing plugin
/plugin uninstall claude-code-tracing@arize-claude-plugin

# Uninstall platform plugin
/plugin uninstall arize-platform@arize-claude-plugin

# Or uninstall all
claude plugin remove arize-claude-plugin
```

**Manual install (tracing only):**

```bash
cd arize-claude-code-plugin
./install.sh uninstall
```

## License

Apache-2.0

## Links

- [Arize AX](https://arize.com)
- [Phoenix](https://github.com/Arize-ai/phoenix)
- [OpenInference](https://github.com/Arize-ai/openinference)
- [Arize AX CLI](https://github.com/Arize-ai/arize-ax-cli)
