#!/bin/bash
# Resolve lnkd.in short URLs to their destinations and replace in .md files
set -euo pipefail

MAPPING_FILE="lnkd-resolved.tsv"
FAILED_FILE="lnkd-failed.txt"

# Extract all unique lnkd.in URLs
echo "Extracting unique lnkd.in URLs..."
grep -ohEr 'https://lnkd\.in/[A-Za-z0-9_-]+' *.md | sort -u > /tmp/lnkd-urls.txt
total=$(wc -l < /tmp/lnkd-urls.txt)
echo "Found $total unique lnkd.in URLs"

> "$MAPPING_FILE"
> "$FAILED_FILE"

count=0
while IFS= read -r short_url; do
    count=$((count + 1))
    echo -n "[$count/$total] Resolving $short_url ... "

    # Fetch the interstitial page and extract the destination URL
    # The destination is the href that's not linkedin.com, licdn.com, or the help page
    dest=$(curl -sL -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' \
        --max-time 10 \
        "$short_url" 2>/dev/null \
        | grep -oE 'href="https?://[^"]*"' \
        | sed 's/href="//;s/"$//' \
        | grep -v 'licdn\.com' \
        | grep -v '^https://www\.linkedin\.com$' \
        | grep -v 'linkedin\.com/help/' \
        | head -1)

    if [ -n "$dest" ] && [ "$dest" != "$short_url" ]; then
        echo "$dest"
        printf '%s\t%s\n' "$short_url" "$dest" >> "$MAPPING_FILE"
    else
        echo "FAILED"
        echo "$short_url" >> "$FAILED_FILE"
    fi

    # Small delay to avoid rate-limiting
    sleep 0.3
done < /tmp/lnkd-urls.txt

echo ""
echo "Resolved $(wc -l < "$MAPPING_FILE") URLs"
failed_count=$(wc -l < "$FAILED_FILE")
if [ "$failed_count" -gt 0 ]; then
    echo "Failed to resolve $failed_count URLs (see $FAILED_FILE)"
fi

echo ""
echo "Mapping saved to $MAPPING_FILE"
