import AppKit
import ServiceManagement
import Security

final class FoundationSettings: ObservableObject {
    static let shared = FoundationSettings()
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginStatus = ""
    @Published private(set) var signingStatus = ""
    init() { refresh() }
    func refresh() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        switch status {
        case .enabled: loginStatus = "Tangerine will open at login."
        case .requiresApproval: loginStatus = "Approve Tangerine in System Settings → Login Items."
        case .notRegistered: loginStatus = "Launch at login is off."
        case .notFound: loginStatus = "Install Tangerine in Applications before enabling login startup."
        @unknown default: loginStatus = "Login startup status unavailable."
        }
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let dictionary = info as? [String: Any], let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first {
            signingStatus = "Persistent signing identity: " + ((SecCertificateCopySubjectSummary(leaf) as String?) ?? "Configured")
        } else { signingStatus = "Ad-hoc development build. Rebuilds may require Accessibility to be enabled again." }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            if enabled && service.status != .enabled && service.status != .requiresApproval { try service.register() }
            if !enabled && service.status != .notRegistered { try service.unregister() }
            refresh()
        } catch { refresh(); loginStatus = error.localizedDescription }
    }
    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
