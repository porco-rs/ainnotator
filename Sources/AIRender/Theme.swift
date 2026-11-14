import AICore
import CoreGraphics
import CoreText
import Foundation

/// The design colors of the overlay and the card.
public enum Theme {
    public static func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
        )
    }

    /// CSS OKLCH conversion to gamma-encoded sRGB, clipped to its gamut.
    public static func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double, alpha: CGFloat = 1) -> CGColor {
        let angle = hue * .pi / 180
        let a = chroma * cos(angle), b = chroma * sin(angle)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        func channel(_ linear: Double) -> CGFloat {
            let v = linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
            return CGFloat(max(0, min(1, v)))
        }
        return CGColor(srgbRed: channel(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                       green: channel(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                       blue: channel(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s), alpha: alpha)
    }

    public static func intent(_ intent: Intent, alpha: CGFloat = 1) -> CGColor {
        switch intent {
        case .bug: oklch(0.66, 0.21, 27, alpha: alpha)
        case .change: oklch(0.64, 0.21, 293, alpha: alpha)
        case .keep: oklch(0.78, 0.17, 152, alpha: alpha)
        case .question: oklch(0.86, 0.15, 88, alpha: alpha)
        }
    }

    public static func onIntent(_ intent: Intent) -> CGColor {
        switch intent {
        case .bug, .change: srgb(0xFFFFFF)
        case .keep: oklch(0.18, 0.03, 152)
        case .question: oklch(0.20, 0.03, 88)
        }
    }

    public static let dim = srgb(0x04060A)
    public static let cardBackground = oklch(0.12, 0.004, 250)
    public static let hudBackground = oklch(0.15, 0.004, 250, alpha: 0.86)
    public static let hudText = oklch(0.97, 0, 0)
    public static let hudMuted = oklch(0.66, 0.005, 250)
    public static let redactA = oklch(0.13, 0, 0)
    public static let redactB = oklch(0.18, 0, 0)

    /// CoreText cannot name SF Mono, and this module stays free of AppKit: the app injects it once at launch.
    /// The fallback serves tests and offscreen use.
    public nonisolated(unsafe) static var monoProvider: @Sendable (CGFloat, MonoWeight) -> CTFont = { size, weight in
        CTFontCreateWithName((weight == .semibold ? "Menlo-Bold" : "Menlo-Regular") as CFString, size, nil)
    }

    public enum MonoWeight: Sendable { case regular, medium, semibold }

    public static func mono(_ size: CGFloat, semibold: Bool = false) -> CTFont {
        monoProvider(size, semibold ? .semibold : .regular)
    }

    public static func monoMedium(_ size: CGFloat) -> CTFont {
        monoProvider(size, .medium)
    }

    public static func semiboldSans(_ size: CGFloat) -> CTFont {
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.3]
        ] as CFDictionary)
        return CTFontCreateCopyWithAttributes(sans(size), size, nil, descriptor)
    }

    public static func sans(_ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil)!
    }
}
