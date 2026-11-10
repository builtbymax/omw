import AppKit
import Combine
import OMWCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ConfigStore()
    private lazy var manager = WindowManager(store: store)
    private lazy var overlay = OverlayController(store: store, manager: manager) { [weak self] in self?.openSettings(id: $0) }
    private lazy var hud = HUDController(undo: { [weak self] in self?.manager.undo() },
                                         chooseLayout: { [weak self] in self?.overlay.show() })
    private lazy var remote = RemoteController(store: store, manager: manager, overlay: overlay)
    private lazy var dragTracker = DragTracker(store: store, manager: manager)
    private lazy var stackIndicator = StackIndicatorController(store: store, manager: manager)
    private lazy var columnResize = ColumnResizeController(store: store, manager: manager)
    /// The stack dots step aside while a window is dragged or columns are resized.
    private var draggingWindow = false, resizingColumns = false
    private let settingsNavigation = SettingsNavigation()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // ⌘-dragging the icon out of the menu bar turns the setting off too.
        statusItem.behavior = .removalAllowed
        store.$config
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] visible in self?.statusItem.isVisible = visible }
            .store(in: &subscriptions)
        statusItem.publisher(for: \.isVisible)
            .sink { [weak self] visible in
                guard let self, self.store.config.showMenuBarIcon != visible else { return }
                self.store.config.showMenuBarIcon = visible
            }
            .store(in: &subscriptions)

        store.$config
            .map(\.accent)
            .removeDuplicates()
            .sink { AccentPalette.shared.mode = $0 }
            .store(in: &subscriptions)

        HotkeyCenter.shared.reload = { [weak self] in
            guard let self else { return }
            self.registerHotkeys(self.store.config)
        }
        store.$config
            .removeDuplicates { Self.hotkeySignature($0) == Self.hotkeySignature($1) }
            .sink { [weak self] config in self?.registerHotkeys(config) }
            .store(in: &subscriptions)

        manager.onArranged = { [weak self] layout, count, screen, note in
            // A note says something didn't happen, so it shows even with the HUD off.
            guard let self, self.store.config.showHUD || note != nil else { return }
            self.hud.show(layout, count: count, note: note, on: screen)
        }

        manager.onWindowsMoved = { [weak self] in self?.stackIndicator.scheduleRefresh() }
        dragTracker.onDragging = { [weak self] dragging in
            guard let self else { return }
            self.draggingWindow = dragging
            self.columnResize.setSuppressed(dragging)
            self.stackIndicator.setSuspended(self.draggingWindow || self.resizingColumns)
        }
        columnResize.onNoLayout = { [weak self] screen in self?.showNoLayout(on: screen) }
        columnResize.onVisible = { [weak self] visible in
            guard let self else { return }
            self.resizingColumns = visible
            self.stackIndicator.setSuspended(self.draggingWindow || self.resizingColumns)
        }
        dragTracker.onMouseUp = { [weak self] in self?.stackIndicator.scheduleRefresh(after: 0.15) }
        store.$config
            .map { ($0.showStackIndicator, $0.stackIndicatorPosition) }
            .removeDuplicates(by: ==)
            .sink { [weak self] _ in self?.stackIndicator.scheduleRefresh(after: 0) }
            .store(in: &subscriptions)
        dragTracker.start()
        stackIndicator.start()
        columnResize.start()

        if !AX.isTrusted { AX.requestTrust() }
        Updater.shared.start()
        remote.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        remote.stop()
        dragTracker.stop()
        columnResize.stop()
    }

    /// Opening omw again from Finder, Spotlight or a launcher shows Settings, the way back when the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Hotkeys

    private static func hotkeySignature(_ config: Config) -> [String] {
        let global: [String] = ([config.overlayShortcut] + WindowCommand.allCases.map { config[keyPath: $0.keyPath] })
            .map { $0?.stringValue ?? "" }
        let layouts: [String] = config.layouts.map { "\($0.id):\($0.shortcut?.stringValue ?? "")" }
        let workspaces: [String] = config.workspaces.map { "\($0.id):\($0.shortcut?.stringValue ?? "")" }
        return global + layouts + workspaces
    }

    private func perform(_ command: WindowCommand) {
        if case let .noLayout(display) = manager.perform(command),
           let screen = NSScreen.screens.first(where: { $0.displayID == display }) {
            showNoLayout(on: screen)
        }
    }

    private func showNoLayout(on screen: NSScreen) {
        NSSound.beep()
        hud.showNoLayout(on: screen, shortcut: store.config.overlayShortcut)
    }

    private func registerHotkeys(_ config: Config) {
        let hotkeys = HotkeyCenter.shared
        hotkeys.unregisterAll()
        if let shortcut = config.overlayShortcut {
            hotkeys.register(shortcut) { [weak self] in self?.overlay.toggle() }
        }
        for command in WindowCommand.allCases {
            guard let shortcut = config[keyPath: command.keyPath] else { continue }
            hotkeys.register(shortcut) { [weak self] in self?.perform(command) }
        }
        for layout in config.layouts {
            guard let shortcut = layout.shortcut else { continue }
            let id = layout.id
            hotkeys.register(shortcut) { [weak self] in self?.applyLayout(id: id) }
        }
        for workspace in config.workspaces {
            guard let shortcut = workspace.shortcut else { continue }
            let id = workspace.id
            hotkeys.register(shortcut) { [weak self] in self?.applyWorkspace(id: id) }
        }
    }

    private func applyLayout(id: UUID) {
        if let layout = store.layout(id: id) { manager.apply(layout) }
    }

    private func applyWorkspace(id: UUID) {
        guard let workspace = store.workspace(id: id) else { return }
        if case .failure = manager.apply(workspace) { NSSound.beep() }
    }

    // MARK: Menu bar

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = store.config
        let activeID = manager.activeLayoutID(on: AX.targetScreen())
        let activeName = activeID.flatMap { store.layout(id: $0)?.name ?? store.workspace(containingLayout: $0)?.name }

        menu.addItem(hostingItem(MenuHeader(layoutName: activeName, trusted: AX.isTrusted)))
        menu.addItem(.separator())
        menu.addItem(hostingItem(QuickLayouts(layouts: config.layouts, activeID: activeID) { [weak self, weak menu] id in
            menu?.cancelTracking()
            DispatchQueue.main.async { self?.applyLayout(id: id) }
        }))
        if !config.workspaces.isEmpty {
            let workspaces = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
            workspaces.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
            workspaces.submenu = NSMenu()
            for workspace in config.workspaces {
                let id = workspace.id
                workspaces.submenu?.addItem(ClosureMenuItem(workspace.name, shortcut: workspace.shortcut) { [weak self] in self?.applyWorkspace(id: id) })
            }
            menu.addItem(workspaces)
        }
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("Open omw…", symbol: "magnifyingglass", shortcut: config.overlayShortcut) { [weak self] in self?.overlay.show() })
        let move = NSMenuItem(title: "Move Window", action: nil, keyEquivalent: "")
        move.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
        move.submenu = NSMenu()
        for (index, command) in WindowCommand.allCases.enumerated() {
            if index > 0, command.style != WindowCommand.allCases[index - 1].style { move.submenu?.addItem(.separator()) }
            let title = command.title.replacingOccurrences(of: "Move Window ", with: "").capitalizingFirstLetter
            move.submenu?.addItem(ClosureMenuItem(title, symbol: command.symbol, shortcut: config[keyPath: command.keyPath]) { [weak self] in
                self?.perform(command)
            })
        }
        menu.addItem(move)
        menu.addItem(ClosureMenuItem("Refresh Layout", symbol: "arrow.triangle.2.circlepath") { [weak self] in self?.manager.refresh() })
        if manager.canUndo {
            menu.addItem(ClosureMenuItem("Undo Last Arrange", symbol: "arrow.uturn.backward") { [weak self] in self?.manager.undo() })
        }
        menu.addItem(.separator())

        if !AX.isTrusted {
            menu.addItem(ClosureMenuItem("Grant Accessibility Access…", symbol: "accessibility") { AX.requestTrust() })
        }
        let login = ClosureMenuItem("Launch at Login", symbol: "power") { LaunchAtLogin.set(!LaunchAtLogin.isEnabled) }
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        let updater = Updater.shared
        if updater.isAvailable {
            let title = updater.pendingVersion.map { "Install Update (\($0))…" } ?? "Check for Updates…"
            menu.addItem(ClosureMenuItem(title, symbol: "arrow.down.circle") { updater.checkForUpdates() })
        }
        menu.addItem(ClosureMenuItem("Settings…", symbol: "gearshape", key: ",") { [weak self] in self?.openSettings() })
        menu.addItem(ClosureMenuItem("Quit omw", symbol: "rectangle.portrait.and.arrow.right", key: "q") { NSApp.terminate(nil) })
    }

    private func hostingItem(_ view: some View) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    /// Opens Settings, on the page of the layout or workspace with `id` if there is one.
    private func openSettings(id: UUID? = nil) {
        if let id, store.workspace(id: id) != nil {
            settingsNavigation.page = .workspaces
            settingsNavigation.workspaceID = id
        } else if let id {
            settingsNavigation.page = .layouts
            settingsNavigation.layoutID = id
        }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store, navigation: settingsNavigation) { [weak self] in self?.applyWorkspace(id: $0) })
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "omw Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // Off, so dragging in the layout editor doesn't drag the window. The title bar still moves it.
            window.isMovableByWindowBackground = false
            window.setContentSize(SettingsView.size)
            window.isReleasedWhenClosed = false
            // Settings follows you to the current Space instead of pulling you back to wherever it was last open.
            window.collectionBehavior = [.moveToActiveSpace]
            window.center()
            settingsWindow = window
        }
        guard let window = settingsWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        // Order the window in before activating: activating first can switch to the Space it was last shown on.
        window.orderFrontRegardless()
        // The launcher panel and the status menu don't activate omw, and the cooperative NSApp.activate()
        // is often refused then, leaving Settings behind the frontmost app. Force it.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The snap mark from the app icon, as a template image so it follows the menu bar's appearance.
    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // The mark's 56-unit artwork, scaled to 15 pt and centered.
            let scale: CGFloat = 15 / 56
            let path = NSBezierPath()
            for rotated in [false, true] {
                let mark = NSBezierPath()
                mark.move(to: NSPoint(x: 34, y: 0))
                mark.line(to: NSPoint(x: 10, y: 0))
                mark.appendArc(from: NSPoint(x: 0, y: 0), to: NSPoint(x: 0, y: 10), radius: 10)
                mark.line(to: NSPoint(x: 0, y: 34))
                mark.line(to: NSPoint(x: 10, y: 34))
                mark.line(to: NSPoint(x: 10, y: 12))
                mark.appendArc(from: NSPoint(x: 10, y: 10), to: NSPoint(x: 12, y: 10), radius: 2)
                mark.line(to: NSPoint(x: 34, y: 10))
                mark.close()
                if rotated {
                    // The bottom-right corner is the top-left one turned half way around.
                    mark.transform(using: AffineTransform(m11: -1, m12: 0, m21: 0, m22: -1, tX: 56, tY: 56))
                }
                path.append(mark)
            }
            path.transform(using: AffineTransform(scale: scale))
            path.transform(using: AffineTransform(translationByX: 1.5, byY: 1.5))
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "omw"
        return image
    }

    /// Menu-bar apps have no visible main menu, but text fields still need the Edit shortcuts.
    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit omw", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, key: String = "", shortcut: Shortcut? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        // Global shortcuts are shown like regular key equivalents, they only fire while the menu is open.
        if let shortcut, let equivalent = shortcut.menuKeyEquivalent {
            keyEquivalent = equivalent
            keyEquivalentModifierMask = shortcut.menuModifiers
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}

private extension Shortcut {
    var menuKeyEquivalent: String? {
        guard let name = keyName else { return nil }
        let special: [String: Int] = [
            "left": NSLeftArrowFunctionKey, "right": NSRightArrowFunctionKey,
            "up": NSUpArrowFunctionKey, "down": NSDownArrowFunctionKey,
        ]
        if let code = special[name], let scalar = UnicodeScalar(code) { return String(Character(scalar)) }
        if name == "space" { return " " }
        return name.count == 1 ? name : nil
    }

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & Shortcut.control != 0 { flags.insert(.control) }
        if modifiers & Shortcut.option != 0 { flags.insert(.option) }
        if modifiers & Shortcut.shift != 0 { flags.insert(.shift) }
        if modifiers & Shortcut.command != 0 { flags.insert(.command) }
        return flags
    }
}

// MARK: - Menu views

/// App icon, the active layout and whether omw can move windows.
private struct MenuHeader: View {
    let layoutName: String?
    let trusted: Bool

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("omw").font(.system(size: 13, weight: .bold))
                Text(trusted ? (layoutName.map { "\($0) is active" } ?? "No layout applied yet") : "Accessibility access needed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(trusted ? Theme.green : Color.orange)
                .frame(width: 7, height: 7)
                .shadow(color: (trusted ? Theme.green : Color.orange).opacity(0.9), radius: 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 300)
    }
}

/// One-click grid of layout icons.
private struct QuickLayouts: View {
    let layouts: [Layout]
    let activeID: UUID?
    let apply: (UUID) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
            ForEach(layouts) { layout in
                QuickLayoutButton(layout: layout, active: layout.id == activeID) { apply(layout.id) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(width: 300)
    }
}

private struct QuickLayoutButton: View {
    let layout: Layout
    let active: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                LayoutIcon(layout: layout, size: 30)
                    .scaleEffect(hovered ? 1.08 : 1)
                Text(layout.name.replacingOccurrences(of: "Main ", with: ""))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(active ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .selectedRow(active, hovered: hovered, cornerRadius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(layout.name)  \(layout.ratioLabel)")
        .onHover { hovering in withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { hovered = hovering } }
    }
}

private extension String {
    var capitalizingFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
