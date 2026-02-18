---
name: setup-arize-cli
description: Install and configure the Arize AX CLI for interacting with the Arize AI platform. Use when users want to install the ax CLI, set up authentication, create configuration profiles, switch between profiles, or troubleshoot CLI setup issues. Triggers on "install ax", "setup arize cli", "configure ax", "ax config", "create profile", or any request about getting started with the Arize AX CLI.
---

# Setup Arize AX CLI

Install and configure the Arize AX CLI for streamlined interaction with the Arize AI platform.

## What is the Arize AX CLI?

The Arize AX CLI is the official command-line tool for Arize AI that enables users to:
- Manage datasets (create, list, update, delete)
- Organize ML projects
- Export data in multiple formats (JSON, CSV, Parquet)
- Maintain multiple configuration profiles for different environments

## Workflow

When a user asks to set up the CLI, follow these steps exactly:

### Step 1: Check if installed

```bash
ax --version 2>&1 || echo "NOT_INSTALLED"
```

### Step 2: Install if needed

If not installed, use `pipx` (recommended for CLI tools, avoids externally-managed-environment errors on macOS/Homebrew):

```bash
# Install pipx if not available
brew install pipx 2>/dev/null || pip3 install --user pipx
pipx ensurepath

# Install the CLI
pipx install arize-ax-cli
```

If `pipx` is not an option, fall back to:
```bash
pip3 install arize-ax-cli
```

Verify installation:
```bash
ax --version
```

### Step 3: Collect configuration from user

Ask the user for exactly three things using AskUserQuestion:

1. **API Key** — Their Arize API key (found at https://app.arize.com → Settings → API Keys)
   - Options: "Use env var $ARIZE_API_KEY" or "Other" (to paste a key)
2. **Profile Name** — Name for this config profile (default: `default`)
   - Options: "default (Recommended)", or "Other" (to enter a custom name)
3. **Output Format** — Default output format
   - Options: "table (Recommended)", "json", "csv", "parquet"

### Step 4: Write config directly

**Important**: Do NOT run `ax config init` — it uses interactive arrow-key prompts that cannot be automated in a non-interactive shell. Instead, write the config file directly.

#### Config file locations

The CLI uses TOML format with these paths (per [manager.py](https://github.com/Arize-ai/arize-ax-cli/blob/main/src/ax/config/manager.py)):
- **Default config**: `~/.arize/config.toml`
- **Named profiles**: `~/.arize/profiles/{profile_name}.toml`
- **Active profile marker**: `~/.arize/.active_profile`

```bash
# Ensure directories exist
mkdir -p ~/.arize/profiles
```

#### Config schema

The config is validated by a Pydantic model with `extra = "forbid"` (per [schema.py](https://github.com/Arize-ai/arize-ax-cli/blob/main/src/ax/config/schema.py)). Only include sections with non-default values — empty values are stripped on save.

Valid top-level sections and all fields (per [schema.py](https://github.com/Arize-ai/arize-ax-cli/blob/main/src/ax/config/schema.py)):

| Section | Field | Default | When to set |
|---|---|---|---|
| `[profile]` | `name` | `"default"` | Always include. Use a custom name for multi-profile setups. |
| `[auth]` | `api_key` | (required) | **Always include.** Only required field. Use `"${ARIZE_API_KEY}"` to reference env var. |
| `[routing]` | `region` | `""` | Only if user needs a specific region. Valid: `ca-central-1a`, `eu-west-1a`, `us-central-1a`, `us-east-1b`. |
| `[routing]` | `single_host` | `""` | Only for on-premise deployments. |
| `[routing]` | `single_port` | `""` | Only for on-premise deployments (pair with `single_host`). |
| `[routing]` | `base_domain` | `""` | Only for Private Connect deployments. |
| `[routing]` | `api_host` | `"api.arize.com"` | Only for custom endpoint overrides. |
| `[routing]` | `api_scheme` | `"https"` | Only for custom endpoint overrides. |
| `[routing]` | `otlp_host` | `"otlp.arize.com"` | Only for custom endpoint overrides. |
| `[routing]` | `otlp_scheme` | `"https"` | Only for custom endpoint overrides. |
| `[routing]` | `flight_host` | `"flight.arize.com"` | Only for custom endpoint overrides. |
| `[routing]` | `flight_port` | `"443"` | Only for custom endpoint overrides. |
| `[routing]` | `flight_scheme` | `"grpc+tls"` | Only for custom endpoint overrides. |
| `[transport]` | `stream_max_workers` | `8` | Only for performance tuning. |
| `[transport]` | `stream_max_queue_bound` | `5000` | Only for performance tuning. |
| `[transport]` | `pyarrow_max_chunksize` | `10000` | Only for performance tuning. |
| `[transport]` | `max_http_payload_size_mb` | `8` | Only for performance tuning. |
| `[security]` | `request_verify` | `true` | Only set to `false` for self-signed certs (on-premise). |
| `[storage]` | `directory` | `"~/.arize"` | Only to change cache location. |
| `[storage]` | `cache_enabled` | `true` | Only to disable caching. |
| `[output]` | `format` | `"table"` | Always include. Options: `table`, `json`, `csv`, `parquet`. |

**For most users, only `[profile]`, `[auth]`, and `[output]` are needed.** Omit all other sections — defaults work out of the box.

**Routing constraint**: Only one routing strategy is allowed — set `region`, `single_host`/`single_port`, or `base_domain`, not a combination. Omit `[routing]` entirely for default behavior.

#### Minimal config example

For the default profile, write `~/.arize/config.toml`:

```toml
[profile]
name = "default"

[auth]
api_key = "${ARIZE_API_KEY}"

[output]
format = "table"
```

For a named profile (e.g., "production"), write `~/.arize/profiles/production.toml`:

```toml
[profile]
name = "production"

[auth]
api_key = "${ARIZE_API_KEY}"

[output]
format = "json"
```

Environment variables are expanded at load time using `${VAR}` or `${VAR:default}` syntax.

### Step 5: Optionally persist credentials in Claude Code settings

Offer to save env vars to `.claude/settings.local.json` so they're available in Claude Code sessions:

If the user wants to persist, read the existing file (or create `{}` if it doesn't exist), then merge `ARIZE_API_KEY` into the `"env"` object:

```json
{
  "env": {
    "ARIZE_API_KEY": "your-api-key-here"
  }
}
```

Create the directory if needed: `mkdir -p .claude`

**Note**: If `settings.local.json` already exists, merge into the existing `"env"` object — other settings may already be configured.

### Step 6: Verify

```bash
ax config show
```

## Managing Configuration Profiles

### List All Profiles
```bash
ax config list
```

### View Current Profile
```bash
ax config show
```

To see expanded values (with environment variables resolved):
```bash
ax config show --expand
```

### Switch Between Profiles
```bash
ax config use <profile-name>
```

### Delete a Profile
```bash
ax config delete <profile-name>
```

## Shell Completion

Enable tab completion for better UX:

```bash
# Bash
ax --install-completion bash

# Zsh
ax --install-completion zsh

# Fish
ax --install-completion fish
```

## Troubleshooting

### "ax: command not found"

The CLI isn't installed or not in PATH:
1. If installed via pipx: `pipx ensurepath` and restart shell
2. Try reinstalling: `pipx install --force arize-ax-cli`
3. Check PATH includes `~/.local/bin`

### "externally-managed-environment" error during install

This happens on macOS with Homebrew Python. Use `pipx` instead of `pip`:
```bash
brew install pipx
pipx ensurepath
pipx install arize-ax-cli
```

### "Profile 'default' not found"

The config file doesn't exist or is malformed. Write `~/.arize/config.toml` directly with the correct TOML format (see Step 4).

### "Invalid region" error

Region values must be one of: `ca-central-1a`, `eu-west-1a`, `us-central-1a`, `us-east-1b`. If unsure, omit the `[routing]` section entirely — the CLI will use default routing.

### "Authentication failed" or "Invalid API key"

1. Verify API key is correct: `ax config show --expand`
2. Generate a new API key at https://app.arize.com → Settings → API Keys
3. Update `~/.arize/config.toml` with the new key

### "Environment variable not found"

If the config references `${ARIZE_API_KEY}` but it's not set:
1. Set it in your shell: `export ARIZE_API_KEY="your-key"`
2. Or add it to `.claude/settings.local.json` under `"env"`
3. Restart the Claude Code session for new env vars to take effect

## Next Steps

After setup, users can:
- Use `/arize-datasets` skill to manage datasets
- Use `/arize-projects` skill to manage projects∂∂
- Run `ax --help` to explore all commands
- Visit https://docs.arize.com for full documentation
