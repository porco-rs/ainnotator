import AICore
import AIPlatform
import AppKit

private struct MenuCopy {
    var capture: String, repeatCapture: String, settings: String, quit: String

    static func forLanguage(_ language: Language) -> MenuCopy {
        switch language {
        case .en:
            MenuCopy(capture: "Annotate area", repeatCapture: "Repeat last area", settings: "Settings…", quit: "Quit AInnotator")
        case .de:
            MenuCopy(capture: "Bereich annotieren", repeatCapture: "Letzten Bereich wiederholen", settings: "Einstellungen …", quit: "AInnotator beenden")
        }
    }
}

final class StatusMenu: NSObject, NSMenuDelegate {
    private let hasLastArea: () -> Bool
    private let capture: () -> Void
    private let repeatCapture: () -> Void
    private let settings: () -> Void
    let menu = NSMenu()
    private var repeatItem: NSMenuItem!

    init(language: Language = .en, hasLastArea: @escaping () -> Bool, capture: @escaping () -> Void,
         repeatCapture: @escaping () -> Void, settings: @escaping () -> Void) {
        let copy = MenuCopy.forLanguage(language)
        self.hasLastArea = hasLastArea
        self.capture = capture
        self.repeatCapture = repeatCapture
        self.settings = settings
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let title = NSMenuItem(title: "AInnotator \(version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(item(copy.capture, #selector(captureAction), key: "a", modifiers: [.option, .shift]))
        repeatItem = item(copy.repeatCapture, #selector(repeatAction), key: "r", modifiers: [.option, .shift])
        menu.addItem(repeatItem)
        menu.addItem(.separator())
        menu.addItem(item(copy.settings, #selector(settingsAction), key: ",", modifiers: .command))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: copy.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
        menuNeedsUpdate(menu)
    }

    private func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        repeatItem.isEnabled = hasLastArea()
    }
    @objc private func captureAction() { capture() }
    @objc private func repeatAction() { repeatCapture() }
    @objc private func settingsAction() { settings() }

    static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 14), flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let path = NSBezierPath()
            let inset = rect.insetBy(dx: 1, dy: 1)
            let arm: CGFloat = 4
            for (corner, dx, dy) in [
                (CGPoint(x: inset.minX, y: inset.minY), arm, arm), (CGPoint(x: inset.maxX, y: inset.minY), -arm, arm),
                (CGPoint(x: inset.minX, y: inset.maxY), arm, -arm), (CGPoint(x: inset.maxX, y: inset.maxY), -arm, -arm),
            ] {
                path.move(to: CGPoint(x: corner.x + dx, y: corner.y))
                path.line(to: corner)
                path.line(to: CGPoint(x: corner.x, y: corner.y + dy))
            }
            path.lineWidth = 1.2
            path.stroke()
            NSBezierPath(ovalIn: CGRect(x: rect.midX - 1.5, y: rect.midY - 1.5, width: 3, height: 3)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    func dump() -> String {
        func lines(_ menu: NSMenu, prefix: String = "") -> [String] {
            menu.items.flatMap { item -> [String] in
                if item.isSeparatorItem { return [prefix + "---"] }
                let state = item.state == .on ? " [selected]" : ""
                let enabled = item.isEnabled ? "enabled" : "disabled"
                let shortcut = item.keyEquivalent.isEmpty ? "" : " [\(item.keyEquivalentModifierMask.contains(.command) ? "⌘" : "")\(item.keyEquivalentModifierMask.contains(.option) ? "⌥" : "")\(item.keyEquivalentModifierMask.contains(.shift) ? "⇧" : "")\(item.keyEquivalent.uppercased())]"
                return ["\(prefix)\(item.title) [\(enabled)]\(state)\(shortcut)"] + (item.submenu.map { lines($0, prefix: prefix + "  ") } ?? [])
            }
        }
        menuNeedsUpdate(menu)
        return lines(menu).joined(separator: "\n")
    }
}
