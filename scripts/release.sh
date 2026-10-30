#!/bin/zsh
# Builds a notarized release of omw plus the signed Sparkle appcast: scripts/release.sh 1.0.3
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
# Only releases committed main as pushed to GitHub, at the version in Resources/Info.plist, after the tests
# pass. Output in build/releases/<version>/: omw-<version>.zip, appcast.xml and omw-<version>-manifest.json.
# Release notes go into an optional omw-<version>.md next to the zip before running. Publish all three
# files as described in release-checklist.md.
set -euo pipefail
cd "${0:A:h}/.."

fail() { echo "release: $1" >&2; exit 1; }

VERSION="${1:?usage: scripts/release.sh <version>}"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "$VERSION isn't a version like 1.0.3"
PROFILE="${OMW_NOTARY_PROFILE:-omw-notary}"
IDENTITY="${OMW_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"' || true)}"
[[ "$IDENTITY" == "Developer ID Application"* ]] || fail "No Developer ID Application identity found"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"
[[ -n "$PUBLIC_KEY" ]] || fail "SUPublicEDKey in Resources/Info.plist is empty, run Sparkle's generate_keys first"
FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Resources/Info.plist)"

# The source has to be exactly what's public, so the release can be traced back to it.
[[ "$(git rev-parse --is-shallow-repository)" == false ]] || fail "Shallow clone: the build number (commit count) would be wrong"
[[ -z "$(git status --porcelain)" ]] || fail "Uncommitted changes, commit or stash them first"
[[ "$(git symbolic-ref --short HEAD 2>/dev/null)" == main ]] || fail "Not on main"
but pull --check
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main isn't the same as origin/main, push or pull first"
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || fail "v$VERSION is already tagged"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[[ "$PLIST_VERSION" == "$VERSION" ]] || fail "Resources/Info.plist says $PLIST_VERSION, bump it to $VERSION first"

# Sparkle only offers builds with a higher number than the installed one.
BUILD="$(git rev-list --count HEAD)"
PUBLISHED="$(curl -fsSL "$FEED" | sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | sort -n | tail -1)"
[[ -z "$PUBLISHED" ]] || (( BUILD > PUBLISHED )) || fail "Build $BUILD isn't newer than the published build $PUBLISHED"

make test

OMW_SIGN_IDENTITY="$IDENTITY" OMW_VERSION="$VERSION" OMW_UNIVERSAL=1 ./scripts/bundle.sh
APP=build/omw.app
[[ "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" == "$VERSION" ]] || fail "The app has the wrong version"
[[ "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" == "$BUILD" ]] || fail "The app has the wrong build number"

OUT="build/releases/$VERSION"
ZIP="$OUT/omw-$VERSION.zip"
MANIFEST="$OUT/omw-$VERSION-manifest.json"
mkdir -p "$OUT"
rm -f "$ZIP" "$OUT/appcast.xml" "$MANIFEST"

# Notarize, staple the ticket to the app so it also opens offline, then zip the stapled app again.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
spctl --assess --type execute "$APP"

# The appcast only lists this release, Sparkle just needs the newest one. The app requires a signed feed
# (SURequireSignedFeed), which makes generate_appcast sign the appcast and the embedded release notes.
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --embed-release-notes \
  --download-url-prefix "https://github.com/builtbymax/omw/releases/download/v$VERSION/" "$OUT"
swift scripts/verify-sparkle.swift "$PUBLIC_KEY" "$OUT/appcast.xml" "$ZIP"

# What went into the release, to check the published files against later (scripts/verify-release.sh).
sha() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
cat > "$MANIFEST" <<EOF
{
  "version": "$VERSION",
  "build": "$BUILD",
  "commit": "$(git rev-parse HEAD)",
  "team": "$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')",
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "macOS": "$(sw_vers -productVersion) ($(sw_vers -buildVersion))",
  "swift": "$(swift --version 2>&1 | head -1)",
  "dependencies": $(plutil -extract pins json -o - Package.resolved),
  "sha256": {
    "zip": "$(sha "$ZIP")",
    "appcast": "$(sha "$OUT/appcast.xml")",
    "app": "$(sha "$APP/Contents/MacOS/omw")",
    "cli": "$(sha "$APP/Contents/Helpers/omw")"
  }
}
EOF
plutil -p "$MANIFEST" >/dev/null || fail "Could not write $MANIFEST"

echo "\nRelease ready in $OUT. Publish it as a draft, check it, then make it public:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  gh release create v$VERSION $ZIP $OUT/appcast.xml $MANIFEST --draft --verify-tag --title \"omw $VERSION\""
echo "  scripts/verify-release.sh $VERSION"
echo "  gh release edit v$VERSION --draft=false --latest"
echo "  scripts/verify-release.sh $VERSION"
