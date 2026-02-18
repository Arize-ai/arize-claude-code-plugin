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

## Installation

### Step 1: Install via pip

```bash
pip install arize-ax-cli
```

Verify installation:
```bash
ax --version
```

### Step 2: Initial Configuration

Run the interactive setup:
```bash
ax config init
```

This will guide the user through two configuration modes:

#### Simple Mode (Recommended)

Best for most users. The CLI will prompt for:

1. **API Key** (required) - The user's Arize API key
   - Find at: https://app.arize.com → Settings → API Keys
   - The CLI auto-detects `ARIZE_API_KEY` environment variable if set

2. **Space ID** (required) - The user's Arize space identifier
   - Find at: https://app.arize.com → Settings → Space Settings
   - The CLI auto-detects `ARIZE_SPACE_ID` environment variable if set

3. **Region** (optional) - Choose the Arize region:
   - `us` - US region (most common)
   - `eu` - EU region
   - The CLI auto-detects `ARIZE_REGION` if set

4. **Output Format** - Default output format:
   - `table` - Human-readable tables (recommended for interactive use)
   - `json` - JSON output (good for scripting)
   - `csv` - CSV format
   - `parquet` - Parquet format

5. **Profile Name** - Name for this configuration (default: `default`)

#### Advanced Mode

For on-premise deployments, Private Connect, or custom configurations. Provides control over:
- Routing strategies
- Transport optimization
- Security settings
- Custom endpoints
- Storage configuration

Only use if the user specifically needs advanced configuration.

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

Example:
```bash
ax config use production
ax config use staging
```

### Delete a Profile
```bash
ax config delete <profile-name>
```

## Configuration Files

Configurations are stored at:
- **Linux/macOS**: `~/.arize/config/`
- **Windows**: `%USERPROFILE%\.arize\config\`

Each profile has its own configuration file named `<profile-name>.yaml`.

## Using Environment Variables

The CLI configuration supports two approaches:

### Approach 1: Store Values Directly in Config
The `ax config init` process stores API keys and credentials directly in `~/.arize/config/<profile>.yaml`.

**Pros**: No need to set environment variables each session
**Cons**: Credentials stored in plaintext files

### Approach 2: Reference Environment Variables
Store references to environment variables in the config instead:

```yaml
api_key: ${ARIZE_API_KEY}
space_id: ${ARIZE_SPACE_ID}
```

**Pros**: More secure, easier to rotate credentials, portable across machines
**Cons**: Must set environment variables before using the CLI

During setup, `ax config init` will automatically detect and offer to use existing:
- `ARIZE_API_KEY`
- `ARIZE_SPACE_ID`

### CLI Environment Variable Mapping

The following environment variables map to CLI config fields per [setup.py](https://github.com/Arize-ai/arize-ax-cli/blob/main/src/ax/config/setup.py) and [schema.py](https://github.com/Arize-ai/arize-ax-cli/blob/main/src/ax/config/schema.py):

| Environment Variable | CLI Config Field | Required | Default |
|---|---|---|---|
| `ARIZE_API_KEY` | `api_key` | Yes | — |
| `ARIZE_SPACE_ID` | `space_id` | Yes | — |
| `ARIZE_REGION` | `region` | No | `""` (use routing fields below if not set) |
| `ARIZE_SINGLE_HOST` | `single_host` | No | `""` |
| `ARIZE_SINGLE_PORT` | `single_port` | No | `""` |
| `ARIZE_BASE_DOMAIN` | `base_domain` | No | `""` |
| `ARIZE_API_HOST` | `api_host` | No | `api.arize.com` |
| `ARIZE_API_SCHEME` | `api_scheme` | No | `https` |
| `ARIZE_OTLP_HOST` | `otlp_host` | No | `otlp.arize.com` |
| `ARIZE_OTLP_SCHEME` | `otlp_scheme` | No | `https` |
| `ARIZE_FLIGHT_HOST` | `flight_host` | No | `flight.arize.com` |
| `ARIZE_FLIGHT_PORT` | `flight_port` | No | `443` |
| `ARIZE_FLIGHT_SCHEME` | `flight_scheme` | No | `grpc+tls` |

**Routing note**: Only one routing strategy is allowed — set `region`, `single_host`/`single_port`, or `base_domain`, not a combination.

### Persisting Environment Variables in Claude Code Settings

Optionally, credentials can be persisted for Claude sessions via the project's `.claude/settings.local.json` file. This makes them available to both Claude and the AX CLI without modifying shell profiles.

If the user wants to persist credentials, read the existing file (or create `{}` if it doesn't exist), then merge the `ARIZE_*` env vars into the `"env"` object. Only include the variables the user provides:

```json
{
  "env": {
    "ARIZE_API_KEY": "your-api-key-here",
    "ARIZE_SPACE_ID": "your-space-id-here"
  }
}
```

Create the directory and file if needed:
```bash
mkdir -p .claude
# Then read/merge env vars into .claude/settings.local.json
```

**Note**: If a `settings.local.json` already exists, merge into the existing `"env"` object rather than overwriting the file — other settings (hooks, tracing, etc.) may already be configured.

**Recommendation**: Use `settings.local.json` for project-specific credentials. This keeps them out of shell profiles and scoped to the project.

## Shell Completion

Enable tab completion for better UX:

```bash
# Bash
ax --install-completion bash

# Zsh
ax --install-completion zsh

# Fish
ax --install-completion fish

# PowerShell
ax --install-completion powershell
```

## Verification

After setup, verify everything works:

```bash
# Check version
ax --version

# View configuration
ax config show

# Test with a simple command
ax datasets list
```

## Troubleshooting

### "ax: command not found"

The CLI isn't installed or not in PATH:
1. Verify installation: `pip show arize-ax-cli`
2. Try reinstalling: `pip install --upgrade arize-ax-cli`
3. Check if pip's bin directory is in PATH

### "Authentication failed" or "Invalid API key"

1. Verify API key is correct:
   ```bash
   ax config show --expand
   ```
2. Generate a new API key at https://app.arize.com
3. Update configuration:
   ```bash
   ax config init
   ```

### "Region not found" or Connection errors

1. Check region setting:
   ```bash
   ax config show
   ```
2. Verify network connectivity to Arize services
3. For on-premise: Use advanced mode to configure custom endpoints

### Cannot switch profiles

1. List available profiles:
   ```bash
   ax config list
   ```
2. Ensure the profile name is correct (case-sensitive)
3. Create the profile if it doesn't exist:
   ```bash
   ax config init
   ```

### "Environment variable not found" or Config uses ${ARIZE_API_KEY}

If the config references environment variables that aren't set:

1. Check if environment variables are set in `.claude/settings.local.json`:
   ```bash
   cat .claude/settings.local.json
   ```
2. If missing, add them to the `"env"` object in `.claude/settings.local.json`:
   ```json
   {
     "env": {
       "ARIZE_API_KEY": "your-api-key",
       "ARIZE_SPACE_ID": "your-space-id"
     }
   }
   ```
3. Restart the Claude Code session for the new env vars to take effect
4. Verify with `ax config show --expand` to see resolved values

## Next Steps

After setup, users can:
- Use `/arize-datasets` skill to manage datasets
- Run `ax datasets list` to see available datasets
- Run `ax --help` to explore all commands
- Visit https://docs.arize.com for full documentation

## Workflow

When a user asks to set up the CLI:

1. **Check if installed**: Run `ax --version`
2. **If not installed**: Run `pip install arize-ax-cli`
3. **Optionally persist credentials**: Offer to save env vars to `.claude/settings.local.json`
   - If the user wants to persist, read the existing file (or create `{}` if it doesn't exist)
   - Merge only the provided variables (e.g. `ARIZE_API_KEY`, `ARIZE_SPACE_ID`) into the `"env"` object
   - Create the `.claude` directory if needed: `mkdir -p .claude`
4. **Configure**: Run `ax config init` (use simple mode unless user specifies otherwise)
5. **Verify**: Run `ax config show` and `ax datasets list` to confirm setup
6. **Enable completion** (optional): Offer to install shell completion

If user needs multiple profiles (e.g., dev/staging/prod):
1. Create first profile: `ax config init` (name it appropriately)
2. Create additional profiles: `ax config init` (use different names)
3. Show how to switch: `ax config use <profile-name>`
4. Consider using environment variables with different variable names per environment
