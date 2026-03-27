# LinkedIn to Hugo Blog

Extract your LinkedIn posts and display them as a Hugo blog using the [hugola](https://github.com/gglanzani/hugola) theme.

## Quick Start

### 1. Extract posts from LinkedIn

1. Open LinkedIn in your browser and navigate to your profile's **Activity → Posts** tab
2. Scroll down to load all the posts you want to extract
3. Open the browser console (F12 → Console)
4. Copy and paste the contents of `extract-linkedin-posts.js` into the console and press Enter
5. The script will download one `.md` file per post, plus a `media-manifest.json`

### 2. Download media (optional)

Move the downloaded `.md` files and `media-manifest.json` into this `linkedin/` directory, then run:

```bash
./download-media.sh
```

This downloads all images and videos referenced in the posts and updates the markdown files to use local paths. Requires `curl` and `jq`.

### 3. Import into Hugo

```bash
./import-to-hugo.sh
```

This copies the markdown files into `site/content/posts/` and media into `site/static/media/`.

### 4. Preview the blog

```bash
cd site
hugo server -D
```

Open http://localhost:1313 in your browser.

### 5. Build for production

```bash
cd site
hugo
```

The static site will be in `site/public/`.

## Configuration

Edit `site/hugo.toml` to customize:

- `title` — site title
- `baseURL` — your deployment URL
- `author` — author name
- `[params] Name` — name shown in navigation
- `[params] Domain` — link for the site name
- `[params.Sidebar]` — navigation links

## Structure

```
linkedin/
├── extract-linkedin-posts.js   # Browser script to extract posts
├── download-media.sh           # Downloads media from manifest
├── import-to-hugo.sh           # Copies posts into Hugo site
├── README.md
└── site/                       # Hugo site
    ├── hugo.toml
    ├── content/posts/          # Posts go here
    ├── static/media/           # Media files go here
    ├── assets/og_base.png      # Open Graph base image
    └── themes/hugola/          # Theme (git submodule)
```
