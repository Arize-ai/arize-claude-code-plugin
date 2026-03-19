package arize

import (
	"context"
	"fmt"
	"net/url"
	"strconv"
)

// List retrieves all projects, optionally filtered by the given options.
func (s *ProjectsService) List(ctx context.Context, opts *ListProjectsOptions) (*ListProjectsResponse, error) {
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
	var result ListProjectsResponse
	if err := s.client.get(ctx, "/v2/projects", q, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// Get retrieves a project by its ID.
func (s *ProjectsService) Get(ctx context.Context, projectID string) (*Project, error) {
	var result Project
	if err := s.client.get(ctx, fmt.Sprintf("/v2/projects/%s", projectID), nil, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// Create creates a new project.
func (s *ProjectsService) Create(ctx context.Context, req *CreateProjectRequest) (*Project, error) {
	var result Project
	if err := s.client.post(ctx, "/v2/projects", nil, req, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// Delete deletes a project by its ID.
func (s *ProjectsService) Delete(ctx context.Context, projectID string) error {
	return s.client.delete(ctx, fmt.Sprintf("/v2/projects/%s", projectID))
}
