import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// The blueprint icon: a dimensioned part on the classic blue, on Apple's 824 px body grid.
// Detail drops with the pixel size, so small sizes stay a clear shape. The digits are strokes: no font in the icon.

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-app-icon <out.icns>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let files: [(String, Int)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                              ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                              ("icon_512x512", 512), ("icon_512x512@2x", 1024)]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let white = color(0xF4F5F7), yellow = color(0xF2C94C), ink = color(0x20201A)
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

func squircle(_ rect: CGRect) -> CGPath {
    let exponent: CGFloat = 5, steps = 720
    let path = CGMutablePath()
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let x = pow(abs(cos(angle)), 2 / exponent) * (cos(angle) < 0 ? -1 : 1)
        let y = pow(abs(sin(angle)), 2 / exponent) * (sin(angle) < 0 ? -1 : 1)
        let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func stroke(_ context: CGContext, _ points: [CGPoint], _ width: CGFloat, _ paint: CGColor, dash: [CGFloat] = [], cap: CGLineCap = .butt) {
    context.saveGState()
    context.setLineWidth(width); context.setStrokeColor(paint); context.setLineCap(cap); context.setLineJoin(.miter)
    if !dash.isEmpty { context.setLineDash(phase: 0, lengths: dash) }
    context.addLines(between: points); context.strokePath()
    context.restoreGState()
}

func arrow(_ context: CGContext, from: CGPoint, to: CGPoint, width: CGFloat, head: CGFloat) {
    let length = hypot(to.x - from.x, to.y - from.y), ux = (to.x - from.x) / length, uy = (to.y - from.y) / length
    let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head), half = head * 0.42
    stroke(context, [from, base], width, white)
    context.setFillColor(white)
    context.addLines(between: [to, CGPoint(x: base.x - uy * half, y: base.y + ux * half), CGPoint(x: base.x + uy * half, y: base.y - ux * half)])
    context.closePath(); context.fillPath()
}

func tab(_ context: CGContext, leftBottom: CGPoint, height: CGFloat, digits: Bool) {
    let rect = CGRect(x: leftBottom.x, y: leftBottom.y - height, width: height * 1.62, height: height)
    context.setFillColor(yellow)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: height * 0.16, cornerHeight: height * 0.16, transform: nil)); context.fillPath()
    guard digits else { return }
    let line = height * 0.115, top = rect.midY - height * 0.3, bottom = rect.midY + height * 0.3
    let zero = CGRect(x: rect.minX + rect.width * 0.17, y: top, width: rect.width * 0.27, height: bottom - top)
    context.setStrokeColor(ink); context.setLineWidth(line)
    context.addPath(CGPath(roundedRect: zero, cornerWidth: zero.width * 0.42, cornerHeight: zero.width * 0.42, transform: nil)); context.strokePath()
    let one = rect.minX + rect.width * 0.7
    stroke(context, [CGPoint(x: one - rect.width * 0.1, y: top + height * 0.13), CGPoint(x: one, y: top), CGPoint(x: one, y: bottom)], line, ink)
    stroke(context, [CGPoint(x: one - rect.width * 0.12, y: bottom), CGPoint(x: one + rect.width * 0.12, y: bottom)], line, ink)
}

func draw(_ context: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / 1024
    let plate = squircle(body)
    context.saveGState()
    // Shadows ignore the transform and the flip, so they are given in device terms.
    context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale, color: color(0x000000, 0.35))
    context.addPath(plate); context.setFillColor(color(0x0A2F5C)); context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(plate); context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x1763AE), color(0x0A2F5C)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    if pixels >= 64 {
        for value in stride(from: CGFloat(100), through: 924, by: 34) {
            let major = Int((value - 100) / 34) % 4 == 0
            guard major || pixels >= 256 else { continue }
            let paint = color(0xFFFFFF, major ? (pixels >= 256 ? 0.17 : 0.22) : 0.07)
            let width: CGFloat = major ? (pixels >= 256 ? 2.5 : 4) : 1.5
            stroke(context, [CGPoint(x: value, y: 100), CGPoint(x: value, y: 924)], width, paint)
            stroke(context, [CGPoint(x: 100, y: value), CGPoint(x: 924, y: value)], width, paint)
        }
    }
    context.restoreGState()

    if pixels >= 64 {
        let part = CGRect(x: 322, y: 366, width: 452, height: 396)
        let partWidth: CGFloat = pixels >= 128 ? 22 : 34, thin: CGFloat = pixels >= 128 ? 9 : 18, witness: CGFloat = pixels >= 128 ? 6 : 12, head: CGFloat = pixels >= 128 ? 54 : 78
        let outline = [CGPoint(x: part.minX, y: part.minY), CGPoint(x: part.maxX, y: part.minY), CGPoint(x: part.maxX, y: part.maxY), CGPoint(x: part.minX, y: part.maxY)]
        stroke(context, outline + [outline[0], outline[1]], partWidth, white)
        if pixels >= 128 {
            stroke(context, [CGPoint(x: part.midX - 96, y: part.midY), CGPoint(x: part.midX + 96, y: part.midY)], 8, color(0xFFFFFF, 0.8), dash: [40, 12, 8, 12])
            stroke(context, [CGPoint(x: part.midX, y: part.midY - 96), CGPoint(x: part.midX, y: part.midY + 96)], 8, color(0xFFFFFF, 0.8), dash: [40, 12, 8, 12])
        }
        let y: CGFloat = 232, x: CGFloat = 224
        stroke(context, [CGPoint(x: part.minX, y: part.minY - 20), CGPoint(x: part.minX, y: y - 24)], witness, white)
        stroke(context, [CGPoint(x: part.maxX, y: part.minY - 20), CGPoint(x: part.maxX, y: y - 24)], witness, white)
        arrow(context, from: CGPoint(x: part.midX, y: y), to: CGPoint(x: part.minX + 2, y: y), width: thin, head: head)
        arrow(context, from: CGPoint(x: part.midX, y: y), to: CGPoint(x: part.maxX - 2, y: y), width: thin, head: head)
        stroke(context, [CGPoint(x: part.minX - 20, y: part.minY), CGPoint(x: x - 24, y: part.minY)], witness, white)
        stroke(context, [CGPoint(x: part.minX - 20, y: part.maxY), CGPoint(x: x - 24, y: part.maxY)], witness, white)
        arrow(context, from: CGPoint(x: x, y: part.midY), to: CGPoint(x: x, y: part.minY + 2), width: thin, head: head)
        arrow(context, from: CGPoint(x: x, y: part.midY), to: CGPoint(x: x, y: part.maxY - 2), width: thin, head: head)
        tab(context, leftBottom: CGPoint(x: part.minX - partWidth / 2, y: part.minY - partWidth / 2), height: pixels >= 128 ? 88 : 92, digits: pixels >= 128)
    } else {
        // Too small for dimensions: the part and its tab, thick enough to survive whole pixels.
        let part = CGRect(x: 262, y: 370, width: 500, height: 400)
        let width: CGFloat = pixels <= 16 ? 88 : 62
        let outline = [CGPoint(x: part.minX, y: part.minY), CGPoint(x: part.maxX, y: part.minY), CGPoint(x: part.maxX, y: part.maxY), CGPoint(x: part.minX, y: part.maxY)]
        stroke(context, outline + [outline[0], outline[1]], width, white)
        tab(context, leftBottom: CGPoint(x: part.minX - width / 2, y: part.minY - width / 2), height: 140, digits: false)
    }

    context.saveGState()
    context.addPath(plate); context.setStrokeColor(color(0xFFFFFF, 0.14)); context.setLineWidth(3); context.strokePath()
    context.restoreGState()
}

// iconutil writes the container: PNG data under hand-picked type codes came out as noise at 16 and 32 px.
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, size) in files {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
    context.translateBy(x: 0, y: -1024)
    draw(context, pixels: size)
    let url = folder.appendingPathComponent("\(name).png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(name)") }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", folder.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: folder)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
