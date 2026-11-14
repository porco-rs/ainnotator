import AICore
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import IOSurface
import UniformTypeIdentifiers

/// Burns the marks into a private bitmap and adds legend and footer. Redactions overwrite pixels here, so the PNG
/// can never contain what lies beneath them.
public enum CardRenderer {
    /// The frozen display in the app; a plain image where no IOSurface can be created, such as in a sandboxed process.
    public enum Source: @unchecked Sendable {
        case surface(IOSurfaceRef)
        case image(CGImage)

        var size: (width: Int, height: Int) {
            switch self {
            case .surface(let surface): (IOSurfaceGetWidth(surface), IOSurfaceGetHeight(surface))
            case .image(let image): (image.width, image.height)
            }
        }

        /// The capture system may reuse a surface nobody marks as in use. The export runs after the overlay let go.
        public func holdForExport() {
            if case .surface(let surface) = self { IOSurfaceIncrementUseCount(surface) }
        }

        public func releaseAfterExport() {
            if case .surface(let surface) = self { IOSurfaceDecrementUseCount(surface) }
        }
    }

    public struct Input: Sendable {
        public var source: Source
        public var state: CaptureState
        public var footer: String
        public var language: Language

        public init(source: Source, state: CaptureState, footer: String, language: Language = .en) {
            self.source = source
            self.state = state
            self.footer = footer
            self.language = language
        }
    }

    /// The words the card says in one language. The intent words (BUG, CHANGE, KEEP, QUESTION) are the same in both.
    struct Words: Sendable {
        var header: @Sendable (Int) -> String
        var box: String, oval: String, arrow: String, highlight: String, point: String
        var noNote: String
        var more: @Sendable (Int) -> String
        var redacted: @Sendable (Int) -> String

        init(_ language: Language) {
            self = language == .de ? Self.german : Self.english
        }

        private init(
            header: @escaping @Sendable (Int) -> String, box: String, oval: String, arrow: String, highlight: String,
            point: String, noNote: String, more: @escaping @Sendable (Int) -> String,
            redacted: @escaping @Sendable (Int) -> String
        ) {
            self.header = header; self.box = box; self.oval = oval; self.arrow = arrow; self.highlight = highlight
            self.point = point; self.noNote = noNote; self.more = more; self.redacted = redacted
        }

        func shape(_ kind: MarkKind) -> String {
            switch kind {
            case .box: box
            case .oval: oval
            case .arrow: arrow
            case .highlight: highlight
            case .pin: point
            case .redact: ""
            }
        }

        private static let english = Words(
            header: { count in
                "\(count) \(count == 1 ? "ANNOTATION" : "ANNOTATIONS") BY THE USER · numbered marks were added afterwards, everything else belongs to the screen"
            },
            box: "box", oval: "oval", arrow: "arrow", highlight: "highlight", point: "point",
            noNote: "(no note)",
            more: { "+ \($0) more" },
            redacted: { "\($0) \($0 == 1 ? "area" : "areas") redacted (black hatching)" }
        )

        private static let german = Words(
            header: { count in
                "\(count) \(count == 1 ? "ANMERKUNG" : "ANMERKUNGEN") DES NUTZERS · nummerierte Marken sind nachträglich gesetzt, alles andere gehört zum Bildschirm"
            },
            box: "Kasten", oval: "Oval", arrow: "Pfeil", highlight: "Textmarker", point: "Punkt",
            noNote: "(ohne Notiz)",
            more: { "+ \($0) weitere" },
            redacted: { "\($0) \($0 == 1 ? "Bereich" : "Bereiche") geschwärzt (schwarz schraffiert)" }
        )
    }

    /// What the card says about the marks in words. A target may take nothing but the image, so the image has to say
    /// which marks are the user's and what each one means, also where no note was typed. Without that, models took
    /// content of the captured screen for the user's wish (seen in a blind test with three models).
    struct Legend: Equatable {
        struct Row: Equatable {
            var number: Int
            var intent: Intent
            var shape: String
            /// The note, or the "no note" placeholder where there is none.
            var note: String
            var hasNote: Bool
        }

        var header: String
        var rows: [Row]
        /// Rows left out by `maxRows`, shown as "+ n more".
        var hidden: Int
    }

    /// The card is laid out at this width; every measure below is in these layout points.
    private static let designWidth = 320.0
    /// The receipt keeps to nine legend rows; the PNG lists every mark.
    private static let previewLegendRows = 9
    private static let noteColor = Theme.oklch(0.92, 0, 0)
    private static let headerColor = Theme.oklch(0.78, 0.005, 250)
    private static let wordColor = Theme.oklch(0.60, 0.005, 250)
    private static let footerColor = Theme.oklch(0.55, 0.005, 250)
    private static let ruleColor = Theme.srgb(0xFFFFFF, alpha: 0.08)

    static func legend(for marks: [Mark], maxRows: Int? = nil, language: Language = .en) -> Legend? {
        let entries = numbered(marks)
        guard !entries.isEmpty else { return nil }
        let words = Words(language)
        let rows = entries.prefix(maxRows ?? entries.count).map { entry in
            Legend.Row(
                number: entry.number, intent: entry.mark.intent, shape: words.shape(entry.mark.kind),
                note: entry.mark.note.isEmpty ? words.noNote : entry.mark.note, hasNote: !entry.mark.note.isEmpty
            )
        }
        return Legend(header: words.header(entries.count), rows: rows, hidden: entries.count - rows.count)
    }

    /// Context, size of the crop and the redactions, which carry no number and are named here instead.
    static func footer(context: String, crop: CGSize, redactions: Int, language: Language = .en) -> String {
        var parts = [context, "\(Int(crop.width))×\(Int(crop.height))"].filter { !$0.isEmpty }
        if redactions > 0 {
            parts.append(Words(language).redacted(redactions))
        }
        return parts.joined(separator: " · ")
    }

    public static func renderPNG(_ input: Input) -> Data? {
        guard let image = render(input) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Labels keep their design size both on the display they came from and in the 1568 px a model scales the long
    /// edge down to. Proportional to the crop alone they would cover the content of large areas.
    static func labelScale(stage: Stage, crop: CGSize) -> Double {
        let device = stage.pointWidth > 0 ? Double(stage.pixelWidth) / stage.pointWidth : 1
        return max(device, max(crop.width, crop.height) / 1568)
    }

    /// Without `previewWidth` this is the PNG: every pixel of the crop. With it, the same content at the layout's
    /// proportions for the receipt, where labels stay readable and no full-size bitmap has to stay in memory.
    public static func render(_ input: Input, previewWidth: Int? = nil) -> CGImage? {
        let state = input.state
        let sel = state.sel ?? .full
        let source = input.source.size
        let crop = CGRect(
            x: (sel.x * Double(source.width)).rounded(), y: (sel.y * Double(source.height)).rounded(),
            width: (sel.w * Double(source.width)).rounded(), height: (sel.h * Double(source.height)).rounded()
        ).integral
        guard crop.width > 0, crop.height > 0 else { return nil }

        let scale: Double
        let image: CGSize
        if let previewWidth {
            scale = Double(previewWidth) / designWidth
            let shrink = min(1, Double(previewWidth) / crop.width)
            image = CGSize(width: (crop.width * shrink).rounded(), height: (crop.height * shrink).rounded())
        } else {
            scale = labelScale(stage: state.stage, crop: crop.size)
            image = crop.size
        }
        // Narrow areas sit left on the dark ground, so legend and footer stay readable beside them.
        let width = max(image.width, (designWidth * scale).rounded(.up))

        let entries = numbered(state.marks)
        let legend = legend(for: state.marks, maxRows: previewWidth == nil ? nil : previewLegendRows, language: input.language)
        let padding = 10 * scale
        let wordTracking = 0.06 * 9
        let shapeX = 98.0
        // The note column starts after the longest shape word of this legend, so narrow cards keep room for notes.
        let shapeWidth = legend?.rows.map { textWidth($0.shape, font: Theme.monoMedium(9), tracking: wordTracking) }.max() ?? 0
        let noteX = (shapeX + shapeWidth + 8).rounded(.up) * scale
        let noteLineHeight = 14.85 * scale
        let headerLineHeight = 12.5 * scale
        let headerGap = 4 * scale
        let rowGap = 5 * scale
        // The legend is the only place for notes when a target takes the image alone, so notes wrap instead of ending.
        // Text is set at its design size and scaled, like a browser at 2x: SF tracks 22 pt tighter than 11 pt at scale 2.
        let headerLines = legend.map {
            wrapped($0.header, font: Theme.monoMedium(9), color: headerColor, width: (width - 2 * padding) / scale, tracking: wordTracking)
        } ?? []
        let rows = (legend?.rows ?? []).map { row in
            (row: row, lines: wrapped(row.note, font: Theme.sans(11), color: row.hasNote ? noteColor : wordColor, width: (width - noteX - padding) / scale))
        }
        let hiddenRows = legend?.hidden ?? 0
        var legendHeight = 0.0
        if legend != nil {
            let rowCount = rows.count + (hiddenRows > 0 ? 1 : 0)
            let lineCount = rows.reduce(hiddenRows > 0 ? 1 : 0) { $0 + $1.lines.count }
            legendHeight = (
                18 * scale + Double(headerLines.count) * headerLineHeight + headerGap
                    + Double(lineCount) * noteLineHeight + Double(rowCount - 1) * rowGap
            ).rounded(.up)
        }
        let redactions = state.marks.filter { $0.kind == .redact }.count
        let footer = footer(context: input.footer, crop: crop.size, redactions: redactions, language: input.language)
        let footerLines = wrapped(footer, font: Theme.mono(9), color: footerColor, width: (width - 2 * padding) / scale, tracking: 0.03 * 9)
        let footerLineHeight = 11.5 * scale
        // Whole pixels only: a fraction here would make the first rule blend into the last row of the image.
        let footerTop = image.height + legendHeight
        let cardHeight = footerTop + (12 * scale + Double(footerLines.count) * footerLineHeight).rounded(.up)

        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: Int(width), height: Int(cardHeight), bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: info
              ) else { return nil }

        context.setFillColor(Theme.cardBackground)
        context.fill(CGRect(x: 0, y: 0, width: width, height: cardHeight))
        // Grayscale antialiasing: font smoothing would thicken every label.
        context.setShouldSmoothFonts(false)

        // Top-left origin for everything below.
        context.translateBy(x: 0, y: cardHeight)
        context.scaleBy(x: 1, y: -1)

        // A scaling filter reaches beyond one pixel, so a scaled image is redacted at full size first.
        let scaled = image != crop.size
        if scaled, state.marks.contains(where: { $0.kind == .redact }) {
            guard let redacted = redactedCrop(input, crop: crop, sel: sel, scale: scale * crop.width / image.width, space: space, info: info),
                  draw(redacted, crop: CGRect(origin: .zero, size: crop.size), size: image, into: context) else { return nil }
        } else {
            guard copyPixels(from: input.source, crop: crop, size: image, into: context, space: space) else { return nil }
        }

        let mapping = StageMapping(crop: sel, width: image.width, height: image.height)
        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: image))
        if !scaled { burnRedactions(state.marks, mapping: mapping, scale: scale, into: context) }
        let anchors = entries.map { entry in
            entry.mark.kind == .arrow
                ? CGPoint(x: mapping.x(entry.mark.x0), y: mapping.y(entry.mark.y0))
                : CGPoint(x: mapping.x(entry.mark.x), y: mapping.y(entry.mark.y))
        }
        let spreadAnchors = spread(anchors, scale: scale)
        for (entry, anchor) in zip(entries, spreadAnchors) {
            drawMark(entry.mark, number: entry.number, anchor: anchor, mapping: mapping, scale: scale, in: context)
        }
        context.restoreGState()

        let rule = (scale).rounded(.up)
        var y = image.height + 9 * scale
        if legend != nil {
            context.setFillColor(ruleColor)
            context.fill(CGRect(x: 0, y: image.height, width: width, height: rule))
            for (index, line) in headerLines.enumerated() {
                draw(line, x: padding, baseline: y + 9.5 * scale + Double(index) * headerLineHeight, scale: scale, in: context)
            }
            y += Double(headerLines.count) * headerLineHeight + headerGap
        }
        for (row, lines) in rows {
            let baseline = y + 11 * scale
            let badge = CGRect(x: padding, y: baseline - 9.5 * scale, width: 19 * scale, height: 13 * scale)
            context.setFillColor(Theme.intent(row.intent))
            context.addPath(CGPath(roundedRect: badge, cornerWidth: 2 * scale, cornerHeight: 2 * scale, transform: nil))
            context.fillPath()
            drawText(String(format: "%02d", row.number), x: badge.minX + 4 * scale, baseline: baseline, font: Theme.mono(9 * scale, semibold: true), color: Theme.onIntent(row.intent), in: context)
            drawText(row.intent.payloadWord, x: 37 * scale, baseline: baseline, font: Theme.monoMedium(9), color: wordColor, tracking: wordTracking, scale: scale, in: context)
            drawText(row.shape, x: shapeX * scale, baseline: baseline, font: Theme.monoMedium(9), color: wordColor, tracking: wordTracking, scale: scale, in: context)
            for (index, line) in lines.enumerated() {
                draw(line, x: noteX, baseline: baseline + Double(index) * noteLineHeight, scale: scale, in: context)
            }
            y += Double(lines.count) * noteLineHeight + rowGap
        }
        if hiddenRows > 0 {
            drawText(Words(input.language).more(hiddenRows), x: padding, baseline: y + 11 * scale, font: Theme.monoMedium(9), color: wordColor, tracking: wordTracking, scale: scale, in: context)
        }
        context.setFillColor(ruleColor)
        context.fill(CGRect(x: 0, y: footerTop, width: width, height: rule))
        for (index, line) in footerLines.enumerated() {
            draw(line, x: padding, baseline: footerTop + (14.5 + 11.5 * Double(index)) * scale, scale: scale, in: context)
        }
        return context.makeImage()
    }

    /// Numbers skip redactions and stay gapless, so image and text always agree.
    public static func numbered(_ marks: [Mark]) -> [(mark: Mark, number: Int)] {
        var number = 0
        var result: [(mark: Mark, number: Int)] = []
        for mark in marks where mark.kind != .redact {
            number += 1
            result.append((mark, number))
        }
        return result
    }

    /// Tabs that would sit on top of each other move to the right, 20 points at a time at the design scale.
    static func spread(_ anchors: [CGPoint], scale: CGFloat) -> [CGPoint] {
        var placed: [CGPoint] = []
        for original in anchors {
            var anchor = original
            for _ in 0..<20 {
                if !placed.contains(where: { abs($0.x - anchor.x) < 20 * scale && abs($0.y - anchor.y) < 16 * scale }) { break }
                anchor.x += 20 * scale
            }
            placed.append(anchor)
        }
        return placed
    }

    private static func copyPixels(from source: Source, crop: CGRect, size: CGSize, into context: CGContext, space: CGColorSpace) -> Bool {
        switch source {
        case .image(let image):
            return draw(image, crop: crop, size: size, into: context)
        case .surface(let surface):
            guard IOSurfaceLock(surface, .readOnly, nil) == KERN_SUCCESS else { return false }
            defer { IOSurfaceUnlock(surface, .readOnly, nil) }
            let width = IOSurfaceGetWidth(surface)
            let height = IOSurfaceGetHeight(surface)
            let stride = IOSurfaceGetBytesPerRow(surface)
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            guard let provider = CGDataProvider(
                dataInfo: nil, data: IOSurfaceGetBaseAddress(surface), size: stride * height, releaseData: { _, _, _ in }
            ), let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride, space: space,
                bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ) else { return false }
            return draw(image, crop: crop, size: size, into: context)
        }
    }

    private static func draw(_ image: CGImage, crop: CGRect, size: CGSize, into context: CGContext) -> Bool {
        guard let cropped = image.cropping(to: crop) else { return false }
        // CGContext draws images bottom-up; undo the top-left flip for this one call.
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = size == crop.size ? .none : .high
        context.setBlendMode(.copy)
        context.draw(cropped, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
        return true
    }

    private static func textWidth(_ text: String, font: CTFont, tracking: Double) -> Double {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTKernAttributeName: tracking]
        guard let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else { return 0 }
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil)
    }

    private static func wrapped(_ text: String, font: CTFont, color: CGColor, width: Double, tracking: Double = 0) -> [CTLine] {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color, kCTKernAttributeName: tracking]
        guard width > 0, let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else { return [] }
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        let length = CFAttributedStringGetLength(string)
        var lines: [CTLine] = []
        var start = 0
        while start < length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, width)
            guard count > 0 else { break }
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return lines
    }

    private static func redactedCrop(_ input: Input, crop: CGRect, sel: NormRect, scale: Double, space: CGColorSpace, info: UInt32) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: Int(crop.width), height: Int(crop.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: info
        ) else { return nil }
        context.translateBy(x: 0, y: crop.height)
        context.scaleBy(x: 1, y: -1)
        guard copyPixels(from: input.source, crop: crop, size: crop.size, into: context, space: space) else { return nil }
        let mapping = StageMapping(crop: sel, width: crop.width, height: crop.height)
        burnRedactions(input.state.marks, mapping: mapping, scale: scale, into: context)
        return context.makeImage()
    }

    private static func burnRedactions(_ marks: [Mark], mapping: StageMapping, scale: Double, into context: CGContext) {
        for mark in marks where mark.kind == .redact {
            drawRedaction(MarkPath.rect(for: mark, mapping: mapping), scale: scale, in: context)
        }
    }

    /// Rounded outward to whole pixels and without antialiasing: a partly covered edge pixel would keep the original.
    private static func drawRedaction(_ markRect: CGRect, scale: Double, in context: CGContext) {
        let rect = markRect.integral
        context.saveGState()
        context.setBlendMode(.copy)
        context.setShouldAntialias(false)
        context.setFillColor(Theme.redactA)
        context.fill(rect)
        context.setShouldAntialias(true)
        context.clip(to: rect)
        context.setStrokeColor(Theme.redactB)
        let stripe = 6 * scale
        context.setLineWidth(stripe)
        var x = rect.minX - rect.height
        while x < rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.maxY))
            context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += stripe * 2 * 2.0.squareRoot()
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawMark(_ mark: Mark, number: Int, anchor: CGPoint, mapping: StageMapping, scale: Double, in context: CGContext) {
        let color = Theme.intent(mark.intent)
        context.saveGState()
        switch mark.kind {
        case .highlight:
            context.setFillColor(Theme.intent(mark.intent, alpha: mark.intent == .question ? 0.36 : 0.30))
            context.fill(MarkPath.rect(for: mark, mapping: mapping))
        case .arrow:
            context.addPath(MarkPath.path(for: mark, mapping: mapping, arrowHead: 12 * scale))
            context.setStrokeColor(color)
            context.setFillColor(color)
            context.setLineWidth(2 * scale)
            context.drawPath(using: .fillStroke)
        case .box, .oval:
            context.addPath(MarkPath.path(for: mark, mapping: mapping, inset: scale))
            context.setStrokeColor(color)
            context.setLineWidth(2 * scale)
            context.strokePath()
        case .pin, .redact:
            break
        }
        context.restoreGState()

        let tab = CGSize(width: 17 * scale, height: 14 * scale)
        let origin: CGPoint
        switch mark.kind {
        case .arrow, .pin: origin = CGPoint(x: anchor.x - tab.width / 2, y: anchor.y - tab.height / 2)
        default: origin = CGPoint(x: anchor.x, y: max(anchor.y - tab.height, 0))
        }
        let rect = CGRect(origin: origin, size: tab)
        context.setFillColor(color)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 3 * scale, cornerHeight: 3 * scale, transform: nil))
        context.fillPath()
        drawText(
            String(format: "%02d", number), x: rect.minX + 3 * scale, baseline: rect.minY + 10 * scale,
            font: Theme.mono(9 * scale, semibold: true), color: Theme.onIntent(mark.intent), in: context
        )
    }

    private static func drawText(_ text: String, x: Double, baseline: Double, font: CTFont, color: CGColor, tracking: Double = 0, scale: Double = 1, in context: CGContext) {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color, kCTKernAttributeName: tracking]
        guard let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else { return }
        draw(CTLineCreateWithAttributedString(string), x: x, baseline: baseline, scale: scale, in: context)
    }

    private static func draw(_ line: CTLine, x: Double, baseline: Double, scale: Double = 1, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: x, y: baseline)
        context.scaleBy(x: scale, y: scale)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
