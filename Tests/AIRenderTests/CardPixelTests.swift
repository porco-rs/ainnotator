import AICore
import AIRender
import CoreGraphics
import IOSurface
import Testing

private let source: (r: UInt8, g: UInt8, b: UInt8) = (0x12, 0x34, 0x56)

private func surfaceProperties(width: Int, height: Int) -> CFDictionary {
    let properties: [CFString: Any] = [
        kIOSurfaceWidth: width, kIOSurfaceHeight: height, kIOSurfaceBytesPerElement: 4, kIOSurfacePixelFormat: 0x4247_5241,
    ]
    return properties as CFDictionary
}

private func filledSurface(width: Int, height: Int) throws -> IOSurfaceRef {
    let surface = try #require(IOSurfaceCreate(surfaceProperties(width: width, height: height)))
    IOSurfaceLock(surface, [], nil)
    defer { IOSurfaceUnlock(surface, [], nil) }
    let base = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
    let stride = IOSurfaceGetBytesPerRow(surface)
    for y in 0..<height {
        for x in 0..<width {
            let pixel = base + y * stride + x * 4
            pixel[0] = source.b
            pixel[1] = source.g
            pixel[2] = source.r
            pixel[3] = 0xFF
        }
    }
    return surface
}

private func filledImage(width: Int, height: Int) throws -> CGImage {
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info
    ))
    context.setFillColor(CGColor(srgbRed: 0x12 / 255, green: 0x34 / 255, blue: 0x56 / 255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

/// BGRA bytes of the rendered card, top row first.
private func pixels(of image: CGImage) throws -> (data: [UInt8], stride: Int) {
    let stride = image.width * 4
    var data = [UInt8](repeating: 0, count: stride * image.height)
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: stride, space: space, bitmapInfo: info
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (data, stride)
}

private func redactionCase() -> CaptureState {
    var state = CaptureState()
    state.stage = Stage(pixelWidth: 400, pixelHeight: 300, pointWidth: 200, pointHeight: 150)
    state.sel = NormRect(x: 0.25, y: 0, w: 0.5, h: 1)
    state.marks = [Mark(id: 1, kind: .redact, intent: .change, x: 0.25, y: 0, w: 0.25, h: 0.5, x0: 0.25, y0: 0, x1: 0.5, y1: 0.5)]
    return state
}

/// Redacted pixels must not carry the original, and everything else must stay exact, so the read is right too
/// (row stride, crop, flip, color space).
private func expectRedactionOverwritesPixels(_ card: CGImage) throws {
    // The 200 px crop sits on the 320 pt minimum width at 2 px per point.
    #expect(card.width == 640)
    let (data, stride) = try pixels(of: card)

    func isSource(_ x: Int, _ y: Int) -> Bool {
        let at = y * stride + x * 4
        return data[at] == source.b && data[at + 1] == source.g && data[at + 2] == source.r
    }

    var redactedSource = 0
    for y in 0..<150 {
        for x in 0..<100 where isSource(x, y) { redactedSource += 1 }
    }
    #expect(redactedSource == 0)

    var keptSource = 0
    for y in 150..<300 {
        for x in 0..<200 where isSource(x, y) { keptSource += 1 }
    }
    #expect(keptSource == 150 * 200)
}

@Test func redactionOverwritesPixelsInAnImage() throws {
    let image = try filledImage(width: 400, height: 300)
    try expectRedactionOverwritesPixels(try #require(CardRenderer.render(CardRenderer.Input(source: .image(image), state: redactionCase(), footer: "t"))))
}

/// The path the app takes. A sandboxed process may refuse IOSurfaceCreate, so the test is skipped there.
@Test(.enabled(if: IOSurfaceCreate(surfaceProperties(width: 1, height: 1)) != nil))
func redactionOverwritesPixelsInASurface() throws {
    let surface = try filledSurface(width: 400, height: 300)
    try expectRedactionOverwritesPixels(try #require(CardRenderer.render(CardRenderer.Input(source: .surface(surface), state: redactionCase(), footer: "t"))))
}

/// A bright secret on a black screen, covering exactly the pixels a redaction touches, including the ones it only
/// partly covers. Whatever bright pixel appears in the image area of the card is the secret.
private func secretScene() throws -> (image: CGImage, state: CaptureState) {
    let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info))
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
    // Mark in pixels: x 200.3...600.7, y 240.56...441.28, so whole pixels 200..<601 and 240..<442. The context is y-up.
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 200, y: 800 - 442, width: 401, height: 202))
    var state = CaptureState()
    state.stage = Stage(pixelWidth: 1000, pixelHeight: 800, pointWidth: 500, pointHeight: 400)
    state.sel = .full
    state.marks = [Mark(id: 1, kind: .redact, intent: .change, x: 0.2003, y: 0.3007, w: 0.4004, h: 0.2509, x0: 0.2003, y0: 0.3007, x1: 0.6007, y1: 0.5516)]
    return (try #require(context.makeImage()), state)
}

private func brightPixels(in card: CGImage, imageHeight: Int) throws -> Int {
    let (data, rowBytes) = try pixels(of: card)
    var bright = 0
    for y in 0..<min(imageHeight, card.height) {
        for x in 0..<card.width {
            let at = y * rowBytes + x * 4
            if data[at] > 60 || data[at + 1] > 60 || data[at + 2] > 60 { bright += 1 }
        }
    }
    return bright
}

@Test func noOriginalPixelSurvivesAlongARedactionEdgeInThePNG() throws {
    let scene = try secretScene()
    let card = try #require(CardRenderer.render(CardRenderer.Input(source: .image(scene.image), state: scene.state, footer: "")))
    #expect(try brightPixels(in: card, imageHeight: 800) == 0)
}

/// The preview scales the image, and a filter reaches further than one pixel: the secret must be gone before it runs.
@Test func noOriginalPixelSurvivesAlongARedactionEdgeInThePreview() throws {
    let scene = try secretScene()
    let card = try #require(CardRenderer.render(CardRenderer.Input(source: .image(scene.image), state: scene.state, footer: ""), previewWidth: 320))
    #expect(try brightPixels(in: card, imageHeight: 256) == 0)
}

/// A scale with a fraction once truncated the card height, so the footer rule covered the last row of the image.
@Test func theFooterLeavesTheLastImageRowAlone() throws {
    let image = try filledImage(width: 4000, height: 300)
    var state = CaptureState()
    state.stage = Stage(pixelWidth: 4000, pixelHeight: 300, pointWidth: 4000, pointHeight: 300)
    state.sel = .full
    let card = try #require(CardRenderer.render(CardRenderer.Input(source: .image(image), state: state, footer: "t")))
    #expect(card.width == 4000)
    let (data, rowBytes) = try pixels(of: card)
    var kept = 0
    for x in 0..<4000 {
        let at = 299 * rowBytes + x * 4
        if data[at] == source.b && data[at + 1] == source.g && data[at + 2] == source.r { kept += 1 }
    }
    #expect(kept == 4000)
}
