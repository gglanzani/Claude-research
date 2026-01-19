package storage

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/gglanzani/podcast/internal/config"
)

// Local implements Storage using the local filesystem
type Local struct {
	basePath    string
	externalURL string
}

// NewLocal creates a new local filesystem storage
func NewLocal(cfg *config.Config) (*Local, error) {
	// Create base directory if it doesn't exist
	if err := os.MkdirAll(cfg.LocalPath, 0755); err != nil {
		return nil, fmt.Errorf("failed to create storage directory: %w", err)
	}

	// Create subdirectories
	for _, subdir := range []string{"audio", "chapters"} {
		path := filepath.Join(cfg.LocalPath, subdir)
		if err := os.MkdirAll(path, 0755); err != nil {
			return nil, fmt.Errorf("failed to create %s directory: %w", subdir, err)
		}
	}

	return &Local{
		basePath:    cfg.LocalPath,
		externalURL: cfg.ExternalURL,
	}, nil
}

func (l *Local) Upload(ctx context.Context, filename string, content io.Reader, contentType string) (string, error) {
	fullPath := filepath.Join(l.basePath, filename)

	// Ensure parent directory exists
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		return "", fmt.Errorf("failed to create directory: %w", err)
	}

	file, err := os.Create(fullPath)
	if err != nil {
		return "", fmt.Errorf("failed to create file: %w", err)
	}
	defer file.Close()

	if _, err := io.Copy(file, content); err != nil {
		return "", fmt.Errorf("failed to write file: %w", err)
	}

	return l.GetPublicURL(filename), nil
}

func (l *Local) Download(ctx context.Context, filename string) (io.ReadCloser, error) {
	fullPath := filepath.Join(l.basePath, filename)
	file, err := os.Open(fullPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open file: %w", err)
	}
	return file, nil
}

func (l *Local) Delete(ctx context.Context, filename string) error {
	fullPath := filepath.Join(l.basePath, filename)
	if err := os.Remove(fullPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to delete file: %w", err)
	}
	return nil
}

func (l *Local) Exists(ctx context.Context, filename string) (bool, error) {
	fullPath := filepath.Join(l.basePath, filename)
	_, err := os.Stat(fullPath)
	if err == nil {
		return true, nil
	}
	if os.IsNotExist(err) {
		return false, nil
	}
	return false, fmt.Errorf("failed to check file: %w", err)
}

func (l *Local) GetPublicURL(filename string) string {
	return fmt.Sprintf("%s/files/%s", l.externalURL, filename)
}

// GetBasePath returns the base storage path (for serving files)
func (l *Local) GetBasePath() string {
	return l.basePath
}
