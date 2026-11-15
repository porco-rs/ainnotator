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

    /// Whether a capture may be copied to the machine a terminal is connected to. On by default, because each
    /// machine is still asked for once and nothing is copied before that.
    public var remoteCopyEnabled: Bool {
        get { defaults.object(forKey: "remoteCopyEnabled") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "remoteCopyEnabled") }
    }

    /// The machines the user said yes to, each by the arguments that reach it (`RemoteTarget.consentKey`).
    public var confirmedRemotes: [String] {
        defaults.stringArray(forKey: "confirmedRemotes") ?? []
    }

    public func confirmRemote(_ key: String) {
        guard !key.isEmpty, !confirmedRemotes.contains(key) else { return }
        defaults.set(confirmedRemotes + [key], forKey: "confirmedRemotes")
    }

    public func forgetRemotes() {
        defaults.removeObject(forKey: "confirmedRemotes")
    }

    /// Nothing is copied to a machine the user has not confirmed, and nothing at all while the switch is off.
    public func mayCopy(toRemote key: String) -> Bool {
        remoteCopyEnabled && confirmedRemotes.contains(key)
    }
}
