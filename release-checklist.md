# Release checklist

Releases are signed with a Developer ID, notarized by Apple and published on GitHub Releases. Installed copies
update themselves with [Sparkle](https://sparkle-project.org) from `appcast.xml` on the latest release.

## Before the release

- [ ] Everything is committed and pushed to `main`, and `CFBundleShortVersionString` in `Resources/Info.plist`
      is the new version. The build number is the git commit count, and Sparkle only offers builds with a higher
      number than the installed one.
- [ ] Optional release notes are in `build/releases/x.y.z/omw-x.y.z.md`. Sparkle shows them in the update window.

## Build

- [ ] `make release VERSION=x.y.z` (checks, tests, universal build, signing, notarization, signed appcast, manifest).
      It refuses to run with uncommitted changes, off `main`, with `main` not matching `origin/main`, an existing
      tag, a mismatched version, a build number that isn't above the published one, or failing tests.
- [ ] It ends with "Release ready in build/releases/x.y.z".

## Publish

Draft first, so nothing is public until the uploaded files are checked.

- [ ] `git tag vx.y.z && git push origin vx.y.z`
- [ ] `gh release create vx.y.z build/releases/x.y.z/{omw-x.y.z.zip,appcast.xml,omw-x.y.z-manifest.json} --draft --verify-tag --title "omw x.y.z"`
- [ ] `scripts/verify-release.sh x.y.z` passes on the draft.
- [ ] `gh release edit vx.y.z --draft=false --latest`. Not a pre-release, otherwise `releases/latest` still points to the old version.
- [ ] `scripts/verify-release.sh x.y.z` passes again, now including the live feed.
- [ ] Bump `version` in `website/src/config.ts` and deploy the website.

## Check

- [ ] Download the zip in a browser, unzip it and open it. No Gatekeeper warning apart from the usual
      "downloaded from the internet" prompt.
- [ ] An installed older version finds the update (menu → Check for Updates…), installs it and restarts.
- [ ] Accessibility still works without asking again.

## Sparkle signing

Since 1.0.4 omw requires a signed appcast (`SURequireSignedFeed`) and checks the zip's signature before unpacking
it (`SUVerifyUpdateBeforeExtraction`). `generate_appcast` signs the appcast and the embedded release notes because
the new app asks for it, and `release.sh` stops if the signatures don't check out.

- Never edit `appcast.xml` by hand after `generate_appcast`: that breaks its signature and installed copies reject
  the feed. Run `generate_appcast` again instead.
- Every release from now on has to come from this setup (or a newer Sparkle), an unsigned feed on the latest
  release stops updates for everyone on 1.0.4 or later.
- The EdDSA private key lives in the login keychain of the release Mac. Keep an encrypted backup somewhere
  else, e.g. a password manager: `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key`,
  store the file, then delete it. Without the key no installed copy can be updated any more.
- Rotating the key: Sparkle only accepts a new key through an update that's signed with the old one. Release
  a version whose `SUPublicEDKey` is the new key, signed with the old key, then switch the release Mac to the
  new key. With a lost key, the only way back is a Developer ID signed disk image as a fallback (see Sparkle's
  `SUVerifyUpdateBeforeExtraction` documentation) or users downloading omw again.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Notarization fails | `xcrun notarytool log <submission-id> --keychain-profile omw-notary` lists the files with signing problems. |
| "Update is improperly signed" | The Sparkle private key is missing from this Mac's keychain. Restore it with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -f <file>`. |
| `verify-sparkle: … has no feed signature` | The appcast wasn't generated from an app with `SURequireSignedFeed`, or was edited afterwards. Run `make release` again. |
| No update offered | The new build number isn't higher than the installed one. Release from a newer commit. |
| `No Developer ID Application identity found` | The certificate isn't in the login keychain, or set `OMW_SIGN_IDENTITY` explicitly. |
