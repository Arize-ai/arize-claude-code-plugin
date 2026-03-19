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

func TestProjectsService_List(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	tests := []struct {
		name       string
		opts       *ListProjectsOptions
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
		check      func(t *testing.T, result *ListProjectsResponse)
	}{
		{
			name: "success with no options",
			opts: nil,
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodGet {
					t.Errorf("expected GET, got %s", r.Method)
				}
				if r.URL.Path != "/v2/projects" {
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
				json.NewEncoder(w).Encode(ListProjectsResponse{
					Projects: []Project{
						{ID: "proj-1", Name: "my-project", SpaceID: "spc_123", CreatedAt: now},
					},
					Pagination: PaginationMeta{HasMore: false},
				})
			},
			check: func(t *testing.T, result *ListProjectsResponse) {
				if len(result.Projects) != 1 {
					t.Fatalf("expected 1 project, got %d", len(result.Projects))
				}
				if result.Projects[0].ID != "proj-1" {
					t.Errorf("project ID = %q, want %q", result.Projects[0].ID, "proj-1")
				}
				if result.Pagination.HasMore {
					t.Error("expected HasMore=false")
				}
			},
		},
		{
			name: "success with all options as query params",
			opts: &ListProjectsOptions{SpaceID: "spc_abc", Name: "test", Limit: 20, Cursor: "tok_xyz"},
			handler: func(w http.ResponseWriter, r *http.Request) {
				q := r.URL.Query()
				if got := q.Get("space_id"); got != "spc_abc" {
					t.Errorf("space_id = %q, want %q", got, "spc_abc")
				}
				if got := q.Get("name"); got != "test" {
					t.Errorf("name = %q, want %q", got, "test")
				}
				if got := q.Get("limit"); got != "20" {
					t.Errorf("limit = %q, want %q", got, "20")
				}
				if got := q.Get("cursor"); got != "tok_xyz" {
					t.Errorf("cursor = %q, want %q", got, "tok_xyz")
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(ListProjectsResponse{
					Projects:   []Project{{ID: "proj-2", Name: "test"}},
					Pagination: PaginationMeta{HasMore: true, NextCursor: "tok_next"},
				})
			},
			check: func(t *testing.T, result *ListProjectsResponse) {
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
			handler:    problemJSON(t, http.StatusNotFound, "Not Found", "space not found"),
			wantErr:    true,
			wantErrMsg: "404",
		},
		{
			name: "429 error sets RetryAfter",
			opts: nil,
			handler: func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/problem+json")
				w.Header().Set("Retry-After", "45")
				w.WriteHeader(http.StatusTooManyRequests)
				json.NewEncoder(w).Encode(map[string]interface{}{
					"status": 429,
					"title":  "Too Many Requests",
					"detail": "rate limit exceeded",
				})
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			result, err := client.Projects.List(context.Background(), tt.opts)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if tt.wantErrMsg != "" && !strings.Contains(err.Error(), tt.wantErrMsg) {
					t.Errorf("error %q does not contain %q", err.Error(), tt.wantErrMsg)
				}
				if strings.Contains(tt.name, "429") {
					apiErr, ok := err.(*APIError)
					if !ok {
						t.Fatalf("expected *APIError, got %T", err)
					}
					if apiErr.RetryAfter != 45 {
						t.Errorf("RetryAfter = %d, want 45", apiErr.RetryAfter)
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

func TestProjectsService_Get(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	tests := []struct {
		name       string
		projectID  string
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
		check      func(t *testing.T, result *Project)
	}{
		{
			name:      "success",
			projectID: "proj-123",
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/v2/projects/proj-123" {
					t.Errorf("unexpected path: %s", r.URL.Path)
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(Project{
					ID:        "proj-123",
					Name:      "my-project",
					SpaceID:   "spc_123",
					CreatedAt: now,
				})
			},
			check: func(t *testing.T, result *Project) {
				if result.ID != "proj-123" {
					t.Errorf("ID = %q, want %q", result.ID, "proj-123")
				}
				if result.Name != "my-project" {
					t.Errorf("Name = %q, want %q", result.Name, "my-project")
				}
			},
		},
		{
			name:       "404 returns error",
			projectID:  "nonexistent",
			handler:    problemJSON(t, http.StatusNotFound, "Not Found", "project not found"),
			wantErr:    true,
			wantErrMsg: "Not Found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			result, err := client.Projects.Get(context.Background(), tt.projectID)
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

func TestProjectsService_Create(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	tests := []struct {
		name       string
		req        *CreateProjectRequest
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
		check      func(t *testing.T, result *Project)
	}{
		{
			name: "success returns 201 with project",
			req:  &CreateProjectRequest{Name: "new-proj", SpaceID: "spc_123"},
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost {
					t.Errorf("expected POST, got %s", r.Method)
				}
				if r.URL.Path != "/v2/projects" {
					t.Errorf("unexpected path: %s", r.URL.Path)
				}
				if ct := r.Header.Get("Content-Type"); ct != "application/json" {
					t.Errorf("Content-Type = %q, want application/json", ct)
				}
				var body map[string]interface{}
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Fatalf("failed to decode body: %v", err)
				}
				if body["name"] != "new-proj" {
					t.Errorf("body name = %v, want %q", body["name"], "new-proj")
				}
				if body["space_id"] != "spc_123" {
					t.Errorf("body space_id = %v, want %q", body["space_id"], "spc_123")
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusCreated)
				json.NewEncoder(w).Encode(Project{
					ID: "proj-new", Name: "new-proj", SpaceID: "spc_123", CreatedAt: now,
				})
			},
			check: func(t *testing.T, result *Project) {
				if result.ID != "proj-new" {
					t.Errorf("ID = %q, want %q", result.ID, "proj-new")
				}
				if result.Name != "new-proj" {
					t.Errorf("Name = %q, want %q", result.Name, "new-proj")
				}
			},
		},
		{
			name:       "bad request returns APIError",
			req:        &CreateProjectRequest{Name: "", SpaceID: "spc_bad"},
			handler:    problemJSON(t, http.StatusBadRequest, "Bad Request", "name is required"),
			wantErr:    true,
			wantErrMsg: "Bad Request",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			result, err := client.Projects.Create(context.Background(), tt.req)
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

func TestProjectsService_Delete(t *testing.T) {
	tests := []struct {
		name       string
		projectID  string
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
	}{
		{
			name:      "success returns 204",
			projectID: "proj-del",
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodDelete {
					t.Errorf("expected DELETE, got %s", r.Method)
				}
				if r.URL.Path != "/v2/projects/proj-del" {
					t.Errorf("unexpected path: %s", r.URL.Path)
				}
				w.WriteHeader(http.StatusNoContent)
			},
		},
		{
			name:       "404 returns error",
			projectID:  "nonexistent",
			handler:    problemJSON(t, http.StatusNotFound, "Not Found", "project not found"),
			wantErr:    true,
			wantErrMsg: "Not Found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			err := client.Projects.Delete(context.Background(), tt.projectID)
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
