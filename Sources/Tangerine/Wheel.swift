import AppKit
import SwiftUI

struct WheelAction: Identifiable {
    var id: String { title }
    let title: String
    let symbol: String
    var enabled = true
    var previewFormat: String? = nil
    let perform: () -> Void
}
struct Wedge: Shape {
    let index: Int
    let count: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 360.0 / Double(count)
        let a = Double(index) * step - 90 - step / 2 + 2
        let b = a + step - 4
        func point(_ radius: Double, _ degrees: Double) -> CGPoint {
            let rad = degrees * Double.pi / 180
            return CGPoint(x: center.x + radius * cos(rad), y: center.y + radius * sin(rad))
        }
        var p = Path()
        // Soft radial corners make each sector feel like a citrus segment.
        p.move(to: point(145, a))
        p.addQuadCurve(to: point(155, a + 4), control: point(155, a))
        p.addArc(center: center, radius: 155, startAngle: .degrees(a + 4), endAngle: .degrees(b - 4), clockwise: false)
        p.addQuadCurve(to: point(145, b), control: point(155, b))
        p.addLine(to: point(75, b))
        p.addQuadCurve(to: point(65, b - 6), control: point(65, b))
        p.addArc(center: center, radius: 65, startAngle: .degrees(b - 6), endAngle: .degrees(a + 6), clockwise: true)
        p.addQuadCurve(to: point(75, a), control: point(65, a))
        p.closeSubpath()
        return p
    }
}
enum WheelGeometry {
    static let canvasSize: CGFloat = 360
    static let displaySize: CGFloat = 290
    static func containsWheel(_ point: CGPoint, in frame: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let radius = min(frame.width, frame.height) * 161 / canvasSize
        return hypot(point.x - frame.midX, point.y - frame.midY) <= radius
    }
    static func actionIndex(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let rect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        return (0..<count).first { Wedge(index: $0, count: count).path(in: rect).contains(point) }
    }
}
/// Blur the desktop behind the floating panel, even while Finder stays active.
private struct GlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
private struct WheelGlass: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency { Circle().fill(Color(nsColor: .windowBackgroundColor)) }
            else { GlassBackdrop().clipShape(Circle()) }
            Circle().fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.025), .black.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.12), .white.opacity(0.36)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            Circle().inset(by: 3).stroke(.white.opacity(0.09), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
        .frame(width: 322, height: 322)
        .allowsHitTesting(false)
    }
}
struct WheelSegment: View {
    let action: WheelAction
    let index: Int
    let count: Int
    let accent: Color
    let hovered: Bool
    let dismiss: () -> Void
    var body: some View {
        let angle = Double(index) * 2 * Double.pi / Double(count) - Double.pi / 2
        let shape = Wedge(index: index, count: count)
        ZStack {
            shape.fill(LinearGradient(colors: hovered
                ? [accent.opacity(0.62), accent.opacity(0.28)]
                : [.white.opacity(0.17), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.stroke(LinearGradient(colors: [.white.opacity(hovered ? 0.95 : 0.7), .white.opacity(0.08), .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            shape.stroke(.black.opacity(0.12), lineWidth: 0.5).offset(y: 0.7)
            VStack(spacing: 5) {
                Image(systemName: action.symbol).font(.system(size: 18, weight: .medium))
                Text(action.title.uppercased()).font(.system(size: 10, weight: .bold))
            }
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            .position(x: 180.0 + 111.0 * cos(angle), y: 180.0 + 111.0 * sin(angle))
        }
        .frame(width: 360, height: 360)
        .contentShape(shape)
        .opacity(action.enabled ? 1 : 0.3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate() }
        .help(action.enabled ? action.title : "Unavailable for this file or Docker is disabled")
    }
    func activate() { if action.enabled { dismiss(); action.perform() } }
}
struct WheelView: View {
    let file: URL
    let title: String
    let actions: [WheelAction]
    let dismiss: () -> Void
    var onHoverAction: ((WheelAction?) -> Void)? = nil
    @ObservedObject var settings = Settings.shared
    @State private var hoverIndex: Int?
    private var hoveredAction: WheelAction? { hoverIndex.map { actions[$0] } }
    var body: some View {
        ZStack {
            WheelGlass()
            ForEach(actions.indices, id: \.self) { index in
                WheelSegment(action: actions[index], index: index, count: actions.count, accent: settings.accent, hovered: hoverIndex == index && actions[index].enabled, dismiss: dismiss)
                    .allowsHitTesting(false)
            }
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.12), .black.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.65), settings.accent.opacity(0.3), .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .frame(width: 116, height: 116)
                .allowsHitTesting(false)
            VStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 28, height: 28)
                Text(hoveredAction?.title ?? title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(file.lastPathComponent).font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
            }.frame(width: 104).allowsHitTesting(false)
        }
        .frame(width: WheelGeometry.canvasSize, height: WheelGeometry.canvasSize)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): setHover(WheelGeometry.actionIndex(at: location, count: actions.count))
            case .ended: setHover(nil)
            }
        }
        .gesture(SpatialTapGesture().onEnded { value in
            guard let index = WheelGeometry.actionIndex(at: value.location, count: actions.count), actions[index].enabled else { return }
            dismiss()
            actions[index].perform()
        })
        .scaleEffect(WheelGeometry.displaySize / WheelGeometry.canvasSize)
        .frame(width: WheelGeometry.displaySize, height: WheelGeometry.displaySize)
    }
    private func setHover(_ index: Int?) {
        guard hoverIndex != index else { return }
        hoverIndex = index
        onHoverAction?(index.map { actions[$0] })
    }
}
final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
final class WheelController {
    private var panel: WheelPanel?
    private var previewPanel: NSPanel?
    private let preview = PreviewModel()
    private var global: Any?
    private var local: Any?
    func show(file: URL, title: String, actions: [WheelAction], at point: CGPoint, selectionCount: Int = 1) {
        dismiss()
        let size = WheelGeometry.displaySize
        let panel = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WheelView(file: file, title: title, actions: actions, dismiss: { [weak self] in self?.dismiss() }, onHoverAction: { [weak self] action in self?.showPreview(file, action: action, count: selectionCount) }))
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let appPoint = CGPoint(x: point.x, y: top - point.y)
        let screen = NSScreen.screens.first { $0.frame.contains(appPoint) } ?? NSScreen.main!
        let bounds = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: max(bounds.minX, min(appPoint.x - size / 2, bounds.maxX - size)), y: max(bounds.minY, min(appPoint.y - size / 2, bounds.maxY - size))))
        self.panel = panel; panel.makeKeyAndOrderFront(nil)
        global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            self?.handleDismissalEvent(event)
        }
        local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleDismissalEvent(event)
            return event.type == .keyDown && event.keyCode == 53 ? nil : event
        }
    }
    /// Called by the existing session event tap before the click reaches Finder/AppKit.
    /// The click itself is left untouched, so dismissal doesn't consume an outside click.
    func dismissIfOutside(atQuartzPoint point: CGPoint) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        dismissIfOutside(atScreenPoint: CGPoint(x: point.x, y: top - point.y))
    }
    private func dismissIfOutside(atScreenPoint point: CGPoint) {
        guard let panel, !WheelGeometry.containsWheel(point, in: panel.frame) else { return }
        dismiss()
    }
    private func handleDismissalEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { dismiss() }
            return
        }
        if let cgEvent = event.cgEvent { dismissIfOutside(atQuartzPoint: cgEvent.location) }
        else if let window = event.window { dismissIfOutside(atScreenPoint: window.convertPoint(toScreen: event.locationInWindow)) }
        else { dismissIfOutside(atScreenPoint: NSEvent.mouseLocation) }
    }
    private func showPreview(_ file: URL, action: WheelAction?, count: Int) {
        guard let panel, let action, action.enabled, let format = action.previewFormat else {
            preview.clear(); previewPanel?.orderOut(nil); return
        }
        if previewPanel == nil {
            let sidecar = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 272, height: 380), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            sidecar.isOpaque = false; sidecar.backgroundColor = .clear; sidecar.hasShadow = true
            sidecar.level = .popUpMenu; sidecar.ignoresMouseEvents = true
            sidecar.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            previewPanel = sidecar
        }
        previewPanel?.contentView = NSHostingView(rootView: OutputPreviewView(model: preview, selectionCount: count))
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main!
        let bounds = screen.visibleFrame
        let right = panel.frame.maxX + 8
        let x = right + 272 <= bounds.maxX ? right : panel.frame.minX - 280
        previewPanel?.setFrameOrigin(NSPoint(x: max(bounds.minX, min(x, bounds.maxX - 272)), y: max(bounds.minY, min(panel.frame.maxY - 380, bounds.maxY - 380))))
        preview.request(file, format: format); previewPanel?.orderFrontRegardless()
    }
    func dismiss() {
        preview.clear(); previewPanel?.orderOut(nil)
        panel?.orderOut(nil); panel = nil
        if let global { NSEvent.removeMonitor(global) }; global = nil
        if let local { NSEvent.removeMonitor(local) }; local = nil
    }
}
