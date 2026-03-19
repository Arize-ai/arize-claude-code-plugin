package arize

// PaginationMeta contains cursor-based pagination metadata returned by list endpoints.
type PaginationMeta struct {
	HasMore    bool   `json:"has_more"`
	NextCursor string `json:"next_cursor"`
}
