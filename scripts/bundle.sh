#!/bin/zsh
# Builds omw and assembles build/omw.app.
#
# Environment:
#   OMW_SIGN_IDENTITY  Code signing identity. Ad-hoc by default, which means macOS asks for Accessibility
#                      access again after every rebuild. A "Developer ID Application" identity also turns
#                      on the hardened runtime and a secure timestamp, both required for notarization.
#   OMW_VERSION        Marketing version (CFBundleShortVersionString). Defaults to the one in Info.plist.
#   OMW_UNIVERSAL=1    Build for both Apple silicon and Intel instead of only this Mac's architecture.
set -euo pipefail
cd "${0:A:h}/.."

ARCH_FLAGS=()
[[ "${OMW_UNIVERSAL:-}" == 1 ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release $ARCH_FLAGS
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

APP=build/omw.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
cp "$BIN_DIR/omw" "$APP/Contents/MacOS/omw"
# The command-line tool, which Settings links into /usr/local/bin.
cp "$BIN_DIR/omw-cli" "$APP/Contents/Helpers/omw"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# Sparkle compares CFBundleVersion to find newer builds, so it must only ever go up: use the commit count.
PLIST="$APP/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
[[ -n "${OMW_VERSION:-}" ]] && plutil -replace CFBundleShortVersionString -string "$OMW_VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD 2>/dev/null || echo 1)" "$PLIST"

# App icon: build the .icns from the 1024px PNG exported from the "OMW" Figma file.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/Icon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/Icon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Sign inside-out (never --deep): Sparkle's helpers first, then the framework and the CLI, then the app.
IDENTITY="${OMW_SIGN_IDENTITY:--}"
SIGN=(codesign --force --sign "$IDENTITY")
[[ "$IDENTITY" == "Developer ID Application"* ]] && SIGN+=(--options runtime --timestamp)
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
$SIGN "$SPARKLE/XPCServices/Installer.xpc"
$SIGN --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
$SIGN "$SPARKLE/Autoupdate"
$SIGN "$SPARKLE/Updater.app"
$SIGN "$APP/Contents/Frameworks/Sparkle.framework"
$SIGN --identifier com.builtbymax.omw.cli "$APP/Contents/Helpers/omw"
$SIGN "$APP"
echo "Built $APP $(plutil -extract CFBundleShortVersionString raw "$PLIST") ($(plutil -extract CFBundleVersion raw "$PLIST")), signed with ${IDENTITY/#-/ad-hoc}"
