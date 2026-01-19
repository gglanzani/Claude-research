package storage

import (
	"context"
	"fmt"
	"io"

	gcs "cloud.google.com/go/storage"
	"github.com/gglanzani/podcast/internal/config"
)

// GCS implements Storage using Google Cloud Storage
type GCS struct {
	client     *gcs.Client
	bucketName string
	bucket     *gcs.BucketHandle
}

// NewGCS creates a new Google Cloud Storage backend
func NewGCS(cfg *config.Config) (*GCS, error) {
	ctx := context.Background()

	client, err := gcs.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create GCS client: %w", err)
	}

	return &GCS{
		client:     client,
		bucketName: cfg.GCSBucketName,
		bucket:     client.Bucket(cfg.GCSBucketName),
	}, nil
}

func (g *GCS) Upload(ctx context.Context, filename string, content io.Reader, contentType string) (string, error) {
	obj := g.bucket.Object(filename)
	writer := obj.NewWriter(ctx)
	writer.ContentType = contentType

	// Make the object publicly readable
	writer.ACL = []gcs.ACLRule{
		{Entity: gcs.AllUsers, Role: gcs.RoleReader},
	}

	if _, err := io.Copy(writer, content); err != nil {
		writer.Close()
		return "", fmt.Errorf("failed to upload to GCS: %w", err)
	}

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("failed to finalize GCS upload: %w", err)
	}

	return g.GetPublicURL(filename), nil
}

func (g *GCS) Download(ctx context.Context, filename string) (io.ReadCloser, error) {
	obj := g.bucket.Object(filename)
	reader, err := obj.NewReader(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to download from GCS: %w", err)
	}
	return reader, nil
}

func (g *GCS) Delete(ctx context.Context, filename string) error {
	obj := g.bucket.Object(filename)
	if err := obj.Delete(ctx); err != nil && err != gcs.ErrObjectNotExist {
		return fmt.Errorf("failed to delete from GCS: %w", err)
	}
	return nil
}

func (g *GCS) Exists(ctx context.Context, filename string) (bool, error) {
	obj := g.bucket.Object(filename)
	_, err := obj.Attrs(ctx)
	if err == gcs.ErrObjectNotExist {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("failed to check GCS object: %w", err)
	}
	return true, nil
}

func (g *GCS) GetPublicURL(filename string) string {
	return fmt.Sprintf("https://storage.googleapis.com/%s/%s", g.bucketName, filename)
}

// Close closes the GCS client
func (g *GCS) Close() error {
	return g.client.Close()
}
