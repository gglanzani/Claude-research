package downloader

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/gglanzani/podcast/internal/config"
)

// VideoInfo contains metadata extracted from YouTube
type VideoInfo struct {
	ID          string    `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Duration    int       `json:"duration"`
	Uploader    string    `json:"uploader"`
	UploadDate  string    `json:"upload_date"`
	Thumbnail   string    `json:"thumbnail"`
	Chapters    []Chapter `json:"chapters"`
}

// Chapter represents a video chapter
type Chapter struct {
	StartTime float64 `json:"start_time"`
	EndTime   float64 `json:"end_time"`
	Title     string  `json:"title"`
}

// YTDLPInfo is the raw structure from yt-dlp JSON output
type YTDLPInfo struct {
	ID          string         `json:"id"`
	Title       string         `json:"title"`
	Description string         `json:"description"`
	Duration    float64        `json:"duration"`
	Uploader    string         `json:"uploader"`
	UploadDate  string         `json:"upload_date"`
	Thumbnail   string         `json:"thumbnail"`
	Chapters    []YTDLPChapter `json:"chapters"`
}

// YTDLPChapter is the chapter structure from yt-dlp
type YTDLPChapter struct {
	StartTime float64 `json:"start_time"`
	EndTime   float64 `json:"end_time"`
	Title     string  `json:"title"`
}

// Downloader wraps yt-dlp for downloading YouTube videos
type Downloader struct {
	ytdlpPath    string
	audioFormat  string
	audioQuality int
	tempDir      string
}

// New creates a new Downloader
func New(cfg *config.Config) (*Downloader, error) {
	// Verify yt-dlp is available
	if _, err := exec.LookPath(cfg.YTDLPPath); err != nil {
		return nil, fmt.Errorf("yt-dlp not found at %s: %w", cfg.YTDLPPath, err)
	}

	tempDir := filepath.Join(os.TempDir(), "podcast-ytdlp")
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create temp directory: %w", err)
	}

	return &Downloader{
		ytdlpPath:    cfg.YTDLPPath,
		audioFormat:  cfg.AudioFormat,
		audioQuality: cfg.AudioQuality,
		tempDir:      tempDir,
	}, nil
}

// ExtractVideoID extracts the video ID from a YouTube URL
func ExtractVideoID(url string) (string, error) {
	patterns := []string{
		`(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/|youtube\.com\/v\/)([a-zA-Z0-9_-]{11})`,
	}

	for _, pattern := range patterns {
		re := regexp.MustCompile(pattern)
		matches := re.FindStringSubmatch(url)
		if len(matches) > 1 {
			return matches[1], nil
		}
	}

	return "", fmt.Errorf("could not extract video ID from URL: %s", url)
}

// GetVideoInfo fetches video metadata without downloading
func (d *Downloader) GetVideoInfo(ctx context.Context, url string) (*VideoInfo, error) {
	args := []string{
		"--dump-json",
		"--no-download",
		url,
	}

	cmd := exec.CommandContext(ctx, d.ytdlpPath, args...)
	output, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("yt-dlp failed: %s", string(exitErr.Stderr))
		}
		return nil, fmt.Errorf("yt-dlp failed: %w", err)
	}

	var info YTDLPInfo
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse yt-dlp output: %w", err)
	}

	// Convert chapters
	chapters := make([]Chapter, len(info.Chapters))
	for i, ch := range info.Chapters {
		chapters[i] = Chapter{
			StartTime: ch.StartTime,
			EndTime:   ch.EndTime,
			Title:     ch.Title,
		}
	}

	return &VideoInfo{
		ID:          info.ID,
		Title:       info.Title,
		Description: info.Description,
		Duration:    int(info.Duration),
		Uploader:    info.Uploader,
		UploadDate:  info.UploadDate,
		Thumbnail:   info.Thumbnail,
		Chapters:    chapters,
	}, nil
}

// DownloadAudio downloads and extracts audio from a YouTube video
// Returns the path to the downloaded audio file
func (d *Downloader) DownloadAudio(ctx context.Context, url string) (string, *VideoInfo, error) {
	videoID, err := ExtractVideoID(url)
	if err != nil {
		return "", nil, err
	}

	// Create a unique temp directory for this download
	downloadDir := filepath.Join(d.tempDir, videoID)
	if err := os.MkdirAll(downloadDir, 0755); err != nil {
		return "", nil, fmt.Errorf("failed to create download directory: %w", err)
	}

	outputTemplate := filepath.Join(downloadDir, "%(id)s.%(ext)s")
	infoFile := filepath.Join(downloadDir, fmt.Sprintf("%s.info.json", videoID))

	args := []string{
		"--extract-audio",
		"--audio-format", d.audioFormat,
		"--audio-quality", fmt.Sprintf("%dk", d.audioQuality),
		"--write-info-json",
		"--output", outputTemplate,
		"--no-playlist",
		"--no-overwrites",
		url,
	}

	cmd := exec.CommandContext(ctx, d.ytdlpPath, args...)
	cmd.Dir = downloadDir

	log.Printf("Running yt-dlp in directory: %s", downloadDir)
	log.Printf("yt-dlp args: %v", args)

	output, err := cmd.CombinedOutput()
	log.Printf("yt-dlp output: %s", string(output))
	if err != nil {
		return "", nil, fmt.Errorf("yt-dlp download failed: %s, output: %s", err, string(output))
	}

	// List all files in directory for debugging
	entries, _ := os.ReadDir(downloadDir)
	log.Printf("Files in download directory after yt-dlp:")
	for _, entry := range entries {
		log.Printf("  - %s", entry.Name())
	}

	// Find the audio file
	expectedFile := fmt.Sprintf("%s.%s", videoID, d.audioFormat)
	audioFile := filepath.Join(downloadDir, expectedFile)
	log.Printf("Looking for audio file: %s", expectedFile)

	if _, err := os.Stat(audioFile); os.IsNotExist(err) {
		log.Printf("Expected file not found, searching for any .%s file", d.audioFormat)
		// Try to find any audio file in the directory
		for _, entry := range entries {
			if strings.HasSuffix(entry.Name(), "."+d.audioFormat) {
				audioFile = filepath.Join(downloadDir, entry.Name())
				log.Printf("Found audio file: %s", entry.Name())
				break
			}
		}
	}

	if _, err := os.Stat(audioFile); os.IsNotExist(err) {
		// Try finding any common audio format
		audioExtensions := []string{".mp3", ".m4a", ".aac", ".opus", ".webm", ".ogg"}
		for _, entry := range entries {
			for _, ext := range audioExtensions {
				if strings.HasSuffix(entry.Name(), ext) {
					audioFile = filepath.Join(downloadDir, entry.Name())
					log.Printf("Found audio file with different extension: %s", entry.Name())
					break
				}
			}
		}
	}

	if _, err := os.Stat(audioFile); os.IsNotExist(err) {
		return "", nil, fmt.Errorf("audio file not found after download, expected format: %s", d.audioFormat)
	}

	// Parse video info from JSON file
	var info *VideoInfo
	if infoData, err := os.ReadFile(infoFile); err == nil {
		var ytdlpInfo YTDLPInfo
		if err := json.Unmarshal(infoData, &ytdlpInfo); err == nil {
			chapters := make([]Chapter, len(ytdlpInfo.Chapters))
			for i, ch := range ytdlpInfo.Chapters {
				chapters[i] = Chapter{
					StartTime: ch.StartTime,
					EndTime:   ch.EndTime,
					Title:     ch.Title,
				}
			}
			info = &VideoInfo{
				ID:          ytdlpInfo.ID,
				Title:       ytdlpInfo.Title,
				Description: ytdlpInfo.Description,
				Duration:    int(ytdlpInfo.Duration),
				Uploader:    ytdlpInfo.Uploader,
				UploadDate:  ytdlpInfo.UploadDate,
				Thumbnail:   ytdlpInfo.Thumbnail,
				Chapters:    chapters,
			}
		}
	}

	// If we couldn't get info from file, fetch it
	if info == nil {
		info, err = d.GetVideoInfo(ctx, url)
		if err != nil {
			// Create minimal info
			info = &VideoInfo{
				ID:    videoID,
				Title: videoID,
			}
		}
	}

	return audioFile, info, nil
}

// Cleanup removes temporary files for a video
func (d *Downloader) Cleanup(videoID string) error {
	downloadDir := filepath.Join(d.tempDir, videoID)
	return os.RemoveAll(downloadDir)
}

// ParseUploadDate parses the upload date from yt-dlp format (YYYYMMDD)
func ParseUploadDate(dateStr string) (time.Time, error) {
	if len(dateStr) != 8 {
		return time.Time{}, fmt.Errorf("invalid date format: %s", dateStr)
	}
	return time.Parse("20060102", dateStr)
}
