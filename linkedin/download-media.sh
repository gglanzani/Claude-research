#!/usr/bin/env bash
# download-media.sh
# Downloads media files referenced in media-manifest.json and updates
# the markdown files to use local paths.
#
# Usage:
#   1. Place the extracted .md files and media-manifest.json in this directory
#   2. Run: ./download-media.sh
#   3. Then run: ./import-to-hugo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/media-manifest.json"

if [ ! -f "$MANIFEST" ]; then
  echo "No media-manifest.json found. Skipping media download."
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it with: apt install jq / brew install jq"
  exit 1
fi

MEDIA_DIR="$SCRIPT_DIR/media"
mkdir -p "$MEDIA_DIR"

count=$(jq length "$MANIFEST")
echo "Downloading $count media files..."

for i in $(seq 0 $((count - 1))); do
  url=$(jq -r ".[$i].url" "$MANIFEST")
  post=$(jq -r ".[$i].post" "$MANIFEST")
  type=$(jq -r ".[$i].type" "$MANIFEST")

  # Derive a filename from the URL
  basename=$(echo "$url" | sed 's/[?#].*//' | sed 's|.*/||')
  if [ -z "$basename" ] || [ "$basename" = "/" ]; then
    ext="jpg"
    [ "$type" = "video" ] && ext="mp4"
    basename="${post%.md}-${i}.${ext}"
  fi

  dest="$MEDIA_DIR/$basename"

  if [ -f "$dest" ]; then
    echo "  [$((i + 1))/$count] Already downloaded: $basename"
  else
    echo "  [$((i + 1))/$count] Downloading: $basename"
    curl -sL -o "$dest" "$url" || echo "    WARNING: Failed to download $url"
  fi

  # Update the markdown file to reference local media
  mdfile="$SCRIPT_DIR/$post"
  if [ -f "$mdfile" ]; then
    # Escape special characters in URL for sed
    escaped_url=$(printf '%s\n' "$url" | sed 's/[&/\]/\\&/g')
    escaped_dest=$(printf '%s\n' "/media/$basename" | sed 's/[&/\]/\\&/g')
    sed -i "s|${escaped_url}|${escaped_dest}|g" "$mdfile" 2>/dev/null || true
  fi
done

echo "Done. Media files saved to $MEDIA_DIR/"
