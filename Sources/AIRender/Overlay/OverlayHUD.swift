import AICore
import CoreText
import QuartzCore

/// Persistent HUD layers. Layout and text are updated only when the displayed state changes.
@MainActor final class OverlayHUD {
    let root = CALayer()
    private let background = CALayer(), modeDot = CALayer(), mode = CATextLayer(), hint = CATextLayer()
    /// The hint line lies on whatever the screen shows, so it gets a ground of its own.
    private let hintBackground = CALayer()
    private let intentButtons = Intent.allCases.map { _ in CALayer() }
    private let intentDots = Intent.allCases.map { _ in CALayer() }
    private let intentLabels = Intent.allCases.map { _ in CATextLayer() }
    private let separators = (0..<3).map { _ in CALayer() }
    private let toolButtons = Tool.allCases.map { _ in CALayer() }
    private let toolIcons = Tool.allCases.map { _ in CAShapeLayer() }
    private let toolLabels = Tool.allCases.map { _ in CATextLayer() }
    private let readout = CATextLayer(), helpButton = CALayer(), helpLabel = CATextLayer()
    private let copyButton = CALayer(), copyLabel = CATextLayer()
    private let helpPanel = CALayer()
    private var hitAreas: [(CGRect, Event)] = []
    private(set) var accessibilityItems: [OverlayAccessibilityItem] = []
    var increasedContrast = false { didSet { if oldValue != increasedContrast { previous = nil } } }
    private var backgroundFrame = CGRect.zero
    private var panelFrame = CGRect.zero
    private struct DisplayKey: Equatable {
        var mode: Mode; var noteMode: Bool; var hasActive: Bool; var intent: Intent; var tool: Tool
        var selection: NormRect?; var stage: Stage; var count: Int; var help: Bool
    }
    private var previous: DisplayKey?
    private let scale: CGFloat
    private var stageWidth: CGFloat
    private let copy: OverlayCopy
    /// The strip at the top that a camera housing hides; the toolbar starts below it.
    private let topInset: CGFloat

    init(width: CGFloat, scale: CGFloat, language: Language, topInset: CGFloat = 0) {
        self.scale = scale; stageWidth = width; copy = .forLanguage(language); self.topInset = topInset
        root.actions = Self.noActions
        background.backgroundColor = Theme.hudBackground; background.cornerRadius = 9
        background.borderColor = Theme.srgb(0xffffff, alpha: 0.10); background.borderWidth = 1
        background.shadowColor = Theme.srgb(0); background.shadowOpacity = 0.45; background.shadowRadius = 16; background.shadowOffset = CGSize(width: 0, height: 6)
        root.addSublayer(background)
        modeDot.cornerRadius = 3; root.addSublayer(modeDot)
        setup(mode, 10, mono: true, semibold: true); setup(hint, 11); setup(readout, 11, mono: true)
        setup(helpLabel, 12, mono: true, semibold: true); setup(copyLabel, 12, semibold: true)
        hintBackground.cornerRadius = 9; hintBackground.actions = Self.noActions
        root.addSublayer(mode); root.addSublayer(hintBackground); root.addSublayer(hint); root.addSublayer(readout)
        for separator in separators { separator.backgroundColor = Theme.srgb(0xffffff, alpha: 0.10); root.addSublayer(separator) }
        for i in intentButtons.indices {
            intentButtons[i].cornerRadius = 6; root.addSublayer(intentButtons[i])
            intentDots[i].cornerRadius = 2; root.addSublayer(intentDots[i])
            setup(intentLabels[i], 11, mono: true); root.addSublayer(intentLabels[i])
        }
        for i in toolButtons.indices {
            toolButtons[i].cornerRadius = 6; root.addSublayer(toolButtons[i])
            toolIcons[i].fillColor = nil; toolIcons[i].lineWidth = 1.4; root.addSublayer(toolIcons[i])
            setup(toolLabels[i], 9, mono: true, semibold: true); root.addSublayer(toolLabels[i])
        }
        helpButton.cornerRadius = 6; root.addSublayer(helpButton); root.addSublayer(helpLabel)
        copyButton.cornerRadius = 6; root.addSublayer(copyButton); root.addSublayer(copyLabel)
        helpPanel.cornerRadius = 10; helpPanel.borderWidth = 1; helpPanel.borderColor = Theme.srgb(0xffffff, alpha: 0.1)
        helpPanel.backgroundColor = Theme.oklch(0.15, 0.004, 250, alpha: 0.92); root.addSublayer(helpPanel)

        for (key, description) in copy.help {
            let k = CATextLayer(), d = CATextLayer(), line = CALayer()
            setup(k, 11, mono: true, semibold: true); setup(d, 12); d.foregroundColor = Theme.oklch(0.72, 0.005, 250); d.truncationMode = .none
            k.string = key; d.string = description; d.isWrapped = true
            line.backgroundColor = Theme.srgb(0xffffff, alpha: 0.06)
            helpPanel.addSublayer(k); helpPanel.addSublayer(d); helpPanel.addSublayer(line)
        }
    }

    func contains(_ p: CGPoint) -> Bool { backgroundFrame.contains(p) || (!helpPanel.isHidden && panelFrame.contains(p)) }
    func action(at p: CGPoint) -> Event? { hitAreas.first { $0.0.contains(p) }?.1 }

    func apply(_ state: CaptureState, isActive: Bool) {
        root.isHidden = !isActive
        guard isActive else { return }
        let currentIntent = state.active.flatMap { id in state.marks.first { $0.id == id }?.intent } ?? state.intent
        let key = DisplayKey(mode: state.mode, noteMode: state.noteMode, hasActive: state.active != nil, intent: currentIntent, tool: state.tool, selection: state.sel, stage: state.stage, count: state.marks.filter { $0.kind != .redact }.count, help: state.help)
        guard key != previous else { return }; previous = key
        background.backgroundColor = increasedContrast ? Theme.oklch(0.15, 0.004, 250) : Theme.hudBackground
        background.borderColor = Theme.srgb(0xffffff, alpha: increasedContrast ? 1 : 0.10)
        hintBackground.backgroundColor = background.backgroundColor
        for separator in separators { separator.backgroundColor = Theme.srgb(0xffffff, alpha: increasedContrast ? 1 : 0.10) }
        helpPanel.borderColor = Theme.srgb(0xffffff, alpha: increasedContrast ? 1 : 0.10)
        helpPanel.backgroundColor = Theme.oklch(0.15, 0.004, 250, alpha: increasedContrast ? 1 : 0.92)
        if let lines = helpPanel.sublayers {
            for index in stride(from: 2, to: lines.count, by: 3) {
                lines[index].backgroundColor = Theme.srgb(0xffffff, alpha: increasedContrast ? 1 : 0.06)
            }
        }
        let selecting = state.mode == .select
        let modeName = selecting ? copy.modeArea : state.noteMode ? copy.modeNote : state.active != nil ? copy.modeSelected : copy.modeAnnotate
        let modeWidth = selecting ? 106 : 106 - CGFloat(9 - modeName.count) * 7.5
        // While choosing the area the bar is as wide as its words: the mode name says what to do, and the help
        // button is labelled, so the two do not read as one question.
        let modeFont = Theme.mono(10, semibold: true)
        let areaLabelWidth = selecting ? textWidth(modeName, font: modeFont, kern: 1) : 0
        let helpText = selecting ? copy.helpButton : "?"
        let helpWidth = selecting ? textWidth(helpText, font: Theme.mono(12, semibold: true), kern: 0) + 18 : 26
        let names = copy.intents
        let intentAdjustment = CGFloat(names[currentIntent.rawValue - 1].count - names[1].count) * 6
        let wide = stageWidth >= 1080
        // The readout was laid out for a two-letter unit behind the number of marks.
        let readoutAdjustment = wide ? CGFloat(copy.marksUnit.count - 2) * 7 : 0
        let naturalWidth: CGFloat = selecting ? 22 + areaLabelWidth + 21 + helpWidth + 5 : (wide ? 880 : 692) + modeWidth - 106 + intentAdjustment + readoutAdjustment
        let width = min(naturalWidth, stageWidth - 20)
        let wraps = !selecting && width < naturalWidth
        let x = max(10, (stageWidth - width) / 2), y = 10 + topInset
        let toolY = y + (wraps ? 34 : 0)
        backgroundFrame = CGRect(x: x, y: y, width: width, height: wraps ? 68 : 34)
        background.frame = backgroundFrame
        hitAreas = []
        accessibilityItems = []
        modeDot.frame = CGRect(x: x + 10, y: y + 14, width: 6, height: 6)
        modeDot.backgroundColor = selecting ? Theme.srgb(0xffffff) : Theme.intent(currentIntent)
        mode.frame = CGRect(x: x + 22, y: y + 11, width: selecting ? areaLabelWidth + 2 : 82, height: 16); setSpaced(modeName, mode, font: modeFont, color: Theme.hudText, spacing: 1)
        for separator in separators { separator.isHidden = selecting }
        separators[0].isHidden = false
        separators[0].frame = CGRect(x: selecting ? x + 22 + areaLabelWidth + 10 : x + modeWidth - 4, y: y + 9, width: 1, height: 16)
        var cursor = x + modeWidth
        for i in intentButtons.indices {
            let button = intentButtons[i], dot = intentDots[i], label = intentLabels[i]
            button.isHidden = selecting; dot.isHidden = selecting; label.isHidden = selecting
            if selecting { continue }
            let active = Intent.allCases[i] == currentIntent
            let w: CGFloat = active ? CGFloat(54 + names[i].count * 6) : 39
            button.frame = CGRect(x: cursor, y: y + 4, width: w, height: 26)
            button.backgroundColor = active ? Theme.srgb(0xffffff, alpha: 0.12) : nil
            dot.frame = CGRect(x: cursor + 8, y: y + 12, width: 9, height: 9); dot.backgroundColor = Theme.intent(Intent.allCases[i])
            label.frame = CGRect(x: cursor + 23, y: y + 10, width: w - 23, height: 16)
            label.foregroundColor = active ? Theme.hudText : Theme.hudMuted
            setSpaced("\(i + 1)" + (active ? " \(names[i])" : ""), label, font: Theme.mono(11), color: active ? Theme.hudText : Theme.hudMuted, spacing: 0.44)
            hitAreas.append((button.frame, .chooseIntent(Intent.allCases[i])))
            accessibilityItems.append(.init(frame: button.frame, role: .radio, name: copy.intentNames[i], action: .chooseIntent(Intent.allCases[i]), selected: active))
            cursor += w + 2
        }
        separators[1].frame = CGRect(x: cursor + 2, y: y + 9, width: 1, height: 16)
        cursor = wraps ? x + 8 : cursor + (selecting ? 0 : 7)
        let letters = ["B", "O", "A", "H", "X", "C"]
        for i in toolButtons.indices {
            let button = toolButtons[i], icon = toolIcons[i], label = toolLabels[i]
            button.isHidden = selecting; icon.isHidden = selecting; label.isHidden = selecting
            if selecting { continue }
            let active = Tool.allCases[i] == state.tool
            button.frame = CGRect(x: cursor, y: toolY + 4, width: 36, height: 26)
            button.backgroundColor = active ? Theme.srgb(0xffffff, alpha: 0.12) : nil
            icon.frame = CGRect(x: cursor + 7, y: toolY + 10, width: 14, height: 14); icon.path = Self.icon(i)
            icon.strokeColor = active ? Theme.hudText : Theme.hudMuted
            icon.fillColor = i == 4 ? icon.strokeColor : nil
            label.frame = CGRect(x: cursor + 24, y: toolY + 14, width: 10, height: 12); label.foregroundColor = Theme.hudMuted; set(letters[i], label)
            hitAreas.append((button.frame, .chooseTool(Tool.allCases[i])))
            accessibilityItems.append(.init(frame: button.frame, role: .radio, name: copy.toolNames[i], action: .chooseTool(Tool.allCases[i]), selected: active))
            cursor += 38
        }
        separators[2].isHidden = selecting || !wide
        separators[2].frame = CGRect(x: cursor + 6, y: y + 9, width: 1, height: 16)
        readout.isHidden = selecting || !wide
        if !readout.isHidden {
            let w = (state.sel?.w ?? 1) * Double(state.stage.pixelWidth), h = (state.sel?.h ?? 1) * Double(state.stage.pixelHeight)
            readout.frame = CGRect(x: cursor + 20, y: y + 10, width: 200, height: 16)
            let dims = "\(Int(w.rounded()))×\(Int(h.rounded()))"
            let marks = "\(String(format: "%02d", state.marks.filter { $0.kind != .redact }.count)) \(copy.marksUnit)"
            let tokens = Geometry.tokenEstimate(width: w, height: h)
            let font = Theme.mono(11)
            // One space plus kerning gives a 10 pt gap between the three groups.
            let gap = NSAttributedString(string: " ", attributes: [.init(kCTFontAttributeName as String): font, .init(kCTKernAttributeName as String): 3.4])
            let styled = NSMutableAttributedString(string: dims, attributes: [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): Theme.oklch(0.62, 0.005, 250)])
            styled.append(gap)
            styled.append(NSAttributedString(string: marks, attributes: [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): Theme.hudText]))
            styled.append(gap)
            styled.append(NSAttributedString(string: tokens, attributes: [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): Theme.oklch(0.62, 0.005, 250)]))
            if !(readout.string as? NSAttributedString ?? NSAttributedString()).isEqual(to: styled) { readout.string = styled }
            cursor += 200
        }
        let helpX = selecting ? x + width - helpWidth - 4 : x + width - 118
        helpButton.frame = CGRect(x: helpX, y: toolY + 4, width: helpWidth, height: 26)
        helpButton.backgroundColor = state.help ? Theme.srgb(0xffffff, alpha: 0.12) : nil
        helpLabel.frame = CGRect(x: helpX + 9, y: toolY + 9, width: helpWidth - 14, height: 16); set(helpText, helpLabel)
        hitAreas.append((helpButton.frame, .toggleHelp))
        accessibilityItems.append(.init(frame: helpButton.frame, role: .button, name: copy.shortcuts, action: .toggleHelp))
        copyButton.isHidden = selecting; copyLabel.isHidden = selecting
        if !selecting {
            copyButton.frame = CGRect(x: x + width - 90, y: toolY + 4, width: 86, height: 26); copyButton.backgroundColor = Theme.hudText
            copyLabel.frame = CGRect(x: x + width - 80, y: toolY + 9, width: 75, height: 17); copyLabel.foregroundColor = Theme.oklch(0.14, 0.004, 250); let copyText = NSMutableAttributedString(string: copy.copy, attributes: [.init(kCTFontAttributeName as String): Theme.semiboldSans(12), .init(kCTForegroundColorAttributeName as String): Theme.oklch(0.14, 0.004, 250)])
            copyText.append(NSAttributedString(string: state.noteMode || state.active != nil ? " ⏎⏎" : "  ⏎", attributes: [.init(kCTFontAttributeName as String): Theme.mono(11, semibold: true), .init(kCTForegroundColorAttributeName as String): Theme.oklch(0.14, 0.004, 250, alpha: 0.55)]))
            if !(copyLabel.string as? NSAttributedString ?? NSAttributedString()).isEqual(to: copyText) { copyLabel.string = copyText }
            hitAreas.append((copyButton.frame, .copy))
            accessibilityItems.append(.init(frame: copyButton.frame, role: .button, name: copy.copy, action: .copy))
        }
        let hints = selecting ? copy.selectHint : state.noteMode ? copy.noteHint : state.tool == .crop ? copy.cropHint : state.active != nil ? copy.selectedHint : copy.markHint
        let styled = NSMutableAttributedString()
        for (index, pair) in hints.enumerated() {
            if index > 0 { styled.append(NSAttributedString(string: "     ")) }
            styled.append(NSAttributedString(string: pair.0, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): Theme.mono(10, semibold: true), NSAttributedString.Key(kCTKernAttributeName as String): 0.4, NSAttributedString.Key(kCTForegroundColorAttributeName as String): Theme.hudText]))
            styled.append(NSAttributedString(string: "  " + pair.1, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): Theme.sans(11), NSAttributedString.Key(kCTForegroundColorAttributeName as String): Theme.hudMuted]))
        }
        hint.frame = CGRect(x: 0, y: topInset + (wraps ? 86 : 52), width: stageWidth, height: 18); hint.alignmentMode = .center
        let hintWidth = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(styled), nil, nil, nil)).rounded(.up) + 28
        hintBackground.frame = CGRect(x: ((stageWidth - hintWidth) / 2).rounded(), y: hint.frame.minY - 5, width: hintWidth, height: 26)
        if !(hint.string as? NSAttributedString ?? NSAttributedString()).isEqual(to: styled) { hint.string = styled }
        helpPanel.isHidden = !state.help
        if state.help {
            let pw = min(stageWidth - 20, 620), columns = pw >= 560 ? 2 : 1
            let rows = (16 + columns - 1) / columns
            let heights: [CGFloat] = columns == 2 ? copy.helpRowHeights : (0..<rows).map { _ in 42 }
            let panelHeight = heights.reduce(22, +)
            panelFrame = CGRect(x: (stageWidth - pw) / 2, y: topInset + (wraps ? 110 : 76), width: pw, height: panelHeight)
            helpPanel.frame = panelFrame
            let colWidth = (pw - 32 - CGFloat(columns - 1) * 28) / CGFloat(columns)
            if let layers = helpPanel.sublayers {
                for i in 0..<16 {
                    let col = i % columns, row = i / columns, bx = 16 + CGFloat(col) * (colWidth + 28), by = 10 + heights.prefix(row).reduce(0, +)
                    layers[i * 3].frame = CGRect(x: bx, y: by + 6, width: 120, height: 20)
                    layers[i * 3 + 1].frame = CGRect(x: bx + 132, y: by + 6, width: colWidth - 132, height: heights[row] - 8)
                    layers[i * 3 + 2].frame = CGRect(x: bx, y: by + heights[row] - 1, width: colWidth, height: 1)
                }
            }
        }
    }

    private func setup(_ layer: CATextLayer, _ size: CGFloat, mono: Bool = false, semibold: Bool = false) {
        layer.font = mono ? Theme.mono(size, semibold: semibold) : (semibold ? Theme.semiboldSans(size) : Theme.sans(size)); layer.fontSize = size
        layer.foregroundColor = Theme.hudText; layer.contentsScale = scale; layer.truncationMode = .end; layer.actions = Self.noActions
    }
    private func setSpaced(_ value: String, _ layer: CATextLayer, font: CTFont, color: CGColor, spacing: CGFloat) {
        let text = NSAttributedString(string: value, attributes: [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): color, .init(kCTKernAttributeName as String): spacing])
        if !(layer.string as? NSAttributedString ?? NSAttributedString()).isEqual(to: text) { layer.string = text }
    }
    var accessibilityFrame: CGRect { backgroundFrame }
    private func set(_ value: String, _ layer: CATextLayer) { if (layer.string as? String) != value { layer.string = value } }
    private func textWidth(_ value: String, font: CTFont, kern: CGFloat) -> CGFloat {
        let text = NSAttributedString(string: value, attributes: [.init(kCTFontAttributeName as String): font, .init(kCTKernAttributeName as String): kern])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)).rounded(.up)
    }
    private static func icon(_ i: Int) -> CGPath {
        let p = CGMutablePath()
        switch i {
        case 0: p.addRoundedRect(in: CGRect(x: 1.5, y: 3, width: 11, height: 8), cornerWidth: 1, cornerHeight: 1)
        case 1: p.addEllipse(in: CGRect(x: 1.4, y: 2.6, width: 11.2, height: 8.8))
        case 2: p.move(to: CGPoint(x: 2, y: 12)); p.addLine(to: CGPoint(x: 12, y: 2)); p.move(to: CGPoint(x: 6, y: 2)); p.addLine(to: CGPoint(x: 12, y: 2)); p.addLine(to: CGPoint(x: 12, y: 8))
        case 3: p.addRect(CGRect(x: 1.5, y: 4.5, width: 11, height: 5))
        case 4: p.addRect(CGRect(x: 1.5, y: 3.5, width: 11, height: 7))
        default: p.move(to: CGPoint(x: 4, y: 1)); p.addLine(to: CGPoint(x: 4, y: 10)); p.addLine(to: CGPoint(x: 13, y: 10)); p.move(to: CGPoint(x: 1, y: 4)); p.addLine(to: CGPoint(x: 10, y: 4)); p.addLine(to: CGPoint(x: 10, y: 13))
        }
        return p
    }
    private static let noActions: [String: any CAAction] = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "hidden": NSNull(), "backgroundColor": NSNull()]
}
