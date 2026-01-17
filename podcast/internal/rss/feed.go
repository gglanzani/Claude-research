package rss

import (
	"bytes"
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/gglanzani/podcast/internal/config"
	"github.com/gglanzani/podcast/internal/storage"
)

const (
	episodesFile = "episodes.json"
	feedFile     = "feed.xml"
)

// FeedManager manages the podcast RSS feed
type FeedManager struct {
	cfg     *config.Config
	storage storage.Storage
	feed    *PodcastFeed
	mu      sync.RWMutex
}

// NewFeedManager creates a new feed manager
func NewFeedManager(cfg *config.Config, store storage.Storage) *FeedManager {
	return &FeedManager{
		cfg:     cfg,
		storage: store,
		feed: &PodcastFeed{
			Title:       cfg.PodcastTitle,
			Description: cfg.PodcastDescription,
			Author:      cfg.PodcastAuthor,
			Email:       cfg.PodcastEmail,
			ImageURL:    cfg.PodcastImageURL,
			Language:    cfg.PodcastLanguage,
			Link:        cfg.ExternalURL,
			Episodes:    []Episode{},
		},
	}
}

// Load loads existing episodes from storage
func (fm *FeedManager) Load(ctx context.Context) error {
	fm.mu.Lock()
	defer fm.mu.Unlock()

	exists, err := fm.storage.Exists(ctx, episodesFile)
	if err != nil {
		return fmt.Errorf("failed to check episodes file: %w", err)
	}

	if !exists {
		return nil
	}

	reader, err := fm.storage.Download(ctx, episodesFile)
	if err != nil {
		return fmt.Errorf("failed to download episodes: %w", err)
	}
	defer reader.Close()

	data, err := io.ReadAll(reader)
	if err != nil {
		return fmt.Errorf("failed to read episodes: %w", err)
	}

	var feed PodcastFeed
	if err := json.Unmarshal(data, &feed); err != nil {
		return fmt.Errorf("failed to parse episodes: %w", err)
	}

	// Preserve config values but load episodes
	fm.feed.Episodes = feed.Episodes

	return nil
}

// AddEpisode adds a new episode to the feed
func (fm *FeedManager) AddEpisode(ctx context.Context, episode Episode) error {
	fm.mu.Lock()
	defer fm.mu.Unlock()

	// Add to beginning of list (newest first)
	fm.feed.Episodes = append([]Episode{episode}, fm.feed.Episodes...)

	// Save and regenerate feed
	if err := fm.save(ctx); err != nil {
		return err
	}

	return fm.generateFeed(ctx)
}

// GetEpisodes returns all episodes
func (fm *FeedManager) GetEpisodes() []Episode {
	fm.mu.RLock()
	defer fm.mu.RUnlock()

	episodes := make([]Episode, len(fm.feed.Episodes))
	copy(episodes, fm.feed.Episodes)
	return episodes
}

// GetFeed returns the current feed
func (fm *FeedManager) GetFeed() *PodcastFeed {
	fm.mu.RLock()
	defer fm.mu.RUnlock()

	return fm.feed
}

// save persists episodes to storage
func (fm *FeedManager) save(ctx context.Context) error {
	data, err := json.MarshalIndent(fm.feed, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal episodes: %w", err)
	}

	_, err = fm.storage.Upload(ctx, episodesFile, bytes.NewReader(data), "application/json")
	if err != nil {
		return fmt.Errorf("failed to upload episodes: %w", err)
	}

	return nil
}

// generateFeed generates the RSS XML feed
func (fm *FeedManager) generateFeed(ctx context.Context) error {
	xmlData, err := fm.GenerateXML()
	if err != nil {
		return err
	}

	_, err = fm.storage.Upload(ctx, feedFile, bytes.NewReader(xmlData), "application/rss+xml")
	if err != nil {
		return fmt.Errorf("failed to upload feed: %w", err)
	}

	return nil
}

// GenerateXML generates the RSS XML
func (fm *FeedManager) GenerateXML() ([]byte, error) {
	rss := RSS{
		Version:   "2.0",
		ITunesNS:  "http://www.itunes.com/dtds/podcast-1.0.dtd",
		AtomNS:    "http://www.w3.org/2005/Atom",
		PodcastNS: "https://podcastindex.org/namespace/1.0",
		ContentNS: "http://purl.org/rss/1.0/modules/content/",
	}

	feedURL := fm.storage.GetPublicURL(feedFile)

	channel := Channel{
		Title:         fm.feed.Title,
		Link:          fm.feed.Link,
		Description:   fm.feed.Description,
		Language:      fm.feed.Language,
		Generator:     "YouTube to Podcast RSS Generator",
		LastBuildDate: time.Now().Format(time.RFC1123Z),
		AtomLink: AtomLink{
			Href: feedURL,
			Rel:  "self",
			Type: "application/rss+xml",
		},
		ITunesAuthor: fm.feed.Author,
		ITunesOwner: ITunesOwner{
			Name:  fm.feed.Author,
			Email: fm.feed.Email,
		},
		ITunesExplicit: "false",
		ITunesType:     "episodic",
	}

	if fm.feed.ImageURL != "" {
		channel.ITunesImage = &ITunesImage{Href: fm.feed.ImageURL}
		channel.Image = &Image{
			URL:   fm.feed.ImageURL,
			Title: fm.feed.Title,
			Link:  fm.feed.Link,
		}
	}

	for _, ep := range fm.feed.Episodes {
		item := Item{
			Title:       ep.Title,
			Description: ep.Description,
			GUID: GUID{
				IsPermaLink: false,
				Value:       ep.ID,
			},
			PubDate: ep.PublishedAt.Format(time.RFC1123Z),
			Enclosure: Enclosure{
				URL:    ep.AudioURL,
				Length: ep.FileSize,
				Type:   "audio/mpeg",
			},
			ITunesDuration: formatDuration(ep.Duration),
			ITunesAuthor:   ep.Author,
			ITunesExplicit: "false",
		}

		if ep.ChaptersURL != "" {
			item.PodcastChapters = &PodcastChapters{
				URL:  ep.ChaptersURL,
				Type: "application/json+chapters",
			}
		}

		channel.Items = append(channel.Items, item)
	}

	rss.Channel = channel

	var buf bytes.Buffer
	buf.WriteString(xml.Header)
	encoder := xml.NewEncoder(&buf)
	encoder.Indent("", "  ")
	if err := encoder.Encode(rss); err != nil {
		return nil, fmt.Errorf("failed to encode RSS: %w", err)
	}

	return buf.Bytes(), nil
}

// formatDuration formats seconds to HH:MM:SS
func formatDuration(seconds int) string {
	h := seconds / 3600
	m := (seconds % 3600) / 60
	s := seconds % 60
	if h > 0 {
		return fmt.Sprintf("%d:%02d:%02d", h, m, s)
	}
	return fmt.Sprintf("%d:%02d", m, s)
}

// RSS XML structures
type RSS struct {
	XMLName   xml.Name `xml:"rss"`
	Version   string   `xml:"version,attr"`
	ITunesNS  string   `xml:"xmlns:itunes,attr"`
	AtomNS    string   `xml:"xmlns:atom,attr"`
	PodcastNS string   `xml:"xmlns:podcast,attr"`
	ContentNS string   `xml:"xmlns:content,attr"`
	Channel   Channel  `xml:"channel"`
}

type Channel struct {
	Title          string       `xml:"title"`
	Link           string       `xml:"link"`
	Description    string       `xml:"description"`
	Language       string       `xml:"language"`
	Generator      string       `xml:"generator"`
	LastBuildDate  string       `xml:"lastBuildDate"`
	AtomLink       AtomLink     `xml:"atom:link"`
	Image          *Image       `xml:"image,omitempty"`
	ITunesAuthor   string       `xml:"itunes:author"`
	ITunesOwner    ITunesOwner  `xml:"itunes:owner"`
	ITunesImage    *ITunesImage `xml:"itunes:image,omitempty"`
	ITunesExplicit string       `xml:"itunes:explicit"`
	ITunesType     string       `xml:"itunes:type"`
	Items          []Item       `xml:"item"`
}

type AtomLink struct {
	Href string `xml:"href,attr"`
	Rel  string `xml:"rel,attr"`
	Type string `xml:"type,attr"`
}

type Image struct {
	URL   string `xml:"url"`
	Title string `xml:"title"`
	Link  string `xml:"link"`
}

type ITunesOwner struct {
	Name  string `xml:"itunes:name"`
	Email string `xml:"itunes:email"`
}

type ITunesImage struct {
	Href string `xml:"href,attr"`
}

type Item struct {
	Title           string           `xml:"title"`
	Description     string           `xml:"description"`
	GUID            GUID             `xml:"guid"`
	PubDate         string           `xml:"pubDate"`
	Enclosure       Enclosure        `xml:"enclosure"`
	ITunesDuration  string           `xml:"itunes:duration"`
	ITunesAuthor    string           `xml:"itunes:author"`
	ITunesExplicit  string           `xml:"itunes:explicit"`
	PodcastChapters *PodcastChapters `xml:"podcast:chapters,omitempty"`
}

type GUID struct {
	IsPermaLink bool   `xml:"isPermaLink,attr"`
	Value       string `xml:",chardata"`
}

type Enclosure struct {
	URL    string `xml:"url,attr"`
	Length int64  `xml:"length,attr"`
	Type   string `xml:"type,attr"`
}

type PodcastChapters struct {
	URL  string `xml:"url,attr"`
	Type string `xml:"type,attr"`
}
