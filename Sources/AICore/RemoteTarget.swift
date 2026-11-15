import Foundation

/// The machine a terminal tab is connected to, taken from its running ssh client.
public struct RemoteTarget: Equatable, Sendable {
    /// Connection arguments that are safe to pass to another ssh call, the destination last. Only
    /// `SSHCommand.target(fromArguments:)` creates a target: it keeps a fixed list of options and nothing that runs
    /// a command.
    public let arguments: [String]

    /// The destination as the user typed it ("devbox", "me@host"), for display.
    public var destination: String { arguments.last ?? "" }

    /// What consent is remembered under: the same arguments reach the same machine.
    public var consentKey: String { arguments.joined(separator: " ") }

    init(arguments: [String]) {
        self.arguments = arguments
    }
}

public enum SSHCommand {
    /// The target of an ssh client, read from its argument vector (program name first). Only connection options
    /// from the fixed allowlist are retained; unsupported modes and invalid arguments return nil.
    public static func target(fromArguments argv: [String]) -> RemoteTarget? {
        guard let program = argv.first, (program as NSString).lastPathComponent == "ssh" else { return nil }
        let takesValue = Set("bceilmopBDEFIJLOPQRSwW")
        let rejected = Set("NfsGVWOQIP")
        let keptValues = Set("plFJiS")
        let known = Set("1246ab:c:e:fgi:kl:m:no:p:qstvxAB:CD:E:F:GI:J:KL:MNO:P:Q:R:S:TVw:W:XYy".filter { $0 != ":" })
        let allowedSettings: Set<String> = [
            "port", "user", "hostname", "identityfile", "identitiesonly", "proxyjump", "userknownhostsfile", "controlpath"
        ]
        var result: [String] = []
        var index = 1
        var optionsEnded = false
        // ssh also reads options that follow the destination ("ssh host -p 2200"); the first word after it that
        // is not an option begins the remote command.
        var destination: String?

        func validValue(_ value: String) -> Bool {
            !value.isEmpty && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        }
        func validPort(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
                && (Int(value).map { (1...65535).contains($0) } ?? false)
        }

        while index < argv.count {
            let word = argv[index]
            index += 1
            if !optionsEnded && word == "--" {
                optionsEnded = true
                continue
            }
            if !optionsEnded && word.hasPrefix("-") && word != "-" {
                let letters = Array(word.dropFirst())
                var offset = 0
                while offset < letters.count {
                    let option = letters[offset]
                    guard known.contains(option), !rejected.contains(option) else { return nil }
                    offset += 1
                    if takesValue.contains(option) {
                        let value: String
                        if offset < letters.count {
                            value = String(letters[offset...])
                        } else {
                            guard index < argv.count else { return nil }
                            value = argv[index]
                            index += 1
                        }
                        if keptValues.contains(option) {
                            guard validValue(value), option != "p" || validPort(value) else { return nil }
                            result.append(contentsOf: ["-\(option)", value])
                        } else if option == "o", let equals = value.firstIndex(of: "=") {
                            let key = value[..<equals].lowercased()
                            if allowedSettings.contains(key) {
                                let setting = String(value[value.index(after: equals)...])
                                guard validValue(value), validValue(setting), key != "port" || validPort(setting) else { return nil }
                                result.append(contentsOf: ["-o", value])
                            }
                        }
                        break
                    }
                    if option == "4" || option == "6" { result.append("-\(option)") }
                }
                continue
            }
            if destination != nil { break }
            guard !word.isEmpty, !word.hasPrefix("-"),
                  word.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            destination = word
        }
        guard let destination else { return nil }
        return RemoteTarget(arguments: result + [destination])
    }
}
