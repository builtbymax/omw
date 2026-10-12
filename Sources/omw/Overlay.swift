import AppKit
import OMWCore
import SwiftUI

struct OverlayItem: Identifiable {
    enum Icon {
        case layout(Layout)
        case tile(IconTile.Style)
    }

    enum Section: String {
        case layouts = "Layouts"
        case commands = "Commands"
    }

    let id: String
    let title: String
    var badge: String?
    var keys: [String] = []
    let section: Section
    let icon: Icon
    /// Shown in the preview pane for commands.
    var detail: String = ""
    var layout: Layout?
    let actionTitle: String
    let run: () -> Void

    var searchText: String { [title, badge ?? "", section == .layouts ? "layout" : "command"].joined(separator: " ") }
}

/// Something the ⌘K menu can do with the selected item.
struct OverlayAction: Identifiable {
    let id: String
    let title: String
    let style: IconTile.Style
    var keys: [String] = []
    let run: () -> Void
}

/// A window on the target display, as far as the preview needs to know.
struct PreviewWindow {
    let bundleID: String?
    let frame: CGRect
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var query = "" {
        didSet { filter() }
    }
    @Published private(set) var results: [OverlayItem] = []
    @Published var selection = 0 {
        didSet { if selection != oldValue { onSelectionChange() } }
    }
    @Published private(set) var focusToken = 0
    @Published private(set) var status = ""
    @Published private(set) var screenName = ""
    @Published private(set) var canSwitchScreen = false
    @Published private(set) var switchScreenKeys: [String] = []
    @Published private(set) var windows: [PreviewWindow] = []
    @Published private(set) var area: CGRect = .zero
    @Published private(set) var activeLayoutID: UUID?
    @Published var actionsVisible = false
    @Published var actionSelection = 0

    private var items: [OverlayItem] = []
    var onRun: (OverlayItem) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onSelectionChange: () -> Void = {}
    var onSwitchScreen: () -> Void = {}
    var actionsFor: (OverlayItem) -> [OverlayAction] = { _ in [] }

    var selected: OverlayItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    var actions: [OverlayAction] {
        selected.map(actionsFor) ?? []
    }

    func reset(items: [OverlayItem]) {
        self.items = items
        actionsVisible = false
        query = ""
        filter()
        focusToken += 1
    }

    func update(items: [OverlayItem]) {
        let selectedID = selected?.id
        self.items = items
        filter()
        if let index = results.firstIndex(where: { $0.id == selectedID }) { selection = index }
    }

    func setTarget(screenName: String, canSwitch: Bool, switchKeys: [String], windows: [PreviewWindow], area: CGRect,
                   activeLayoutID: UUID?, status: String) {
        self.screenName = screenName
        canSwitchScreen = canSwitch
        switchScreenKeys = switchKeys
        self.windows = windows
        self.area = area
        self.activeLayoutID = activeLayoutID
        self.status = status
    }

    func moveSelection(_ delta: Int) {
        if actionsVisible {
            let count = actions.count
            if count > 0 { actionSelection = (actionSelection + delta + count) % count }
            return
        }
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func submit() {
        if actionsVisible {
            let actions = actions
            actionsVisible = false
            if actions.indices.contains(actionSelection) { actions[actionSelection].run() }
            return
        }
        if let selected { onRun(selected) }
    }

    func cancel() {
        if actionsVisible {
            actionsVisible = false
        } else if query.isEmpty {
            onClose()
        } else {
            query = ""
        }
    }

    func toggleActions() {
        guard selected != nil else { return }
        actionSelection = 0
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { actionsVisible.toggle() }
    }

    private func filter() {
        results = items.enumerated()
            .compactMap { index, item in Fuzzy.score(query, in: item.searchText).map { (item, $0, index) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
        selection = 0
        onSelectionChange()
    }
}

final class OverlayPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Wraps SwiftUI content in a rounded glass background: NSGlassEffectView on macOS 26+,
/// a HUD material before that.
@MainActor
func glassContainer(for content: NSView, cornerRadius: CGFloat) -> NSView {
    if #available(macOS 26, *) {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.tintColor = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.11, alpha: 0.55)
        glass.contentView = content
        // Without a mask the panel's square corners show up dark behind the rounded glass.
        glass.wantsLayer = true
        glass.layer?.cornerRadius = cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        return glass
    }
    let background = NSVisualEffectView()
    background.material = .hudWindow
    background.blendingMode = .behindWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = cornerRadius
    background.layer?.cornerCurve = .continuous
    background.layer?.masksToBounds = true
    background.layer?.borderWidth = 1
    background.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
    content.translatesAutoresizingMaskIntoConstraints = false
    background.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        content.topAnchor.constraint(equalTo: background.topAnchor),
        content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
    ])
    return background
}

/// The ⌃⌥Space launcher. It's a non-activating panel, so the app you were in stays frontmost
/// and the layout gets applied to the desktop you're looking at.
@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 840, height: 540)

    private let panel = OverlayPanel(size: OverlayController.size)
    private let model = OverlayModel()
    private let ghost = GhostColumnsController()
    private let store: ConfigStore
    private let manager: WindowManager
    private let openSettings: (UUID?) -> Void
    private var screen: NSScreen?
    private var keyMonitor: Any?

    init(store: ConfigStore, manager: WindowManager, openSettings: @escaping (UUID?) -> Void) {
        self.store = store
        self.manager = manager
        self.openSettings = openSettings
        super.init()

        let hosting = NSHostingView(rootView: OverlayView(model: model))
        panel.contentView = glassContainer(for: hosting, cornerRadius: 26)
        panel.delegate = self

        model.onClose = { [weak self] in self?.hide() }
        model.onRun = { [weak self] item in
            self?.hide()
            item.run()
        }
        model.onSelectionChange = { [weak self] in self?.updateGhost() }
        model.onSwitchScreen = { [weak self] in self?.switchScreen() }
        model.actionsFor = { [weak self] item in self?.actions(for: item) ?? [] }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        screen = AX.targetScreen() ?? NSScreen.main
        loadTarget()
        model.reset(items: items())

        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                         y: visible.maxY - visible.height * 0.16 - size.height))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        updateGhost()
        installKeyMonitor()
    }

    func hide() {
        ghost.hide()
        panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// ⌘K and friends, which the search field doesn't see as commands.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if let shortcut = self.store.config.switchDisplayShortcut, Shortcut(event: event) == shortcut {
                self.switchScreen()
                return nil
            }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return event }
            switch event.charactersIgnoringModifiers {
            case "k": self.model.toggleActions()
            case "e":
                guard let id = self.model.selected?.layout?.id else { return event }
                self.hide()
                self.openSettings(id)
            case ",":
                self.hide()
                self.openSettings(nil)
            default: return event
            }
            return nil
        }
    }

    private func switchScreen() {
        let screens = NSScreen.screens
        guard screens.count > 1, let current = screen, let index = screens.firstIndex(of: current) else { return }
        screen = screens[(index + 1) % screens.count]
        loadTarget()
        model.update(items: items())
        updateGhost()
    }

    private func loadTarget() {
        guard let screen else { return }
        let trusted = AX.isTrusted
        let windows = trusted ? AX.visibleWindows(on: screen).map { PreviewWindow(bundleID: $0.bundleID, frame: $0.frame) } : []
        let status: String
        if !trusted {
            status = "Accessibility access needed"
        } else {
            status = windows.count == 1 ? "1 window on this display" : "\(windows.count) windows on this display"
        }
        model.setTarget(screenName: screen.localizedName, canSwitch: NSScreen.screens.count > 1,
                        switchKeys: store.config.switchDisplayShortcut?.displayKeys ?? [], windows: windows,
                        area: screen.axVisibleFrame, activeLayoutID: manager.activeLayoutID(on: screen), status: status)
    }

    private func updateGhost() {
        guard panel.isVisible, let screen, let layout = model.selected?.layout, !model.actionsVisible else {
            ghost.hide()
            return
        }
        ghost.show(layout, on: screen, gap: store.config.gap, below: panel)
    }

    private func apply(_ id: UUID) {
        guard let layout = store.layout(id: id) else { return }
        manager.apply(layout, on: screen)
    }

    private func actions(for item: OverlayItem) -> [OverlayAction] {
        var actions: [OverlayAction] = []
        if let layout = item.layout {
            let id = layout.id
            actions.append(OverlayAction(id: "apply", title: "Apply Layout", style: .layouts, keys: ["↩"]) { [weak self] in
                self?.hide()
                self?.apply(id)
            })
            actions.append(OverlayAction(id: "edit", title: "Edit Layout…", style: .general, keys: ["⌘", "E"]) { [weak self] in
                self?.hide()
                self?.openSettings(id)
            })
        } else {
            actions.append(OverlayAction(id: "run", title: item.actionTitle, style: .general, keys: ["↩"]) { [weak self] in
                self?.hide()
                item.run()
            })
        }
        if manager.canUndo {
            actions.append(OverlayAction(id: "undo", title: "Undo Last Arrange", style: .undo) { [weak self] in
                self?.hide()
                self?.manager.undo()
            })
        }
        actions.append(OverlayAction(id: "settings", title: "Open Settings", style: .general, keys: ["⌘", ","]) { [weak self] in
            self?.hide()
            self?.openSettings(nil)
        })
        return actions
    }

    private func items() -> [OverlayItem] {
        let config = store.config
        let layouts = config.layouts.map { layout in
            OverlayItem(
                id: layout.id.uuidString,
                title: layout.name,
                badge: layout.ratioLabel,
                keys: layout.shortcut?.displayKeys ?? [],
                section: .layouts,
                icon: .layout(layout),
                layout: layout,
                actionTitle: "Apply Layout"
            ) { [weak self] in self?.apply(layout.id) }
        }
        var commands = WindowCommand.allCases.map { command in
            OverlayItem(id: command.rawValue, title: command.title, keys: config[keyPath: command.keyPath]?.displayKeys ?? [],
                        section: .commands, icon: .tile(command.style), detail: command.detail,
                        actionTitle: "Move Window") { [weak self] in self?.manager.perform(command) }
        }
        if manager.canUndo {
            commands.append(OverlayItem(id: "undo", title: "Undo Last Arrange", section: .commands, icon: .tile(.undo),
                                        detail: "Puts the windows back where they were before the last layout was applied.",
                                        actionTitle: "Undo") { [weak self] in self?.manager.undo() })
        }
        commands += [
            OverlayItem(id: "settings", title: "Settings…", keys: ["⌘", ","], section: .commands, icon: .tile(.general),
                        detail: "Layouts, shortcuts, gaps and startup options.",
                        actionTitle: "Open Settings") { [weak self] in self?.openSettings(nil) },
            OverlayItem(id: "quit", title: "Quit omw", section: .commands, icon: .tile(.quit),
                        detail: "Stops omw and frees its shortcuts.", actionTitle: "Quit") { NSApp.terminate(nil) },
        ]
        return layouts + commands
    }
}

// MARK: - Views

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                resultList
                Divider().opacity(0.5)
                PreviewPane(model: model)
                    .frame(width: 310)
                    .background(Color.black.opacity(0.12))
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: OverlayController.size.width, height: OverlayController.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if model.actionsVisible {
                ActionsMenu(model: model)
                    .padding(.trailing, 12)
                    .padding(.bottom, 54)
                    .transition(.scale(scale: 0.95, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            SearchField(text: $model.query, focusToken: model.focusToken) { command in
                switch command {
                case .up: model.moveSelection(-1)
                case .down: model.moveSelection(1)
                case .submit: model.submit()
                case .cancel: model.cancel()
                }
            }
            if !model.screenName.isEmpty {
                if model.canSwitchScreen && !model.switchScreenKeys.isEmpty {
                    Keycaps(keys: model.switchScreenKeys)
                }
                Button { model.onSwitchScreen() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "display").font(.system(size: 11))
                        Text(model.screenName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if model.canSwitchScreen {
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Theme.rim(0.2, 0.04)))
                }
                .buttonStyle(.hoverable(scale: 1.04))
                .disabled(!model.canSwitchScreen)
                .help(model.canSwitchScreen ? "Switch the display the layout is applied to" : "Target display")
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .frame(height: 62)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sections, id: \.title) { section in
                        SectionLabel(section.title)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(section.indices, id: \.self) { index in
                            let item = model.results[index]
                            Button {
                                model.selection = index
                                model.submit()
                            } label: {
                                OverlayRow(item: item, isSelected: index == model.selection,
                                           isActive: item.layout != nil && item.layout?.id == model.activeLayoutID)
                            }
                            .buttonStyle(PressableRowStyle())
                            .id(index)
                        }
                    }

                    if model.results.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "rectangle.dashed").font(.system(size: 28)).opacity(0.4)
                            Text("No matching layouts or commands").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .onChange(of: model.selection) { _, selection in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(selection) }
            }
        }
    }

    /// Results grouped by section, keeping their flat index for selection.
    private var sections: [(title: String, indices: [Int])] {
        if !model.query.isEmpty { return [("Results", Array(model.results.indices))] }
        let layouts = model.results.indices.filter { model.results[$0].section == .layouts }
        let commands = model.results.indices.filter { model.results[$0].section == .commands }
        return [("Layouts", layouts), ("Commands", commands)].filter { !$0.1.isEmpty }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            AppIconView(size: 22)
            Text("omw").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            Text("·  \(model.status)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
            Spacer()
            if let selected = model.selected {
                Button(selected.actionTitle) { model.submit() }
                    .buttonStyle(.glassCapsule(.primary))
                Keycap("↩")
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 18)
                Button("Actions") { model.toggleActions() }
                    .buttonStyle(.glassCapsule(.ghost))
                Keycaps(keys: ["⌘", "K"])
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 50)
        .background(Color.white.opacity(0.03))
    }
}

private struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct OverlayRow: View {
    let item: OverlayItem
    let isSelected: Bool
    let isActive: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            switch item.icon {
            case .layout(let layout): LayoutIcon(layout: layout, size: 28)
            case .tile(let style): IconTile(style: style, size: 28)
            }

            Text(item.title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.88))

            if let badge = item.badge { RatioPill(text: badge) }

            Spacer(minLength: 8)

            if isActive { StatusBadge(text: "Active") }
            Keycaps(keys: item.keys)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .selectedRow(isSelected, hovered: hovered)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { hovered = hovering } }
    }
}

/// Right-hand pane: what the selected layout does to the windows on this display.
private struct PreviewPane: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item = model.selected {
                if let layout = item.layout {
                    layoutPreview(layout)
                } else {
                    commandPreview(item)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .animation(.easeOut(duration: 0.15), value: model.selected?.id)
    }

    @ViewBuilder
    private func layoutPreview(_ layout: Layout) -> some View {
        let windows = model.windows.filter { layout.arranges(appID: $0.bundleID) }
        let assignment = Arranger.assign(windows.map { WindowSnapshot(appID: $0.bundleID, frame: $0.frame) },
                                         layout: layout, in: model.area, pinned: true, balanced: true)
        let cells = (0..<layout.cellCount).map { cell in
            assignment.indices.filter { assignment[$0] == cell }.map { windows[$0].bundleID }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(layout.name).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            Text(summary(layout))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }

        DisplayPreview(fractions: layout.fractions, rows: layout.rowCounts, cells: cells)
            .frame(height: 168)

        // Scrolls when many windows wrap onto lots of chip rows, instead of growing the pane past the panel.
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(cells.indices, id: \.self) { cell in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Int((layout.fractions[layout.cells[cell].column] * 100).rounded()))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.45))
                            if let row = layout.rowName(of: cell) {
                                Text(row).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .frame(width: 40, alignment: .leading)
                        .padding(.top, 3)
                        FlowChips(bundleIDs: cells[cell])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func summary(_ layout: Layout) -> String {
        var parts = ["\(layout.columnCount) column\(layout.columnCount == 1 ? "" : "s")"]
        if layout.cellCount != layout.columnCount { parts[0] += ", \(layout.cellCount) cell\(layout.cellCount == 1 ? "" : "s")" }
        let moved = model.windows.filter { layout.arranges(appID: $0.bundleID) }.count
        if !model.windows.isEmpty { parts.append("\(moved) window\(moved == 1 ? "" : "s")") }
        let pinned = layout.pins.keys.map { AppIdentity(bundleID: $0).name }.sorted()
        if !pinned.isEmpty { parts.append("\(pinned.joined(separator: ", ")) pinned") }
        if layout.pinnedOnly { parts.append("other windows stay") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func commandPreview(_ item: OverlayItem) -> some View {
        if case .tile(let style) = item.icon { IconTile(style: style, size: 44) }
        Text(item.title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
        Text(item.detail)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
        if !item.keys.isEmpty { Keycaps(keys: item.keys) }
    }
}

/// Miniature display with the layout's cells and one app tile per window.
private struct DisplayPreview: View {
    let fractions: [Double]
    let rows: [Int]
    /// Apps per cell, column by column.
    let cells: [[String?]]

    var body: some View {
        GeometryReader { geometry in
            let pad: CGFloat = 6, gap: CGFloat = 4
            let available = geometry.size.width - pad * 2 - gap * CGFloat(fractions.count - 1)
            HStack(spacing: gap) {
                ForEach(fractions.indices, id: \.self) { column in
                    let count = rows.indices.contains(column) ? rows[column] : 1
                    let first = rows.prefix(column).reduce(0, +)
                    let cellHeight = (geometry.size.height - pad * 2 - gap * CGFloat(count - 1)) / CGFloat(max(1, count))
                    VStack(spacing: gap) {
                        ForEach(0..<count, id: \.self) { row in
                            cell(cells.indices.contains(first + row) ? cells[first + row] : [], height: cellHeight, gap: gap)
                        }
                    }
                    .frame(width: max(1, available * fractions[column]))
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(pad)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1E4FD8), Color(hex: 0x5B2BB5)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.rim(0.35, 0.1)))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: fractions)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: rows)
    }

    /// As many tiles as fit at a readable height, the rest collapse into a "+N" tile. A cell with room
    /// for only one tile shows the front app with a "+N" badge.
    @ViewBuilder
    private func cell(_ apps: [String?], height: CGFloat, gap: CGFloat) -> some View {
        let fitting = max(1, Int((height + gap) / (MiniWindow.minHeight + gap)))
        let shown = apps.count > fitting ? fitting - 1 : apps.count
        VStack(spacing: gap) {
            if apps.isEmpty {
                MiniWindow(bundleID: nil)
            } else if shown == 0 {
                MiniWindow(bundleID: apps[0], more: apps.count - 1)
            } else {
                ForEach(0..<shown, id: \.self) { MiniWindow(bundleID: apps[$0]) }
                if shown < apps.count { MiniWindow(bundleID: nil, more: apps.count - shown) }
            }
        }
    }
}

private struct MiniWindow: View {
    static let minHeight: CGFloat = 24

    let bundleID: String?
    /// Number of windows this tile stands in for when the cell has no room for all of them.
    var more = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let empty = bundleID == nil && more == 0
        ZStack(alignment: .top) {
            shape.fill(LinearGradient(colors: [.white.opacity(empty ? 0.18 : 0.9), Color(hex: 0xE6F0FF, opacity: empty ? 0.08 : 0.7)],
                                      startPoint: .top, endPoint: .bottom))
            if let bundleID, let icon = AppIdentity(bundleID: bundleID).icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    .frame(maxHeight: .infinity)
            } else if more > 0 {
                Text("+\(more)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x1E4FD8))
                    .frame(maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if bundleID != nil, more > 0 {
                Text("+\(more)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(Color(hex: 0x1E4FD8)))
                    .padding(3)
            }
        }
        .overlay(shape.strokeBorder(.white.opacity(empty ? 0.35 : 0.8), style: StrokeStyle(lineWidth: 0.75, dash: empty ? [3, 3] : [])))
        .shadow(color: .black.opacity(empty ? 0 : 0.25), radius: 3, y: 2)
    }
}

/// App chips that wrap onto new lines.
private struct FlowChips: View {
    let bundleIDs: [String?]

    var body: some View {
        if bundleIDs.isEmpty {
            Text("empty").font(.system(size: 11)).foregroundStyle(.white.opacity(0.3)).padding(.top, 3)
        } else {
            WrapLayout(spacing: 5) {
                ForEach(bundleIDs.indices, id: \.self) { index in
                    let app = AppIdentity(bundleID: bundleIDs[index])
                    HStack(spacing: 5) {
                        if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 13, height: 13) }
                        Text(app.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.leading, 5)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.07)))
                }
            }
        }
    }
}

/// Simple left-to-right wrapping layout.
struct WrapLayout: SwiftUI.Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// The ⌘K menu, Raycast style.
private struct ActionsMenu: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        let actions = model.actions
        VStack(alignment: .leading, spacing: 2) {
            if let title = model.selected?.title {
                SectionLabel(title).padding(.horizontal, 10).padding(.vertical, 6)
            }
            ForEach(actions.indices, id: \.self) { index in
                let action = actions[index]
                Button {
                    model.actionSelection = index
                    model.submit()
                } label: {
                    HStack(spacing: 10) {
                        IconTile(style: action.style, size: 22)
                        Text(action.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        Spacer(minLength: 16)
                        Keycaps(keys: action.keys)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .selectedRow(index == model.actionSelection, cornerRadius: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableRowStyle())
            }
        }
        .padding(6)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x1A1E2B, opacity: 0.92)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.rim(0.28, 0.08)))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }
}

/// AppKit text field so arrow keys, return and escape can drive the list.
struct SearchField: NSViewRepresentable {
    enum Command { case up, down, submit, cancel }

    @Binding var text: String
    let focusToken: Int
    let onCommand: (Command) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: "Search layouts and commands…",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.38), .font: NSFont.systemFont(ofSize: 20)]
        )
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var focusToken = -1

        init(parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onCommand(.up)
            case #selector(NSResponder.moveDown(_:)): parent.onCommand(.down)
            case #selector(NSResponder.insertNewline(_:)): parent.onCommand(.submit)
            case #selector(NSResponder.cancelOperation(_:)): parent.onCommand(.cancel)
            default: return false
            }
            return true
        }
    }
}
