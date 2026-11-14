import AppKit

// The invented screen every README image is captured from: a browser on a small desktop, showing the checkout of a
// made-up plant shop. Nothing here comes from a real screen. Points with the origin top-left, rendered at 2x.
//
//   swiftc -O -o screen screen.swift && ./screen screen.png
//
// The page carries a few things that look like annotations but belong to the app (a red "Only 2 left" pill, a
// "-10%" chip, a blue focus ring), so the card's header line has something to tell apart.

let width = 1024.0, height = 640.0, scale = 2.0
let context = CGContext(
    data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
)!
context.translateBy(x: 0, y: height * scale)
context.scaleBy(x: scale, y: -scale)
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func fill(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ hex: Int, radius: Double = 0, alpha: CGFloat = 1) {
    color(hex, alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func stroke(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ hex: Int, line: Double = 1, radius: Double = 0, alpha: CGFloat = 1) {
    color(hex, alpha).setStroke()
    let path = NSBezierPath(roundedRect: NSRect(x: x + line / 2, y: y + line / 2, width: w - line, height: h - line), xRadius: radius, yRadius: radius)
    path.lineWidth = line
    path.stroke()
}
func font(_ size: Double, _ weight: NSFont.Weight = .regular, design: NSFontDescriptor.SystemDesign = .default) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}
@discardableResult
func text(_ string: String, _ x: Double, _ y: Double, _ font: NSFont, _ hex: Int, alignRight: Bool = false, kern: Double = 0) -> Double {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(hex), .kern: kern]
    let size = (string as NSString).size(withAttributes: attributes)
    (string as NSString).draw(at: NSPoint(x: alignRight ? x - size.width : x, y: y), withAttributes: attributes)
    return size.width
}
func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ hex: Int, width: Double = 1) {
    color(hex).setStroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x0, y: y0))
    path.line(to: NSPoint(x: x1, y: y1))
    path.lineWidth = width
    path.stroke()
}

// Desktop
let wallpaper = NSGradient(colors: [color(0x1B2433), color(0x0D1118)])!
wallpaper.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)
fill(0, 0, width, 22, 0x0B0E13, alpha: 0.75)
text("Browser", 16, 4, font(12.5, .semibold), 0xE7EAF0)
var menuX = 82.0
for item in ["File", "Edit", "View", "History", "Window"] { menuX += text(item, menuX, 4, font(12.5), 0xC9CED8) + 18 }
text("Thu 10:24", width - 14, 4, font(12.5, .medium), 0xE7EAF0, alignRight: true)
// The AInnotator menu bar icon (StatusMenu.icon): four corner angles and a dot.
do {
    let x = width - 104.0, y = 5.0, w = 16.0, h = 12.0, arm = 4.0
    color(0xE7EAF0).setStroke()
    let path = NSBezierPath()
    for (cx, cy, dx, dy) in [(x, y, arm, arm), (x + w, y, -arm, arm), (x, y + h, arm, -arm), (x + w, y + h, -arm, -arm)] {
        path.move(to: NSPoint(x: cx + dx, y: cy)); path.line(to: NSPoint(x: cx, y: cy)); path.line(to: NSPoint(x: cx, y: cy + dy))
    }
    path.lineWidth = 1.2
    path.stroke()
    color(0xE7EAF0).setFill()
    NSBezierPath(ovalIn: NSRect(x: x + w / 2 - 1.5, y: y + h / 2 - 1.5, width: 3, height: 3)).fill()
}

// Browser window
let win = (x: 92.0, y: 76.0, w: 840.0, h: 548.0)
do {
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.55)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    fill(win.x, win.y, win.w, win.h, 0xF7F6F2, radius: 11)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: NSRect(x: win.x, y: win.y, width: win.w, height: win.h), xRadius: 11, yRadius: 11).addClip()
    fill(win.x, win.y, win.w, 40, 0xE9E8E3)
    line(win.x, win.y + 40, win.x + win.w, win.y + 40, 0xD6D4CD)
    for (index, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        color(hex).setFill()
        NSBezierPath(ovalIn: NSRect(x: win.x + 14 + Double(index) * 20, y: win.y + 14, width: 12, height: 12)).fill()
    }
    // Address field with a small lock
    fill(win.x + 250, win.y + 8, 340, 24, 0xF7F6F2, radius: 7)
    color(0x7A7F78).setStroke()
    let lock = NSBezierPath(roundedRect: NSRect(x: win.x + 352, y: win.y + 17, width: 8, height: 7), xRadius: 1.5, yRadius: 1.5)
    lock.lineWidth = 1.2
    lock.stroke()
    let shackle = NSBezierPath()
    shackle.appendArc(withCenter: NSPoint(x: win.x + 356, y: win.y + 17), radius: 2.6, startAngle: 180, endAngle: 0, clockwise: false)
    shackle.lineWidth = 1.2
    shackle.stroke()
    text("tinyplant.example/checkout", win.x + 366, win.y + 12, font(12.5), 0x3C423C)
    NSGraphicsContext.restoreGraphicsState()
}

// Page
let page = (x: win.x, y: win.y + 41)
let ink = 0x1E2420, muted = 0x6E736C, rule = 0xE4E2DA, brand = 0x2F7D4F
text("Tiny Plant Co.", page.x + 32, page.y + 16, font(19, .bold, design: .serif), brand)
var navX = page.x + win.w - 32
for item in ["Cart (3)", "Care guides", "Shop"] {
    navX -= text(item, navX, page.y + 20, font(13, .medium), item.hasPrefix("Cart") ? ink : muted, alignRight: true) + 22
}
line(page.x, page.y + 56, page.x + win.w, page.y + 56, rule)

// Left column: checkout form
let left = page.x + 32
text("Checkout", left, page.y + 70, font(25, .bold), ink)
func label(_ string: String, _ y: Double) { text(string.uppercased(), left, y, font(10.5, .semibold), muted, kern: 0.8) }

label("Contact", page.y + 112)
fill(left, page.y + 130, 420, 38, 0xFFFFFF, radius: 8)
stroke(left - 3, page.y + 127, 426, 44, 0x4C8DF6, line: 2.5, radius: 10, alpha: 0.55)   // browser focus ring
stroke(left, page.y + 130, 420, 38, 0x4C8DF6, line: 1, radius: 8)
text("sam.rivera@example.com", left + 14, page.y + 139, font(14), ink)

label("Delivery", page.y + 196)
for (index, option) in [("Standard · 3–5 days", "Free", true), ("Express · tomorrow", "$6.00", false)].enumerated() {
    let y = page.y + 214 + Double(index) * 42
    fill(left, y, 420, 36, 0xFFFFFF, radius: 8)
    stroke(left, y, 420, 36, option.2 ? brand : rule, line: option.2 ? 1.5 : 1, radius: 8)
    stroke(left + 13, y + 11, 14, 14, option.2 ? brand : 0xB9BCB4, line: 1.5, radius: 7)
    if option.2 { fill(left + 17, y + 15, 6, 6, brand, radius: 3) }
    text(option.0, left + 38, y + 9, font(13.5), ink)
    text(option.1, left + 404, y + 9, font(13.5, .medium), ink, alignRight: true)
}

label("Coupon", page.y + 324)
fill(left, page.y + 342, 190, 38, 0xFFFFFF, radius: 8)
stroke(left, page.y + 342, 190, 38, rule, radius: 8)
text("SPRING10", left + 14, page.y + 352, font(14, .medium), ink, kern: 0.6)
text("✓ applied", left + 202, page.y + 353, font(12.5), brand)
text("Apply", left + 420, page.y + 352, font(13.5, .semibold), brand, alignRight: true)

fill(left, page.y + 404, 420, 48, brand, radius: 10)
text("Pay $0.00", left + 210 - 38, page.y + 417, font(16, .semibold), 0xFFFFFF)
text("By placing your order you agree to our plant care terms.", left, page.y + 466, font(11), muted)

// Right column: order summary
let card = (x: page.x + 488, y: page.y + 70, w: 320.0, h: 384.0)
fill(card.x, card.y, card.w, card.h, 0xFFFFFF, radius: 14)
stroke(card.x, card.y, card.w, card.h, rule, radius: 14)
text("Order summary", card.x + 20, card.y + 18, font(15, .semibold), ink)

func thumbnail(_ x: Double, _ y: Double, _ kind: Int) {
    fill(x, y, 40, 40, [0xE6F0E4, 0xF5E7DD, 0xEDEAF6][kind], radius: 9)
    switch kind {
    case 0: // leaf
        color(0x3E8E5C).setFill()
        let leaf = NSBezierPath()
        leaf.move(to: NSPoint(x: x + 12, y: y + 31))
        leaf.curve(to: NSPoint(x: x + 30, y: y + 9), controlPoint1: NSPoint(x: x + 9, y: y + 16), controlPoint2: NSPoint(x: x + 20, y: y + 8))
        leaf.curve(to: NSPoint(x: x + 12, y: y + 31), controlPoint1: NSPoint(x: x + 31, y: y + 22), controlPoint2: NSPoint(x: x + 22, y: y + 30))
        leaf.fill()
        line(x + 12, y + 31, x + 24, y + 17, 0xE6F0E4, width: 1.4)
    case 1: // pot
        color(0xC8693F).setFill()
        let pot = NSBezierPath()
        pot.move(to: NSPoint(x: x + 11, y: y + 15)); pot.line(to: NSPoint(x: x + 29, y: y + 15))
        pot.line(to: NSPoint(x: x + 26, y: y + 31)); pot.line(to: NSPoint(x: x + 14, y: y + 31)); pot.close()
        pot.fill()
        fill(x + 9, y + 11, 22, 5, 0xB55A33, radius: 1.5)
    default: // bottle of plant food
        fill(x + 14, y + 14, 12, 18, 0x7B68C9, radius: 3)
        fill(x + 17, y + 9, 6, 6, 0x5B4BA6, radius: 1.5)
        fill(x + 16, y + 20, 8, 6, 0xEDEAF6, radius: 1)
    }
}
let items = [("Monstera, small", "$24.00"), ("Terracotta pot", "$18.00"), ("Plant food", "$9.50")]
for (index, item) in items.enumerated() {
    let y = card.y + 54 + Double(index) * 58
    thumbnail(card.x + 20, y, index)
    text(item.0, card.x + 72, y + 3, font(13.5, .medium), ink)
    text(item.1, card.x + card.w - 20, y + 3, font(13.5), ink, alignRight: true)
    if index == 0 {
        fill(card.x + 72, y + 22, 76, 17, 0xE5484D, radius: 8.5)
        text("Only 2 left", card.x + 80, y + 23.5, font(10.5, .semibold), 0xFFFFFF)
    } else {
        text(index == 1 ? "Sand, 14 cm" : "250 ml", card.x + 72, y + 22, font(11.5), muted)
    }
}
line(card.x + 20, card.y + 234, card.x + card.w - 20, card.y + 234, rule)
let rows: [(String, String, Bool)] = [("Subtotal", "$51.50", false), ("SPRING10", "−$5.15", true), ("Shipping", "Free", false)]
for (index, row) in rows.enumerated() {
    let y = card.y + 248 + Double(index) * 26
    let w = text(row.0, card.x + 20, y, font(13), row.2 ? brand : muted)
    if row.2 {
        fill(card.x + 28 + w, y + 1, 36, 16, 0x0E9F9A, radius: 4)
        text("−10%", card.x + 32 + w, y + 2, font(10.5, .bold), 0xFFFFFF)
    }
    text(row.1, card.x + card.w - 20, y, font(13), row.2 ? brand : ink, alignRight: true)
}
line(card.x + 20, card.y + 332, card.x + card.w - 20, card.y + 332, rule)
text("Total", card.x + 20, card.y + 346, font(16, .semibold), ink)
text("$0.00", card.x + card.w - 20, card.y + 344, font(19, .bold), ink, alignRight: true)

NSGraphicsContext.current = nil
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(CommandLine.arguments[1])") }
