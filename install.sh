#!/usr/bin/env bash
#
# One-line installer for go-ip-echo.
#
#   curl -fsSL https://raw.githubusercontent.com/bborn2/go-ip-echo/main/install.sh | sudo bash
#
# Downloads the latest release binary, installs a systemd unit that restarts on
# crash, seeds a config file, and starts the service.
#
# Override defaults via env vars, e.g.:
#   curl ... | sudo PORT=9000 TOKEN=secret TRUST_PROXY=1 bash
#
# Uninstall (pass args through the pipe with 'bash -s --'):
#   curl ... | sudo bash -s -- --uninstall          # keep /opt/ip-echo/.env
#   curl ... | sudo bash -s -- --uninstall --purge  # also remove dir and user
#
set -euo pipefail

REPO="bborn2/go-ip-echo"
ASSET="ip-echo-linux-amd64"
VERSION="${VERSION:-latest}"

INSTALL_DIR="${INSTALL_DIR:-/opt/ip-echo}"
BIN_PATH="${INSTALL_DIR}/ip-echo"
ENV_PATH="${INSTALL_DIR}/.env"
UNIT_PATH="/etc/systemd/system/ip-echo.service"
SVC_USER="${SVC_USER:-ip-echo}"

PORT="${PORT:-}"
TOKEN="${TOKEN:-}"
TRUST_PROXY="${TRUST_PROXY:-}"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# prompt reads a value from the terminal, even when the script is piped from
# curl (stdin is the script, so we read from /dev/tty). Falls back to the
# default when no terminal is attached (non-interactive install).
prompt() {
  local msg="$1" def="$2" ans=""
  if [ -r /dev/tty ] && { printf '%s [%s]: ' "$msg" "$def" >/dev/tty; } 2>/dev/null; then
    { read -r ans </dev/tty; } 2>/dev/null || ans=""
  fi
  printf '%s' "${ans:-$def}"
}

# gen_token produces a URL-safe random token using whatever is available.
gen_token() {
  if command -v openssl >/dev/null; then
    openssl rand -hex 24
  elif [ -r /dev/urandom ]; then
    tr -dc 'a-f0-9' < /dev/urandom | head -c 48
  else
    err "no random source available to generate a token"
  fi
}

# uninstall stops and removes the service. With --purge it also deletes the
# install dir (including .env) and the service user.
uninstall() {
  local purge="$1"
  log "Stopping and disabling service"
  systemctl disable --now ip-echo 2>/dev/null || true
  if [ -f "$UNIT_PATH" ]; then
    rm -f "$UNIT_PATH"
    systemctl daemon-reload
  fi
  if [ "$purge" -eq 1 ]; then
    log "Purging ${INSTALL_DIR} and user '${SVC_USER}'"
    rm -rf "$INSTALL_DIR"
    userdel "$SVC_USER" 2>/dev/null || true
  else
    log "Kept ${INSTALL_DIR} (config preserved). Use --purge to remove it."
  fi
  log "Uninstalled."
  exit 0
}

# Parse args. Uninstall is handled before any download work.
DO_UNINSTALL=0
PURGE=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) DO_UNINSTALL=1 ;;
    --purge)     PURGE=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//; 1d'
      exit 0 ;;
    *) err "unknown argument: $arg" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || err "please run as root (e.g. pipe into 'sudo bash')"
command -v systemctl >/dev/null || err "systemd is required"

if [ "$DO_UNINSTALL" -eq 1 ]; then
  uninstall "$PURGE"
fi

command -v curl >/dev/null || err "curl is required"

# Resolve config. Values already set via env are respected as-is; otherwise ask
# (interactive) or fall back to a default. TOKEN is auto-generated when unset.
GENERATED_TOKEN=0
if [ -z "$PORT" ]; then
  PORT="$(prompt 'Port to listen on' '8080')"
fi
if [ -z "$TOKEN" ]; then
  TOKEN="$(gen_token)"
  GENERATED_TOKEN=1
fi
TRUST_PROXY="${TRUST_PROXY:-0}"

# Resolve the download URL.
if [ "$VERSION" = "latest" ]; then
  DL_URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
else
  DL_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
fi

log "Creating service user '${SVC_USER}'"
if ! id "$SVC_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SVC_USER"
fi

log "Installing binary to ${BIN_PATH}"
mkdir -p "$INSTALL_DIR"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fSL "$DL_URL" -o "$tmp" || err "download failed: $DL_URL"
install -m 0755 "$tmp" "$BIN_PATH"

# Seed config only on first install so upgrades never clobber a real .env.
if [ ! -f "$ENV_PATH" ]; then
  log "Writing config to ${ENV_PATH}"
  umask 077
  {
    echo "PORT=${PORT}"
    echo "TOKEN=${TOKEN}"
    echo "TRUST_PROXY=${TRUST_PROXY}"
  } > "$ENV_PATH"
else
  log "Keeping existing config ${ENV_PATH}"
fi

chown -R "${SVC_USER}:${SVC_USER}" "$INSTALL_DIR"
chmod 600 "$ENV_PATH"

log "Installing systemd unit ${UNIT_PATH}"
cat > "$UNIT_PATH" <<EOF
[Unit]
Description=go-ip-echo service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=10
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_PATH}
Restart=always
RestartSec=3
User=${SVC_USER}
Group=${SVC_USER}
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

log "Enabling and starting service"
systemctl daemon-reload
systemctl enable --now ip-echo

log "Done. Service status:"
systemctl --no-pager --full status ip-echo || true

cat <<EOF

go-ip-echo is installed and running.

  Port:    ${PORT}
  Config:  ${ENV_PATH}   (edit, then: systemctl restart ip-echo)
  Logs:    journalctl -u ip-echo -f
EOF

if [ "$GENERATED_TOKEN" -eq 1 ]; then
  cat <<EOF

  A token was generated for you. Save it — it is stored in ${ENV_PATH}:

      TOKEN=${TOKEN}

  Test:
      curl -H "Authorization: Bearer ${TOKEN}" http://127.0.0.1:${PORT}/
EOF
else
  cat <<EOF
  Test:    curl -H "Authorization: Bearer \$TOKEN" http://127.0.0.1:${PORT}/
EOF
fi
echo
