# pair-export

Exports a pair issue database (JSON array of records) to one Markdown file per issue,
with YAML frontmatter for metadata and the `notes` field as the body.

## Build

```bash
go build -o pair-export
```

## Usage

```bash
go run . --input issues.json --output out
```

### Flags

- `--input` (required): path to JSON file containing an array of issue objects.
- `--output` (default `out`): directory to write `.md` files into.
- `--notes-field` (default `notes`): field name whose value becomes the markdown body.
- `--filename-field` (default: tries `title`, then `name`, then `id`): field used to derive the filename (slugified).

## Input format

An array of objects. Every key except the notes field is emitted as YAML frontmatter; the notes field becomes the body.

```json
[
  {
    "id": "PAIR-1",
    "title": "Refactor auth flow",
    "status": "Open",
    "tags": ["auth", "refactor"],
    "notes": "Discussed splitting the session middleware..."
  }
]
```

Produces `out/refactor-auth-flow.md`:

```markdown
---
id: PAIR-1
status: Open
tags:
  - auth
  - refactor
title: Refactor auth flow
---

Discussed splitting the session middleware...
```
