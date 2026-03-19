package arize

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// problemJSON returns an HTTP handler that responds with an RFC 9457 problem+json body.
func problemJSON(t *testing.T, status int, title, detail string) http.HandlerFunc {
	t.Helper()
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/problem+json")
		w.WriteHeader(status)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": status,
			"title":  title,
			"detail": detail,
		})
	}
}

func TestDatasetsService_List(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	tests := []struct {
		name       string
		opts       *ListDatasetsOptions
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
		check      func(t *testing.T, result *ListDatasetsResponse)
	}{
		{
			name: "success with no options",
			opts: nil,
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodGet {
					t.Errorf("expected GET, got %s", r.Method)
				}
				if r.URL.Path != "/v2/datasets" {
					t.Errorf("unexpected path: %s", r.URL.Path)
				}
				// Verify required headers.
				if got := r.Header.Get("Authorization"); got != "Bearer test-key" {
					t.Errorf("Authorization = %q, want %q", got, "Bearer test-key")
				}
				if got := r.Header.Get("Accept"); got != "application/json" {
					t.Errorf("Accept = %q, want %q", got, "application/json")
				}
				if got := r.Header.Get("User-Agent"); got != "arize-go/0.1.0" {
					t.Errorf("User-Agent = %q, want %q", got, "arize-go/0.1.0")
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(ListDatasetsResponse{
					Datasets: []Dataset{
						{ID: "ds1", Name: "my-dataset", SpaceID: "spc_123", CreatedAt: now, UpdatedAt: now},
					},
					Pagination: PaginationMeta{HasMore: false},
				})
			},
			check: func(t *testing.T, result *ListDatasetsResponse) {
				if len(result.Datasets) != 1 {
					t.Fatalf("expected 1 dataset, got %d", len(result.Datasets))
				}
				if result.Datasets[0].ID != "ds1" {
					t.Errorf("dataset ID = %q, want %q", result.Datasets[0].ID, "ds1")
				}
				if result.Pagination.HasMore {
					t.Error("expected HasMore=false")
				}
			},
		},
		{
			name: "success with all options sent as query params",
			opts: &ListDatasetsOptions{SpaceID: "spc_abc", Name: "test", Limit: 10, Cursor: "tok_xyz"},
			handler: func(w http.ResponseWriter, r *http.Request) {
				q := r.URL.Query()
				if got := q.Get("space_id"); got != "spc_abc" {
					t.Errorf("space_id = %q, want %q", got, "spc_abc")
				}
				if got := q.Get("name"); got != "test" {
					t.Errorf("name = %q, want %q", got, "test")
				}
				if got := q.Get("limit"); got != "10" {
					t.Errorf("limit = %q, want %q", got, "10")
				}
				if got := q.Get("cursor"); got != "tok_xyz" {
					t.Errorf("cursor = %q, want %q", got, "tok_xyz")
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(ListDatasetsResponse{
					Datasets:   []Dataset{{ID: "ds2", Name: "test"}},
					Pagination: PaginationMeta{HasMore: true, NextCursor: "tok_next"},
				})
			},
			check: func(t *testing.T, result *ListDatasetsResponse) {
				if !result.Pagination.HasMore {
					t.Error("expected HasMore=true")
				}
				if result.Pagination.NextCursor != "tok_next" {
					t.Errorf("NextCursor = %q, want %q", result.Pagination.NextCursor, "tok_next")
				}
			},
		},
		{
			name:       "404 error returns APIError",
			opts:       nil,
			handler:    problemJSON(t, http.StatusNotFound, "Not Found", "dataset not found"),
			wantErr:    true,
			wantErrMsg: "404",
		},
		{
			name: "429 error sets RetryAfter",
			opts: nil,
			handler: func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/problem+json")
				w.Header().Set("Retry-After", "30")
				w.WriteHeader(http.StatusTooManyRequests)
				json.NewEncoder(w).Encode(map[string]interface{}{
					"status": 429,
					"title":  "Too Many Requests",
					"detail": "rate limit exceeded",
				})
			},
			wantErr: true,
			check: func(t *testing.T, result *ListDatasetsResponse) {
				// check is called only on success; this won't run
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			result, err := client.Datasets.List(context.Background(), tt.opts)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if tt.wantErrMsg != "" && !strings.Contains(err.Error(), tt.wantErrMsg) {
					t.Errorf("error %q does not contain %q", err.Error(), tt.wantErrMsg)
				}
				// For 429, verify RetryAfter is set.
				if strings.Contains(tt.name, "429") {
					apiErr, ok := err.(*APIError)
					if !ok {
						t.Fatalf("expected *APIError, got %T", err)
					}
					if apiErr.RetryAfter != 30 {
						t.Errorf("RetryAfter = %d, want 30", apiErr.RetryAfter)
					}
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tt.check != nil {
				tt.check(t, result)
			}
		})
	}
}

func TestDatasetsService_Get(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	tests := []struct {
		name       string
		datasetID  string
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
		check      func(t *testing.T, result *Dataset)
	}{
		{
			name:      "success",
			datasetID: "ds-123",
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/v2/datasets/ds-123" {
					t.Errorf("unexpected path: %s", r.URL.Path)
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(Dataset{
					ID:        "ds-123",
					Name:      "my-dataset",
					SpaceID:   "spc_123",
					CreatedAt: now,
					UpdatedAt: now,
					Versions: []DatasetVersion{
						{ID: "v1", Name: "v1", DatasetID: "ds-123", CreatedAt: now, UpdatedAt: now},
					},
				})
			},
			check: func(t *testing.T, result *Dataset) {
				if result.ID != "ds-123" {
					t.Errorf("ID = %q, want %q", result.ID, "ds-123")
				}
				if len(result.Versions) != 1 {
					t.Errorf("expected 1 version, got %d", len(result.Versions))
				}
			},
		},
		{
			name:       "404 returns error",
			datasetID:  "nonexistent",
			handler:    problemJSON(t, http.StatusNotFound, "Not Found", "dataset not found"),
			wantErr:    true,
			wantErrMsg: "Not Found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			result, err := client.Datasets.Get(context.Background(), tt.datasetID)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if tt.wantErrMsg != "" && !strings.Contains(err.Error(), tt.wantErrMsg) {
					t.Errorf("error %q does not contain %q", err.Error(), tt.wantErrMsg)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tt.check != nil {
				tt.check(t, result)
			}
		})
	}
}

func TestDatasetsService_Create(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	tests := []struct {
		name       string
		req        *CreateDatasetRequest
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
		check      func(t *testing.T, result *Dataset)
	}{
		{
			name: "success returns 201 with dataset",
			req: &CreateDatasetRequest{
				Name:    "new-ds",
				SpaceID: "spc_123",
				Examples: []map[string]interface{}{
					{"input": "hello", "output": "world"},
				},
			},
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost {
					t.Errorf("expected POST, got %s", r.Method)
				}
				if r.URL.Path != "/v2/datasets" {
					t.Errorf("unexpected path: %s", r.URL.Path)
				}
				if ct := r.Header.Get("Content-Type"); ct != "application/json" {
					t.Errorf("Content-Type = %q, want application/json", ct)
				}
				// Decode and verify body.
				var body map[string]interface{}
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Fatalf("failed to decode request body: %v", err)
				}
				if body["name"] != "new-ds" {
					t.Errorf("body name = %v, want %q", body["name"], "new-ds")
				}
				if body["space_id"] != "spc_123" {
					t.Errorf("body space_id = %v, want %q", body["space_id"], "spc_123")
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusCreated)
				json.NewEncoder(w).Encode(Dataset{
					ID: "ds-new", Name: "new-ds", SpaceID: "spc_123", CreatedAt: now, UpdatedAt: now,
				})
			},
			check: func(t *testing.T, result *Dataset) {
				if result.ID != "ds-new" {
					t.Errorf("ID = %q, want %q", result.ID, "ds-new")
				}
				if result.Name != "new-ds" {
					t.Errorf("Name = %q, want %q", result.Name, "new-ds")
				}
			},
		},
		{
			name:       "server error returns APIError",
			req:        &CreateDatasetRequest{Name: "bad-ds", SpaceID: "spc_bad"},
			handler:    problemJSON(t, http.StatusBadRequest, "Bad Request", "invalid space_id"),
			wantErr:    true,
			wantErrMsg: "Bad Request",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			result, err := client.Datasets.Create(context.Background(), tt.req)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if tt.wantErrMsg != "" && !strings.Contains(err.Error(), tt.wantErrMsg) {
					t.Errorf("error %q does not contain %q", err.Error(), tt.wantErrMsg)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tt.check != nil {
				tt.check(t, result)
			}
		})
	}
}

func TestDatasetsService_Delete(t *testing.T) {
	tests := []struct {
		name       string
		datasetID  string
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
	}{
		{
			name:      "success returns 204",
			datasetID: "ds-del",
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodDelete {
					t.Errorf("expected DELETE, got %s", r.Method)
				}
				if r.URL.Path != "/v2/datasets/ds-del" {
					t.Errorf("unexpected path: %s", r.URL.Path)
				}
				w.WriteHeader(http.StatusNoContent)
			},
		},
		{
			name:       "404 returns error",
			datasetID:  "nonexistent",
			handler:    problemJSON(t, http.StatusNotFound, "Not Found", "dataset not found"),
			wantErr:    true,
			wantErrMsg: "Not Found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			err := client.Datasets.Delete(context.Background(), tt.datasetID)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if tt.wantErrMsg != "" && !strings.Contains(err.Error(), tt.wantErrMsg) {
					t.Errorf("error %q does not contain %q", err.Error(), tt.wantErrMsg)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestDatasetsService_ListExamples(t *testing.T) {
	tests := []struct {
		name       string
		datasetID  string
		opts       *ListExamplesOptions
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
		check      func(t *testing.T, result *ListExamplesResponse)
	}{
		{
			name:      "success returns examples",
			datasetID: "ds-123",
			opts:      &ListExamplesOptions{DatasetVersionID: "v1", Limit: 50},
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/v2/datasets/ds-123/examples" {
					t.Errorf("unexpected path: %s", r.URL.Path)
				}
				q := r.URL.Query()
				if got := q.Get("dataset_version_id"); got != "v1" {
					t.Errorf("dataset_version_id = %q, want %q", got, "v1")
				}
				if got := q.Get("limit"); got != "50" {
					t.Errorf("limit = %q, want %q", got, "50")
				}
				// cursor must NOT be sent.
				if q.Has("cursor") {
					t.Error("cursor param should not be sent for ListExamples")
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				// Build a raw example.
				exRaw := map[string]json.RawMessage{
					"id":    json.RawMessage(`"ex-1"`),
					"input": json.RawMessage(`"hello"`),
				}
				json.NewEncoder(w).Encode(ListExamplesResponse{
					Examples:   []DatasetExample{exRaw},
					Pagination: PaginationMeta{HasMore: false},
				})
			},
			check: func(t *testing.T, result *ListExamplesResponse) {
				if len(result.Examples) != 1 {
					t.Fatalf("expected 1 example, got %d", len(result.Examples))
				}
				ex := result.Examples[0]
				if _, ok := ex["id"]; !ok {
					t.Error("expected 'id' key in example")
				}
			},
		},
		{
			name:      "cursor param is never sent even when opts has no cursor field",
			datasetID: "ds-456",
			opts:      &ListExamplesOptions{Limit: 10},
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Query().Has("cursor") {
					t.Error("cursor param must not be sent for ListExamples")
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(ListExamplesResponse{
					Examples:   []DatasetExample{},
					Pagination: PaginationMeta{HasMore: false},
				})
			},
			check: func(t *testing.T, result *ListExamplesResponse) {
				if len(result.Examples) != 0 {
					t.Errorf("expected 0 examples, got %d", len(result.Examples))
				}
			},
		},
		{
			name:       "error response",
			datasetID:  "bad-ds",
			opts:       nil,
			handler:    problemJSON(t, http.StatusNotFound, "Not Found", "dataset not found"),
			wantErr:    true,
			wantErrMsg: "Not Found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			result, err := client.Datasets.ListExamples(context.Background(), tt.datasetID, tt.opts)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if tt.wantErrMsg != "" && !strings.Contains(err.Error(), tt.wantErrMsg) {
					t.Errorf("error %q does not contain %q", err.Error(), tt.wantErrMsg)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tt.check != nil {
				tt.check(t, result)
			}
		})
	}
}
