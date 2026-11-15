import AIPlatform
import AppKit

/// Keeps a capture that was copied to another machine on the clipboard in the form that fits the app in front: the
/// path on the other machine while a terminal is in front, the file for everything else. A terminal that is given a
/// file pastes its local path; a browser that is given image and text may take the text.
@MainActor final class ClipFollower {
    private let pasteboard: NSPasteboard
    private var observer: NSObjectProtocol?
    private var clip: PendingClip?
    /// Called after each change of form, with the app that came to the front.
    var onSwitch: ((PendingClip.Form, String) -> Void)?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    static func form(forFrontmost bundle: String?) -> PendingClip.Form {
        isKnownTerminal(bundleIdentifier: bundle) ? .remote : .file
    }

    /// From now on the clipboard follows the app in front, for as long as it still holds this capture.
    func follow(_ clip: PendingClip) {
        stop()
        self.clip = clip
        let own = Bundle.main.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundle = app?.bundleIdentifier
            let name = app?.localizedName ?? bundle ?? "?"
            MainActor.assumeIsolated {
                // This app's own windows are no paste target.
                guard let self, let clip = self.clip, bundle != own else { return }
                let form = Self.form(forFrontmost: bundle)
                if Clipboard.switchForm(of: clip, to: form, on: self.pasteboard) { self.onSwitch?(form, name) }
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        clip = nil
    }

    isolated deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
