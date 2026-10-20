import AppKit

/// Keep the sharing service alive while macOS presents its recipient dialog.
final class AirDropController: NSObject, NSSharingServiceDelegate {
    private var services: [NSSharingService] = []
    func share(_ files: [URL]) {
        let files = FileSelection.unique(files)
        guard !files.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: files) else {
            FileActions.alert("AirDrop is unavailable for these files on this Mac."); return
        }
        services.append(service)
        service.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: files)
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        services.removeAll { $0 === sharingService }
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        services.removeAll { $0 === sharingService }
        if (error as NSError).code != NSUserCancelledError { FileActions.alert(error.localizedDescription) }
    }
}
