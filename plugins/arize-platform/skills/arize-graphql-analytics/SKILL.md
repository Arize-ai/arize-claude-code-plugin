---
name: arize-graphql-analytics
description: Query and analyze data from the Arize platform using GraphQL, or help build/validate GraphQL queries and mutations. Use when users want to explore spaces, models, monitors, datasets, any Arize platform data, OR when they need help writing, formatting, or debugging GraphQL queries/mutations for the Arize API.
---

# Arize GraphQL Analytics

Query and analyze data from the Arize platform using GraphQL via curl.

---

## Workflow

```
1. Check API Key → 2. Fetch Full Schema → 3. Build Query/Mutation → 4. Execute → 5. Summarize
```

**CRITICAL**: Always fetch the full schema FIRST before building any queries. This ensures accuracy.

---

## Step 1: Check API Key

```bash
echo "${ARIZE_API_KEY:-NOT_SET}"
```

### If NOT_SET

Ask the user for their API key:

> "To query the Arize GraphQL API, I need your API key. You can find it in Arize: Settings → API Keys. If you need to, generate a new User Api Key."

Then set it:

```bash
export ARIZE_API_KEY="user-provided-key"
```

Verify:

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d '{"query": "{ __typename }"}'
```

Expected: `{"data":{"__typename":"Query"}}`

---

## Step 2: Fetch Full Schema (REQUIRED FIRST STEP)

Use this comprehensive introspection query to get the complete schema. This query uses fragments to capture all type information including nested types up to 10 levels deep.

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF'
{
  "query": "query IntrospectionQuery { __schema { queryType { name } mutationType { name } subscriptionType { name } types { ...FullType } directives { name description locations args { ...InputValue } } } } fragment FullType on __Type { kind name description fields(includeDeprecated: true) { name description args { ...InputValue } type { ...TypeRef } isDeprecated deprecationReason } inputFields { ...InputValue } interfaces { ...TypeRef } enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason } possibleTypes { ...TypeRef } } fragment InputValue on __InputValue { name description type { ...TypeRef } defaultValue } fragment TypeRef on __Type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } } }"
}
EOF
```

### Understanding the Schema Response

The introspection returns:
- **queryType**: Root query type (usually "Query")
- **mutationType**: Root mutation type (usually "Mutation")
- **types**: All types in the schema with their fields, arguments, and relationships
- **directives**: Available directives

### Key Type Kinds

| Kind | Description | Example |
|------|-------------|---------|
| `SCALAR` | Primitive types | `String`, `Int`, `ID`, `Boolean`, `Float` |
| `OBJECT` | Complex types with fields | `Space`, `Model`, `Monitor` |
| `INPUT_OBJECT` | Input types for mutations | `CreateMonitorInput` |
| `ENUM` | Enumeration types | `ModelType`, `MonitorStatus` |
| `LIST` | Array wrapper | `[Model]` |
| `NON_NULL` | Required wrapper | `String!` |
| `INTERFACE` | Shared field contract | `Node` |
| `UNION` | One of multiple types | `SearchResult` |

### Unwrapping Types

When `kind` is `NON_NULL` or `LIST`, the actual type is in `ofType`. Keep unwrapping until you reach a named type:

```
NON_NULL → LIST → NON_NULL → OBJECT(Model)
means: [Model!]!
```

---

## Step 3: Build Query or Mutation

Using the schema, construct the appropriate operation.

### For Queries

1. Find the query field in the schema's queryType
2. Check its return type and arguments
3. Follow the Relay connection pattern for lists
4. Use inline fragments for interface/union types

### For Mutations

1. Find the mutation in mutationType
2. Get the input argument's type name
3. Look up that INPUT_OBJECT in types
4. Build mutation with all required inputFields

See [references/PATTERNS.md](references/PATTERNS.md) for detailed patterns.

---

## Step 4: Execute

### Simple Query

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d '{"query": "{ spaces { edges { node { id name } } } }"}'
```

### With Variables (for Mutations)

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF'
{
  "query": "mutation CreateSpace($input: CreateSpaceInput!) { createSpace(input: $input) { space { id name } } }",
  "variables": {
    "input": {
      "name": "My Space",
      "organizationId": "org-id-here"
    }
  }
}
EOF
```

---

## Step 5: Summarize Results

Parse the JSON response and provide clear insights to the user.

---

## Quick Reference: Common Patterns

### Relay Connections (Lists)

All lists use edges/node pattern:

```graphql
{
  spaces {
    edges {
      node { id name }
      cursor
    }
    pageInfo { hasNextPage endCursor }
  }
}
```

### Node Lookup (by ID)

```graphql
{
  node(id: "BASE64_ID") {
    ... on Space { name }
    ... on Model { name modelType }
  }
}
```

### Pagination

```graphql
{ spaces(first: 10, after: "cursor") { edges { node { id } } } }
```

### Mutations

```graphql
mutation Op($input: InputType!) {
  mutationName(input: $input) {
    entity { id }
    errors { field message }
  }
}
```

---

## Query Building Mode

When helping users write queries (without executing):

1. **Fetch schema first**
2. **Identify relevant types** from schema
3. **Build query** following patterns
4. **Provide multiple formats**:
   - Pretty (readable)
   - Compact (for curl)
   - Full curl command

---

## Troubleshooting

| Error | Solution |
|-------|----------|
| `401 Unauthorized` | Invalid/expired API key |
| `Field doesn't exist` | Check schema for correct field name |
| `Cannot query field on type` | Use inline fragment for interfaces |
| Parse errors | Check JSON escaping in curl |

---

## References

- [references/PATTERNS.md](references/PATTERNS.md) - Detailed GraphQL patterns
- [references/EXAMPLES.md](references/EXAMPLES.md) - Ready-to-use examples
