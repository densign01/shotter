#!/bin/bash
set -e

# Full release pipeline for Shotter
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.0.0

if [ -z "$1" ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 1.0.0"
    exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "  Shotter Release Pipeline v$VERSION"
echo "============================================"
echo ""

# Validate version format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in format X.Y.Z (e.g., 1.0.0)"
    exit 1
fi

# Check notarytool credentials
echo "Checking notarization credentials..."
if ! xcrun notarytool history --keychain-profile "notarytool" &>/dev/null; then
    echo ""
    echo "Error: Notarization credentials not configured."
    echo ""
    echo "Run this command first:"
    echo "  xcrun notarytool store-credentials \"notarytool\" \\"
    echo "    --apple-id \"YOUR_APPLE_ID\" \\"
    echo "    --team-id \"PTP9R9BR3L\" \\"
    echo "    --password \"APP_SPECIFIC_PASSWORD\""
    echo ""
    echo "Get an app-specific password at: https://appleid.apple.com"
    echo "(Sign In and Security → App-Specific Passwords)"
    exit 1
fi
echo "Credentials OK"
echo ""

# Step 1: Build and sign
echo "Step 1/4: Building and signing..."
"$SCRIPT_DIR/build-release.sh" "$VERSION"
echo ""

# Step 2: Notarize app
echo "Step 2/4: Notarizing app..."
"$SCRIPT_DIR/notarize.sh"
echo ""

# Step 3: Create DMG
echo "Step 3/4: Creating DMG..."
"$SCRIPT_DIR/create-dmg.sh" "$VERSION"
echo ""

# Step 4: Update appcast for Sparkle auto-updates
echo "Step 4/4: Updating appcast.xml..."
"$SCRIPT_DIR/update-appcast.sh" "$VERSION"
echo ""

echo "============================================"
echo "  Release Complete!"
echo "============================================"
echo ""
echo "Output: $PROJECT_DIR/dist/Shotter-$VERSION.dmg"
echo ""
echo "To publish to GitHub:"
echo "  git add docs/appcast.xml"
echo "  git commit -m \"Update appcast for v$VERSION\""
echo "  git tag v$VERSION"
echo "  git push origin main v$VERSION"
echo "  gh release create v$VERSION dist/Shotter-$VERSION.dmg --title \"Shotter v$VERSION\""
echo ""
