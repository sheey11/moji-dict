#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-"$PROJECT_DIR/dist"}"
APP_NAME="Moji 辞書"
EXECUTABLE_NAME="MojiQuickLook"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME.zip"
SWIFT_MODULE_CACHE="$PROJECT_DIR/.build/module-cache"
CLANG_MODULE_CACHE="$PROJECT_DIR/.build/clang-cache"
ASSET_BUILD_DIR="$PROJECT_DIR/.build/asset-catalog"

mkdir -p "$SWIFT_MODULE_CACHE" "$CLANG_MODULE_CACHE"
SWIFTPM_MODULECACHE_OVERRIDE="$SWIFT_MODULE_CACHE" \
CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE" \
swift build --package-path "$PROJECT_DIR" -c release --disable-sandbox

mkdir -p "$ASSET_BUILD_DIR"
xcrun actool "$PROJECT_DIR/assets/Assets.xcassets" \
    --compile "$ASSET_BUILD_DIR" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ASSET_BUILD_DIR/asset-info.plist"

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$PROJECT_DIR/.build/release/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ASSET_BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ASSET_BUILD_DIR/Assets.car" "$APP_BUNDLE/Contents/Resources/Assets.car"

codesign --force --sign - --timestamp=none "$APP_BUNDLE"
rm -f "$ZIP_PATH"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "$APP_BUNDLE"
echo "$ZIP_PATH"
