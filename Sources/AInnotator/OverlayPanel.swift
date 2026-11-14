import AICore
import AIRender
import AppKit

/// Full-screen panel over everything, including full-screen Spaces. It takes the keyboard without activating the app,
/// so the previous app stays frontmost and ⌘V lands there.
final class OverlayPanel: NSPanel {
    let overlayView: OverlayView
    let scene: OverlayScene

    init(screen: NSScreen, language: Language = .en, handler: @escaping (Event, OverlayPanel) -> Void) {
        let frame = screen.frame
        // The toolbar sat behind the camera housing of a notched display; the safe area says how much to leave free.
        scene = OverlayScene(size: frame.size, scale: screen.backingScaleFactor, language: language, topInset: screen.safeAreaInsets.top)
        overlayView = OverlayView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isMovable = false
        overlayView.layer = scene.root
        overlayView.wantsLayer = true
        contentView = overlayView
        overlayView.scene = scene
        scene.accessibilityMarksDidChange = { [weak overlayView] in
            guard let overlayView else { return }
            NSAccessibility.post(element: overlayView, notification: .layoutChanged)
        }
        overlayView.observeContrast()
        overlayView.send = { [unowned self] event in handler(event, self) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Turns AppKit input into core events. Text goes through the input system, so dead keys and ⌥ characters work.
final class OverlayView: NSView, NSTextInputClient {
    var send: (Event) -> Void = { _ in }
    weak var scene: OverlayScene?
    private var hudGesture = false
    private var marked = ""
    private var accessibilityCache: [String: OverlayElement] = [:]

    func observeContrast() {
        updateContrast()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateContrast), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @objc private func updateContrast() {
        scene?.increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        guard let scene, let window else { return [] }
        let items = scene.accessibilityItems
        var next: [String: OverlayElement] = [:]
        var toolbar: OverlayElement?
        var controls: [OverlayElement] = []
        var images: [OverlayElement] = []
        for item in items {
            let key = "\(item.role):\(item.name)"
            let element = accessibilityCache[key] ?? OverlayElement()
            element.handler.action = item.action
            element.handler.send = { [weak self] event in self?.send(event) }
            let role: NSAccessibility.Role = switch item.role {
            case .toolbar: .toolbar
            case .radio: .radioButton
            case .button: .button
            case .image: .image
            }
            element.setAccessibilityRole(role)
            element.setAccessibilityLabel(item.name)
            let windowRect = convert(item.frame, to: nil)
            element.setAccessibilityFrame(window.convertToScreen(windowRect))
            if item.role == .radio { element.setAccessibilityValue(item.selected ? 1 : 0) }
            next[key] = element
            switch item.role {
            case .toolbar: toolbar = element
            case .image: images.append(element)
            default: controls.append(element)
            }
        }
        toolbar?.setAccessibilityParent(self)
        toolbar?.setAccessibilityChildren(controls)
        for control in controls { control.setAccessibilityParent(toolbar) }
        for image in images { image.setAccessibilityParent(self) }
        accessibilityCache = next
        return (toolbar.map { [$0] } ?? []) + images
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self
        ))
    }

    private func position(_ event: NSEvent) -> (NormPoint, Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let x = point.x / bounds.width
        let y = point.y / bounds.height
        let inside = x >= 0 && x <= 1 && y >= 0 && y <= 1
        return (NormPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1)), inside)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let scene, scene.containsHUD(point) {
            hudGesture = true
            if let action = scene.action(at: point) { send(action) }
        } else if scene?.helpIsOpen == true {
            hudGesture = true; send(.toggleHelp)
        } else { hudGesture = false; send(.pointerDown(position(event).0)) }
    }
    override func mouseUp(with event: NSEvent) { if hudGesture { hudGesture = false } else { send(.pointerUp) } }
    override func mouseExited(with event: NSEvent) { send(.pointerLeft) }

    override func mouseDragged(with event: NSEvent) {
        guard !hudGesture else { return }
        let (point, inside) = position(event)
        send(.pointerMoved(point, inside: inside))
    }

    override func mouseMoved(with event: NSEvent) {
        let (point, inside) = position(event)
        send(.pointerMoved(point, inside: inside))
    }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let command = event.modifierFlags.contains(.command)
        let special: Key? = switch event.keyCode {
        case 36, 76: .enter
        case 53: .escape
        case 48: .tab
        case 51: .backspace
        case 117: .delete
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        default: nil
        }
        // ⏎⏎ finishes, so a held key must not count as the second press.
        if special == .enter, event.isARepeat { return }
        if special == .escape, marked.isEmpty, scene?.helpIsOpen == true {
            send(.toggleHelp)
        } else if let special, marked.isEmpty {
            send(.key(KeyInput(key: special, shift: shift, command: command)))
        } else if command, let characters = event.charactersIgnoringModifiers?.lowercased() {
            send(.key(KeyInput(key: .character(characters), shift: shift, command: true)))
        } else {
            interpretKeyEvents([event])
        }
    }

    // MARK: NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        marked = ""
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if !text.isEmpty { send(.insertText(text)) }
    }

    override func doCommand(by selector: Selector) {}

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    }

    func unmarkText() { marked = "" }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { marked.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: marked.utf16.count) }
    func hasMarkedText() -> Bool { !marked.isEmpty }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { window?.frame ?? .zero }
    func characterIndex(for point: NSPoint) -> Int { 0 }
}

nonisolated private final class OverlayActionHandler: @unchecked Sendable {
    @MainActor var action: Event?
    @MainActor var send: (@MainActor (Event) -> Void)?
    nonisolated init() {}
}

nonisolated private final class OverlayElement: NSAccessibilityElement {
    let handler = OverlayActionHandler()

    override func accessibilityPerformPress() -> Bool {
        let handler = handler
        Task { @MainActor in
            guard let action = handler.action else { return }
            handler.send?(action)
        }
        return true
    }
}
