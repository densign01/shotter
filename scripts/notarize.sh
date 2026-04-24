#!/bin/bash
set -e

# Notarize signed Shotter app with Apple
# Usage: ./scripts/notarize.sh
#
# Prerequisites: Run this once to store credentials:
#   xcrun notarytool store-credentials "notarytool" \
#     --apple-id "YOUR_APPLE_ID" \
#     --team-id "PTP9R9BR3L" \
#     --password "APP_SPECIFIC_PASSWORD"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="${SHOTTER_DIST_DIR:-$PROJECT_DIR/dist}"
APP_BUNDLE="$DIST_DIR/Shotter.app"
ZIP_FILE="$DIST_DIR/Shotter-notarize.zip"
KEYCHAIN_PROFILE="notarytool"

echo "=== Notarizing Shotter ==="

# Check app exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found. Run ./scripts/build-release.sh first."
    exit 1
fi

# Verify it's signed before notarizing
echo "Verifying signature before submission..."
if ! codesign --verify --verbose "$APP_BUNDLE" 2>/dev/null; then
    echo "Error: App is not properly signed. Run ./scripts/build-release.sh first."
    exit 1
fi

# Create zip for notarization
echo "Creating zip archive..."
rm -f "$ZIP_FILE"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_FILE"

# Submit for notarization
echo "Submitting to Apple notary service..."
echo "(This may take a few minutes...)"
xcrun notarytool submit "$ZIP_FILE" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

# Staple the ticket
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"

# Verify staple
echo "Verifying stapled ticket..."
xcrun stapler validate "$APP_BUNDLE"

# Clean up zip
rm -f "$ZIP_FILE"

echo ""
echo "=== Notarization complete ==="
echo "App is signed, notarized, and stapled."
echo ""
echo "Next step: ./scripts/create-dmg.sh"
