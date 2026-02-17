---
name: arize-datasets
description: Manage datasets in Arize AI using the ax CLI. Use when users want to list datasets, get dataset details, create new datasets, delete datasets, export dataset data, or work with dataset examples. Triggers on "list datasets", "create dataset", "ax datasets", "export dataset", "delete dataset", or any request about managing Arize datasets via CLI.
---

# Arize AX Datasets

Manage datasets in the Arize AI platform using the `ax` CLI.

## Prerequisites

The user must have:
1. Arize AX CLI installed (`pip install arize-ax-cli`)
2. CLI configured with valid credentials (`ax config init`)

**If not set up**: Use the `/setup-arize-cli` skill first.

## Core Dataset Commands

### List All Datasets

```bash
ax datasets list
```

**Options:**
- `--output <format>` - Output format: `table` (default), `json`, `csv`, `parquet`
- `--profile <name>` - Use specific configuration profile
- `--limit <n>` - Limit number of results
- `--offset <n>` - Skip first n results (pagination)

**Examples:**

```bash
# List as table (default)
ax datasets list

# List as JSON
ax datasets list --output json

# List with pagination
ax datasets list --limit 10 --offset 0

# Use production profile
ax datasets list --profile production
```

**Extracting Dataset IDs:**

To find a specific dataset ID for use in other operations:

```bash
# Get all dataset IDs and names as JSON
ax datasets list --output json | jq '.[] | {id: .id, name: .name}'

# Find a dataset ID by name
ax datasets list --output json | jq -r '.[] | select(.name == "Training Data") | .id'

# Save dataset ID to a variable
DATASET_ID=$(ax datasets list --output json | jq -r '.[] | select(.name == "Training Data") | .id')
echo "Found dataset: $DATASET_ID"

# Use the ID in subsequent commands
ax datasets get "$DATASET_ID"
ax datasets delete "$DATASET_ID"
```

**Without jq (using grep):**

```bash
# List with grep to find dataset
ax datasets list --output json | grep -A 2 "Training Data" | grep "id"

# More reliable pattern
ax datasets list --output json | grep -B 1 '"name": "Training Data"' | grep "id" | cut -d'"' -f4
```

### Get Dataset Details

Retrieve information about a specific dataset:

```bash
ax datasets get <dataset-id>
```

**Options:**
- `--output <format>` - Output format
- `--profile <name>` - Configuration profile to use

**Examples:**

```bash
# Get dataset details
ax datasets get ds_abc123xyz

# Get as JSON
ax datasets get ds_abc123xyz --output json

# Get from production environment
ax datasets get ds_abc123xyz --profile production
```

### Create a New Dataset

Create a dataset from a file:

```bash
ax datasets create --file <path> [options]
```

**Supported File Formats:**
- CSV (`.csv`)
- JSON (`.json`, `.jsonl`)
- Parquet (`.parquet`)

**Options:**
- `--name <name>` - Dataset name (required or inferred from filename)
- `--description <text>` - Dataset description
- `--profile <name>` - Configuration profile to use

**Examples:**

```bash
# Create from CSV
ax datasets create --file data.csv --name "Training Data" --description "Production training set"

# Create from JSON
ax datasets create --file examples.json --name "Test Examples"

# Create from Parquet
ax datasets create --file dataset.parquet --name "Large Dataset"

# Use staging profile
ax datasets create --file data.csv --name "Test Data" --profile staging
```

### Delete a Dataset

Remove a dataset from Arize:

```bash
ax datasets delete <dataset-id>
```

**Options:**
- `--profile <name>` - Configuration profile to use
- `--yes` or `-y` - Skip confirmation prompt

**Examples:**

```bash
# Delete with confirmation
ax datasets delete ds_abc123xyz

# Delete without confirmation
ax datasets delete ds_abc123xyz --yes

# Delete from production
ax datasets delete ds_abc123xyz --profile production
```

**⚠️ Warning**: Deletion is permanent. Always verify the dataset ID before deleting.

## Export Dataset Data

Export dataset examples to various formats:

```bash
ax datasets get <dataset-id> --output <format>
```

**Export Formats:**
- `json` - JSON format
- `csv` - Comma-separated values
- `parquet` - Apache Parquet format

**Examples:**

```bash
# Export to JSON
ax datasets get ds_abc123xyz --output json > dataset.json

# Export to CSV
ax datasets get ds_abc123xyz --output csv > dataset.csv

# Export to Parquet
ax datasets get ds_abc123xyz --output parquet > dataset.parquet
```

## Working with Multiple Profiles

When working across different environments (dev, staging, production):

```bash
# List datasets in production
ax datasets list --profile production

# Create dataset in staging
ax datasets create --file test_data.csv --profile staging

# Get dataset from dev environment
ax datasets get ds_dev_123 --profile dev
```

## Pagination for Large Results

For accounts with many datasets, use pagination:

```bash
# First page (10 items)
ax datasets list --limit 10 --offset 0

# Second page
ax datasets list --limit 10 --offset 10

# Third page
ax datasets list --limit 10 --offset 20
```

## Common Workflows

### Workflow 1: Find Dataset by Name and Get Details

```bash
# 1. List all datasets and find the one you want
ax datasets list --output json | jq '.[] | {id: .id, name: .name}'

# 2. Extract the specific dataset ID by name
DATASET_ID=$(ax datasets list --output json | jq -r '.[] | select(.name == "Production Data") | .id')

# 3. Get detailed information about that dataset
ax datasets get "$DATASET_ID"

# 4. Export the dataset if needed
ax datasets get "$DATASET_ID" --output csv > dataset_export.csv
```

### Workflow 2: Create and Verify Dataset

```bash
# 1. Create dataset
ax datasets create --file data.csv --name "My Dataset"

# 2. Find the new dataset ID
DATASET_ID=$(ax datasets list --output json | jq -r '.[] | select(.name == "My Dataset") | .id')
echo "Created dataset: $DATASET_ID"

# 3. Verify details
ax datasets get "$DATASET_ID"
```

### Workflow 2: Export, Modify, and Re-upload

```bash
# 1. Export existing dataset
ax datasets get ds_abc123 --output csv > dataset.csv

# 2. Modify the CSV file (manual editing)

# 3. Create new version
ax datasets create --file dataset.csv --name "Updated Dataset v2"
```

### Workflow 3: Migrate Dataset Between Environments

```bash
# 1. Export from production
ax datasets get ds_prod_123 --profile production --output json > prod_data.json

# 2. Import to staging
ax datasets create --file prod_data.json --name "Production Copy" --profile staging
```

### Workflow 4: Cleanup Old Datasets

```bash
# 1. List all datasets
ax datasets list --output json > all_datasets.json

# 2. Review and identify datasets to delete (manual review)

# 3. Delete old datasets
ax datasets delete ds_old_001 --yes
ax datasets delete ds_old_002 --yes
```

## Output Format Examples

### Table Format (Default)
Human-readable table with columns for ID, Name, Created, and Status.

### JSON Format
Structured JSON with full dataset metadata:
```json
{
  "id": "ds_abc123xyz",
  "name": "Training Data",
  "description": "Production training set",
  "created_at": "2024-01-15T10:30:00Z",
  "num_examples": 1000,
  "size_bytes": 52428800
}
```

### CSV Format
Comma-separated values, useful for importing into spreadsheets or pandas.

### Parquet Format
Efficient columnar format, ideal for large datasets and data processing.

## Troubleshooting

### "Dataset not found"

1. Verify dataset ID: `ax datasets list`
2. Check you're using the correct profile: `ax config show`
3. Ensure the dataset exists in the current space/project

### "Permission denied" or "Unauthorized"

1. Check API key is valid: `ax config show --expand`
2. Verify the key has dataset permissions in Arize
3. Try re-authenticating: `ax config init`

### "File format not supported"

Supported formats are CSV, JSON (including JSONL), and Parquet. Check:
1. File extension is correct
2. File is not corrupted
3. File content matches the extension

### Large dataset creation fails

For very large datasets:
1. Check file size and network stability
2. Try breaking into smaller chunks
3. Use Parquet format for better compression
4. Consider using the Arize Python SDK for programmatic uploads

### Output is too large

For datasets with many examples:
1. Use `--limit` to restrict output size
2. Export to file instead of viewing in terminal:
   ```bash
   ax datasets get ds_abc123 --output json > dataset.json
   ```
3. Use pagination with `--limit` and `--offset`

## Tips

1. **Extract dataset IDs by name**:
   ```bash
   DATASET_ID=$(ax datasets list --output json | jq -r '.[] | select(.name == "My Dataset") | .id')
   ```
2. **Use JSON output for scripting**: `ax datasets list --output json | jq '.[] | .id'`
3. **List IDs and names together**: `ax datasets list --output json | jq '.[] | {id, name}'`
4. **Pipe to files for export**: Always redirect large outputs to files
5. **Verify before delete**: Use `ax datasets get "$DATASET_ID"` to confirm before deleting
6. **Profile naming**: Use descriptive names like `prod`, `staging`, `dev`
7. **Save IDs to variables**: Store dataset IDs in shell variables for reuse in scripts
8. **Check limits**: Some operations may have rate limits or quotas

## Next Steps

- View dataset details in Arize UI: https://app.arize.com
- Use datasets in experiments and evaluations
- Integrate with Arize Python SDK for programmatic access
- Set up CI/CD pipelines using the CLI

## When to Use This Skill

Use this skill when users want to:
- ✅ List all datasets in their Arize account
- ✅ Get details about a specific dataset
- ✅ Create a new dataset from a local file
- ✅ Delete datasets they no longer need
- ✅ Export dataset data to different formats
- ✅ Work with datasets across multiple environments
- ✅ Troubleshoot dataset-related CLI issues

**Don't use this skill for:**
- ❌ GraphQL queries (use `/arize-graphql-analytics` instead)
- ❌ Installing/configuring the CLI (use `/setup-arize-cli` instead)
- ❌ Managing projects, models, or other Arize resources beyond datasets
