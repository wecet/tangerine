import AppKit
import SwiftUI
import PDFKit
import ImageIO

@main
struct NativeChecks {
    static func main() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let image = NSImage(size: NSSize(width: 320, height: 240), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("TANGERINE 123" as NSString).draw(at: NSPoint(x: 20, y: 100), withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black])
            return true
        }
        for format in ["png", "jpg", "heic", "tiff", "pdf"] {
            let data = try FileActions.encode(image, format: format)
            precondition(data.count > 100)
            let file = tmp.appendingPathComponent("sample." + format)
            try data.write(to: file)
            let restored = try FileActions.image(file)
            precondition(restored.isValid)
            if format == "pdf" { precondition(PDFDocument(data: data)?.pageCount == 1) }
            else {
                let source = CGImageSourceCreateWithData(data as CFData, nil)!
                let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)!
                precondition(cg.width >= 320 && cg.height >= 240)
            }
        }
        let pdf = PDFDocument()
        pdf.insert(PDFPage(image: image)!, at: 0)
        pdf.insert(PDFPage(image: image)!, at: 1)
        let pdfFile = tmp.appendingPathComponent("two-pages.pdf")
        try pdf.dataRepresentation()!.write(to: pdfFile)
        for format in ["png", "jpg", "heic"] {
            try FileActions.convert(pdfFile, format: format, reveal: false)
            for index in 1...2 {
                let page = tmp.appendingPathComponent("two-pages page \(index)." + format)
                precondition(FileManager.default.fileExists(atPath: page.path))
                let loaded = try FileActions.image(page)
                precondition(loaded.isValid)
            }
        }
        let source = tmp.appendingPathComponent("sample.png")
        let proposed = FileActions.output(for: source, ext: "png")
        precondition(proposed.lastPathComponent == "sample 2.png")
        try Data([1]).write(to: proposed)
        precondition(FileActions.output(for: source, ext: "png").lastPathComponent == "sample 3.png")
        let text = try FileActions.recognize(image)
        precondition(text.contains("TANGERINE"), "OCR failed: \(text)")
        precondition(Binding.option.matches(.maskAlternate))
        precondition(!Binding.option.matches([.maskAlternate, .maskShift]))
        precondition(Binding.controlShift.matches([.maskControl, .maskShift]))
        // Exercise all sectors across the wheel, not just the last overlaid view.
        for count in [3, 4, 6, 8] {
            for index in 0..<count {
                let angle = Double(index) * 2 * Double.pi / Double(count) - Double.pi / 2
                for radius in [85.0, 111.0, 140.0] {
                    let point = CGPoint(x: 180 + radius * cos(angle), y: 180 + radius * sin(angle))
                    precondition(WheelGeometry.actionIndex(at: point, count: count) == index)
                }
            }
            precondition(WheelGeometry.actionIndex(at: CGPoint(x: 180, y: 180), count: count) == nil)
            precondition(WheelGeometry.actionIndex(at: .zero, count: count) == nil)
            precondition(WheelGeometry.actionIndex(at: CGPoint(x: 180, y: 20), count: count) == nil)
        }
        let actions = ["PNG", "JPG", "WEBP", "HEIC", "TIFF", "PDF", "TXT", "DOCX"].map { WheelAction(title: $0, symbol: "doc", perform: {}) }
        let view = NSHostingView(rootView: WheelView(file: source, title: "Convert", actions: actions, dismiss: {}))
        view.frame = NSRect(x: 0, y: 0, width: WheelGeometry.displaySize, height: WheelGeometry.displaySize)
        view.layoutSubtreeIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/wheel-preview.png")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: path)
        }
        print("Native checks passed: PNG/JPEG/HEIC/TIFF/PDF, multipage PDF exports, output collisions, OCR, exact modifier bindings, every wheel sector")
    }
}
