---
name: setup-tracing
description: Set up and configure Arize tracing for Claude Code sessions. Use when users want to set up tracing, configure Arize AX or Phoenix, create a new Arize project, get an API key, enable/disable tracing, or troubleshoot tracing issues. Triggers on "set up tracing", "configure Arize", "configure Phoenix", "enable tracing", "setup-tracing", "create Arize project", "get Arize API key", or any request about connecting Claude Code to Arize or Phoenix for observability.
---

# Setup Tracing

Configure OpenInference tracing for Claude Code sessions to Arize AX (cloud) or Phoenix (self-hosted).

## Decision Tree

1. **User already has credentials** → Go to [Configure Local Project](#configure-local-project)
2. **User needs to set up Phoenix** → Go to [Set Up Phoenix](#set-up-phoenix)
3. **User needs to create an Arize AX project** → Go to [Set Up Arize AX](#set-up-arize-ax)
4. **User wants to troubleshoot** → Go to [Troubleshoot](#troubleshoot)

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

Then proceed to [Configure Local Project](#configure-local-project) with `PHOENIX_ENDPOINT=http://localhost:6006`.

## Set Up Arize AX

Arize AX is a cloud platform. Users need an account, a space, and an API key.

### 1. Create an account

If the user doesn't have an Arize account, direct them to:
- Sign up at https://app.arize.com/auth/join

### 2. Get Space ID and API key

Walk the user through finding their credentials:
1. Log in at https://app.arize.com
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

Then proceed to [Configure Local Project](#configure-local-project).

## Configure Settings

Add tracing env vars to `~/.claude/settings.json` — the same file where the plugin's hooks are configured. Preserve all existing settings (hooks, enabledPlugins, etc.) — only add/update keys under `"env"`.

### Ask the user for:

1. **Backend choice** (if not already determined): Phoenix or Arize AX
2. **Credentials**:
   - Phoenix: endpoint URL (default: `http://localhost:6006`), optional API key
   - Arize AX: API key and Space ID
3. **Project name** (optional): defaults to `claude-code`

### Write the config

Read `~/.claude/settings.json`, then merge the appropriate env vars into the existing `"env"` object.

**Phoenix:**
```json
{
  "env": {
    "PHOENIX_ENDPOINT": "<endpoint>",
    "ARIZE_TRACE_ENABLED": "true"
  }
}
```

If the user has a Phoenix API key, also set `"PHOENIX_API_KEY": "<key>"`.

**Arize AX:**
```json
{
  "env": {
    "ARIZE_API_KEY": "<key>",
    "ARIZE_SPACE_ID": "<space-id>",
    "ARIZE_TRACE_ENABLED": "true"
  }
}
```

If a custom project name was provided, also set `"ARIZE_PROJECT_NAME": "<name>"`.

### Validate

**Phoenix**: Run `curl -sf <endpoint>/v1/traces >/dev/null` to check connectivity. Warn if unreachable but note it may just not be running yet.

**Arize AX**: Run `python3 -c "import opentelemetry; import grpc"` to check dependencies. If it fails, tell the user to run `pip install opentelemetry-proto grpcio`.

### Confirm

Tell the user:
- Configuration saved to `~/.claude/settings.json` alongside hook config
- Restart the Claude Code session for tracing to take effect
- After restarting, traces will appear in their Phoenix UI or Arize AX dashboard under the project name
- Mention `ARIZE_DRY_RUN=true` to test without sending data
- Mention `ARIZE_VERBOSE=true` for debug output
- Logs are written to `/tmp/arize-claude-code.log`

## Troubleshoot

Common issues and fixes:

| Problem | Fix |
|---------|-----|
| Traces not appearing | Check `ARIZE_TRACE_ENABLED` is `"true"` in `~/.claude/settings.json` |
| Phoenix unreachable | Verify Phoenix is running: `curl -sf <endpoint>/v1/traces` |
| "Python with opentelemetry not found" | Run `pip install opentelemetry-proto grpcio` |
| No output in terminal | Hook stderr is discarded by Claude Code; check `/tmp/arize-claude-code.log` |
| Want to test without sending | Set `ARIZE_DRY_RUN` to `"true"` in env config |
| Want verbose logging | Set `ARIZE_VERBOSE` to `"true"` in env config |
| Wrong project name | Set `ARIZE_PROJECT_NAME` in env config (default: `claude-code`) |
