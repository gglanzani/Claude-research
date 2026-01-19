package job

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/gglanzani/podcast/internal/chapters"
	"github.com/gglanzani/podcast/internal/config"
	"github.com/gglanzani/podcast/internal/downloader"
	"github.com/gglanzani/podcast/internal/rss"
	"github.com/gglanzani/podcast/internal/storage"
	"github.com/google/uuid"
)

// JobStatus represents the status of a job
type JobStatus string

const (
	StatusQueued     JobStatus = "queued"
	StatusProcessing JobStatus = "processing"
	StatusCompleted  JobStatus = "completed"
	StatusFailed     JobStatus = "failed"
)

// Job represents a download job
type Job struct {
	ID          string     `json:"id"`
	YouTubeURL  string     `json:"youtube_url"`
	Title       string     `json:"title,omitempty"`
	Description string     `json:"description,omitempty"`
	Author      string     `json:"author,omitempty"`
	Status      JobStatus  `json:"status"`
	Error       string     `json:"error,omitempty"`
	EpisodeID   string     `json:"episode_id,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
}

// Processor processes download jobs
type Processor struct {
	cfg         *config.Config
	storage     storage.Storage
	feedManager *rss.FeedManager
	downloader  *downloader.Downloader
	jobs        map[string]*Job
	queue       chan *Job
	mu          sync.RWMutex
	stopCh      chan struct{}
	wg          sync.WaitGroup
}

// NewProcessor creates a new job processor
func NewProcessor(cfg *config.Config, store storage.Storage, feedManager *rss.FeedManager) *Processor {
	return &Processor{
		cfg:         cfg,
		storage:     store,
		feedManager: feedManager,
		jobs:        make(map[string]*Job),
		queue:       make(chan *Job, 100),
		stopCh:      make(chan struct{}),
	}
}

// Start starts the job processor
func (p *Processor) Start(ctx context.Context) {
	log.Printf("Starting job processor...")
	// Initialize downloader
	dl, err := downloader.New(p.cfg)
	if err != nil {
		log.Printf("Warning: downloader initialization failed: %v", err)
		log.Println("Jobs will fail until yt-dlp is available")
	} else {
		log.Printf("Downloader initialized successfully")
	}
	p.downloader = dl

	p.wg.Add(1)
	go p.worker(ctx)
	log.Printf("Job processor worker started")
}

// Stop stops the job processor
func (p *Processor) Stop() {
	close(p.stopCh)
	p.wg.Wait()
}

// Submit submits a new job
func (p *Processor) Submit(youtubeURL, title, description, author string) (*Job, error) {
	// Validate URL
	if _, err := downloader.ExtractVideoID(youtubeURL); err != nil {
		return nil, fmt.Errorf("invalid YouTube URL: %w", err)
	}

	job := &Job{
		ID:          uuid.New().String(),
		YouTubeURL:  youtubeURL,
		Title:       title,
		Description: description,
		Author:      author,
		Status:      StatusQueued,
		CreatedAt:   time.Now(),
	}

	p.mu.Lock()
	p.jobs[job.ID] = job
	p.mu.Unlock()

	log.Printf("Submitting job %s to queue", job.ID)
	select {
	case p.queue <- job:
		log.Printf("Job %s queued successfully", job.ID)
		return job, nil
	default:
		log.Printf("Job queue is full!")
		return nil, fmt.Errorf("job queue is full")
	}
}

// GetJob returns a job by ID
func (p *Processor) GetJob(id string) (*Job, bool) {
	p.mu.RLock()
	defer p.mu.RUnlock()
	job, ok := p.jobs[id]
	if !ok {
		return nil, false
	}
	// Return a copy
	jobCopy := *job
	return &jobCopy, true
}

// worker processes jobs from the queue
func (p *Processor) worker(ctx context.Context) {
	defer p.wg.Done()
	log.Printf("Worker started and waiting for jobs...")

	for {
		select {
		case <-p.stopCh:
			log.Printf("Worker received stop signal")
			return
		case <-ctx.Done():
			log.Printf("Worker context cancelled")
			return
		case job := <-p.queue:
			log.Printf("Worker picked up job %s from queue", job.ID)
			p.processJob(ctx, job)
		}
	}
}

// processJob processes a single job
func (p *Processor) processJob(ctx context.Context, job *Job) {
	p.updateStatus(job, StatusProcessing, "")

	if p.downloader == nil {
		p.updateStatus(job, StatusFailed, "downloader not initialized - is yt-dlp installed?")
		return
	}

	log.Printf("Processing job %s: %s", job.ID, job.YouTubeURL)

	// Download audio
	audioPath, videoInfo, err := p.downloader.DownloadAudio(ctx, job.YouTubeURL)
	if err != nil {
		p.updateStatus(job, StatusFailed, fmt.Sprintf("download failed: %v", err))
		return
	}
	defer p.downloader.Cleanup(videoInfo.ID)

	// Get file info
	fileInfo, err := os.Stat(audioPath)
	if err != nil {
		p.updateStatus(job, StatusFailed, fmt.Sprintf("failed to stat audio file: %v", err))
		return
	}

	// Upload audio file
	audioFile, err := os.Open(audioPath)
	if err != nil {
		p.updateStatus(job, StatusFailed, fmt.Sprintf("failed to open audio file: %v", err))
		return
	}
	defer audioFile.Close()

	episodeID := uuid.New().String()
	audioFilename := fmt.Sprintf("audio/%s.%s", episodeID, p.cfg.AudioFormat)
	audioURL, err := p.storage.Upload(ctx, audioFilename, audioFile, "audio/mpeg")
	if err != nil {
		p.updateStatus(job, StatusFailed, fmt.Sprintf("failed to upload audio: %v", err))
		return
	}

	// Extract and upload chapters
	var chaptersURL string
	extractedChapters := chapters.ExtractChapters(videoInfo)
	if len(extractedChapters) > 0 {
		chaptersJSON, err := chapters.GenerateChaptersJSON(extractedChapters)
		if err == nil {
			chaptersFilename := fmt.Sprintf("chapters/%s.json", episodeID)
			chaptersURL, err = p.storage.Upload(ctx, chaptersFilename, bytes.NewReader(chaptersJSON), "application/json")
			if err != nil {
				log.Printf("Warning: failed to upload chapters: %v", err)
			}
		}
	}

	// Parse publish date
	publishedAt := time.Now()
	if videoInfo.UploadDate != "" {
		if parsed, err := downloader.ParseUploadDate(videoInfo.UploadDate); err == nil {
			publishedAt = parsed
		}
	}

	// Use provided metadata or fall back to video info
	title := job.Title
	if title == "" {
		title = videoInfo.Title
	}
	description := job.Description
	if description == "" {
		description = videoInfo.Description
	}
	author := job.Author
	if author == "" {
		author = videoInfo.Uploader
	}
	if author == "" {
		author = p.cfg.PodcastAuthor
	}

	// Create episode
	episode := rss.Episode{
		ID:          episodeID,
		YouTubeURL:  job.YouTubeURL,
		YouTubeID:   videoInfo.ID,
		Title:       title,
		Description: description,
		Author:      author,
		Duration:    videoInfo.Duration,
		FileSize:    fileInfo.Size(),
		AudioURL:    audioURL,
		ChaptersURL: chaptersURL,
		Chapters:    extractedChapters,
		PublishedAt: publishedAt,
		CreatedAt:   time.Now(),
	}

	// Add to feed
	if err := p.feedManager.AddEpisode(ctx, episode); err != nil {
		p.updateStatus(job, StatusFailed, fmt.Sprintf("failed to add episode: %v", err))
		return
	}

	job.EpisodeID = episodeID
	p.updateStatus(job, StatusCompleted, "")
	log.Printf("Job %s completed: episode %s", job.ID, episodeID)
}

// updateStatus updates a job's status
func (p *Processor) updateStatus(job *Job, status JobStatus, errorMsg string) {
	p.mu.Lock()
	defer p.mu.Unlock()

	job.Status = status
	job.Error = errorMsg
	if status == StatusCompleted || status == StatusFailed {
		now := time.Now()
		job.CompletedAt = &now
	}
}
