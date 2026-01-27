#!/bin/bash
set -e

# Update appcast.xml with new release entry
# Usage: ./scripts/update-appcast.sh <version>
# Requires: DMG at dist/Shotter-<version>.dmg

if [ -z "$1" ]; then
    echo "Usage: ./scripts/update-appcast.sh <version>"
    exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DMG_PATH="$PROJECT_DIR/dist/Shotter-$VERSION.dmg"
APPCAST_PATH="$PROJECT_DIR/docs/appcast.xml"
SPARKLE_BIN="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin"

# Verify DMG exists
if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG not found at $DMG_PATH"
    exit 1
fi

# Get DMG size (works on both macOS and Linux)
DMG_SIZE=$(wc -c < "$DMG_PATH" | tr -d ' ')

# Get EdDSA signature using Sparkle's sign_update tool
echo "Signing DMG with EdDSA..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH" 2>/dev/null | grep "sparkle:edSignature" | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$SIGNATURE" ]; then
    echo "Error: Failed to generate EdDSA signature"
    exit 1
fi

echo "Signature: $SIGNATURE"

# GitHub release URL
DOWNLOAD_URL="https://github.com/densign01/shotter/releases/download/v$VERSION/Shotter-$VERSION.dmg"

# Build date in RFC 2822 format
PUB_DATE=$(date -R)

# Create new item XML
NEW_ITEM=$(cat << EOF
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$DOWNLOAD_URL"
        length="$DMG_SIZE"
        type="application/octet-stream"
        sparkle:edSignature="$SIGNATURE"
      />
    </item>
EOF
)

# Insert new item into appcast (after <language>en</language>)
# Create backup
cp "$APPCAST_PATH" "$APPCAST_PATH.bak"

# Use awk to insert after </language>
awk -v item="$NEW_ITEM" '
    /<\/language>/ {
        print
        print item
        next
    }
    { print }
' "$APPCAST_PATH.bak" > "$APPCAST_PATH"

rm "$APPCAST_PATH.bak"

echo "Updated appcast.xml with version $VERSION"
echo "Don't forget to commit and push docs/appcast.xml!"
