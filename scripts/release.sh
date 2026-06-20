#!/bin/sh
# Local sign-notarize-release script for mgr.
# Run from the repo root: scripts/release.sh v0.1.0
#
# Prerequisites:
#   - Developer ID Application certificate in Keychain
#   - Apple ID app-specific password: `xcrun notarytool store-credentials mgr-notary`
#   - GitHub CLI authenticated: `gh auth login`
#   - Xcode CLI tools installed
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version-tag>   e.g. $0 v0.1.0" >&2
    exit 1
fi

# Strip leading 'v' for the Package.swift version check
VERSION_NUM="${VERSION#v}"

echo "==> Building mgr $VERSION"

# Detect signing identity automatically
SIGNING_IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" \
    | head -1 \
    | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$SIGNING_IDENTITY" ]; then
    echo ""
    echo "ERROR: No 'Developer ID Application' certificate found in Keychain." >&2
    echo "" >&2
    echo "To get one:" >&2
    echo "  1. Enrol in Apple Developer Program (developer.apple.com, \$99/yr)" >&2
    echo "  2. Certificates → Create → Developer ID Application" >&2
    echo "  3. Download and double-click to install into Keychain" >&2
    echo "" >&2
    echo "Then re-run this script." >&2
    exit 1
fi
echo "==> Signing identity: $SIGNING_IDENTITY"

# Clean build
rm -f mgr-arm64 mgr-x86_64 mgr mgr.zip

echo "==> Building arm64..."
swift build -c release --arch arm64
cp .build/arm64-apple-macosx/release/mgr mgr-arm64

echo "==> Building x86_64..."
swift build -c release --arch x86_64
cp .build/x86_64-apple-macosx/release/mgr mgr-x86_64

echo "==> Creating universal binary..."
lipo -create -output mgr mgr-arm64 mgr-x86_64

echo "==> Signing..."
codesign --force --deep --strict \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    mgr
codesign --verify --deep --strict --verbose mgr
echo "  ✓ Signature valid"

echo "==> Notarizing..."
zip mgr.zip mgr

# Uses stored credentials — run once to set up:
#   xcrun notarytool store-credentials mgr-notary \
#       --apple-id <your@email.com> \
#       --team-id <TEAMID> \
#       --password <app-specific-password>
xcrun notarytool submit mgr.zip \
    --keychain-profile "mgr-notary" \
    --wait

echo "==> Stapling..."
xcrun stapler staple mgr
spctl --assess --type exec mgr
echo "  ✓ Gatekeeper passes"

echo "==> Creating GitHub release $VERSION..."
gh release create "$VERSION" \
    --title "mgr $VERSION" \
    --generate-notes \
    mgr \
    mgr-arm64 \
    mgr-x86_64 \
    scripts/install.sh

echo ""
echo "Released: https://github.com/sholtomaud/mgr/releases/tag/$VERSION"
echo "Cleaning up..."
rm -f mgr-arm64 mgr-x86_64 mgr.zip
