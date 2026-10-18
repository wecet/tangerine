import AppKit
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Vision

struct ActionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
final class FileActions {
    var onBusy: ((Bool) -> Void)?
    private var busy = false
    var editor: NSWindow?
    static func image(_ file: URL) throws -> NSImage {
        if file.pathExtension.lowercased() == "pdf", let page = PDFDocument(url: file)?.page(at: 0) {
            return page.thumbnail(of: NSSize(width: 2400, height: 2400), for: .mediaBox)
        }
        guard let image = NSImage(contentsOf: file), image.isValid else { throw ActionError(message: "This file cannot be opened as an image.") }
        return image
    }
    func run(_ work: @escaping () throws -> Void) {
        guard !busy else { Self.alert("A task is already running. Please wait for it to finish."); return }
        busy = true; onBusy?(true)
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: Error?
            do { try work() } catch { failure = error }
            DispatchQueue.main.async { self.busy = false; self.onBusy?(false); if let failure { Self.alert(failure.localizedDescription) } }
        }
    }
    static func alert(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Tangerine"; alert.informativeText = message; alert.runModal()
    }
    static func output(for file: URL, suffix: String = "", ext: String) -> URL {
        let base = file.deletingPathExtension().lastPathComponent + suffix
        let folder = file.deletingLastPathComponent()
        var url = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext); n += 1 }
        return url
    }
    static func save(_ data: Data, to output: URL) throws {
        // O_EXCL semantics prevent races from overwriting an existing file.
        try data.write(to: output, options: [.withoutOverwriting])
        DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([output]) }
    }
    func conversions(_ file: URL) -> [WheelAction] {
        let type = (try? file.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        let image = type?.conforms(to: .image) == true
        let pdf = type?.conforms(to: .pdf) == true
        let media = type?.conforms(to: .movie) == true || type?.conforms(to: .audio) == true
        var actions: [WheelAction] = []
        let formats = image ? ["png", "jpg", "webp", "heic", "tiff", "pdf", "txt", "docx"] : pdf ? ["png", "jpg", "txt", "docx"] : media ? ["mp4", "mp3", "gif"] : []
        for format in formats {
            let worker = ["webp", "mp4", "mp3", "gif"].contains(format)
            actions.append(WheelAction(title: format, symbol: worker ? "arrow.triangle.2.circlepath" : "doc", enabled: !worker || Settings.shared.workerEnabled) { [weak self] in
                self?.run { if worker { try Self.workerConvert(file, format: format) } else { try Self.convert(file, format: format) } }
            })
        }
        if actions.isEmpty { actions = [WheelAction(title: "No formats", symbol: "nosign", enabled: false, perform: {})] }
        return actions
    }
    func utilities(_ file: URL) -> [WheelAction] {
        let image = (try? file.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) == true
        return [
            WheelAction(title: "Compress", symbol: "arrow.down.right.and.arrow.up.left") { [weak self] in self?.run { try Self.compress(file) } },
            WheelAction(title: "Metadata", symbol: "info.circle") { Self.metadata(file) },
            WheelAction(title: "Preview", symbol: "pencil.tip") { NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Preview.app"), configuration: NSWorkspace.OpenConfiguration()) },
            WheelAction(title: "Copy path", symbol: "link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.path, forType: .string) },
            WheelAction(title: "Add BG", symbol: "photo.on.rectangle", enabled: image) { [weak self] in self?.openEditor(file, mode: .background) },
            WheelAction(title: "Crop", symbol: "crop", enabled: image) { [weak self] in self?.openEditor(file, mode: .crop) },
            WheelAction(title: "Duplicate", symbol: "doc.on.doc") { [weak self] in self?.run { let out = Self.output(for: file, suffix: " copy", ext: file.pathExtension); try FileManager.default.copyItem(at: file, to: out); DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([out]) } } },
            WheelAction(title: "Rename", symbol: "character.cursor.ibeam") { Self.rename(file) }
        ]
    }
    static func convert(_ file: URL, format: String) throws {
        if ["txt", "docx"].contains(format) {
            var text = ""
            if file.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: file) {
                for index in 0..<doc.pageCount {
                    guard let page = doc.page(at: index) else { continue }
                    let extracted = page.string ?? ""
                    if extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        text += try recognize(page.thumbnail(of: NSSize(width: 2200, height: 2200), for: .mediaBox)) + "\n"
                    } else { text += extracted + "\n" }
                }
            } else { text = try recognize(image(file)) }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ActionError(message: "No text was detected in this file.") }
            if format == "txt" { try save(Data(text.utf8), to: output(for: file, ext: "txt")); return }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
            defer { try? FileManager.default.removeItem(at: temp) }
            try Data(text.utf8).write(to: temp)
            let data = try process("/usr/bin/textutil", ["-convert", "docx", "-stdout", temp.path])
            try save(data, to: output(for: file, ext: "docx")); return
        }
        if file.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: file), doc.pageCount > 1 {
            // Export every page; never silently drop later pages.
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index) else { continue }
                try save(encode(page.thumbnail(of: NSSize(width: 2400, height: 2400), for: .mediaBox), format: format), to: output(for: file, suffix: " page \(index + 1)", ext: format))
            }
        } else { try save(encode(image(file), format: format), to: output(for: file, ext: format)) }
    }
    static func recognize(_ image: NSImage) throws -> String {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw ActionError(message: "Cannot read image pixels.") }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cg).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    static func encode(_ image: NSImage, format: String) throws -> Data {
        var rect = CGRect(origin: .zero, size: image.size)
        guard var cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw ActionError(message: "Cannot read image pixels.") }
        if format == "pdf" {
            let doc = PDFDocument(); guard let page = PDFPage(image: image) else { throw ActionError(message: "Cannot create PDF.") }
            doc.insert(page, at: 0); guard let data = doc.dataRepresentation() else { throw ActionError(message: "Cannot write PDF.") }; return data
        }
        if format == "jpg", let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height)); context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)); cg = context.makeImage()!
        }
        let types = ["png": UTType.png, "jpg": UTType.jpeg, "tiff": UTType.tiff, "heic": UTType.heic]
        guard let type = types[format] else { throw ActionError(message: "Unsupported output format.") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { throw ActionError(message: "This Mac cannot encode \(format.uppercased()).") }
        CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ActionError(message: "Image conversion failed.") }
        return data as Data
    }
    static func process(_ executable: String, _ args: [String]) throws -> Data {
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ActionError(message: "The operation failed. Check the file format and available disk space.") }; return data
    }
    static func compress(_ file: URL) throws {
        let out = output(for: file, ext: "zip")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        defer { try? FileManager.default.removeItem(at: temp) }
        _ = try process("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", file.path, temp.path])
        try FileManager.default.copyItem(at: temp, to: out)
        DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([out]) }
    }
    static func workerConvert(_ file: URL, format: String) throws {
        let token = Settings.shared.token
        guard !token.isEmpty else { throw ActionError(message: "Worker credentials are missing. Run scripts/deploy.sh and reopen the rebuilt app.") }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        // Upload and download directly from disk; no whole-video buffering in the app.
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["--silent", "--show-error", "--fail", "--max-time", "330", "--connect-timeout", "3", "--config", "-", "--header", "Content-Type: application/octet-stream", "--data-binary", "@" + file.path, "--output", temp.path, "http://127.0.0.1:8765/convert?format=" + format]
        let input = Pipe(); p.standardInput = input; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); input.fileHandleForWriting.write(Data("header = \"Authorization: Bearer \(token)\"\n".utf8)); try input.fileHandleForWriting.close(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ActionError(message: "Media conversion failed. Check Docker is running (scripts/deploy.sh). Files must be under 128 MiB; conversions time out after five minutes. The file may be unsupported or exceed the worker's memory limit.") }
        let out = output(for: file, ext: format); try FileManager.default.copyItem(at: temp, to: out)
        DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([out]) }
    }
    static func metadata(_ file: URL) {
        do {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .contentTypeKey])
            var info = "\(file.path)\n\nType: \(values.contentType?.identifier ?? "Unknown")\nSize: \(ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file))\nCreated: \(values.creationDate?.description ?? "Unknown")\nModified: \(values.contentModificationDate?.description ?? "Unknown")"
            if let source = CGImageSourceCreateWithURL(file as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) { info += "\n\nImage properties:\n\(props)" }
            alert(info)
        } catch { alert(error.localizedDescription) }
    }
    static func rename(_ file: URL) {
        let alert = NSAlert(); alert.messageText = "Rename \(file.lastPathComponent)"; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: file.lastPathComponent); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24); alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), name != file.lastPathComponent else { return }
        do { try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent(name)) } catch { Self.alert(error.localizedDescription) }
    }
}
