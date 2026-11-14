import AICore
import CoreGraphics
import Foundation

/// Maps normalized image positions into a drawing space with its origin top left.
public struct StageMapping: Sendable {
    public var crop: NormRect
    public var width: Double
    public var height: Double

    public init(crop: NormRect, width: Double, height: Double) {
        self.crop = crop
        self.width = width
        self.height = height
    }

    public func x(_ v: Double) -> Double { (v - crop.x) / crop.w * width }
    public func y(_ v: Double) -> Double { (v - crop.y) / crop.h * height }
}

/// The one source of mark shapes, so the overlay and the card cannot drift apart.
public enum MarkPath {
    public static func path(for mark: Mark, mapping m: StageMapping, arrowHead: Double = 12, inset: Double = 0) -> CGPath {
        let path = CGMutablePath()
        switch mark.kind {
        case .box:
            path.addRect(insetRect(for: mark, mapping: m, inset: inset))
        case .highlight, .redact:
            path.addRect(rect(for: mark, mapping: m))
        case .oval:
            path.addEllipse(in: insetRect(for: mark, mapping: m, inset: inset))
        case .pin:
            path.addEllipse(in: CGRect(x: m.x(mark.x) - 2, y: m.y(mark.y) - 2, width: 4, height: 4))
        case .arrow:
            let a = CGPoint(x: m.x(mark.x0), y: m.y(mark.y0))
            let b = CGPoint(x: m.x(mark.x1), y: m.y(mark.y1))
            let angle = atan2(b.y - a.y, b.x - a.x)
            let wing = arrowHead / 2
            let base = CGPoint(x: b.x - cos(angle) * arrowHead, y: b.y - sin(angle) * arrowHead)
            path.move(to: a)
            path.addLine(to: base)
            path.move(to: b)
            path.addLine(to: CGPoint(x: base.x - sin(angle) * wing, y: base.y + cos(angle) * wing))
            path.addLine(to: CGPoint(x: base.x + sin(angle) * wing, y: base.y - cos(angle) * wing))
            path.closeSubpath()
        }
        return path
    }

    private static func insetRect(for mark: Mark, mapping: StageMapping, inset: Double) -> CGRect {
        let rect = rect(for: mark, mapping: mapping)
        let amount = max(0, min(inset, min(rect.width, rect.height) / 2))
        return rect.insetBy(dx: amount, dy: amount)
    }

    public static func rect(for mark: Mark, mapping m: StageMapping) -> CGRect {
        CGRect(x: m.x(mark.x), y: m.y(mark.y), width: mark.w / m.crop.w * m.width, height: mark.h / m.crop.h * m.height)
    }
}
