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
