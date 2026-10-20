# Release checklist

Releases are signed with a Developer ID, notarized by Apple and published on GitHub Releases. Installed copies
update themselves with [Sparkle](https://sparkle-project.org) from `appcast.xml` on the latest release.

## Before the release

- [ ] Everything is committed and pushed to `main`. The build number is the git commit count, and Sparkle only
      offers builds with a higher number than the installed one.
- [ ] `make test` passes.
- [ ] Optional release notes are in `build/releases/x.y.z/omw-x.y.z.md`. Sparkle shows them in the update window.

## Build

- [ ] `make release VERSION=x.y.z` (universal build, signing, notarization, appcast).
- [ ] It ends with "Release ready in build/releases/x.y.z".

## Publish

- [ ] `git tag vx.y.z && git push origin vx.y.z`
- [ ] `gh release create vx.y.z build/releases/x.y.z/omw-x.y.z.zip build/releases/x.y.z/appcast.xml --title "omw x.y.z"`
- [ ] Not a draft or pre-release, otherwise `releases/latest` still points to the old version.
- [ ] Bump `version` in `website/src/config.ts` and deploy the website.

## Check

- [ ] The feed shows the new version:
      `curl -L https://github.com/builtbymax/omw/releases/latest/download/appcast.xml`
- [ ] Download the zip in a browser, unzip it and open it. No Gatekeeper warning apart from the usual
      "downloaded from the internet" prompt.
- [ ] An installed older version finds the update (menu → Check for Updates…), installs it and restarts.
- [ ] Accessibility still works without asking again.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Notarization fails | `xcrun notarytool log <submission-id> --keychain-profile omw-notary` lists the files with signing problems. |
| "Update is improperly signed" | The Sparkle private key is missing from this Mac's keychain. Restore it with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -f <file>`. |
| No update offered | The new build number isn't higher than the installed one. Release from a newer commit. |
| `No Developer ID Application identity found` | The certificate isn't in the login keychain, or set `OMW_SIGN_IDENTITY` explicitly. |
