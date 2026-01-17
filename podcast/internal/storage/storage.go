package storage

import (
	"context"
	"fmt"
	"io"

	"github.com/gglanzani/podcast/internal/config"
)

// Storage defines the interface for file storage backends
type Storage interface {
	// Upload uploads a file and returns its public URL
	Upload(ctx context.Context, filename string, content io.Reader, contentType string) (string, error)

	// Download retrieves a file's content
	Download(ctx context.Context, filename string) (io.ReadCloser, error)

	// Delete removes a file
	Delete(ctx context.Context, filename string) error

	// Exists checks if a file exists
	Exists(ctx context.Context, filename string) (bool, error)

	// GetPublicURL returns the public URL for a file
	GetPublicURL(filename string) string
}

// New creates a new storage backend based on configuration
func New(cfg *config.Config) (Storage, error) {
	switch cfg.StorageType {
	case "gcs":
		return NewGCS(cfg)
	case "local":
		return NewLocal(cfg)
	default:
		return nil, fmt.Errorf("unknown storage type: %s", cfg.StorageType)
	}
}
