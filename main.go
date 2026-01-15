package main

import (
	"encoding/xml"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

type RSS struct {
	Channel Channel `xml:"channel"`
}

type Channel struct {
	Items []Item `xml:"item"`
}

type Item struct {
	Title   string `xml:"title"`
	Link    string `xml:"link"`
	PubDate string `xml:"pubDate"`
	Creator string `xml:"http://purl.org/dc/elements/1.1/ creator"`
}

func main() {
	feedURL := flag.String("feed", "", "RSS feed URL (required)")
	sinceDays := flag.Int("since", 0, "Number of days to look back (0 = no limit)")
	flag.Parse()

	if *feedURL == "" {
		fmt.Fprintf(os.Stderr, "Error: --feed parameter is required\n")
		flag.Usage()
		os.Exit(1)
	}

	// Fetch the feed
	resp, err := http.Get(*feedURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error fetching feed: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "Error: received status code %d\n", resp.StatusCode)
		os.Exit(1)
	}

	// Parse the RSS feed
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading response: %v\n", err)
		os.Exit(1)
	}

	var rss RSS
	if err := xml.Unmarshal(body, &rss); err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing RSS: %v\n", err)
		os.Exit(1)
	}

	// Calculate cutoff date if since is specified
	var cutoffDate time.Time
	if *sinceDays > 0 {
		cutoffDate = time.Now().AddDate(0, 0, -*sinceDays)
	}

	// Filter and output items
	for _, item := range rss.Channel.Items {
		// Check if URL contains post_type=news or post_type=article
		if shouldFilter(item.Link) {
			continue
		}

		// Check date if since parameter is specified
		if *sinceDays > 0 {
			pubDate, err := parseRSSDate(item.PubDate)
			if err != nil {
				// Skip items with unparseable dates
				continue
			}
			if pubDate.Before(cutoffDate) {
				continue
			}
		}

		// Output as Markdown list item
		author := item.Creator
		if author == "" {
			author = "Unknown"
		}
		fmt.Printf("- [%s](%s) - %s\n", item.Title, item.Link, author)
	}
}

// shouldFilter returns true if the URL contains /news/ or /articles/ in the path
// or has post_type=news or post_type=article in query parameters
func shouldFilter(link string) bool {
	parsedURL, err := url.Parse(link)
	if err != nil {
		return false
	}

	// Check URL path for /news/ or /articles/
	path := parsedURL.Path
	if strings.Contains(path, "/news/") || strings.Contains(path, "/articles/") {
		return true
	}

	// Also check query parameters as fallback
	query := parsedURL.Query()
	postType := query.Get("post_type")

	return postType == "news" || postType == "article" || postType == "articles"
}

// parseRSSDate parses common RSS date formats
func parseRSSDate(dateStr string) (time.Time, error) {
	// RSS typically uses RFC1123Z format: "Mon, 02 Jan 2006 15:04:05 -0700"
	formats := []string{
		time.RFC1123Z,
		time.RFC1123,
		time.RFC822Z,
		time.RFC822,
		"2006-01-02T15:04:05Z07:00", // ISO 8601
		"2006-01-02",
	}

	dateStr = strings.TrimSpace(dateStr)

	for _, format := range formats {
		if t, err := time.Parse(format, dateStr); err == nil {
			return t, nil
		}
	}

	return time.Time{}, fmt.Errorf("unable to parse date: %s", dateStr)
}
