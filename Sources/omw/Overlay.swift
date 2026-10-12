import AppKit
import OMWCore
import SwiftUI

struct OverlayItem: Identifiable {
    enum Icon {
        case layout([Double])
        case symbol(String)
    }

    let id: String
    let title: String
    var badge: String?
    var keys: [String] = []
    let kind: String
    let icon: Icon
    let actionTitle: String
    let run: () -> Void

    var searchText: String { [title, badge ?? "", kind].joined(separator: " ") }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var query = "" {
        didSet { filter() }
    }
    @Published private(set) var results: [OverlayItem] = []
    @Published var selection = 0
    @Published private(set) var focusToken = 0
    @Published private(set) var status = ""

    private var items: [OverlayItem] = []
    var onRun: (OverlayItem) -> Void = { _ in }
    var onClose: () -> Void = {}

    var selected: OverlayItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    func reset(items: [OverlayItem], status: String) {
        self.items = items
        self.status = status
        query = ""
        filter()
        focusToken += 1
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func submit() {
        if let selected { onRun(selected) }
    }

    func cancel() {
        if query.isEmpty { onClose() } else { query = "" }
    }

    private func filter() {
        results = items.enumerated()
            .compactMap { index, item in Fuzzy.score(query, in: item.searchText).map { (item, $0, index) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
        selection = 0
    }
}

final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The ⌃⌥Space launcher. It's a non-activating panel, so the app you were in stays frontmost
/// and the layout gets applied to the desktop you're looking at.
@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    private let panel = OverlayPanel()
    private let model = OverlayModel()
    private let store: ConfigStore
    private let manager: WindowManager
    private let openSettings: () -> Void

    init(store: ConfigStore, manager: WindowManager, openSettings: @escaping () -> Void) {
        self.store = store
        self.manager = manager
        self.openSettings = openSettings
        super.init()

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        panel.delegate = self

        model.onClose = { [weak self] in self?.hide() }
        model.onRun = { [weak self] item in
            self?.hide()
            item.run()
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        let screen = AX.targetScreen() ?? NSScreen.main
        model.reset(items: items(activeLayoutID: manager.activeLayoutID(on: screen)), status: status(on: screen))

        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                         y: visible.maxY - visible.height * 0.2 - size.height))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func status(on screen: NSScreen?) -> String {
        guard AX.isTrusted else { return "Accessibility access needed" }
        guard let screen else { return "" }
        let count = AX.visibleWindows(on: screen).count
        return count == 1 ? "1 window on this display" : "\(count) windows on this display"
    }

    private func items(activeLayoutID: UUID?) -> [OverlayItem] {
        let layouts = store.config.layouts.map { layout in
            OverlayItem(
                id: layout.id.uuidString,
                title: layout.name,
                badge: layout.ratioLabel,
                keys: layout.shortcut?.displayKeys ?? [],
                kind: layout.id == activeLayoutID ? "Active Layout" : "Layout",
                icon: .layout(layout.fractions),
                actionTitle: "Apply Layout"
            ) { [weak self] in
                guard let self, let current = self.store.layout(id: layout.id) else { return }
                self.manager.apply(current)
            }
        }
        let commands = [
            OverlayItem(id: "settings", title: "Settings", kind: "Command", icon: .symbol("gearshape"),
                        actionTitle: "Open Settings", run: openSettings),
            OverlayItem(id: "quit", title: "Quit omw", kind: "Command", icon: .symbol("power"),
                        actionTitle: "Quit") { NSApp.terminate(nil) },
        ]
        return layouts + commands
    }
}

// MARK: - Views

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $model.query, focusToken: model.focusToken) { command in
                switch command {
                case .up: model.moveSelection(-1)
                case .down: model.moveSelection(1)
                case .submit: model.submit()
                case .cancel: model.cancel()
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 20)

            Divider().opacity(0.6)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.query.isEmpty ? "Layouts & Commands" : "Results")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                            OverlayRow(item: item, isSelected: index == model.selection)
                                .id(index)
                                .onTapGesture {
                                    model.selection = index
                                    model.submit()
                                }
                        }

                        if model.results.isEmpty {
                            Text("No matching layouts")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: model.selection) { _, selection in
                    proxy.scrollTo(selection)
                }
            }

            Divider().opacity(0.6)

            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.3x1")
                    .foregroundStyle(.secondary)
                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if let selected = model.selected {
                    Text(selected.actionTitle)
                        .font(.system(size: 12, weight: .medium))
                    Keycap("↩")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color.black.opacity(0.08))
        }
        .frame(width: 680, height: 420)
    }
}

private struct OverlayRow: View {
    let item: OverlayItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch item.icon {
                case .layout(let fractions): LayoutGlyph(fractions: fractions)
                case .symbol(let name): Image(systemName: name).font(.system(size: 14))
                }
            }
            .frame(width: 24, height: 18)

            Text(item.title)
                .font(.system(size: 14))

            if let badge = item.badge {
                Text(badge)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.4)))
            }

            HStack(spacing: 3) {
                ForEach(item.keys, id: \.self) { Keycap($0) }
            }

            Spacer()

            Text(item.kind)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.primary.opacity(0.1) : .clear)
        )
        .contentShape(Rectangle())
    }
}

/// Miniature of the layout's columns.
struct LayoutGlyph: View {
    let fractions: [Double]
    var spacing: CGFloat = 1.5

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.width - spacing * CGFloat(fractions.count - 1)
            HStack(spacing: spacing) {
                ForEach(fractions.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: max(1, available * fractions[index]))
                }
            }
        }
    }
}

struct Keycap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.1)))
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
        field.font = .systemFont(ofSize: 20)
        field.placeholderString = "Search layouts…"
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
