#!/bin/bash
set -e

# Build and sign Shotter for distribution
# Usage: ./scripts/build-release.sh [version]

VERSION="${1:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Shotter.app"
SIGNING_IDENTITY="Developer ID Application: Daniel Ensign (PTP9R9BR3L)"
ENTITLEMENTS="$PROJECT_DIR/Shotter/Resources/Shotter.entitlements"

echo "=== Building Shotter v$VERSION ==="

# Clean previous build
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Build release binary
echo "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

# Create app bundle structure
echo "Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp ".build/release/Shotter" "$APP_BUNDLE/Contents/MacOS/"

# Create Info.plist with version
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Shotter</string>
    <key>CFBundleIdentifier</key>
    <string>com.densign.shotter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Shotter</string>
    <key>CFBundleDisplayName</key>
    <string>Shotter</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>${VERSION//./}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Shotter needs screen recording permission to capture screenshots.</string>
</dict>
</plist>
EOF

# Copy any resources if they exist
if [ -d "$PROJECT_DIR/Shotter/Resources" ]; then
    # Copy resources except Info.plist and entitlements (we generate Info.plist)
    find "$PROJECT_DIR/Shotter/Resources" -type f ! -name "Info.plist" ! -name "*.entitlements" -exec cp {} "$APP_BUNDLE/Contents/Resources/" \; 2>/dev/null || true
fi

# Sign with hardened runtime
echo "Signing with hardened runtime..."
codesign --force --deep --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    "$APP_BUNDLE"

# Verify signature
echo "Verifying signature..."
codesign --verify --verbose=2 "$APP_BUNDLE"

# Check hardened runtime
echo "Checking hardened runtime..."
codesign -d --verbose=2 "$APP_BUNDLE" 2>&1 | grep -i "runtime"

echo ""
echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
echo "Version: $VERSION"
echo ""
echo "Next step: ./scripts/notarize.sh"
