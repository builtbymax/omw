# omw — oh my windows

A deliberately small window manager for macOS. Pick a column layout, and every window on the
current desktop snaps into it. No tiling trees, no workspaces, no config language.

## Usage

| Shortcut | Action |
| --- | --- |
| `⌃⌥Space` | Open the omw launcher: type a layout name (`code`, `20/60`, `halves`…) and press `↩` |
| `⌃⌥⌘←` / `⌃⌥⌘→` | Move the focused window one column left/right, swapping with the window there |
| `⌃⌥⌘↑` / `⌃⌥⌘↓` | Move the focused window to the row above/below. In a column without rows: top/bottom half (again: back to full height) |
| `⌃⌥⌘]` / `⌃⌥⌘[` | Move the focused window to the matching column on the next/previous display |
| `⌃⌥⇧→` / `⌃⌥⇧←` | Move the focused window to the next/previous workspace (Space) |
| `⌃⌥1`…`⌃⌥5` | Apply Halves, Thirds, Code, Main Left, Main Right (new configs only) |

All shortcuts can be changed in **Settings** (menu bar icon → Settings…), and every layout can get its own shortcut.

### Launcher

- While you browse, dashed ghost columns show the selected layout on the real display, and the
  preview pane lists which app lands in which column.
- The display chip next to the search field (or `⌘D`) switches the target display when you have more than one.
- `⌘K` opens the actions for the selected item (apply, edit the layout in Settings, undo), `⌘E` edits
  the selected layout, `⌘,` opens Settings.

Moving windows between workspaces has no public macOS API. omw briefly holds the window by its title
bar and presses the Mission Control shortcuts "Move left/right a space" (`⌃←` / `⌃→`), so those
need to stay enabled in System Settings → Keyboard → Keyboard Shortcuts → Mission Control.

After a layout is applied, windows glide into place and a small "Arranged N windows" confirmation
offers **Undo** for a few seconds (also in the launcher and the menu). Both can be turned off in
Settings → General.

### Layouts

Built in: Halves `50/50`, Thirds `33/33/33`, Code `20/60/20`, Main Left `70/30`, Main Right `30/70`, Full `100`,
Center `_20/60/_20`.
Add or edit layouts in Settings, columns are written like `20/60/20` or `1:2:1`, or drag the
column edges in the blueprint preview (they snap to 5%).

A column can be split into up to 4 equal rows: `2x20/60/2x20` gives two stacked windows on each side of a
wide middle column. A column written as `_20` stays empty: `_20/60/_20` puts windows in a centered 60% column
and leaves the sides free. In the blueprint, hover a column and use its row buttons, below one row it
becomes empty.

### How windows are assigned

Every window fills a cell: a whole column, or one row of it. When there are more windows than cells, the
extra windows go into the same cells again, filling the emptiest one first:

```
Layout 20/60/20, windows: Slack, VSCode, Claude, Spotify, Linear
→ 20: Slack, Spotify   60: VSCode, Linear   20: Claude
```

- **Preferred columns**: in Settings → Layouts you can pin apps to a column or row, e.g. VSCode always
  in the `60` of the Code layout. With **Only move pinned apps** turned on for a layout, all other
  windows stay where they are.
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

## Releasing

```sh
make release VERSION=0.2.0   # universal build, Developer ID signing, notarization, Sparkle appcast
```

The output in `build/releases/0.2.0/` (the zip and `appcast.xml`) goes onto the GitHub release `v0.2.0`.
Installed copies find it through `SUFeedURL` and update themselves with [Sparkle](https://sparkle-project.org).
See [RELEASING.md](RELEASING.md) for the one-time setup (certificate, notary credentials, Sparkle keys)
and the release checklist.
