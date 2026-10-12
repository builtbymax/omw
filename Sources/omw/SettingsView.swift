import AppKit
import OMWCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        TabView {
            GeneralSettings(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            LayoutSettings(store: store)
                .tabItem { Label("Layouts", systemImage: "rectangle.split.3x1") }
        }
        .frame(width: 620, height: 480)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var hotkeys = HotkeyCenter.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var trusted = AX.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                LabeledContent("Accessibility") {
                    if trusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { AX.requestTrust() }
                    }
                }
            }

            Section("Windows") {
                Stepper(value: $store.config.gap, in: 0...40, step: 2) {
                    LabeledContent("Gap between windows", value: "\(Int(store.config.gap)) pt")
                }
            }

            Section {
                shortcutRow("Open omw", \.overlayShortcut)
                shortcutRow("Move window left", \.moveLeftShortcut)
                shortcutRow("Move window right", \.moveRightShortcut)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Layout shortcuts are set per layout in the Layouts tab.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Config file") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.url]) }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = AX.isTrusted
        }
    }

    private func shortcutRow(_ title: String, _ keyPath: WritableKeyPath<Config, Shortcut?>) -> some View {
        LabeledContent(title) {
            ShortcutRecorder(shortcut: $store.config[dynamicMember: keyPath], isTaken: store.config[keyPath: keyPath].map(hotkeys.failed.contains) ?? false)
        }
    }
}

// MARK: - Layouts

private struct LayoutSettings: View {
    @ObservedObject var store: ConfigStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.config.layouts) { layout in
                        HStack(spacing: 8) {
                            LayoutGlyph(fractions: layout.fractions).frame(width: 22, height: 14)
                            Text(layout.name)
                            Spacer()
                            Text(layout.ratioLabel).foregroundStyle(.secondary).font(.caption.monospaced())
                        }
                        .tag(layout.id)
                    }
                    .onMove { store.config.layouts.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 0) {
                    Button { add() } label: { Image(systemName: "plus").frame(width: 24, height: 22) }
                    Button { remove() } label: { Image(systemName: "minus").frame(width: 24, height: 22) }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 210)

            Divider()

            if let id = selection, let index = store.config.layouts.firstIndex(where: { $0.id == id }) {
                LayoutDetail(layout: $store.config.layouts[index])
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
        let layout = OMWCore.Layout(name: "New Layout", ratios: [50, 50])
        store.config.layouts.append(layout)
        selection = layout.id
    }

    private func remove() {
        guard let index = store.config.layouts.firstIndex(where: { $0.id == selection }) else { return }
        store.config.layouts.remove(at: index)
        selection = store.config.layouts.indices.contains(index) ? store.config.layouts[index].id : store.config.layouts.last?.id
    }
}

private struct LayoutDetail: View {
    @Binding var layout: OMWCore.Layout
    @ObservedObject private var hotkeys = HotkeyCenter.shared
    @State private var ratioText = ""

    private var ratiosValid: Bool { OMWCore.Layout.parseRatios(ratioText) != nil }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $layout.name)
                TextField("Columns", text: $ratioText, prompt: Text("20/60/20"))
                    .onChange(of: ratioText) { _, text in
                        guard let ratios = OMWCore.Layout.parseRatios(text) else { return }
                        layout.ratios = ratios
                        layout.pins = layout.pins.mapValues { min($0, ratios.count - 1) }
                    }
                    .foregroundStyle(ratiosValid ? Color.primary : Color.red)
                LabeledContent("Shortcut") {
                    ShortcutRecorder(shortcut: $layout.shortcut,
                                     isTaken: layout.shortcut.map(hotkeys.failed.contains) ?? false)
                }
                LayoutGlyph(fractions: layout.fractions, spacing: 4)
                    .frame(height: 60)
                    .padding(.vertical, 4)
            }

            Section {
                ForEach(layout.pins.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Picker("", selection: pinBinding(bundleID)) {
                            ForEach(0..<layout.columnCount, id: \.self) { column in
                                Text("Column \(column + 1) · \(Int((layout.fractions[column] * 100).rounded()))%").tag(column)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button { layout.pins[bundleID] = nil } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Menu("Add App…") {
                    ForEach(runningApps(), id: \.bundleID) { app in
                        Button(app.name) { layout.pins[app.bundleID] = largestColumn }
                    }
                }
                .fixedSize()
            } header: {
                Text("Preferred columns")
            } footer: {
                Text("These apps always go to their column when the layout is applied. Other windows fill the remaining space.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { ratioText = layout.ratioLabel }
    }

    private var largestColumn: Int {
        layout.fractions.indices.max { layout.fractions[$0] < layout.fractions[$1] } ?? 0
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

private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
        }
    }
}

// MARK: - Shortcut recorder

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var isTaken = false
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            if isTaken && !recording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Another app already uses this shortcut")
            }
            Button(recording ? "Type shortcut…" : (shortcut?.displayString ?? "Record Shortcut")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 130)
            if shortcut != nil && !recording {
                Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
                    .help("Remove shortcut")
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
