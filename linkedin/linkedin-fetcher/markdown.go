package main

import (
	"fmt"
	"regexp"
	"strings"
	"time"
	"unicode"
)

// generatePostMarkdownFiles creates markdown files from snapshot MEMBER_SHARE_INFO data.
// Returns the number of new files created.
func generatePostMarkdownFiles(data []map[string]interface{}, outputDir string, state *State) int {
	count := 0
	for _, record := range data {
		url, _ := record["ShareLink"].(string)
		if url == "" {
			url, _ = record["ShareUrl"].(string)
		}
		if url == "" {
			continue
		}

		// Deduplicate
		if state.SeenPosts[url] {
			continue
		}

		dateStr, _ := record["Date"].(string)
		text, _ := record["ShareCommentary"].(string)
		if text == "" {
			text, _ = record["SharedText"].(string)
		}
		if text == "" {
			text, _ = record["Commentary"].(string)
		}
		visibility, _ := record["Visibility"].(string)

		md := snapshotPostToMarkdown(dateStr, text, url, visibility, record)
		if md == "" {
			continue
		}

		filename := makeFilename(dateStr, text)
		outPath := outputDir + "/" + filename
		if fileExists(outPath) {
			state.SeenPosts[url] = true
			continue
		}

		if err := writeFileString(outPath, md); err != nil {
			continue
		}

		state.SeenPosts[url] = true
		count++
	}
	return count
}

// snapshotPostToMarkdown converts a MEMBER_SHARE_INFO record to Hugo-compatible markdown.
// Matches the format: TOML front matter with +++, then body text.
func snapshotPostToMarkdown(dateStr, text, url, visibility string, record map[string]interface{}) string {
	if text == "" && url == "" {
		return ""
	}

	// Parse date - LinkedIn uses various formats
	parsedDate := parseLinkedInDate(dateStr)
	formattedDate := parsedDate.Format("2006-01-02")

	// Build title: first ~60 chars of the text, cleaned up
	title := makeTitle(text)

	var sb strings.Builder
	sb.WriteString("+++\n")
	sb.WriteString(fmt.Sprintf("title = %q\n", title))
	sb.WriteString(fmt.Sprintf("date = %q\n", formattedDate))
	sb.WriteString("draft = false\n")
	sb.WriteString("[params]\n")
	sb.WriteString("  source = \"linkedin\"\n")
	if url != "" {
		sb.WriteString(fmt.Sprintf("  url = %q\n", url))
	}
	if visibility != "" {
		sb.WriteString(fmt.Sprintf("  visibility = %q\n", visibility))
	}
	sb.WriteString("  fetched_via = \"snapshot\"\n")
	sb.WriteString("+++\n\n")
	sb.WriteString(text)
	sb.WriteString("\n")

	// If there's a media URL in the record
	if mediaURL, ok := record["MediaUrl"].(string); ok && mediaURL != "" {
		sb.WriteString(fmt.Sprintf("\n![Post media](%s)\n", mediaURL))
	}

	return sb.String()
}

// changelogEventToMarkdown converts a changelog CREATE event into markdown.
func changelogEventToMarkdown(event ChangelogEvent) string {
	// Try to extract post text from processedActivity
	text := extractText(event.ProcessedActivity)
	if text == "" {
		text = extractText(event.Activity)
	}
	if text == "" {
		return ""
	}

	capturedTime := time.UnixMilli(event.CapturedAt)
	formattedDate := capturedTime.Format("2006-01-02")
	title := makeTitle(text)

	var sb strings.Builder
	sb.WriteString("+++\n")
	sb.WriteString(fmt.Sprintf("title = %q\n", title))
	sb.WriteString(fmt.Sprintf("date = %q\n", formattedDate))
	sb.WriteString("draft = false\n")
	sb.WriteString("[params]\n")
	sb.WriteString("  source = \"linkedin\"\n")
	sb.WriteString(fmt.Sprintf("  resource_name = %q\n", event.ResourceName))
	sb.WriteString(fmt.Sprintf("  resource_id = %q\n", event.ResourceID))
	if event.ResourceURI != "" {
		sb.WriteString(fmt.Sprintf("  resource_uri = %q\n", event.ResourceURI))
	}
	sb.WriteString(fmt.Sprintf("  changelog_method = %q\n", event.Method))
	sb.WriteString(fmt.Sprintf("  captured_at = %q\n", capturedTime.Format(time.RFC3339)))
	sb.WriteString("  fetched_via = \"changelog\"\n")
	sb.WriteString("+++\n\n")
	sb.WriteString(text)
	sb.WriteString("\n")

	return sb.String()
}

// generateFilename creates a filename from a changelog event.
func generateFilename(event ChangelogEvent) string {
	text := extractText(event.ProcessedActivity)
	if text == "" {
		text = extractText(event.Activity)
	}
	capturedTime := time.UnixMilli(event.CapturedAt)
	dateStr := capturedTime.Format("2006-01-02")
	return makeFilename(dateStr, text)
}

// extractText tries to find the post body text from an activity map.
// LinkedIn uses various field names depending on the resource type.
func extractText(activity map[string]interface{}) string {
	if activity == nil {
		return ""
	}

	// Check common field paths for post content
	textFields := []string{
		"commentary", "shareCommentary", "specificContent",
		"text", "body", "content", "message", "description",
	}

	for _, field := range textFields {
		if val, ok := activity[field]; ok {
			switch v := val.(type) {
			case string:
				if v != "" && v != "Unable_to_process_this_field." {
					return v
				}
			case map[string]interface{}:
				// Could be nested like {"text": "the content"} or {"string": "the content"}
				for _, innerKey := range []string{"text", "string", "rawText", "content"} {
					if inner, ok := v[innerKey].(string); ok && inner != "" {
						return inner
					}
				}
			}
		}
	}

	// Try nested specificContent -> com.linkedin.ugc.ShareContent -> shareCommentary -> text
	if sc, ok := activity["specificContent"].(map[string]interface{}); ok {
		for _, v := range sc {
			if m, ok := v.(map[string]interface{}); ok {
				if comm, ok := m["shareCommentary"].(map[string]interface{}); ok {
					if t, ok := comm["text"].(string); ok {
						return t
					}
				}
			}
		}
	}

	return ""
}

// makeTitle extracts a clean title from post text (first ~60 chars).
func makeTitle(text string) string {
	if text == "" {
		return "Untitled post"
	}

	// Take first line or first ~80 chars
	lines := strings.SplitN(text, "\n", 2)
	title := strings.TrimSpace(lines[0])

	// Truncate to ~80 chars at a word boundary
	if len(title) > 80 {
		title = title[:80]
		if idx := strings.LastIndex(title, " "); idx > 40 {
			title = title[:idx]
		}
	}

	// Clean up quotes and special chars for TOML
	title = strings.ReplaceAll(title, "\r", "")

	return title
}

// makeFilename generates a slug-style filename matching your existing convention:
// YYYY-MM-DD-first-words-of-the-post.md
func makeFilename(dateStr, text string) string {
	// Parse and reformat date
	t := parseLinkedInDate(dateStr)
	datePart := t.Format("2006-01-02")

	// Slugify the text
	slug := slugify(text, 60)
	if slug == "" {
		slug = "untitled-post"
	}

	return fmt.Sprintf("%s-%s.md", datePart, slug)
}

func slugify(text string, maxLen int) string {
	text = strings.ToLower(text)

	// Replace non-alphanumeric with hyphens
	var sb strings.Builder
	lastWasHyphen := false
	for _, r := range text {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			sb.WriteRune(r)
			lastWasHyphen = false
		} else if !lastWasHyphen {
			sb.WriteRune('-')
			lastWasHyphen = true
		}
		if sb.Len() >= maxLen {
			break
		}
	}

	result := strings.Trim(sb.String(), "-")

	// Truncate at a word boundary
	if len(result) >= maxLen {
		if idx := strings.LastIndex(result[:maxLen], "-"); idx > 20 {
			result = result[:idx]
		} else {
			result = result[:maxLen]
		}
	}

	return result
}

var dateFormats = []string{
	"2006-01-02",
	"01/02/2006",
	"Jan 2, 2006",
	"January 2, 2006",
	"2006-01-02T15:04:05Z",
	"2006-01-02 15:04:05",
	time.RFC3339,
}

func parseLinkedInDate(dateStr string) time.Time {
	dateStr = strings.TrimSpace(dateStr)

	// Try epoch milliseconds (number as string)
	if matched, _ := regexp.MatchString(`^\d{13}$`, dateStr); matched {
		var ms int64
		fmt.Sscanf(dateStr, "%d", &ms)
		return time.UnixMilli(ms)
	}

	for _, layout := range dateFormats {
		if t, err := time.Parse(layout, dateStr); err == nil {
			return t
		}
	}

	// Fallback to now
	return time.Now()
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func writeFileString(path, content string) error {
	return os.WriteFile(path, []byte(content), 0644)
}
