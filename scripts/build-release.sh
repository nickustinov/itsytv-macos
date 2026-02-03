#!/bin/bash
set -e

# Configuration
APP_NAME="itsytv"
BUNDLE_ID="com.itsytv.app"
VERSION=$(defaults read "$(pwd)/itsytv/Info.plist" CFBundleShortVersionString)

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

cd "$PROJECT_DIR"

echo "==> Version: $VERSION"

# Generate Xcode project from project.yml
echo "==> Generating Xcode project..."
xcodegen generate

# Build universal binary (arm64 + x86_64)
echo "==> Building universal release binary..."
xcodebuild -scheme itsytv -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$DIST_DIR/itsytv.xcarchive" \
    archive \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

echo "==> Extracting app bundle..."
rm -rf "$APP_BUNDLE"
cp -R "$DIST_DIR/itsytv.xcarchive/Products/Applications/$APP_NAME.app" "$APP_BUNDLE"
rm -rf "$DIST_DIR/itsytv.xcarchive"

# Verify universal binary
echo "==> Checking architectures..."
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Check if we should sign
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')"

    echo "==> Signing app with: $SIGNING_IDENTITY"

    # Sign all frameworks and dylibs first
    find "$APP_BUNDLE" -name "*.framework" -o -name "*.dylib" | while read -r item; do
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$item"
    done

    # Sign the app bundle
    codesign --force --options runtime --deep --sign "$SIGNING_IDENTITY" \
        --entitlements "$PROJECT_DIR/itsytv/itsytv.entitlements" \
        "$APP_BUNDLE"

    echo "==> Verifying signature..."
    codesign --verify --deep --strict "$APP_BUNDLE"

    echo "==> Creating DMG..."
    rm -f "$DMG_PATH"
    DMG_STAGING="$DIST_DIR/dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_BUNDLE" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
    rm -rf "$DMG_STAGING"

    echo "==> Signing DMG..."
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

    echo ""
    echo "==> Build complete!"
    echo "    App: $APP_BUNDLE"
    echo "    DMG: $DMG_PATH"
    echo ""
    echo "To notarize, run:"
    echo "    xcrun notarytool submit \"$DMG_PATH\" --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD> --wait"
    echo "    xcrun stapler staple \"$DMG_PATH\""
    echo ""
    echo "To create a GitHub release:"
    echo "    gh release create v$VERSION \"$DMG_PATH\" --title \"v$VERSION\" --generate-notes"
else
    echo "==> No Developer ID certificate found, skipping signing..."

    echo "==> Creating unsigned DMG..."
    rm -f "$DMG_PATH"
    DMG_STAGING="$DIST_DIR/dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_BUNDLE" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
    rm -rf "$DMG_STAGING"

    echo ""
    echo "==> Build complete (UNSIGNED)!"
    echo "    App: $APP_BUNDLE"
    echo "    DMG: $DMG_PATH"
    echo ""
    echo "NOTE: To distribute, you need a Developer ID certificate from developer.apple.com"
fi
