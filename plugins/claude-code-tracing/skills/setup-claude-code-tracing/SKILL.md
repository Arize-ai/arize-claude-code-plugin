---
name: setup-claude-code-tracing
description: Set up and configure Arize tracing for Claude Code sessions. Use when users want to set up tracing, configure Arize AX or Phoenix, create a new Arize project, get an API key, enable/disable tracing, or troubleshoot tracing issues. Triggers on "set up tracing", "configure Arize", "configure Phoenix", "enable tracing", "setup-claude-code-tracing", "create Arize project", "get Arize API key", or any request about connecting Claude Code to Arize or Phoenix for observability.
---

# Setup Tracing

Configure OpenInference tracing for Claude Code sessions to Arize AX (cloud) or Phoenix (self-hosted).

## How to Use This Skill

**This skill follows a decision tree workflow.** Start by asking the user where they are in the setup process:

1. **Do they already have credentials?**
   - ✅ Yes → Jump to [Configure Settings](#configure-settings)
   - ❌ No → Continue to step 2

2. **Which backend do they want to use?**
   - 🐦 Phoenix (self-hosted) → Go to [Set Up Phoenix](#set-up-phoenix)
   - ☁️ Arize AX (cloud) → Go to [Set Up Arize AX](#set-up-arize-ax)

3. **Are they troubleshooting?**
   - 🔧 Yes → Jump to [Troubleshoot](#troubleshoot)

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

Before configuring, ask the user:

**"Do you want to configure tracing globally or for this project only?"**
- **Globally** → `~/.claude/settings.json` (applies to all projects)
- **Project-local** → `.claude/settings.local.json` (applies only to this project)

**Recommendation**: Use project-local for different backends per project (e.g., dev Phoenix vs prod Arize).

### Ask the user for:

1. **Scope** (if not already determined): Global or project-local
2. **Backend choice**: Phoenix or Arize AX
3. **Credentials**:
   - Phoenix: endpoint URL (default: `http://localhost:6006`), optional API key
   - Arize AX: API key and Space ID
4. **Project name** (optional): defaults to workspace name

### Write the config

**Determine the config file:**
- Global: `~/.claude/settings.json`
- Project-local: `.claude/settings.local.json` (create directory if needed: `mkdir -p .claude`)

Read the file (or create `{}` if it doesn't exist), then merge env vars into the `"env"` object.

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

**Example workflow:**
```bash
# For project-local
mkdir -p .claude
echo '{}' > .claude/settings.local.json
# Then use jq or editor to add env vars
```

### Validate

**Phoenix**: Run `curl -sf <endpoint>/v1/traces >/dev/null` to check connectivity. Warn if unreachable but note it may just not be running yet.

**Arize AX**: Run `python3 -c "import opentelemetry; import grpc"` to check dependencies. If it fails, tell the user to run `pip install opentelemetry-proto grpcio`.

### Confirm

Tell the user:
- Configuration saved to the chosen file:
  - Global: `~/.claude/settings.json`
  - Project-local: `.claude/settings.local.json`
- Restart the Claude Code session for tracing to take effect
- After restarting, traces will appear in their Phoenix UI or Arize AX dashboard under the project name
- Mention `ARIZE_DRY_RUN=true` to test without sending data
- Mention `ARIZE_VERBOSE=true` for debug output
- Logs are written to `/tmp/arize-claude-code.log`

**Note**: Project-local settings override global settings for the same variables.

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
