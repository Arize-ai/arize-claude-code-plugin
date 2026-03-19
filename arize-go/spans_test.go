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

func TestSpansService_List(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	tests := []struct {
		name       string
		req        *ListSpansRequest
		handler    http.HandlerFunc
		wantErr    bool
		wantErrMsg string
		check      func(t *testing.T, result *ListSpansResponse)
	}{
		{
			name: "success with required project_id in body",
			req: &ListSpansRequest{
				ProjectID: "proj-123",
				Limit:     50,
				Cursor:    "tok_abc",
			},
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost {
					t.Errorf("expected POST, got %s", r.Method)
				}
				if r.URL.Path != "/v2/spans" {
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
				// Verify limit and cursor are query params, not body fields.
				q := r.URL.Query()
				if got := q.Get("limit"); got != "50" {
					t.Errorf("limit query param = %q, want %q", got, "50")
				}
				if got := q.Get("cursor"); got != "tok_abc" {
					t.Errorf("cursor query param = %q, want %q", got, "tok_abc")
				}
				// Verify project_id is in the body, not query.
				var body map[string]interface{}
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Fatalf("failed to decode request body: %v", err)
				}
				if body["project_id"] != "proj-123" {
					t.Errorf("body project_id = %v, want %q", body["project_id"], "proj-123")
				}
				// limit and cursor must NOT appear in the body.
				if _, ok := body["limit"]; ok {
					t.Error("limit should not appear in request body")
				}
				if _, ok := body["cursor"]; ok {
					t.Error("cursor should not appear in request body")
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(ListSpansResponse{
					Spans: []Span{
						{
							Name:       "my-span",
							Context:    SpanContext{TraceID: "trace-1", SpanID: "span-1"},
							Kind:       "SERVER",
							StartTime:  now,
							EndTime:    now.Add(time.Second),
							StatusCode: "OK",
						},
					},
					Pagination: PaginationMeta{HasMore: false},
				})
			},
			check: func(t *testing.T, result *ListSpansResponse) {
				if len(result.Spans) != 1 {
					t.Fatalf("expected 1 span, got %d", len(result.Spans))
				}
				if result.Spans[0].Name != "my-span" {
					t.Errorf("span Name = %q, want %q", result.Spans[0].Name, "my-span")
				}
				if result.Spans[0].Context.TraceID != "trace-1" {
					t.Errorf("trace_id = %q, want %q", result.Spans[0].Context.TraceID, "trace-1")
				}
				if result.Pagination.HasMore {
					t.Error("expected HasMore=false")
				}
			},
		},
		{
			name: "success with optional filter and time range in body",
			req: &ListSpansRequest{
				ProjectID: "proj-456",
				Filter:    "status_code = 'ERROR'",
				StartTime: &now,
				EndTime:   func() *time.Time { t := now.Add(time.Hour); return &t }(),
			},
			handler: func(w http.ResponseWriter, r *http.Request) {
				var body map[string]interface{}
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Fatalf("failed to decode body: %v", err)
				}
				if body["filter"] != "status_code = 'ERROR'" {
					t.Errorf("body filter = %v, want %q", body["filter"], "status_code = 'ERROR'")
				}
				if body["start_time"] == nil {
					t.Error("start_time should be in body")
				}
				if body["end_time"] == nil {
					t.Error("end_time should be in body")
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(ListSpansResponse{
					Spans:      []Span{},
					Pagination: PaginationMeta{HasMore: false},
				})
			},
			check: func(t *testing.T, result *ListSpansResponse) {
				if len(result.Spans) != 0 {
					t.Errorf("expected 0 spans, got %d", len(result.Spans))
				}
			},
		},
		{
			name: "success with pagination has_more=true",
			req:  &ListSpansRequest{ProjectID: "proj-789"},
			handler: func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(ListSpansResponse{
					Spans:      []Span{{Name: "span-a"}},
					Pagination: PaginationMeta{HasMore: true, NextCursor: "tok_next"},
				})
			},
			check: func(t *testing.T, result *ListSpansResponse) {
				if !result.Pagination.HasMore {
					t.Error("expected HasMore=true")
				}
				if result.Pagination.NextCursor != "tok_next" {
					t.Errorf("NextCursor = %q, want %q", result.Pagination.NextCursor, "tok_next")
				}
			},
		},
		{
			name:       "500 error returns APIError",
			req:        &ListSpansRequest{ProjectID: "proj-err"},
			handler:    problemJSON(t, http.StatusInternalServerError, "Internal Server Error", "unexpected failure"),
			wantErr:    true,
			wantErrMsg: "Internal Server Error",
		},
		{
			name:       "404 error returns APIError",
			req:        &ListSpansRequest{ProjectID: "proj-missing"},
			handler:    problemJSON(t, http.StatusNotFound, "Not Found", "project not found"),
			wantErr:    true,
			wantErrMsg: "Not Found",
		},
		{
			name: "429 error sets RetryAfter on APIError",
			req:  &ListSpansRequest{ProjectID: "proj-rate"},
			handler: func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/problem+json")
				w.Header().Set("Retry-After", "60")
				w.WriteHeader(http.StatusTooManyRequests)
				json.NewEncoder(w).Encode(map[string]interface{}{
					"status": 429,
					"title":  "Too Many Requests",
					"detail": "rate limit exceeded",
				})
			},
			wantErr: true,
			check: func(t *testing.T, result *ListSpansResponse) {
				// not called on error path
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(tt.handler)
			defer srv.Close()
			client := NewClient("test-key", WithBaseURL(srv.URL))
			result, err := client.Spans.List(context.Background(), tt.req)
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
					if apiErr.RetryAfter != 60 {
						t.Errorf("RetryAfter = %d, want 60", apiErr.RetryAfter)
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
