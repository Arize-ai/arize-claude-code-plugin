package arize

import (
	"context"
	"net/http"
	"net/url"
)

// do is the central HTTP method. It:
//   - Appends path to c.baseURL
//   - Adds query params (if non-nil) to the URL
//   - JSON-encodes body (if non-nil) and sets Content-Type: application/json
//   - Sets Accept: application/json and User-Agent: arize-go/0.1.0
//   - Sets Authorization: Bearer <apiKey>
//   - Treats 200, 201, 204 as success; 204 responses have no body to decode
//   - On non-2xx, decodes application/problem+json into *APIError
//   - On 429, reads the Retry-After header (integer seconds) into APIError.RetryAfter
func (c *Client) do(ctx context.Context, method, path string, query url.Values, body, result interface{}) error {
	panic("not implemented")
}

// get performs an HTTP GET request to the given path with optional query parameters.
func (c *Client) get(ctx context.Context, path string, query url.Values, result interface{}) error {
	return c.do(ctx, http.MethodGet, path, query, nil, result)
}

// post performs an HTTP POST request to the given path with optional query parameters and a JSON body.
func (c *Client) post(ctx context.Context, path string, query url.Values, body, result interface{}) error {
	return c.do(ctx, http.MethodPost, path, query, body, result)
}

// delete performs an HTTP DELETE request to the given path.
func (c *Client) delete(ctx context.Context, path string) error {
	return c.do(ctx, http.MethodDelete, path, nil, nil, nil)
}
