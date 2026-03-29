#!/usr/bin/env bash
set -euo pipefail

REPO="${XRAYR_REPO:-kaydencevioletvz39-cmd/XrayR}"
VERSION_INPUT="${1:-${XRAYR_VERSION:-}}"

INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
SERVICE_FILE="/etc/systemd/system/XrayR.service"

need_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Error: please run as root."
    exit 1
  fi
}

install_deps() {
  local pkgs
  pkgs="curl wget unzip tar"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y $pkgs
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y $pkgs
    return
  fi
  if command -v yum >/dev/null 2>&1; then
    yum install -y $pkgs
    return
  fi
  echo "Warning: unsupported package manager, please ensure curl/wget and unzip are installed."
}

fetch() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
    return
  fi
  echo "Error: curl or wget is required."
  exit 1
}

fetch_text() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
    return
  fi
  echo "Error: curl or wget is required."
  exit 1
}

detect_asset_name() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "linux-64" ;;
    i386|i686) echo "linux-32" ;;
    aarch64|arm64) echo "linux-arm64-v8a" ;;
    armv7l|armv7) echo "linux-arm32-v7a" ;;
    armv6l|armv6) echo "linux-arm32-v6" ;;
    armv5l|armv5) echo "linux-arm32-v5" ;;
    mips) echo "linux-mips32" ;;
    mipsle) echo "linux-mips32le" ;;
    mips64) echo "linux-mips64" ;;
    mips64le) echo "linux-mips64le" ;;
    riscv64) echo "linux-riscv64" ;;
    s390x) echo "linux-s390x" ;;
    ppc64le) echo "linux-ppc64le" ;;
    *)
      echo "Error: unsupported architecture: $arch"
      exit 1
      ;;
  esac
}

resolve_version() {
  if [ -n "$VERSION_INPUT" ]; then
    if [[ "$VERSION_INPUT" == v* ]]; then
      echo "$VERSION_INPUT"
    else
      echo "v$VERSION_INPUT"
    fi
    return
  fi

  local api tag
  api="https://api.github.com/repos/${REPO}/releases/latest"
  tag="$(fetch_text "$api" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  if [ -z "$tag" ]; then
    echo "Error: failed to detect latest release tag from ${REPO}."
    exit 1
  fi
  echo "$tag"
}

install_files() {
  local workdir version asset zip_url tmpdir zip_file
  version="$(resolve_version)"
  asset="$(detect_asset_name)"

  echo "Repository: ${REPO}"
  echo "Version: ${version}"
  echo "Asset: XrayR-${asset}.zip"

  workdir="$(mktemp -d -t xrayr-install-XXXXXX)"
  zip_file="${workdir}/XrayR.zip"
  zip_url="https://github.com/${REPO}/releases/download/${version}/XrayR-${asset}.zip"

  fetch "$zip_url" "$zip_file"

  if ! command -v unzip >/dev/null 2>&1; then
    echo "Error: unzip is required."
    exit 1
  fi

  tmpdir="${workdir}/unpack"
  mkdir -p "$tmpdir"
  unzip -oq "$zip_file" -d "$tmpdir"

  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  cp -af "$tmpdir/." "$INSTALL_DIR/"
  chmod +x "$INSTALL_DIR/XrayR"

  mkdir -p "$CONFIG_DIR"
  cp -f "$INSTALL_DIR/geoip.dat" "$CONFIG_DIR/" || true
  cp -f "$INSTALL_DIR/geosite.dat" "$CONFIG_DIR/" || true

  if [ ! -f "$CONFIG_DIR/config.yml" ]; then
    cp -f "$INSTALL_DIR/config.yml" "$CONFIG_DIR/config.yml"
    echo "Config initialized at ${CONFIG_DIR}/config.yml"
  else
    echo "Config kept: ${CONFIG_DIR}/config.yml"
  fi

  [ -f "$CONFIG_DIR/dns.json" ] || cp -f "$INSTALL_DIR/dns.json" "$CONFIG_DIR/dns.json"
  [ -f "$CONFIG_DIR/route.json" ] || cp -f "$INSTALL_DIR/route.json" "$CONFIG_DIR/route.json"
  [ -f "$CONFIG_DIR/custom_outbound.json" ] || cp -f "$INSTALL_DIR/custom_outbound.json" "$CONFIG_DIR/custom_outbound.json"
  [ -f "$CONFIG_DIR/custom_inbound.json" ] || cp -f "$INSTALL_DIR/custom_inbound.json" "$CONFIG_DIR/custom_inbound.json"
  [ -f "$CONFIG_DIR/rulelist" ] || cp -f "$INSTALL_DIR/rulelist" "$CONFIG_DIR/rulelist"

  rm -rf "$workdir"
}

install_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: systemd is required (systemctl not found)."
    exit 1
  fi

  cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=XrayR Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/XrayR/XrayR -c /etc/XrayR/config.yml
Restart=on-failure
RestartSec=5s
LimitNOFILE=512000

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable XrayR >/dev/null 2>&1 || true
  systemctl restart XrayR
}

print_result() {
  echo
  echo "XrayR installed from ${REPO}."
  echo "Service: systemctl status XrayR"
  echo "Config:  ${CONFIG_DIR}/config.yml"
  echo "Log:     journalctl -u XrayR -f"
}

main() {
  need_root
  install_deps
  install_files
  install_service
  print_result
}

main "$@"
