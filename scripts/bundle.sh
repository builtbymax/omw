#!/bin/zsh
# Builds omw and assembles build/omw.app.
#
# Signs ad-hoc by default, which means macOS asks for Accessibility access again after every
# rebuild. Set OMW_SIGN_IDENTITY to a code signing certificate (e.g. a self-signed one from
# Keychain Access) to keep the permission across builds.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/omw"

APP=build/omw.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/omw"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${OMW_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with ${IDENTITY/#-/ad-hoc})"
