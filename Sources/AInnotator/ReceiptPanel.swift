import AICore
import AIRender
import AppKit

/// All values are captured at export time; the FILE row does not depend on the pasteboard.
struct ReceiptModel {
    /// What a terminal pastes: the absolute path of the card.
    var text: String
    var card: CGImage
    var width: Int
    var height: Int
    var pngPath: String
    var jsonPath: String
    var pngBytes: Int
    var jsonBytes: Int
    var marks: [Mark]
    var time: Date
}

/// The words of the receipt in one language. The row names TEXT, PNG, FILE and JSON are file kinds and stay as they are.
struct ReceiptCopy {
    var copied: String
    var noMarks: String
    var marks: (Int) -> String
    var path: String
    var card: String
    var consumers: String
    var new: String
    var newCapture: String
    var announcement: (Int) -> String

    static func forLanguage(_ language: Language) -> ReceiptCopy {
        switch language {
        case .en:
            ReceiptCopy(
                copied: "COPIED", noMarks: "(no marks)", marks: { "\($0) mark\($0 == 1 ? "" : "s")" }, path: "Path",
                card: "Card", consumers: "Agents", new: "New", newCapture: "New capture",
                announcement: { "Copied, \($0) mark\($0 == 1 ? "" : "s")" }
            )
        case .de:
            ReceiptCopy(
                copied: "KOPIERT", noMarks: "(keine Markierungen)", marks: { "\($0) Markierung\($0 == 1 ? "" : "en")" }, path: "Pfad",
                card: "Karte", consumers: "Agents", new: "Neu", newCapture: "Neue Aufnahme",
                announcement: { "Kopiert, \($0) Markierung\($0 == 1 ? "" : "en")" }
            )
        }
    }
}

/// The owner retains this object while the receipt is visible. The panel never takes the keyboard from the app the
/// user is about to paste into.
final class ReceiptPanel: NSObject {
    private static let visibleFor: TimeInterval = 4

    var onClose: (() -> Void)?
    private let panel: NSPanel
    private let content: ReceiptView
    private let model: ReceiptModel
    private let copy: ReceiptCopy
    private let onNew: () -> Void
    private var timer: Timer?
    private var closed = false

    init(model: ReceiptModel, language: Language = .en, onNew: @escaping () -> Void) {
        self.model = model
        self.onNew = onNew
        copy = .forLanguage(language)
        content = ReceiptView(model: model, language: language)
        panel = Self.makePanel(size: content.frame.size)
        super.init()
        panel.contentView = content
        content.onHover = { [weak self] in self?.timer?.invalidate() }
        content.onLeave = { [weak self] in self?.startTimer() }
        content.onNew = { [weak self] in
            // Held strongly: closing releases this object in the owner, and the call after it still has to happen.
            guard let self else { return }
            close()
            onNew()
        }
    }

    func show(on screen: NSScreen? = NSScreen.main) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - panel.frame.width - 10, y: visible.maxY - 10))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [.announcement: copy.announcement(model.marks.filter { $0.kind != .redact }.count), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        startTimer()
    }

    func close() {
        guard !closed else { return }
        closed = true
        timer?.invalidate()
        panel.orderOut(nil)
        onClose?()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.visibleFor, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    var windowNumber: Int { panel.windowNumber }
    func pressNew() { content.newButton?.performClick(nil) }

    private static func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}

class ReceiptFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The panel never becomes key, so the first click has to count.
private final class ReceiptButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shared with the offscreen developer command so the rendered output uses the actual panel content.
final class ReceiptView: ReceiptFlippedView {
    var onHover: (() -> Void)?
    var onLeave: (() -> Void)?
    var onNew: (() -> Void)?
    private(set) var newButton: NSButton?
    private var tracking: NSTrackingArea?

    init(model: ReceiptModel, language: Language = .en) {
        let copy = ReceiptCopy.forLanguage(language)
        let cardHeight = min(460.0, 320.0 * CGFloat(model.card.height) / CGFloat(model.card.width))
        let rowsTop = 32 + cardHeight + 8
        let total = rowsTop + 4 * 26 + 4 + 46
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: total))
        wantsLayer = true
        layer?.backgroundColor = Theme.oklch(0.15, 0.004, 250, alpha: 0.92)
        layer?.cornerRadius = 12
        layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        let dot = NSView(frame: NSRect(x: 12, y: 13, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = Theme.oklch(0.78, 0.17, 152)
        dot.layer?.cornerRadius = 3
        addSubview(dot)
        add(copy.copied, x: 26, y: 10, width: 170, size: 10, weight: .semibold, tracking: 0.1, color: .white)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        add(formatter.string(from: model.time), x: 245, y: 10, width: 83, size: 10, weight: .semibold, tracking: 0.04, right: true, color: Self.gray(0.55))
        let image = NSImageView(frame: NSRect(x: 10, y: 32, width: 320, height: cardHeight))
        image.image = NSImage(cgImage: model.card, size: NSSize(width: model.card.width, height: model.card.height))
        image.imageScaling = .scaleProportionallyUpOrDown
        image.wantsLayer = true
        image.layer?.cornerRadius = 7
        image.layer?.masksToBounds = true
        addSubview(image)
        let n = model.marks.filter { $0.kind != .redact }.count
        let count = n == 0 ? copy.noMarks : copy.marks(n)
        let tokenText = Geometry.tokenEstimate(width: Double(model.width), height: Double(model.height))
        let rows = [("TEXT", "\(copy.path) · \(count)", "\(model.text.utf8.count) B"), ("PNG", "\(copy.card) \(model.width)×\(model.height)", tokenText), ("FILE", model.pngPath, ""), ("JSON", model.jsonPath, copy.consumers)]
        for (index, row) in rows.enumerated() {
            let y = rowsTop + CGFloat(index) * 26
            // Regular rather than medium: AppKit renders this text heavier than its weight suggests.
            add(row.0, x: 12, y: y + 9, width: 44, size: 9, weight: .regular, tracking: 0.1, color: Self.gray(0.55))
            let detail = add(row.2, x: 66, y: y + 7, width: 262, size: 11, weight: .regular, color: Self.gray(0.60))
            detail.alignment = .right
            let detailWidth = row.2.isEmpty ? 0 : detail.intrinsicContentSize.width + 10
            add(row.1, x: 66, y: y + 7, width: 262 - detailWidth, size: 11, weight: .regular, color: NSColor(white: 0.9, alpha: 1))
            let line = NSView(frame: NSRect(x: 12, y: y + 25, width: 316, height: 1))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
            addSubview(line)
        }
        let buttonsY = rowsTop + 4 * 26 + 4 + 8
        // The only button, so it takes the whole row.
        let new = ReceiptButton(title: "", target: self, action: #selector(newPressed))
        style(new, title: copy.new, key: "⌥⇧A", frame: NSRect(x: 10, y: buttonsY, width: 320, height: 28), light: true)
        new.setAccessibilityLabel(copy.newCapture)
        newButton = new
    }
    required init?(coder: NSCoder) { nil }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseExited(with event: NSEvent) { onLeave?() }
    @objc private func newPressed() { onNew?() }
    private func style(_ button: NSButton, title: String, key: String, frame: NSRect, light: Bool) {
        button.frame = frame
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = light ? Theme.oklch(0.97, 0, 0) : NSColor.clear.cgColor
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = light ? 0 : 1
        button.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        let color = NSColor(cgColor: light ? Theme.oklch(0.14, 0.004, 250) : Theme.oklch(0.95, 0, 0)) ?? .white
        let styled = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: light ? .semibold : .medium), .foregroundColor: color,
        ])
        // An 8 pt gap before the key hint, as space behind the last letter.
        styled.addAttribute(.kern, value: 8, range: NSRange(location: styled.length - 1, length: 1))
        styled.append(NSAttributedString(string: key, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: color.withAlphaComponent(0.5),
        ]))
        button.attributedTitle = styled
        addSubview(button)
    }
    @discardableResult private func add(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat = 0, right: Bool = false, color: NSColor) -> NSTextField {
        let field = Self.field(text, x: x, y: y, width: width, size: size, weight: weight, tracking: tracking, right: right, color: color)
        addSubview(field)
        return field
    }
    static func field(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat, right: Bool, color: NSColor) -> NSTextField {
        let field = label(text, size: size, mono: true, color: color)
        field.font = .monospacedSystemFont(ofSize: size, weight: weight)
        if tracking != 0 {
            // An attributed value brings its own paragraph style, so the alignment has to travel inside it.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = right ? .right : .left
            paragraph.lineBreakMode = .byTruncatingTail
            field.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: size * tracking, .paragraphStyle: paragraph,
            ])
        }
        // NSTextField keeps its text 2 pt inside the frame on both sides; x and width here mean the text itself.
        field.frame = NSRect(x: x - 2, y: y, width: width + 4, height: 18)
        return field
    }
    private static func gray(_ lightness: Double) -> NSColor {
        NSColor(cgColor: Theme.oklch(lightness, 0.005, 250)) ?? .gray
    }
    static func label(_ text: String, size: CGFloat, mono: Bool, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = mono ? .monospacedSystemFont(ofSize: size, weight: .medium) : .systemFont(ofSize: size)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        return field
    }
}
