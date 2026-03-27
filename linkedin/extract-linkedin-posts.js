// LinkedIn Post Extractor
// Usage: Open your LinkedIn profile's "Posts" tab, scroll down to load all posts
// you want to extract, then paste this script into the browser console (F12 → Console).
//
// It will extract each post (text, images, videos, documents, date, reactions, comments)
// and download them as individual markdown files plus a media manifest.

(async function extractLinkedInPosts() {
  "use strict";

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  function sleep(ms) {
    return new Promise((r) => setTimeout(r, ms));
  }

  function slugify(text) {
    return text
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 60);
  }

  function downloadFile(filename, content) {
    const blob = new Blob([content], { type: "text/markdown;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  function downloadJSON(filename, obj) {
    const blob = new Blob([JSON.stringify(obj, null, 2)], {
      type: "application/json;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  // Try to parse LinkedIn's relative date strings into approximate ISO dates
  function parseLinkedInDate(text) {
    if (!text) return new Date().toISOString().slice(0, 10);
    text = text.trim().toLowerCase();

    const now = new Date();

    // Exact-ish patterns: "Jan 1, 2025", "1 Jan 2025", etc.
    const parsed = Date.parse(text);
    if (!isNaN(parsed)) return new Date(parsed).toISOString().slice(0, 10);

    // Relative: "2d", "3w", "1mo", "1yr", "5h", "30m"
    const rel = text.match(/(\d+)\s*(s|m|h|d|w|mo|yr)/);
    if (rel) {
      const n = parseInt(rel[1], 10);
      const unit = rel[2];
      const d = new Date(now);
      switch (unit) {
        case "s":
          d.setSeconds(d.getSeconds() - n);
          break;
        case "m":
          d.setMinutes(d.getMinutes() - n);
          break;
        case "h":
          d.setHours(d.getHours() - n);
          break;
        case "d":
          d.setDate(d.getDate() - n);
          break;
        case "w":
          d.setDate(d.getDate() - n * 7);
          break;
        case "mo":
          d.setMonth(d.getMonth() - n);
          break;
        case "yr":
          d.setFullYear(d.getFullYear() - n);
          break;
      }
      return d.toISOString().slice(0, 10);
    }

    return now.toISOString().slice(0, 10);
  }

  // ---------------------------------------------------------------------------
  // Expand truncated posts and comments
  // ---------------------------------------------------------------------------
  async function clickAllSeeMore() {
    const buttons = document.querySelectorAll(
      'button.see-more-less-button, button[aria-label*="see more"], button[aria-label*="See more"], .feed-shared-inline-show-more-text button'
    );
    for (const btn of buttons) {
      btn.click();
      await sleep(200);
    }
  }

  // Expand comment sections
  async function expandComments() {
    // Click "Load more comments" / "Show previous comments" buttons
    const loadMore = document.querySelectorAll(
      'button.comments-comments-list__load-more-comments-button, button[aria-label*="Load more comments"], button[aria-label*="previous comments"]'
    );
    for (const btn of loadMore) {
      btn.click();
      await sleep(500);
    }
  }

  // ---------------------------------------------------------------------------
  // Extract a single post
  // ---------------------------------------------------------------------------
  function extractPost(postEl) {
    const post = {
      text: "",
      date: "",
      images: [],
      videos: [],
      documents: [],
      links: [],
      likes: 0,
      views: 0,
      url: "",
      comments: [],
    };

    // -- Date --
    const timeEl = postEl.querySelector(
      "time, .feed-shared-actor__sub-description span, span.update-components-actor__sub-description"
    );
    const dateText = timeEl ? timeEl.innerText || timeEl.getAttribute("datetime") : "";
    post.date = parseLinkedInDate(dateText);

    // -- Post text --
    const textEl = postEl.querySelector(
      ".feed-shared-update-v2__description, .feed-shared-text, .update-components-text, .break-words"
    );
    if (textEl) {
      post.text = textEl.innerText.trim();
    }

    // -- Images --
    const imgEls = postEl.querySelectorAll(
      ".feed-shared-image__container img, .update-components-image img, .feed-shared-carousel img, img.ivm-view-attr__img--centered"
    );
    imgEls.forEach((img) => {
      const src = img.getAttribute("data-delayed-url") || img.src;
      if (src && !src.includes("data:image") && !post.images.includes(src)) {
        post.images.push(src);
      }
    });

    // -- Videos --
    const videoEls = postEl.querySelectorAll(
      "video source, video[src], .feed-shared-linkedin-video video"
    );
    videoEls.forEach((v) => {
      const src = v.src || v.getAttribute("src");
      if (src && !post.videos.includes(src)) {
        post.videos.push(src);
      }
    });

    // -- Documents / articles --
    const docLinks = postEl.querySelectorAll(
      '.feed-shared-article a, .update-components-article a, a[data-control-name="article"]'
    );
    docLinks.forEach((a) => {
      const href = a.href;
      if (href && !post.documents.includes(href)) {
        post.documents.push(href);
      }
    });

    // -- External links --
    const extLinks = postEl.querySelectorAll(
      ".feed-shared-article__link, .update-components-article__link-container a"
    );
    extLinks.forEach((a) => {
      const href = a.href;
      if (href && !post.links.includes(href)) {
        post.links.push(href);
      }
    });

    // -- Likes count --
    const reactionsEl = postEl.querySelector(
      ".social-details-social-counts__reactions-count, .social-details-social-counts span:first-child"
    );
    if (reactionsEl) {
      const likesText = reactionsEl.innerText.trim().replace(/,/g, "");
      post.likes = parseInt(likesText, 10) || 0;
    }

    // -- Views count --
    const viewsEl = postEl.querySelector(
      ".analytics-entry-point span, .feed-shared-analytics-entry-point span, span[class*='impressions'], .social-details-social-counts__impressions-count"
    );
    if (viewsEl) {
      const viewsText = viewsEl.innerText.trim().replace(/,/g, "");
      post.views = parseInt(viewsText, 10) || 0;
    }

    // -- Original post URL --
    const linkEl = postEl.querySelector(
      'a[href*="/feed/update/"], a[data-tracking-control-name="feed_post_share_link"], a[href*="urn:li:activity"]'
    );
    if (linkEl) {
      const href = linkEl.href;
      post.url = href.split("?")[0];
    } else {
      const urn = postEl.getAttribute("data-urn") || postEl.getAttribute("data-id") || "";
      if (urn) {
        const activityId = urn.match(/urn:li:activity:(\d+)/);
        if (activityId) {
          post.url = `https://www.linkedin.com/feed/update/urn:li:activity:${activityId[1]}`;
        }
      }
    }

    // -- Comments --
    const commentEls = postEl.querySelectorAll(
      ".comments-comment-item, .comments-comment-entity, article.comments-comment-item"
    );
    commentEls.forEach((c) => {
      const authorEl = c.querySelector(
        ".comments-post-meta__name-text, .comments-comment-item__post-meta span, a.comments-post-meta__actor-link"
      );
      const bodyEl = c.querySelector(
        ".comments-comment-item__main-content, .comments-comment-texteditor .update-components-text, .feed-shared-main-content"
      );
      const comment = {
        author: authorEl ? authorEl.innerText.trim().split("\n")[0] : "Unknown",
        text: bodyEl ? bodyEl.innerText.trim() : "",
      };
      if (comment.text) {
        post.comments.push(comment);
      }
    });

    return post;
  }

  // ---------------------------------------------------------------------------
  // Convert post to Hugo markdown
  // ---------------------------------------------------------------------------
  function postToMarkdown(post, index) {
    const slug = slugify(post.text.slice(0, 80)) || `linkedin-post-${index}`;
    const title = post.text.split("\n")[0].slice(0, 120).replace(/"/g, '\\"');

    let md = `+++
title = "${title}"
date = "${post.date}T12:00:00"
draft = false
[params]
  source = "linkedin"
  likes = ${post.likes}
  views = ${post.views}
  url = "${post.url}"
+++

${post.text}
`;

    // Images
    if (post.images.length > 0) {
      md += "\n\n";
      post.images.forEach((img, i) => {
        md += `![Post image ${i + 1}](${img})\n\n`;
      });
    }

    // Videos
    if (post.videos.length > 0) {
      md += "\n\n## Video\n\n";
      post.videos.forEach((vid) => {
        md += `<video src="${vid}" controls></video>\n\n`;
      });
    }

    // Documents / shared articles
    if (post.documents.length > 0) {
      md += "\n\n## Shared Links\n\n";
      post.documents.forEach((doc) => {
        md += `- [${doc}](${doc})\n`;
      });
    }

    if (post.links.length > 0) {
      md += "\n\n## External Links\n\n";
      post.links.forEach((link) => {
        md += `- [${link}](${link})\n`;
      });
    }

    // Comments
    if (post.comments.length > 0) {
      md += "\n\n---\n\n## Comments\n\n";
      post.comments.forEach((c) => {
        md += `> **${c.author}**: ${c.text}\n\n`;
      });
    }

    return { slug, md, date: post.date };
  }

  // ---------------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------------
  console.log("🔍 Expanding truncated posts and comments...");
  await clickAllSeeMore();
  await sleep(500);
  await expandComments();
  await sleep(500);
  await clickAllSeeMore(); // catch any newly revealed "see more" buttons

  const postElements = document.querySelectorAll(
    '.feed-shared-update-v2, .occludable-update, div[data-urn*="activity"], div[data-id*="urn:li:activity"]'
  );

  if (postElements.length === 0) {
    console.error(
      "No posts found. Make sure you are on a LinkedIn page showing posts (e.g. your profile Activity / Posts tab) and that posts are loaded."
    );
    return;
  }

  console.log(`📝 Found ${postElements.length} posts. Extracting...`);

  const allMedia = [];
  const allPosts = [];

  postElements.forEach((el, i) => {
    const post = extractPost(el);
    // Skip empty posts (shares with no text, etc.)
    if (!post.text && post.images.length === 0 && post.videos.length === 0) return;

    const { slug, md, date } = postToMarkdown(post, i);
    const filename = `${date}-${slug}.md`;

    allPosts.push({ filename, md });

    // Collect media for manifest
    post.images.forEach((url) => allMedia.push({ type: "image", url, post: filename }));
    post.videos.forEach((url) => allMedia.push({ type: "video", url, post: filename }));
  });

  if (allPosts.length === 0) {
    console.error("No posts with content found.");
    return;
  }

  // Download each post as a .md file
  console.log(`⬇️ Downloading ${allPosts.length} markdown files...`);
  for (let i = 0; i < allPosts.length; i++) {
    downloadFile(allPosts[i].filename, allPosts[i].md);
    // Small delay to avoid browser blocking multiple downloads
    await sleep(300);
  }

  // Download media manifest
  if (allMedia.length > 0) {
    downloadJSON("media-manifest.json", allMedia);
    console.log(
      `📎 Downloaded media manifest with ${allMedia.length} media items.`
    );
  }

  console.log(
    `✅ Done! ${allPosts.length} posts extracted. Place the .md files in your Hugo site's content/posts/ directory.`
  );
})();
