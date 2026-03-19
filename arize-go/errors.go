package arize

import "fmt"

// APIError represents an error response from the Arize API.
// Fields map to RFC 9457 Problem Details (status, title, type, detail, instance).
type APIError struct {
	// Status is the HTTP status code returned by the API.
	Status int `json:"status"`

	// Title is a short, human-readable summary of the problem type.
	Title string `json:"title"`

	// Type is a URI reference that identifies the problem type.
	Type string `json:"type"`

	// Detail is a human-readable explanation specific to this occurrence.
	Detail string `json:"detail"`

	// Instance is a URI reference that identifies the specific occurrence.
	Instance string `json:"instance"`

	// RetryAfter is the number of seconds to wait before retrying (from the Retry-After header on 429 responses).
	// It is not part of the JSON response body.
	RetryAfter int `json:"-"`
}

// Error returns a string representation of the API error.
// Format: "arize: <status> <title>: <detail>" (omits detail if empty).
func (e *APIError) Error() string {
	if e.Detail != "" {
		return fmt.Sprintf("arize: %d %s: %s", e.Status, e.Title, e.Detail)
	}
	return fmt.Sprintf("arize: %d %s", e.Status, e.Title)
}
