# Xebia Careers - Data & AI

A custom static careers page for Xebia's Data & AI department, fetching vacancies from Recruitee and serving them with Xebia's look and feel.

## Features

- **Static site generation** - Pure HTML/CSS/JS output, no backend required
- **Recruitee integration** - Fetches live job listings from Recruitee API
- **Data & AI focus** - Only shows positions from the Data & AI department
- **Direct applications** - Users apply via JavaScript directly to Recruitee API
- **Daily sync** - GitHub Action updates vacancies at midnight UTC
- **Xebia styling** - Matches Xebia's brand colors and design

## Architecture

```
recruitee/
├── cmd/generate/         # CLI tool for generating the static site
├── internal/
│   ├── api/              # Recruitee API client
│   └── generator/        # Static HTML generator
├── templates/            # HTML templates (index + job detail)
├── static/               # CSS and JavaScript
├── output/               # Generated static site (committed)
└── .github/workflows/    # Daily sync automation
```

## How it works

1. **Build time**: Go fetches vacancies from `https://xebiacareers.recruitee.com/api/offers/`
2. **Filter**: Only keeps jobs where `department == "Data & AI"`
3. **Generate**: Creates static HTML pages for each job
4. **Deploy**: Output folder is committed and can be deployed anywhere

## Local Development

### Prerequisites

- Go 1.21+

### Generate the site

```bash
cd recruitee
go run ./cmd/generate
```

This will:
1. Fetch current Data & AI vacancies from Recruitee
2. Generate `output/index.html` with all job listings
3. Generate `output/jobs/{slug}.html` for each job

### Preview locally

```bash
cd output
python3 -m http.server 8000
# or
npx serve
```

Then open http://localhost:8000

## Deployment

The `output/` directory contains a fully static site that can be deployed to:

- GitHub Pages
- Netlify
- Vercel
- AWS S3 + CloudFront
- Any static file host

## GitHub Action

The workflow runs daily at midnight UTC and:

1. Fetches latest vacancies from Recruitee
2. Regenerates the static site
3. Commits changes if vacancies changed
4. Uploads site as artifact

You can also trigger it manually from the Actions tab.

## Application Flow

When a user submits an application:

1. JavaScript collects form data (name, email, CV, etc.)
2. Sends `POST` to `https://xebiacareers.recruitee.com/api/offers/{slug}/candidates`
3. Recruitee processes the application and sends confirmation email
4. User sees success/error message on the page

No backend required - the browser talks directly to Recruitee's API.

## Customization

### Styling

Edit `static/style.css`. Key brand colors:

```css
--color-primary: #891f7a;      /* Xebia purple */
--color-navy: #150027;         /* Dark background */
```

### Templates

- `templates/index.html` - Job listings page
- `templates/job.html` - Individual job page with application form

### Filter criteria

Edit `internal/api/client.go`:

```go
const Department = "Data & AI"  // Change to filter different department
```
