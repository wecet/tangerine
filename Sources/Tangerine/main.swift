import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let monitor = FinderMonitor()
    private let wheel = WheelController()
    private let actions = FileActions()
    private var settingsWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Brand.menuIcon
        actions.onBusy = { [weak self] busy in self?.item.button?.image = (busy ? NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Tangerine is working") : Brand.menuIcon) }
        monitor.onClick = { [weak self] files, convert, point in
            guard let self else { return }
            guard let file = files.first else { return }
            self.wheel.show(file: file, title: files.count > 1 ? "\(files.count) files" : convert ? "Convert" : "Utilities", actions: convert ? self.actions.conversions(files) : self.actions.utilities(files), at: point, selectionCount: files.count)
        }
        Settings.shared.onChange = { [weak self] in self?.wheel.dismiss(); self?.monitor.start(); self?.updateMenu() }
        monitor.start(); updateMenu()
        if !AXIsProcessTrusted() { showSettings() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        // Refresh after returning from System Settings without polling permission state.
        monitor.start()
        if item != nil { updateMenu() }
    }
    func updateMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Tangerine", action: nil, keyEquivalent: "")
        let state = !Settings.shared.enabled ? "Wheels paused" : Settings.shared.conversion == Settings.shared.utilities ? "Binding conflict · choose different bindings" : monitor.active ? "Ready · Finder & Desktop" : "Accessibility access needed"
        menu.addItem(withTitle: state, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let toggle = menu.addItem(withTitle: "Enable wheels", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.state = Settings.shared.enabled ? .on : .off
        let convert = menu.addItem(withTitle: "Convert files…", action: #selector(chooseFiles), keyEquivalent: "o"); convert.target = self
        let settings = menu.addItem(withTitle: "Settings & accent color…", action: #selector(showSettings), keyEquivalent: ","); settings.target = self
        let retry = menu.addItem(withTitle: "Retry permissions", action: #selector(retryPermissions), keyEquivalent: ""); retry.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Tangerine", action: #selector(quit), keyEquivalent: "q"); quit.target = self
        item.menu = menu
    }
    @objc func chooseFiles() { actions.chooseFiles() }
    @objc func toggleEnabled() { Settings.shared.enabled.toggle() }
    @objc func retryPermissions() { monitor.start(); updateMenu() }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 522, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Tangerine Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(permissions: { [weak self] in self?.requestPermission() }, convertFiles: { [weak self] in self?.actions.chooseFiles() }))
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { monitor.stop(); wheel.dismiss() }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
