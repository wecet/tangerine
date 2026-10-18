import AppKit
import SwiftUI

struct WheelAction: Identifiable {
    var id: String { title }
    let title: String
    let symbol: String
    var enabled = true
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
    static func actionIndex(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let rect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        return (0..<count).first { Wedge(index: $0, count: count).path(in: rect).contains(point) }
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
            shape.fill(hovered ? accent.opacity(0.85) : Color.white.opacity(0.24))
            shape.stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            VStack(spacing: 5) {
                Image(systemName: action.symbol).font(.system(size: 18, weight: .medium))
                Text(action.title.uppercased()).font(.system(size: 10, weight: .bold))
            }.position(x: 180.0 + 111.0 * cos(angle), y: 180.0 + 111.0 * sin(angle))
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
    @ObservedObject var settings = Settings.shared
    @State private var hoverIndex: Int?
    private var hoveredAction: WheelAction? { hoverIndex.map { actions[$0] } }
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
                .frame(width: 322, height: 322)
            ForEach(actions.indices, id: \.self) { index in
                WheelSegment(action: actions[index], index: index, count: actions.count, accent: settings.accent, hovered: hoverIndex == index && actions[index].enabled, dismiss: dismiss)
                    .allowsHitTesting(false)
            }
            Circle().fill(.thinMaterial).frame(width: 116, height: 116).overlay(Circle().stroke(settings.accent.opacity(0.35), lineWidth: 1))
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
            case .active(let location): hoverIndex = WheelGeometry.actionIndex(at: location, count: actions.count)
            case .ended: hoverIndex = nil
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
}
final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
final class WheelController {
    private var panel: WheelPanel?
    private var global: Any?
    private var local: Any?
    func show(file: URL, title: String, actions: [WheelAction], at point: CGPoint) {
        dismiss()
        let size = WheelGeometry.displaySize
        let panel = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WheelView(file: file, title: title, actions: actions, dismiss: { [weak self] in self?.dismiss() }))
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let appPoint = CGPoint(x: point.x, y: top - point.y)
        let screen = NSScreen.screens.first { $0.frame.contains(appPoint) } ?? NSScreen.main!
        let bounds = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: max(bounds.minX, min(appPoint.x - size / 2, bounds.maxX - size)), y: max(bounds.minY, min(appPoint.y - size / 2, bounds.maxY - size))))
        self.panel = panel; panel.makeKeyAndOrderFront(nil)
        global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in DispatchQueue.main.async { self?.dismiss() } }
        local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 { self?.dismiss(); return nil }
            if event.type != .keyDown && event.window !== self?.panel { self?.dismiss() }
            return event
        }
    }
    func dismiss() {
        panel?.orderOut(nil); panel = nil
        if let global { NSEvent.removeMonitor(global) }; global = nil
        if let local { NSEvent.removeMonitor(local) }; local = nil
    }
}
