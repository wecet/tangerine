import AppKit
import SwiftUI

private final class StopFlag {
    private let lock = NSLock()
    private var value = false
    func set(_ value: Bool) { lock.lock(); self.value = value; lock.unlock() }
    func read() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}
final class BatchConversionModel: ObservableObject {
    @Published var files: [URL]
    @Published var format: String
    @Published var selectedFile: URL?
    @Published var running = false
    @Published var completed = 0
    @Published var currentFile: URL?
    @Published var result: BatchResult?
    let preview = PreviewModel()
    private let stop = StopFlag()
    private weak var owner: FileActions?
    var formats: [String] { FileSelection.commonFormats(files) }
    var formatEnabled: Bool { !FileActions.needsWorker(format) || Settings.shared.workerEnabled }
    init(files: [URL], format: String?, owner: FileActions) {
        self.files = FileSelection.unique(files)
        self.format = format ?? FileSelection.commonFormats(files).first ?? ""
        self.owner = owner; self.selectedFile = files.first
    }
    func refresh() {
        if !formats.contains(format) { format = formats.first ?? "" }
        if selectedFile == nil || !files.contains(selectedFile!) { selectedFile = files.first }
        result = nil
        refreshPreview()
    }
    func refreshPreview() {
        guard let file = selectedFile, !format.isEmpty else { preview.clear(); return }
        preview.request(file, format: format)
    }
    func remove(_ file: URL) { guard !running else { return }; files.removeAll { $0 == file }; refresh() }
    func move(_ file: URL, offset: Int) {
        guard !running, let index = files.firstIndex(of: file), files.indices.contains(index + offset) else { return }
        files.swapAt(index, index + offset); refresh()
    }
    func addFiles() {
        guard !running else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Choose files to convert. Only formats shared by every file will be offered."
        if panel.runModal() == .OK { files = FileSelection.unique(files + panel.urls); refresh() }
    }
    func start() {
        guard !running, !files.isEmpty, formats.contains(format), formatEnabled, let owner, owner.beginTask() else { return }
        running = true; result = nil; completed = 0; stop.set(false)
        let files = files, format = format, worker = Settings.shared.workerEnabled, token = Settings.shared.token
        DispatchQueue.global(qos: .userInitiated).async {
            let result = BatchRunner.convert(files, format: format, workerEnabled: worker, token: token, cancelled: { self.stop.read() }, progress: { index, file in
                DispatchQueue.main.async { self.completed = index; self.currentFile = file }
            })
            DispatchQueue.main.async {
                self.result = result; self.completed = result.outcomes.count; self.currentFile = nil; self.running = false
                owner.endTask()
            }
        }
    }
    func requestStop() { stop.set(true) }
    func status(_ file: URL) -> String {
        if let outcome = result?.outcomes.first(where: { $0.input == file }) { return outcome.error ?? "Saved \(outcome.outputs.count) output\(outcome.outputs.count == 1 ? "" : "s")" }
        if currentFile == file { return "Converting…" }
        if running, let index = files.firstIndex(of: file), index < completed { return "Processed" }
        if result != nil { return "Not processed" }
        return FileKind.of(file).rawValue.capitalized
    }
}
struct BatchConversionView: View {
    @ObservedObject var model: BatchConversionModel
    @ObservedObject var settings = Settings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Convert files").font(.title2.bold()); Text("\(model.files.count) files · originals stay untouched").foregroundStyle(.secondary) }
                Spacer()
                Button("Add files…") { model.addFiles() }.disabled(model.running)
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    List(model.files, id: \.self) { file in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.lastPathComponent).lineLimit(1)
                                Text(model.status(file)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            if model.selectedFile == file { Image(systemName: "eye").foregroundStyle(settings.accent) }
                            Button { model.move(file, offset: -1) } label: { Image(systemName: "chevron.up") }.help("Move earlier").disabled(model.running || model.files.first == file)
                            Button { model.move(file, offset: 1) } label: { Image(systemName: "chevron.down") }.help("Move later").disabled(model.running || model.files.last == file)
                            Button { model.remove(file) } label: { Image(systemName: "minus.circle") }.help("Remove from this batch").disabled(model.running)
                        }.buttonStyle(.borderless).padding(.vertical, 5).contentShape(Rectangle()).onTapGesture { model.selectedFile = file; model.refreshPreview() }
                    }.frame(minHeight: 290).clipShape(RoundedRectangle(cornerRadius: 10))
                    if model.formats.isEmpty { Text("These files have no shared output format. Remove incompatible files or start another batch.").font(.callout).foregroundStyle(.secondary) }
                    else {
                        Picker("Output", selection: $model.format) { ForEach(model.formats, id: \.self) { Text($0.uppercased()).tag($0) } }.disabled(model.running)
                        if !model.formatEnabled { Text("Enable the local media worker in Settings for this format.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                OutputPreviewView(model: model.preview).frame(width: 272)
            }
            if model.running {
                ProgressView(value: Double(model.completed), total: Double(max(1, model.files.count)))
                HStack { Text("\(model.completed) of \(model.files.count) processed").font(.callout); Spacer(); Button("Stop after current file") { model.requestStop() } }
            } else {
                HStack {
                    if let result = model.result {
                        Text("\(result.outcomes.count - result.failedCount) succeeded · \(result.failedCount) failed" + (result.cancelled ? " · stopped" : "")).font(.callout)
                        if !result.outputs.isEmpty { Button("Reveal outputs") { NSWorkspace.shared.activateFileViewerSelecting(result.outputs) } }
                    } else { Text("Outputs are saved beside each original.").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Convert \(model.files.count) file\(model.files.count == 1 ? "" : "s")") { model.start() }.buttonStyle(.borderedProminent).disabled(model.files.isEmpty || model.formats.isEmpty || !model.formatEnabled)
                }
            }
        }.padding(24).frame(width: 860, height: 520).tint(settings.accent)
            .onAppear { model.refreshPreview() }
            .onChange(of: model.format) { _ in model.refreshPreview() }
    }
}
extension FileActions {
    func chooseFiles(_ initial: [URL] = []) {
        if batchModel?.running == true { batchWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Choose one or more files to preview and convert."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { openBatch(panel.urls) }
    }
    func openBatch(_ files: [URL], format: String? = nil) {
        if batchModel?.running == true { batchWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        batchWindow?.close()
        let model = BatchConversionModel(files: files, format: format, owner: self)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 908, height: 568), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Convert files — Tangerine"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: BatchConversionView(model: model))
        batchModel = model; batchWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
}
