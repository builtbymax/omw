import AppKit
import OMWCore
import SwiftUI

/// Click-through, transparent panel that covers a display.
private final class FeedbackPanel: NSPanel {
    init(clickThrough: Bool) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = clickThrough
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Ghost columns

@MainActor
private final class GhostModel: ObservableObject {
    @Published var columns: [CGRect] = []
    @Published var visible = false
}

/// Dashed blueprint columns drawn on the real display while browsing layouts in the launcher.
@MainActor
final class GhostColumnsController {
    private let panel = FeedbackPanel(clickThrough: true)
    private let model = GhostModel()

    init() {
        panel.contentView = NSHostingView(rootView: GhostView(model: model))
    }

    func show(_ layout: Layout, on screen: NSScreen, gap: Double, below window: NSWindow) {
        let area = screen.axVisibleFrame
        let columns = Arranger.cells(for: layout, in: area, gap: gap)
            .map { $0.offsetBy(dx: -area.minX, dy: -area.minY) }
        if panel.frame != screen.visibleFrame {
            panel.setFrame(screen.visibleFrame, display: false)
            model.columns = columns
        }
        if !panel.isVisible {
            model.columns = columns
            panel.order(.below, relativeTo: window.windowNumber)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            model.columns = columns
        }
        withAnimation(.easeOut(duration: 0.16)) { model.visible = true }
    }

    func hide() {
        model.visible = false
        panel.orderOut(nil)
    }
}

private struct GhostView: View {
    @ObservedObject var model: GhostModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.columns.indices, id: \.self) { index in
                let rect = model.columns[index]
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                ZStack {
                    shape.fill(Theme.tileTop.opacity(0.12))
                    shape.strokeBorder(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(model.visible ? 1 : 0)
    }
}

// MARK: - HUD

@MainActor
private final class HUDModel: ObservableObject {
    @Published var layout: Layout?
    @Published var count = 0
    @Published var visible = false
    var onUndo: () -> Void = {}
}

/// "Arranged 5 windows" confirmation at the bottom of the display, with Undo.
@MainActor
final class HUDController {
    /// Room around the pill for its shadow (radius 20, y 10), so the panel edge never clips it.
    private static let size = NSSize(width: 540, height: 130)
    private static let shadowInset: CGFloat = 34
    private let panel = FeedbackPanel(clickThrough: false)
    private let model = HUDModel()
    private var hideTask: Task<Void, Never>?

    init(undo: @escaping () -> Void) {
        panel.setContentSize(Self.size)
        panel.contentView = NSHostingView(rootView: HUDView(model: model, bottomInset: Self.shadowInset))
        model.onUndo = { [weak self] in
            undo()
            self?.hide()
        }
    }

    func show(_ layout: Layout, count: Int, on screen: NSScreen) {
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 40 - Self.shadowInset))
        model.layout = layout
        model.count = count
        model.visible = false
        panel.orderFrontRegardless()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { model.visible = true }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(.easeIn(duration: 0.18)) { model.visible = false }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            if self?.model.visible == false { self?.panel.orderOut(nil) }
        }
    }
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel
    let bottomInset: CGFloat
    @State private var bounce = false

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if model.visible, let layout = model.layout {
                HStack(spacing: 12) {
                    LayoutIcon(layout: layout, size: 36)
                        .scaleEffect(bounce ? 1.12 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.count == 1 ? "Arranged 1 window" : "Arranged \(model.count) windows")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Text(layout.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                            Text(layout.ratioLabel).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 26)
                    Button("Undo") { model.onUndo() }
                        .buttonStyle(.glassCapsule(.secondary))
                }
                .padding(10)
                .padding(.trailing, 4)
                // A dark base under the content keeps the white text readable when light windows shine through the glass.
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color(hex: 0x141824, opacity: 0.6)))
                .glassSurface(cornerRadius: 30, tint: Color(hex: 0x141824, opacity: 0.55))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                .onAppear {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45).delay(0.12)) { bounce = true }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.3)) { bounce = false }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, bottomInset)
        .environment(\.colorScheme, .dark)
    }
}
