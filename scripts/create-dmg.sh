#!/bin/bash
set -e

# Create DMG installer for Shotter
# Usage: ./scripts/create-dmg.sh [version]

VERSION="${1:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Shotter.app"
DMG_NAME="Shotter-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_TEMP="$DIST_DIR/Shotter-temp.dmg"
DMG_VOLUME="Shotter"
SIGNING_IDENTITY="Developer ID Application: Daniel Ensign (PTP9R9BR3L)"
KEYCHAIN_PROFILE="notarytool"

echo "=== Creating DMG for Shotter v$VERSION ==="

# Check app exists and is notarized
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found."
    exit 1
fi

# Verify stapled ticket exists
if ! xcrun stapler validate "$APP_BUNDLE" 2>/dev/null; then
    echo "Warning: App doesn't have a stapled notarization ticket."
    echo "Run ./scripts/notarize.sh first for best user experience."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Clean up any previous DMG
rm -f "$DMG_PATH" "$DMG_TEMP"

# Create temporary directory for DMG contents
DMG_STAGING="$DIST_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app to staging
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create Applications symlink
ln -s /Applications "$DMG_STAGING/Applications"

# Calculate size needed (app size + 10MB buffer)
APP_SIZE=$(du -sm "$APP_BUNDLE" | cut -f1)
DMG_SIZE=$((APP_SIZE + 10))

# Create temporary DMG
echo "Creating DMG..."
hdiutil create -srcfolder "$DMG_STAGING" \
    -volname "$DMG_VOLUME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${DMG_SIZE}m" \
    "$DMG_TEMP"

# Convert to compressed final DMG
echo "Compressing DMG..."
hdiutil convert "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

# Clean up temp files
rm -f "$DMG_TEMP"
rm -rf "$DMG_STAGING"

# Sign the DMG
echo "Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$DMG_PATH"

# Notarize the DMG
echo "Notarizing DMG..."
echo "(This may take a few minutes...)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

# Staple the DMG
echo "Stapling DMG..."
xcrun stapler staple "$DMG_PATH"

# Verify
echo "Verifying DMG..."
xcrun stapler validate "$DMG_PATH"
codesign --verify --verbose "$DMG_PATH"

echo ""
echo "=== DMG created ==="
echo "Output: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "Ready for release!"
