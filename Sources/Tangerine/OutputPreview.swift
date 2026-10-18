import AppKit
import SwiftUI
import ImageIO
import PDFKit
import AVFoundation

struct OutputPreview {
    let image: NSImage?
    let text: String?
    let heading: String
    let details: [String]
}
enum PreviewRenderer {
    static let maximumPixelSize = 768
    static func render(_ file: URL, format: String) throws -> OutputPreview {
        let kind = FileKind.of(file)
        if kind == .video || kind == .audio {
            var thumbnail: NSImage?
            if kind == .video {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
                generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 480, height: 270)
                if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) { thumbnail = NSImage(cgImage: cg, size: .zero) }
            }
            let note = format == "mp4" ? "Native macOS export, up to 720p" : format == "gif" ? "12 fps · up to 640 px · first 30 seconds" : "192 kbps MP3 · requires an audio stream"
            return OutputPreview(image: thumbnail, text: nil, heading: format.uppercased(), details: [note, "Source thumbnail · playback is not transcoded on hover"])
        }
        let sample: NSImage
        var width = 0, height = 0, pages = 1
        if kind == .pdf {
            guard let doc = PDFDocument(url: file), !doc.isLocked, let page = doc.page(at: 0) else { throw ActionError(message: "This PDF is locked or has no readable pages.") }
            pages = doc.pageCount
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(2400 / max(bounds.width, 1), 2400 / max(bounds.height, 1))
            width = Int(bounds.width * scale); height = Int(bounds.height * scale)
            sample = page.thumbnail(of: NSSize(width: maximumPixelSize, height: maximumPixelSize), for: .mediaBox)
            if ["txt", "docx"].contains(format), let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return OutputPreview(image: nil, text: String(text.prefix(1200)), heading: format.uppercased(), details: ["Text excerpt · first page of \(pages)", format == "docx" ? "DOCX preserves text, not the original page layout" : "Full conversion extracts all pages"])
            }
        } else {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw ActionError(message: "No image preview is available.") }
            width = properties[kCGImagePropertyPixelWidth] as? Int ?? cg.width
            height = properties[kCGImagePropertyPixelHeight] as? Int ?? cg.height
            if (properties[kCGImagePropertyOrientation] as? Int ?? 1) >= 5 { swap(&width, &height) }
            sample = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        if ["txt", "docx"].contains(format) {
            let text = try FileActions.recognize(sample)
            return OutputPreview(image: nil, text: text.isEmpty ? "No text detected in this sample." : String(text.prefix(1200)), heading: format.uppercased(), details: ["On-device OCR sample", "Full conversion reads the entire file"])
        }
        var details = ["\(width) × \(height) px" + (pages > 1 ? " · \(pages) pages" : "")]
        details.append(format == "jpg" ? "Transparency becomes white" : format == "pdf" ? "One image per PDF page" : "Transparency supported")
        if FileActions.needsWorker(format) {
            details.append("Source thumbnail · output uses local media worker")
            return OutputPreview(image: sample, text: nil, heading: format.uppercased(), details: details)
        }
        let data = try FileActions.encode(sample, format: format)
        let decoded: NSImage?
        if format == "pdf", let page = PDFDocument(data: data)?.page(at: 0) { decoded = page.thumbnail(of: NSSize(width: 320, height: 240), for: .mediaBox) }
        else { decoded = NSImage(data: data) }
        var sampleRect = CGRect(origin: .zero, size: sample.size)
        let cg = sample.cgImage(forProposedRect: &sampleRect, context: nil, hints: nil)
        let samplePixels = max(1, Double((cg?.width ?? 1) * (cg?.height ?? 1)))
        let ratio = max(1, Double(width) * Double(height) / samplePixels)
        let estimate = Int64(min(Double(Int64.max / 2), Double(data.count) * ratio))
        details.append("≈ " + ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file) + (pages > 1 ? " per page" : "") + " · sampled estimate")
        details.append(pages > 1 ? "First-page output preview" : "Encoded sample · final size may differ")
        return OutputPreview(image: decoded ?? sample, text: nil, heading: format.uppercased(), details: details)
    }
}
private final class PreviewBox: NSObject {
    let value: OutputPreview
    init(_ value: OutputPreview) { self.value = value }
}
final class PreviewModel: ObservableObject {
    @Published var result: OutputPreview?
    @Published var loading = false
    @Published var error: String?
    private let queue = DispatchQueue(label: "local.tangerine.preview", qos: .userInitiated)
    private let cache = NSCache<NSString, PreviewBox>()
    private var generation = UUID()
    init() { cache.countLimit = 12; cache.totalCostLimit = 24 * 1024 * 1024 }
    func clear() { generation = UUID(); result = nil; error = nil; loading = false }
    func request(_ file: URL, format: String) {
        let id = UUID(); generation = id; result = nil; error = nil; loading = true
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(file.path)|\(modified)|\(format)" as NSString
        if let cached = cache.object(forKey: key) { result = cached.value; loading = false; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.generation == id else { return }
            self.queue.async {
                let value: Result<OutputPreview, Error> = Result { try PreviewRenderer.render(file, format: format) }
                DispatchQueue.main.async {
                    guard self.generation == id else { return }
                    self.loading = false
                    switch value {
                    case .success(let preview):
                        self.cache.setObject(PreviewBox(preview), forKey: key, cost: 768 * 768 * 4)
                        self.result = preview
                    case .failure(let error): self.error = error.localizedDescription
                    }
                }
            }
        }
    }
}
struct OutputPreviewView: View {
    @ObservedObject var model: PreviewModel
    var selectionCount = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "eye"); Text("Output preview").font(.headline); Spacer(); if model.loading { ProgressView().controlSize(.small) } }
            if let result = model.result {
                Text(result.heading).font(.title3.bold())
                if let image = result.image {
                    ZStack { RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)); Image(nsImage: image).resizable().scaledToFit().padding(6) }.frame(height: 145)
                }
                if let text = result.text { ScrollView { Text(text).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(height: 145) }
                ForEach(Array(result.details.enumerated()), id: \.offset) { _, text in Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            } else if let error = model.error { Text(error).font(.callout).foregroundStyle(.secondary) }
            else { Text(model.loading ? "Preparing a bounded preview…" : "Hover over a format to preview the result.").font(.callout).foregroundStyle(.secondary) }
            if selectionCount > 1 { Divider(); Text("Sample: first selected file · \(selectionCount) files in batch").font(.caption).foregroundStyle(.secondary) }
        }.padding(16).frame(width: 240, alignment: .leading).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.25), lineWidth: 1))
    }
}
