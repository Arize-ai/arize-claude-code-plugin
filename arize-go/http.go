package arize

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
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
	// Build the full URL.
	rawURL := strings.TrimRight(c.baseURL, "/") + path
	parsedURL, err := url.Parse(rawURL)
	if err != nil {
		return fmt.Errorf("arize: invalid URL %q: %w", rawURL, err)
	}
	if len(query) > 0 {
		parsedURL.RawQuery = query.Encode()
	}

	// Encode the request body.
	var bodyReader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("arize: failed to encode request body: %w", err)
		}
		bodyReader = bytes.NewReader(encoded)
	}

	// Create the request.
	req, err := http.NewRequestWithContext(ctx, method, parsedURL.String(), bodyReader)
	if err != nil {
		return fmt.Errorf("arize: failed to create request: %w", err)
	}

	// Set headers.
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "arize-go/0.1.0")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	// Execute the request.
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("arize: request failed: %w", err)
	}
	defer resp.Body.Close()

	// Handle success responses.
	switch resp.StatusCode {
	case http.StatusOK, http.StatusCreated:
		if result != nil {
			if err := json.NewDecoder(resp.Body).Decode(result); err != nil {
				return fmt.Errorf("arize: failed to decode response: %w", err)
			}
		}
		return nil
	case http.StatusNoContent:
		// No body to decode.
		return nil
	}

	// Non-2xx: decode the problem+json error body.
	apiErr := &APIError{}
	if err := json.NewDecoder(resp.Body).Decode(apiErr); err != nil {
		// If we can't decode the error body, still return a meaningful error.
		return fmt.Errorf("arize: unexpected status %d", resp.StatusCode)
	}
	// Ensure the status field is populated even if the body didn't include it.
	if apiErr.Status == 0 {
		apiErr.Status = resp.StatusCode
	}

	// On 429, parse the Retry-After header.
	if resp.StatusCode == http.StatusTooManyRequests {
		if retryAfter := resp.Header.Get("Retry-After"); retryAfter != "" {
			if seconds, err := strconv.Atoi(retryAfter); err == nil {
				apiErr.RetryAfter = seconds
			}
		}
	}

	return apiErr
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
