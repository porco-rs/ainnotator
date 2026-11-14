import AICore
import CoreText
import Foundation
import QuartzCore

/// CATextLayer always sets its text at the top; the chips want it centered in their 15 pt.
private final class ChipLayer: CATextLayer {
    override func draw(in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: 1.5)
        super.draw(in: context)
        context.restoreGState()
    }
}

public struct OverlayAccessibilityItem {
    public enum Role { case toolbar, radio, button, image }
    public var frame: CGRect
    public var role: Role
    public var name: String
    public var action: Event? = nil
    public var selected = false
}

/// The layer tree of one display. A pointer move only repositions layers; nothing is redrawn on the CPU.
@MainActor public final class OverlayScene {
    public let root = CALayer()

    private let image = CALayer()
    private let dims = (0..<4).map { _ in CALayer() }
    private let frame = CALayer()
    private let crossX = CALayer()
    private let crossY = CALayer()
    private let chip = ChipLayer()
    private let sizeChip = ChipLayer()
    private let preview = CAShapeLayer()
    private let previewHatch = CALayer()
    private let marksRoot = CALayer()
    private let hud: OverlayHUD
    private let corners = CAShapeLayer()
    private let dragChip = ChipLayer()

    private var size: CGSize
    private var scale: CGFloat
    private let copy: OverlayCopy
    private var drawnMarks: [Mark]?
    private var drawnActive: Int?
    private var drawnNoteMode = false
    public private(set) var wantsArrowCursor = false
    public private(set) var helpIsOpen = false
    private var accessibilityState: CaptureState?
    public var accessibilityMarksDidChange: (() -> Void)?
    public var increasedContrast: Bool = false {
        didSet {
            hud.increasedContrast = increasedContrast
            frame.borderColor = Theme.srgb(0xffffff, alpha: increasedContrast ? 1 : 0.55)
            for line in [crossX, crossY] { line.backgroundColor = Theme.srgb(0xffffff, alpha: increasedContrast ? 1 : 0.28) }
            if let state = accessibilityState { apply(state, isActive: true) }
        }
    }

    public var accessibilityItems: [OverlayAccessibilityItem] {
        guard let state = accessibilityState else { return [] }
        var items = [OverlayAccessibilityItem(frame: hud.accessibilityFrame, role: .toolbar, name: copy.toolbar)]
        items += hud.accessibilityItems
        if state.mode == .annotate {
            var number = 0
            for mark in state.marks where mark.kind != .redact {
                number += 1
                var rect = MarkPath.rect(for: mark, mapping: fullMapping)
                if mark.kind == .arrow {
                    rect = CGRect(x: min(mark.x0, mark.x1) * size.width, y: min(mark.y0, mark.y1) * size.height, width: abs(mark.x1 - mark.x0) * size.width, height: abs(mark.y1 - mark.y0) * size.height)
                }
                if rect.width < 22 { rect.size.width = 22 }
                if rect.height < 18 { rect.size.height = 18 }
                items.append(.init(frame: rect, role: .image, name: copy.markName(number: number, intent: mark.intent, note: mark.note)))
            }
        }
        return items
    }

    /// `topInset` is the height of the strip a camera housing hides at the top of the display, zero elsewhere.
    public init(size: CGSize, scale: CGFloat, language: Language = .en, topInset: CGFloat = 0) {
        self.size = size
        self.scale = scale
        self.copy = .forLanguage(language)
        self.hud = OverlayHUD(width: size.width, scale: scale, language: language, topInset: topInset)
        root.frame = CGRect(origin: .zero, size: size)
        root.isGeometryFlipped = true
        root.backgroundColor = Theme.srgb(0x000000)
        root.actions = Self.noActions

        image.frame = root.bounds
        image.contentsGravity = .resize
        image.actions = Self.noActions
        root.addSublayer(image)

        for dim in dims {
            dim.backgroundColor = Theme.dim
            dim.actions = Self.noActions
            root.addSublayer(dim)
        }

        frame.borderColor = Theme.srgb(0xFFFFFF, alpha: 0.55)
        frame.borderWidth = 1
        frame.actions = Self.noActions
        root.addSublayer(frame)

        root.addSublayer(marksRoot)
        marksRoot.actions = Self.noActions

        previewHatch.masksToBounds = true; previewHatch.backgroundColor = Theme.redactA; previewHatch.actions = Self.noActions
        let hatch = CAShapeLayer(), hatchPath = CGMutablePath()
        var hx = -size.height
        while hx < size.width {
            hatchPath.move(to: CGPoint(x: hx, y: 0)); hatchPath.addLine(to: CGPoint(x: hx + 6, y: 0))
            hatchPath.addLine(to: CGPoint(x: hx + size.height + 6, y: size.height)); hatchPath.addLine(to: CGPoint(x: hx + size.height, y: size.height)); hatchPath.closeSubpath()
            hx += 12
        }
        hatch.path = hatchPath; hatch.fillColor = Theme.redactB; previewHatch.addSublayer(hatch); root.addSublayer(previewHatch)
        preview.fillColor = nil
        preview.lineWidth = 1.5
        preview.lineDashPattern = [4, 3]
        preview.actions = Self.noActions
        root.addSublayer(preview)

        for line in [crossX, crossY] {
            line.backgroundColor = Theme.srgb(0xFFFFFF, alpha: 0.28)
            line.actions = Self.noActions
            root.addSublayer(line)
        }

        for label in [chip, sizeChip] {
            configure(label, font: Theme.mono(10), size: 10, color: Theme.hudText)
            label.alignmentMode = .center
            label.backgroundColor = Theme.srgb(0x04060A, alpha: 0.82)
            label.cornerRadius = 3
            root.addSublayer(label)
        }

        corners.strokeColor = Theme.srgb(0xffffff); corners.fillColor = nil; corners.lineWidth = 2
        corners.actions = Self.noActions; root.addSublayer(corners)
        configure(dragChip, font: Theme.mono(10), size: 10, color: Theme.hudText)
        dragChip.backgroundColor = Theme.srgb(0x04060A, alpha: 0.82); dragChip.cornerRadius = 3; root.addSublayer(dragChip)
        root.addSublayer(hud.root)
    }

    /// The platform uses this for the arrow cursor and HUD event routing.
    public func containsHUD(_ point: CGPoint) -> Bool { !hud.root.isHidden && hud.contains(point) }
    public func action(at point: CGPoint) -> Event? { hud.action(at: point) }

    /// Accepts an IOSurface (zero copy) or a CGImage (offscreen rendering).
    public func setImage(_ contents: Any?) {
        image.contents = contents
    }

    /// Updates everything from the state. `isActive` is false for the displays the area does not lie on.
    public func apply(_ state: CaptureState, isActive: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        helpIsOpen = state.help
        accessibilityState = isActive && (state.mode == .select || state.mode == .annotate) ? state : nil
        let visible = state.mode == .select || state.mode == .annotate
        for layer in dims + [frame, crossX, crossY, chip, sizeChip, preview, previewHatch, marksRoot, corners, dragChip, hud.root] as [CALayer] {
            layer.isHidden = !visible
        }
        guard visible else { wantsArrowCursor = false; return }

        let area = visibleArea(state, isActive: isActive)
        layoutDims(around: area, opacity: state.mode == .select ? 0.42 : 0.62)

        frame.isHidden = area == nil
        if let area { frame.frame = area }
        corners.isHidden = state.mode != .annotate || area == nil || !isActive
        if let area, !corners.isHidden {
            let p = CGMutablePath()
            for (x, y, dx, dy) in [(area.minX, area.minY, 1.0, 1.0), (area.maxX, area.minY, -1.0, 1.0), (area.minX, area.maxY, 1.0, -1.0), (area.maxX, area.maxY, -1.0, -1.0)] {
                p.move(to: CGPoint(x: x + dx * 14, y: y)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + dy * 14))
            }
            corners.path = p
        }
        layoutCrosshair(state, isActive: isActive)
        layoutSizeChip(area, state: state)
        layoutPreview(state, isActive: isActive)
        layoutMarks(state, isActive: isActive)
        hud.apply(state, isActive: isActive)
        wantsArrowCursor = isActive && state.cursor.map { hud.contains(CGPoint(x: $0.x * size.width, y: $0.y * size.height)) } == true
    }

    private func visibleArea(_ state: CaptureState, isActive: Bool) -> CGRect? {
        guard isActive else { return nil }
        if state.mode == .select, let drag = state.drag {
            return rect(from: drag)
        }
        guard state.mode == .annotate, let sel = state.sel else { return nil }
        return CGRect(x: sel.x * size.width, y: sel.y * size.height, width: sel.w * size.width, height: sel.h * size.height)
    }

    private func rect(from drag: Drag) -> CGRect {
        CGRect(
            x: min(drag.x0, drag.x1) * size.width, y: min(drag.y0, drag.y1) * size.height,
            width: abs(drag.x1 - drag.x0) * size.width, height: abs(drag.y1 - drag.y0) * size.height
        )
    }

    /// Four solid layers instead of a mask: changing their frames costs next to nothing.
    private func layoutDims(around area: CGRect?, opacity: Float) {
        for dim in dims { dim.opacity = opacity }
        guard let area else {
            dims[0].frame = root.bounds
            for dim in dims.dropFirst() { dim.frame = .zero }
            return
        }
        dims[0].frame = CGRect(x: 0, y: 0, width: size.width, height: area.minY)
        dims[1].frame = CGRect(x: 0, y: area.maxY, width: size.width, height: size.height - area.maxY)
        dims[2].frame = CGRect(x: 0, y: area.minY, width: area.minX, height: area.height)
        dims[3].frame = CGRect(x: area.maxX, y: area.minY, width: size.width - area.maxX, height: area.height)
    }

    private func layoutCrosshair(_ state: CaptureState, isActive: Bool) {
        // Hairlines belong to choosing the area only; marking up uses the crosshair cursor.
        guard isActive, state.mode == .select, state.drag == nil, let cursor = state.cursor else {
            crossX.isHidden = true
            crossY.isHidden = true
            chip.isHidden = true
            return
        }
        let point = CGPoint(x: cursor.x * size.width, y: cursor.y * size.height)
        crossX.frame = CGRect(x: 0, y: point.y.rounded(), width: size.width, height: 1)
        crossY.frame = CGRect(x: point.x.rounded(), y: 0, width: 1, height: size.height)

        chip.isHidden = state.mode != .select
        if !chip.isHidden {
            let px = Int((cursor.x * Double(state.stage.pixelWidth)).rounded())
            let py = Int((cursor.y * Double(state.stage.pixelHeight)).rounded())
            let text = String(format: "%04d %04d", px, py)
            let width = chipWidth(text, layer: chip)
            chip.frame = CGRect(x: point.x + 12, y: point.y + 12, width: width, height: 15)
        }
    }

    private func layoutSizeChip(_ area: CGRect?, state: CaptureState) {
        guard state.mode == .annotate, let area else {
            sizeChip.isHidden = true
            return
        }
        let width = Int((area.width * Double(state.stage.pixelWidth) / size.width).rounded())
        let height = Int((area.height * Double(state.stage.pixelHeight) / size.height).rounded())
        let text = "\(width) × \(height)"
        let chipSize = chipWidth(text, layer: sizeChip)
        sizeChip.frame = CGRect(x: area.maxX - 8 - chipSize, y: area.maxY - 8 - 15, width: chipSize, height: 15)
    }

    private func layoutPreview(_ state: CaptureState, isActive: Bool) {
        guard isActive, let drag = state.drag, drag.movedMark == nil else {
            preview.isHidden = true; previewHatch.isHidden = true; dragChip.isHidden = true
            return
        }
        preview.isHidden = false; dragChip.isHidden = false
        let tool = state.mode == .select ? Tool.box : state.tool
        let kind: MarkKind = switch tool {
        case .box, .crop: .box
        case .oval: .oval
        case .arrow: .arrow
        case .highlight: .highlight
        case .redact: .redact
        }
        let mark = Mark(
            id: 0, kind: kind, intent: state.intent,
            x: min(drag.x0, drag.x1), y: min(drag.y0, drag.y1), w: abs(drag.x1 - drag.x0), h: abs(drag.y1 - drag.y0),
            x0: drag.x0, y0: drag.y0, x1: drag.x1, y1: drag.y1
        )
        preview.path = MarkPath.path(for: mark, mapping: fullMapping, inset: (kind == .box || kind == .oval) ? (state.mode == .select || state.tool == .crop ? 0.5 : 0.75) : 0)
        let selecting = state.mode == .select || state.tool == .crop
        preview.strokeColor = selecting ? Theme.srgb(0xffffff) : state.tool == .redact ? Theme.oklch(0.8, 0, 0) : Theme.intent(state.intent)
        preview.lineWidth = selecting ? 1 : state.tool == .arrow ? 2 : 1.5
        preview.lineDashPattern = selecting || state.tool == .arrow ? nil : [4, 3]
        preview.fillColor = state.tool == .highlight && !selecting ? Theme.intent(state.intent, alpha: state.intent == .question ? 0.36 : 0.30) : state.tool == .arrow && !selecting ? Theme.intent(state.intent) : nil
        let r = rect(from: drag)
        previewHatch.isHidden = selecting || state.tool != .redact
        if !previewHatch.isHidden { previewHatch.frame = r }
        let text: String
        if state.tool == .arrow && !selecting {
            let dx = (drag.x1 - drag.x0) * Double(state.stage.pixelWidth), dy = (drag.y1 - drag.y0) * Double(state.stage.pixelHeight)
            let angle = (atan2(-dy, dx) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            text = "\(Int(hypot(dx, dy).rounded())) px · \(Int(angle.rounded()))°"
            dragChip.frame = CGRect(x: drag.x1 * size.width + 12, y: drag.y1 * size.height + 8, width: CGFloat(text.count) * 7 + 12, height: 15)
        } else {
            text = "\(Int((abs(drag.x1 - drag.x0) * Double(state.stage.pixelWidth)).rounded())) × \(Int((abs(drag.y1 - drag.y0) * Double(state.stage.pixelHeight)).rounded()))"
            dragChip.frame = CGRect(x: r.maxX - CGFloat(text.count) * 7 - 12, y: r.maxY + 6, width: CGFloat(text.count) * 7 + 12, height: 15)
        }
        setText(" " + text, on: dragChip)
    }

    private var fullMapping: StageMapping {
        StageMapping(crop: .full, width: size.width, height: size.height)
    }

    /// Marks change rarely compared to the pointer, so this rebuilds only when they did.
    private func layoutMarks(_ state: CaptureState, isActive: Bool) {
        marksRoot.isHidden = !isActive || state.mode != .annotate
        guard !marksRoot.isHidden else { return }
        if let drag = state.drag, let original = drag.movedMark, let layer = marksRoot.sublayers?.first(where: { $0.name == String(original.id) }), drawnActive == state.active {
            layer.setAffineTransform(CGAffineTransform(translationX: (drag.x1 - drag.x0) * size.width, y: (drag.y1 - drag.y0) * size.height))
            return
        }
        guard drawnMarks != state.marks || drawnActive != state.active || drawnNoteMode != state.noteMode else { return }
        drawnMarks = state.marks
        drawnActive = state.active
        drawnNoteMode = state.noteMode
        accessibilityMarksDidChange?()

        marksRoot.sublayers = nil
        var number = 0
        let numbered = state.marks.filter { $0.kind != .redact }
        let positions = Geometry.spread(numbered.map { NormPoint(x: $0.kind == .arrow ? $0.x0 : $0.x, y: $0.kind == .arrow ? $0.y0 : $0.y) }, width: size.width, height: size.height, step: 26)
        for mark in state.marks {
            let group = CALayer(); group.name = String(mark.id); group.actions = Self.noActions; marksRoot.addSublayer(group)
            if mark.kind == .redact {
                group.addSublayer(redactionLayer(for: mark))
                continue
            }
            number += 1
            group.addSublayer(shapeLayer(for: mark))
            let badge = badgeLayer(for: mark, number: number)
            let origin = positions[number - 1]
            let shift = origin.x * size.width - (mark.kind == .arrow ? mark.x0 : mark.x) * size.width
            badge.frame.origin.x += shift
            if (mark.kind == .arrow || mark.kind == .pin) && (state.noteMode && state.active == mark.id || !mark.note.isEmpty) {
                let labelText = state.noteMode && state.active == mark.id && mark.note.isEmpty ? "▍\(copy.intentNames[mark.intent.rawValue - 1]) · \(copy.typeNote)" : mark.note + (state.noteMode && state.active == mark.id ? "▍" : "")
                badge.frame.origin.x -= (Self.noteWidth(labelText) + 4) / 2
            }
            if state.active == mark.id { badge.borderWidth = 1.5; badge.borderColor = Theme.srgb(0xffffff) }
            group.addSublayer(badge)
            if state.active == mark.id && !state.noteMode {
                let outline = CAShapeLayer(); outline.path = MarkPath.path(for: mark, mapping: fullMapping)
                outline.fillColor = nil; outline.strokeColor = Theme.srgb(0xffffff, alpha: 0.7); outline.lineWidth = 1; outline.lineDashPattern = [4, 3]
                if mark.kind != .arrow && mark.kind != .pin {
                    let box = MarkPath.rect(for: mark, mapping: fullMapping).insetBy(dx: -4, dy: -4)
                    let path = CGMutablePath(); if mark.kind == .oval { path.addEllipse(in: box) } else { path.addRect(box) }; outline.path = path
                }
                group.addSublayer(outline)
            }
            let typing = state.noteMode && state.active == mark.id
            if typing || !mark.note.isEmpty {
                group.addSublayer(noteLayer(for: mark, typing: typing, next: badge.frame))
            }
        }
    }

    private func shapeLayer(for mark: Mark) -> CALayer {
        let layer = CAShapeLayer()
        layer.actions = Self.noActions
        layer.path = MarkPath.path(for: mark, mapping: fullMapping, inset: (mark.kind == .box || mark.kind == .oval) ? 1 : 0)
        if mark.kind == .highlight {
            layer.fillColor = Theme.intent(mark.intent, alpha: mark.intent == .question ? 0.36 : 0.30)
        } else {
            layer.fillColor = mark.kind == .arrow ? Theme.intent(mark.intent) : nil
            layer.strokeColor = Theme.intent(mark.intent)
            layer.lineWidth = 2
        }
        return layer
    }

    private func redactionLayer(for mark: Mark) -> CALayer {
        let layer = CALayer()
        layer.actions = Self.noActions
        layer.frame = MarkPath.rect(for: mark, mapping: fullMapping)
        layer.backgroundColor = Theme.redactA
        layer.masksToBounds = true
        let stripes = CAShapeLayer(), path = CGMutablePath()
        let width = layer.frame.width, height = layer.frame.height
        var x = -height
        while x < width {
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x + 6, y: 0))
            path.addLine(to: CGPoint(x: x + height + 6, y: height)); path.addLine(to: CGPoint(x: x + height, y: height)); path.closeSubpath()
            x += 12
        }
        stripes.path = path; stripes.fillColor = Theme.redactB; layer.addSublayer(stripes)
        return layer
    }

    private func badgeLayer(for mark: Mark, number: Int) -> CALayer {
        let badge = CALayer()
        badge.backgroundColor = Theme.intent(mark.intent)
        badge.cornerRadius = mark.kind == .pin ? 9 : 3
        let content = CATextLayer()
        configure(content, font: Theme.mono(11, semibold: true), size: 11, color: Theme.onIntent(mark.intent))
        content.alignmentMode = .center
        content.frame = CGRect(x: 0, y: 2, width: 22, height: 16)
        setText(String(format: "%02d", number), on: content)
        badge.addSublayer(content)
        let anchor = mark.kind == .arrow
            ? CGPoint(x: mark.x0 * size.width, y: mark.y0 * size.height)
            : CGPoint(x: mark.x * size.width, y: mark.y * size.height)
        switch mark.kind {
        case .arrow, .pin:
            badge.frame = CGRect(x: anchor.x - 11, y: anchor.y - 9, width: 22, height: 18)
        default:
            badge.frame = CGRect(x: anchor.x, y: anchor.y - 18, width: 22, height: 18)
        }
        return badge
    }

    private func noteLayer(for mark: Mark, typing: Bool, next badge: CGRect) -> CALayer {
        let label = CALayer()
        let text: String
        if typing {
            text = mark.note.isEmpty ? "▍\(copy.intentNames[mark.intent.rawValue - 1]) · \(copy.typeNote)" : mark.note + "▍"
        } else {
            text = mark.note
        }
        label.backgroundColor = Theme.srgb(0x080A0E, alpha: 0.88)
        label.borderColor = Theme.intent(mark.intent)
        label.borderWidth = 1
        label.cornerRadius = 3
        let width = Self.noteWidth(text)
        label.frame = CGRect(x: badge.maxX + 4, y: badge.minY, width: width, height: 18)
        let content = CATextLayer()
        configure(content, font: Theme.sans(12), size: 12, color: typing && mark.note.isEmpty ? Theme.hudMuted : Theme.hudText)
        content.frame = CGRect(x: 7, y: 2, width: max(0, width - 14), height: 16)
        setText(text, on: content)
        label.addSublayer(content)
        return label
    }

    /// The digits are monospaced, so the width changes only with the number of characters; this runs on pointer moves.
    private func chipWidth(_ text: String, layer: CATextLayer) -> CGFloat {
        let previous = (layer.string as? NSAttributedString)?.string
        guard previous != text else { return layer.frame.width }
        let value = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): Theme.mono(10), .init(kCTForegroundColorAttributeName as String): Theme.hudText, .init(kCTKernAttributeName as String): 0.4])
        layer.string = value
        if previous?.count == text.count, layer.frame.width > 0 { return layer.frame.width }
        return ceil(CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(value), nil, nil, nil))) + 12
    }

    private static func noteWidth(_ text: String) -> CGFloat {
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): Theme.sans(12)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return min(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + 14, 520)
    }

    private func configure(_ label: CATextLayer, font: CTFont, size: CGFloat, color: CGColor) {
        label.font = font
        label.fontSize = size
        label.foregroundColor = color
        label.contentsScale = scale
        label.actions = Self.noActions
        label.isWrapped = false
        label.truncationMode = .end
    }

    /// Text is only set when it changed: rasterizing a label is the one expensive thing here.
    private func setText(_ text: String, on label: CATextLayer) {
        if (label.string as? String) != text { label.string = text }
    }

    private static let noActions: [String: any CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "hidden": NSNull(), "opacity": NSNull(),
        "sublayers": NSNull(), "path": NSNull(), "backgroundColor": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull(),
    ]
}
