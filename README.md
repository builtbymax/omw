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

In Settings → Appearance, buttons, badges and highlights can follow the macOS accent color instead of omw blue.
Layout icons and the blueprint stay omw blue.

### Launcher

- While you browse, dashed ghost columns show the selected layout on the real display, and the
  preview pane lists which app lands in which column.
- The display chip next to the search field (or `⌘D`) switches the target display when you have more than one.
- The launcher opens on the display with the focused window. With **Open launcher on primary display**
  (Settings → General) it always opens on the display with the menu bar, while layouts still go to the
  focused window's display, shown in the display chip.
- `⌘K` opens the actions for the selected item (apply, edit the layout in Settings, undo), `⌘E` edits
  the selected layout, `⌘,` opens Settings.

Moving windows between workspaces has no public macOS API. omw briefly holds the window by its title
bar and presses the Mission Control shortcuts "Move left/right a space" (`⌃←` / `⌃→` unless you
remapped them), so those need to stay enabled in System Settings → Keyboard → Keyboard Shortcuts →
Mission Control. If there's no Space in that direction or the shortcut is off, omw beeps.

After a layout is applied, windows glide into place and a small "Arranged N windows" confirmation
offers **Undo** for a few seconds (also in the launcher and the menu). Both can be turned off in
Settings → General.

### Layouts

Built in: Halves `50/50`, Thirds `33/33/33`, Code `20/60/20`, Main Left `70/30`, Main Right `30/70`, Full `100`,
Center `_20/60/_20`.
Add or edit layouts in Settings, columns are written like `20/60/20` or `1:2:1`, or drag the
column edges in the blueprint preview (they snap to 5%). A typed spec is applied when you press `↩` or leave the
field, `esc` discards it, and the field explains what's wrong with an invalid spec.

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

### Command line

The `omw` CLI drives the running app from scripts, Shortcuts, Raycast, Alfred or a login item. Install it in
Settings → General → Command line, which links `/usr/local/bin/omw` to the copy inside omw.app (asks for an
admin password if needed), so it stays up to date with the app.

```sh
omw apply code                    # by name or ratios, like the launcher: "halves", "20/60", "1:2:1"
omw apply 20/60/20 --display 2    # display by number (see `omw displays`) or name
omw move left|right|up|down       # the focused window, like the hotkeys
omw move --display next|previous
omw move --space next|previous
omw refresh                       # place windows opened since the layout was applied
omw undo
omw layouts                       # name, ratios and id of every layout
omw displays
omw open                          # show the launcher
omw reload                        # re-read config.json
```

Exit codes: `0` done, `1` the command failed (unknown layout, no Accessibility access, no workspace in
that direction…), `2` wrong usage, `3` omw isn't running. Errors go to stderr.

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
make release VERSION=1.0.0   # universal build, Developer ID signing, notarization, Sparkle appcast
```

The output in `build/releases/1.0.0/` (the zip and `appcast.xml`) goes onto the GitHub release `v1.0.0`.
Installed copies find it through `SUFeedURL` and update themselves with [Sparkle](https://sparkle-project.org).
See [release-checklist.md](release-checklist.md) for the steps of a release.
