package handler

import (
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"io/fs"
	"log"
	"net/http"
	"strings"

	"github.com/gglanzani/podcast/internal/config"
	"github.com/gglanzani/podcast/internal/job"
	"github.com/gglanzani/podcast/internal/rss"
	"github.com/gglanzani/podcast/internal/storage"
)

// Handler handles HTTP requests
type Handler struct {
	cfg         *config.Config
	storage     storage.Storage
	feedManager *rss.FeedManager
	processor   *job.Processor
	templates   *template.Template
	staticFS    fs.FS
}

// Template functions
var templateFuncs = template.FuncMap{
	"formatDuration": func(seconds int) string {
		h := seconds / 3600
		m := (seconds % 3600) / 60
		s := seconds % 60
		if h > 0 {
			return fmt.Sprintf("%d:%02d:%02d", h, m, s)
		}
		return fmt.Sprintf("%d:%02d", m, s)
	},
	"truncate": func(s string, maxLen int) string {
		if len(s) <= maxLen {
			return s
		}
		return s[:maxLen] + "..."
	},
}

// New creates a new handler
func New(cfg *config.Config, store storage.Storage, feedManager *rss.FeedManager, processor *job.Processor, webFS embed.FS) *Handler {
	// Parse templates with custom functions
	tmpl, err := template.New("").Funcs(templateFuncs).ParseFS(webFS, "web/templates/*.html")
	if err != nil {
		log.Printf("Warning: failed to parse templates: %v", err)
	}

	// Get static files
	staticFS, err := fs.Sub(webFS, "web/static")
	if err != nil {
		log.Printf("Warning: failed to get static files: %v", err)
	}

	return &Handler{
		cfg:         cfg,
		storage:     store,
		feedManager: feedManager,
		processor:   processor,
		templates:   tmpl,
		staticFS:    staticFS,
	}
}

// RegisterRoutes registers all HTTP routes
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	// Pages
	mux.HandleFunc("GET /", h.handleIndex)
	mux.HandleFunc("GET /bookmarklet", h.handleBookmarklet)
	mux.HandleFunc("GET /episodes", h.handleEpisodesPage)

	// API
	mux.HandleFunc("POST /api/episodes", h.handleCreateEpisode)
	mux.HandleFunc("GET /api/episodes", h.handleListEpisodes)
	mux.HandleFunc("GET /api/jobs/{id}", h.handleGetJob)
	mux.HandleFunc("GET /api/bookmarklet.js", h.handleBookmarkletJS)

	// Feed
	mux.HandleFunc("GET /feed.xml", h.handleFeed)

	// Static files
	mux.Handle("GET /static/", http.StripPrefix("/static/", http.FileServer(http.FS(h.staticFS))))

	// Serve files from local storage if using local storage
	if localStore, ok := h.storage.(*storage.Local); ok {
		mux.Handle("GET /files/", http.StripPrefix("/files/", http.FileServer(http.Dir(localStore.GetBasePath()))))
	}

	// Health check
	mux.HandleFunc("GET /health", h.handleHealth)
}

// handleIndex serves the main page
func (h *Handler) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	data := struct {
		URL         string
		ExternalURL string
	}{
		URL:         r.URL.Query().Get("url"),
		ExternalURL: h.cfg.ExternalURL,
	}

	if h.templates == nil {
		http.Error(w, "Templates not loaded", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := h.templates.ExecuteTemplate(w, "index.html", data); err != nil {
		log.Printf("Template error: %v", err)
		http.Error(w, "Template error", http.StatusInternalServerError)
	}
}

// handleBookmarklet serves the bookmarklet installation page
func (h *Handler) handleBookmarklet(w http.ResponseWriter, r *http.Request) {
	data := struct {
		ExternalURL string
		Bookmarklet template.JS
	}{
		ExternalURL: h.cfg.ExternalURL,
		Bookmarklet: template.JS(h.generateBookmarklet()),
	}

	if h.templates == nil {
		http.Error(w, "Templates not loaded", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := h.templates.ExecuteTemplate(w, "bookmarklet.html", data); err != nil {
		log.Printf("Template error: %v", err)
		http.Error(w, "Template error", http.StatusInternalServerError)
	}
}

// handleEpisodesPage serves the episodes list page
func (h *Handler) handleEpisodesPage(w http.ResponseWriter, r *http.Request) {
	data := struct {
		Episodes    []rss.Episode
		ExternalURL string
		FeedURL     string
	}{
		Episodes:    h.feedManager.GetEpisodes(),
		ExternalURL: h.cfg.ExternalURL,
		FeedURL:     h.storage.GetPublicURL("feed.xml"),
	}

	if h.templates == nil {
		http.Error(w, "Templates not loaded", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := h.templates.ExecuteTemplate(w, "episodes.html", data); err != nil {
		log.Printf("Template error: %v", err)
		http.Error(w, "Template error", http.StatusInternalServerError)
	}
}

// CreateEpisodeRequest is the request body for creating an episode
type CreateEpisodeRequest struct {
	YouTubeURL  string `json:"youtube_url"`
	Title       string `json:"title,omitempty"`
	Description string `json:"description,omitempty"`
	Author      string `json:"author,omitempty"`
}

// handleCreateEpisode handles episode creation
func (h *Handler) handleCreateEpisode(w http.ResponseWriter, r *http.Request) {
	var req CreateEpisodeRequest

	contentType := r.Header.Get("Content-Type")
	if strings.HasPrefix(contentType, "application/json") {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			h.jsonError(w, "Invalid JSON", http.StatusBadRequest)
			return
		}
	} else {
		// Form submission
		if err := r.ParseForm(); err != nil {
			h.jsonError(w, "Invalid form data", http.StatusBadRequest)
			return
		}
		req.YouTubeURL = r.FormValue("youtube_url")
		req.Title = r.FormValue("title")
		req.Description = r.FormValue("description")
		req.Author = r.FormValue("author")
	}

	if req.YouTubeURL == "" {
		h.jsonError(w, "youtube_url is required", http.StatusBadRequest)
		return
	}

	job, err := h.processor.Submit(req.YouTubeURL, req.Title, req.Description, req.Author)
	if err != nil {
		h.jsonError(w, err.Error(), http.StatusBadRequest)
		return
	}

	h.jsonResponse(w, http.StatusAccepted, map[string]interface{}{
		"job_id": job.ID,
		"status": job.Status,
	})
}

// handleListEpisodes returns all episodes
func (h *Handler) handleListEpisodes(w http.ResponseWriter, r *http.Request) {
	episodes := h.feedManager.GetEpisodes()
	h.jsonResponse(w, http.StatusOK, map[string]interface{}{
		"episodes": episodes,
	})
}

// handleGetJob returns job status
func (h *Handler) handleGetJob(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		h.jsonError(w, "job ID required", http.StatusBadRequest)
		return
	}

	job, ok := h.processor.GetJob(id)
	if !ok {
		h.jsonError(w, "job not found", http.StatusNotFound)
		return
	}

	h.jsonResponse(w, http.StatusOK, job)
}

// handleBookmarkletJS returns the bookmarklet JavaScript
func (h *Handler) handleBookmarkletJS(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/javascript")
	fmt.Fprint(w, h.generateBookmarklet())
}

// handleFeed serves the RSS feed
func (h *Handler) handleFeed(w http.ResponseWriter, r *http.Request) {
	xmlData, err := h.feedManager.GenerateXML()
	if err != nil {
		http.Error(w, "Failed to generate feed", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/rss+xml; charset=utf-8")
	w.Write(xmlData)
}

// handleHealth returns health status
func (h *Handler) handleHealth(w http.ResponseWriter, r *http.Request) {
	h.jsonResponse(w, http.StatusOK, map[string]string{
		"status": "ok",
	})
}

// generateBookmarklet generates the bookmarklet JavaScript
func (h *Handler) generateBookmarklet() string {
	return fmt.Sprintf(`javascript:(function(){var url=location.href;if(url.match(/youtube\.com\/watch|youtu\.be\//)){window.open('%s/?url='+encodeURIComponent(url),'_blank');}else{alert('Not a YouTube video page');}})();`, h.cfg.ExternalURL)
}

// jsonResponse sends a JSON response
func (h *Handler) jsonResponse(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// jsonError sends a JSON error response
func (h *Handler) jsonError(w http.ResponseWriter, message string, status int) {
	h.jsonResponse(w, status, map[string]string{
		"error": message,
	})
}
