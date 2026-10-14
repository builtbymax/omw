import AppKit
import OMWCore
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, layouts, shortcuts, about

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var style: IconTile.Style {
        switch self {
        case .general: .general
        case .layouts: .layouts
        case .shortcuts: .shortcuts
        case .about: .about
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Startup, permissions, spacing and the config file."
        case .layouts: "Columns, shortcuts and preferred columns per layout."
        case .shortcuts: "Global shortcuts and one per layout."
        case .about: "oh my windows"
        }
    }

    /// Extra words the sidebar search matches.
    var keywords: String {
        switch self {
        case .general: "launch login startup accessibility permission gap spacing animate animation confirmation hud config file finder"
        case .layouts: "columns ratio preferred pin apps"
        case .shortcuts: "hotkey keyboard open move window left right"
        case .about: "version info"
        }
    }
}

/// Which page Settings shows, so the launcher can jump straight to a layout.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .general
    @Published var layoutID: UUID?
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var navigation: SettingsNavigation
    @State private var search = ""

    static let size = CGSize(width: 900, height: 640)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .padding(10)

            Group {
                switch navigation.page {
                case .general: GeneralSettings(store: store)
                case .layouts: LayoutSettings(store: store, selection: $navigation.layoutID)
                case .shortcuts: ShortcutSettings(store: store)
                case .about: AboutSettings(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: Self.size.width, maxWidth: .infinity, minHeight: Self.size.height, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(
            LinearGradient(colors: [Theme.tileBottom.opacity(0.06), .clear, Color(hex: 0x7C3AED, opacity: 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var pages: [SettingsPage] {
        guard !search.isEmpty else { return SettingsPage.allCases }
        return SettingsPage.allCases.filter { Fuzzy.score(search, in: "\($0.title) \($0.keywords)") != nil }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            .padding(.bottom, 10)

            ForEach(pages) { page in
                let selected = navigation.page == page
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { navigation.page = page }
                } label: {
                    HStack(spacing: 10) {
                        IconTile(style: page.style, size: 24)
                        Text(page.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                        Spacer()
                        if page == .layouts {
                            Text("\(store.config.layouts.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .selectedRow(selected, cornerRadius: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if pages.isEmpty {
                Text("No results").font(.system(size: 12)).foregroundStyle(.secondary).padding(8)
            }

            Spacer()

            HStack(spacing: 10) {
                AppIconView(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("omw \(AboutSettings.version)").font(.system(size: 12, weight: .semibold))
                    Text("oh my windows").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.05)))
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .glassSurface(cornerRadius: 18)
        .padding(.top, 30) // the traffic lights sit above the sidebar
    }
}

// MARK: - Building blocks

private struct PageHeader<Trailing: View>: View {
    let page: SettingsPage
    var title: String?
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconTile(style: page.style, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? page.title).font(.system(size: 20, weight: .bold))
                Text(subtitle ?? page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(page: SettingsPage) {
        self.init(page: page) { EmptyView() }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionLabel(title).padding(.leading, 4) }
            VStack(spacing: 0) { content }
                .glassCard()
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var monoSubtitle = false
    var divider = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            if divider {
                Rectangle().fill(.primary.opacity(0.07)).frame(height: 1).padding(.leading, 14)
            }
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, design: monoSubtitle ? .monospaced : .default))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
        }
    }
}

extension SettingsRow where Leading == IconTile {
    init(_ style: IconTile.Style, _ title: String, subtitle: String? = nil, monoSubtitle: Bool = false, divider: Bool = true,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, monoSubtitle: monoSubtitle, divider: divider,
                  leading: { IconTile(style: style, size: 26) }, trailing: trailing)
    }
}

/// Plain text field on a dark inset, for the layout's name and columns.
private struct InsetField: View {
    @Binding var text: String
    var prompt = ""
    var mono = false
    var invalid = false

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: mono ? .monospaced : .default))
            .multilineTextAlignment(.trailing)
            .foregroundStyle(invalid ? Color.red : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: 180)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(invalid ? Color.red.opacity(0.6) : .primary.opacity(0.1)))
    }
}

private struct ScrollPage<Content: View>: View {
    var leading: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.leading, leading)
                .padding(.trailing, 28)
                .padding(.top, 22)
                .padding(.bottom, 28)
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var updater = Updater.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var trusted = AX.isTrusted
    @State private var reloaded = false
    @State private var reloadError: String?

    var body: some View {
        ScrollPage {
            PageHeader(page: .general)

            SettingsSection(title: "Startup") {
                SettingsRow(.login, "Launch at login", subtitle: "Start omw quietly in the menu bar.", divider: false) {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                        .onChange(of: launchAtLogin) { _, enabled in
                            LaunchAtLogin.set(enabled)
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                }
                SettingsRow(.menuBar, "Show in menu bar", subtitle: menuBarSubtitle) {
                    Toggle("", isOn: $store.config.showMenuBarIcon).toggleStyle(.switch).labelsHidden()
                }
                SettingsRow(.accessibility, "Accessibility", subtitle: "Needed to move and resize windows.") {
                    if trusted {
                        StatusBadge(text: "Granted", color: Theme.green, textColor: Color(hex: 0x4ADE80))
                    } else {
                        Button("Grant Access…") { AX.requestTrust() }.buttonStyle(.glassCapsule(.primary))
                    }
                }
            }

            SettingsSection(title: "Windows") {
                SettingsRow(.windows, "Gap between windows", subtitle: "Space around and between columns.", divider: false) {
                    GapPicker(gap: $store.config.gap)
                }
                SettingsRow(.move, "Animate windows", subtitle: "Glide windows into their columns.") {
                    Toggle("", isOn: $store.config.animate).toggleStyle(.switch).labelsHidden()
                }
                SettingsRow(.undo, "Show confirmation", subtitle: "\u{201C}Arranged N windows\u{201D} with Undo after applying a layout.") {
                    Toggle("", isOn: $store.config.showHUD).toggleStyle(.switch).labelsHidden()
                }
                SettingsRow(.display, "Open launcher on primary display", subtitle: "Instead of the display with the focused window.") {
                    Toggle("", isOn: $store.config.launcherOnPrimaryDisplay).toggleStyle(.switch).labelsHidden()
                }
            }

            if updater.isAvailable {
                SettingsSection(title: "Updates") {
                    SettingsRow(.update, "Check for updates automatically", subtitle: "Version \(AboutSettings.version)", divider: false) {
                        HStack(spacing: 10) {
                            Button("Check Now") { updater.checkForUpdates() }.buttonStyle(.glassCapsule(.secondary))
                            Toggle("", isOn: $updater.automaticallyChecks).toggleStyle(.switch).labelsHidden()
                        }
                    }
                }
            }

            SettingsSection(title: "Configuration") {
                SettingsRow(.config, "Config file", subtitle: store.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                            monoSubtitle: true, divider: false) {
                    HStack(spacing: 8) {
                        Button { reloadConfig() } label: {
                            Image(systemName: reloaded ? "checkmark" : "arrow.clockwise")
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 14)
                        }
                        .buttonStyle(.glassCapsule(.secondary))
                        .help("Reload config")
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.url]) }
                            .buttonStyle(.glassCapsule(.secondary))
                    }
                }
            }
        }
        .alert("Could not reload config", isPresented: Binding(get: { reloadError != nil }, set: { if !$0 { reloadError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(reloadError ?? "")\n\nYour current settings are unchanged.")
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = AX.isTrusted
        }
    }
}

private extension GeneralSettings {
    var menuBarSubtitle: String {
        if store.config.showMenuBarIcon { return "Quick access to layouts and settings." }
        let launcher = store.config.overlayShortcut.map { "the launcher (\($0.displayString) → ⌘,)" } ?? "the launcher"
        return "Open Settings via \(launcher) or by opening omw again."
    }

    func reloadConfig() {
        do {
            try store.reload()
            withAnimation { reloaded = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { reloaded = false }
            }
        } catch let error as DecodingError {
            reloadError = error.configMessage
        } catch {
            reloadError = error.localizedDescription
        }
    }
}

/// Segmented glass control for the window gap. Values outside the presets get their own segment.
private struct GapPicker: View {
    @Binding var gap: Double
    @Namespace private var knob

    private var options: [Double] {
        let presets: [Double] = [0, 4, 8, 12, 16]
        return presets.contains(gap) ? presets : (presets + [gap]).sorted()
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { value in
                let selected = value == gap
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { gap = value }
                } label: {
                    Text("\(Int(value)) pt")
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .fixedSize()
                        .foregroundStyle(selected ? Color.primary : .secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(LinearGradient(colors: [.primary.opacity(0.22), .primary.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                                    .overlay(Capsule().strokeBorder(Theme.rim(0.4, 0.08)))
                                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "knob", in: knob)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.black.opacity(0.2)))
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var hotkeys = HotkeyCenter.shared

    var body: some View {
        ScrollPage {
            PageHeader(page: .shortcuts)

            SettingsSection(title: "Global", footer: "A warning sign means another app already uses that shortcut.") {
                row(.search, "Open omw", \.overlayShortcut, divider: false)
            }

            SettingsSection(title: "Windows",
                            footer: "Moving to another workspace uses the Mission Control shortcuts \u{201C}Move left/right a space\u{201D} (⌃← / ⌃→), keep them enabled in System Settings → Keyboard → Keyboard Shortcuts.") {
                ForEach(WindowCommand.allCases) { command in
                    row(command.style, command.title.prefix(1) + command.title.dropFirst().lowercased(), command.keyPath,
                        divider: command != WindowCommand.allCases.first)
                }
            }

            SettingsSection(title: "Launcher", footer: "Only active while the launcher is open.") {
                SettingsRow(.display, "Switch display", subtitle: "Pick the display a layout is applied to.", divider: false) {
                    ShortcutRecorder(shortcut: $store.config.switchDisplayShortcut)
                }
            }

            SettingsSection(title: "Layouts") {
                ForEach($store.config.layouts) { $layout in
                    SettingsRow(title: layout.name, subtitle: layout.ratioLabel, monoSubtitle: true,
                                divider: layout.id != store.config.layouts.first?.id) {
                        LayoutIcon(layout: layout, size: 26)
                    } trailing: {
                        ShortcutRecorder(shortcut: $layout.shortcut, isTaken: layout.shortcut.map(hotkeys.failed.contains) ?? false)
                    }
                }
            }
        }
    }

    private func row(_ style: IconTile.Style, _ title: String, _ keyPath: WritableKeyPath<Config, Shortcut?>, divider: Bool = true) -> some View {
        SettingsRow(style, title, divider: divider) {
            ShortcutRecorder(shortcut: $store.config[dynamicMember: keyPath],
                             isTaken: store.config[keyPath: keyPath].map(hotkeys.failed.contains) ?? false)
        }
    }
}

// MARK: - Layouts

private struct LayoutSettings: View {
    @ObservedObject var store: ConfigStore
    @Binding var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Layouts").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button { add() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.primary.opacity(0.1)))
                            .overlay(Circle().strokeBorder(Theme.rim(0.28, 0.06)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.hoverable)
                    .focusEffectDisabled()
                    .help("New layout")
                }
                .padding(.leading, 6)
                .padding(.bottom, 10)

                List {
                    ForEach(store.config.layouts) { layout in
                        LayoutListRow(layout: layout, selected: layout.id == selection)
                            .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { selection = layout.id } }
                            .contextMenu {
                                Button("Delete", role: .destructive) { remove(layout.id) }
                                    .disabled(store.config.layouts.count <= 1)
                            }
                            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { store.config.layouts.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.top, 22)
            .frame(width: 230)

            if let id = selection, let index = store.config.layouts.firstIndex(where: { $0.id == id }) {
                LayoutDetail(layout: $store.config.layouts[index], canDelete: store.config.layouts.count > 1) { remove(id) }
                    .id(id)
            } else {
                Text("Select a layout")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? store.config.layouts.first?.id }
    }

    private func add() {
        let layout = Layout(name: "New Layout", ratios: [50, 50])
        store.config.layouts.append(layout)
        selection = layout.id
    }

    private func remove(_ id: UUID) {
        guard store.config.layouts.count > 1, let index = store.config.layouts.firstIndex(where: { $0.id == id }) else { return }
        store.config.layouts.remove(at: index)
        if selection == id {
            selection = store.config.layouts[min(index, store.config.layouts.count - 1)].id
        }
    }
}

private struct LayoutListRow: View {
    let layout: Layout
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            LayoutIcon(layout: layout, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(layout.name).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.white : .primary)
                Text(layout.ratioLabel).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? Color.white.opacity(0.7) : .secondary)
            }
            Spacer()
            if let shortcut = layout.shortcut {
                Text(shortcut.displayString).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? Color.white.opacity(0.7) : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if selected {
                shape.fill(LinearGradient(colors: [Theme.tileTop.opacity(0.85), Theme.accentBottom.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Theme.rim(0.45, 0.1)))
                    .shadow(color: Theme.accentBottom.opacity(0.35), radius: 6, y: 2)
            } else if hovered {
                shape.fill(.primary.opacity(0.06))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

private struct LayoutDetail: View {
    @Binding var layout: Layout
    let canDelete: Bool
    let onDelete: () -> Void
    @ObservedObject private var hotkeys = HotkeyCenter.shared
    @State private var ratioText = ""

    private var ratiosValid: Bool { Layout.parse(ratioText) != nil }

    var body: some View {
        ScrollPage(leading: 14) {
            HStack(spacing: 12) {
                LayoutIcon(layout: layout, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    EditableTitle(text: $layout.name)
                    Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.glassCapsule(.destructive))
                    .disabled(!canDelete)
            }

            VStack(alignment: .leading, spacing: 8) {
                BlueprintEditor(layout: $layout)
                    .frame(height: 200)
                HStack {
                    Text("Drag the handles to resize, they snap to 5%. Hover a column to split it into rows or leave it empty.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    ColumnStepper(layout: $layout)
                }
            }

            SettingsSection(title: "Layout") {
                SettingsRow(title: "Columns", divider: false) { EmptyView() } trailing: {
                    InsetField(text: $ratioText, prompt: "20/60/20", mono: true, invalid: !ratiosValid)
                }
                SettingsRow(title: "Shortcut") { EmptyView() } trailing: {
                    ShortcutRecorder(shortcut: $layout.shortcut, isTaken: layout.shortcut.map(hotkeys.failed.contains) ?? false)
                }
                SettingsRow(title: "Only move pinned apps", subtitle: "Other windows stay where they are.") { EmptyView() } trailing: {
                    Toggle("", isOn: $layout.pinnedOnly).toggleStyle(.switch).labelsHidden()
                }
            }

            SettingsSection(title: "Preferred columns",
                            footer: "These apps always go to their column or row when the layout is applied. Other windows fill the remaining space.") {
                ForEach(layout.pins.keys.sorted(), id: \.self) { bundleID in
                    let app = AppIdentity(bundleID: bundleID)
                    SettingsRow(title: app.name, divider: bundleID != layout.pins.keys.sorted().first) {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                        }
                    } trailing: {
                        Picker("", selection: pinBinding(bundleID)) {
                            ForEach(0..<layout.cellCount, id: \.self) { cell in
                                Text(layout.cellTitle(cell)).tag(cell)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button { layout.pins[bundleID] = nil } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.hoverable)
                        .help("Remove")
                    }
                }
                AddAppButton(apps: runningApps(), target: layout.cellTitle(largestCell)) { bundleID in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { layout.pins[bundleID] = largestCell }
                }
                .overlay(alignment: .top) {
                    if !layout.pins.isEmpty { Rectangle().fill(.primary.opacity(0.07)).frame(height: 1).padding(.leading, 14) }
                }
            }
        }
        .onAppear { ratioText = layout.ratioLabel }
        .onChange(of: ratioText) { _, text in
            guard let parsed = Layout.parse(text), parsed.ratios != layout.ratios || parsed.rows != layout.rows else { return }
            layout = layout.restructured(ratios: parsed.ratios, rows: parsed.rows)
        }
        .onChange(of: layout.ratios) { _, _ in syncRatioText() }
        .onChange(of: layout.rowCounts) { _, _ in syncRatioText() }
    }

    /// Dragging and the row buttons in the blueprint update the text field.
    private func syncRatioText() {
        let typed = Layout.parse(ratioText).map { layout.restructured(ratios: $0.ratios, rows: $0.rows) }
        if typed?.ratios != layout.ratios || typed?.rowCounts != layout.rowCounts { ratioText = layout.ratioLabel }
    }

    private var summary: String {
        let pinned = layout.pins.count
        var columns = "\(layout.columnCount) column\(layout.columnCount == 1 ? "" : "s")"
        if layout.cellCount != layout.columnCount { columns += ", \(layout.cellCount) cell\(layout.cellCount == 1 ? "" : "s")" }
        return pinned == 0 ? columns : "\(columns) · \(pinned) app\(pinned == 1 ? "" : "s") pinned"
    }

    private var largestCell: Int {
        let cells = layout.cells, counts = layout.rowCounts
        func area(_ cell: Int) -> Double { layout.fractions[cells[cell].column] / Double(counts[cells[cell].column]) }
        return cells.indices.max { area($0) < area($1) } ?? 0
    }

    private func pinBinding(_ bundleID: String) -> Binding<Int> {
        Binding(get: { layout.pins[bundleID] ?? 0 }, set: { layout.pins[bundleID] = $0 })
    }

    private func runningApps() -> [(name: String, bundleID: String)] {
        var seen = Set(layout.pins.keys)
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
}

private extension Layout {
    /// "Column 2 · 60%" or "Column 1 · Top · 20%".
    func cellTitle(_ cell: Int) -> String {
        let column = cells.indices.contains(cell) ? cells[cell].column : 0
        let parts = ["Column \(column + 1)", rowName(of: cell), "\(Int((fractions[column] * 100).rounded()))%"]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// Card row that opens a menu of running apps to pin, styled like the rows above it.
private struct AddAppButton: View {
    let apps: [(name: String, bundleID: String)]
    /// Where new apps go, e.g. "Column 2 · 60%".
    let target: String
    let add: (String) -> Void
    @State private var hovered = false

    var body: some View {
        Menu {
            if apps.isEmpty {
                Text("All running apps are pinned")
            } else {
                Section("Running apps · added to \(target)") {
                    ForEach(apps, id: \.bundleID) { app in
                        Button { add(app.bundleID) } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                if let icon = AppIdentity(bundleID: app.bundleID).icon { Image(nsImage: icon.menuSized) }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.tileTop.opacity(hovered ? 0.28 : 0.16))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.accentText.opacity(hovered ? 0.9 : 0.55), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accentText)
                        .rotationEffect(.degrees(hovered ? 90 : 0))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add app…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentTop)
                    Text("Pin a running app to a column or row")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // A peek at the running apps that can still be added.
                HStack(spacing: -6) {
                    ForEach(apps.prefix(4), id: \.bundleID) { app in
                        if let icon = AppIdentity(bundleID: app.bundleID).icon {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        }
                    }
                }
                .offset(x: hovered ? -4 : 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.tileTop.opacity(hovered ? 0.07 : 0))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .disabled(apps.isEmpty)
        .onHover { hovering in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hovered = hovering } }
    }
}

private extension NSImage {
    /// App icons are large, menus want 16pt.
    var menuSized: NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        image.unlockFocus()
        return image
    }
}

/// Layout name as an inline-editable title.
private struct EditableTitle: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text, prompt: Text("Untitled"))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .bold))
                .focused($focused)
                .fixedSize()
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(hovered && !focused ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.primary.opacity(focused ? 0.08 : (hovered ? 0.05 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.accentTop.opacity(focused ? 0.7 : 0), lineWidth: 1.5)
        )
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: focused)
        .help("Rename")
    }
}

/// "− 3 columns +" control under the blueprint. Adding splits the widest column.
private struct ColumnStepper: View {
    @Binding var layout: Layout

    var body: some View {
        HStack(spacing: 2) {
            button("minus", enabled: layout.columnCount > 1, help: "Remove the last column") {
                layout = layout.removingColumn(at: layout.columnCount - 1)
            }
            Text("\(layout.columnCount) column\(layout.columnCount == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 76)
            button("plus", enabled: layout.columnCount < Layout.maxColumns, help: "Split the widest column") {
                layout = layout.addingColumn()
            }
        }
        .padding(3)
        .background(Capsule().fill(.primary.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Theme.rim(0.22, 0.05)))
    }

    private func button(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.primary.opacity(enabled ? 0.1 : 0.04)))
                .contentShape(Circle())
        }
        .buttonStyle(.hoverable)
        .focusEffectDisabled()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }
}

/// Blueprint preview of the layout where the edges between columns can be dragged.
private struct BlueprintEditor: View {
    @Binding var layout: Layout
    @State private var dragging: Int?
    @State private var hoveredColumn: Int?

    private let pad: CGFloat = 14
    private let gap: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let inner = geometry.size.width - pad * 2
            let height = geometry.size.height
            let fractions = layout.fractions
            let edges = fractions.indices.reduce(into: [0.0]) { $0.append($0.last! + fractions[$1]) }

            ZStack(alignment: .topLeading) {
                BlueprintGrid(divisions: 20).stroke(.white.opacity(0.06), lineWidth: 0.5)
                BlueprintGrid(divisions: 5).stroke(.white.opacity(0.13), lineWidth: 1)

                ForEach(fractions.indices, id: \.self) { index in
                    let minX = pad + inner * edges[index] + (index == 0 ? 0 : gap / 2)
                    let maxX = pad + inner * edges[index + 1] - (index == fractions.count - 1 ? 0 : gap / 2)
                    column(index, percent: fractions[index])
                        .frame(width: max(4, maxX - minX), height: height - pad * 2 - 22)
                        .offset(x: minX, y: pad)
                    Text("COL \(index + 1)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: max(4, maxX - minX))
                        .offset(x: minX, y: height - pad - 13)
                }

                ForEach(0..<max(0, fractions.count - 1), id: \.self) { boundary in
                    handle(boundary)
                        .offset(x: pad + inner * edges[boundary + 1] - 10, y: pad + (height - pad * 2 - 22) / 2 - 24)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("blueprint"))
                                .onChanged { value in
                                    dragging = boundary
                                    let position = Double((value.location.x - pad) / inner)
                                    let ratios = layout.resizedRatios(movingBoundary: boundary, to: position)
                                    if ratios != layout.ratios { layout.ratios = ratios }
                                }
                                .onEnded { _ in dragging = nil }
                        )
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: layout.fractions)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: layout.rowCounts)
        }
        .coordinateSpace(name: "blueprint")
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1F63E0), Color(hex: 0x0B2E80)], startPoint: .top, endPoint: .bottom))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.rim(0.3, 0.08)))
    }

    private func column(_ index: Int, percent: Double) -> some View {
        let rows = layout.rowCounts[index]
        let first = layout.cellIndex(column: index, row: 0)
        let hovered = hoveredColumn == index && dragging == nil
        return VStack(spacing: gap) {
            if rows == 0 {
                emptyColumn(percent: percent)
            }
            ForEach(0..<rows, id: \.self) { row in
                cell(first + row, percent: percent)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovered && layout.columnCount > 1 {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { layout = layout.removingColumn(at: index) }
                    hoveredColumn = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color(hex: 0x0B2E80, opacity: 0.85)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.5)))
                }
                .buttonStyle(.hoverable)
                .help("Remove column")
                .padding(5)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topLeading) {
            if hovered { emptyToggle(index, rows: rows).padding(5).transition(.scale(scale: 0.6).combined(with: .opacity)) }
        }
        .overlay(alignment: .bottom) {
            if hovered { rowStepper(index, rows: rows).padding(6).transition(.scale(scale: 0.6).combined(with: .opacity)) }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                if hovering { hoveredColumn = index } else if hoveredColumn == index { hoveredColumn = nil }
            }
        }
    }

    private func cell(_ cell: Int, percent: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let apps = layout.pins.filter { $0.value == cell }.keys.sorted()
        return VStack(spacing: 6) {
            Text("\(Int((percent * 100).rounded()))%")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: 0x0B2E80))
                .contentTransition(.numericText())
            if !apps.isEmpty {
                HStack(spacing: -4) {
                    ForEach(apps, id: \.self) { bundleID in
                        if let icon = AppIdentity(bundleID: bundleID).icon {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(LinearGradient(colors: [.white.opacity(0.92), Color(hex: 0xE0EBFF, opacity: 0.68)], startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(.white.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }

    /// Free space that never gets a window, e.g. the sides of a centered layout.
    private func emptyColumn(percent: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 2) {
            Text("\(Int((percent * 100).rounded()))%")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
            Text("EMPTY").font(.system(size: 9, weight: .medium, design: .monospaced)).opacity(0.7)
        }
        .foregroundStyle(.white.opacity(0.75))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(.white.opacity(0.06)))
        .overlay(shape.strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    /// Switches a column between empty space and holding windows, like `_` in the columns field.
    private func emptyToggle(_ column: Int, rows: Int) -> some View {
        let empty = rows == 0
        let enabled = empty || layout.canEmpty(column: column)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { layout = layout.settingRows(empty ? 1 : 0, inColumn: column) }
        } label: {
            Image(systemName: empty ? "macwindow" : "square.dashed")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(hex: 0x0B2E80, opacity: 0.85)))
                .overlay(Circle().strokeBorder(.white.opacity(0.5)))
        }
        .buttonStyle(.hoverable)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(empty ? "Use the column for windows" : (enabled ? "Leave the column empty" : "At least one column has to hold windows"))
    }

    /// "− 2 rows +" on the hovered column. Below one row the column becomes empty.
    private func rowStepper(_ column: Int, rows: Int) -> some View {
        HStack(spacing: 0) {
            rowButton("minus", enabled: rows > 1 || (rows == 1 && layout.canEmpty(column: column)),
                      help: rows == 1 ? "Leave the column empty" : "Remove a row") { layout = layout.settingRows(rows - 1, inColumn: column) }
            Text(rows == 0 ? "Empty" : "\(rows) row\(rows == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize()
                .padding(.horizontal, 2)
            rowButton("plus", enabled: rows < Layout.maxRows, help: rows == 0 ? "Use the column for windows" : "Add a row") { layout = layout.settingRows(rows + 1, inColumn: column) }
        }
        .padding(2)
        .background(Capsule().fill(Color(hex: 0x0B2E80, opacity: 0.85)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.5)))
    }

    private func rowButton(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .contentShape(Circle())
        }
        .buttonStyle(.hoverable(scale: 1.2))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(help)
    }

    private func handle(_ boundary: Int) -> some View {
        let active = dragging == boundary
        return Capsule()
            .fill(.white)
            .frame(width: active ? 8 : 6, height: active ? 46 : 38)
            .shadow(color: Theme.accentText.opacity(0.9), radius: active ? 10 : 6)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .frame(width: 20, height: 48)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: active)
    }
}

// MARK: - About

private struct AboutSettings: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var updater = Updater.shared

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppIconView(size: 128)
                .shadow(color: Theme.accentBottom.opacity(0.35), radius: 24, y: 10)
            VStack(spacing: 4) {
                Text("omw").font(.system(size: 30, weight: .bold))
                Text("oh my windows").font(.system(size: 14)).foregroundStyle(.secondary)
                Text("Version \(Self.version)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
            if updater.isAvailable {
                Button(updater.pendingVersion.map { "Install Update (\($0))" } ?? "Check for Updates") { updater.checkForUpdates() }
                    .buttonStyle(.glassCapsule(updater.pendingVersion == nil ? .secondary : .primary))
            }
            Text("Pick a column layout, and every window on the current desktop snaps into it.\nNo tiling trees, no workspaces, no config language.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            HStack(spacing: 8) {
                if let shortcut = store.config.overlayShortcut {
                    Text("Open with").font(.system(size: 12)).foregroundStyle(.secondary)
                    Keycaps(keys: shortcut.displayKeys)
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

// MARK: - Shortcut recorder

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var isTaken = false
    @State private var recording = false
    @State private var monitor: Any?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            if isTaken && !recording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Another app already uses this shortcut")
            }
            if recording {
                Text("Type shortcut…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent))
                    .overlay(Capsule().strokeBorder(Theme.accentText.opacity(pulse ? 0.9 : 0.2), lineWidth: 2))
                    .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
                    .onDisappear { pulse = false }
                    .onTapGesture { stop() }
            } else if let shortcut {
                Button { start() } label: { Keycaps(keys: shortcut.displayKeys) }
                    .buttonStyle(.hoverable(scale: 1.05))
                    .help("Click to change")
                Button { self.shortcut = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.hoverable)
                    .help("Remove shortcut")
            } else {
                Button("Record Shortcut") { start() }
                    .buttonStyle(.glassCapsule(.secondary))
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        HotkeyCenter.shared.suspend()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // escape
                stop()
            } else if let recorded = Shortcut(event: event) {
                shortcut = recorded
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotkeyCenter.shared.resume()
        }
    }
}
