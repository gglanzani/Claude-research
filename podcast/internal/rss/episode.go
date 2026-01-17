package rss

import (
	"time"

	"github.com/gglanzani/podcast/internal/chapters"
)

// Episode represents a podcast episode
type Episode struct {
	ID          string             `json:"id"`
	YouTubeURL  string             `json:"youtube_url"`
	YouTubeID   string             `json:"youtube_id"`
	Title       string             `json:"title"`
	Description string             `json:"description"`
	Author      string             `json:"author"`
	Duration    int                `json:"duration"`
	FileSize    int64              `json:"file_size"`
	AudioURL    string             `json:"audio_url"`
	ChaptersURL string             `json:"chapters_url,omitempty"`
	Chapters    []chapters.Chapter `json:"chapters,omitempty"`
	PublishedAt time.Time          `json:"published_at"`
	CreatedAt   time.Time          `json:"created_at"`
}

// PodcastFeed represents the podcast feed metadata
type PodcastFeed struct {
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Author      string    `json:"author"`
	Email       string    `json:"email"`
	ImageURL    string    `json:"image_url"`
	Language    string    `json:"language"`
	Link        string    `json:"link"`
	Episodes    []Episode `json:"episodes"`
}
