import Foundation
import Testing
@testable import AIPlatform

// There is no choice between text and JSON on the clipboard: it carries the card as a file. The JSON stays as a
// sidecar on disk.
@Test func preferenceDefaultsAndPersistence() {
    let name = "AInnotatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let first = Preferences(defaults: defaults)
    #expect(first.retentionDays == 7)
    first.retentionDays = 30
    let second = Preferences(defaults: defaults)
    #expect(second.retentionDays == 30)
    defaults.set(3, forKey: "retentionDays")
    #expect(second.retentionDays == 7)
}

/// Nothing leaves the Mac for a machine the user has not said yes to. The yes is remembered per machine, the switch
/// turns the whole thing off, and forgetting brings the question back.
@Test func aCaptureIsCopiedOnlyToAConfirmedMachine() {
    let name = "AInnotatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.remoteCopyEnabled)
    #expect(!preferences.mayCopy(toRemote: "devbox"))
    preferences.confirmRemote("devbox")
    preferences.confirmRemote("devbox")
    #expect(preferences.confirmedRemotes == ["devbox"])
    #expect(Preferences(defaults: defaults).mayCopy(toRemote: "devbox"))
    // Other arguments are another machine, also when the name is the same.
    #expect(!preferences.mayCopy(toRemote: "-p 2200 devbox"))
    preferences.remoteCopyEnabled = false
    #expect(!preferences.mayCopy(toRemote: "devbox"))
    preferences.remoteCopyEnabled = true
    preferences.forgetRemotes()
    #expect(!preferences.mayCopy(toRemote: "devbox"))
}
