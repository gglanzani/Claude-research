#!/usr/bin/env bash
set -euo pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR"
HUGO_POSTS="$SCRIPT_DIR/site/content/posts"
STATIC_MEDIA="$SCRIPT_DIR/site/static/media"

mkdir -p "$STATIC_MEDIA"

# Counters
downloaded=0
skipped=0
failed=0
updated=0

# Process each source post that has [Post image 2] or higher
for src_post in "$SRC_DIR"/*.md; do
  filename="$(basename "$src_post")"
  hugo_post="$HUGO_POSTS/$filename"

  # Skip if no Hugo post exists
  if [[ ! -f "$hugo_post" ]]; then
    continue
  fi

  # Extract all image lines with index >= 2
  # Format: ![Post image N](URL)
  while IFS= read -r line; do
    # Extract the image number and URL
    # Parse image number and URL using sed
    img_num=$(echo "$line" | sed -n 's/^!\[Post image \([0-9]*\)\].*/\1/p')
    url=$(echo "$line" | sed -n 's/^!\[Post image [0-9]*\](\(.*\))$/\1/p')

    if [[ -n "$img_num" && -n "$url" ]]; then

      # Skip image 1
      if [[ "$img_num" -lt 2 ]]; then
        continue
      fi

      # Create a unique filename based on post + image number
      base="${filename%.md}"
      img_file="${base}-image${img_num}"

      # Check if already downloaded (any extension)
      existing=$(ls "$STATIC_MEDIA/${img_file}".* 2>/dev/null | head -1 || true)
      if [[ -n "$existing" ]]; then
        skipped=$((skipped + 1))
        ext="${existing##*.}"
        local_path="/media/${img_file}.${ext}"

        # Still make sure the Hugo post references it
        if ! grep -q "$local_path" "$hugo_post" 2>/dev/null; then
          # Append image to Hugo post
          echo "" >> "$hugo_post"
          echo "![Post image ${img_num}](${local_path})" >> "$hugo_post"
          updated=$((updated + 1))
        fi
        continue
      fi

      # Download to a temp file, capture content-type
      tmp_file="$STATIC_MEDIA/${img_file}.tmp"
      http_code=$(curl -sL -o "$tmp_file" -w "%{http_code}" \
        -H "User-Agent: Mozilla/5.0" \
        --connect-timeout 10 --max-time 30 \
        "$url" 2>/dev/null || echo "000")

      if [[ "$http_code" != "200" ]]; then
        echo "FAIL ($http_code): $filename image $img_num"
        rm -f "$tmp_file"
        failed=$((failed + 1))
        continue
      fi

      # Detect file type using the `file` command on the downloaded content
      mime=$(file -b --mime-type "$tmp_file" 2>/dev/null || echo "unknown")

      case "$mime" in
        image/jpeg)       ext="jpg" ;;
        image/png)        ext="png" ;;
        image/gif)        ext="gif" ;;
        image/webp)       ext="webp" ;;
        image/svg+xml)    ext="svg" ;;
        image/bmp)        ext="bmp" ;;
        image/tiff)       ext="tiff" ;;
        *)
          # Fallback: try to guess from URL path
          url_path="${url%%\?*}"  # strip query params
          case "$url_path" in
            *.jpg|*.jpeg) ext="jpg" ;;
            *.png)        ext="png" ;;
            *.gif)        ext="gif" ;;
            *.webp)       ext="webp" ;;
            *)            ext="jpg" ;;  # default to jpg for LinkedIn images
          esac
          ;;
      esac

      final_file="$STATIC_MEDIA/${img_file}.${ext}"
      mv "$tmp_file" "$final_file"
      downloaded=$((downloaded + 1))

      local_path="/media/${img_file}.${ext}"

      # Add image reference to the Hugo post
      echo "" >> "$hugo_post"
      echo "![Post image ${img_num}](${local_path})" >> "$hugo_post"
      updated=$((updated + 1))

      echo "OK: $filename image $img_num -> ${img_file}.${ext}"
    fi
  done < <(grep '!\[Post image [2-9]' "$src_post" || true)
done

echo ""
echo "Done! Downloaded: $downloaded, Skipped (existing): $skipped, Failed: $failed, Posts updated: $updated"
