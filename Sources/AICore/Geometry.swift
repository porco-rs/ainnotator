import Foundation

/// Pure calculations shared with a renderer.
public enum Geometry {
    /// Move overlapping badges to the right, preserving their input order.
    public static func spread(_ badges: [NormPoint], width: Double, height: Double, step: Double) -> [NormPoint] {
        guard width > 0, height > 0 else { return badges }
        var placed: [NormPoint] = []
        for badge in badges {
            var x = badge.x * width
            let y = badge.y * height
            for _ in 0..<20 {
                guard placed.contains(where: { abs($0.x - x) < step && abs($0.y - y) < 16 }) else { break }
                x += step
            }
            placed.append(NormPoint(x: x, y: y))
        }
        return placed.map { NormPoint(x: $0.x / width, y: $0.y / height) }
    }

    public static func tokenEstimate(width: Double, height: Double) -> String {
        guard width > 0, height > 0 else { return "≈0 tok" }
        let scale = min(1, 1568 / max(width, height))
        let tokens = Int(floor(width * scale * height * scale / 750 + 0.5))
        return tokens >= 1000 ? String(format: "≈%.1fk tok", locale: Locale(identifier: "en_US_POSIX"), Double(tokens) / 1000) : "≈\(tokens) tok"
    }
}
