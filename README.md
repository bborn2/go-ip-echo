# go-ip-echo

A tiny HTTP service that echoes back the caller's IP address. Zero external
dependencies. Optional token auth, optional reverse-proxy awareness, and `.env`
based configuration.

## Run

```bash
go run .
```

Or build a binary:

```bash
go build -o ip-echo .
./ip-echo
```

## Configuration

Configured entirely through environment variables. A real environment variable
always wins over a value from the `.env` file.

| Variable      | Default | Description                                                                 |
| ------------- | ------- | --------------------------------------------------------------------------- |
| `PORT`        | `8080`  | Port to listen on.                                                          |
| `TOKEN`       | (unset) | If set, requests must authenticate. If empty, the service is open.          |
| `TRUST_PROXY` | (unset) | If truthy (`1`/`true`/`yes`/`on`), honor `X-Forwarded-For` / `X-Real-IP`.   |
| `ENV_FILE`    | (unset) | Explicit path to the `.env` file. Overrides the default lookup below.       |

### `.env` resolution order

1. `ENV_FILE`, if set, is used verbatim (no fallback).
2. An `.env` next to the executable — so the service starts correctly from any
   working directory.
3. An `.env` in the current working directory.

The first file that exists is loaded. If none exist, that is not an error.

Copy the template to get started:

```bash
cp .env.example .env
```

## Usage

### No token (open service)

```bash
curl http://127.0.0.1:8080/
```

### With a token — Bearer header (recommended)

```bash
curl -H "Authorization: Bearer secret" http://127.0.0.1:8080/
```

### With a token — query parameter

```bash
curl "http://127.0.0.1:8080/?token=secret"
```

### Read the token from a variable instead of hardcoding it

```bash
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/
```

### Debugging auth

```bash
# Just the status code: 401 when a token is required but missing
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/

# Full response headers, including WWW-Authenticate
curl -i http://127.0.0.1:8080/
```

## Behind a reverse proxy

By default the service reports the direct peer address (`RemoteAddr`), because
`X-Forwarded-For` and `X-Real-IP` can be forged by a client connecting directly.
When running behind a trusted proxy such as nginx, set `TRUST_PROXY=1` so the
real client IP is reported. `X-Forwarded-For` takes precedence (first value),
then `X-Real-IP`.

See [nginx.conf.example](nginx.conf.example) for a sample configuration.

```bash
# Simulate a proxied request (server needs TRUST_PROXY=1 to honor the header)
curl -H "Authorization: Bearer secret" \
     -H "X-Forwarded-For: 203.0.113.9" \
     http://127.0.0.1:8080/
```

## Security notes

- Trust proxy headers only when the service actually sits behind a proxy you
  control. Exposed directly to the internet, `X-Forwarded-For` is client-supplied
  and unreliable — leave `TRUST_PROXY` unset so `RemoteAddr` is used.
- Keep real tokens out of shell history and out of the repo. `.env` is
  gitignored; prefer the Bearer header over the `?token=` query parameter, since
  URLs are more likely to be logged.
