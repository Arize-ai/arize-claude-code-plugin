# Arize Claude Code Tracing Plugin

Trace your Claude Code sessions to [Arize AX](https://arize.com) or [Phoenix](https://github.com/Arize-ai/phoenix) with OpenInference spans.

## Features

- **9 Hooks** — Most comprehensive tracing coverage available
  - SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStop, Notification, PermissionRequest, SessionEnd
- **Dual Target Support** — Send traces to Arize AX (cloud) or Phoenix (self-hosted)
- **OpenInference Format** — Standard span format compatible with any OpenInference tool
- **DX Features** — Dry run mode, verbose output, session summaries
- **Automatic Cost Tracking** — Phoenix/Arize calculate costs from token counts automatically
- **Minimal Dependencies**
  - Phoenix: Pure bash (`jq` + `curl` only)
  - Arize AX: Requires Python with `opentelemetry-proto` and `grpcio`

## Quick Start

### Option 1: Plugin Marketplace (Recommended)

From within Claude Code:

```bash
# Add the Arize marketplace
/plugin marketplace add Arize-ai/arize-claude-code-plugin

# Install the tracing plugin
/plugin install arize-tracing@arize-plugins
```

Or browse and install interactively via `/plugin` > **Discover**.

### Option 2: Manual Installation

```bash
git clone https://github.com/Arize-ai/arize-claude-code-plugin
cd arize-claude-code-plugin
./install.sh
```

### Configuration

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

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ARIZE_API_KEY` | For AX | - | Arize AX API key |
| `ARIZE_SPACE_ID` | For AX | - | Arize AX space ID |
| `PHOENIX_ENDPOINT` | For Phoenix | - | Phoenix collector URL |
| `ARIZE_PROJECT_NAME` | No | workspace name | Project name in Arize/Phoenix |
| `ARIZE_TRACE_ENABLED` | No | `true` | Enable/disable tracing |
| `ARIZE_DRY_RUN` | No | `false` | Print spans instead of sending |
| `ARIZE_VERBOSE` | No | `false` | Enable verbose logging |
| `ARIZE_LOG_FILE` | No | `/tmp/arize-claude-code.log` | Log file path (set empty to disable) |

## Usage

Once installed and configured, tracing happens automatically. After each session, you'll see:

```
[arize] Session complete: 3 traces, 12 tool calls, ~2,450 tokens
[arize] Trace: https://app.arize.com/spaces/xxx/traces/yyy
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
| `SessionStart` | Session begins | Session ID, project name, workspace |
| `UserPromptSubmit` | User sends prompt | Trace number, prompt preview |
| `PreToolUse` | Before tool executes | Tool name, start time |
| `PostToolUse` | After tool executes | Tool name, input, output, duration |
| `Stop` | Claude finishes responding | Token counts, model |
| `SubagentStop` | Subagent completes | Subagent activity |
| `Notification` | System notification | Message, level |
| `PermissionRequest` | Permission requested | Permission type |
| `SessionEnd` | Session closes | Summary stats, total tokens |

## Uninstall

```bash
./install.sh uninstall
```

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

### Permission errors (manual install)

Make sure the hook scripts are executable:

```bash
chmod +x ~/.claude/hooks/*.sh
```

## License

Apache-2.0

## Links

- [Arize AX](https://arize.com)
- [Phoenix](https://github.com/Arize-ai/phoenix)
- [OpenInference](https://github.com/Arize-ai/openinference)
