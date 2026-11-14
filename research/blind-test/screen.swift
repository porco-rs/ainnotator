import AppKit

// A fake order dashboard whose own UI contains things that look like annotations: a purple focus outline, a red
// hint arrow with text, numbered step chips, a yellow ring, a red validation border, a striped skeleton bar.
// Coordinates are pixels with the origin top-left.
let width = 2400, height = 1400
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> NSRect { NSRect(x: x, y: height - y - h, width: w, height: h) }
func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: Int, radius: CGFloat = 0) {
    color(hex).setFill()
    NSBezierPath(roundedRect: box(x, y, w, h), xRadius: radius, yRadius: radius).fill()
}
func stroke(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: Int, line: CGFloat, radius: CGFloat = 0) {
    color(hex).setStroke()
    let path = NSBezierPath(roundedRect: box(x, y, w, h), xRadius: radius, yRadius: radius)
    path.lineWidth = line
    path.stroke()
}
func text(_ string: String, _ x: Int, _ y: Int, _ size: CGFloat, _ hex: Int = 0x1F2430, weight: NSFont.Weight = .regular) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    (string as NSString).draw(at: NSPoint(x: CGFloat(x), y: CGFloat(height - y) - size * 1.2), withAttributes: [
        .font: font, .foregroundColor: color(hex),
    ])
}

fill(0, 0, width, height, 0xF4F5F7)

// Header
fill(0, 0, width, 120, 0xFFFFFF)
text("Acme Supply · Orders", 60, 34, 44, weight: .semibold)
fill(1380, 30, 420, 62, 0xEEF0F3, radius: 14)
text("Search …", 1410, 42, 30, 0x7A8190)
text("Messages", 1830, 44, 28, 0x444B59)
fill(1996, 24, 44, 44, 0xE5484D, radius: 22)                       // decoy: red badge
text("3", 2009, 28, 28, 0xFFFFFF, weight: .bold)
fill(2080, 28, 260, 64, 0x1F2430, radius: 14)
text("Export", 2160, 40, 30, 0xFFFFFF, weight: .medium)

// Decoy: red hint arrow with text, part of the product's onboarding
text("New: CSV export", 1700, 150, 30, 0xE5484D, weight: .medium)
color(0xE5484D).setStroke()
let hint = NSBezierPath()
hint.lineWidth = 5
hint.move(to: NSPoint(x: 1950, y: height - 172))
hint.line(to: NSPoint(x: 2130, y: height - 108))
hint.stroke()
color(0xE5484D).setFill()
let head = NSBezierPath()
head.move(to: NSPoint(x: 2146, y: height - 102))
head.line(to: NSPoint(x: 2112, y: height - 100))
head.line(to: NSPoint(x: 2124, y: height - 128))
head.close()
head.fill()

// Decoy: numbered step chips
let steps = ["Intake", "Review", "Shipping"]
for (index, name) in steps.enumerated() {
    let x = 70 + index * 300
    fill(x, 176, 58, 44, 0x0E9F9A, radius: 10)
    text("0\(index + 1)", x + 10, 181, 26, 0xFFFFFF, weight: .bold)
    text(name, x + 72, 180, 30, 0x444B59)
}

// Tiles
let tiles = [("Open", "12"), ("In progress", "5"), ("Shipped", "31"), ("Cancelled", "2")]
for (index, tile) in tiles.enumerated() {
    let x = 60 + index * 580
    fill(x, 280, 540, 240, 0xFFFFFF, radius: 22)
    text(tile.0, x + 36, 304, 32, 0x7A8190)
    text(tile.1, x + 36, 370, 96, weight: .bold)
}
stroke(640, 280, 540, 240, 0x8B5CF6, line: 6, radius: 22)           // decoy: purple focus outline on "In progress"
color(0xF5C842).setStroke()                                        // decoy: yellow ring from a product tour
let ring = NSBezierPath(ovalIn: box(1620, 312, 110, 110))
ring.lineWidth = 6
ring.stroke()
fill(1650, 342, 50, 50, 0xDDE1E7, radius: 25)

// Table
fill(60, 590, 2280, 660, 0xFFFFFF, radius: 22)
let columns = [(90, "No."), (320, "Customer"), (920, "Item"), (1500, "Qty"), (1800, "Total"), (2080, "Status")]
for column in columns { text(column.1, column.0, 612, 26, 0x7A8190, weight: .medium) }
let rows = [
    ("4711", "Sunrise Bakery", "Flour type 550, 25 kg", "12", "$418.80", "Paid"),
    ("4712", "Cafe Daybreak", "Roasted coffee, 1 kg", "-4", "–", "Open"),
    ("4713", "Hillside Farm Shop", "Jars 250 ml, 48 pcs", "6", "$214.20", "Paid"),
    ("4714", "Harbor Canteen", "Canola oil, 10 l", "3", "$89.70", "Open"),
    ("4715", "", "Sugar, 25 kg", "2", "$61.90", "Open"),
]
for (index, row) in rows.enumerated() {
    let y = 680 + index * 110
    fill(60, y - 10, 2280, 2, 0xE7E9ED)
    text(row.0, 90, y + 22, 30)
    text(row.1, 320, y + 22, 30)
    text(row.2, 920, y + 22, 30)
    text(row.3, 1520, y + 22, 30)
    text(row.4, 1800, y + 22, 30)
    if row.5 == "Paid" {
        stroke(2070, y + 14, 170, 52, 0x2FB171, line: 4, radius: 26)  // decoy: green outlined pill
        text(row.5, 2096, y + 22, 28, 0x2FB171, weight: .medium)
    } else {
        text(row.5, 2096, y + 22, 28, 0x7A8190)
    }
}
stroke(1490, 800, 200, 66, 0xE5484D, line: 5, radius: 10)           // decoy: red validation border on "-4"
// decoy: striped skeleton bar where a customer name is still loading
fill(320, 1136, 460, 44, 0x2A2F3A, radius: 8)
color(0x4A5060).setStroke()
for offset in stride(from: 0, to: 480, by: 22) {
    let line = NSBezierPath()
    line.lineWidth = 6
    line.move(to: NSPoint(x: 320 + offset, y: height - 1180))
    line.line(to: NSPoint(x: 320 + offset + 30, y: height - 1136))
    line.stroke()
}

text("Last updated 14 Nov 2026, 11:58 · 5 of 128 orders", 90, 1300, 20, 0x7A8190)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
