import AppKit
import Combine
import OMWCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ConfigStore()
    private lazy var manager = WindowManager(store: store)
    private lazy var overlay = OverlayController(store: store, manager: manager) { [weak self] in self?.openSettings() }
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "omw")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        HotkeyCenter.shared.reload = { [weak self] in
            guard let self else { return }
            self.registerHotkeys(self.store.config)
        }
        store.$config
            .removeDuplicates { Self.hotkeySignature($0) == Self.hotkeySignature($1) }
            .sink { [weak self] config in self?.registerHotkeys(config) }
            .store(in: &subscriptions)

        if !AX.isTrusted { AX.requestTrust() }
    }

    // MARK: Hotkeys

    private static func hotkeySignature(_ config: Config) -> [String] {
        [config.overlayShortcut, config.moveLeftShortcut, config.moveRightShortcut].map { $0?.stringValue ?? "" }
            + config.layouts.map { "\($0.id):\($0.shortcut?.stringValue ?? "")" }
    }

    private func registerHotkeys(_ config: Config) {
        let hotkeys = HotkeyCenter.shared
        hotkeys.unregisterAll()
        if let shortcut = config.overlayShortcut {
            hotkeys.register(shortcut) { [weak self] in self?.overlay.toggle() }
        }
        if let shortcut = config.moveLeftShortcut {
            hotkeys.register(shortcut) { [weak self] in self?.manager.moveFocused(by: -1) }
        }
        if let shortcut = config.moveRightShortcut {
            hotkeys.register(shortcut) { [weak self] in self?.manager.moveFocused(by: 1) }
        }
        for layout in config.layouts {
            guard let shortcut = layout.shortcut else { continue }
            let id = layout.id
            hotkeys.register(shortcut) { [weak self] in self?.applyLayout(id: id) }
        }
    }

    private func applyLayout(id: UUID) {
        if let layout = store.layout(id: id) { manager.apply(layout) }
    }

    // MARK: Menu bar

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = ClosureMenuItem("Open omw") { [weak self] in self?.overlay.show() }
        if let shortcut = store.config.overlayShortcut { open.title += "    \(shortcut.displayString)" }
        menu.addItem(open)
        menu.addItem(.separator())

        for layout in store.config.layouts {
            let id = layout.id
            let item = ClosureMenuItem("\(layout.name)  (\(layout.ratioLabel))") { [weak self] in self?.applyLayout(id: id) }
            item.state = layout.id == manager.activeLayoutID(on: AX.targetScreen()) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if !AX.isTrusted {
            menu.addItem(ClosureMenuItem("Grant Accessibility Access…") { AX.requestTrust() })
        }
        let login = ClosureMenuItem("Launch at Login") { LaunchAtLogin.set(!LaunchAtLogin.isEnabled) }
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [weak self] in self?.openSettings() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit omw", key: "q") { NSApp.terminate(nil) })
    }

    private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            window.title = "omw Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
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

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
