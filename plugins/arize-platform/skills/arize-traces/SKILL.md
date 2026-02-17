---
name: arize-traces
description: Retrieve and debug trace data from the Arize ML observability platform using GraphQL via curl. Use when users want to list recent traces, look up a specific trace by trace ID, get all spans within a trace, analyze trace performance (latency, tokens, cost), or export trace data. Triggers on requests involving Arize traces, span lookup, trace debugging, trace ID queries, or trace performance analysis.
---

# Arize Traces

Retrieve trace and span data from Arize via GraphQL curl commands.

## Workflow

```
1. Check API Key → 2. Resolve Model ID → 3. List Traces → 4. Get Trace Detail → 5. Summarize
```

---

## Step 1: Check API Key

```bash
echo "${ARIZE_API_KEY:-NOT_SET}"
```

If NOT_SET, ask the user for their key (Arize: Settings > API Keys), then set and verify:

```bash
export ARIZE_API_KEY="user-provided-key"
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d '{"query": "{ __typename }"}' | jq .
```

---

## Step 2: Resolve Model ID by Name

The trace queries require a base64-encoded **model ID**. Resolve it from space and project names using the `search` parameter. Users will typically say something like "get traces from business-intel-agent" — use that as the model name search.

### Find Model by Name (searches all spaces)

**Replace:** `MODEL_NAME` with the project name (partial matches work, e.g. `"business-intel"`).

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF' | jq '[.data.viewer.spaces.edges[] | .node as $space | ($space.models.edges // [])[] | .node | {spaceId: $space.id, spaceName: $space.name, modelId: .id, modelName: .name}]'
{
  "query": "query FindModel($modelName: String) { viewer { spaces(first: 50) { edges { node { id name models(first: 1, search: $modelName) { edges { node { id name } } } } } } } }",
  "variables": { "modelName": "MODEL_NAME" }
}
EOF
```

Use the returned `modelId` as `MODEL_ID` in subsequent queries.

### Find Model by Space + Model Name

If both names are known, use a single targeted query:

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF' | jq '{space: .data.viewer.spaces.edges[0].node | {id, name}, model: .data.viewer.spaces.edges[0].node.models.edges[0].node | {id, name}}'
{
  "query": "query FindProject($spaceName: String, $modelName: String) { viewer { spaces(first: 1, search: $spaceName) { edges { node { id name models(first: 1, search: $modelName) { edges { node { id name modelType } } } } } } } }",
  "variables": { "spaceName": "SPACE_NAME", "modelName": "MODEL_NAME" }
}
EOF
```

---

## Step 3: List Traces in a Time Window

Get root spans (one per trace) to discover trace IDs. Root spans have `parentId: ""` or `null`.

**Replace:** `MODEL_ID`, `START_TIME`, `END_TIME`

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF' | jq '[.data.node.spans.edges[] | .span | {traceId, name, spanKind, statusCode, latencyMs: (.latencyMs | round), startTime}]'
{
  "query": "query ListTraces($id: ID!, $dataset: ModelDatasetInput!, $sort: SpanSort!, $count: Int!, $cursor: String, $columnNames: [String!]!) { node(id: $id) { __typename ... on Model { spans: spanRecordsPublic(first: $count, after: $cursor, dataset: $dataset, sort: $sort, columnNames: $columnNames, includeRootSpans: true) { pageInfo { hasNextPage endCursor } edges { span: node { name spanKind statusCode startTime parentId latencyMs traceId spanId } } } } id } }",
  "variables": {
    "id": "MODEL_ID",
    "dataset": {
      "startTime": "START_TIME",
      "endTime": "END_TIME",
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

Filter the results to root spans only: `| jq '[.[] | select(.parentId == "" or .parentId == null)]'`

Present results as a table of traces with: trace ID, root span name, status, latency, start time.

---

## Step 4: Get Trace Detail (Spans with Input/Output)

Once the user picks a trace ID, get all spans with their input and output content.

**Replace:** `MODEL_ID`, `TRACE_ID`, `START_TIME`, `END_TIME`

```bash
curl -s -X POST "${ARIZE_GRAPHQL_ENDPOINT:-https://app.arize.com/graphql}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ARIZE_API_KEY" \
  -d @- <<'EOF' | jq .
{
  "query": "query GetTrace($id: ID!, $dataset: ModelDatasetInput!, $sort: SpanSort!, $count: Int!, $cursor: String, $columnNames: [String!]!, $includeRootSpans: Boolean!) { node(id: $id) { __typename ... on Model { spans: spanRecordsPublic(first: $count, after: $cursor, dataset: $dataset, sort: $sort, columnNames: $columnNames, includeRootSpans: $includeRootSpans) { pageInfo { hasNextPage endCursor } edges { span: node { name spanKind statusCode startTime parentId latencyMs traceId spanId columns { name value { __typename ... on CategoricalDimensionValue { stringValue: value } ... on NumericDimensionValue { numericValue: value } } } } } } } id } }",
  "variables": {
    "id": "MODEL_ID",
    "dataset": {
      "startTime": "START_TIME",
      "endTime": "END_TIME",
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
            { "id": "TRACE_ID", "value": "TRACE_ID" }
          ]
        }
      ]
    },
    "sort": { "column": "start_time", "dir": "ASC" },
    "count": 20,
    "cursor": null,
    "columnNames": [
      "attributes.input.value",
      "attributes.output.value",
      "attributes.llm.input_messages",
      "attributes.llm.output_messages"
    ],
    "includeRootSpans": false
  }
}
EOF
```

### Parsing Columns

Extract input/output per span:

```bash
| jq '[.data.node.spans.edges[] | .span | {
    name, spanKind, latencyMs: (.latencyMs | round), parentId, spanId,
    input:  (.columns[] | select(.name == "attributes.input.value") | .value.stringValue),
    output: (.columns[] | select(.name == "attributes.output.value") | .value.stringValue)
  }]'
```

### Pagination

If `pageInfo.hasNextPage` is true, set `"cursor"` to the `endCursor` value and re-run.

---

## Step 5: Summarize Results

Present trace detail as:

1. **Span tree** — show parent-child relationships using `parentId` (root has `parentId: ""`)
2. **Per-span row** — name, kind, latency, status, truncated input/output
3. **Errors** — highlight spans with error status codes

---

## API Constraints

- Public API field is `spanRecordsPublic` (NOT `spanRecords`)
- `queryFilter` string does NOT work — always use `filters` array
- Query complexity limit is 1000 — keep `count` at 10-20 and paginate
- `environmentName` must be `"tracing"` for trace/span data

---

## References

- [references/TRACE_QUERIES.md](references/TRACE_QUERIES.md) — additional column names, filter patterns, token/cost queries
