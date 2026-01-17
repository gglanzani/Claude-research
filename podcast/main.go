package main

import (
	"context"
	"embed"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gglanzani/podcast/internal/config"
	"github.com/gglanzani/podcast/internal/handler"
	"github.com/gglanzani/podcast/internal/job"
	"github.com/gglanzani/podcast/internal/rss"
	"github.com/gglanzani/podcast/internal/storage"
)

//go:embed web/templates/* web/static/*
var webFS embed.FS

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize storage
	store, err := storage.New(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize storage: %v", err)
	}

	// Initialize RSS feed manager
	feedManager := rss.NewFeedManager(cfg, store)

	// Load existing episodes
	ctx := context.Background()
	if err := feedManager.Load(ctx); err != nil {
		log.Printf("Warning: could not load existing feed: %v", err)
	}

	// Initialize job processor
	processor := job.NewProcessor(cfg, store, feedManager)
	go processor.Start(ctx)

	// Initialize HTTP handlers
	h := handler.New(cfg, store, feedManager, processor, webFS)

	// Set up routes
	mux := http.NewServeMux()
	h.RegisterRoutes(mux)

	// Create server
	server := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Starting server on http://localhost:%s", cfg.Port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	// Graceful shutdown with timeout
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	processor.Stop()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server stopped")
}
