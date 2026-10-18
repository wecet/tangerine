import AppKit
import SwiftUI

enum Binding: String, CaseIterable, Identifiable {
    case option = "Option", shift = "Shift", control = "Control", commandOption = "Command + Option", controlShift = "Control + Shift"
    var id: String { rawValue }
    var flags: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .shift: return .maskShift
        case .control: return .maskControl
        case .commandOption: return [.maskCommand, .maskAlternate]
        case .controlShift: return [.maskControl, .maskShift]
        }
    }
    func matches(_ flags: CGEventFlags) -> Bool {
        flags.intersection([.maskAlternate, .maskShift, .maskCommand, .maskControl]) == self.flags
    }
}
final class Settings: ObservableObject {
    static let shared = Settings()
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); onChange?() } }
    @Published var conversion: Binding { didSet { UserDefaults.standard.set(conversion.rawValue, forKey: "conversion"); onChange?() } }
    @Published var utilities: Binding { didSet { UserDefaults.standard.set(utilities.rawValue, forKey: "utilities"); onChange?() } }
    @Published var workerEnabled: Bool { didSet { UserDefaults.standard.set(workerEnabled, forKey: "workerEnabled") } }
    @Published var accentHex: String { didSet { UserDefaults.standard.set(accentHex, forKey: "accentHex") } }
    var accent: Color { Color(nsColor: accentColor) }
    var accentColor: NSColor {
        let n = UInt32(accentHex, radix: 16) ?? 0x7C83F5
        return NSColor(srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
    func setAccent(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        accentHex = String(format: "%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
    var onChange: (() -> Void)?
    var token: String {
        guard let url = Bundle.main.url(forResource: "worker-token", withExtension: nil) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }
    init() {
        let d = UserDefaults.standard
        accentHex = d.string(forKey: "accentHex") ?? "7C83F5"
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        conversion = Binding(rawValue: d.string(forKey: "conversion") ?? "") ?? .option
        utilities = Binding(rawValue: d.string(forKey: "utilities") ?? "") ?? .shift
        workerEnabled = d.object(forKey: "workerEnabled") as? Bool ?? true
    }
}
struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    let permissions: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52); VStack(alignment: .leading) { Text("Tangerine").font(.title.bold()); Text("A little more at your fingertips.").foregroundStyle(.secondary) } }
            ColorPicker("Wheel accent", selection: SwiftUI.Binding(get: { settings.accent }, set: { settings.setAccent($0) }), supportsOpacity: false)
            Toggle("Enable Finder & Desktop wheels", isOn: $settings.enabled)
            GroupBox("Click bindings") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Conversions", selection: $settings.conversion) { ForEach(Binding.allCases) { Text($0.rawValue + " + Click").tag($0) } }
                    Picker("Utilities", selection: $settings.utilities) { ForEach(Binding.allCases) { Text($0.rawValue + " + Click").tag($0) } }
                    if settings.conversion == settings.utilities { Text("Choose different bindings. Wheels are paused while they conflict.").foregroundStyle(.red) }
                }.padding(8)
            }
            Toggle("Enable Docker media conversions (WebP, MP4, MP3)", isOn: $settings.workerEnabled)
            Text("Native image, PDF and text conversions work offline. Media conversions use the local worker at 127.0.0.1:8765. Originals are always kept.").font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Click directly on a file icon or filename in Finder or on the Desktop. Choose an action, or press Escape / click outside to dismiss.").font(.callout)
            HStack { Button("Accessibility permission…", action: permissions); Spacer(); Button("Restore defaults") { settings.conversion = .option; settings.utilities = .shift; settings.enabled = true } }
            Text("Enable Tangerine under Privacy & Security → Accessibility, then return here. No polling, analytics, or cloud uploads.").font(.caption).foregroundStyle(.secondary)
        }.padding(26).frame(width: 470)
    }
}
