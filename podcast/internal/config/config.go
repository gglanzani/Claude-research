package config

import (
	"fmt"
	"os"
	"strconv"
)

// Config holds all application configuration
type Config struct {
	// Server settings
	Port        string
	ExternalURL string

	// GCS settings
	GCSBucketName string
	GCSProjectID  string

	// Storage type: "gcs" or "local"
	StorageType string
	LocalPath   string // For local storage

	// Podcast metadata
	PodcastTitle       string
	PodcastDescription string
	PodcastAuthor      string
	PodcastEmail       string
	PodcastLanguage    string
	PodcastImageURL    string

	// yt-dlp settings
	YTDLPPath    string
	AudioFormat  string
	AudioQuality int
}

// Load reads configuration from environment variables
func Load() (*Config, error) {
	cfg := &Config{
		Port:               getEnv("PORT", "8080"),
		ExternalURL:        getEnv("EXTERNAL_URL", "http://localhost:8080"),
		GCSBucketName:      os.Getenv("GCS_BUCKET_NAME"),
		GCSProjectID:       os.Getenv("GCS_PROJECT_ID"),
		StorageType:        getEnv("STORAGE_TYPE", "local"),
		LocalPath:          getEnv("LOCAL_STORAGE_PATH", "./data"),
		PodcastTitle:       getEnv("PODCAST_TITLE", "My YouTube Podcast"),
		PodcastDescription: getEnv("PODCAST_DESCRIPTION", "Converted YouTube videos"),
		PodcastAuthor:      getEnv("PODCAST_AUTHOR", "Podcast Author"),
		PodcastEmail:       getEnv("PODCAST_EMAIL", "author@example.com"),
		PodcastLanguage:    getEnv("PODCAST_LANGUAGE", "en"),
		PodcastImageURL:    os.Getenv("PODCAST_IMAGE_URL"),
		YTDLPPath:          getEnv("YTDLP_PATH", "yt-dlp"),
		AudioFormat:        getEnv("AUDIO_FORMAT", "mp3"),
		AudioQuality:       getEnvInt("AUDIO_QUALITY", 192),
	}

	// Validate required fields based on storage type
	if cfg.StorageType == "gcs" {
		if cfg.GCSBucketName == "" {
			return nil, fmt.Errorf("GCS_BUCKET_NAME is required when STORAGE_TYPE=gcs")
		}
		if cfg.GCSProjectID == "" {
			return nil, fmt.Errorf("GCS_PROJECT_ID is required when STORAGE_TYPE=gcs")
		}
	}

	return cfg, nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}
