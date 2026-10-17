#!/usr/bin/env bash
# HyL Server OOBE Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/qualitydll/hyl/main/scripts/install.sh | bash
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[HyL]${NC} $*"; }
ok()      { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ── Require root ──────────────────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] || die "Please run as root: sudo bash install.sh"

# ── Detect OS ─────────────────────────────────────────────────────────────────
header "Detecting system"

OS_ID=""
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-}"
fi

case "$OS_ID" in
    ubuntu|debian)   PKG_MGR="apt-get"; UPDATE="apt-get update -qq"; INSTALL="apt-get install -y -qq" ;;
    centos|rhel|ol)  PKG_MGR="yum";     UPDATE="yum makecache -q";   INSTALL="yum install -y -q" ;;
    fedora)          PKG_MGR="dnf";     UPDATE="dnf makecache -q";   INSTALL="dnf install -y -q" ;;
    alpine)          PKG_MGR="apk";     UPDATE="apk update -q";      INSTALL="apk add -q" ;;
    *)               die "Unsupported OS: '$OS_ID'. Supported: Ubuntu, Debian, CentOS, RHEL, Fedora, Alpine" ;;
esac

ok "OS: $PRETTY_NAME"
info "Package manager: $PKG_MGR"

# ── Install dependencies ───────────────────────────────────────────────────────
header "Installing dependencies"

info "Updating package lists…"
$UPDATE

DEPS="curl openssl git"
info "Installing: $DEPS"
$INSTALL $DEPS
ok "Dependencies installed"

# ── Detect architecture ───────────────────────────────────────────────────────
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH_LABEL="amd64" ;;
    aarch64) ARCH_LABEL="arm64" ;;
    *)       die "Unsupported architecture: $ARCH. Supported: x86_64, aarch64" ;;
esac
ok "Architecture: $ARCH_LABEL"

# ── Install Go if needed ───────────────────────────────────────────────────────
install_go() {
    info "Installing Go 1.22…"
    local GO_VERSION="1.22.5"
    local GO_TAR="go${GO_VERSION}.linux-${ARCH_LABEL}.tar.gz"
    curl -fsSL "https://go.dev/dl/${GO_TAR}" -o "/tmp/${GO_TAR}"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "/tmp/${GO_TAR}"
    rm -f "/tmp/${GO_TAR}"
    export PATH="/usr/local/go/bin:$PATH"
    ok "Go $(go version | awk '{print $3}') installed"
}

# ── Fetch binary or build from source ─────────────────────────────────────────
header "Installing HyL server"

REPO="qualitydll/hyl"
INSTALL_PATH="/usr/local/bin/hyl-server"
BINARY_INSTALLED=false

# 1) Попробовать скачать готовый бинарь с Releases
info "Checking for pre-built releases…"
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || true)

if [[ -n "$LATEST_TAG" ]]; then
    BINARY_NAME="hyl-server-linux-${ARCH_LABEL}"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${BINARY_NAME}"
    TMP_BINARY="$(mktemp)"
    info "Downloading ${BINARY_NAME} (${LATEST_TAG})…"
    # Avoid curl -f: a missing asset must trigger the source-build fallback.
    # Check HTTP status explicitly so a 404 response body is never installed as a binary.
    HTTP_STATUS="$(curl -sSL -w '%{http_code}' "$DOWNLOAD_URL" -o "$TMP_BINARY" 2>/dev/null || true)"
    if [[ "$HTTP_STATUS" == "200" && -s "$TMP_BINARY" ]]; then
        install -m 0755 "$TMP_BINARY" "$INSTALL_PATH"
        ok "Binary downloaded: $LATEST_TAG"
        BINARY_INSTALLED=true
    else
        rm -f "$TMP_BINARY"
        warn "Pre-built binary unavailable (HTTP ${HTTP_STATUS:-unknown}); building from source."
    fi
else
    info "No published release found yet — building from source (this takes ~2 min)."
fi

# 2) Fallback: собрать из исходников
if [[ "$BINARY_INSTALLED" == false ]]; then
    header "Building from source"

    # Установить Go если нет
    if ! command -v go &>/dev/null || ! go version | grep -qE 'go1\.(2[2-9]|[3-9][0-9])'; then
        install_go
    else
        export PATH="/usr/local/go/bin:$PATH"
        ok "Go already available: $(go version | awk '{print $3}')"
    fi

    BUILD_DIR=$(mktemp -d)
    info "Cloning sources…"
    git clone --depth 1 "https://github.com/${REPO}.git" "$BUILD_DIR" -q
    info "Building hyl-server…"
    cd "$BUILD_DIR"
    # The repository may not yet contain go.sum. Resolve dependencies first so
    # Go can download modules and write the required checksums before building.
    info "Resolving Go modules and generating dependency checksums…"
    go mod tidy
    info "Building hyl-server…"
    go build -mod=mod -o "$INSTALL_PATH" ./cmd/hyl-server
    cd /
    rm -rf "$BUILD_DIR"
    chmod +x "$INSTALL_PATH"
    ok "Built and installed to $INSTALL_PATH"
fi

# ── Gather configuration ──────────────────────────────────────────────────────
header "Configuration"

# Port
read -rp "$(echo -e "${CYAN}[?]${NC} Server port [default: 443]: ")" USER_PORT </dev/tty
PORT="${USER_PORT:-443}"
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "Invalid port: $PORT (must be 1-65535)"
ok "Port: $PORT"

# Password
read -rsp "$(echo -e "${CYAN}[?]${NC} Auth password [leave blank for random]: ")" USER_PASS </dev/tty
echo
if [[ -z "$USER_PASS" ]]; then
    USER_PASS=$(openssl rand -hex 24)
    info "Generated password: ${BOLD}${USER_PASS}${NC}"
fi
ok "Password configured"

# Domain / IP
SERVER_IP=$(curl -fsSL --max-time 8 https://api.ipify.org 2>/dev/null || true)
if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
[[ -n "$SERVER_IP" ]] || die "Could not detect the server IP. Set up network connectivity and retry."
ok "Detected address: $SERVER_IP"

# ── Create directories ────────────────────────────────────────────────────────
header "Setting up files"

mkdir -p /etc/hyl
chmod 700 /etc/hyl

# ── Generate TLS certificate ──────────────────────────────────────────────────
CERT_PATH="/etc/hyl/server.crt"
KEY_PATH="/etc/hyl/server.key"

if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
    info "Generating self-signed TLS certificate…"
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH" \
        -days 3650 \
        -nodes \
        -subj "/CN=${SERVER_IP}" \
        -addext "subjectAltName=IP:${SERVER_IP}" \
        -quiet 2>/dev/null
    chmod 600 "$KEY_PATH"
    ok "TLS certificate generated (10-year validity)"
else
    ok "Using existing TLS certificate"
fi

# ── Write config ──────────────────────────────────────────────────────────────
CONFIG_PATH="/etc/hyl/server.yaml"
cat > "$CONFIG_PATH" <<EOF
# HyL Server Configuration
# Generated by install.sh on $(date -u +"%Y-%m-%d %H:%M UTC")

listen: "0.0.0.0:${PORT}"

auth:
  password: "${USER_PASS}"

tls:
  cert: "${CERT_PATH}"
  key: "${KEY_PATH}"

congestion:
  # mode: auto (adaptive), brutal (aggressive), economy (battery-friendly)
  mode: auto

bandwidth:
  up: 100    # Mbps hint
  down: 100

log:
  level: info
EOF

chmod 600 "$CONFIG_PATH"
ok "Config written to $CONFIG_PATH"

# ── Create systemd unit ───────────────────────────────────────────────────────
header "Configuring systemd service"

SYSTEMD_UNIT="/etc/systemd/system/hyl.service"
cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=HyL Server (Hysteria Lite)
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH} start --config ${CONFIG_PATH}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/etc/hyl /var/log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hyl --quiet
if systemctl restart hyl; then
    sleep 2
    if systemctl is-active --quiet hyl; then
        ok "systemd service is active"
    else
        warn "Service did not stay active. Recent logs:"
        journalctl -u hyl -n 30 --no-pager || true
        die "HyL service failed to start; configuration was installed but service is NOT running."
    fi
else
    journalctl -u hyl -n 30 --no-pager || true
    die "Could not start HyL service."
fi

# ── Allow firewall ────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow "${PORT}/udp" >/dev/null 2>&1 && ok "ufw: opened UDP port $PORT"
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-port="${PORT}/udp" >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
    ok "firewalld: opened UDP port $PORT"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
header "Installation complete!"

echo -e "${BOLD}Connection URI:${NC}"
echo -e "  ${GREEN}hyl://${USER_PASS}@${SERVER_IP}:${PORT}${NC}"
echo
echo -e "${BOLD}Useful commands:${NC}"
echo -e "  Status  : systemctl status hyl"
echo -e "  Logs    : journalctl -u hyl -f"
echo -e "  Restart : systemctl restart hyl"
echo -e "  Config  : ${CONFIG_PATH}"
echo
warn "Save the connection URI above — you'll need it for your client."
warn "This build currently contains server startup scaffolding, not a working QUIC/VPN data plane. A running service does not yet mean VPN traffic is supported."
