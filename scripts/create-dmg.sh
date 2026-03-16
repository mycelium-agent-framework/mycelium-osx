#!/usr/bin/env bash
# Creates a DMG installer for MyceliumOSX
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/Release"
APP_NAME="MyceliumOSX"
DMG_NAME="MyceliumOSX"
VERSION=$(defaults read "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.1.0")
DMG_FILE="$PROJECT_DIR/build/${DMG_NAME}-${VERSION}.dmg"
STAGING_DIR="$PROJECT_DIR/build/dmg-staging"

echo "Building DMG for $APP_NAME v$VERSION..."

# Clean staging
rm -rf "$STAGING_DIR" "$DMG_FILE"
mkdir -p "$STAGING_DIR"

# Copy app
cp -R "$BUILD_DIR/$APP_NAME.app" "$STAGING_DIR/"

# Create Applications symlink
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
hdiutil create \
    -volname "$DMG_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_FILE"

# Clean staging
rm -rf "$STAGING_DIR"

echo ""
echo "DMG created: $DMG_FILE"
echo "Size: $(du -h "$DMG_FILE" | cut -f1)"
