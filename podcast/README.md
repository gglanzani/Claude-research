# YouTube to Podcast RSS Generator

A web application that converts YouTube videos to podcast episodes by extracting audio and generating a valid podcast RSS feed with chapter support.

## Features

- Convert YouTube videos to podcast episodes
- Automatic audio extraction using yt-dlp
- RSS 2.0 feed with iTunes and Podcasting 2.0 extensions
- Chapter support (extracted from YouTube or video description)
- Browser bookmarklet for one-click submission
- Modular storage backend (local filesystem or Google Cloud Storage)
- Simple web interface

## Quick Start

### Using Docker

```bash
docker build -t podcast .
docker run -p 8080:8080 -v podcast-data:/app/data podcast
```

### Local Development

```bash
# Prerequisites
# - Go 1.21+
# - yt-dlp installed and in PATH
# - ffmpeg installed

# Run the server
cd podcast
go run main.go

# Access at http://localhost:8080
```

## Configuration

Set these environment variables:

### Required for GCS Storage

```bash
export STORAGE_TYPE=gcs
export GCS_BUCKET_NAME=my-podcast-bucket
export GCS_PROJECT_ID=my-gcp-project
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

### Optional Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | HTTP server port |
| `EXTERNAL_URL` | `http://localhost:8080` | Public URL for the server |
| `STORAGE_TYPE` | `local` | Storage backend: `local` or `gcs` |
| `LOCAL_STORAGE_PATH` | `./data` | Path for local storage |
| `PODCAST_TITLE` | `My YouTube Podcast` | Podcast feed title |
| `PODCAST_DESCRIPTION` | `Converted YouTube videos` | Podcast description |
| `PODCAST_AUTHOR` | `Podcast Author` | Author name |
| `PODCAST_EMAIL` | `author@example.com` | Author email |
| `PODCAST_LANGUAGE` | `en` | Language code |
| `PODCAST_IMAGE_URL` | (empty) | Podcast artwork URL |
| `AUDIO_FORMAT` | `mp3` | Output audio format |
| `AUDIO_QUALITY` | `192` | Audio bitrate in kbps |
| `YTDLP_PATH` | `yt-dlp` | Path to yt-dlp binary |

## Usage

### Web Interface

1. Navigate to `http://localhost:8080`
2. Paste a YouTube URL
3. Optionally customize title, description, and author
4. Click "Add to Podcast"
5. Wait for processing to complete
6. Subscribe to the RSS feed at `/feed.xml`

### Bookmarklet

1. Visit `/bookmarklet` for installation instructions
2. Drag the bookmarklet to your bookmarks bar
3. Click it on any YouTube video page to quickly add it

### API

```bash
# Submit a video
curl -X POST http://localhost:8080/api/episodes \
  -H "Content-Type: application/json" \
  -d '{"youtube_url": "https://www.youtube.com/watch?v=..."}'

# Check job status
curl http://localhost:8080/api/jobs/{job_id}

# List episodes
curl http://localhost:8080/api/episodes

# Get RSS feed
curl http://localhost:8080/feed.xml
```

## Chapter Support

The application automatically extracts chapters from YouTube videos:

1. **Primary**: Uses yt-dlp to extract chapters from YouTube's metadata
2. **Fallback**: Parses timestamps from video descriptions (e.g., `0:00 Intro`)

Chapters are stored in Podcasting 2.0 format and supported by:
- Pocket Casts
- Overcast
- Castro
- Podcast Addict
- AntennaPod
- Podverse
- Fountain

## Architecture

```
podcast/
├── main.go                    # Entry point
├── internal/
│   ├── config/               # Configuration loading
│   ├── downloader/           # yt-dlp wrapper
│   ├── storage/              # Storage interface (local/GCS)
│   ├── chapters/             # Chapter extraction
│   ├── rss/                  # RSS feed generation
│   ├── handler/              # HTTP handlers
│   └── job/                  # Background job processor
└── web/
    ├── templates/            # HTML templates
    └── static/               # CSS
```

## License

MIT
