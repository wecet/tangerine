import AppKit
import ApplicationServices

final class FinderMonitor {
    var onClick: (([URL], Bool, CGPoint) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowed = false
    func start() {
        let settings = Settings.shared
        guard settings.enabled else { stop(); settings.connectionStatus = "Wheels paused"; return }
        guard settings.conversion != settings.utilities else { stop(); settings.connectionStatus = "Choose different click bindings"; return }
        guard AXIsProcessTrusted() else { stop(); settings.connectionStatus = "This running app does not have Accessibility access"; return }
        if let tap, CGEvent.tapIsEnabled(tap: tap) { settings.connectionStatus = "Ready · Finder & Desktop"; return }
        stop()
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<FinderMonitor>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            settings.connectionStatus = "Ready · Finder & Desktop"
        } else {
            settings.connectionStatus = "Accessibility granted, but mouse event access failed. Quit and reopen Tangerine."
        }
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; swallowed = false
    }
    var active: Bool { tap != nil }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseUp, swallowed { swallowed = false; return nil }
        guard type == .leftMouseDown, Settings.shared.enabled else { return Unmanaged.passUnretained(event) }
        let convert = Settings.shared.conversion.matches(event.flags)
        guard convert || Settings.shared.utilities.matches(event.flags) else { return Unmanaged.passUnretained(event) }
        Settings.shared.lastClickStatus = "Bound click received; checking Finder item…"
        guard let file = clickedFile(at: event.location) else { return Unmanaged.passUnretained(event) }
        swallowed = true
        let location = event.location
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let files = self.selectionForClick(file, at: location)
            Settings.shared.lastClickStatus = "Opened \(convert ? "conversion" : "utilities") wheel · \(files.count) file(s)."
            self.onClick?(files, convert, location)
        }
        return nil
    }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    private func fileURL(_ value: CFTypeRef?) -> URL? {
        if let url = value as? URL, url.isFileURL { return url }
        if let raw = value as? String, let url = URL(string: raw), url.isFileURL { return url }
        return nil
    }
    private func selectedItemURL(_ element: AXUIElement, folder: URL, depth: Int = 0) -> URL? {
        if let url = fileURL(attribute(element, kAXURLAttribute)), FileManager.default.fileExists(atPath: url.path) { return url }
        for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
            if let name = attribute(element, key) as? String, !name.isEmpty, !name.contains("/"), name != ".", name != ".." {
                let candidate = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        if depth < 2, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children.prefix(32) {
                if let url = selectedItemURL(child, folder: folder, depth: depth + 1) { return url }
            }
        }
        return nil
    }
    private func selectionForClick(_ clicked: URL, at point: CGPoint) -> [URL] {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, var element = hit else { return [clicked] }
        let folder = clicked.deletingLastPathComponent()
        for _ in 0..<12 {
            for key in [kAXSelectedChildrenAttribute, "AXSelectedRows"] {
                if let selected = attribute(element, key) as? [AXUIElement], selected.count > 1, selected.count <= 256 {
                    let urls = selected.compactMap { selectedItemURL($0, folder: folder) }
                    // Only a complete current selection containing the clicked item becomes a batch.
                    if urls.count == selected.count {
                        let snapshot = FileSelection(clicked: clicked, selected: urls)
                        if snapshot.files.count > 1 { return snapshot.files }
                    }
                }
            }
            if (attribute(element, kAXRoleAttribute) as? String) == kAXWindowRole { break }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return [clicked]
    }
    private func clickedFile(at point: CGPoint) -> URL? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, var element = hit else {
            Settings.shared.lastClickStatus = "Click received; macOS could not resolve the item under the pointer."
            return nil
        }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder" else {
            Settings.shared.lastClickStatus = "Click passed through: the target belongs to another app."
            return nil
        }
        AXUIElementSetMessagingTimeout(element, 0.08)
        var names: [String] = []
        var folder: URL?
        var desktop = false
        for _ in 0..<9 {
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            // Never treat the folder represented by a window as the clicked item.
            if role == kAXWindowRole {
                folder = fileURL(attribute(element, kAXDocumentAttribute))
                desktop = (attribute(element, kAXSubroleAttribute) as? String) == "AXDesktop"
                break
            }
            if let url = attribute(element, kAXURLAttribute) as? URL, url.isFileURL, FileManager.default.fileExists(atPath: url.path) { return url }
            if let raw = attribute(element, kAXURLAttribute) as? String, let url = URL(string: raw), url.isFileURL, FileManager.default.fileExists(atPath: url.path) { return url }
            if [kAXImageRole, kAXStaticTextRole, kAXTextFieldRole, kAXRowRole, kAXCellRole].contains(role) {
                for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                    if let name = attribute(element, key) as? String, !name.isEmpty, !name.contains("/") { names.append(name) }
                }
            }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { desktop = true; break }
            element = unsafeBitCast(parent, to: AXUIElement.self)
        }
        if desktop && folder == nil { folder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first }
        guard let folder, folder.isFileURL else {
            Settings.shared.lastClickStatus = "Finder item found; its containing folder was not available."
            return nil
        }
        for name in names {
            let candidate = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        Settings.shared.lastClickStatus = "Finder click received, but the filename could not be resolved (\(names.count) candidates)."
        return nil // Fail closed: never operate on a previous Finder selection.
    }
}
