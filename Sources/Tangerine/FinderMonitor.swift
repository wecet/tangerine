import AppKit
import ApplicationServices

final class FinderMonitor {
    var onClick: ((URL, Bool, CGPoint) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowed = false
    func start() {
        stop()
        guard Settings.shared.enabled, Settings.shared.conversion != Settings.shared.utilities, AXIsProcessTrusted() else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<FinderMonitor>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
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
        guard convert || Settings.shared.utilities.matches(event.flags), let file = clickedFile(at: event.location) else { return Unmanaged.passUnretained(event) }
        swallowed = true
        let location = event.location
        DispatchQueue.main.async { [weak self] in self?.onClick?(file, convert, location) }
        return nil
    }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    private func clickedFile(at point: CGPoint) -> URL? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, var element = hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder" else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.08)
        var names: [String] = []
        var folder: URL?
        var desktop = false
        for _ in 0..<9 {
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            // Never treat the folder represented by a window as the clicked item.
            if role == kAXWindowRole {
                if let doc = attribute(element, kAXDocumentAttribute) as? String { folder = URL(string: doc) }
                desktop = (attribute(element, kAXSubroleAttribute) as? String) == "AXDesktop"
                break
            }
            if let url = attribute(element, kAXURLAttribute) as? URL, url.isFileURL, FileManager.default.fileExists(atPath: url.path) { return url }
            if let raw = attribute(element, kAXURLAttribute) as? String, let url = URL(string: raw), url.isFileURL, FileManager.default.fileExists(atPath: url.path) { return url }
            if [kAXImageRole, kAXStaticTextRole, kAXTextFieldRole, kAXRowRole, kAXCellRole].contains(role) {
                for key in [kAXTitleAttribute, kAXValueAttribute] {
                    if let name = attribute(element, key) as? String, !name.isEmpty, !name.contains("/") { names.append(name) }
                }
            }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { desktop = true; break }
            element = unsafeBitCast(parent, to: AXUIElement.self)
        }
        if desktop && folder == nil { folder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first }
        guard let folder, folder.isFileURL else { return nil }
        for name in names {
            let candidate = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil // Fail closed: never operate on a previous Finder selection.
    }
}
