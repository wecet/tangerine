import AppKit
import AVFoundation
import ImageIO

extension FileActions {
    static var nativeWebP: Bool { (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains("org.webmproject.webp") }
    static func needsWorker(_ format: String) -> Bool { ["mp3", "gif"].contains(format) || (format == "webp" && !nativeWebP) }
    static func convertAutomatically(_ file: URL, format: String, workerEnabled: Bool, token: String, reveal: Bool) throws -> [URL] {
        if format == "mp4" {
            do { return [try nativeMP4(file, reveal: reveal)] }
            catch { if !workerEnabled { throw error } }
        }
        if needsWorker(format) || format == "mp4" {
            guard workerEnabled else { throw ActionError(message: "This output needs the local media worker. Enable it in Settings and start Docker.") }
            return [try workerConvert(file, format: format, reveal: reveal, token: token)]
        }
        return try convert(file, format: format, reveal: reveal)
    }
    static func nativeMP4(_ file: URL, reveal: Bool) throws -> URL {
        let asset = AVURLAsset(url: file)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720), export.supportedFileTypes.contains(.mp4) else {
            throw ActionError(message: "macOS cannot export this video to MP4.")
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: temp) }
        export.outputURL = temp; export.outputFileType = .mp4; export.shouldOptimizeForNetworkUse = true
        let done = DispatchSemaphore(value: 0)
        export.exportAsynchronously { done.signal() }
        if done.wait(timeout: .now() + 300) == .timedOut {
            export.cancelExport()
            _ = done.wait(timeout: .now() + 5)
            throw ActionError(message: "Native video export timed out.")
        }
        guard export.status == .completed else { throw export.error ?? ActionError(message: "Native video export failed.") }
        let out = output(for: file, ext: "mp4")
        try FileManager.default.copyItem(at: temp, to: out)
        if reveal { DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([out]) } }
        return out
    }
}
