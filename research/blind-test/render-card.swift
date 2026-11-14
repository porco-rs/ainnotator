import AICore
import AIRender
import CoreGraphics
import Foundation
import ImageIO
import Testing

// Renders the card of the blind test with the product's own renderer. It is not part of the test suite: copy it
// next to the render tests, run it once and remove it again. From the repository root:
//
//   swiftc -O -o build/blind-screen research/blind-test/screen.swift && build/blind-screen build/blind-screen.png
//   cp research/blind-test/render-card.swift Tests/AIRenderTests/BlindTestTemp.swift
//   BLIND_SRC=$PWD/build/blind-screen.png BLIND_OUT=$PWD/build/blind swift test --filter blindProbeCard
//   rm Tests/AIRenderTests/BlindTestTemp.swift
//
// build/blind/card.png is the card. marks-only.png is the same picture with legend and footer cut off (the top
// 1400 pixel rows).
@Test func blindProbeCard() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let sourcePath = environment["BLIND_SRC"], let out = environment["BLIND_OUT"] else { return }
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil))
    let picture = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let width = Double(picture.width), height = Double(picture.height)

    func mark(_ id: Int, _ kind: MarkKind, _ intent: Intent, _ note: String, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Mark {
        Mark(
            id: id, kind: kind, intent: intent, note: note,
            x: min(x0, x1) / width, y: min(y0, y1) / height, w: abs(x1 - x0) / width, h: abs(y1 - y0) / height,
            x0: x0 / width, y0: y0 / height, x1: x1 / width, y1: y1 / height
        )
    }
    var state = CaptureState()
    state.stage = Stage(pixelWidth: picture.width, pixelHeight: picture.height, pointWidth: width / 2, pointHeight: height / 2)
    state.marks = [
        mark(1, .box, .change, "Move the Export button next to the search field", 2060, 14, 2360, 106),
        mark(2, .arrow, .bug, "Total is net, should be gross", 1640, 1060, 1790, 935),
        mark(3, .oval, .question, "", 1780, 262, 2360, 538),
        mark(4, .box, .keep, "", 40, 156, 1000, 244),
        mark(5, .pin, .change, "Font too small here", 420, 1322, 420, 1322),
        mark(6, .redact, .change, "", 300, 690, 860, 770),
    ]
    let context = CaptureContext(app: "Chrome", url: "https://acme-supply.example/orders", repo: "shop", branch: "main")
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    let input = CardRenderer.Input(source: .image(picture), state: state, footer: Payload.contextLine(context) ?? "")
    let png = try #require(CardRenderer.renderPNG(input))
    try png.write(to: URL(fileURLWithPath: out + "/card.png"))
    if let preview = CardRenderer.render(input, previewWidth: 640),
       let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out + "/preview.png") as CFURL, "public.png" as CFString, 1, nil) {
        CGImageDestinationAddImage(destination, preview, nil)
        CGImageDestinationFinalize(destination)
    }
}
