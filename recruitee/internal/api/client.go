package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

const (
	BaseURL    = "https://xebiacareers.recruitee.com/api"
	Department = "Data & AI"
)

type Client struct {
	httpClient *http.Client
	baseURL    string
}

func NewClient() *Client {
	return &Client{
		httpClient: &http.Client{Timeout: 30 * time.Second},
		baseURL:    BaseURL,
	}
}

type OffersResponse struct {
	Offers []Offer `json:"offers"`
}

type Offer struct {
	ID                 int              `json:"id"`
	Title              string           `json:"title"`
	Slug               string           `json:"slug"`
	Department         string           `json:"department"`
	Description        string           `json:"description"`
	Requirements       string           `json:"requirements"`
	City               string           `json:"city"`
	Country            string           `json:"country"`
	CountryCode        string           `json:"country_code"`
	Location           string           `json:"location"`
	Remote             bool             `json:"remote"`
	Hybrid             bool             `json:"hybrid"`
	OnSite             bool             `json:"on_site"`
	EmploymentTypeCode string           `json:"employment_type_code"`
	MinHours           *int             `json:"min_hours"`
	MaxHours           *int             `json:"max_hours"`
	CreatedAt          string           `json:"created_at"`
	PublishedAt        string           `json:"published_at"`
	OptionsCV          string           `json:"options_cv"`
	OptionsPhone       string           `json:"options_phone"`
	OptionsCoverLetter string           `json:"options_cover_letter"`
	CareersURL         string           `json:"careers_url"`
	CareersApplyURL    string           `json:"careers_apply_url"`
	OpenQuestions      []OpenQuestion   `json:"open_questions"`
	Locations          []OfferLocation  `json:"locations"`
}

type OpenQuestion struct {
	ID                  int                  `json:"id"`
	Body                string               `json:"body"`
	Kind                string               `json:"kind"`
	Required            bool                 `json:"required"`
	OpenQuestionOptions []OpenQuestionOption `json:"open_question_options"`
}

type OpenQuestionOption struct {
	ID   int    `json:"id"`
	Body string `json:"body"`
}

// GetOptions returns the option bodies as a string slice (for template convenience)
func (q OpenQuestion) GetOptions() []string {
	var opts []string
	for _, o := range q.OpenQuestionOptions {
		opts = append(opts, o.Body)
	}
	return opts
}

type OfferLocation struct {
	City        string `json:"city"`
	Country     string `json:"country"`
	CountryCode string `json:"country_code"`
	Region      string `json:"region"`
}

// FetchOffers retrieves all published offers from Recruitee
func (c *Client) FetchOffers() ([]Offer, error) {
	resp, err := c.httpClient.Get(c.baseURL + "/offers")
	if err != nil {
		return nil, fmt.Errorf("failed to fetch offers: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	var offersResp OffersResponse
	if err := json.NewDecoder(resp.Body).Decode(&offersResp); err != nil {
		return nil, fmt.Errorf("failed to decode offers: %w", err)
	}

	return offersResp.Offers, nil
}

// FetchDataAIOffers retrieves only Data & AI department offers
func (c *Client) FetchDataAIOffers() ([]Offer, error) {
	offers, err := c.FetchOffers()
	if err != nil {
		return nil, err
	}

	var filtered []Offer
	for _, offer := range offers {
		if offer.Department == Department {
			filtered = append(filtered, offer)
		}
	}

	return filtered, nil
}

// GetWorkType returns a human-readable work type string
func (o Offer) GetWorkType() string {
	var types []string
	if o.Remote {
		types = append(types, "Remote")
	}
	if o.Hybrid {
		types = append(types, "Hybrid")
	}
	if o.OnSite {
		types = append(types, "On-site")
	}
	if len(types) == 0 {
		return "On-site"
	}
	result := types[0]
	for i := 1; i < len(types); i++ {
		result += " / " + types[i]
	}
	return result
}

// GetEmploymentType returns a human-readable employment type
func (o Offer) GetEmploymentType() string {
	switch o.EmploymentTypeCode {
	case "fulltime_permanent":
		return "Full-time"
	case "parttime_permanent":
		return "Part-time"
	case "fulltime_temporary":
		return "Full-time (Contract)"
	case "parttime_temporary":
		return "Part-time (Contract)"
	case "freelance":
		return "Freelance"
	case "internship":
		return "Internship"
	default:
		return "Full-time"
	}
}

// GetLocationString returns a formatted location string
func (o Offer) GetLocationString() string {
	if o.Location != "" {
		return o.Location
	}
	if o.City != "" && o.Country != "" {
		return o.City + ", " + o.Country
	}
	if o.Country != "" {
		return o.Country
	}
	return "Remote"
}
