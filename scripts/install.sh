#!/bin/sh
# Stage 0 bootstrap — downloads and verifies the signed mgr binary, then hands off.
# This script is the ONLY bash that runs before the signed binary takes over.
set -euo pipefail

REPO="sholtomaud/mgr"
INSTALL_DIR="/usr/local/bin"
BINARY="mgr"

# Minimum macOS 14 (Sonoma)
OS_VER=$(sw_vers -productVersion | cut -d. -f1)
if [ "$OS_VER" -lt 14 ]; then
    echo "Error: mgr requires macOS 14 (Sonoma) or later." >&2
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    arm64)  ASSET="mgr-arm64" ;;
    x86_64) ASSET="mgr-x86_64" ;;
    *)
        echo "Error: unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

# Xcode CLI tools
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode CLI tools..."
    xcode-select --install
    echo "Waiting for Xcode CLI tools to finish installing..."
    until xcode-select -p &>/dev/null; do sleep 5; done
    echo "Xcode CLI tools installed."
fi

# Download binary
LATEST_URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
TMP=$(mktemp)
echo "Downloading mgr from ${LATEST_URL}..."
curl -fsSL "$LATEST_URL" -o "$TMP"
chmod +x "$TMP"

# Verify code signature before executing anything
echo "Verifying code signature..."
if codesign --verify --deep --strict "$TMP" 2>/dev/null; then
    echo "  ✓ Signature valid"
else
    echo "  WARNING: binary is not signed or notarized." >&2
    echo "  This is expected for pre-Developer-ID releases." >&2
    echo "  After install, run: xattr -d com.apple.quarantine ${INSTALL_DIR}/${BINARY}" >&2
fi

# Install
echo "Installing to ${INSTALL_DIR}/${BINARY}..."
sudo mv "$TMP" "${INSTALL_DIR}/${BINARY}"

echo "mgr installed. Running bootstrap..."
"${INSTALL_DIR}/${BINARY}" bootstrap
