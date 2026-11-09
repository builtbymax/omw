import AppKit
import OMWCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Workspaces

struct WorkspaceSettings: View {
    @ObservedObject var store: ConfigStore
    @Binding var selection: UUID?
    let apply: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Workspaces").font(.system(size: 20, weight: .bold))
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
                    .help("New workspace")
                }
                .padding(.leading, 6)
                .padding(.bottom, 10)

                List {
                    ForEach(store.config.workspaces) { workspace in
                        WorkspaceListRow(workspace: workspace, selected: workspace.id == selection)
                            .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { selection = workspace.id } }
                            .contextMenu {
                                Button("Apply") { apply(workspace.id) }
                                Button("Delete", role: .destructive) { remove(workspace.id) }
                            }
                            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { store.config.workspaces.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.top, 22)
            .frame(width: 230)

            if let id = selection, let index = store.config.workspaces.firstIndex(where: { $0.id == id }) {
                WorkspaceDetail(workspace: $store.config.workspaces[index], layouts: store.config.layouts,
                                onApply: { apply(id) }, onDelete: { remove(id) })
                    .id(id)
            } else {
                VStack(spacing: 12) {
                    IconTile(style: .workspaces, size: 48)
                    Text("No workspace yet").font(.system(size: 15, weight: .semibold))
                    Text("Pin apps to columns on each display and bring them all back with one shortcut.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Button("New Workspace") { add() }
                        .buttonStyle(.glassCapsule(.primary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? store.config.workspaces.first?.id }
    }

    private func add() {
        let template = store.config.layouts.first ?? Layout(name: "Halves", ratios: [50, 50])
        var workspace = Workspace(name: "New Workspace")
        if let screen = NSScreen.screens.first, let uuid = screen.uuid {
            workspace.displays = [WorkspaceDisplay(displayID: uuid, displayName: screen.localizedName,
                                                   layout: Layout(name: workspace.name, ratios: template.ratios, rows: template.rowCounts))]
        }
        store.config.workspaces.append(workspace)
        selection = workspace.id
    }

    private func remove(_ id: UUID) {
        guard let index = store.config.workspaces.firstIndex(where: { $0.id == id }) else { return }
        store.config.workspaces.remove(at: index)
        if selection == id {
            selection = store.config.workspaces.isEmpty ? nil : store.config.workspaces[min(index, store.config.workspaces.count - 1)].id
        }
    }
}

extension Workspace {
    /// "2 displays · 5 apps".
    var summary: String {
        let apps = apps.count
        let displays = "\(displays.count) display\(displays.count == 1 ? "" : "s")"
        return apps == 0 ? "\(displays) · no apps yet" : "\(displays) · \(apps) app\(apps == 1 ? "" : "s")"
    }
}

private struct WorkspaceListRow: View {
    let workspace: Workspace
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            IconTile(style: .workspaces, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(workspace.name).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.onAccent : .primary)
                    .lineLimit(1)
                Text(workspace.summary).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? Theme.onAccent.opacity(0.7) : .secondary)
            }
            Spacer()
            if let shortcut = workspace.shortcut {
                Text(shortcut.displayString).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? Theme.onAccent.opacity(0.7) : .secondary)
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

/// A display a workspace can cover: every connected one, and the ones it covers that aren't connected.
private struct DisplayChoice: Identifiable {
    let id: String
    let name: String
    let connected: Bool
    let main: Bool
}

private struct WorkspaceDetail: View {
    @Binding var workspace: Workspace
    let layouts: [Layout]
    let onApply: () -> Void
    let onDelete: () -> Void
    @ObservedObject private var hotkeys = HotkeyCenter.shared
    @State private var screens = NSScreen.leftToRight

    private var choices: [DisplayChoice] {
        let connected = screens.compactMap { screen in
            screen.uuid.map { DisplayChoice(id: $0, name: screen.localizedName, connected: true, main: screen == NSScreen.screens.first) }
        }
        let missing = workspace.displays.filter { display in !connected.contains { $0.id == display.displayID } }
            .map { DisplayChoice(id: $0.displayID, name: $0.displayName, connected: false, main: false) }
        return connected + missing
    }

    var body: some View {
        ScrollPage(leading: 14) {
            HStack(spacing: 12) {
                IconTile(style: .workspaces, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    EditableTitle(text: $workspace.name)
                    Text(workspace.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Apply", action: onApply)
                    .buttonStyle(.glassCapsule(.primary))
                    .disabled(workspace.apps.isEmpty)
                    .help(workspace.apps.isEmpty ? "Pin an app first" : "Open the pinned apps and put them in their columns")
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.glassCapsule(.destructive))
            }

            SettingsSection(title: "Workspace",
                            footer: "Applying opens the pinned apps that aren't running and puts every pinned app in its column. Other windows stay where they are. Applying a layout afterwards takes over again.") {
                SettingsRow(title: "Shortcut", divider: false) { EmptyView() } trailing: {
                    ShortcutRecorder(shortcut: $workspace.shortcut, isTaken: workspace.shortcut.map(hotkeys.failed.contains) ?? false)
                }
            }

            AppTray(pinned: Set(workspace.apps), add: addApp, remove: { app in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { workspace = workspace.unpinning(app) }
            })

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Displays").padding(.leading, 4)
                ForEach(choices) { choice in
                    displayCard(choice)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.leftToRight
        }
    }

    private func displayCard(_ choice: DisplayChoice) -> some View {
        let included = workspace.displays.contains { $0.displayID == choice.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: choice.connected ? "display" : "display.trianglebadge.exclamationmark")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(choice.name).font(.system(size: 13, weight: .semibold))
                if choice.main { badge("Main") }
                if !choice.connected { badge("Not connected") }
                Spacer()
                Toggle("", isOn: Binding(get: { included }, set: { setIncluded($0, choice) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(included ? "Leave this display out of the workspace" : "Use this display in the workspace")
            }
            if included {
                BlueprintEditor(layout: layoutBinding(choice.id),
                                dropApp: { app, cell in workspace = workspace.pinning(app, display: choice.id, cell: cell) },
                                removeApp: { app in workspace = workspace.unpinning(app) })
                    .frame(height: 190)
                HStack(spacing: 8) {
                    Text("Drag apps between columns, right-click one to remove it.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Menu("Columns") {
                        Section("Use the columns of") {
                            ForEach(layouts) { layout in
                                Button("\(layout.name)  \(layout.ratioLabel)") { useColumns(of: layout, on: choice.id) }
                            }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glassCapsule(.secondary))
                    .fixedSize()
                    ColumnStepper(layout: layoutBinding(choice.id))
                }
            }
        }
        .padding(12)
        .glassCard()
        .opacity(included || choice.connected ? 1 : 0.6)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.primary.opacity(0.08)))
    }

    /// The columns of one display. Looked up by display, so switching a display off doesn't shift the others.
    private func layoutBinding(_ displayID: String) -> Binding<Layout> {
        Binding {
            workspace.displays.first { $0.displayID == displayID }?.layout ?? Layout(name: workspace.name, ratios: [50, 50])
        } set: { layout in
            guard let index = workspace.displays.firstIndex(where: { $0.displayID == displayID }) else { return }
            workspace.displays[index].layout = layout
        }
    }

    private func setIncluded(_ included: Bool, _ choice: DisplayChoice) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if included {
                guard !workspace.displays.contains(where: { $0.displayID == choice.id }) else { return }
                let template = layouts.first ?? Layout(name: "Halves", ratios: [50, 50])
                workspace.displays.append(WorkspaceDisplay(displayID: choice.id, displayName: choice.name,
                                                           layout: Layout(name: workspace.name, ratios: template.ratios, rows: template.rowCounts)))
            } else {
                workspace.displays.removeAll { $0.displayID == choice.id }
            }
        }
    }

    /// Takes over the columns and rows of a saved layout, the pinned apps follow their column.
    private func useColumns(of layout: Layout, on displayID: String) {
        let binding = layoutBinding(displayID)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            binding.wrappedValue = binding.wrappedValue.restructured(ratios: layout.ratios, rows: layout.rowCounts)
        }
    }

    /// Pins an app to the largest cell of the first display, covering the main display first if there's none.
    private func addApp(_ bundleID: String) {
        if workspace.displays.isEmpty, let main = choices.first { setIncluded(true, main) }
        guard let display = workspace.displays.first else { return }
        let layout = display.layout, cells = layout.cells, counts = layout.rowCounts
        func area(_ cell: Int) -> Double { layout.fractions[cells[cell].column] / Double(counts[cells[cell].column]) }
        let largest = cells.indices.max { area($0) < area($1) } ?? 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            workspace = workspace.pinning(bundleID, display: display.displayID, cell: largest)
        }
    }
}

/// Running apps that aren't pinned yet, to drag onto a column. Dropping a pinned app here unpins it.
private struct AppTray: View {
    let pinned: Set<String>
    let add: (String) -> Void
    let remove: (String) -> Void
    @State private var targeted = false
    @State private var running = AppTray.runningApps()

    var body: some View {
        let apps = running.filter { !pinned.contains($0.bundleID) }
        SettingsSection(title: "Apps",
                        footer: "Drag an app onto a column, or click it to add it to the largest one. Drop a pinned app here to remove it.") {
            FlowLayout(spacing: 6) {
                ForEach(apps, id: \.bundleID) { app in
                    AppChip(name: app.name, bundleID: app.bundleID) { add(app.bundleID) }
                }
                Button { choose() } label: {
                    Label("Choose App…", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().strokeBorder(Theme.accentText.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5])))
                        .contentShape(Capsule())
                }
                .buttonStyle(.hoverable)
                .help("Pin an app that isn't running")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.tileTop.opacity(targeted ? 0.12 : 0))
            .modifier(AppDrop(enabled: true) { remove($0) } targeted: { targeted = $0 })
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            running = Self.runningApps()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            running = Self.runningApps()
        }
    }

    private static func runningApps() -> [(name: String, bundleID: String)] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    /// Any app from disk, so apps that aren't running can be pinned too.
    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !pinned.contains(id) { add(id) }
        }
    }
}

private struct AppChip: View {
    let name: String
    let bundleID: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            AppIconImage(bundleID: bundleID, size: 18)
            Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(.primary.opacity(hovered ? 0.12 : 0.07)))
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .draggable(bundleID) { AppIconImage(bundleID: bundleID, size: 32) }
        .onHover { hovered = $0 }
        .help("Drag onto a column, or click to add")
    }
}

/// Pinned apps in a blueprint cell, each one draggable to another cell, display or back to the tray.
struct WrappingIcons: View {
    let apps: [String]
    let size: CGFloat
    var remove: ((String) -> Void)?

    var body: some View {
        FlowLayout(spacing: 4, alignment: .center) {
            ForEach(apps, id: \.self) { bundleID in
                let name = AppIdentity(bundleID: bundleID).name
                AppIconImage(bundleID: bundleID, size: size)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .help(name)
                    .draggable(bundleID) { AppIconImage(bundleID: bundleID, size: 32) }
                    .contextMenu {
                        if let remove { Button("Remove \(name)") { remove(bundleID) } }
                    }
            }
        }
    }
}

struct AppIconImage: View {
    let bundleID: String
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = AppIdentity(bundleID: bundleID).icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Accepts apps dragged as bundle identifiers. Text that isn't an installed app's identifier is refused.
struct AppDrop: ViewModifier {
    let enabled: Bool
    let drop: (String) -> Void
    let targeted: (Bool) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { items, _ in
                let apps = items.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
                apps.forEach(drop)
                return !apps.isEmpty
            } isTargeted: { targeted($0) }
        } else {
            content
        }
    }
}

/// Lays out views left to right and wraps them into new lines.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(for: subviews, width: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(for: subviews, width: bounds.width) {
            var x = alignment == .center ? bounds.minX + (bounds.width - line.width) / 2 : bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private func lines(for subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var lines: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = lines.last, last.width + spacing + size.width <= width {
                lines[lines.count - 1] = (last.indices + [index], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                lines.append(([index], size.width, size.height))
            }
        }
        return lines
    }
}
