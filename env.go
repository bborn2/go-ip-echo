package main

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

// loadEnvFiles loads the .env file, resolving its location in priority order:
//  1. ENV_FILE, if set, is used verbatim (no fallback).
//  2. an .env next to the executable, so the service can start from any CWD.
//  3. an .env in the current working directory.
//
// The first path that exists is loaded; if none exist, that is not an error.
func loadEnvFiles() error {
	if p, ok := os.LookupEnv("ENV_FILE"); ok {
		return loadDotEnv(p)
	}

	var candidates []string
	if exe, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Join(filepath.Dir(exe), ".env"))
	}
	candidates = append(candidates, ".env")

	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return loadDotEnv(p)
		}
	}
	return nil
}

// loadDotEnv reads key=value pairs from the given file and sets them into the
// process environment. Existing environment variables take precedence, so real
// env always wins over the file. A missing file is not an error.
func loadDotEnv(path string) error {
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")

		key, val, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		if key == "" {
			continue
		}
		if _, exists := os.LookupEnv(key); exists {
			continue
		}
		os.Setenv(key, unquote(strings.TrimSpace(val)))
	}
	return sc.Err()
}

// unquote strips a single matching pair of surrounding quotes from v.
func unquote(v string) string {
	if len(v) >= 2 {
		if (v[0] == '"' && v[len(v)-1] == '"') || (v[0] == '\'' && v[len(v)-1] == '\'') {
			return v[1 : len(v)-1]
		}
	}
	return v
}
