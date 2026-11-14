import Foundation

public struct Preferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var retentionDays: Int {
        get {
            let days = defaults.integer(forKey: "retentionDays")
            return [1, 7, 30].contains(days) ? days : 7
        }
        nonmutating set { defaults.set([1, 7, 30].contains(newValue) ? newValue : 7, forKey: "retentionDays") }
    }
}
