package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	log.SetFlags(log.LstdFlags | log.Lshortfile)

	var (
		token      string
		outputDir  string
		stateFile  string
		mode       string
		pollEvery  time.Duration
		daemon     bool
		oneShot    bool
		maxPages   int
	)

	flag.StringVar(&token, "token", os.Getenv("LINKEDIN_ACCESS_TOKEN"), "LinkedIn OAuth access token (or set LINKEDIN_ACCESS_TOKEN)")
	flag.StringVar(&outputDir, "output", ".", "Directory to write post markdown files")
	flag.StringVar(&stateFile, "state", "linkedin-fetcher-state.json", "Path to state file for tracking last poll time")
	flag.StringVar(&mode, "mode", "both", "Mode: snapshot, changelog, or both")
	flag.DurationVar(&pollEvery, "poll", 1*time.Hour, "Poll interval for changelog in daemon mode")
	flag.BoolVar(&daemon, "daemon", false, "Run continuously, polling for new changelog events")
	flag.BoolVar(&oneShot, "one-shot", false, "Run once and exit (default if not daemon)")
	flag.IntVar(&maxPages, "max-pages", 100, "Maximum pages to fetch for snapshot pagination")

	flag.Parse()

	if token == "" {
		log.Fatal("Access token required: use -token flag or set LINKEDIN_ACCESS_TOKEN environment variable")
	}

	if err := os.MkdirAll(outputDir, 0755); err != nil {
		log.Fatalf("Failed to create output directory: %v", err)
	}

	client := NewLinkedInClient(token)
	state := LoadState(stateFile)

	switch mode {
	case "snapshot":
		runSnapshot(client, state, stateFile, outputDir, maxPages)
	case "changelog":
		if daemon {
			runDaemon(client, state, stateFile, outputDir, pollEvery)
		} else {
			runChangelog(client, state, stateFile, outputDir)
		}
	case "both":
		runSnapshot(client, state, stateFile, outputDir, maxPages)
		if daemon {
			runDaemon(client, state, stateFile, outputDir, pollEvery)
		} else {
			runChangelog(client, state, stateFile, outputDir)
		}
	default:
		log.Fatalf("Unknown mode: %s (use snapshot, changelog, or both)", mode)
	}
}

func runSnapshot(client *LinkedInClient, state *State, stateFile, outputDir string, maxPages int) {
	log.Println("=== Fetching Snapshot Data ===")

	// Fetch posts/shares
	domains := []string{"MEMBER_SHARE_INFO", "ARTICLES", "ALL_COMMENTS", "ALL_LIKES", "INSTANT_REPOSTS"}

	for _, domain := range domains {
		log.Printf("Fetching snapshot domain: %s", domain)
		allData, err := client.FetchSnapshotDomain(domain, maxPages)
		if err != nil {
			log.Printf("Warning: failed to fetch domain %s: %v", domain, err)
			continue
		}

		outPath := filepath.Join(outputDir, fmt.Sprintf("snapshot-%s.json", strings.ToLower(domain)))
		if err := writeJSON(outPath, allData); err != nil {
			log.Printf("Warning: failed to write %s: %v", outPath, err)
			continue
		}
		log.Printf("  Wrote %d records to %s", len(allData), outPath)

		// For MEMBER_SHARE_INFO, also generate individual markdown files
		if domain == "MEMBER_SHARE_INFO" {
			count := generatePostMarkdownFiles(allData, outputDir, state)
			log.Printf("  Generated %d new markdown files for posts", count)
		}
	}

	state.LastSnapshotRun = time.Now().UnixMilli()
	SaveState(stateFile, state)
	log.Println("=== Snapshot complete ===")
}

func runChangelog(client *LinkedInClient, state *State, stateFile, outputDir string) {
	log.Println("=== Fetching Changelog Events ===")

	startTime := state.LastChangelogProcessedAt
	if startTime == 0 {
		// Default: go back 28 days (maximum window)
		startTime = time.Now().Add(-28 * 24 * time.Hour).UnixMilli()
		log.Printf("No previous state found, fetching from 28 days ago")
	}

	events, latestProcessedAt, err := client.FetchChangelogEvents(startTime)
	if err != nil {
		log.Printf("Error fetching changelog: %v", err)
		return
	}

	log.Printf("Fetched %d changelog events", len(events))

	// Filter for post-related events
	postEvents := filterPostEvents(events)
	log.Printf("  %d are post-related events", len(postEvents))

	if len(postEvents) > 0 {
		// Save all raw events
		eventsPath := filepath.Join(outputDir, fmt.Sprintf("changelog-%d.json", time.Now().Unix()))
		if err := writeJSON(eventsPath, postEvents); err != nil {
			log.Printf("Warning: failed to write changelog events: %v", err)
		}

		// Generate markdown for new post CREATE events
		count := 0
		for _, event := range postEvents {
			if event.Method == "CREATE" && isPostResource(event.ResourceName) {
				if md := changelogEventToMarkdown(event); md != "" {
					filename := generateFilename(event)
					outPath := filepath.Join(outputDir, filename)
					if _, err := os.Stat(outPath); os.IsNotExist(err) {
						if err := os.WriteFile(outPath, []byte(md), 0644); err != nil {
							log.Printf("Warning: failed to write %s: %v", outPath, err)
						} else {
							count++
						}
					}
				}
			}
		}
		log.Printf("  Generated %d new markdown files from changelog", count)
	}

	// Update state with latest processedAt timestamp
	if latestProcessedAt > 0 {
		state.LastChangelogProcessedAt = latestProcessedAt
	}
	state.LastChangelogRun = time.Now().UnixMilli()
	SaveState(stateFile, state)
	log.Println("=== Changelog complete ===")
}

func runDaemon(client *LinkedInClient, state *State, stateFile, outputDir string, interval time.Duration) {
	log.Printf("Starting daemon mode, polling every %s", interval)
	for {
		runChangelog(client, state, stateFile, outputDir)
		log.Printf("Sleeping for %s...", interval)
		time.Sleep(interval)
	}
}

// filterPostEvents returns only events related to posts, shares, articles
func filterPostEvents(events []ChangelogEvent) []ChangelogEvent {
	var result []ChangelogEvent
	for _, e := range events {
		if isPostResource(e.ResourceName) {
			result = append(result, e)
		}
	}
	return result
}

func isPostResource(resourceName string) bool {
	postResources := map[string]bool{
		"shares":         true,
		"ugcPosts":       true,
		"posts":          true,
		"articles":       true,
		"socialActions":  true,
		"comments":       true,
		"instantReposts": true,
	}
	return postResources[resourceName]
}

func writeJSON(path string, data interface{}) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	enc := json.NewEncoder(f)
	enc.SetIndent("", "  ")
	return enc.Encode(data)
}
