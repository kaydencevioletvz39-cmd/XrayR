#!/usr/bin/env bash
set -euo pipefail

# One-click installer entrypoint for this repository.
# It delegates to the official XrayR-release installer by default.

UPSTREAM_INSTALL_URL="${XRAYR_INSTALL_URL:-https://raw.githubusercontent.com/XrayR-project/XrayR-release/master/install.sh}"
TMP_INSTALL_SCRIPT="$(mktemp -t xrayr-install-XXXXXX.sh)"

cleanup() {
  rm -f "$TMP_INSTALL_SCRIPT"
}
trap cleanup EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$UPSTREAM_INSTALL_URL" -o "$TMP_INSTALL_SCRIPT"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP_INSTALL_SCRIPT" "$UPSTREAM_INSTALL_URL"
else
  echo "Error: curl or wget is required."
  exit 1
fi

bash "$TMP_INSTALL_SCRIPT" "$@"
