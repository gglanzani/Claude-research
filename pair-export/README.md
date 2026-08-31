# pair-export

Exports a [PaiR](https://github.com/w3dev33/pair-dist) issue database to one
Markdown file per issue. The `notes` field becomes the markdown body; every
other field is emitted as YAML frontmatter.

## Build

```bash
go build -o pair-export
```

## Usage

From a project that uses PaiR (so `.pair/issues.jsonl` exists):

```bash
# Make sure the JSONL is up to date with the SQLite DB
pair export

# Then export to markdown
go run . --output out
```

Or point at any JSONL/JSON file:

```bash
go run . --input path/to/issues.jsonl --output out
```

### Flags

- `--input` (default `.pair/issues.jsonl`): PaiR JSONL export, or a JSON array of issue objects.
- `--output` (default `out`): directory to write `.md` files into.
- `--notes-field` (default `notes`): field whose value becomes the markdown body.
- `--filename-field` (default: tries `id`, then `short_id`, then `title`): field used to derive the filename (slugified).

## Output

Given a PaiR issue:

```json
{"id":"pair-001","title":"Refactor auth flow","status":"open","type":"task",
 "priority":"p1","labels":["auth","refactor"],"blocked_by":[],
 "updated_at":"2026-04-30T10:11:12Z","description":"Split session middleware.",
 "notes":"Discussed with bob.\n\n- extract token parsing\n- add tests for expiry"}
```

Produces `out/pair-001.md`:

```markdown
---
blocked_by: []
description: Split session middleware.
id: pair-001
labels:
  - auth
  - refactor
priority: p1
status: open
title: Refactor auth flow
type: task
updated_at: "2026-04-30T10:11:12Z"
---

Discussed with bob.

- extract token parsing
- add tests for expiry
```
