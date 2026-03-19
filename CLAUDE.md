# Arize Go SDK — Swarm Build Protocol

## 1. Project Goal

Build `arize-go`, an idiomatic Go client library wrapping the Arize REST API v2.
The SDK gives Go applications programmatic access to Arize/Phoenix for observability,
dataset management, and span analysis.

### Scope: Three Resource Domains

| Domain | Operations | REST Endpoints |
|--------|-----------|----------------|
| **Datasets** | List, Get, Create, Delete, ListExamples | `GET/POST /v2/datasets`, `GET/DELETE /v2/datasets/{id}`, `GET /v2/datasets/{id}/examples` |
| **Spans** | List (with filters) | `POST /v2/spans` (body contains project_id, time range, filter) |
| **Projects** | List, Get, Create, Delete | `GET/POST /v2/projects`, `GET/DELETE /v2/projects/{id}` |

**Do NOT implement** resources beyond Datasets, Spans, and Projects (no Prompts, Sessions,
Experiments, Evaluators, Annotation Configs, or Annotation Queues).

### Source of Truth

- OpenAPI spec: `https://api.arize.com/v2/spec.yaml`
- REST reference: `https://arize.com/docs/ax/rest-reference`
- Python SDK (behavioral parity): `https://arize.com/docs/api-clients/python/version-8/overview`

## 2. Technical Specifications

- **Go version**: 1.21+
- **Dependencies**: Standard library only (`net/http`, `encoding/json`, `net/url`)
- **Auth**: `Authorization: Bearer <api-key>` on every request
- **Base URL**: `https://api.arize.com` (configurable via `WithBaseURL`)
- **Pagination**: Cursor-based. Each list response uses a resource-specific key (not a generic `"data"` key). All list responses include a `"pagination"` object with `{ "has_more": bool, "next_cursor": string }`. The `next_cursor` field is present only when `has_more` is `true`. Pass `next_cursor` as the `cursor` query parameter in subsequent requests.
- **Context**: All public methods take `context.Context` as first parameter
- **Error handling**: Return `(result, error)`. Typed `*APIError` for non-2xx responses.
- **Testing**: Table-driven with `net/http/httptest`. Test marshaling, request construction, errors, pagination.

### Target API Shape

```go
client := arize.NewClient("api-key", arize.WithBaseURL("https://api.arize.com"))

// Datasets
datasets, err := client.Datasets.List(ctx, &arize.ListDatasetsOptions{SpaceID: "spc_123"}) // (*ListDatasetsResponse, error)
dataset, err := client.Datasets.Get(ctx, "dataset-id") // (*Dataset, error)
dataset, err := client.Datasets.Create(ctx, &arize.CreateDatasetRequest{ // (*Dataset, error)
	Name: "ds", SpaceID: "spc_123", Examples: examples,
})
err = client.Datasets.Delete(ctx, "dataset-id") // error
examples, err := client.Datasets.ListExamples(ctx, "dataset-id", &arize.ListExamplesOptions{ // (*ListExamplesResponse, error)
	DatasetVersionID: "v1", Limit: 100,
})

// Spans
spans, err := client.Spans.List(ctx, &arize.ListSpansRequest{ // (*ListSpansResponse, error)
	ProjectID: "proj-id", Limit: 100, Filter: "status_code = 'ERROR'",
})

// Projects
projects, err := client.Projects.List(ctx, &arize.ListProjectsOptions{SpaceID: "spc_123"}) // (*ListProjectsResponse, error)
project, err := client.Projects.Get(ctx, "project-id") // (*Project, error)
project, err := client.Projects.Create(ctx, &arize.CreateProjectRequest{ // (*Project, error)
	Name: "my-project", SpaceID: "spc_123",
})
err = client.Projects.Delete(ctx, "project-id") // error
```

### REST API Details (derived from OpenAPI spec)

**Common query params**: `space_id`, `name` (case-insensitive substring filter on name), `limit`, `cursor`

**Datasets**:
- `GET /v2/datasets` — query: `space_id`, `name`, `limit` (max 100, default 50), `cursor`
- `POST /v2/datasets` — body: `{ name, space_id, examples: [{ ...user_fields }] }` → returns 201
- `GET /v2/datasets/{dataset_id}` — returns dataset object with `versions` array
- `DELETE /v2/datasets/{dataset_id}` — returns 204
- `GET /v2/datasets/{dataset_id}/examples` — query: `dataset_version_id`, `limit` (max 500, default 50). Cursor pagination is not yet implemented by the API — do not send a `cursor` parameter for this endpoint.

**Projects**:
- `GET /v2/projects` — query: `space_id`, `name`, `limit` (max 100, default 50), `cursor`
- `POST /v2/projects` — body: `{ name, space_id }` → returns 201
- `GET /v2/projects/{project_id}`
- `DELETE /v2/projects/{project_id}` — returns 204

**Spans**:
- `POST /v2/spans` — query: `limit` (max 500, default 50), `cursor`; body: `{ project_id (required), start_time (optional), end_time (optional), filter (optional) }` → returns 200

**Response envelopes** (list endpoints use resource-specific keys):
```json
// GET /v2/datasets
{ "datasets": [...], "pagination": { "has_more": true, "next_cursor": "opaque_token" } }

// GET /v2/datasets/{id}/examples
{ "examples": [...], "pagination": { "has_more": true, "next_cursor": "opaque_token" } }

// POST /v2/spans
{ "spans": [...], "pagination": { "has_more": true, "next_cursor": "opaque_token" } }

// GET /v2/projects
{ "projects": [...], "pagination": { "has_more": true, "next_cursor": "opaque_token" } }
```

**Error envelope**: Non-2xx responses return `application/problem+json` with RFC 9457 Problem Details:
`{ "status": int, "title": "...", "detail": "...", "type": "...", "instance": "..." }`.
429 responses also include a `Retry-After` header (integer seconds). There is no equivalent body field — parse the header and expose it on `APIError`.

## 3. Swarm Protocol

This project uses **Claude Code Agent Teams** — the built-in team orchestration feature.
The Lead MUST use the following Claude Code tools to orchestrate the pipeline:

| Tool | Purpose |
|------|---------|
| `TeamCreate` | Create the team (name: `arize-sdk`). This also creates the shared task list. Call this FIRST before anything else. |
| `TaskCreate` | Add tasks to the shared task list for teammates to claim. |
| `TaskUpdate` | Assign tasks (`owner`), update status, set `blocks`/`blockedBy` dependencies. |
| `TaskList` | Check task progress. |
| `Agent` | Spawn each teammate. MUST include `team_name: "arize-sdk"`, `name: "<role>"`, `isolation: "worktree"`, and `mode: "bypassPermissions"`. Use `model` to select the right model per role. |
| `SendMessage` | Send messages to teammates by name (e.g., `to: "architect"`). Use for instructions, feedback, and shutdown requests. |

**All teammates MUST be spawned with `mode: "bypassPermissions"` on the Agent tool.** No permission prompts should interrupt the pipeline.

### Roles

| Role | Agent `name` | Agent `model` | `subagent_type` | Responsibility | Writes code? |
|------|-------------|---------------|-----------------|---------------|-------------|
| **Lead** | _(you)_ | `opus` | — | Creates team via `TeamCreate`, defines tasks via `TaskCreate`, merges worktrees, applies remediation fixes, delivers PR. | Yes — remediation fixes only |
| **Architect** | `architect` | `opus` | `general-purpose` | Initializes Go module, creates directory layout, writes ALL shared types (structs, interfaces, error types, client skeleton) AND HTTP helper method signatures with stub bodies. This is the contract both Builders code against. | Yes — types and interfaces only |
| **Builder: HTTP** | `builder-http` | `sonnet` | `general-purpose` | Implements the HTTP client layer: request/response helpers, auth injection, pagination, error parsing. Replaces the Architect's `panic("not implemented")` stub in `http.go` with real implementation. | Yes |
| **Builder: Services** | `builder-services` | `sonnet` | `general-purpose` | Implements DatasetsService, SpansService, ProjectsService — the three service structs with all methods. Calls the HTTP helper methods by their Architect-defined signatures. | Yes |
| **Reviewer** | `reviewer` | `opus` | `general-purpose` | Reviews ALL generated code as a senior Go engineer. Messages the Lead with structured feedback via `SendMessage`. | No — review only |
| **Tester** | `tester` | `sonnet` | `general-purpose` | Writes table-driven tests using httptest for every public method. Runs `go test ./... -v`. Messages the Lead with results via `SendMessage`. | Yes — tests only |

### Lead Startup Sequence

The Lead MUST execute these steps in order before spawning any teammates:

```
1. TeamCreate(team_name: "arize-sdk", description: "Arize Go SDK build")
2. git checkout -b feat/arize-go-sdk  (create feature branch)
3. TaskCreate — create all tasks (see Task List below)
4. TaskUpdate — set blockedBy dependencies between tasks
5. Agent(...) — spawn Architect (Phase 1)
```

### Task List

The Lead creates these tasks via `TaskCreate` at startup:

| ID | Subject | Owner | blockedBy |
|----|---------|-------|-----------|
| 1 | Scaffold Go module, types, client, HTTP stubs | `architect` | — |
| 2 | Implement HTTP client layer (do method) | `builder-http` | 1 |
| 3 | Implement service methods (datasets, spans, projects) | `builder-services` | 1 |
| 4 | Review all generated code | `reviewer` | 2, 3 |
| 5 | Write and run tests for all public methods | `tester` | 2, 3 |
| 6 | Apply remediation fixes | _(Lead)_ | 4, 5 |
| 7 | Final verification and PR delivery | _(Lead)_ | 6 |

### Spawn Strategy

The Lead spawns teammates **on demand** using the `Agent` tool, not all at once.

| Phase | Lead action |
|-------|------------|
| **Phase 1** | Spawn **architect** via `Agent(name: "architect", team_name: "arize-sdk", model: "opus", isolation: "worktree", mode: "bypassPermissions")` |
| **Phase 2** | After architect goes idle → merge worktree → spawn **builder-http** and **builder-services** in parallel (two `Agent` calls in one message, both with `team_name: "arize-sdk"`, `model: "sonnet"`, `isolation: "worktree"`, `mode: "bypassPermissions"`) |
| **Phase 3** | After both builders go idle → merge worktrees → spawn **reviewer** and **tester** in parallel (two `Agent` calls, same pattern) |
| **Phase 4** | After reviewer and tester go idle → Lead applies remediation and delivers PR (0 teammates) → `TeamDelete` to clean up |

### Pipeline

```
TeamCreate("arize-sdk")
 ↓
Lead creates feat/arize-go-sdk branch
 ↓
TaskCreate (all 7 tasks) + TaskUpdate (dependencies)
 ↓
Agent(name="architect") → goes idle → Lead merges worktree
 ↓
Agent(name="builder-http") ‖ Agent(name="builder-services") → both go idle → Lead merges worktrees
 ↓
Agent(name="reviewer") ‖ Agent(name="tester") → both go idle → Lead collects feedback
 ↓
Remediation (max 1 round: Lead applies fixes, re-runs tests)
 ↓
Delivery (Lead pushes branch, creates PR)
 ↓
SendMessage shutdown to all teammates → TeamDelete
```

### Merge Order

**Phase 2 merge (Builders):** Both Builders run in parallel, but they may finish at different times. The merge order matters:

1. **HTTP must be merged first** — its `http.go` replaces the `panic("not implemented")` stub that Services' code calls at runtime
2. If Services goes idle before HTTP, the Lead **waits** for HTTP to go idle before merging either
3. Once HTTP is idle: merge HTTP worktree into `feat/arize-go-sdk`
4. Then merge Services worktree into `feat/arize-go-sdk`
5. Verify combined build: `go build ./...`

**Phase 3 (Reviewer + Tester):** Both go idle independently. The Reviewer and Tester must **message the Lead via `SendMessage`** with their results before going idle — idle notification alone is not enough because the Lead needs the structured review feedback and `go test` output to act on during remediation.

### Worktree Strategy

All teammates are spawned with `isolation: "worktree"` on the `Agent` tool, which gives each an isolated copy of the repo.

| Phase | Worktree handling |
|-------|------------------|
| **Architect** | Own worktree → Lead merges into `feat/arize-go-sdk`, verifies `go build ./...` |
| **Builder: HTTP** | Own worktree branched from `feat/arize-go-sdk` after Architect merge |
| **Builder: Services** | Own worktree branched from `feat/arize-go-sdk` after Architect merge, parallel with HTTP |
| **Reviewer** | Own worktree branched from `feat/arize-go-sdk` after both Builders merged (read-only, discarded after review) |
| **Tester** | Own worktree branched from `feat/arize-go-sdk` after both Builders merged → Lead merges test files |
| **Remediation** | Lead works directly on `feat/arize-go-sdk` (no worktree) |

### Teammate Messaging

All inter-agent communication uses the `SendMessage` tool. Upon being spawned, each teammate must `SendMessage(to: "lead", ...)` to confirm their role and the tasks they plan to complete before beginning work. If scope is unclear, ask before starting.

Explicit `SendMessage` calls are also required for:

- **reviewer → lead**: Structured review feedback (the Lead needs this to know what to fix)
- **tester → lead**: Full `go test ./... -v` output (the Lead needs this for remediation and the PR body)
- **Any teammate → lead**: Blocker alerts (e.g., Builder discovers Architect's stubs are insufficient — Lead updates types directly on the feature branch)

### Remediation Gate

If the Reviewer flags errors or tests fail, the Lead applies targeted fixes directly on `feat/arize-go-sdk` (max 1 remediation round). After fixes, re-run `go build ./...` and `go test ./... -v`. If still failing after 1 round, the Lead reports remaining issues in the PR description.

### Shutdown

After the PR is created, the Lead sends shutdown requests to all remaining teammates:
```
SendMessage(to: "<name>", message: { type: "shutdown_request", reason: "Pipeline complete" })
```
Then calls `TeamDelete` to clean up team and task files.

## 4. Architect's Blueprint Requirements

The Architect MUST produce these files before Builders start:

1. **`go.mod`** — `module arize-go` with Go 1.21

2. **`arize.go`** — Client struct, NewClient constructor, functional options, and service type skeletons. The HTTP helper methods live in `http.go`, not here:

```go
// Client is the root Arize API client. Safe for concurrent use after construction.
type Client struct {
	apiKey string
	baseURL string
	httpClient *http.Client

	Datasets *DatasetsService
	Spans    *SpansService
	Projects *ProjectsService
}

// Service types — defined here, methods implemented in their respective files.
type DatasetsService struct{ client *Client }
type SpansService    struct{ client *Client }
type ProjectsService struct{ client *Client }

func NewClient(apiKey string, opts ...Option) *Client {
	c := &Client{
		apiKey:     apiKey,
		baseURL:    "https://api.arize.com",
		httpClient: &http.Client{},
	}
	for _, opt := range opts {
		opt(c)
	}
	c.Datasets = &DatasetsService{client: c}
	c.Spans    = &SpansService{client: c}
	c.Projects = &ProjectsService{client: c}
	return c
}

type Option func(*Client)

func WithBaseURL(u string) Option    { return func(c *Client) { c.baseURL = u } }
func WithHTTPClient(h *http.Client) Option { return func(c *Client) { c.httpClient = h } }
```

3. **`http.go`** — HTTP helper method stubs. Builder: HTTP replaces only the `do` implementation; `get`, `post`, and `delete` are real (thin) wrappers that delegate to `do`. Stubs are in this file — NOT in `arize.go` — so Builder: HTTP can implement them without touching the client definition:

```go
// do is the central HTTP method. It:
// - Appends path to c.baseURL
// - Adds query params (if non-nil) to the URL
// - JSON-encodes body (if non-nil) and sets Content-Type: application/json
// - Sets Accept: application/json and User-Agent: arize-go/0.1.0
// - Sets Authorization: Bearer <apiKey>
// - Treats 200, 201, 204 as success; 204 responses have no body to decode
// - On non-2xx, decodes application/problem+json into *APIError
// - On 429, reads the Retry-After header (integer seconds) into APIError.RetryAfter
func (c *Client) do(ctx context.Context, method, path string, query url.Values, body, result interface{}) error {
	panic("not implemented")
}

func (c *Client) get(ctx context.Context, path string, query url.Values, result interface{}) error {
	return c.do(ctx, http.MethodGet, path, query, nil, result)
}

func (c *Client) post(ctx context.Context, path string, query url.Values, body, result interface{}) error {
	return c.do(ctx, http.MethodPost, path, query, body, result)
}

func (c *Client) delete(ctx context.Context, path string) error {
	return c.do(ctx, http.MethodDelete, path, nil, nil, nil)
}
```

4. **`types.go`** — All shared types. The Architect defines these exactly; Builders MUST NOT redefine them.

**Resource models** (all JSON tags use `snake_case` matching the API):

```go
type Dataset struct {
	ID        string           `json:"id"`
	Name      string           `json:"name"`
	SpaceID   string           `json:"space_id"`
	CreatedAt time.Time        `json:"created_at"`
	UpdatedAt time.Time        `json:"updated_at"`
	Versions  []DatasetVersion `json:"versions,omitempty"`
}

type DatasetVersion struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	DatasetID string    `json:"dataset_id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// DatasetExample maps all example fields — system-managed (id, created_at, updated_at)
// and user-defined — as raw JSON values. A map avoids schema constraints on user fields.
type DatasetExample map[string]json.RawMessage

type Project struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	SpaceID   string    `json:"space_id"`
	CreatedAt time.Time `json:"created_at"`
}

type Span struct {
	Name          string            `json:"name"`
	Context       SpanContext       `json:"context"`
	Kind          string            `json:"kind"`
	ParentID      string            `json:"parent_id,omitempty"`
	StartTime     time.Time         `json:"start_time"`
	EndTime       time.Time         `json:"end_time"`
	StatusCode    string            `json:"status_code,omitempty"` // "OK", "ERROR", or "UNSET"
	StatusMessage string            `json:"status_message,omitempty"`
	Attributes    map[string]any    `json:"attributes,omitempty"`
	Annotations   map[string]any    `json:"annotations,omitempty"`
	Evaluations   map[string]any    `json:"evaluations,omitempty"`
	Events        []SpanEvent       `json:"events,omitempty"`
}

type SpanContext struct {
	TraceID string `json:"trace_id"`
	SpanID  string `json:"span_id"`
}

type SpanEvent struct {
	Name       string         `json:"name"`
	Timestamp  time.Time      `json:"timestamp"`
	Attributes map[string]any `json:"attributes,omitempty"`
}
```

**Request and option types**:

```go
type ListDatasetsOptions struct {
	SpaceID string
	Name    string // substring filter; maps to the `name` query parameter
	Limit   int
	Cursor  string
}

type ListProjectsOptions struct {
	SpaceID string
	Name    string // substring filter; maps to the `name` query parameter
	Limit   int
	Cursor  string
}

// ListExamplesOptions for GET /v2/datasets/{id}/examples.
// Cursor pagination is not yet implemented by the API; do not send a cursor.
type ListExamplesOptions struct {
	DatasetVersionID string
	Limit            int
}

// ListSpansRequest for POST /v2/spans.
// ProjectID, StartTime, EndTime, and Filter are sent in the JSON body.
// Limit and Cursor are sent as query parameters (json:"-" keeps them out of the body).
type ListSpansRequest struct {
	ProjectID string     `json:"project_id"`
	StartTime *time.Time `json:"start_time,omitempty"`
	EndTime   *time.Time `json:"end_time,omitempty"`
	Filter    string     `json:"filter,omitempty"`
	Limit     int        `json:"-"` // query param
	Cursor    string     `json:"-"` // query param
}

type CreateDatasetRequest struct {
	Name     string                   `json:"name"`
	SpaceID  string                   `json:"space_id"`
	Examples []map[string]interface{} `json:"examples"`
}

type CreateProjectRequest struct {
	Name    string `json:"name"`
	SpaceID string `json:"space_id"`
}
```

**List response envelopes** — pagination is a named field (NOT embedded) so that JSON decoding
maps the `"pagination"` key to the `Pagination` field:

```go
type ListDatasetsResponse struct {
	Datasets   []Dataset      `json:"datasets"`
	Pagination PaginationMeta `json:"pagination"`
}

type ListProjectsResponse struct {
	Projects   []Project      `json:"projects"`
	Pagination PaginationMeta `json:"pagination"`
}

type ListSpansResponse struct {
	Spans      []Span         `json:"spans"`
	Pagination PaginationMeta `json:"pagination"`
}

type ListExamplesResponse struct {
	Examples   []DatasetExample `json:"examples"`
	Pagination PaginationMeta   `json:"pagination"`
}
```

5. **`errors.go`** — `APIError` struct implementing the `error` interface. Fields map to RFC 9457 Problem Details (`status`, `title`, `type`, `detail`, `instance`). `RetryAfter int` is excluded from JSON (`json:"-"`) and populated from the `Retry-After` header on 429s. `Error()` returns `"arize: <status> <title>: <detail>"` (omits detail if empty).

6. **`pagination.go`** — `PaginationMeta` struct with `HasMore bool` (`json:"has_more"`) and `NextCursor string` (`json:"next_cursor"`). Used as a named `Pagination` field in all list response types.

### Directory Layout

```
arize-go/
├── go.mod
├── CLAUDE.md
├── arize.go        # Client struct, NewClient, options, service type skeletons
├── types.go        # All shared types, request/option structs, response envelopes
├── errors.go       # APIError (RFC 9457 Problem Details)
├── pagination.go   # PaginationMeta
├── http.go         # HTTP helper stubs (Architect) → real implementations (Builder: HTTP)
├── datasets.go     # DatasetsService methods (Builder: Services)
├── spans.go        # SpansService methods (Builder: Services)
├── projects.go     # ProjectsService methods (Builder: Services)
├── datasets_test.go  # (Tester)
├── spans_test.go     # (Tester)
└── projects_test.go  # (Tester)
```

The Architect's types are the **SINGLE SOURCE OF TRUTH**. Builders MUST import and use them exactly — no redefining types.

## 5. Rules and Constraints

- Each agent works in an independent Git Worktree
- Code MUST compile (`go build ./...`) before any agent marks a task complete
- Builders MUST run `go vet` and `gofmt -s` on their code
- Tester MUST run `go test ./... -v` and include full output
- All public types and functions MUST have GoDoc comments
- **No third-party dependencies** — standard library only
- The Reviewer must produce feedback in this format per file:
  ```
  ## [filename]
  - Line X: [severity: error|warning|info] [description]
  Overall: [pass|needs-revision]
  ```
- JSON field tags must use `snake_case` matching the API (e.g., `json:"space_id"`)
- Use `*time.Time` for optional time fields in request structs (e.g., `StartTime`, `EndTime`)
- `DatasetExample` is `map[string]json.RawMessage` — do not define it as a struct
- The `do` method MUST set `Content-Type: application/json`, `Accept: application/json`, and `User-Agent: arize-go/0.1.0` on every request
- The `do` method MUST treat HTTP 200, 201, and 204 as success; skip response body decoding on 204
- On 429, parse the integer `Retry-After` response header and set `APIError.RetryAfter` — there is no `retry_after_seconds` body field

## 6. Delivery

The Lead performs the following steps to deliver the SDK:

1. Creates the feature branch `feat/arize-go-sdk` **at the start of the pipeline** (before spawning any teammates)
2. After each sequential teammate completes, merges their worktree branch into `feat/arize-go-sdk` and verifies `go build ./...`
3. After remediation is complete, runs final verification on `feat/arize-go-sdk`:
   - `go mod tidy`
   - `go build ./...`
   - `go vet ./...`
   - `gofmt -l .` (must produce no output)
   - `go test ./... -v` (capture full output for PR body)
4. Commits any remediation changes with message `fix: address review feedback`
5. Pushes `feat/arize-go-sdk` to origin
6. Creates PR via:
   ```
   gh pr create --base main --title "feat: Arize Go SDK (datasets, spans, projects)" --body "$(cat <<'EOF'
   ## Summary
   Production-quality Go client library for the Arize REST API v2.

   ### Implemented resources
   - **Datasets**: List, Get, Create, Delete, ListExamples
   - **Spans**: List (with filters, time range)
   - **Projects**: List, Get, Create, Delete

   ### Technical details
   - Zero dependencies (standard library only)
   - Cursor-based pagination
   - Typed error handling with APIError (RFC 9457 Problem Details)
   - Table-driven tests using net/http/httptest

   ### Test results
   <paste go test ./... -v output here>

   EOF
   )"
   ```

The PR is the **sole deliverable**. The pipeline is not complete until the PR URL is returned to the user.
