package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

const (
	baseURL        = "https://api.linkedin.com/rest"
	linkedInVersion = "202312"
)

// LinkedInClient wraps authenticated calls to the LinkedIn DMA Portability APIs.
type LinkedInClient struct {
	token      string
	httpClient *http.Client
}

func NewLinkedInClient(token string) *LinkedInClient {
	return &LinkedInClient{
		token: token,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (c *LinkedInClient) doRequest(url string) ([]byte, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Linkedin-Version", linkedInVersion)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("executing request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("reading response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	return body, nil
}

// --- Member Snapshot API ---

// SnapshotResponse is the response from /rest/memberSnapshotData
type SnapshotResponse struct {
	Paging   Paging            `json:"paging"`
	Elements []SnapshotElement `json:"elements"`
}

type SnapshotElement struct {
	SnapshotDomain string                   `json:"snapshotDomain"`
	SnapshotData   []map[string]interface{} `json:"snapshotData"`
}

type Paging struct {
	Start int          `json:"start"`
	Count int          `json:"count"`
	Total int          `json:"total"`
	Links []PagingLink `json:"links"`
}

type PagingLink struct {
	Type string `json:"type"`
	Rel  string `json:"rel"`
	Href string `json:"href"`
}

// FetchSnapshotDomain fetches all pages of a given snapshot domain.
func (c *LinkedInClient) FetchSnapshotDomain(domain string, maxPages int) ([]map[string]interface{}, error) {
	var allData []map[string]interface{}

	start := 0
	for page := 0; page < maxPages; page++ {
		url := fmt.Sprintf("%s/memberSnapshotData?q=criteria&domain=%s&start=%d", baseURL, domain, start)
		log.Printf("  GET %s (page %d)", url, page)

		body, err := c.doRequest(url)
		if err != nil {
			// "No data found" means we've exhausted the pages
			if contains(string(body), "No data found") {
				break
			}
			// On first page, this is likely a real error
			if page == 0 {
				return nil, err
			}
			// On subsequent pages, we may have just run out of data
			log.Printf("  Stopping pagination: %v", err)
			break
		}

		var resp SnapshotResponse
		if err := json.Unmarshal(body, &resp); err != nil {
			return nil, fmt.Errorf("parsing snapshot response: %w", err)
		}

		for _, elem := range resp.Elements {
			allData = append(allData, elem.SnapshotData...)
		}

		// Check if there's a next page
		hasNext := false
		for _, link := range resp.Paging.Links {
			if link.Rel == "next" {
				hasNext = true
				break
			}
		}
		if !hasNext {
			break
		}

		start++
		// Be nice to the API
		time.Sleep(500 * time.Millisecond)
	}

	return allData, nil
}

// --- Member Changelog API ---

// ChangelogResponse is the response from /rest/memberChangeLogs
type ChangelogResponse struct {
	Paging   Paging           `json:"paging"`
	Elements []ChangelogEvent `json:"elements"`
}

// ChangelogEvent represents a single changelog activity record.
type ChangelogEvent struct {
	ID                      int64                  `json:"id"`
	CapturedAt              int64                  `json:"capturedAt"`
	ProcessedAt             int64                  `json:"processedAt"`
	ConfigVersion           int                    `json:"configVersion"`
	Owner                   string                 `json:"owner"`
	Actor                   string                 `json:"actor"`
	ResourceName            string                 `json:"resourceName"`
	ResourceID              string                 `json:"resourceId"`
	ResourceURI             string                 `json:"resourceUri"`
	Method                  string                 `json:"method"`
	MethodName              string                 `json:"methodName,omitempty"`
	Activity                map[string]interface{} `json:"activity"`
	ProcessedActivity       map[string]interface{} `json:"processedActivity"`
	SiblingActivities       []interface{}          `json:"siblingActivities,omitempty"`
	ParentSiblingActivities []interface{}          `json:"parentSiblingActivities,omitempty"`
	ActivityID              string                 `json:"activityId"`
	ActivityStatus          string                 `json:"activityStatus,omitempty"`
}

// FetchChangelogEvents fetches all changelog events since startTime.
// Returns the events and the latest processedAt timestamp for state tracking.
//
// LinkedIn recommends: count=10, poll once per hour, use latest processedAt as next startTime.
func (c *LinkedInClient) FetchChangelogEvents(startTimeMs int64) ([]ChangelogEvent, int64, error) {
	var allEvents []ChangelogEvent
	var latestProcessedAt int64

	count := 10 // LinkedIn recommended count
	maxIterations := 100

	currentStartTime := startTimeMs

	for i := 0; i < maxIterations; i++ {
		url := fmt.Sprintf("%s/memberChangeLogs?q=memberAndApplication&startTime=%d&count=%d",
			baseURL, currentStartTime, count)

		log.Printf("  GET %s", url)

		body, err := c.doRequest(url)
		if err != nil {
			if i == 0 {
				return nil, 0, err
			}
			log.Printf("  Stopping changelog fetch: %v", err)
			break
		}

		var resp ChangelogResponse
		if err := json.Unmarshal(body, &resp); err != nil {
			return nil, 0, fmt.Errorf("parsing changelog response: %w", err)
		}

		if len(resp.Elements) == 0 {
			break
		}

		allEvents = append(allEvents, resp.Elements...)

		// Track the latest processedAt for state
		for _, event := range resp.Elements {
			if event.ProcessedAt > latestProcessedAt {
				latestProcessedAt = event.ProcessedAt
			}
		}

		// If we got fewer than count, we've caught up
		if len(resp.Elements) < count {
			break
		}

		// Use latest processedAt as next startTime (LinkedIn recommendation)
		currentStartTime = latestProcessedAt

		// Respect rate limits
		time.Sleep(1 * time.Second)
	}

	return allEvents, latestProcessedAt, nil
}

// --- Member Authorization Check ---

// CheckAuthorization verifies that changelog events are being generated for the user.
func (c *LinkedInClient) CheckAuthorization() (bool, error) {
	url := fmt.Sprintf("%s/memberAuthorizations?q=memberAndApplication", baseURL)
	body, err := c.doRequest(url)
	if err != nil {
		return false, err
	}

	var resp struct {
		Elements []struct {
			RegulatedAt int64 `json:"regulatedAt"`
		} `json:"elements"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return false, err
	}

	return len(resp.Elements) > 0, nil
}

// EnableChangelog manually enables changelog event generation via POST.
func (c *LinkedInClient) EnableChangelog() error {
	req, err := http.NewRequest("POST", baseURL+"/memberAuthorizations", nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Linkedin-Version", linkedInVersion)
	req.Header.Set("Content-Type", "application/json")

	// LinkedIn requires an empty JSON body
	req.Body = io.NopCloser(emptyJSONReader())

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("enable changelog returned status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsSubstr(s, substr))
}

func containsSubstr(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
