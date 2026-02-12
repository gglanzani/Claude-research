package main

import (
	"bytes"
	"io"
	"os"
)

// emptyJSONReader returns a reader for an empty JSON object {}.
// Required by LinkedIn's POST /memberAuthorizations endpoint.
func emptyJSONReader() io.Reader {
	return bytes.NewReader([]byte("{}"))
}

// fileExists checks if a path exists (used as an os-level helper).
func fileExistsOS(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
