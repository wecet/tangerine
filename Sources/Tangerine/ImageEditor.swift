import SwiftUI
import AppKit

enum EditorMode { case crop, background }
struct ImageEditor: View {
    let image: NSImage
    let file: URL
    let mode: EditorMode
    let close: () -> Void
    @State private var crop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var start: CGPoint?
    @State private var padding: Double = 60
    @State private var radius: Double = 24
    @State private var shadow: Double = 20
    @State private var color: Color = Color(red: 0.118, green: 0.118, blue: 0.129)
    @State private var gradient = true
    @ObservedObject var settings = Settings.shared
    var body: some View {
        VStack(spacing: 16) {
            Text(mode == .crop ? "Crop image" : "Add background").font(.title2.bold())
            GeometryReader { geo in
                let size = fitted(image.size, in: geo.size)
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.15))
                    if mode == .crop {
                        Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                            .overlay(alignment: .topLeading) {
                                Rectangle().fill(settings.accent.opacity(0.14)).overlay(Rectangle().stroke(settings.accent, lineWidth: 2))
                                    .frame(width: crop.width * size.width, height: crop.height * size.height)
                                    .offset(x: crop.minX * size.width, y: crop.minY * size.height)
                            }
                            .contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                let p = CGPoint(x: min(1, max(0, value.location.x / size.width)), y: min(1, max(0, value.location.y / size.height)))
                                if start == nil { start = p }
                                let a = start!
                                crop = CGRect(x: min(a.x, p.x), y: min(a.y, p.y), width: abs(a.x - p.x), height: abs(a.y - p.y))
                            }.onEnded { _ in start = nil })
                    } else {
                        Image(nsImage: renderBackground()).resizable().scaledToFit().padding(12)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(height: 380)
            if mode == .crop {
                Text("Drag across the image to select a crop.").foregroundStyle(.secondary)
                HStack {
                    Button("Reset") { crop = CGRect(x: 0, y: 0, width: 1, height: 1) }
                    ForEach(["1:1", "16:9", "4:3"], id: \.self) { label in Button(label) {
                        let parts = label.split(separator: ":").compactMap { Double($0) }; let aspect = parts[0] / parts[1]
                        let h = min(1.0, Double(image.size.width / image.size.height) / aspect)
                        let w = min(1.0, aspect / Double(image.size.width / image.size.height))
                        crop = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
                    } }
                }
            } else {
                HStack { ColorPicker("Background", selection: $color, supportsOpacity: false); Toggle("Gradient", isOn: $gradient) }
                HStack { Text("Padding").frame(width: 65, alignment: .leading); Slider(value: $padding, in: 0...200); Text("\(Int(padding)) px").frame(width: 65) }
                HStack { Text("Corners").frame(width: 65, alignment: .leading); Slider(value: $radius, in: 0...120); Text("\(Int(radius)) px").frame(width: 65) }
                HStack { Text("Shadow").frame(width: 65, alignment: .leading); Slider(value: $shadow, in: 0...80); Text("\(Int(shadow)) px").frame(width: 65) }
            }
            HStack { Button("Cancel", action: close).keyboardShortcut(.cancelAction); Spacer(); Text("Saves a new PNG beside the original.").font(.caption).foregroundStyle(.secondary); Button("Save copy") { save() }.keyboardShortcut(.defaultAction).disabled(mode == .crop && (crop.width < 0.005 || crop.height < 0.005)) }
        }.padding(24).frame(width: 590).tint(settings.accent)
    }
    func fitted(_ size: NSSize, in box: NSSize) -> NSSize {
        let scale = min(box.width / size.width, box.height / size.height)
        return NSSize(width: size.width * scale, height: size.height * scale)
    }
    func renderBackground() -> NSImage {
        // Bound the editor/export raster to 2400px to keep interaction memory predictable.
        let size = fitted(image.size, in: NSSize(width: 2000, height: 2000))
        let canvas = NSSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
        return NSImage(size: canvas, flipped: false) { rect in
            let base = NSColor(color)
            if gradient, let grad = NSGradient(starting: base, ending: base.blended(withFraction: 0.5, of: .black) ?? .black) { grad.draw(in: rect, angle: -45) }
            else { base.setFill(); rect.fill() }
            NSGraphicsContext.saveGraphicsState()
            let target = NSRect(x: padding, y: padding, width: size.width, height: size.height)
            let path = NSBezierPath(roundedRect: target, xRadius: radius, yRadius: radius)
            let cast = NSShadow(); cast.shadowColor = NSColor.black.withAlphaComponent(0.4); cast.shadowBlurRadius = shadow; cast.shadowOffset = NSSize(width: 0, height: -shadow / 3); cast.set()
            NSColor.black.setFill(); path.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState(); path.addClip(); image.draw(in: target); NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }
    func save() {
        do {
            let result: NSImage
            if mode == .background { result = renderBackground() }
            else {
                var rect = CGRect(origin: .zero, size: image.size)
                guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil), let cropped = cg.cropping(to: CGRect(x: crop.minX * Double(cg.width), y: crop.minY * Double(cg.height), width: crop.width * Double(cg.width), height: crop.height * Double(cg.height)).integral) else { throw ActionError(message: "Select a larger crop area.") }
                result = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
            }
            try FileActions.save(FileActions.encode(result, format: "png"), to: FileActions.output(for: file, suffix: mode == .crop ? " cropped" : " background", ext: "png"))
            close()
        } catch { FileActions.alert(error.localizedDescription) }
    }
}
extension FileActions {
    func openEditor(_ file: URL, mode: EditorMode) {
        do {
            let image = try Self.image(file)
            editor?.close()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 638, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = mode == .crop ? "Crop — Tangerine" : "Background — Tangerine"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ImageEditor(image: image, file: file, mode: mode, close: { [weak self] in self?.editor?.close() }))
            editor = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        } catch { Self.alert(error.localizedDescription) }
    }
}
