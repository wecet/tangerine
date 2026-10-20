import AppKit
import SwiftUI
import PDFKit
import ImageIO
import AVFoundation

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
        // The visible wheel is circular; transparent panel corners are outside clicks.
        let wheelFrame = CGRect(x: -500, y: 200, width: 290, height: 290)
        precondition(WheelGeometry.containsWheel(CGPoint(x: -355, y: 345), in: wheelFrame))
        precondition(WheelGeometry.containsWheel(CGPoint(x: -226, y: 345), in: wheelFrame))
        precondition(!WheelGeometry.containsWheel(CGPoint(x: -225, y: 345), in: wheelFrame))
        precondition(!WheelGeometry.containsWheel(CGPoint(x: -499, y: 201), in: wheelFrame))
        precondition(!WheelGeometry.containsWheel(CGPoint(x: 0, y: 0), in: wheelFrame))
        precondition(!WheelGeometry.containsWheel(.zero, in: .zero))
        // Context rules must never offer video output for audio, or convert an old selection.
        precondition(FileSelection(clicked: source, selected: [pdfFile]).files == [source])
        precondition(FileSelection(clicked: source, selected: [source, pdfFile, source]).files == [source, pdfFile])
        precondition(FileSelection.commonFormats([source, pdfFile]) == ["png", "jpg", "heic", "tiff", "txt", "docx"])
        precondition(FileKind.audio.formats == ["mp3"])
        precondition(FileKind.folder.formats.isEmpty)
        let second = tmp.appendingPathComponent("second.png")
        try FileActions.encode(image, format: "png").write(to: second)
        let broken = tmp.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: broken)
        let originalBytes = try Data(contentsOf: source)
        let utilities = FileActions()
        for files in [[source], [source, pdfFile]] {
            let titles = utilities.utilities(files).map(\.title)
            precondition(titles.contains("AirDrop") && titles.contains("Float"))
            precondition(!titles.contains("Duplicate") && !titles.contains("Metadata"))
        }
        let shelf = FloatingFilesModel()
        shelf.add([source, pdfFile, source])
        shelf.add([pdfFile, second])
        precondition(shelf.files == [source, pdfFile, second])
        shelf.remove([pdfFile])
        precondition(shelf.files == [source, second])
        shelf.clear()
        precondition(shelf.files.isEmpty)
        let afterShelf = try Data(contentsOf: source)
        precondition(afterShelf == originalBytes, "Shelf modified an original")
        let batch = BatchRunner.convert([source, broken, second], format: "jpg", workerEnabled: false, token: "")
        precondition(batch.outcomes.count == 3 && batch.failedCount == 1 && batch.outputs.count == 2)
        for out in batch.outputs { precondition(NSImage(contentsOf: out)?.isValid == true) }
        let after = try Data(contentsOf: source)
        precondition(originalBytes == after, "Batch conversion modified an original")
        var stop = false
        let cancelled = BatchRunner.convert([source, second], format: "png", workerEnabled: false, token: "", cancelled: { stop }, progress: { _, _ in stop = true })
        precondition(cancelled.cancelled && cancelled.outcomes.count == 1)
        let mixed = BatchRunner.convert([source, pdfFile], format: "png", workerEnabled: false, token: "")
        precondition(mixed.failedCount == 0 && mixed.outputs.count == 3)
        let combined = try FileActions.mergePDF([source, pdfFile], reveal: false)
        precondition(PDFDocument(url: combined)?.pageCount == 3)
        let split = try FileActions.splitPDF(combined)
        precondition(split.count == 3)
        for page in split { precondition(PDFDocument(url: page)?.pageCount == 1) }
        let jpgPreview = try PreviewRenderer.render(source, format: "jpg")
        precondition(jpgPreview.image?.isValid == true)
        precondition(jpgPreview.details.contains { $0.contains("Transparency becomes white") })
        precondition(jpgPreview.details.contains { $0.contains("sampled estimate") })
        let large = NSImage(size: NSSize(width: 2400, height: 1600), flipped: false) { rect in NSColor.blue.setFill(); rect.fill(); return true }
        let largeFile = tmp.appendingPathComponent("large.png")
        try FileActions.encode(large, format: "png").write(to: largeFile)
        let bounded = try PreviewRenderer.render(largeFile, format: "png")
        var boundedRect = CGRect(origin: .zero, size: bounded.image!.size)
        let boundedCG = bounded.image!.cgImage(forProposedRect: &boundedRect, context: nil, hints: nil)!
        precondition(max(boundedCG.width, boundedCG.height) <= PreviewRenderer.maximumPixelSize)
        let pdfPreview = try PreviewRenderer.render(pdfFile, format: "jpg")
        precondition(pdfPreview.details.contains { $0.contains("2 pages") })
        let mov = tmp.appendingPathComponent("video.mov")
        _ = try FileActions.process("/usr/bin/env", ["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=320x240:d=0.25", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-threads", "1", mov.path])
        let nativeVideo = try FileActions.convertAutomatically(mov, format: "mp4", workerEnabled: false, token: "", reveal: false)
        precondition(nativeVideo.count == 1)
        precondition(!AVURLAsset(url: nativeVideo[0]).tracks(withMediaType: .video).isEmpty)
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
        print("Native checks passed: PNG/JPEG/HEIC/TIFF/PDF, multipage PDF exports, output collisions, OCR, exact modifier bindings, every wheel sector, context intersection, batch failure/cancellation, PDF merge/split, bounded previews, native MP4")
    }
}
