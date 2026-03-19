package arize

import (
	"context"
	"net/url"
	"strconv"
)

// List retrieves spans matching the given request parameters.
// ProjectID is required. StartTime, EndTime, and Filter are optional body fields.
// Limit and Cursor are sent as query parameters.
func (s *SpansService) List(ctx context.Context, req *ListSpansRequest) (*ListSpansResponse, error) {
	q := url.Values{}
	if req != nil {
		if req.Limit > 0 {
			q.Set("limit", strconv.Itoa(req.Limit))
		}
		if req.Cursor != "" {
			q.Set("cursor", req.Cursor)
		}
	}
	var result ListSpansResponse
	if err := s.client.post(ctx, "/v2/spans", q, req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}
