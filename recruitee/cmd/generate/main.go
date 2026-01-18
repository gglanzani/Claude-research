package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/xebia/recruitee-careers/internal/api"
	"github.com/xebia/recruitee-careers/internal/generator"
)

func main() {
	var (
		templatesDir string
		outputDir    string
		staticDir    string
	)

	flag.StringVar(&templatesDir, "templates", "templates", "Path to templates directory")
	flag.StringVar(&outputDir, "output", "output", "Path to output directory")
	flag.StringVar(&staticDir, "static", "static", "Path to static files directory")
	flag.Parse()

	// Resolve paths relative to working directory if not absolute
	if !filepath.IsAbs(templatesDir) {
		wd, _ := os.Getwd()
		templatesDir = filepath.Join(wd, templatesDir)
	}
	if !filepath.IsAbs(outputDir) {
		wd, _ := os.Getwd()
		outputDir = filepath.Join(wd, outputDir)
	}
	if !filepath.IsAbs(staticDir) {
		wd, _ := os.Getwd()
		staticDir = filepath.Join(wd, staticDir)
	}

	fmt.Println("Fetching Data & AI offers from Recruitee...")

	client := api.NewClient()
	offers, err := client.FetchDataAIOffers()
	if err != nil {
		log.Fatalf("Failed to fetch offers: %v", err)
	}

	fmt.Printf("Found %d Data & AI positions\n", len(offers))

	if len(offers) == 0 {
		fmt.Println("No offers found, generating empty page")
	}

	fmt.Println("Generating static site...")

	gen := generator.New(templatesDir, outputDir, staticDir)
	if err := gen.Generate(offers); err != nil {
		log.Fatalf("Failed to generate site: %v", err)
	}

	fmt.Printf("Static site generated successfully in %s\n", outputDir)
}
