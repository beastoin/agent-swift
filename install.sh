#!/bin/bash
# Install agent-swift — macOS only
set -euo pipefail

REPO="beastoin/agent-swift"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "Error: agent-swift only runs on macOS" >&2
  exit 1
fi

# Get latest version
echo "Fetching latest release..."
VERSION=$(curl -sI "https://github.com/${REPO}/releases/latest" | grep -i "^location:" | sed 's/.*tag\/v//' | tr -d '\r\n')
if [[ -z "$VERSION" ]]; then
  echo "Error: Could not determine latest version" >&2
  exit 1
fi

TARBALL="agent-swift-${VERSION}-macos-universal.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${TARBALL}"

# Download
echo "Downloading agent-swift v${VERSION}..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
curl -sL "$URL" -o "${TMPDIR}/${TARBALL}"

# Verify SHA256
echo "Verifying checksum..."
curl -sL "${URL}.sha256" -o "${TMPDIR}/expected.sha256"
EXPECTED=$(cat "${TMPDIR}/expected.sha256" | awk '{print $1}')
ACTUAL=$(shasum -a 256 "${TMPDIR}/${TARBALL}" | awk '{print $1}')
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  echo "Error: Checksum mismatch" >&2
  echo "  Expected: ${EXPECTED}" >&2
  echo "  Got:      ${ACTUAL}" >&2
  exit 1
fi

# Extract and install
echo "Installing to ${INSTALL_DIR}..."
tar -xzf "${TMPDIR}/${TARBALL}" -C "${TMPDIR}"
mkdir -p "${INSTALL_DIR}" 2>/dev/null || sudo mkdir -p "${INSTALL_DIR}"
if [[ -w "$INSTALL_DIR" ]]; then
  mv "${TMPDIR}/agent-swift" "${INSTALL_DIR}/agent-swift"
else
  sudo mv "${TMPDIR}/agent-swift" "${INSTALL_DIR}/agent-swift"
fi
chmod +x "${INSTALL_DIR}/agent-swift"

echo "agent-swift v${VERSION} installed to ${INSTALL_DIR}/agent-swift"
echo ""
echo "Usage:"
echo "  agent-swift doctor"
echo "  agent-swift connect --bundle-id com.apple.TextEdit"
echo "  agent-swift snapshot -i"
