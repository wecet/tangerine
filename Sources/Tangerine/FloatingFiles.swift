import AppKit
import SwiftUI
import QuickLookThumbnailing

final class FloatingFilesModel: ObservableObject {
    @Published private(set) var files: [URL] = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    private var requests: [URL: QLThumbnailGenerator.Request] = [:]
    func add(_ urls: [URL]) {
        files = FileSelection.unique(files + urls)
        for file in files where thumbnails[file] == nil && requests[file] == nil {
            let request = QLThumbnailGenerator.Request(fileAt: file, size: NSSize(width: 96, height: 96), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            requests[file] = request
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
                DispatchQueue.main.async {
                    guard let self, self.requests[file] === request else { return }
                    self.requests.removeValue(forKey: file)
                    if self.files.contains(file), let thumbnail { self.thumbnails[file] = thumbnail.nsImage }
                }
            }
        }
    }
    func remove(_ urls: [URL]) {
        let removed = Set(urls)
        files.removeAll { removed.contains($0) }
        for file in urls {
            thumbnails.removeValue(forKey: file)
            if let request = requests.removeValue(forKey: file) { QLThumbnailGenerator.shared.cancel(request) }
        }
    }
    func clear() { remove(files) }
    func icon(_ file: URL) -> NSImage { thumbnails[file] ?? NSWorkspace.shared.icon(forFile: file.path) }
}

private final class FloatingFilesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class FloatingFilesController {
    let model = FloatingFilesModel()
    private(set) var panel: NSPanel?
    private var expanded = false
    func show(_ files: [URL]) {
        model.add(files)
        guard !model.files.isEmpty else { return }
        if panel == nil {
            let panel = FloatingFilesPanel(contentRect: NSRect(x: 0, y: 0, width: 116, height: 136), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Floating files"
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.level = .floating; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            let root = FloatingFilesView(model: model, expand: { [weak self] in self?.setExpanded($0) }, close: { [weak self] in self?.close() }, dragged: { [weak self] in self?.didDrag($0) })
            panel.contentView = FloatingDropView(root: root, model: model)
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let bounds = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: bounds.maxX - 140, y: bounds.midY - 68))
            }
            self.panel = panel
        }
        setExpanded(expanded)
        panel?.orderFrontRegardless()
    }
    private func setExpanded(_ value: Bool) {
        expanded = value
        guard let panel else { return }
        let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let size = NSSize(width: value ? 160 : 116, height: value ? min(540, bounds.height, CGFloat(model.files.count) * 82 + 148) : 136)
        let x = max(bounds.minX, min(panel.frame.midX - size.width / 2, bounds.maxX - size.width))
        let y = max(bounds.minY, min(panel.frame.maxY - size.height, bounds.maxY - size.height))
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }
    private func didDrag(_ files: [URL]) {
        model.remove(files)
        if model.files.isEmpty { close() } else { setExpanded(expanded) }
    }
    private func close() {
        panel?.orderOut(nil); panel = nil; expanded = false; model.clear()
    }
}

private struct FloatingFilesView: View {
    @ObservedObject var model: FloatingFilesModel
    let expand: (Bool) -> Void
    let close: () -> Void
    let dragged: ([URL]) -> Void
    @State private var expanded = false
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: close) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Close shelf")
                Spacer()
                Image(systemName: "paperclip").foregroundStyle(.secondary)
            }.font(.system(size: 12)).padding(.horizontal, 10).padding(.top, 9)
            FileDragView(files: model.files, completed: dragged, clicked: { setExpanded(!expanded) }, content: AnyView(
                ZStack {
                    ForEach(Array(model.files.suffix(3).enumerated()), id: \.element) { index, file in
                        Image(nsImage: model.icon(file)).resizable().scaledToFit().frame(width: 62, height: 62)
                            .rotationEffect(.degrees(Double(index - 1) * 9)).offset(x: CGFloat(index - 1) * 4)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            )).frame(height: 64).help("Drag all files · Click to expand or collapse")
            Text("\(model.files.count) \(model.files.count == 1 ? "item" : "items")").font(.system(size: 10, weight: .medium))
            if expanded {
                Divider().padding(.horizontal, 12)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.files, id: \.self) { file in
                            FileDragView(files: [file], completed: dragged, clicked: { NSWorkspace.shared.activateFileViewerSelecting([file]) }, content: AnyView(
                                VStack(spacing: 3) {
                                    Image(nsImage: model.icon(file)).resizable().scaledToFit().frame(width: 44, height: 44)
                                    Text(file.lastPathComponent).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            )).frame(height: 74).help(file.path)
                        }
                    }.padding(.horizontal, 10)
                }
            }
            Text("Drop files to add").font(.system(size: 9)).foregroundStyle(.secondary).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.35), lineWidth: 1))
        .padding(2)
        .onHover { setExpanded($0) }
    }
    private func setExpanded(_ value: Bool) { expanded = value; expand(value) }
}

private final class FloatingDropView: NSHostingView<FloatingFilesView> {
    override var mouseDownCanMoveWindow: Bool { true }
    private let model: FloatingFilesModel
    init(root: FloatingFilesView, model: FloatingFilesModel) {
        self.model = model
        super.init(rootView: root)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable) required init(rootView: FloatingFilesView) { fatalError() }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Dropping back onto this shelf must not count as a successful export.
        sender.draggingSource is FileDragSourceView ? [] : (urls(sender).isEmpty ? [] : .copy)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !(sender.draggingSource is FileDragSourceView) else { return false }
        let files = urls(sender)
        guard !files.isEmpty else { return false }
        model.add(files); return true
    }
    private func urls(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}

private struct FileDragView: NSViewRepresentable {
    let files: [URL]
    let completed: ([URL]) -> Void
    let clicked: () -> Void
    let content: AnyView
    func makeNSView(context: Context) -> FileDragSourceView { FileDragSourceView() }
    func updateNSView(_ view: FileDragSourceView, context: Context) {
        view.files = files; view.completed = completed; view.clicked = clicked; view.host.rootView = content
    }
}

private final class FileDragSourceView: NSView, NSDraggingSource {
    var files: [URL] = []
    var completed: (([URL]) -> Void)?
    var clicked: (() -> Void)?
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var start: NSEvent?
    private var exported: [URL] = []
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        host.frame = bounds; host.autoresizingMask = [.width, .height]; addSubview(host)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { start = event }
    override func mouseUp(with event: NSEvent) { if start != nil { clicked?() }; start = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let start, hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) > 4 else { return }
        self.start = nil
        exported = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !exported.isEmpty else { FileActions.alert("These files are no longer at their original locations."); return }
        let items = exported.map { file in
            let item = NSDraggingItem(pasteboardWriter: file as NSURL)
            item.setDraggingFrame(NSRect(x: bounds.midX - 24, y: bounds.midY - 24, width: 48, height: 48), contents: NSWorkspace.shared.icon(forFile: file.path))
            return item
        }
        beginDraggingSession(with: items, event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let files = exported; exported = []
        // Defer rebuilding the shelf until AppKit has finished the drag callback.
        if !operation.isEmpty {
            let completed = self.completed
            DispatchQueue.main.async { completed?(files) }
        }
    }
}
