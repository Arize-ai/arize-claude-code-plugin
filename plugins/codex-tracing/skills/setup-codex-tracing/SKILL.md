---
name: setup-codex-tracing
description: Set up and configure Arize tracing for OpenAI Codex CLI sessions. Use when users want to set up Codex tracing, configure Arize AX or Phoenix for Codex, enable/disable tracing, or troubleshoot Codex tracing issues. Triggers on "set up codex tracing", "configure Arize for Codex", "configure Phoenix for Codex", "enable codex tracing", "setup-codex-tracing", or any request about connecting Codex to Arize or Phoenix for observability.
---

# Setup Codex Tracing

Configure OpenInference tracing for OpenAI Codex CLI sessions to Arize AX (cloud) or Phoenix (self-hosted).

## Architecture Overview

Codex tracing uses two complementary mechanisms:

1. **Notify hook** — A bash script registered via `notify` in `~/.codex/config.toml`. Fires on `agent-turn-complete` events and creates OpenInference LLM spans with user input, assistant output, and session tracking.

2. **Native OTLP export** (optional) — Codex has built-in OpenTelemetry support configured via the `[otel]` section in `config.toml`. Sends rich internal events (`codex.tool_decision`, `codex.tool_result`, `codex.api_request`, etc.) directly to your backend.

Environment variables are stored in `~/.codex/arize-env.sh` and auto-sourced by the notify script — no shell profile changes needed.

## How to Use This Skill

**This skill follows a decision tree workflow.** Start by asking the user where they are in the setup process:

1. **Do they already have credentials?**
   - Yes → Jump to [Configure Codex](#configure-codex)
   - No → Continue to step 2

2. **Which backend do they want to use?**
   - Phoenix (self-hosted) → Go to [Set Up Phoenix](#set-up-phoenix)
   - Arize AX (cloud) → Go to [Set Up Arize AX](#set-up-arize-ax)

3. **Are they troubleshooting?**
   - Yes → Jump to [Troubleshoot](#troubleshoot)

**Important:** Only follow the relevant path for the user's needs. Don't go through all sections.

## Set Up Phoenix

Phoenix is self-hosted and requires no Python dependencies for tracing.

### Install Phoenix

Ask if they already have Phoenix running. If not, walk through:

```bash
# Option A: pip
pip install arize-phoenix && phoenix serve

# Option B: Docker
docker run -p 6006:6006 arizephoenix/phoenix:latest
```

Phoenix UI will be available at `http://localhost:6006`. Confirm it's running:

```bash
curl -sf http://localhost:6006/v1/traces >/dev/null && echo "Phoenix is running" || echo "Phoenix not reachable"
```

Then proceed to [Configure Codex](#configure-codex) with `PHOENIX_ENDPOINT=http://localhost:6006`.

## Set Up Arize AX

Arize AX is available as a SaaS platform or as an on-prem deployment. Users need an account, a space, and an API key.

**First, ask the user: "Are you using the Arize SaaS platform or an on-prem instance?"**

- **SaaS** → Uses the default endpoint (`otlp.arize.com:443`). Continue below.
- **On-prem** → The user will need to provide their custom OTLP endpoint (e.g., `otlp.mycompany.arize.com:443`). Ask for it and note it for the configure step where it will be set as `ARIZE_OTLP_ENDPOINT`.

### 1. Create an account

If the user doesn't have an Arize account:
- **SaaS**: Sign up at https://app.arize.com/auth/join
- **On-prem**: Contact their administrator for access

### 2. Get Space ID and API key

Walk the user through finding their credentials:
1. Log in to their Arize instance (https://app.arize.com for SaaS, or their on-prem URL)
2. Click **Settings** (gear icon) in the left sidebar
3. The **Space ID** is shown on the Space Settings page
4. Go to the **API Keys** tab
5. Click **Create API Key** or copy an existing one

Both `ARIZE_API_KEY` and `ARIZE_SPACE_ID` are required.

### 3. Install Python dependencies

Arize AX uses gRPC, which requires Python:

```bash
pip install opentelemetry-proto grpcio
```

Verify:
```bash
python3 -c "import opentelemetry; import grpc; print('OK')"
```

Then proceed to [Configure Codex](#configure-codex).

## Configure Codex

This section configures three things:
1. **Environment variables** in `~/.codex/arize-env.sh`
2. **Notify hook** in `~/.codex/config.toml`
3. **Native OTLP export** (optional) in `~/.codex/config.toml`

### Determine the plugin path

Ask the user: **"Where is the codex-tracing plugin located?"**

Common locations:
- If cloned: `./arize-claude-code-plugin/plugins/codex-tracing`
- If installed via Claude Code CLI: `~/.claude/plugins/cache/arize-claude-plugin/codex-tracing/1.0.0`

Store this as `PLUGIN_PATH` for the notify hook config.

### Step 1: Write the environment file

Create `~/.codex/arize-env.sh` with the user's credentials. The notify script auto-sources this file on each invocation.

**Phoenix:**
```bash
cat > ~/.codex/arize-env.sh << 'EOF'
export ARIZE_TRACE_ENABLED=true
export PHOENIX_ENDPOINT=http://localhost:6006
export ARIZE_PROJECT_NAME=codex
EOF
chmod 600 ~/.codex/arize-env.sh
```

If the user has a Phoenix API key, also add `export PHOENIX_API_KEY="<key>"`.

**Arize AX:**
```bash
cat > ~/.codex/arize-env.sh << 'EOF'
export ARIZE_TRACE_ENABLED=true
export ARIZE_API_KEY=<user's key>
export ARIZE_SPACE_ID=<user's space id>
export ARIZE_PROJECT_NAME=codex
EOF
chmod 600 ~/.codex/arize-env.sh
```

If the user has a custom OTLP endpoint (on-prem), also add `export ARIZE_OTLP_ENDPOINT="<host:port>"`.

If the user wants a custom project name, update `ARIZE_PROJECT_NAME`.

### Step 2: Add the notify hook to config.toml

Read `~/.codex/config.toml`. Add the `notify` line at the top level (NOT inside any `[section]`):

```toml
notify = ["bash", "<PLUGIN_PATH>/hooks/notify.sh"]
```

**Important:** If `notify` already exists in the config, update the existing line. If it's set to something else (non-Arize), warn the user that Codex only supports a single `notify` command — they'll need to choose or create a wrapper script that calls both.

Use the Edit tool to add or update the notify line. Place it after any top-level key-value pairs but before any `[section]` headers.

### Step 3 (optional): Enable native OTLP export

Ask the user: **"Do you also want to enable Codex's native OpenTelemetry export? This sends richer events like tool decisions, tool results, and API request metrics in addition to the per-turn LLM spans."**

If yes, add an `[otel]` section to `~/.codex/config.toml`:

**Phoenix:**
```toml
[otel]
exporter = { otlp-http = { endpoint = "http://localhost:6006/v1/traces", protocol = "binary" } }
```

**Arize AX (SaaS):**
```toml
[otel]
exporter = { otlp-grpc = { endpoint = "https://otlp.arize.com:443", headers = { "authorization" = "Bearer <API_KEY>", "space_id" = "<SPACE_ID>" } } }
```

**Arize AX (on-prem):**
```toml
[otel]
exporter = { otlp-grpc = { endpoint = "https://<CUSTOM_ENDPOINT>", headers = { "authorization" = "Bearer <API_KEY>", "space_id" = "<SPACE_ID>" } } }
```

**Important:** If `[otel]` already exists, warn the user and show them what to update rather than duplicating the section.

### Validate

After writing the config, validate:

1. **Check config.toml is valid:**
```bash
cat ~/.codex/config.toml
```
Visually confirm the `notify` line is at the top level and any `[otel]` section is properly formatted.

2. **Check env file:**
```bash
source ~/.codex/arize-env.sh && echo "ARIZE_TRACE_ENABLED=$ARIZE_TRACE_ENABLED"
```

3. **Phoenix connectivity** (if using Phoenix):
```bash
source ~/.codex/arize-env.sh && curl -sf ${PHOENIX_ENDPOINT}/v1/traces >/dev/null && echo "Phoenix reachable" || echo "Phoenix not reachable"
```

4. **Arize AX dependencies** (if using Arize):
```bash
python3 -c "import opentelemetry; import grpc; print('Dependencies OK')"
```

5. **Dry run test:**
```bash
source ~/.codex/arize-env.sh && ARIZE_DRY_RUN=true bash <PLUGIN_PATH>/hooks/notify.sh '{"type":"agent-turn-complete","thread-id":"test-123","turn-id":"turn-1","cwd":"/tmp","input-messages":"hello","last-assistant-message":"hi there"}'
```
Should print: `[arize] DRY RUN:` followed by the span name.

### Confirm

Tell the user:
- Configuration saved to `~/.codex/config.toml` and `~/.codex/arize-env.sh`
- No restart needed — the notify hook fires on the next Codex turn
- Traces will appear in their Phoenix UI or Arize AX dashboard
- Mention `ARIZE_DRY_RUN=true` to test without sending data
- Mention `ARIZE_VERBOSE=true` for debug output
- Logs are written to `/tmp/arize-codex.log`

### Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ARIZE_API_KEY` | For AX | - | Arize AX API key |
| `ARIZE_SPACE_ID` | For AX | - | Arize AX space ID |
| `ARIZE_OTLP_ENDPOINT` | No | `otlp.arize.com:443` | OTLP gRPC endpoint (on-prem Arize) |
| `PHOENIX_ENDPOINT` | For Phoenix | `http://localhost:6006` | Phoenix collector URL |
| `PHOENIX_API_KEY` | No | - | Phoenix API key for auth |
| `ARIZE_PROJECT_NAME` | No | `codex` | Project name in Arize/Phoenix |
| `ARIZE_TRACE_ENABLED` | No | `true` | Enable/disable tracing |
| `ARIZE_DRY_RUN` | No | `false` | Print spans instead of sending |
| `ARIZE_VERBOSE` | No | `false` | Enable verbose logging |
| `ARIZE_LOG_FILE` | No | `/tmp/arize-codex.log` | Log file path |

## Troubleshoot

Common issues and fixes:

| Problem | Fix |
|---------|-----|
| Traces not appearing | Check `ARIZE_TRACE_ENABLED` is `true` in `~/.codex/arize-env.sh` |
| Notify hook not firing | Verify `notify` line in `~/.codex/config.toml` points to correct path |
| "jq required" error | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |
| Phoenix unreachable | Verify Phoenix is running: `curl -sf <endpoint>/v1/traces` |
| "Python with opentelemetry not found" | Run `pip install opentelemetry-proto grpcio` |
| No output in terminal | Notify runs in background; check `/tmp/arize-codex.log` |
| Want to test without sending | Set `ARIZE_DRY_RUN=true` in env or `export ARIZE_DRY_RUN=true` |
| Want verbose logging | Set `ARIZE_VERBOSE=true` in env or `export ARIZE_VERBOSE=true` |
| Wrong project name | Set `ARIZE_PROJECT_NAME` in `~/.codex/arize-env.sh` (default: `codex`) |
| Existing notify hook | Codex supports only one `notify` — create a wrapper script that calls both |
| Stale state files | Run: `rm -rf ~/.arize-codex/state_*.json` |
| Native OTLP not sending | Check `[otel]` section in config.toml; verify endpoint and headers |
