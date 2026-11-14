import Foundation

/// The language of every text a user or a model reads. It is decided once at launch and passed down explicitly;
/// English is the default wherever a language is optional.
public enum Language: String, Sendable, CaseIterable {
    case en
    case de

    /// German if the first preferred language is German, English otherwise (also for an empty list).
    public static func choose(from preferred: [String]) -> Language {
        guard let first = preferred.first else { return .en }
        let code = first.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        return code == "de" ? .de : .en
    }
}
