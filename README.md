# RSS Feed Filter

A Go command-line tool that filters RSS feeds to show only technical blog posts (excluding marketing/news content) and outputs them as a Markdown list.

## Features

- Fetches and parses RSS feeds
- Filters out marketing content (posts with `/news/` or `/articles/` in the URL path)
- Optional date filtering to show only recent posts
- Outputs clean Markdown list with linked titles and authors

## Installation

```bash
go build -o feed-filter
```

## Usage

### Basic usage (all technical posts):
```bash
go run main.go --feed "https://xebia.com/blog/category/domains/data-ai/feed"
```

### Filter by date (last N days):
```bash
go run main.go --feed "https://xebia.com/blog/category/domains/data-ai/feed" --since 7
```

### Using the compiled binary:
```bash
./feed-filter --feed "https://xebia.com/blog/category/domains/data-ai/feed" --since 30
```

## Parameters

- `--feed` (required): RSS feed URL to fetch and filter
- `--since` (optional): Number of days to look back (0 = no limit, default: 0)

## Output Format

The tool outputs a Markdown list to stdout:

```markdown
- [Post Title](https://example.com/post-url) - Author Name
- [Another Post](https://example.com/another-post) - Another Author
```

## Filtering Logic

The tool filters OUT posts that contain:
- `/news/` in the URL path
- `/articles/` in the URL path
- `post_type=news` in query parameters
- `post_type=article` or `post_type=articles` in query parameters

This keeps only technical blog posts (typically under `/blog/` paths).

## Example

```bash
$ go run main.go --feed "https://xebia.com/blog/category/domains/data-ai/feed" --since 7
- [Realist's Guide to Hybrid Mesh Architecture (1): Single Source of Truth vs Democratisation](https://xebia.com/blog/realists-guide-to-hybrid-mesh-architecture-1-single-source-of-truth-vs-democratisation/) - XiaoHan Li
```
