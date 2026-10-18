import Foundation
import UniformTypeIdentifiers

enum FileKind: String {
    case image, pdf, video, audio, folder, other
    static func of(_ file: URL) -> FileKind {
        guard let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]) else { return .other }
        if values.isDirectory == true { return .folder }
        guard let type = values.contentType else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .other
    }
    var formats: [String] {
        switch self {
        case .image: return ["png", "jpg", "webp", "heic", "tiff", "pdf", "txt", "docx"]
        case .pdf: return ["png", "jpg", "heic", "tiff", "txt", "docx"]
        case .video: return ["mp4", "mp3", "gif"]
        case .audio: return ["mp3"]
        case .folder, .other: return []
        }
    }
}
struct FileSelection {
    let files: [URL]
    init(clicked: URL, selected: [URL]) {
        let clicked = clicked.standardizedFileURL
        let unique = Self.unique(selected)
        // A different selection must never become a batch merely because it exists.
        files = unique.contains(clicked) ? unique : [clicked]
    }
    static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.map(\.standardizedFileURL).filter { $0.isFileURL && seen.insert($0).inserted }
    }
    static func commonFormats(_ files: [URL]) -> [String] {
        guard let first = files.first else { return [] }
        return files.dropFirst().reduce(FileKind.of(first).formats) { current, file in
            let supported = Set(FileKind.of(file).formats)
            return current.filter(supported.contains)
        }
    }
}
struct ConversionOutcome {
    let input: URL
    let outputs: [URL]
    let error: String?
}
struct BatchResult {
    let outcomes: [ConversionOutcome]
    let cancelled: Bool
    var outputs: [URL] { outcomes.flatMap(\.outputs) }
    var failedCount: Int { outcomes.filter { $0.error != nil }.count }
}
enum BatchRunner {
    static func convert(_ files: [URL], format: String, workerEnabled: Bool, token: String,
                        cancelled: () -> Bool = { false },
                        progress: (Int, URL) -> Void = { _, _ in }) -> BatchResult {
        var outcomes: [ConversionOutcome] = []
        for (index, file) in files.enumerated() {
            if cancelled() { return BatchResult(outcomes: outcomes, cancelled: true) }
            progress(index, file)
            let outcome: ConversionOutcome = autoreleasepool {
                do {
                    guard FileKind.of(file).formats.contains(format) else { throw ActionError(message: "This file cannot be converted to \(format.uppercased()).") }
                    let outputs = try FileActions.convertAutomatically(file, format: format, workerEnabled: workerEnabled, token: token, reveal: false)
                    return ConversionOutcome(input: file, outputs: outputs, error: nil)
                } catch { return ConversionOutcome(input: file, outputs: [], error: error.localizedDescription) }
            }
            outcomes.append(outcome)
        }
        return BatchResult(outcomes: outcomes, cancelled: false)
    }
}
