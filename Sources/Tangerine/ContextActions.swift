import AppKit
import PDFKit

extension FileActions {
    func conversions(_ file: URL) -> [WheelAction] { conversions([file]) }
    func conversions(_ files: [URL]) -> [WheelAction] {
        let formats = FileSelection.commonFormats(files)
        guard !formats.isEmpty else {
            return [WheelAction(title: "Choose files", symbol: "doc.badge.plus") { [weak self] in self?.chooseFiles(files) }]
        }
        return formats.map { format in
            WheelAction(title: format, symbol: needsWorkerSymbol(format), enabled: !Self.needsWorker(format) || Settings.shared.workerEnabled, previewFormat: format) { [weak self] in
                guard let self else { return }
                if files.count > 1 { self.openBatch(files, format: format) }
                else if let file = files.first {
                    let worker = Settings.shared.workerEnabled, token = Settings.shared.token
                    self.run { _ = try Self.convertAutomatically(file, format: format, workerEnabled: worker, token: token, reveal: true) }
                }
            }
        }
    }
    private func needsWorkerSymbol(_ format: String) -> String { Self.needsWorker(format) ? "arrow.triangle.2.circlepath" : "doc" }
    func utilities(_ file: URL) -> [WheelAction] { utilities([file]) }
    func utilities(_ files: [URL]) -> [WheelAction] {
        guard let first = files.first else { return [] }
        let kinds = Set(files.map { FileKind.of($0) })
        let single = files.count == 1
        var items: [WheelAction] = []
        if single && kinds == [.image] {
            items += [WheelAction(title: "Crop", symbol: "crop") { [weak self] in self?.openEditor(first, mode: .crop) },
                      WheelAction(title: "Add BG", symbol: "photo.on.rectangle") { [weak self] in self?.openEditor(first, mode: .background) }]
        }
        if kinds.isSubset(of: [.image, .pdf]) && files.count > 1 {
            items.append(WheelAction(title: "Merge PDF", symbol: "rectangle.stack") { [weak self] in self?.run { _ = try Self.mergePDF(files) } })
        }
        if kinds == [.pdf] {
            items.append(WheelAction(title: "Split PDF", symbol: "rectangle.split.3x1") { [weak self] in self?.run {
                var outputs: [URL] = []
                for file in files { outputs += try Self.splitPDF(file) }
                DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
            } })
        }
        if single {
            items.append(WheelAction(title: kinds == [.image] || kinds == [.pdf] ? "Preview" : "Open", symbol: "arrow.up.forward.app") {
                if kinds == [.image] || kinds == [.pdf] { NSWorkspace.shared.open([first], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Preview.app"), configuration: NSWorkspace.OpenConfiguration()) }
                else { NSWorkspace.shared.open(first) }
            })
            items.append(WheelAction(title: "Metadata", symbol: "info.circle") { Self.metadata(first) })
        }
        items.append(WheelAction(title: "ZIP", symbol: "archivebox") { [weak self] in self?.run {
            var outputs: [URL] = []
            for file in files { outputs.append(try Self.compress(file, reveal: false)) }
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        } })
        items.append(WheelAction(title: files.count > 1 ? "Copy paths" : "Copy path", symbol: "link") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(files.map(\.path).joined(separator: "\n"), forType: .string)
        })
        items.append(WheelAction(title: "AirDrop", symbol: "airplayaudio") { [weak self] in self?.airDrop.share(files) })
        if single { items.append(WheelAction(title: "Rename", symbol: "character.cursor.ibeam") { Self.rename(first) }) }
        if !single { items.append(WheelAction(title: "Convert…", symbol: "arrow.triangle.2.circlepath") { [weak self] in self?.openBatch(files) }) }
        return items
    }
    @discardableResult
    static func mergePDF(_ files: [URL], reveal: Bool = true) throws -> URL {
        guard let first = files.first else { throw ActionError(message: "Choose at least one image or PDF.") }
        let result = PDFDocument()
        for file in files {
            switch FileKind.of(file) {
            case .pdf:
                guard let doc = PDFDocument(url: file), !doc.isLocked else { throw ActionError(message: "Cannot read \(file.lastPathComponent); it may be locked.") }
                for index in 0..<doc.pageCount {
                    guard let page = doc.page(at: index)?.copy() as? PDFPage else { throw ActionError(message: "Cannot read PDF page.") }
                    result.insert(page, at: result.pageCount)
                }
            case .image:
                guard let page = PDFPage(image: try image(file)) else { throw ActionError(message: "Cannot create a PDF page.") }
                result.insert(page, at: result.pageCount)
            default: throw ActionError(message: "Merge PDF supports images and PDFs only.")
            }
        }
        guard result.pageCount > 0, let data = result.dataRepresentation() else { throw ActionError(message: "No pages to combine.") }
        let out = output(for: first, suffix: " combined", ext: "pdf")
        try save(data, to: out, reveal: reveal); return out
    }
    static func splitPDF(_ file: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: file), !doc.isLocked else { throw ActionError(message: "Cannot open this PDF; it may be locked.") }
        var outputs: [URL] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index)?.copy() as? PDFPage else { throw ActionError(message: "Cannot read PDF page.") }
            let result = PDFDocument(); result.insert(page, at: 0)
            guard let data = result.dataRepresentation() else { throw ActionError(message: "Cannot write PDF page.") }
            let out = output(for: file, suffix: " page \(index + 1)", ext: "pdf")
            try save(data, to: out, reveal: false); outputs.append(out)
        }
        return outputs
    }
}
