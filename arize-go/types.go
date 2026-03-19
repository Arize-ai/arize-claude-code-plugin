package arize

import (
	"encoding/json"
	"time"
)

// Dataset represents an Arize dataset resource.
type Dataset struct {
	ID        string           `json:"id"`
	Name      string           `json:"name"`
	SpaceID   string           `json:"space_id"`
	CreatedAt time.Time        `json:"created_at"`
	UpdatedAt time.Time        `json:"updated_at"`
	Versions  []DatasetVersion `json:"versions,omitempty"`
}

// DatasetVersion represents a version of an Arize dataset.
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

// Project represents an Arize project resource.
type Project struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	SpaceID   string    `json:"space_id"`
	CreatedAt time.Time `json:"created_at"`
}

// Span represents a trace span from the Arize API.
type Span struct {
	Name          string         `json:"name"`
	Context       SpanContext    `json:"context"`
	Kind          string         `json:"kind"`
	ParentID      string         `json:"parent_id,omitempty"`
	StartTime     time.Time      `json:"start_time"`
	EndTime       time.Time      `json:"end_time"`
	StatusCode    string         `json:"status_code,omitempty"` // "OK", "ERROR", or "UNSET"
	StatusMessage string         `json:"status_message,omitempty"`
	Attributes    map[string]any `json:"attributes,omitempty"`
	Annotations   map[string]any `json:"annotations,omitempty"`
	Evaluations   map[string]any `json:"evaluations,omitempty"`
	Events        []SpanEvent    `json:"events,omitempty"`
}

// SpanContext contains the trace and span identifiers for a span.
type SpanContext struct {
	TraceID string `json:"trace_id"`
	SpanID  string `json:"span_id"`
}

// SpanEvent represents an event that occurred during a span's lifetime.
type SpanEvent struct {
	Name       string         `json:"name"`
	Timestamp  time.Time      `json:"timestamp"`
	Attributes map[string]any `json:"attributes,omitempty"`
}

// ListDatasetsOptions specifies optional parameters for listing datasets.
type ListDatasetsOptions struct {
	SpaceID string
	Name    string // substring filter; maps to the `name` query parameter
	Limit   int
	Cursor  string
}

// ListProjectsOptions specifies optional parameters for listing projects.
type ListProjectsOptions struct {
	SpaceID string
	Name    string // substring filter; maps to the `name` query parameter
	Limit   int
	Cursor  string
}

// ListExamplesOptions specifies optional parameters for listing dataset examples.
// Cursor pagination is not yet implemented by the API; do not send a cursor.
type ListExamplesOptions struct {
	DatasetVersionID string
	Limit            int
}

// ListSpansRequest specifies the parameters for listing spans.
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

// CreateDatasetRequest specifies the parameters for creating a dataset.
type CreateDatasetRequest struct {
	Name     string                   `json:"name"`
	SpaceID  string                   `json:"space_id"`
	Examples []map[string]interface{} `json:"examples"`
}

// CreateProjectRequest specifies the parameters for creating a project.
type CreateProjectRequest struct {
	Name    string `json:"name"`
	SpaceID string `json:"space_id"`
}

// ListDatasetsResponse is the response envelope for listing datasets.
type ListDatasetsResponse struct {
	Datasets   []Dataset      `json:"datasets"`
	Pagination PaginationMeta `json:"pagination"`
}

// ListProjectsResponse is the response envelope for listing projects.
type ListProjectsResponse struct {
	Projects   []Project      `json:"projects"`
	Pagination PaginationMeta `json:"pagination"`
}

// ListSpansResponse is the response envelope for listing spans.
type ListSpansResponse struct {
	Spans      []Span         `json:"spans"`
	Pagination PaginationMeta `json:"pagination"`
}

// ListExamplesResponse is the response envelope for listing dataset examples.
type ListExamplesResponse struct {
	Examples   []DatasetExample `json:"examples"`
	Pagination PaginationMeta   `json:"pagination"`
}
