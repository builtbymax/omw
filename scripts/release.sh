#!/bin/zsh
# Builds a notarized release of omw plus the Sparkle appcast: scripts/release.sh 0.2.0
#
# One-time setup:
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. Notary credentials: xcrun notarytool store-credentials omw-notary --apple-id <id> --team-id <team>
#   3. Sparkle keys: .build/artifacts/sparkle/Sparkle/bin/generate_keys, then put the printed public key
#      into SUPublicEDKey in Resources/Info.plist. The private key stays in the login keychain.
#
# Environment:
#   OMW_SIGN_IDENTITY   Defaults to the first Developer ID Application identity in the keychain.
#   OMW_NOTARY_PROFILE  notarytool keychain profile, defaults to omw-notary.
#
# Output in build/releases/<version>/: omw-<version>.zip and appcast.xml. Release notes go into an optional
# omw-<version>.md next to the zip before running. Upload both files to the GitHub release v<version>.
set -euo pipefail
cd "${0:A:h}/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
VERSION="${VERSION#v}"
PROFILE="${OMW_NOTARY_PROFILE:-omw-notary}"
IDENTITY="${OMW_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"' || true)}"
[[ "$IDENTITY" == "Developer ID Application"* ]] || { echo "No Developer ID Application identity found" >&2; exit 1; }
[[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)" ]] \
  || { echo "SUPublicEDKey in Resources/Info.plist is empty, run Sparkle's generate_keys first" >&2; exit 1; }

OMW_SIGN_IDENTITY="$IDENTITY" OMW_VERSION="$VERSION" OMW_UNIVERSAL=1 ./scripts/bundle.sh

OUT="build/releases/$VERSION"
ZIP="$OUT/omw-$VERSION.zip"
mkdir -p "$OUT"
rm -f "$ZIP" "$OUT/appcast.xml"

# Notarize, staple the ticket to the app so it also opens offline, then zip the stapled app again.
ditto -c -k --sequesterRsrc --keepParent build/omw.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/omw.app
rm "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/omw.app "$ZIP"
spctl --assess --type execute build/omw.app

# The appcast only lists this release, Sparkle just needs the newest one.
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/builtbymax/omw/releases/download/v$VERSION/" "$OUT"

echo "\nRelease ready in $OUT. Publish it with:"
echo "  gh release create v$VERSION $ZIP $OUT/appcast.xml --title \"omw $VERSION\""
