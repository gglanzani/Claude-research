#!/usr/bin/env python3
"""
Fetch real LinkedIn post URLs and dates from analytics pages.

For each markdown post in content/posts/, this script:
1. Reads the analytics URL from the front matter
2. Opens Chromium (you'll need to log into LinkedIn on first run)
3. Clicks the Export button to download an Excel file
4. Extracts the real post URL and date/time from the Excel
5. Updates the front matter with the correct url and date

Requirements:
    pip install playwright openpyxl
    playwright install chromium

Usage:
    # Process all posts that have analytics URLs
    python scripts/fetch_linkedin_post_data.py

    # Process a single post
    python scripts/fetch_linkedin_post_data.py content/posts/2025-02-08-gen-ai-is-many-things.md

    # Dry run (show what would change, don't write)
    python scripts/fetch_linkedin_post_data.py --dry-run

    # Limit to N posts (useful for testing)
    python scripts/fetch_linkedin_post_data.py --limit 5
"""

import argparse
import asyncio
import glob
import os
import re
import sys
import tempfile
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Front-matter helpers (TOML between +++ delimiters)
# ---------------------------------------------------------------------------

FRONT_MATTER_RE = re.compile(r"^\+\+\+\n(.*?)\n\+\+\+", re.DOTALL)


def parse_front_matter(text: str) -> tuple[dict, str, str]:
    """
    Minimal TOML-ish parser for the front matter we care about.
    Returns (params_dict, raw_front_matter, body).
    params_dict has keys: title, date, likes, views, url
    """
    m = FRONT_MATTER_RE.match(text)
    if not m:
        raise ValueError("No front matter found")
    raw_fm = m.group(1)
    body = text[m.end():]

    params = {}
    for key in ("title", "date", "url"):
        match = re.search(rf'^\s*{key}\s*=\s*"(.*?)"', raw_fm, re.MULTILINE)
        if match:
            params[key] = match.group(1)
    for key in ("likes", "views"):
        match = re.search(rf"^\s*{key}\s*=\s*(\d+)", raw_fm, re.MULTILINE)
        if match:
            params[key] = int(match.group(1))

    return params, raw_fm, body


def update_front_matter(
    text: str,
    new_url: str,
    new_date: str,
    analytics_url: str,
) -> str:
    """
    Update front matter:
    - url = the real public LinkedIn post URL
    - date = actual post date/time
    - linkedin_analytics_url = the analytics URL (was previously in 'url')
    """
    m = FRONT_MATTER_RE.match(text)
    if not m:
        return text
    raw_fm = m.group(1)
    body = text[m.end():]

    # Replace the url value with the real public URL
    raw_fm = re.sub(
        r'(^\s*url\s*=\s*)".*?"',
        rf'\1"{new_url}"',
        raw_fm,
        flags=re.MULTILINE,
    )

    # Replace the date value
    raw_fm = re.sub(
        r'(^\s*date\s*=\s*)".*?"',
        rf'\1"{new_date}"',
        raw_fm,
        flags=re.MULTILINE,
    )

    # Add or update linkedin_analytics_url in [params]
    if re.search(r'^\s*linkedin_analytics_url\s*=', raw_fm, re.MULTILINE):
        raw_fm = re.sub(
            r'(^\s*linkedin_analytics_url\s*=\s*)".*?"',
            rf'\1"{analytics_url}"',
            raw_fm,
            flags=re.MULTILINE,
        )
    else:
        # Insert after the url line in [params]
        raw_fm = re.sub(
            r'(^\s*url\s*=\s*".*?")',
            rf'\1\n  linkedin_analytics_url = "{analytics_url}"',
            raw_fm,
            flags=re.MULTILINE,
        )

    return f"+++\n{raw_fm}\n+++{body}"


# ---------------------------------------------------------------------------
# Excel parsing
# ---------------------------------------------------------------------------

def parse_linkedin_export(file_path: str) -> dict:
    """
    Parse the LinkedIn analytics Excel export.

    The file is laid out as key-value pairs in columns A and B:
        A1: "Post URL"          B1: "https://www.linkedin.com/feed/update/..."
        A2: "Post Date"         B2: "Dec 8, 2023"
        A3: "Post Publish Time" B3: "8:56 AM"
        (blank row)
        A5: "Post Performance"
        A6: "Impressions"       B6: "960"
        ...

    Returns a flat dict, e.g.:
        {"Post URL": "https://...", "Post Date": "Dec 8, 2023", ...}
    """
    import zipfile
    import xml.etree.ElementTree as ET

    ns = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}

    z = zipfile.ZipFile(file_path)
    # Read shared strings table
    ss = ET.parse(z.open("xl/sharedStrings.xml"))
    strings = []
    for si in ss.findall(".//s:si", ns):
        texts = [t.text or "" for t in si.findall(".//s:t", ns)]
        strings.append("".join(texts))

    # Read sheet1 — extract A/B column pairs
    sheet = ET.parse(z.open("xl/worksheets/sheet1.xml"))
    result = {}
    for row in sheet.findall(".//s:row", ns):
        cells = {}
        for c in row.findall("s:c", ns):
            ref = c.get("r", "")
            col = ref.rstrip("0123456789")  # e.g. "A" from "A1"
            t = c.get("t")
            v = c.find("s:v", ns)
            val = v.text if v is not None else None
            if t == "s" and val is not None:
                val = strings[int(val)]
            cells[col] = val

        key = cells.get("A")
        value = cells.get("B")
        if key and key.strip():
            result[key.strip()] = (value or "").strip()

    return result


def _parse_linkedin_datetime(date_str: str, time_str: str) -> str | None:
    """
    Parse LinkedIn export date/time strings into Hugo ISO format.

    Examples:
        date_str="Dec 8, 2023"  time_str="8:56 AM"  -> "2023-12-08T08:56:00"
        date_str="Jan 12, 2024" time_str="3:15 PM"   -> "2024-01-12T15:15:00"
    """
    from datetime import datetime

    if not date_str:
        return None

    # Combine date and time, or just date if no time
    combined = date_str.strip()
    if time_str and time_str.strip():
        combined += " " + time_str.strip()

    # Try common formats LinkedIn uses
    for fmt in [
        "%b %d, %Y %I:%M %p",   # "Dec 8, 2023 8:56 AM"
        "%b %d, %Y %I:%M%p",    # "Dec 8, 2023 8:56AM"
        "%B %d, %Y %I:%M %p",   # "December 8, 2023 8:56 AM"
        "%b %d, %Y",             # "Dec 8, 2023" (no time)
        "%B %d, %Y",             # "December 8, 2023" (no time)
        "%m/%d/%Y %I:%M %p",    # "12/08/2023 8:56 AM"
        "%m/%d/%Y",              # "12/08/2023"
        "%Y-%m-%d",              # "2023-12-08"
    ]:
        try:
            dt = datetime.strptime(combined, fmt)
            return dt.strftime("%Y-%m-%dT%H:%M:%S")
        except ValueError:
            continue

    return None


# ---------------------------------------------------------------------------
# Playwright automation
# ---------------------------------------------------------------------------

# Persistent Chromium profile directory for storing LinkedIn session.
# On first run, you'll need to log into LinkedIn manually in the browser window.
# Subsequent runs will reuse the session.
CHROMIUM_PROFILE_DIR = (
    Path.home() / ".linkedin-playwright-profile"
)


async def fetch_export_for_url(
    page, analytics_url: str, download_dir: str, debug: bool = False,
) -> str | None:
    """
    Navigate to a LinkedIn analytics URL and click Export.
    Returns path to downloaded Excel file, or None on failure.
    """
    try:
        await page.goto(analytics_url, wait_until="domcontentloaded", timeout=30000)
        # Wait for the export button to appear (LinkedIn's JS needs time to render)
        await page.wait_for_timeout(5000)

        if debug:
            # Save a screenshot and dump all buttons for debugging
            screenshot_path = os.path.join(download_dir, "debug_page.png")
            await page.screenshot(path=screenshot_path, full_page=True)
            print(f"  DEBUG: Screenshot saved to {screenshot_path}")

            buttons = await page.query_selector_all("button")
            print(f"  DEBUG: Found {len(buttons)} <button> elements:")
            for btn in buttons:
                text = await btn.text_content()
                aria = await btn.get_attribute("aria-label")
                cls = await btn.get_attribute("class")
                print(f"    text={text!r}  aria-label={aria!r}  class={cls!r}")

            # Also check for links/anchors that might look like buttons
            links = await page.query_selector_all("a")
            print(f"  DEBUG: Found {len(links)} <a> elements:")
            for link in links:
                text = (await link.text_content() or "").strip()
                href = await link.get_attribute("href")
                cls = await link.get_attribute("class")
                if "export" in (text + (cls or "") + (href or "")).lower():
                    print(f"    text={text!r}  href={href!r}  class={cls!r}")

        # LinkedIn wraps "Export" in a <span class="artdeco-button__text">
        # with lots of whitespace. Target the artdeco button with the
        # download icon or the span text directly.
        export_button = None
        selectors = [
            # Most specific: artdeco button containing a span with "Export"
            'button.artdeco-button span.artdeco-button__text:has-text("Export")',
            # The download icon data attribute
            'button:has([data-test-icon="download-small"])',
            # Artdeco button class with text match
            'button.artdeco-button:has-text("Export")',
            # Generic text match
            'button:has-text("Export")',
        ]

        for selector in selectors:
            try:
                el = await page.wait_for_selector(
                    selector, timeout=2000, state="visible"
                )
                if el:
                    # If we matched a <span>, click the parent <button>
                    tag = await el.evaluate("e => e.tagName.toLowerCase()")
                    if tag == "button":
                        export_button = el
                    else:
                        export_button = await el.evaluate_handle(
                            "e => e.closest('button')"
                        )
                    print(f"  Found export button with selector: {selector}")
                    break
            except Exception:
                continue

        if not export_button:
            print(f"  WARNING: Could not find Export button on {analytics_url}")
            # Always save a debug screenshot on failure
            fail_path = os.path.join(download_dir, "failed_page.png")
            await page.screenshot(path=fail_path, full_page=True)
            print(f"  Screenshot saved to {fail_path}")
            return None

        # Click and wait for the download
        async with page.expect_download(timeout=15000) as download_info:
            await export_button.click()

        download = await download_info.value
        file_path = os.path.join(download_dir, download.suggested_filename)
        await download.save_as(file_path)

        return file_path

    except Exception as e:
        print(f"  ERROR fetching {analytics_url}: {e}")
        # Save screenshot on error too
        try:
            err_path = os.path.join(download_dir, "error_page.png")
            await page.screenshot(path=err_path, full_page=True)
            print(f"  Screenshot saved to {err_path}")
        except Exception:
            pass
        return None


async def login_only():
    """Open Chromium so the user can log into LinkedIn. Session is saved to the profile."""
    from playwright.async_api import async_playwright

    CHROMIUM_PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Chromium profile: {CHROMIUM_PROFILE_DIR}")
    print("Opening Chromium — please log into LinkedIn.")
    print("Once logged in, close the browser window to save the session.\n")

    async with async_playwright() as p:
        browser = await p.chromium.launch_persistent_context(
            user_data_dir=str(CHROMIUM_PROFILE_DIR),
            headless=False,
            accept_downloads=True,
        )
        page = browser.pages[0] if browser.pages else await browser.new_page()
        await page.goto("https://www.linkedin.com/login")

        # Wait until the user closes the browser
        try:
            await page.wait_for_event("close", timeout=0)
        except Exception:
            pass
        try:
            await browser.close()
        except Exception:
            pass

    print("Session saved. You can now run the script without --login.")


async def process_posts(
    post_files: list[str],
    dry_run: bool = False,
    delay: float = 3.0,
    debug: bool = False,
):
    """Main processing loop: open browser, iterate posts, download & update."""
    from playwright.async_api import async_playwright

    download_dir = tempfile.mkdtemp(prefix="linkedin_export_")
    print(f"Download directory: {download_dir}")
    print(f"Chromium profile: {CHROMIUM_PROFILE_DIR}")

    # Create profile dir if it doesn't exist
    CHROMIUM_PROFILE_DIR.mkdir(parents=True, exist_ok=True)

    # Collect posts that need processing.
    # A post needs processing if:
    #   - Its url is an analytics URL (/analytics/post-summary/...)
    #   - Its url is a feed URL but it has no linkedin_analytics_url yet
    #     (meaning a previous run got the URL but not the date/analytics_url)
    posts_to_process = []
    for fpath in post_files:
        if fpath.endswith(".bak"):
            continue
        with open(fpath, "r") as f:
            text = f.read()
        try:
            params, raw_fm, body = parse_front_matter(text)
        except ValueError:
            continue

        url = params.get("url", "")
        has_analytics_url_field = "linkedin_analytics_url" in raw_fm

        if "/analytics/post-summary/" in url:
            # Analytics URL in url field — need to fetch everything
            posts_to_process.append((fpath, text, params, url))
        elif "/feed/update/" in url and not has_analytics_url_field:
            # Real URL from a previous run but missing analytics_url and real date.
            # Reconstruct the analytics URL from the activity URN.
            urn_match = re.search(r"urn:li:(?:activity|share):(\d+)", url)
            if urn_match:
                activity_id = urn_match.group(1)
                analytics = f"https://www.linkedin.com/analytics/post-summary/urn:li:activity:{activity_id}/"
                posts_to_process.append((fpath, text, params, analytics))
        # else: already fully processed (has linkedin_analytics_url), skip

    if not posts_to_process:
        print("No posts needing processing found. Nothing to do.")
        return

    print(f"\nFound {len(posts_to_process)} posts to process.\n")

    async with async_playwright() as p:
        # Launch Chromium with a persistent profile so the LinkedIn session
        # is preserved across runs.  On first run you'll need to log in
        # manually in the browser window that opens.
        browser = await p.chromium.launch_persistent_context(
            user_data_dir=str(CHROMIUM_PROFILE_DIR),
            headless=False,  # LinkedIn detects headless
            accept_downloads=True,
        )

        page = browser.pages[0] if browser.pages else await browser.new_page()

        processed = 0
        skipped = 0
        errors = 0

        for i, (fpath, text, params, analytics_url) in enumerate(posts_to_process):
            fname = os.path.basename(fpath)
            print(f"[{i+1}/{len(posts_to_process)}] {fname}")
            print(f"  Analytics URL: {analytics_url}")

            excel_path = await fetch_export_for_url(page, analytics_url, download_dir, debug=debug)
            if not excel_path:
                errors += 1
                continue

            try:
                data = parse_linkedin_export(excel_path)
            except Exception as e:
                print(f"  ERROR parsing Excel: {e}")
                errors += 1
                continue

            # Extract fields from the key-value Excel format:
            #   "Post URL"          -> real public URL
            #   "Post Date"         -> e.g. "Dec 8, 2023"
            #   "Post Publish Time" -> e.g. "8:56 AM"
            post_url = data.get("Post URL", "")
            post_date_str = data.get("Post Date", "")
            post_time_str = data.get("Post Publish Time", "")

            if not post_url:
                print(f"  WARNING: No 'Post URL' in Excel. Keys: {list(data.keys())}")
                print(f"  Data: {data}")
                errors += 1
                continue

            # Parse date + time into ISO format for Hugo
            new_date = _parse_linkedin_datetime(post_date_str, post_time_str)
            if not new_date:
                print(f"  WARNING: Could not parse date '{post_date_str}' / time '{post_time_str}'")
                new_date = params.get("date", "")

            print(f"  Post URL: {post_url}")
            print(f"  Date: {new_date}")
            print(f"  Analytics URL: {analytics_url}")

            new_text = update_front_matter(
                text,
                new_url=post_url,
                new_date=new_date,
                analytics_url=analytics_url,
            )

            if dry_run:
                # Show the updated front matter
                m = FRONT_MATTER_RE.match(new_text)
                if m:
                    print("  [DRY RUN] Updated front matter would be:")
                    for line in m.group(1).splitlines():
                        print(f"    {line}")
                processed += 1
            else:
                with open(fpath, "w") as f:
                    f.write(new_text)
                print("  Updated front matter.")
                processed += 1

            # Be nice to LinkedIn's servers
            if i < len(posts_to_process) - 1:
                print(f"  Waiting {delay}s...")
                await page.wait_for_timeout(int(delay * 1000))

        await browser.close()

    print(f"\nDone! Processed: {processed}, Skipped: {skipped}, Errors: {errors}")
    print(f"Excel files saved in: {download_dir}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Fetch real LinkedIn post URLs and dates from analytics pages."
    )
    parser.add_argument(
        "files",
        nargs="*",
        help="Specific markdown files to process. If omitted, processes all in content/posts/",
    )
    parser.add_argument(
        "--login",
        action="store_true",
        help="Just open Chromium to log into LinkedIn (saves session for future runs)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would change without writing files",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit processing to N posts (0 = all)",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=3.0,
        help="Seconds to wait between requests (default: 3)",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Save screenshots and dump button info for debugging selectors",
    )
    args = parser.parse_args()

    if args.login:
        asyncio.run(login_only())
        return

    # Resolve post files
    if args.files:
        post_files = args.files
    else:
        site_dir = Path(__file__).resolve().parent.parent
        post_files = sorted(glob.glob(str(site_dir / "content" / "posts" / "*.md")))

    if args.limit > 0:
        post_files = post_files[: args.limit]

    print(f"LinkedIn Analytics Export Fetcher")
    print(f"Posts to scan: {len(post_files)}")
    print(f"Dry run: {args.dry_run}")
    print()

    asyncio.run(process_posts(post_files, dry_run=args.dry_run, delay=args.delay, debug=args.debug))


if __name__ == "__main__":
    main()
