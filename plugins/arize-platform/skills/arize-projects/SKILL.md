---
name: arize-projects
description: Manage projects in Arize AI using the ax CLI. Use when users want to list projects, get project details, create new projects, delete projects, or organize work within Arize spaces. Triggers on "list projects", "create project", "ax projects", "delete project", or any request about managing Arize projects via CLI.
---

# Arize AX Projects

Manage projects in the Arize AI platform using the `ax` CLI.

## Prerequisites

The user must have:
1. Arize AX CLI installed (`pip install arize-ax-cli`)
2. CLI configured with valid credentials (`ax config init`)

**If not set up**: Use the `/setup-arize-cli` skill first.

## Core Project Commands

### List Projects

```bash
ax projects list
```

**Options:**
- `--space-id <id>` - Space ID to list projects from (uses config default if not set)
- `--limit, -n <count>` - Maximum number of projects to return (default: 15)
- `--cursor <token>` - Pagination cursor for next page
- `--output, -o <format>` - Output format: `table` (default), `json`, `csv`, `parquet`, or a file path
- `--profile, -p <name>` - Configuration profile to use
- `--verbose, -v` - Enable verbose logs

**Examples:**

```bash
# List projects (default table format)
ax projects list

# List as JSON
ax projects list --output json

# List from a specific space
ax projects list --space-id sp_abc123

# Limit results
ax projects list -n 5

# Use production profile
ax projects list --profile production
```

**Extracting Project IDs:**

```bash
# Get all project IDs and names as JSON
ax projects list --output json | jq '.[] | {id: .id, name: .name}'

# Find a project ID by name
ax projects list --output json | jq -r '.[] | select(.name == "My Project") | .id'

# Save project ID to a variable
PROJECT_ID=$(ax projects list --output json | jq -r '.[] | select(.name == "My Project") | .id')
echo "Found project: $PROJECT_ID"
```

**Without jq (using grep):**

```bash
# Find project by name
ax projects list --output json | grep -B 1 '"name": "My Project"' | grep "id" | cut -d'"' -f4
```

### Resolving Project Names to IDs

The CLI commands (`get`, `delete`) require a project ID, not a name. When a user refers to a project by name, resolve the ID first using `projects list`:

1. Run `ax projects list --output json`
2. Parse the JSON to find the project matching the requested name
3. Use the resolved ID for subsequent commands

If no exact match is found, check for partial or case-insensitive matches and confirm with the user before proceeding. If multiple matches exist, present the options and ask the user to choose.

```bash
# Example: user asks to "get the ML Experiments project"
PROJECT_ID=$(ax projects list --output json | jq -r '.[] | select(.name == "ML Experiments") | .id')
if [ -z "$PROJECT_ID" ]; then
  echo "Project not found. Available projects:"
  ax projects list --output json | jq '.[] | {id: .id, name: .name}'
else
  ax projects get "$PROJECT_ID"
fi
```

### Get Project Details

Retrieve information about a specific project:

```bash
ax projects get <project-id>
```

**Arguments:**
- `id` (required) - The project ID

**Options:**
- `--output, -o <format>` - Output format: `table` (default), `json`, `csv`, `parquet`, or a file path
- `--profile, -p <name>` - Configuration profile to use
- `--verbose, -v` - Enable verbose logs

**Examples:**

```bash
# Get project details
ax projects get proj_abc123

# Get as JSON
ax projects get proj_abc123 --output json

# Get from production environment
ax projects get proj_abc123 --profile production
```

### Create a Project

Create a new project in a space:

```bash
ax projects create --name <name> --space-id <space-id>
```

**Options:**
- `--name, -n <name>` (required) - Project name (prompted interactively if not provided)
- `--space-id <id>` (required) - Space ID to create the project in (prompted interactively if not provided)
- `--output, -o <format>` - Output format: `table` (default), `json`, `csv`, `parquet`, or a file path
- `--profile, -p <name>` - Configuration profile to use
- `--verbose, -v` - Enable verbose logs

**Examples:**

```bash
# Create with all options specified
ax projects create --name "ML Experiments" --space-id sp_abc123

# Create interactively (prompts for name and space-id)
ax projects create

# Create and output as JSON
ax projects create --name "Staging Tests" --space-id sp_abc123 --output json

# Create using a specific profile
ax projects create --name "Production Project" --space-id sp_abc123 --profile production
```

### Delete a Project

Remove a project by ID:

```bash
ax projects delete <project-id>
```

**Arguments:**
- `id` (required) - The project ID

**Options:**
- `--force, -f` - Skip confirmation prompt
- `--profile, -p <name>` - Configuration profile to use
- `--verbose, -v` - Enable verbose logs

**Examples:**

```bash
# Delete with confirmation prompt
ax projects delete proj_abc123

# Delete without confirmation
ax projects delete proj_abc123 --force

# Delete from production
ax projects delete proj_abc123 --profile production
```

**Warning**: Deletion is permanent. Always verify the project ID before deleting.

## Pagination

The `projects list` command uses cursor-based pagination. The response includes a cursor for fetching the next page:

```bash
# First page
ax projects list -n 10 --output json

# Use the cursor from the previous response to get the next page
ax projects list -n 10 --cursor <cursor-from-previous-response>
```

## Common Workflows

### Workflow 1: Find Project by Name and Get Details

```bash
# 1. List all projects
ax projects list --output json | jq '.[] | {id: .id, name: .name}'

# 2. Extract the project ID by name
PROJECT_ID=$(ax projects list --output json | jq -r '.[] | select(.name == "ML Experiments") | .id')

# 3. Get detailed information
ax projects get "$PROJECT_ID"
```

### Workflow 2: Create and Verify a Project

```bash
# 1. Create the project
ax projects create --name "New Experiment" --space-id sp_abc123

# 2. Find the new project ID
PROJECT_ID=$(ax projects list --output json | jq -r '.[] | select(.name == "New Experiment") | .id')
echo "Created project: $PROJECT_ID"

# 3. Verify details
ax projects get "$PROJECT_ID"
```

### Workflow 3: Work with Projects Across Environments

```bash
# List projects in production
ax projects list --profile production

# Create project in staging
ax projects create --name "Test Project" --space-id sp_staging_123 --profile staging

# Get project details from dev
ax projects get proj_dev_456 --profile dev
```

### Workflow 4: Cleanup Old Projects

```bash
# 1. List all projects
ax projects list --output json | jq '.[] | {id: .id, name: .name}'

# 2. Review and identify projects to delete

# 3. Delete old projects
ax projects delete proj_old_001 --force
ax projects delete proj_old_002 --force
```

## Output Format Examples

### Table Format (Default)
Human-readable table with columns for ID, Name, Created, and other metadata.

### JSON Format
Structured JSON with full project metadata:
```json
{
  "id": "proj_abc123",
  "name": "ML Experiments",
  "space_id": "sp_xyz789",
  "created_at": "2024-01-15T10:30:00Z"
}
```

### CSV / Parquet
Use `--output csv` or `--output parquet` for data-processing-friendly formats. You can also pass a file path to write directly to a file:
```bash
ax projects list --output projects.csv
ax projects list --output projects.parquet
```

## Troubleshooting

### "Project not found"

1. Verify project ID: `ax projects list`
2. Check you're using the correct profile: `ax config show`
3. Ensure the project exists in the current space

### "Permission denied" or "Unauthorized"

1. Check API key is valid: `ax config show --expand`
2. Verify the key has project permissions in Arize
3. Try re-authenticating: `ax config init`

### "Space not found" when creating

1. Verify the space ID is correct
2. Check your profile has the right space configured: `ax config show`
3. List available spaces or check https://app.arize.com

### Cannot list projects

1. Check CLI is configured: `ax config show`
2. Verify network connectivity
3. Try with `--verbose` for more detail: `ax projects list --verbose`

## Tips

1. **Extract project IDs by name**:
   ```bash
   PROJECT_ID=$(ax projects list --output json | jq -r '.[] | select(.name == "My Project") | .id')
   ```
2. **Use JSON output for scripting**: `ax projects list --output json | jq '.[] | .id'`
3. **List IDs and names together**: `ax projects list --output json | jq '.[] | {id, name}'`
4. **Verify before delete**: Use `ax projects get "$PROJECT_ID"` to confirm before deleting
5. **Profile naming**: Use descriptive names like `prod`, `staging`, `dev`
6. **Use `--force` in scripts**: Skip interactive confirmation with `-f` when automating

## Next Steps

- View project details in Arize UI: https://app.arize.com
- Use `/arize-datasets` to manage datasets within projects
- Visit https://docs.arize.com for full documentation

## When to Use This Skill

Use this skill when users want to:
- ✅ List all projects in their Arize space
- ✅ Get details about a specific project
- ✅ Create a new project
- ✅ Delete projects they no longer need
- ✅ Work with projects across multiple environments/profiles

**Don't use this skill for:**
- ❌ Managing datasets (use `/arize-datasets` instead)
- ❌ Installing/configuring the CLI (use `/setup-arize-cli` instead)
