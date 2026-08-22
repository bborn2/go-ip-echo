package main

import (
	"log"
	"net"
	"net/http"
	"os"
	"strings"
)

func main() {
	if err := loadDotEnv(getenv("ENV_FILE", ".env")); err != nil {
		log.Fatalf("loading env file: %v", err)
	}

	port := getenv("PORT", "8080")
	token := os.Getenv("TOKEN")
	trustProxy := truthy(os.Getenv("TRUST_PROXY"))

	mux := http.NewServeMux()
	mux.HandleFunc("/", handler(token, trustProxy))

	addr := ":" + port
	log.Printf("ip-echo listening on %s (auth=%t, trust_proxy=%t)", addr, token != "", trustProxy)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

func handler(token string, trustProxy bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if token != "" && !authorized(r, token) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		ip := clientIP(r, trustProxy)
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write([]byte(ip + "\n"))
	}
}

// authorized checks the request against the configured token. It accepts either
// an "Authorization: Bearer <token>" header or a "token" query parameter.
func authorized(r *http.Request, token string) bool {
	auth := r.Header.Get("Authorization")
	if after, ok := strings.CutPrefix(auth, "Bearer "); ok {
		if after == token {
			return true
		}
	}
	return r.URL.Query().Get("token") == token
}

// clientIP returns the caller's IP. Proxy headers (X-Forwarded-For, X-Real-IP)
// are honored only when trustProxy is set, since a client can forge them when
// the service is exposed directly. Behind a reverse proxy such as nginx, enable
// TRUST_PROXY so the real client IP is reported instead of the proxy's.
func clientIP(r *http.Request, trustProxy bool) string {
	if trustProxy {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			if first, _, _ := strings.Cut(xff, ","); strings.TrimSpace(first) != "" {
				return strings.TrimSpace(first)
			}
		}
		if xrip := r.Header.Get("X-Real-IP"); xrip != "" {
			return strings.TrimSpace(xrip)
		}
	}
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}

// truthy reports whether an env value represents an enabled boolean flag.
func truthy(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
