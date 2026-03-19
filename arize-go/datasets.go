package arize

import (
	"context"
	"fmt"
	"net/url"
	"strconv"
)

// List retrieves all datasets, optionally filtered by the given options.
func (s *DatasetsService) List(ctx context.Context, opts *ListDatasetsOptions) (*ListDatasetsResponse, error) {
	q := url.Values{}
	if opts != nil {
		if opts.SpaceID != "" {
			q.Set("space_id", opts.SpaceID)
		}
		if opts.Name != "" {
			q.Set("name", opts.Name)
		}
		if opts.Limit > 0 {
			q.Set("limit", strconv.Itoa(opts.Limit))
		}
		if opts.Cursor != "" {
			q.Set("cursor", opts.Cursor)
		}
	}
	var result ListDatasetsResponse
	if err := s.client.get(ctx, "/v2/datasets", q, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// Get retrieves a dataset by its ID.
func (s *DatasetsService) Get(ctx context.Context, datasetID string) (*Dataset, error) {
	var result Dataset
	if err := s.client.get(ctx, fmt.Sprintf("/v2/datasets/%s", datasetID), nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// Create creates a new dataset.
func (s *DatasetsService) Create(ctx context.Context, req *CreateDatasetRequest) (*Dataset, error) {
	var result Dataset
	if err := s.client.post(ctx, "/v2/datasets", nil, req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// Delete deletes a dataset by its ID.
func (s *DatasetsService) Delete(ctx context.Context, datasetID string) error {
	return s.client.delete(ctx, fmt.Sprintf("/v2/datasets/%s", datasetID))
}

// ListExamples retrieves examples for a dataset.
// Note: cursor pagination is not yet implemented by the API; do not send cursor param.
func (s *DatasetsService) ListExamples(ctx context.Context, datasetID string, opts *ListExamplesOptions) (*ListExamplesResponse, error) {
	q := url.Values{}
	if opts != nil {
		if opts.DatasetVersionID != "" {
			q.Set("dataset_version_id", opts.DatasetVersionID)
		}
		if opts.Limit > 0 {
			q.Set("limit", strconv.Itoa(opts.Limit))
		}
	}
	var result ListExamplesResponse
	if err := s.client.get(ctx, fmt.Sprintf("/v2/datasets/%s/examples", datasetID), q, &result); err != nil {
		return nil, err
	}
	return &result, nil
}
