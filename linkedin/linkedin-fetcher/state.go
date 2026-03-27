package main

import (
	"encoding/json"
	"log"
	"os"
)

// State tracks the fetcher's progress across runs.
type State struct {
	// Last processedAt timestamp from changelog events (epoch ms).
	// Used as startTime for the next changelog fetch.
	LastChangelogProcessedAt int64 `json:"lastChangelogProcessedAt"`

	// Timestamps of when each mode was last run (epoch ms).
	LastChangelogRun int64 `json:"lastChangelogRun"`
	LastSnapshotRun  int64 `json:"lastSnapshotRun"`

	// Set of post IDs/URLs we've already written, to avoid duplicates.
	SeenPosts map[string]bool `json:"seenPosts"`
}

func LoadState(path string) *State {
	state := &State{
		SeenPosts: make(map[string]bool),
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("No state file found at %s, starting fresh", path)
			return state
		}
		log.Printf("Warning: failed to read state file %s: %v", path, err)
		return state
	}

	if err := json.Unmarshal(data, state); err != nil {
		log.Printf("Warning: failed to parse state file %s: %v", path, err)
		return state
	}

	if state.SeenPosts == nil {
		state.SeenPosts = make(map[string]bool)
	}

	log.Printf("Loaded state: lastChangelogProcessedAt=%d, seenPosts=%d", state.LastChangelogProcessedAt, len(state.SeenPosts))
	return state
}

func SaveState(path string, state *State) {
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		log.Printf("Warning: failed to marshal state: %v", err)
		return
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		log.Printf("Warning: failed to write state file %s: %v", path, err)
	}
}
