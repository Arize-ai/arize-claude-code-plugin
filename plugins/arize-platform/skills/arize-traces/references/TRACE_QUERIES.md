# Trace Query Reference

Verified, working GraphQL queries for retrieving trace data from the Arize public API.

**CRITICAL**: The public API uses `spanRecordsPublic` (not `spanRecords`). The `queryFilter` string causes internal errors — always use the `filters` array. The API has a query complexity limit of 1000; keep `first` at 10-20 and paginate.

---

## Table of Contents

1. [List Traces in a Time Window](#list-traces-in-a-time-window)
2. [Get Spans with Input/Output for a Trace](#get-spans-with-inputoutput-for-a-trace)
3. [Get Span Metadata Only (No Columns)](#get-span-metadata-only)
4. [Resolve Space and Model IDs](#resolve-space-and-model-ids)
5. [Filter Pattern](#filter-pattern)
6. [Pagination](#pagination)
7. [SpanRecord Fields](#spanrecord-fields)
8. [Column Name Catalog](#column-name-catalog)

---

## List Traces in a Time Window

Get root spans (one per trace) to discover trace IDs within a time range.

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF' | jq '[.data.node.spans.edges[] | .span | select(.parentId == "" or .parentId == null) | {traceId, name, spanKind, statusCode, latencyMs: (.latencyMs | round), startTime}]'
{
  "query": "query ListTraces($id: ID!, $dataset: ModelDatasetInput!, $sort: SpanSort!, $count: Int!, $cursor: String, $columnNames: [String!]!) { node(id: $id) { __typename ... on Model { spans: spanRecordsPublic(first: $count, after: $cursor, dataset: $dataset, sort: $sort, columnNames: $columnNames, includeRootSpans: true) { pageInfo { hasNextPage endCursor } edges { span: node { name spanKind statusCode startTime parentId latencyMs traceId spanId } } } } id } }",
  "variables": {
    "id": "MODEL_ID_HERE",
    "dataset": {
      "startTime": "2025-01-01T00:00:00Z",
      "endTime": "2026-12-31T23:59:59Z",
      "externalModelVersionIds": [],
      "externalBatchIds": [],
      "environmentName": "tracing"
    },
    "sort": { "column": "start_time", "dir": "DESC" },
    "count": 20,
    "cursor": null,
    "columnNames": []
  }
}
EOF
```

Returns a list of traces with trace ID, root span name, status, latency, and start time.

---

## Get Spans with Input/Output for a Trace

Retrieves all spans for a specific trace with their input and output values.

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF' | jq .
{
  "query": "query GetTrace($id: ID!, $dataset: ModelDatasetInput!, $sort: SpanSort!, $count: Int!, $cursor: String, $columnNames: [String!]!, $includeRootSpans: Boolean!) { node(id: $id) { __typename ... on Model { spans: spanRecordsPublic(first: $count, after: $cursor, dataset: $dataset, sort: $sort, columnNames: $columnNames, includeRootSpans: $includeRootSpans) { pageInfo { hasNextPage endCursor } edges { span: node { name spanKind statusCode startTime parentId latencyMs traceId spanId columns { name value { __typename ... on CategoricalDimensionValue { stringValue: value } ... on NumericDimensionValue { numericValue: value } } } } } } } id } }",
  "variables": {
    "id": "MODEL_ID_HERE",
    "dataset": {
      "startTime": "2025-01-01T00:00:00Z",
      "endTime": "2026-12-31T23:59:59Z",
      "externalModelVersionIds": [],
      "externalBatchIds": [],
      "environmentName": "tracing",
      "filters": [
        {
          "filterType": "spanProperty",
          "operator": "equals",
          "dimension": {
            "id": "context.trace_id",
            "name": "context.trace_id",
            "dataType": "STRING",
            "category": "spanProperty"
          },
          "dimensionValues": [
            {
              "id": "TRACE_ID_HERE",
              "value": "TRACE_ID_HERE"
            }
          ]
        }
      ]
    },
    "sort": { "column": "start_time", "dir": "DESC" },
    "count": 10,
    "cursor": null,
    "columnNames": [
      "attributes.input.value",
      "attributes.output.value",
      "attributes.llm.input_messages",
      "attributes.llm.output_messages",
      "attributes.llm.model_name"
    ],
    "includeRootSpans": false
  }
}
EOF
```

### Parsing Column Values

Columns use a union type. Extract values with jq:

```bash
# Extract input/output from each span
| jq '.data.node.spans.edges[] | .span | {
  name,
  spanKind,
  input: (.columns[] | select(.name == "attributes.input.value") | .value.stringValue),
  output: (.columns[] | select(.name == "attributes.output.value") | .value.stringValue)
}'
```

---

## Get Span Metadata Only

Lighter query without columns — useful for building a span tree or checking trace structure.

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF' | jq .
{
  "query": "query GetTrace($id: ID!, $dataset: ModelDatasetInput!, $sort: SpanSort!, $count: Int!, $cursor: String, $columnNames: [String!]!, $includeRootSpans: Boolean!) { node(id: $id) { __typename ... on Model { spans: spanRecordsPublic(first: $count, after: $cursor, dataset: $dataset, sort: $sort, columnNames: $columnNames, includeRootSpans: $includeRootSpans) { pageInfo { hasNextPage endCursor } edges { span: node { name spanKind statusCode startTime parentId latencyMs traceId spanId } } } } id } }",
  "variables": {
    "id": "MODEL_ID_HERE",
    "dataset": {
      "startTime": "2025-01-01T00:00:00Z",
      "endTime": "2026-12-31T23:59:59Z",
      "externalModelVersionIds": [],
      "externalBatchIds": [],
      "environmentName": "tracing",
      "filters": [
        {
          "filterType": "spanProperty",
          "operator": "equals",
          "dimension": {
            "id": "context.trace_id",
            "name": "context.trace_id",
            "dataType": "STRING",
            "category": "spanProperty"
          },
          "dimensionValues": [
            {
              "id": "TRACE_ID_HERE",
              "value": "TRACE_ID_HERE"
            }
          ]
        }
      ]
    },
    "sort": { "column": "start_time", "dir": "DESC" },
    "count": 10,
    "cursor": null,
    "columnNames": [],
    "includeRootSpans": false
  }
}
EOF
```

---

## Resolve Space and Model IDs

### List Spaces

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d '{"query": "{ viewer { spaces(first: 50) { edges { node { id name } } } } }"}' | jq .
```

### List Models in a Space

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF' | jq .
{
  "query": "query GetModels($spaceId: ID!) { node(id: $spaceId) { ... on Space { id name models(first: 50) { edges { node { id name modelType } } } } } }",
  "variables": { "spaceId": "SPACE_ID_HERE" }
}
EOF
```

### Decode a Base64 ID

```bash
echo "TW9kZWw6NjA1NTIzNDU0Mjp6azlI" | base64 -d
# Output: Model:6055234542:zk9H
```

---

## Filter Pattern

The `filters` array uses this structure to filter by trace ID:

```json
{
  "filterType": "spanProperty",
  "operator": "equals",
  "dimension": {
    "id": "context.trace_id",
    "name": "context.trace_id",
    "dataType": "STRING",
    "category": "spanProperty"
  },
  "dimensionValues": [
    {
      "id": "your-trace-id",
      "value": "your-trace-id"
    }
  ]
}
```

### Available Filter Properties

| filterType | category | Use for |
|-----------|----------|---------|
| `spanProperty` | `spanProperty` | Span fields like `context.trace_id`, `name`, `status_code` |
| `llmEval` | `llmEval` | Evaluation labels, scores, explanations |
| `annotation` | `annotation` | Annotation data |

### Operators

`equals`, `notEquals`, `contains`, `containsString`, `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`

### Dimension Data Types

`STRING`, `LONG`, `FLOAT`, `DOUBLE`, `EMBEDDING`, `STRING_LIST`, `DICTIONARY`

---

## Pagination

```bash
# First page: cursor = null
# Next pages: set cursor to endCursor from previous response

"cursor": "YXJyYXljb25uZWN0aW9uOjk="
```

Keep `count` at 10-20 to stay under the complexity limit. Paginate with `after` cursor.

---

## SpanRecord Fields

Available fields on each span node:

| Field | Type | Description |
|-------|------|-------------|
| `traceId` | `String!` | Trace ID |
| `spanId` | `String!` | Span ID |
| `parentId` | `String` | Parent span ID (null = root span) |
| `name` | `String!` | Span name |
| `spanKind` | `String!` | Kind: LLM, CHAIN, AGENT, TOOL, RETRIEVER |
| `statusCode` | `String!` | Status: OK, ERROR |
| `startTime` | `DateTime!` | Start timestamp |
| `endTime` | `DateTime` | End timestamp |
| `recordTimestamp` | `DateTime!` | Record timestamp |
| `latencyMs` | `Float` | Latency in milliseconds |
| `sessionId` | `String` | Session ID |
| `userId` | `String` | User ID |
| `columns` | `[NameValuePairType!]!` | Requested column values |
| `attributes` | `String!` | All attributes as JSON string |

**Note**: `traceTokenCounts` and `totalCost` are available but add significant query complexity. Only include when needed and reduce `count` accordingly.

---

## Column Name Catalog

### Core Input/Output (most commonly needed)

- `attributes.input.value` - Span input text
- `attributes.output.value` - Span output text
- `attributes.llm.input_messages` - LLM input messages (JSON)
- `attributes.llm.output_messages` - LLM output messages (JSON)

### LLM Details

- `attributes.llm.model_name` - Model name
- `attributes.llm.provider` - LLM provider
- `attributes.llm.system` - LLM system
- `attributes.llm.invocation_parameters` - Model parameters
- `attributes.llm.token_count.total` - Total tokens
- `attributes.llm.token_count.prompt` - Prompt tokens
- `attributes.llm.token_count.completion` - Completion tokens
- `attributes.llm.token_count.prompt_details.cache_read` - Cached prompt tokens
- `attributes.llm.token_count.completion_details.reasoning` - Reasoning tokens

### Cost

- `attributes.llm.cost.total` - Total cost
- `attributes.llm.cost.prompt` - Prompt cost
- `attributes.llm.cost.completion` - Completion cost

### Span Metadata

- `context.trace_id` - Trace ID (as column)
- `name` - Span name (as column)
- `start_time` - Start time (as column)
- `latency_ms` - Latency (as column)
- `status_code` - Status (as column)
- `attributes.metadata` - Custom metadata
- `attributes.session.id` - Session ID
- `attributes.user.id` - User ID

### Evaluations

Pattern: `eval.<eval_name>.<field>` where field is `label`, `score`, or `explanation`.

Example: `eval.matches_regex.label`, `eval.matches_regex.score`

### Environment Name Values

- `tracing` - For trace/span data (most common)
- `production` - Production environment
- `training` - Training environment
- `validation` - Validation environment
