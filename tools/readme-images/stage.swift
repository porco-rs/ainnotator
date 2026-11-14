import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Composes the README images around the product renders of ReadmeImages.swift. Only the stage is drawn here: dark
// ground, generic windows, key caps, captions. Overlay and card are always the app's own pixels.
//
//   stage hero-frames <work> <frames-dir>     one PNG per frame of timeline.tsv, 1280×880
//   stage hero-still  <work> <out.png>        the moment before ⏎⏎, 1760×1210
//   stage anatomy     <work> <out.png>        the card at 1:1 with lettered callouts
//   stage blind       <test-dir> <out.png>    the blind test, from research/blind-test
//   stage everywhere  <work> <out.png>        one ⌘V, terminal and browser
//   stage social      <work> <icon.png> <out.png>
//
// <work> holds screen.png, card.png, overlay-final.png, overlay/ and timeline.tsv.

enum Failure: Error { case message(String) }

/// Same conversion as AIRender's Theme, so stage colors match the app exactly.
func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double, _ alpha: CGFloat = 1) -> CGColor {
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
func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: alpha)
}

let bug = oklch(0.66, 0.21, 27), change = oklch(0.64, 0.21, 293), keep = oklch(0.78, 0.17, 152), question = oklch(0.86, 0.15, 88)
let groundColor = oklch(0.12, 0.004, 250)
let textColor = oklch(0.97, 0, 0), muted = oklch(0.70, 0.005, 250), dim = oklch(0.52, 0.005, 250)
let hairline = hex(0xFFFFFF, 0.12)

func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CTFont { NSFont.systemFont(ofSize: size, weight: weight) as CTFont }
func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CTFont { NSFont.monospacedSystemFont(ofSize: size, weight: weight) as CTFont }

func load(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.message("Missing image: \(path)") }
    return image
}

final class Canvas {
    let width: Int, height: Int
    let c: CGContext
    /// Draw in base units; the bitmap is base × scale.
    init(_ width: Int, _ height: Int, scale: CGFloat = 1) {
        self.width = width; self.height = height
        c = CGContext(data: nil, width: Int((CGFloat(width) * scale).rounded()), height: Int((CGFloat(height) * scale).rounded()),
                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        c.translateBy(x: 0, y: CGFloat(height) * scale)
        c.scaleBy(x: scale, y: -scale)
        c.interpolationQuality = .high
        c.setShouldSmoothFonts(false)
    }
    var w: CGFloat { CGFloat(width) }
    var h: CGFloat { CGFloat(height) }

    func fill(_ r: CGRect, _ color: CGColor, radius: CGFloat = 0) {
        c.setFillColor(color)
        c.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        c.fillPath()
    }
    func stroke(_ r: CGRect, _ color: CGColor, line: CGFloat = 1, radius: CGFloat = 0, dash: [CGFloat] = []) {
        c.saveGState()
        c.setStrokeColor(color); c.setLineWidth(line); c.setLineDash(phase: 0, lengths: dash)
        c.addPath(CGPath(roundedRect: r.insetBy(dx: line / 2, dy: line / 2), cornerWidth: radius, cornerHeight: radius, transform: nil))
        c.strokePath()
        c.restoreGState()
    }
    func line(_ points: [CGPoint], _ color: CGColor, width: CGFloat = 1, dash: [CGFloat] = []) {
        c.saveGState()
        c.setStrokeColor(color); c.setLineWidth(width); c.setLineDash(phase: 0, lengths: dash); c.setLineCap(.round); c.setLineJoin(.round)
        c.addLines(between: points)
        c.strokePath()
        c.restoreGState()
    }
    func circle(_ center: CGPoint, _ radius: CGFloat, fill: CGColor? = nil, stroke: CGColor? = nil, line: CGFloat = 1) {
        let r = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        if let fill { c.setFillColor(fill); c.fillEllipse(in: r) }
        if let stroke { c.setStrokeColor(stroke); c.setLineWidth(line); c.strokeEllipse(in: r.insetBy(dx: line / 2, dy: line / 2)) }
    }

    func line(_ text: String, _ font: CTFont, _ color: CGColor, kern: CGFloat = 0) -> CTLine {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color, kCTKernAttributeName: kern]
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
    }
    func measure(_ text: String, _ font: CTFont, kern: CGFloat = 0) -> CGFloat {
        CTLineGetTypographicBounds(line(text, font, textColor, kern: kern), nil, nil, nil)
    }
    enum Align { case left, center, right }
    /// `y` is the baseline.
    @discardableResult
    func text(_ string: String, _ x: CGFloat, _ y: CGFloat, _ font: CTFont, _ color: CGColor, align: Align = .left, kern: CGFloat = 0) -> CGFloat {
        let l = line(string, font, color, kern: kern)
        let width = CTLineGetTypographicBounds(l, nil, nil, nil)
        let start = align == .left ? x : align == .center ? x - width / 2 : x - width
        c.saveGState()
        c.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        c.textPosition = CGPoint(x: start, y: y)
        CTLineDraw(l, c)
        c.restoreGState()
        return width
    }
    /// Mixed colors on one line, left to right from x.
    func runs(_ parts: [(String, CTFont, CGColor)], _ x: CGFloat, _ y: CGFloat) -> CGFloat {
        var cursor = x
        for (string, font, color) in parts { cursor += text(string, cursor, y, font, color) }
        return cursor
    }

    func image(_ image: CGImage, _ r: CGRect, alpha: CGFloat = 1, radius: CGFloat = 0, source: CGRect? = nil) {
        let piece = source.flatMap { image.cropping(to: $0) } ?? image
        c.saveGState()
        if radius > 0 { c.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); c.clip() }
        c.setAlpha(alpha)
        c.translateBy(x: r.minX, y: r.maxY)
        c.scaleBy(x: 1, y: -1)
        c.draw(piece, in: CGRect(origin: .zero, size: r.size))
        c.restoreGState()
    }
    func shadow(_ r: CGRect, radius: CGFloat, blur: CGFloat = 40, offset: CGFloat = 16, alpha: CGFloat = 0.6) {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: offset), blur: blur, color: hex(0, alpha))
        fill(r, hex(0x000000), radius: radius)
        c.restoreGState()
    }

    /// The stage: near-black ground of the card with a faint drafting grid, like the app icon's blueprint.
    func ground(grid: CGFloat = 40) {
        fill(CGRect(x: 0, y: 0, width: w, height: h), groundColor)
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [hex(0x2A3550, 0.35), hex(0x2A3550, 0)] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(glow, startCenter: CGPoint(x: w * 0.3, y: 0), startRadius: 0, endCenter: CGPoint(x: w * 0.3, y: 0), endRadius: max(w, h) * 0.9, options: [])
        c.saveGState()
        c.setStrokeColor(hex(0xFFFFFF, 0.035)); c.setLineWidth(1)
        var x = grid
        while x < w { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: h)); x += grid }
        var y = grid
        while y < h { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: w, y: y)); y += grid }
        c.strokePath()
        c.restoreGState()
    }

    func keycap(_ label: String, center: CGPoint, size: CGFloat) {
        let font = label == "drag" ? mono(size * 0.8, .medium) : sans(size, .medium)
        let width = max(size * 2.1, measure(label, font) + size * 1.2)
        let height = size * 1.9
        let r = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        shadow(r, radius: size * 0.35, blur: 10, offset: 3, alpha: 0.5)
        fill(r, hex(0x2B2F36), radius: size * 0.35)
        fill(r.insetBy(dx: 1, dy: 1).offsetBy(dx: 0, dy: -1), hex(0x3A3F48), radius: size * 0.33)
        fill(r.insetBy(dx: 1, dy: 3).offsetBy(dx: 0, dy: 1), hex(0x30343C), radius: size * 0.3)
        text(label, center.x, center.y + size * 0.36, font, textColor, align: .center)
    }

    /// A number tab like the card's, for steps and callouts.
    func tab(_ label: String, _ x: CGFloat, _ baseline: CGFloat, size: CGFloat, fill color: CGColor, ink: CGColor) -> CGFloat {
        let font = mono(size, .semibold)
        let width = measure(label, font) + size * 0.8
        fill(CGRect(x: x, y: baseline - size * 1.05, width: width, height: size * 1.45), color, radius: size * 0.22)
        text(label, x + size * 0.4, baseline, font, ink)
        return width
    }

    /// A generic window: rounded body, title bar with three dots and a centered title.
    func window(_ r: CGRect, title: String, dark: Bool, bar: CGFloat = 30, radius: CGFloat = 12) {
        shadow(r, radius: radius, blur: 36, offset: 14, alpha: 0.65)
        fill(r, dark ? hex(0x111317) : hex(0xF6F6F3), radius: radius)
        c.saveGState()
        c.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); c.clip()
        fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: bar), dark ? hex(0x1B1E23) : hex(0xE8E7E2))
        fill(CGRect(x: r.minX, y: r.minY + bar - 1, width: r.width, height: 1), dark ? hex(0xFFFFFF, 0.06) : hex(0x000000, 0.08))
        c.restoreGState()
        stroke(r, dark ? hex(0xFFFFFF, 0.10) : hex(0x000000, 0.10), line: 1, radius: radius)
        for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            circle(CGPoint(x: r.minX + bar * 0.55 + CGFloat(i) * bar * 0.62, y: r.minY + bar / 2), bar * 0.19, fill: dark ? hex(0x3A3E46) : hex(UInt32(color)))
        }
        text(title, r.midX, r.minY + bar * 0.66, mono(bar * 0.42), dark ? muted : hex(0x6B6E70), align: .center)
    }

    func arrowCursor(_ p: CGPoint, scale s: CGFloat) {
        let shape: [CGPoint] = [(0, 0), (0, 17), (4.2, 13.2), (7, 19.6), (9.6, 18.5), (6.9, 12.3), (12.4, 12.3)].map { CGPoint(x: p.x + $0.0 * s, y: p.y + $0.1 * s) }
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 1.5 * s), blur: 3 * s, color: hex(0, 0.45))
        c.addLines(between: shape); c.closePath(); c.setFillColor(hex(0x000000)); c.fillPath()
        c.restoreGState()
        c.addLines(between: shape); c.closePath(); c.setStrokeColor(hex(0xFFFFFF)); c.setLineWidth(1.2 * s); c.setLineJoin(.round); c.strokePath()
        c.addLines(between: shape); c.closePath(); c.setFillColor(hex(0x000000)); c.fillPath()
    }
    func crossCursor(_ p: CGPoint, scale s: CGFloat) {
        let arm = 8 * s, gap = 0.0
        for (color, width) in [(hex(0xFFFFFF), 3.2 * s), (hex(0x000000), 1.2 * s)] {
            line([CGPoint(x: p.x - arm, y: p.y), CGPoint(x: p.x - gap, y: p.y)], color, width: width)
            line([CGPoint(x: p.x + gap, y: p.y), CGPoint(x: p.x + arm, y: p.y)], color, width: width)
            line([CGPoint(x: p.x, y: p.y - arm), CGPoint(x: p.x, y: p.y - gap)], color, width: width)
            line([CGPoint(x: p.x, y: p.y + gap), CGPoint(x: p.x, y: p.y + arm)], color, width: width)
        }
    }

    func save(_ path: String) throws {
        guard let image = c.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.message("Cannot write \(path)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.message("Cannot finish \(path)") }
    }
}

// MARK: Hero

/// Screen area 1280×800 (the 1024×640 pt screen at 1.25), below it a band with steps and key caps.
let heroWidth = 1280, heroHeight = 880, screenScale: CGFloat = 1.25

struct Frame {
    var overlay: String, x: CGFloat, y: CGFloat, cursor: String, key: String, step: Int, terminal: String, card: CGFloat
}

func timeline(_ work: String) throws -> [Frame] {
    let rows = try String(contentsOfFile: work + "/timeline.tsv", encoding: .utf8).split(separator: "\n").dropFirst()
    return rows.map { row in
        let f = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        return Frame(overlay: f[1], x: CGFloat(Double(f[2])!), y: CGFloat(Double(f[3])!), cursor: f[4], key: f[5], step: Int(f[6])!, terminal: f[7], card: CGFloat(Double(f[8])!))
    }
}

func band(_ a: Canvas, step: Int, key: String, caption: String? = nil) {
    let top: CGFloat = 800
    a.fill(CGRect(x: 0, y: top, width: a.w, height: 80), hex(0x07080A))
    a.fill(CGRect(x: 0, y: top, width: a.w, height: 1), hairline)
    var x: CGFloat = 36
    for (index, name) in ["MARK", "COPY", "PASTE"].enumerated() {
        let active = index + 1 == step
        let done = index + 1 < step
        x += a.tab(String(format: "%02d", index + 1), x, top + 49, size: 17, fill: active ? textColor : done ? hex(0xFFFFFF, 0.28) : hex(0xFFFFFF, 0.10), ink: active ? groundColor : done ? textColor : dim) + 10
        x += a.text(name, x, top + 49, mono(19, .medium), active ? textColor : done ? muted : dim, kern: 1.2) + 34
    }
    if let caption { a.text(caption, a.w - 40, top + 48, mono(19), muted, align: .right) }
    if key != "-" { a.keycap(key, center: CGPoint(x: a.w - 36 - max(46, a.measure(key, sans(24, .medium)) / 2 + 22), y: top + 40), size: 24) }
}

func terminalScene(_ a: Canvas, screen: CGImage, card: CGImage, line: String, cardAlpha: CGFloat, dimAlpha: CGFloat) {
    a.image(screen, CGRect(x: 0, y: 0, width: 1280, height: 800))
    a.fill(CGRect(x: 0, y: 0, width: 1280, height: 800), hex(0x05070A, 0.8 * dimAlpha))
    let cardWidth: CGFloat = 980
    let cardHeight = cardWidth * CGFloat(card.height) / CGFloat(card.width)
    if cardAlpha > 0 {
        let r = CGRect(x: (1280 - cardWidth) / 2, y: 104 + (1 - cardAlpha) * 24, width: cardWidth, height: cardHeight)
        a.c.saveGState(); a.c.setAlpha(cardAlpha)
        a.shadow(r, radius: 10, blur: 40, offset: 18, alpha: 0.7)
        a.image(card, r, radius: 10)
        a.stroke(r, hex(0xFFFFFF, 0.14), radius: 10)
        a.c.restoreGState()
    }
    let t = CGRect(x: (1280 - cardWidth) / 2, y: 18, width: cardWidth, height: 70)
    a.window(t, title: "tiny-plant", dark: true, bar: 22, radius: 10)
    let baseline = t.minY + 22 + 32
    var x = t.minX + 22
    x += a.text("> ", x, baseline, mono(21), muted)
    let rest = String(line.dropFirst(2))
    if rest.hasPrefix("[Image #1]") {
        let tag = "[Image #1]"
        let width = a.measure(tag, mono(21, .semibold))
        a.fill(CGRect(x: x - 4, y: baseline - 20, width: width + 8, height: 27), hex(0xFFFFFF, 0.10), radius: 5)
        x += a.text(tag, x, baseline, mono(21, .semibold), textColor)
        x += a.text(String(rest.dropFirst(tag.count)), x, baseline, mono(21), textColor)
    }
    a.fill(CGRect(x: x + 2, y: baseline - 19, width: 11, height: 24), hex(0xFFFFFF, 0.85))
}

func heroFrame(_ f: Frame, index: Int, firstTerminal: Int, screen: CGImage, card: CGImage, work: String, scale: CGFloat = 1, overlayPath: String? = nil) throws -> Canvas {
    let a = Canvas(heroWidth, heroHeight, scale: scale)
    a.fill(CGRect(x: 0, y: 0, width: a.w, height: a.h), hex(0x07080A))
    if f.terminal != "-" {
        let dimAlpha = min(1, CGFloat(index - firstTerminal + 1) / 4)
        terminalScene(a, screen: screen, card: card, line: f.terminal, cardAlpha: f.card, dimAlpha: dimAlpha)
    } else {
        let path = overlayPath ?? (f.overlay == "-" ? nil : work + "/" + f.overlay)
        a.image(try path.map(load) ?? screen, CGRect(x: 0, y: 0, width: 1280, height: 800))
        let p = CGPoint(x: f.x * screenScale, y: f.y * screenScale)
        if f.cursor == "arrow" { a.arrowCursor(p, scale: 1.25) }
        if f.cursor == "cross" { a.crossCursor(p, scale: 1.25) }
    }
    band(a, step: f.step, key: f.key, caption: f.card >= 0.999 ? "the model gets this one image" : nil)
    return a
}

// MARK: Anatomy

/// Vertical centers of the legend rows, found by the intent color of their number badges (x 20…58 px at scale 2),
/// so the callouts follow the card in any language and layout.
func legendRows(_ card: CGImage, below imageHeight: Int) throws -> [CGFloat] {
    let width = card.width, height = card.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure.message("Cannot read card pixels") }
    context.draw(card, in: CGRect(x: 0, y: 0, width: width, height: height))
    let intents = [bug, change, keep, question].map { ($0.components ?? []).map { Int(($0 * 255).rounded()) } }
    let x = 23  // inside the badge, left of its digits
    var rows: [CGFloat] = []
    var start: Int?
    for y in imageHeight..<height {
        let i = (y * width + x) * 4
        let rgb = [Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]
        let hit = intents.contains { color in zip(color, rgb).map { abs($0 - $1) }.reduce(0, +) < 60 }
        if hit, start == nil { start = y }
        if !hit, let s = start { rows.append(CGFloat(s + y) / 2); start = nil }
    }
    return rows
}

/// The card at 1:1 with lettered callouts in the left margin and their key below. Letters, so they never read as the
/// card's own numbers. Targets come from geometry.tsv (written by ReadmeImages.swift from the marks) and from the
/// legend rows found in card.png.
func anatomy(_ work: String, _ out: String) throws {
    let card = try load(work + "/card.png")
    var geometry: [String: Int] = [:]
    for line in try String(contentsOfFile: work + "/geometry.tsv", encoding: .utf8).split(separator: "\n") {
        let parts = line.split(separator: "\t")
        if parts.count == 2, let value = Int(parts[1]) { geometry[String(parts[0])] = value }
    }
    guard let imageHeight = geometry["imageHeight"], let redactionY = geometry["redactionY"], let tabY = geometry["tabY"],
          let noNoteRow = geometry["noNoteRow"] else { throw Failure.message("geometry.tsv incomplete") }
    let rows = try legendRows(card, below: imageHeight)
    guard rows.count > noNoteRow, let firstRow = rows.first else { throw Failure.message("legend rows not found: \(rows)") }
    let margin: CGFloat = 72, top: CGFloat = 64
    let cw = CGFloat(card.width), ch = CGFloat(card.height)
    let callouts: [(String, CGFloat, String, String)] = [
        ("A", CGFloat(redactionY), "Redaction is final.", "The pixels are overwritten; the original is never saved."),
        ("B", CGFloat(tabY), "A number and a color for every mark.", "Red bug, purple change, green keep, yellow question."),
        // The header line sits between the image and the first row.
        ("C", (CGFloat(imageHeight) + firstRow - 10) / 2, "It says which marks are yours.", "Numbered marks were added; everything else is the screen."),
        ("D", rows[noNoteRow], "Every mark is listed,", "with intent and shape, even without a note."),
        ("E", ch - 26, "Where it came from:", "app, address, repository and branch."),
    ]
    let keyTop = top + ch + 56
    let rowHeight: CGFloat = 92
    let height = Int(keyTop + CGFloat((callouts.count + 1) / 2) * rowHeight + 40)
    let a = Canvas(1760, height)
    a.ground()
    let r = CGRect(x: margin, y: top, width: cw, height: ch)
    a.shadow(r, radius: 10, blur: 50, offset: 20, alpha: 0.7)
    a.image(card, r, radius: 10)
    a.stroke(r, hex(0xFFFFFF, 0.14), radius: 10)
    func badge(_ letter: String, _ center: CGPoint, radius: CGFloat = 19) {
        a.circle(center, radius, fill: groundColor, stroke: hex(0xFFFFFF, 0.85), line: 2)
        a.text(letter, center.x, center.y + 8, mono(22, .semibold), textColor, align: .center)
    }
    for (letter, y, _, _) in callouts {
        let center = CGPoint(x: margin / 2, y: top + y)
        a.line([CGPoint(x: center.x + 19, y: center.y), CGPoint(x: margin + 10, y: center.y)], hex(0xFFFFFF, 0.85), width: 2)
        badge(letter, center)
    }
    // Key in two columns.
    let columnWidth = (a.w - 2 * margin) / 2
    for (index, callout) in callouts.enumerated() {
        let x = margin + CGFloat(index % 2) * columnWidth
        let y = keyTop + CGFloat(index / 2) * rowHeight
        badge(callout.0, CGPoint(x: x + 19, y: y + 14))
        a.text(callout.2, x + 56, y + 23, sans(28, .semibold), textColor)
        a.text(callout.3, x + 56, y + 61, sans(23), muted)
    }
    try a.save(out)
}

// MARK: Blind test

func blind(_ probes: String, _ out: String) throws {
    let plain = try load(probes + "/marks-only.png")
    let real = try load(probes + "/card.png")
    let a = Canvas(1760, 1060)
    a.ground()
    let margin: CGFloat = 64, gap: CGFloat = 56
    let column = (a.w - 2 * margin - gap) / 2
    a.text("BLIND TEST", margin, 92, mono(22, .semibold), muted, kern: 2)
    a.text("Three models, one image each, no other context: what does the user want?", margin, 140, sans(34, .semibold), textColor)

    let panels: [(CGFloat, String, CGImage, String, String, CGColor)] = [
        (margin, "MARKS ONLY", plain, "3 of 3", "took the app’s own hint (circled) for the user’s request", bug),
        (margin + column + gap, "AINNOTATOR CARD", real, "3 of 3", "read all five marks and took nothing on screen for a task", keep),
    ]
    let imageTop: CGFloat = 250
    for (x, title, image, number, verdict, color) in panels {
        a.text(title, x, imageTop - 26, mono(20, .semibold), muted, kern: 1.6)
        let height = column * CGFloat(image.height) / CGFloat(image.width)
        let r = CGRect(x: x, y: imageTop, width: column, height: height)
        a.shadow(r, radius: 8, blur: 30, offset: 12, alpha: 0.6)
        a.image(image, r, radius: 8)
        a.stroke(r, hex(0xFFFFFF, 0.14), radius: 8)
        let verdictTop = imageTop + column * 1705 / 2400 + 76
        a.fill(CGRect(x: x, y: verdictTop - 44, width: 8, height: 100), color, radius: 4)
        let numberFont = sans(54, .bold)
        a.text(number, x + 30, verdictTop + 10, numberFont, textColor)
        a.text("models", x + 30 + a.measure(number, numberFont) + 14, verdictTop + 10, sans(30, .medium), muted)
        a.text(verdict, x + 30, verdictTop + 50, sans(26), textColor)
    }
    // The decoy the models fell for: the app's own red hint "New: CSV export", not a mark. Ink, not white: the
    // dashboard is white, and a fifth color would read like another intent.
    let s = column / 2400
    let hint = CGRect(x: margin + 1690 * s, y: imageTop + 140 * s, width: 250 * s, height: 50 * s).insetBy(dx: -14, dy: -12)
    a.c.saveGState()
    a.c.setShadow(offset: .zero, blur: 0, color: nil)
    a.stroke(hint.insetBy(dx: -3, dy: -3), hex(0xFFFFFF, 0.9), line: 7, radius: 16)
    a.stroke(hint, hex(0x101216), line: 3, radius: 13, dash: [9, 6])
    a.c.restoreGState()

    a.text("Claude Haiku, Claude Opus and Codex, one run each. Five marks, two of them without a note. Material and answers: research/blind-test.", margin, a.h - 44, sans(21), dim)
    try a.save(out)
}

// MARK: Everywhere

func everywhere(_ work: String, _ out: String) throws {
    let card = try load(work + "/card.png")
    let a = Canvas(1760, 900)
    a.ground()
    let margin: CGFloat = 64
    a.keycap("⌘V", center: CGPoint(x: a.w / 2, y: 92), size: 34)
    a.text("one paste, the same image everywhere", a.w / 2, 172, mono(22, .medium), muted, align: .center, kern: 0.8)

    let gap: CGFloat = 64
    let width = (a.w - 2 * margin - gap) / 2
    let top: CGFloat = 230, height: CGFloat = 480
    // Terminal: the prompt, and under it what [Image #1] stands for.
    let t = CGRect(x: margin, y: top, width: width, height: height)
    a.window(t, title: "tiny-plant", dark: true, bar: 40, radius: 14)
    let prompt = t.minY + 40 + 62
    let tagX = t.minX + 30 + a.measure("> ", mono(25))
    let tagWidth = a.measure("[Image #1]", mono(25, .semibold))
    a.fill(CGRect(x: tagX - 5, y: prompt - 25, width: tagWidth + 10, height: 34), hex(0xFFFFFF, 0.10), radius: 6)
    let end = a.runs([("> ", mono(25), muted), ("[Image #1]", mono(25, .semibold), textColor), (" fix these", mono(25), textColor)], t.minX + 30, prompt)
    a.fill(CGRect(x: end + 3, y: prompt - 24, width: 13, height: 30), hex(0xFFFFFF, 0.85))
    let thumbWidth: CGFloat = width - 60
    let thumb = CGRect(x: t.minX + 30, y: prompt + 96, width: thumbWidth, height: thumbWidth * CGFloat(card.height) / CGFloat(card.width))
    let joint = CGPoint(x: tagX + tagWidth / 2, y: prompt + 16)
    a.line([joint, CGPoint(x: joint.x, y: thumb.minY - 6)], hex(0xFFFFFF, 0.45), width: 2, dash: [4, 5])
    a.circle(CGPoint(x: joint.x, y: thumb.minY - 6), 4, fill: hex(0xFFFFFF, 0.7))
    a.text("the card itself, as one image", joint.x + 18, prompt + 62, mono(19), dim)
    a.c.saveGState()
    a.c.addPath(CGPath(roundedRect: t.insetBy(dx: 1, dy: 1), cornerWidth: 14, cornerHeight: 14, transform: nil)); a.c.clip()
    a.image(card, thumb, alpha: 0.92, radius: 8)
    let fade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [hex(0x111317, 0), hex(0x111317, 1)] as CFArray, locations: [0, 1])!
    a.c.drawLinearGradient(fade, start: CGPoint(x: 0, y: t.maxY - 150), end: CGPoint(x: 0, y: t.maxY - 8), options: [.drawsAfterEndLocation])
    a.c.restoreGState()

    // Browser chat: an empty page with a composer holding the picture.
    let b = CGRect(x: margin + width + gap, y: top, width: width, height: height)
    a.window(b, title: "chat.example", dark: false, bar: 40, radius: 14)
    let composer = CGRect(x: b.minX + 40, y: b.midY - 70, width: b.width - 80, height: 250)
    a.shadow(composer, radius: 26, blur: 18, offset: 4, alpha: 0.12)
    a.fill(composer, hex(0xFFFFFF), radius: 26)
    a.stroke(composer, hex(0x000000, 0.10), line: 1.5, radius: 26)
    let tile = CGRect(x: composer.minX + 24, y: composer.minY + 24, width: 200, height: 200 * CGFloat(card.height) / CGFloat(card.width))
    a.image(card, tile, radius: 10)
    a.stroke(tile, hex(0x000000, 0.12), line: 1.5, radius: 10)
    a.circle(CGPoint(x: tile.maxX - 4, y: tile.minY + 4), 13, fill: hex(0x2A2C2E))
    a.line([CGPoint(x: tile.maxX - 9, y: tile.minY - 1), CGPoint(x: tile.maxX + 1, y: tile.minY + 9)], hex(0xFFFFFF), width: 2.2)
    a.line([CGPoint(x: tile.maxX + 1, y: tile.minY - 1), CGPoint(x: tile.maxX - 9, y: tile.minY + 9)], hex(0xFFFFFF), width: 2.2)
    a.text("fix these", composer.minX + 24, composer.maxY - 30, sans(25), hex(0x2A2C2E))
    let send = CGPoint(x: composer.maxX - 44, y: composer.maxY - 40)
    a.circle(send, 22, fill: hex(0x2A2C2E))
    a.line([CGPoint(x: send.x, y: send.y + 10), CGPoint(x: send.x, y: send.y - 10)], hex(0xFFFFFF), width: 3)
    a.line([CGPoint(x: send.x - 8, y: send.y - 2), CGPoint(x: send.x, y: send.y - 10), CGPoint(x: send.x + 8, y: send.y - 2)], hex(0xFFFFFF), width: 3)

    // Captions
    let captionTop = top + height + 64
    for (r, title, detail) in [
        (t, "In the terminal", "Claude Code and Codex attach it as [Image #1]."),
        (b, "In the browser", "claude.ai, ChatGPT and Claude Design take it as a picture."),
    ] {
        a.text(title, r.minX, captionTop, sans(30, .semibold), textColor)
        a.text(detail, r.minX, captionTop + 44, sans(24), muted)
    }
    try a.save(out)
}

// MARK: Social preview

let headline = ["Show,", "don’t type."]

func social(_ work: String, _ iconPath: String, _ out: String) throws {
    let card = try load(work + "/card.png")
    let icon = try load(iconPath)
    let a = Canvas(1280, 640)
    a.ground(grid: 32)
    a.image(icon, CGRect(x: 84, y: 92, width: 96, height: 96))
    a.text(headline[0], 84, 290, sans(72, .bold), textColor)
    a.text(headline[1], 84, 372, sans(72, .bold), textColor)
    a.text("AInnotator for macOS", 86, 452, mono(24, .semibold), textColor)
    a.text("Mark the screen, paste one image", 86, 492, mono(20), muted)
    a.text("into Claude Code, Codex or ChatGPT.", 86, 524, mono(20), muted)
    // The card, cropped at the right edge: marks above, legend below.
    let width: CGFloat = 840
    let r = CGRect(x: 596, y: 64, width: width, height: width * CGFloat(card.height) / CGFloat(card.width))
    a.shadow(r, radius: 12, blur: 40, offset: 16, alpha: 0.7)
    a.image(card, r, radius: 12)
    a.stroke(r, hex(0xFFFFFF, 0.14), radius: 12)
    try a.save(out)
}

// MARK: Main

do {
    let args = CommandLine.arguments
    guard args.count >= 4 else { throw Failure.message("usage: stage <hero-frames|hero-still|anatomy|blind|everywhere|social> …") }
    switch args[1] {
    case "hero-frames":
        let work = args[2]
        let frames = try timeline(work)
        let screen = try load(work + "/screen.png"), card = try load(work + "/card.png")
        let firstTerminal = frames.firstIndex { $0.terminal != "-" } ?? frames.count
        let scale = args.count > 4 ? CGFloat(Double(args[4]) ?? 1) : 1
        try FileManager.default.createDirectory(atPath: args[3], withIntermediateDirectories: true)
        for (index, frame) in frames.enumerated() {
            try heroFrame(frame, index: index, firstTerminal: firstTerminal, screen: screen, card: card, work: work, scale: scale)
                .save(String(format: "%@/frame-%03d.png", args[3], index))
        }
        print("hero frames: \(frames.count)")
    case "hero-still":
        let work = args[2]
        let screen = try load(work + "/screen.png"), card = try load(work + "/card.png")
        let still = Frame(overlay: "overlay-final.png", x: 0, y: 0, cursor: "none", key: "⏎ ⏎", step: 2, terminal: "-", card: 0)
        try heroFrame(still, index: 0, firstTerminal: 0, screen: screen, card: card, work: work, scale: 1.375, overlayPath: work + "/overlay-final.png").save(args[3])
    case "anatomy": try anatomy(args[2], args[3])
    case "blind": try blind(args[2], args[3])
    case "everywhere": try everywhere(args[2], args[3])
    case "social":
        guard args.count == 5 else { throw Failure.message("social needs work, icon and output") }
        try social(args[2], args[3], args[4])
    default: throw Failure.message("unknown command \(args[1])")
    }
} catch {
    FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
    exit(1)
}
