# YouTube to Podcast RSS Generator - Implementation Plan

## Overview

A web application that converts YouTube videos to podcast episodes by extracting audio and generating a valid podcast RSS feed. Files are uploaded to cloud storage (initially GCS) and the RSS feed is automatically updated.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Web Frontend                             │
│                  (HTML form for URL + metadata)                  │
└─────────────────────────────────────┬───────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Go Backend                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ HTTP Server │  │  Job Queue  │  │     RSS Generator       │  │
│  │  (net/http) │  │  (in-memory)│  │  (gorilla/feeds or      │  │
│  └─────────────┘  └─────────────┘  │   custom XML)           │  │
│                                     └─────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    Storage Interface                         │ │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐               │ │
│  │  │    GCS    │  │    S3     │  │   Local   │  (future)     │ │
│  │  └───────────┘  └───────────┘  └───────────┘               │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    External Dependencies                         │
│  ┌─────────────┐  ┌─────────────────────────────────────────┐   │
│  │   yt-dlp    │  │        Google Cloud Storage             │   │
│  │  (CLI tool) │  │  - Audio files (.mp3)                   │   │
│  └─────────────┘  │  - RSS feed (feed.xml)                  │   │
│                   │  - Metadata store (episodes.json)       │   │
│                   └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Technology Stack

- **Language**: Go (consistent with existing codebase)
- **Web Framework**: Standard library `net/http` with minimal dependencies
- **Audio Extraction**: `yt-dlp` (called via `os/exec`)
- **RSS Generation**: Custom XML or `gorilla/feeds` library
- **Storage**: Modular interface, GCS implementation first
- **Frontend**: Simple HTML/CSS (embedded in Go binary)

## Project Structure

```
podcast/
├── PLAN.md
├── go.mod
├── go.sum
├── main.go                 # Entry point, HTTP server setup
├── cmd/
│   └── server/
│       └── main.go         # Alternative entry point if needed
├── internal/
│   ├── config/
│   │   └── config.go       # Environment variable loading
│   ├── downloader/
│   │   └── ytdlp.go        # yt-dlp wrapper
│   ├── storage/
│   │   ├── storage.go      # Storage interface
│   │   ├── gcs.go          # GCS implementation
│   │   └── local.go        # Local filesystem (for testing)
│   ├── rss/
│   │   ├── feed.go         # RSS feed generation
│   │   └── episode.go      # Episode metadata
│   ├── handler/
│   │   └── handlers.go     # HTTP handlers
│   └── job/
│       └── processor.go    # Background job processing
├── web/
│   ├── templates/
│   │   └── index.html      # Main form page
│   └── static/
│       └── style.css       # Minimal styling
└── README.md
```

## Data Models

### Episode Metadata

```go
type Episode struct {
    ID          string    `json:"id"`           // UUID
    YouTubeURL  string    `json:"youtube_url"`
    YouTubeID   string    `json:"youtube_id"`
    Title       string    `json:"title"`
    Description string    `json:"description"`
    Author      string    `json:"author"`
    Duration    int       `json:"duration"`      // seconds
    FileSize    int64     `json:"file_size"`     // bytes
    AudioURL    string    `json:"audio_url"`     // public GCS URL
    PublishedAt time.Time `json:"published_at"`
    CreatedAt   time.Time `json:"created_at"`
}
```

### Podcast Feed Metadata

```go
type PodcastFeed struct {
    Title       string    `json:"title"`
    Description string    `json:"description"`
    Author      string    `json:"author"`
    Email       string    `json:"email"`
    ImageURL    string    `json:"image_url"`
    Language    string    `json:"language"`
    Episodes    []Episode `json:"episodes"`
}
```

## Environment Variables

```bash
# Required
GCS_BUCKET_NAME=my-podcast-bucket
GCS_PROJECT_ID=my-gcp-project
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json

# Optional with defaults
PORT=8080
PODCAST_TITLE="My YouTube Podcast"
PODCAST_DESCRIPTION="Converted YouTube videos"
PODCAST_AUTHOR="Podcast Author"
PODCAST_EMAIL="author@example.com"
PODCAST_LANGUAGE="en"

# Storage type (for future extensibility)
STORAGE_TYPE=gcs  # gcs, s3, local

# yt-dlp settings
YTDLP_PATH=yt-dlp  # path to yt-dlp binary
AUDIO_FORMAT=mp3
AUDIO_QUALITY=192  # kbps
```

## API Endpoints

### `GET /`
- Serves the HTML form for submitting YouTube URLs

### `POST /api/episodes`
- **Request Body**:
  ```json
  {
    "youtube_url": "https://www.youtube.com/watch?v=...",
    "title": "Optional custom title",
    "description": "Optional custom description",
    "author": "Optional author override"
  }
  ```
- **Response**: Job ID for tracking
  ```json
  {
    "job_id": "uuid",
    "status": "queued"
  }
  ```

### `GET /api/episodes`
- Lists all episodes in the feed

### `GET /api/jobs/:id`
- Returns job status (queued, processing, completed, failed)

### `GET /feed.xml`
- Returns the podcast RSS feed

## Storage Interface

```go
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
```

## Implementation Steps

### Phase 1: Project Setup
1. Initialize Go module
2. Create directory structure
3. Set up configuration loading from environment variables
4. Create basic HTTP server with health check endpoint

### Phase 2: Storage Layer
1. Define storage interface
2. Implement GCS storage backend
3. Implement local filesystem storage (for development/testing)
4. Add storage factory based on `STORAGE_TYPE` env var

### Phase 3: YouTube Downloader
1. Create yt-dlp wrapper
2. Implement audio extraction with configurable format/quality
3. Extract video metadata (title, description, duration, thumbnail)
4. Handle errors and edge cases (age-restricted, unavailable, etc.)

### Phase 4: RSS Feed Generation
1. Create episode data model
2. Implement RSS 2.0 feed generation with iTunes podcast extensions
3. Store episode metadata in JSON file on storage
4. Load and update feed atomically

### Phase 5: HTTP Handlers & Web UI
1. Create form submission handler
2. Implement job status endpoint
3. Create simple HTML form with JavaScript for status polling
4. Add episode listing page

### Phase 6: Job Processing
1. Implement background job processor
2. Add job queue (in-memory for single instance)
3. Process: download → extract audio → upload → update RSS

### Phase 7: Testing & Polish
1. Add unit tests for core components
2. Add integration tests
3. Create Dockerfile for deployment
4. Write README with setup instructions

## RSS Feed Format

The generated RSS feed will follow the RSS 2.0 specification with iTunes podcast extensions:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
     xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>My YouTube Podcast</title>
    <link>https://storage.googleapis.com/bucket/feed.xml</link>
    <description>Converted YouTube videos</description>
    <language>en</language>
    <itunes:author>Author Name</itunes:author>
    <itunes:email>email@example.com</itunes:email>
    <itunes:image href="https://..."/>
    <atom:link href="https://storage.googleapis.com/bucket/feed.xml" rel="self" type="application/rss+xml"/>

    <item>
      <title>Episode Title</title>
      <description>Episode description</description>
      <enclosure url="https://storage.googleapis.com/bucket/audio/episode.mp3"
                 length="12345678"
                 type="audio/mpeg"/>
      <guid isPermaLink="false">episode-uuid</guid>
      <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
      <itunes:duration>3600</itunes:duration>
      <itunes:author>Author</itunes:author>
    </item>
  </channel>
</rss>
```

## Error Handling

| Error Type | Handling |
|------------|----------|
| Invalid YouTube URL | Return 400 with message |
| Video unavailable | Mark job as failed, notify user |
| yt-dlp not installed | Fail startup with clear error |
| GCS auth failure | Fail startup with clear error |
| Upload failure | Retry 3 times, then mark job failed |
| RSS generation failure | Log error, keep previous RSS |

## Future Enhancements (Out of Scope)

- User authentication
- Multiple podcast feeds
- Scheduled/automatic YouTube channel sync
- S3 storage backend
- Web UI for managing episodes
- Webhook notifications
- Playlist support
- Video quality selection for video podcasts

## Dependencies

```
github.com/google/uuid          # UUID generation
cloud.google.com/go/storage     # GCS client
```

## Security Considerations

1. **Input Validation**: Validate YouTube URLs before processing
2. **No Shell Injection**: Use exec.Command with args, not shell string
3. **Resource Limits**: Limit file sizes, concurrent downloads
4. **GCS Permissions**: Use minimal required IAM permissions
5. **No User Data**: Single user, no auth = no user data to protect

## Quick Start (After Implementation)

```bash
# Set required environment variables
export GCS_BUCKET_NAME=my-podcast-bucket
export GCS_PROJECT_ID=my-gcp-project
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/creds.json

# Ensure yt-dlp is installed
yt-dlp --version

# Run the server
cd podcast
go run main.go

# Access at http://localhost:8080
```
