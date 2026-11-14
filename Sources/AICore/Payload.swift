import Foundation

/// The machine-readable output of a capture: the JSON beside the PNG, and the context line on the card.
public enum Payload {
    /// App, URL and repository in one line: the footer of the card.
    public static func contextLine(_ context: CaptureContext) -> String? {
        var parts: [String] = []
        if let app = context.app, !app.isEmpty { parts.append(app) }
        if let url = cleanURL(context.url), !url.isEmpty { parts.append(url) }
        if let repo = context.repo, !repo.isEmpty {
            parts.append(repo + (context.branch.flatMap { $0.isEmpty ? nil : "@" + $0 } ?? ""))
        } else if let branch = context.branch, !branch.isEmpty { parts.append(branch) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public static func json(_ state: CaptureState, imagePath: String, context: CaptureContext, createdAt: Date, timeZone: TimeZone = .current) -> String {
        let sel = state.sel ?? .full
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        var lines = ["{", "  \"schemaVersion\": 1,", "  \"tool\": \"ainnotator\",", "  \"createdAt\": \(quote(formatter.string(from: createdAt))),", "  \"image\": \(quote(imagePath)),", "  \"crop\": [", "    \(rounded(sel.w * Double(state.stage.pixelWidth))),", "    \(rounded(sel.h * Double(state.stage.pixelHeight)))", "  ],", "  \"context\": {"]
        let values: [(String, String?)] = [("app", context.app), ("window", context.window), ("url", cleanURL(context.url)), ("repo", context.repo), ("branch", context.branch)]
        let fields = values.compactMap { key, value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return "    \(quote(key)): \(quote(value))"
        }
        if !fields.isEmpty { lines.append(fields.joined(separator: ",\n")) }
        lines.append("  },")
        lines.append("  \"marks\": [")
        let marks = state.marks.filter { $0.kind != .redact }
        for (index, mark) in marks.enumerated() {
            lines += ["    {", "      \"n\": \(index + 1),", "      \"intent\": \(quote(mark.intent.jsonValue)),", "      \"shape\": \(quote(mark.kind.rawValue)),", "      \"at\": ["]
            let at = pixels(mark, sel, state.stage)
            for (i, value) in at.enumerated() { lines.append("        \(value)\(i + 1 < at.count ? "," : "")") }
            lines += ["      ],", "      \"note\": \(mark.note.isEmpty ? "null" : quote(mark.note))", "    }\(index + 1 < marks.count ? "," : "")"]
        }
        lines += ["  ],", "  \"redacted\": \(state.marks.count - marks.count)", "}"]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func pixels(_ mark: Mark, _ sel: NormRect, _ stage: Stage) -> [Int] {
        func x(_ value: Double) -> Int { rounded((value - sel.x) * Double(stage.pixelWidth)) }
        func y(_ value: Double) -> Int { rounded((value - sel.y) * Double(stage.pixelHeight)) }
        if mark.kind == .pin { return [x(mark.x), y(mark.y)] }
        if mark.kind == .arrow { return [x(mark.x0), y(mark.y0), x(mark.x1), y(mark.y1)] }
        return [x(mark.x), y(mark.y), x(mark.x + mark.w), y(mark.y + mark.h)]
    }

    private static func rounded(_ value: Double) -> Int { Int(floor(value + 0.5)) }
    private static func quote(_ value: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }
    private static func cleanURL(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let withoutScheme: String
        if let range = value.range(of: "://") { withoutScheme = String(value[range.upperBound...]) }
        else { withoutScheme = value }
        return String(withoutScheme.prefix { $0 != "?" && $0 != "#" })
    }
}
