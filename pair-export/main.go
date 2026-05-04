package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

func main() {
	inputPath := flag.String("input", "", "Path to JSON file containing the pair issue database (array of objects) (required)")
	outputDir := flag.String("output", "out", "Directory to write markdown files into")
	notesField := flag.String("notes-field", "notes", "Field name whose value becomes the markdown body")
	filenameField := flag.String("filename-field", "", "Field used to derive the markdown filename (default: tries title, name, id, then index)")
	flag.Parse()

	if *inputPath == "" {
		fmt.Fprintln(os.Stderr, "Error: --input is required")
		flag.Usage()
		os.Exit(1)
	}

	data, err := os.ReadFile(*inputPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading input: %v\n", err)
		os.Exit(1)
	}

	var records []map[string]any
	if err := json.Unmarshal(data, &records); err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing JSON (expected an array of objects): %v\n", err)
		os.Exit(1)
	}

	if err := os.MkdirAll(*outputDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating output directory: %v\n", err)
		os.Exit(1)
	}

	usedNames := map[string]int{}
	for i, rec := range records {
		base := deriveFilename(rec, *filenameField, i)
		base = slugify(base)
		if base == "" {
			base = fmt.Sprintf("issue-%d", i+1)
		}
		// Disambiguate collisions
		name := base
		if n := usedNames[base]; n > 0 {
			name = fmt.Sprintf("%s-%d", base, n+1)
		}
		usedNames[base]++

		path := filepath.Join(*outputDir, name+".md")
		body, _ := rec[*notesField].(string)
		delete(rec, *notesField)

		md := buildMarkdown(rec, body)
		if err := os.WriteFile(path, []byte(md), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "Error writing %s: %v\n", path, err)
			os.Exit(1)
		}
		fmt.Printf("wrote %s\n", path)
	}
}

func deriveFilename(rec map[string]any, preferred string, index int) string {
	if preferred != "" {
		if v, ok := rec[preferred]; ok {
			return scalarString(v)
		}
	}
	for _, k := range []string{"title", "name", "id"} {
		if v, ok := rec[k]; ok {
			if s := scalarString(v); s != "" {
				return s
			}
		}
	}
	return fmt.Sprintf("issue-%d", index+1)
}

var slugRe = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = slugRe.ReplaceAllString(s, "-")
	return strings.Trim(s, "-")
}

func buildMarkdown(meta map[string]any, body string) string {
	var b strings.Builder
	b.WriteString("---\n")
	keys := make([]string, 0, len(meta))
	for k := range meta {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		writeYAML(&b, k, meta[k], 0)
	}
	b.WriteString("---\n")
	if body != "" {
		b.WriteString("\n")
		b.WriteString(body)
		if !strings.HasSuffix(body, "\n") {
			b.WriteString("\n")
		}
	}
	return b.String()
}

func writeYAML(b *strings.Builder, key string, val any, indent int) {
	pad := strings.Repeat("  ", indent)
	switch v := val.(type) {
	case nil:
		fmt.Fprintf(b, "%s%s: null\n", pad, key)
	case string:
		fmt.Fprintf(b, "%s%s: %s\n", pad, key, yamlString(v))
	case bool:
		fmt.Fprintf(b, "%s%s: %t\n", pad, key, v)
	case float64:
		fmt.Fprintf(b, "%s%s: %s\n", pad, key, formatNumber(v))
	case json.Number:
		fmt.Fprintf(b, "%s%s: %s\n", pad, key, v.String())
	case []any:
		if len(v) == 0 {
			fmt.Fprintf(b, "%s%s: []\n", pad, key)
			return
		}
		fmt.Fprintf(b, "%s%s:\n", pad, key)
		for _, item := range v {
			writeYAMLListItem(b, item, indent+1)
		}
	case map[string]any:
		if len(v) == 0 {
			fmt.Fprintf(b, "%s%s: {}\n", pad, key)
			return
		}
		fmt.Fprintf(b, "%s%s:\n", pad, key)
		keys := make([]string, 0, len(v))
		for k := range v {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			writeYAML(b, k, v[k], indent+1)
		}
	default:
		fmt.Fprintf(b, "%s%s: %s\n", pad, key, yamlString(fmt.Sprintf("%v", v)))
	}
}

func writeYAMLListItem(b *strings.Builder, val any, indent int) {
	pad := strings.Repeat("  ", indent)
	switch v := val.(type) {
	case nil:
		fmt.Fprintf(b, "%s- null\n", pad)
	case string:
		fmt.Fprintf(b, "%s- %s\n", pad, yamlString(v))
	case bool:
		fmt.Fprintf(b, "%s- %t\n", pad, v)
	case float64:
		fmt.Fprintf(b, "%s- %s\n", pad, formatNumber(v))
	case json.Number:
		fmt.Fprintf(b, "%s- %s\n", pad, v.String())
	case map[string]any:
		keys := make([]string, 0, len(v))
		for k := range v {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for i, k := range keys {
			if i == 0 {
				fmt.Fprintf(b, "%s- ", pad)
				inline(b, k, v[k], indent+1)
			} else {
				fmt.Fprintf(b, "%s  ", pad)
				inline(b, k, v[k], indent+1)
			}
		}
	case []any:
		fmt.Fprintf(b, "%s-\n", pad)
		for _, it := range v {
			writeYAMLListItem(b, it, indent+1)
		}
	default:
		fmt.Fprintf(b, "%s- %s\n", pad, yamlString(fmt.Sprintf("%v", v)))
	}
}

// inline writes a single key/value belonging to a map within a list item.
// The caller has already emitted the list dash or padding.
func inline(b *strings.Builder, key string, val any, indent int) {
	switch v := val.(type) {
	case map[string]any, []any:
		fmt.Fprintf(b, "%s:\n", key)
		writeYAML(b, key, v, indent)
	default:
		var sb strings.Builder
		writeYAML(&sb, key, val, 0)
		b.WriteString(sb.String())
	}
}

func formatNumber(f float64) string {
	if f == float64(int64(f)) {
		return strconv.FormatInt(int64(f), 10)
	}
	return strconv.FormatFloat(f, 'f', -1, 64)
}

// yamlString returns a YAML-safe representation of s. It uses a block scalar
// for multi-line strings and double-quotes for anything that needs escaping.
func yamlString(s string) string {
	if strings.ContainsRune(s, '\n') {
		var b strings.Builder
		b.WriteString("|-\n")
		for _, line := range strings.Split(strings.TrimRight(s, "\n"), "\n") {
			b.WriteString("  ")
			b.WriteString(line)
			b.WriteString("\n")
		}
		return strings.TrimRight(b.String(), "\n")
	}
	if needsQuoting(s) {
		return strconv.Quote(s)
	}
	return s
}

func needsQuoting(s string) bool {
	if s == "" {
		return true
	}
	switch strings.ToLower(s) {
	case "true", "false", "null", "yes", "no", "on", "off", "~":
		return true
	}
	if _, err := strconv.ParseFloat(s, 64); err == nil {
		return true
	}
	first := s[0]
	if strings.ContainsRune("!&*-?|>%@`{}[],#\"'", rune(first)) {
		return true
	}
	if strings.ContainsAny(s, ":#") {
		return true
	}
	if s != strings.TrimSpace(s) {
		return true
	}
	return false
}

func scalarString(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case float64:
		return formatNumber(x)
	case bool:
		return strconv.FormatBool(x)
	case json.Number:
		return x.String()
	case nil:
		return ""
	default:
		return fmt.Sprintf("%v", x)
	}
}
