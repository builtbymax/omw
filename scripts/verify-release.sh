#!/bin/zsh
# Downloads a GitHub release of omw (draft or published) and checks it against its manifest:
#   scripts/verify-release.sh 1.0.4
#
# Checks the zip and appcast hashes, the Sparkle feed and archive signatures against SUPublicEDKey,
# code signatures, Gatekeeper, the stapled notarization ticket, architectures, version and build, and
# that the manifest's commit is the one tagged v<version>. Once the release is public, also that the live
# feed (SUFeedURL) is this release's appcast.
set -euo pipefail
cd "${0:A:h}/.."

fail() { echo "verify-release: $1" >&2; exit 1; }
ok() { echo "  ✓ $1"; }

VERSION="${1:?usage: scripts/verify-release.sh <version>}"
VERSION="${VERSION#v}"
TAG="v$VERSION"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"
FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Resources/Info.plist)"

DIR="$(mktemp -d)"
gh release download "$TAG" --dir "$DIR" --pattern "omw-$VERSION.zip" --pattern appcast.xml --pattern "omw-$VERSION-manifest.json"
ZIP="$DIR/omw-$VERSION.zip"
MANIFEST="$DIR/omw-$VERSION-manifest.json"
field() { plutil -extract "$1" raw -o - "$MANIFEST"; }
sha() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
echo "Checking omw $VERSION in $DIR"

[[ "$(field version)" == "$VERSION" ]] || fail "The manifest is for version $(field version)"
[[ "$(sha "$ZIP")" == "$(field sha256.zip)" ]] || fail "The zip doesn't match the manifest"
[[ "$(sha "$DIR/appcast.xml")" == "$(field sha256.appcast)" ]] || fail "appcast.xml doesn't match the manifest"
ok "zip and appcast match the manifest"

swift scripts/verify-sparkle.swift "$PUBLIC_KEY" "$DIR/appcast.xml" "$ZIP" >/dev/null
ok "feed and archive signatures are valid for SUPublicEDKey"

git fetch --quiet --tags origin
[[ "$(git rev-parse -q --verify "refs/tags/$TAG^{commit}")" == "$(field commit)" ]] || fail "$TAG isn't the commit in the manifest ($(field commit))"
ok "$TAG is commit $(field commit)"

ditto -x -k "$ZIP" "$DIR/unzipped"
APP="$DIR/unzipped/omw.app"
PLIST="$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
[[ "$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')" == "$(field team)" ]] || fail "Signed by another team than $(field team)"
spctl --assess --type execute "$APP"
xcrun stapler validate -q "$APP"
ok "code signatures, Gatekeeper and stapled notarization (team $(field team))"

for key binary in app Contents/MacOS/omw cli Contents/Helpers/omw; do
  [[ "$(sha "$APP/$binary")" == "$(field "sha256.$key")" ]] || fail "$binary doesn't match the manifest"
  [[ "$(lipo -archs "$APP/$binary")" == *arm64* && "$(lipo -archs "$APP/$binary")" == *x86_64* ]] || fail "$binary isn't universal"
done
ok "binaries match the manifest and are universal"

[[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" == "$VERSION" ]] || fail "The app says version $(plutil -extract CFBundleShortVersionString raw "$PLIST")"
[[ "$(plutil -extract CFBundleVersion raw "$PLIST")" == "$(field build)" ]] || fail "The app has another build number than the manifest"
[[ "$(plutil -extract SUPublicEDKey raw "$PLIST")" == "$PUBLIC_KEY" ]] || fail "The app has another SUPublicEDKey than Resources/Info.plist"
[[ "$(plutil -extract SURequireSignedFeed raw "$PLIST")" == true ]] || fail "The app doesn't require a signed feed"
[[ "$(plutil -extract SUVerifyUpdateBeforeExtraction raw "$PLIST")" == true ]] || fail "The app doesn't verify updates before extracting them"
ok "version $VERSION, build $(field build), Sparkle settings"

if [[ "$(gh release view "$TAG" --json isDraft -q .isDraft)" == false ]]; then
  curl -fsSL "$FEED" -o "$DIR/live-appcast.xml"
  cmp -s "$DIR/live-appcast.xml" "$DIR/appcast.xml" || fail "The live feed $FEED isn't this release's appcast"
  ok "the live feed is this release's appcast"
else
  echo "  - draft: publish it, then run this again to check the live feed"
fi
echo "omw $VERSION checks out."
