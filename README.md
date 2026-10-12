# omw — order my windows

A deliberately small window manager for macOS. Pick a column layout, and every window on the
current desktop snaps into it. No tiling trees, no workspaces, no config language.

## Usage

| Shortcut | Action |
| --- | --- |
| `⌃⌥Space` | Open the omw launcher: type a layout name (`code`, `20/60`, `halves`…) and press `↩` |
| `⌃⌥⌘←` / `⌃⌥⌘→` | Move the focused window one column left/right, swapping with the window there |

All shortcuts can be changed in **Settings** (menu bar icon → Settings…), and every layout can get its own shortcut.

### Layouts

Built in: Halves `50/50`, Thirds `33/33/33`, Code `20/60/20`, Main Left `70/30`, Main Right `30/70`, Full `100`.
Add or edit layouts in Settings, columns are written like `20/60/20` or `1:2:1`.

### How windows are assigned

Every window gets the full height of a column. When there are more windows than columns, the extra
windows go into the same columns again, filling the emptiest one first:

```
Layout 20/60/20, windows: Slack, VSCode, Claude, Spotify, Linear
→ 20: Slack, Spotify   60: VSCode, Linear   20: Claude
```

- **Preferred columns**: in Settings → Layouts you can pin apps to a column, e.g. VSCode always
  in the `60` of the Code layout.
- **Stable**: windows that already sit in a column stay there, so re-applying a layout (e.g. after
  opening a new window) doesn't shuffle everything around.
- Only windows on the current desktop and on the display of the focused window are touched.
  Minimized, hidden and full-screen windows are left alone.

## Install

Requires macOS 14+ and the Swift toolchain (Xcode or the Command Line Tools).

```sh
make install   # builds build/omw.app, copies it to /Applications and starts it
```

On first launch macOS asks for **Accessibility** access (System Settings → Privacy & Security →
Accessibility), which omw needs to move windows. "Launch at login" lives in Settings and the menu.

The app is signed ad-hoc, so macOS asks for Accessibility access again after a rebuild (remove the old
entry and add the new app). To avoid that, sign with a stable certificate:
`OMW_SIGN_IDENTITY="My Cert" make install`.

## Development

```sh
make run    # build and launch from build/
make test   # unit tests for the layout logic (Sources/OMWCore)
```

Settings are stored in `~/.config/omw/config.json`, so you can edit them by hand. Restart omw after manual edits.
