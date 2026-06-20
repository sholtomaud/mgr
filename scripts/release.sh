#!/bin/sh
# Local sign-notarize-release script for mgr.
# Run from the repo root:
#   scripts/release.sh v0.1.0           # signed + notarized (requires Developer ID cert)
#   scripts/release.sh v0.1.0 --unsigned # skip signing (personal use, bypass Gatekeeper manually)
#
# Prerequisites:
#   - GitHub CLI authenticated: gh auth login
#   - Xcode CLI tools installed
#   - (signed only) Developer ID Application certificate in Keychain
#   - (signed only) Notarization credentials stored:
#       xcrun notarytool store-credentials mgr-notary \
#           --apple-id <email> --team-id <TEAMID> --password <app-specific-password>
set -euo pipefail

VERSION="${1:-}"
UNSIGNED=0
for arg in "$@"; do
    [ "$arg" = "--unsigned" ] && UNSIGNED=1
done

if [ -z "$VERSION" ] || [ "$VERSION" = "--unsigned" ]; then
    echo "Usage: $0 <version-tag> [--unsigned]   e.g. $0 v0.1.0" >&2
    exit 1
fi

echo "==> Building mgr $VERSION"

# Detect signing identity
SIGNING_IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" \
    | head -1 \
    | sed 's/.*"\(.*\)".*/\1/' 2>/dev/null || true)

if [ -z "$SIGNING_IDENTITY" ] && [ "$UNSIGNED" -eq 0 ]; then
    echo ""
    echo "No 'Developer ID Application' certificate found in Keychain." >&2
    echo "To release unsigned (personal use only): $0 $VERSION --unsigned" >&2
    echo "" >&2
    echo "To get a Developer ID cert:" >&2
    echo "  1. Enrol in Apple Developer Program (developer.apple.com, \$99/yr)" >&2
    echo "  2. Certificates → Create → Developer ID Application" >&2
    echo "  3. Download and double-click to install into Keychain" >&2
    exit 1
fi

if [ "$UNSIGNED" -eq 1 ]; then
    echo "==> WARNING: unsigned release — Gatekeeper will block this on other Macs"
    echo "    To run on your own Mac after install: xattr -d com.apple.quarantine /usr/local/bin/mgr"
else
    echo "==> Signing identity: $SIGNING_IDENTITY"
fi

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

if [ "$UNSIGNED" -eq 0 ]; then
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
    xcrun notarytool submit mgr.zip \
        --keychain-profile "mgr-notary" \
        --wait
    rm -f mgr.zip

    echo "==> Stapling..."
    xcrun stapler staple mgr
    spctl --assess --type exec mgr
    echo "  ✓ Gatekeeper passes"
else
    echo "==> Skipping sign/notarize (--unsigned)"
fi

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
rm -f mgr-arm64 mgr-x86_64
