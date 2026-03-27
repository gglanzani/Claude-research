#!/usr/bin/env bash
# import-to-hugo.sh
# Copies extracted LinkedIn posts and media into the Hugo site.
#
# Usage: ./import-to-hugo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUGO_DIR="$SCRIPT_DIR/site"
CONTENT_DIR="$HUGO_DIR/content/posts"
STATIC_MEDIA="$HUGO_DIR/static/media"

mkdir -p "$CONTENT_DIR"
mkdir -p "$STATIC_MEDIA"

# Copy markdown files
count=0
for md in "$SCRIPT_DIR"/*.md; do
  [ -f "$md" ] || continue
  basename=$(basename "$md")
  # Skip README
  [ "$basename" = "README.md" ] && continue
  cp "$md" "$CONTENT_DIR/$basename"
  count=$((count + 1))
done

echo "Copied $count posts to $CONTENT_DIR/"

# Copy media files
if [ -d "$SCRIPT_DIR/media" ]; then
  media_count=$(find "$SCRIPT_DIR/media" -type f | wc -l)
  cp -r "$SCRIPT_DIR/media/"* "$STATIC_MEDIA/" 2>/dev/null || true
  echo "Copied $media_count media files to $STATIC_MEDIA/"
fi

echo ""
echo "Done! To preview the site:"
echo "  cd $HUGO_DIR && hugo server -D"
