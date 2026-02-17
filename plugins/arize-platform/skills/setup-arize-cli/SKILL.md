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

1. **API Key** - The user's Arize API key
   - Find at: https://app.arize.com → Settings → API Keys
   - The CLI auto-detects `ARIZE_API_KEY` environment variable if set

2. **Region** - Choose the Arize region:
   - `us` - US region (most common)
   - `eu` - EU region
   - The CLI auto-detects `ARIZE_REGION` if set

3. **Output Format** - Default output format:
   - `table` - Human-readable tables (recommended for interactive use)
   - `json` - JSON output (good for scripting)
   - `csv` - CSV format
   - `parquet` - Parquet format

4. **Profile Name** - Name for this configuration (default: `default`)

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
- `ARIZE_REGION`

### Persisting Environment Variables

If using environment variable references, persist them in your shell profile:

**For Bash** (`~/.bashrc` or `~/.bash_profile`):
```bash
export ARIZE_API_KEY="your-api-key-here"
export ARIZE_SPACE_ID="your-space-id-here"
export ARIZE_REGION="us"
```

**For Zsh** (`~/.zshrc`):
```bash
export ARIZE_API_KEY="your-api-key-here"
export ARIZE_SPACE_ID="your-space-id-here"
export ARIZE_REGION="us"
```

**For Fish** (`~/.config/fish/config.fish`):
```fish
set -x ARIZE_API_KEY "your-api-key-here"
set -x ARIZE_SPACE_ID "your-space-id-here"
set -x ARIZE_REGION "us"
```

After adding these, reload your shell:
```bash
# Bash
source ~/.bashrc

# Zsh
source ~/.zshrc

# Fish
source ~/.config/fish/config.fish
```

**Recommendation**: Use environment variables for sensitive credentials, especially in shared or team environments.

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

1. Check if environment variables are set:
   ```bash
   echo $ARIZE_API_KEY
   echo $ARIZE_SPACE_ID
   ```
2. If empty, set them for the current session:
   ```bash
   export ARIZE_API_KEY="your-api-key"
   export ARIZE_SPACE_ID="your-space-id"
   ```
3. To persist, add to your shell profile:
   ```bash
   # For Zsh
   echo 'export ARIZE_API_KEY="your-api-key"' >> ~/.zshrc
   echo 'export ARIZE_SPACE_ID="your-space-id"' >> ~/.zshrc
   source ~/.zshrc

   # For Bash
   echo 'export ARIZE_API_KEY="your-api-key"' >> ~/.bashrc
   source ~/.bashrc
   ```
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
3. **Determine credential storage approach**:
   - Ask: "Would you like to store credentials directly in the config file, or use environment variables?"
   - **If environment variables**: Offer to help persist them in shell profile
4. **Configure**: Run `ax config init` (use simple mode unless user specifies otherwise)
5. **If using environment variables**:
   - Detect shell type (bash/zsh/fish)
   - Offer to add export statements to the appropriate profile file
   - Example: `echo 'export ARIZE_API_KEY="xxx"' >> ~/.zshrc`
   - Reload shell: `source ~/.zshrc`
6. **Verify**: Run `ax config show` and `ax datasets list` to confirm setup
7. **Enable completion** (optional): Offer to install shell completion

If user needs multiple profiles (e.g., dev/staging/prod):
1. Create first profile: `ax config init` (name it appropriately)
2. Create additional profiles: `ax config init` (use different names)
3. Show how to switch: `ax config use <profile-name>`
4. Consider using environment variables with different variable names per environment
