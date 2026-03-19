// Package arize provides a Go client for the Arize REST API v2.
//
// The client supports Datasets, Spans, and Projects resources with
// cursor-based pagination and typed error handling.
package arize

import "net/http"

// Client is the root Arize API client. Safe for concurrent use after construction.
type Client struct {
	apiKey     string
	baseURL    string
	httpClient *http.Client

	// Datasets provides access to the Datasets API.
	Datasets *DatasetsService

	// Spans provides access to the Spans API.
	Spans *SpansService

	// Projects provides access to the Projects API.
	Projects *ProjectsService
}

// DatasetsService handles communication with the dataset-related endpoints of the Arize API.
type DatasetsService struct{ client *Client }

// SpansService handles communication with the span-related endpoints of the Arize API.
type SpansService struct{ client *Client }

// ProjectsService handles communication with the project-related endpoints of the Arize API.
type ProjectsService struct{ client *Client }

// NewClient creates a new Arize API client with the given API key.
// Use functional options to configure the client (e.g., WithBaseURL, WithHTTPClient).
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
	c.Spans = &SpansService{client: c}
	c.Projects = &ProjectsService{client: c}
	return c
}

// Option is a functional option for configuring the Client.
type Option func(*Client)

// WithBaseURL sets a custom base URL for the Arize API.
func WithBaseURL(u string) Option { return func(c *Client) { c.baseURL = u } }

// WithHTTPClient sets a custom HTTP client for the Arize API client.
func WithHTTPClient(h *http.Client) Option { return func(c *Client) { c.httpClient = h } }
