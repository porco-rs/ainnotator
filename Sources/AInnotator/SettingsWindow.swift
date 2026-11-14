import AICore
import AIPlatform
import AppKit
import ServiceManagement
import SwiftUI

final class SettingsWindow {
    private var window: NSWindow?
    private let preferences: Preferences
    private let copy: SettingsCopy
    init(preferences: Preferences, language: Language = .en) {
        self.preferences = preferences
        copy = .forLanguage(language)
    }

    var windowNumber: Int { window?.windowNumber ?? 0 }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = copy.title
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, copy: copy))
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    let preferences: Preferences
    let copy: SettingsCopy
    @State private var days: Int
    @State private var loginEnabled = false
    @State private var loginBusy = false
    @State private var loginMessage = ""
    @State private var screenAllowed = false

    init(preferences: Preferences, copy: SettingsCopy) {
        self.preferences = preferences
        self.copy = copy
        _days = State(initialValue: preferences.retentionDays)
    }

    var body: some View {
        Form {
            Toggle(copy.login, isOn: Binding(get: { loginEnabled }, set: setLogin))
                .disabled(loginBusy)
            if !loginMessage.isEmpty { Text(loginMessage).foregroundStyle(.secondary) }
            Picker(copy.retention, selection: $days) {
                Text(copy.days(1)).tag(1)
                Text(copy.days(7)).tag(7)
                Text(copy.days(30)).tag(30)
            }.onChange(of: days) { _, value in preferences.retentionDays = value }
            Section(copy.shortcuts) {
                LabeledContent(copy.capture, value: "⌥⇧A")
                LabeledContent(copy.repeatCapture, value: "⌥⇧R")
            }
            Section(copy.screen) {
                Text(screenAllowed ? copy.screenAllowed : copy.screenDenied)
                Button(copy.openSettings) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 400)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        screenAllowed = CGPreflightScreenCaptureAccess()
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginMessage = status == .requiresApproval ? copy.loginApproval : ""
    }

    private func setLogin(_ enabled: Bool) {
        loginBusy = true
        Task {
            let failure = await Task.detached {
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try await SMAppService.mainApp.unregister() }
                    return false
                } catch { return true }
            }.value
            refresh()
            if failure { loginMessage = copy.loginError }
            loginBusy = false
        }
    }
}
