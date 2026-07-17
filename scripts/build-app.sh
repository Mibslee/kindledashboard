#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
APP_NAME="KindleDashboard"
VERSION="${VERSION:-0.3.1}"
BUILD_ROOT="$ROOT/.build/app-bundle"
APP_PATH="$BUILD_ROOT/$APP_NAME.app"
DIST_PATH="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ICONSET="$BUILD_ROOT/AppIcon.iconset"
ASSET_CATALOG="$BUILD_ROOT/Assets.xcassets"
BASE_ICON="$BUILD_ROOT/AppIcon-1024.png"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"

swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"
EXECUTABLE="$BIN_DIR/$APP_NAME"

rm -rf "$BUILD_ROOT" "$DIST_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET" "$(dirname "$DIST_PATH")"
install -m 755 "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"

PLIST="$CONTENTS/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleName -string "$APP_NAME" "$PLIST"
plutil -insert CFBundleDisplayName -string "Kindle Dashboard" "$PLIST"
plutil -insert CFBundleIdentifier -string "studio.shane.kindledashboard" "$PLIST"
plutil -insert CFBundleExecutable -string "$APP_NAME" "$PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$PLIST"
plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -insert CFBundleVersion -string "${BUILD_NUMBER:-1}" "$PLIST"
plutil -insert CFBundleIconFile -string "AppIcon" "$PLIST"
plutil -insert CFBundleIconName -string "AppIcon" "$PLIST"
plutil -insert CFBundleDevelopmentRegion -string "zh_CN" "$PLIST"
plutil -insert LSMinimumSystemVersion -string "14.0" "$PLIST"
plutil -insert LSUIElement -bool true "$PLIST"
plutil -insert LSMultipleInstancesProhibited -bool true "$PLIST"
plutil -insert NSHighResolutionCapable -bool true "$PLIST"
plutil -insert NSPrincipalClass -string "NSApplication" "$PLIST"
plutil -insert NSAppleEventsUsageDescription -string "读取日历、提醒事项和音乐状态，用于 Kindle 信息页。" "$PLIST"
plutil -insert NSCalendarsUsageDescription -string "读取近期日程，用于 Kindle 日历页。" "$PLIST"
plutil -insert NSRemindersUsageDescription -string "读取未完成事项，用于 Kindle 日历页。" "$PLIST"
plutil -insert NSScreenCaptureUsageDescription -string "将用户主动触发的屏幕截图投射到 Kindle。" "$PLIST"

"$MACOS_DIR/$APP_NAME" --write-app-icon "$BASE_ICON"
for entry in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
do
    size="${entry%% *}"
    name="${entry#* }"
    sips -z "$size" "$size" "$BASE_ICON" --out "$ICONSET/$name" >/dev/null
done

mkdir -p "$ASSET_CATALOG/AppIcon.appiconset"
cp "$ROOT/scripts/AppIconContents.json" "$ASSET_CATALOG/AppIcon.appiconset/Contents.json"
cp "$ICONSET"/*.png "$ASSET_CATALOG/AppIcon.appiconset/"
xcrun actool \
    --compile "$RESOURCES_DIR" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$BUILD_ROOT/asset-info.plist" \
    "$ASSET_CATALOG" >/dev/null

codesign --force --deep --sign - "$APP_PATH"
ditto "$APP_PATH" "$DIST_PATH"

printf '%s\n' "$DIST_PATH"
