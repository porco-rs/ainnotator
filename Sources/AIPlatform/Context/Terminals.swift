import Foundation

/// Whether an app is one of the terminals whose tabs this app can read.
public func isKnownTerminal(bundleIdentifier: String?) -> Bool {
    bundleIdentifier.flatMap(TerminalKind.init(bundle:)) != nil
}
