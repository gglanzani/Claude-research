package chapters

import (
	"encoding/json"

	"github.com/gglanzani/podcast/internal/downloader"
)

// Chapter represents a podcast chapter in Podcasting 2.0 format
type Chapter struct {
	StartTime float64 `json:"startTime"`
	Title     string  `json:"title"`
	URL       string  `json:"url,omitempty"`
	Image     string  `json:"img,omitempty"`
}

// ChaptersFile represents the Podcasting 2.0 chapters JSON format
type ChaptersFile struct {
	Version  string    `json:"version"`
	Chapters []Chapter `json:"chapters"`
}

// ExtractChapters extracts chapters from video info, falling back to description parsing
func ExtractChapters(info *downloader.VideoInfo) []Chapter {
	// First, try to use chapters from yt-dlp
	if len(info.Chapters) > 0 {
		return convertYTDLPChapters(info.Chapters)
	}

	// Fallback: parse chapters from description
	if info.Description != "" {
		parsed := ParseChaptersFromDescription(info.Description)
		if len(parsed) > 0 {
			return parsed
		}
	}

	return nil
}

// convertYTDLPChapters converts yt-dlp chapters to Podcasting 2.0 format
func convertYTDLPChapters(chapters []downloader.Chapter) []Chapter {
	result := make([]Chapter, len(chapters))
	for i, ch := range chapters {
		result[i] = Chapter{
			StartTime: ch.StartTime,
			Title:     ch.Title,
		}
	}
	return result
}

// GenerateChaptersJSON generates a Podcasting 2.0 chapters JSON file
func GenerateChaptersJSON(chapters []Chapter) ([]byte, error) {
	file := ChaptersFile{
		Version:  "1.2.0",
		Chapters: chapters,
	}
	return json.MarshalIndent(file, "", "  ")
}
