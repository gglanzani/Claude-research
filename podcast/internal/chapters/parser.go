package chapters

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// timestampPattern matches timestamps in various formats:
// 0:00, 00:00, 0:00:00, 00:00:00
// Optionally followed by separator and title
var timestampPattern = regexp.MustCompile(`^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*[-–—:]?\s*(.+)$`)

// ParseChaptersFromDescription extracts chapters from a video description
// that contains timestamps in common formats like:
// 0:00 Introduction
// 1:23 - Topic One
// 10:45 Topic Two
func ParseChaptersFromDescription(description string) []Chapter {
	var chapters []Chapter

	lines := strings.Split(description, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		chapter := parseTimestampLine(line)
		if chapter != nil {
			chapters = append(chapters, *chapter)
		}
	}

	// Validate that we have a reasonable chapter list
	// (at least 2 chapters, and they should be in order)
	if len(chapters) < 2 {
		return nil
	}

	// Verify chapters are in chronological order
	for i := 1; i < len(chapters); i++ {
		if chapters[i].StartTime < chapters[i-1].StartTime {
			return nil
		}
	}

	return chapters
}

// parseTimestampLine attempts to parse a single line as a chapter timestamp
func parseTimestampLine(line string) *Chapter {
	matches := timestampPattern.FindStringSubmatch(line)
	if matches == nil {
		return nil
	}

	var hours, minutes, seconds int
	var title string
	var err error

	if matches[3] != "" {
		// Format: HH:MM:SS
		hours, err = strconv.Atoi(matches[1])
		if err != nil {
			return nil
		}
		minutes, err = strconv.Atoi(matches[2])
		if err != nil {
			return nil
		}
		seconds, err = strconv.Atoi(matches[3])
		if err != nil {
			return nil
		}
		title = matches[4]
	} else {
		// Format: MM:SS
		minutes, err = strconv.Atoi(matches[1])
		if err != nil {
			return nil
		}
		seconds, err = strconv.Atoi(matches[2])
		if err != nil {
			return nil
		}
		title = matches[4]
	}

	// Validate reasonable values
	if minutes > 59 && hours == 0 {
		// If minutes > 59 and no hours, treat first number as hours
		hours = minutes
		minutes = seconds
		seconds = 0
	}

	if seconds > 59 || (minutes > 59 && hours > 0) {
		return nil
	}

	title = strings.TrimSpace(title)
	if title == "" {
		return nil
	}

	startTime := float64(hours*3600 + minutes*60 + seconds)

	return &Chapter{
		StartTime: startTime,
		Title:     title,
	}
}

// FormatDuration formats a duration in seconds to HH:MM:SS or MM:SS format
func FormatDuration(seconds float64) string {
	totalSeconds := int(seconds)
	hours := totalSeconds / 3600
	minutes := (totalSeconds % 3600) / 60
	secs := totalSeconds % 60

	if hours > 0 {
		return fmt.Sprintf("%d:%02d:%02d", hours, minutes, secs)
	}
	return fmt.Sprintf("%d:%02d", minutes, secs)
}
