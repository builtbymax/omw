# Releasing omw

Releases are signed with a Developer ID, notarized by Apple and distributed through GitHub Releases.
Installed copies update themselves with [Sparkle](https://sparkle-project.org), which reads
`appcast.xml` from the latest GitHub release (`SUFeedURL` in `Resources/Info.plist`).

## Regular release

```sh
make release VERSION=x.y.z
git tag vx.y.z && git push origin vx.y.z
gh release create vx.y.z build/releases/x.y.z/omw-x.y.z.zip build/releases/x.y.z/appcast.xml --title "omw x.y.z"
```

- Release from committed code. The build number (`CFBundleVersion`) is the git commit count, and Sparkle only
  offers builds with a higher number than the installed one.
- Optional release notes: put them in `build/releases/x.y.z/omw-x.y.z.md` before running `make release`.
  Sparkle shows them in the update window.
- Don't publish the GitHub release as a draft or pre-release, or `releases/latest` won't point to it and the
  feed stays on the old version.

## One-time setup

- [ ] Create a **Developer ID Application** certificate (developer.apple.com → Certificates → +, or Xcode →
      Settings → Accounts → Manage Certificates). Only the Account Holder can create one.
- [ ] Check that it is installed: `security find-identity -v -p codesigning` must list
      `"Developer ID Application: … (EDF2FDW257)"`.
- [ ] Back up the certificate: export it from Keychain Access as `.p12` into a password manager. Never keep
      `.p12` files in the repo (they're gitignored).
- [ ] Create an app-specific password at account.apple.com → Sign-In and Security.
- [ ] Store the notary credentials:
      `xcrun notarytool store-credentials omw-notary --apple-id <apple-id> --team-id EDF2FDW257`
- [x] Sparkle keys: the public key is in `Resources/Info.plist` (`SUPublicEDKey`), the private key is in the
      login keychain and backed up in a password manager.
- [ ] The repo must be public, otherwise GitHub release downloads need a login and updates fail. If it stays
      private, host the zip and `appcast.xml` elsewhere and update `SUFeedURL` and `--download-url-prefix`
      in `scripts/release.sh`.

## First release checklist

1. Commit everything and push `main`.
2. `make release VERSION=0.2.0`, tag it and create the GitHub release (see above).
3. Test it like a user:
   - Download the zip in a browser (not from `build/`, so the quarantine flag is set), unzip it and move the
     app to `/Applications`.
   - It opens without a Gatekeeper warning, apart from the usual "downloaded from the internet" prompt.
   - Grant Accessibility and arrange some windows.
   - The feed resolves:
     `curl -L https://github.com/builtbymax/omw/releases/latest/download/appcast.xml`
4. Test the update:
   - Make a small change, commit it and release `0.2.1`.
   - In the installed 0.2.0: menu → Check for Updates… → Install. omw restarts as 0.2.1.
   - Accessibility still works without asking again.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Notarization fails | `xcrun notarytool log <submission-id> --keychain-profile omw-notary` lists the files with signing problems. |
| "Update is improperly signed" | The Sparkle private key is missing from this Mac's keychain. Restore it with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -f <file>`. |
| No update offered | The new build number isn't higher than the installed one. Release from a newer commit. |
| `No Developer ID Application identity found` | The certificate isn't in the login keychain, or set `OMW_SIGN_IDENTITY` explicitly. |
