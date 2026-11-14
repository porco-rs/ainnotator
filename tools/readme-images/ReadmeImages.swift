import AICore
import AIRender
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import QuartzCore
import Testing

// Product renders for the README images: the overlay and the card come from AIRender, every state from the real
// reducer. Not part of the test suite: render.sh copies this file to Tests/AIRenderTests/, runs it once and removes
// it again. Without README_SRC and README_OUT it does nothing. README_LANG picks the app language (default en).
//
// Writes to README_OUT:
//   overlay/NNN.png   overlay frames at 2x, only where the state changed
//   timeline.tsv      one row per hero frame (12 fps): overlay frame, pointer, key cap, step, terminal line, card alpha
//   overlay-final.png the overlay with all marks set, nothing selected
//   card.png          the card exactly as the app exports it
//   geometry.tsv      where callout targets sit on card.png, for stage.swift anatomy

private let fps = 12.0
private let size = CGSize(width: 1024, height: 640)

private enum Step {
    case events(Double, [Event])
    /// Pointer moves without a button, as the user aims.
    case aim(from: CGPoint, to: CGPoint, start: Double, end: Double)
    case drag(from: CGPoint, to: CGPoint, start: Double, end: Double)
    case type(String, start: Double, end: Double)
}

@MainActor @Test func readmeImages() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let sourcePath = environment["README_SRC"], let out = environment["README_OUT"] else { return }
    // The app decides its language once at launch and passes it down; here README_LANG stands in for that decision.
    let language = try #require(Language(rawValue: environment["README_LANG"] ?? "en"))
    print("readme images: language \(language.rawValue)")
    // As in Sources/AInnotator/main.swift, so labels are set in SF Mono like in the app, not in the Menlo fallback.
    Theme.monoProvider = { size, weight in
        let appKitWeight: NSFont.Weight = switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: appKitWeight) as CTFont
    }
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil))
    let picture = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(picture.width == Int(size.width * 2) && picture.height == Int(size.height * 2))
    let stage = Stage(pixelWidth: picture.width, pixelHeight: picture.height, pointWidth: size.width, pointHeight: size.height)
    try FileManager.default.createDirectory(atPath: out + "/overlay", withIntermediateDirectories: true)

    func norm(_ p: CGPoint) -> NormPoint { NormPoint(x: p.x / size.width, y: p.y / size.height) }
    func key(_ k: Key) -> Event { .key(KeyInput(key: k)) }
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    // The script of the hero, in seconds. Coordinates are points on the invented screen (screen.swift).
    let begin = 1.0, closed = 9.15, terminal = 9.75, pasted = 10.35, typed = 10.6, card = 11.3, end = 14.5
    let script: [Step] = [
        .aim(from: p(700, 600), to: p(560, 420), start: 0.0, end: 0.8),
        .events(begin, [.begin(stage)]),
        .aim(from: p(560, 420), to: p(108, 176), start: begin, end: 1.45),
        .drag(from: p(108, 176), to: p(916, 616), start: 1.5, end: 2.2),
        // 01 CHANGE box, the intent the app starts with
        .aim(from: p(916, 616), to: p(116, 434), start: 2.25, end: 2.45),
        .drag(from: p(116, 434), to: p(552, 503), start: 2.5, end: 2.9),
        .type("Apply next to the field", start: 2.95, end: 3.85),
        .events(3.95, [key(.enter)]),
        // 02 BUG arrow
        .events(4.15, [.insertText("1")]),
        .events(4.3, [.insertText("a")]),
        .aim(from: p(552, 503), to: p(752, 604), start: 4.3, end: 4.45),
        .drag(from: p(752, 604), to: p(828, 558), start: 4.5, end: 4.9),
        .type("Should be $46.35", start: 4.95, end: 5.55),
        .events(5.65, [key(.enter)]),
        // A redaction over the e-mail address
        .events(5.85, [.insertText("x")]),
        .aim(from: p(828, 558), to: p(134, 251), start: 5.85, end: 6.0),
        .drag(from: p(134, 251), to: p(334, 281), start: 6.05, end: 6.4),
        // 03 KEEP box without a note
        .events(6.6, [.insertText("3")]),
        .events(6.72, [.insertText("b")]),
        .aim(from: p(334, 281), to: p(116, 306), start: 6.72, end: 6.85),
        .drag(from: p(116, 306), to: p(552, 415), start: 6.9, end: 7.25),
        .events(7.4, [key(.enter)]),
        // 04 QUESTION oval
        .events(7.6, [.insertText("4")]),
        .events(7.72, [.insertText("o")]),
        .aim(from: p(552, 415), to: p(640, 255), start: 7.72, end: 7.85),
        .drag(from: p(640, 255), to: p(742, 289), start: 7.9, end: 8.2),
        .type("Real stock?", start: 8.25, end: 8.65),
        .events(8.8, [key(.enter)]),
        .events(9.0, [key(.enter)]),
    ]
    let keycaps: [(Double, Double, String)] = [
        (0.35, 1.2, "⌥⇧A"), (1.5, 2.2, "drag"), (2.5, 2.9, "drag"), (3.95, 4.15, "⏎"), (4.15, 4.3, "1"), (4.3, 4.5, "A"),
        (5.65, 5.85, "⏎"), (5.85, 6.05, "X"), (6.6, 6.72, "3"), (6.72, 6.9, "B"), (7.4, 7.6, "⏎"), (7.6, 7.72, "4"),
        (7.72, 7.9, "O"), (8.8, 9.6, "⏎ ⏎"), (pasted - 0.25, pasted + 0.35, "⌘V"),
    ]

    // Expand the script into timed events and a pointer track.
    var timed: [(Double, Event)] = []
    var track: [(Double, CGPoint)] = []
    for step in script {
        switch step {
        case .events(let t, let events):
            timed += events.map { (t, $0) }
        case .aim(let a, let b, let t0, let t1), .drag(let a, let b, let t0, let t1):
            let isDrag: Bool
            if case .drag = step { isDrag = true } else { isDrag = false }
            let n = max(2, Int(((t1 - t0) * fps * 2).rounded()))
            if isDrag { timed.append((t0, .pointerDown(norm(a)))) }
            for i in 0...n {
                let u = Double(i) / Double(n)
                let e = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
                let point = CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
                let t = t0 + (t1 - t0) * u
                track.append((t, point))
                timed.append((t, .pointerMoved(norm(point), inside: true)))
            }
            if isDrag { timed.append((t1 + 0.001, .pointerUp)) }
        case .type(let text, let t0, let t1):
            let characters = Array(text)
            for (i, character) in characters.enumerated() {
                timed.append((t0 + (t1 - t0) * Double(i) / Double(characters.count), .insertText(String(character))))
            }
        }
    }
    // Stable by time: events of one moment keep the order of the script.
    timed = timed.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map(\.element)
    track = track.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map(\.element)

    let scene = OverlayScene(size: size, scale: 2, language: language)
    scene.setImage(picture)
    func renderOverlay(_ state: CaptureState, to path: String) throws {
        scene.apply(state, isActive: true)
        CATransaction.flush()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let context = try #require(CGContext(
            data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info
        ))
        context.translateBy(x: 0, y: CGFloat(picture.height))
        context.scaleBy(x: 2, y: -2)
        scene.root.render(in: context)
        try write(try #require(context.makeImage()), to: path)
    }

    var state = CaptureState()
    var next = 0
    var lastRendered: CaptureState?
    var lastFile = "-"
    var finalMarked: CaptureState?
    var rows = ["frame\toverlay\tx\ty\tcursor\tkey\tstep\tterminal\tcard"]
    let frames = Int((end * fps).rounded())
    for frame in 0..<frames {
        let t = Double(frame) / fps
        while next < timed.count, timed[next].0 <= t + 1e-9 {
            _ = reduce(&state, timed[next].1)
            if state.mode == .annotate, state.active == nil, !state.noteMode, state.drag == nil, state.marks.count == 5 { finalMarked = state }
            next += 1
        }
        let pointer = track.last { $0.0 <= t + 1e-9 }?.1 ?? track[0].1
        var overlay = "-"
        if state.mode == .select || state.mode == .annotate {
            if state != lastRendered {
                lastFile = String(format: "overlay/%03d.png", frame)
                try renderOverlay(state, to: out + "/" + lastFile)
                lastRendered = state
            }
            overlay = lastFile
        }
        let cursor: String
        if t < begin || (t >= closed && t < terminal) { cursor = "arrow" }
        else if state.mode == .select && state.drag == nil { cursor = "none" }
        else if state.mode == .select || state.mode == .annotate { cursor = "cross" }
        else { cursor = "none" }
        let cap = keycaps.first { t >= $0.0 && t < $0.1 }?.2 ?? "-"
        let step = t < closed - 0.2 ? 1 : t < terminal ? 2 : 3
        var line = "-"
        if t >= terminal {
            line = "> "
            if t >= pasted { line += "[Image #1] " }
            if t >= typed { line += String("fix these".prefix(Int(((t - typed) / 0.05).rounded(.down)) + 1)) }
        }
        let cardAlpha = max(0, min(1, (t - card) / 0.5))
        rows.append([String(frame), overlay, String(format: "%.1f", pointer.x), String(format: "%.1f", pointer.y), cursor, cap, String(step), line, String(format: "%.3f", cardAlpha)].joined(separator: "\t"))
    }
    try (rows.joined(separator: "\n") + "\n").write(toFile: out + "/timeline.tsv", atomically: true, encoding: .utf8)

    let marked = try #require(finalMarked)
    try renderOverlay(marked, to: out + "/overlay-final.png")
    #expect(state.mode == .done)
    let context = CaptureContext(app: "Browser", url: "https://tinyplant.example/checkout?step=pay", repo: "tiny-plant", branch: "main")
    let input = CardRenderer.Input(source: .image(picture), state: state, footer: Payload.contextLine(context) ?? "", language: language)
    try #require(CardRenderer.renderPNG(input)).write(to: URL(fileURLWithPath: out + "/card.png"))

    // Card pixels of the callout targets that come from the marks; the legend rows are found in the image itself.
    let sel = try #require(state.sel)
    let ph = Double(picture.height)
    let redaction = try #require(state.marks.first { $0.kind == .redact })
    let numbered = CardRenderer.numbered(state.marks)
    // Callout B points at the tab of the keep box, the topmost tab on the left edge.
    let firstBox = try #require(numbered.first { $0.mark.kind == .box && $0.mark.intent == .keep }?.mark)
    let noNote = try #require(numbered.firstIndex { $0.mark.note.isEmpty })
    let geometry = [
        "imageHeight\t\(Int((sel.h * ph).rounded()))",
        "redactionY\t\(Int(((redaction.y + redaction.h / 2 - sel.y) * ph).rounded()))",
        // Tabs sit above a box's top edge, 14 pt high at scale 2.
        "tabY\t\(Int(((firstBox.y - sel.y) * ph - 14).rounded()))",
        "noNoteRow\t\(noNote)",
    ]
    try (geometry.joined(separator: "\n") + "\n").write(toFile: out + "/geometry.tsv", atomically: true, encoding: .utf8)
}

private func write(_ image: CGImage, to path: String) throws {
    let destination = try #require(CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}
