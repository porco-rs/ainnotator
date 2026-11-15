import AICore
import AIPlatform
import AIRender
import AppKit
import OSLog

/// Owns the one capture session: event -> reduce -> apply. Everything else is a thin call into the shells.
final class AppController: NSObject, NSApplicationDelegate {
    private let capture = ScreenCapture()
    private let hotkeys = HotkeyCenter()
    private let store = CaptureStore()
    private let preferences = Preferences()
    private let probe = ContextProbe()
    private let log = Logger(subsystem: "de.leonschwahn.ainnotator", category: "session")

    private var statusItem: NSStatusItem?
    private var statusMenu: StatusMenu?
    private var settingsWindow: SettingsWindow?
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var panelLayout: [CGDirectDisplayID: CGRect] = [:]
    private var surfaces: [CGDirectDisplayID: IOSurfaceRef] = [:]
    private var activeDisplay: CGDirectDisplayID?
    private var state = CaptureState()
    private var context = CaptureContext()
    private var session = 0
    private var pendingClip: PendingClip?
    /// The machine the terminal tab is connected to, and the app that was in front when the capture began.
    private var remote: RemoteTarget?
    private var frontBundle: String?
    private let follower = ClipFollower()
    private let copier = RemoteCopier()
    private var receipt: ReceiptPanel?
    private var hotkeyTime: UInt64 = 0
    private var cursorHidden = false
    private let language: Language
    private let alerts: AlertCopy
    private let settingsCopy: SettingsCopy

    init(language: Language) {
        self.language = language
        alerts = .forLanguage(language)
        settingsCopy = .forLanguage(language)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
        setUpStatusItem()
        let captureOK = hotkeys.register(keyCode: HotkeyCenter.keyA, modifiers: HotkeyCenter.optionShift) { [weak self] in
            self?.beginCapture(repeating: false)
        }
        let repeatOK = hotkeys.register(keyCode: HotkeyCenter.keyR, modifiers: HotkeyCenter.optionShift) { [weak self] in
            self?.beginCapture(repeating: true)
        }
        log.notice("hotkeys capture=\(captureOK != nil) repeat=\(repeatOK != nil)")
        if captureOK == nil || repeatOK == nil {
            let unavailable = [(captureOK == nil, "⌥⇧A"), (repeatOK == nil, "⌥⇧R")]
                .filter { $0.0 }.map { $0.1 }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                presentError(alerts.shortcutTaken(unavailable))
            }
        }
        probe.startTracking()
        rebuildPanels()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        let days = preferences.retentionDays
        Task.detached { [store] in store.removeExpired(days: days) }
        warmUp(reason: "launch")
        observeScreenReturn()
    }

    /// A start on the locked screen finds no displays, so the first hotkey afterwards would pay for all of it.
    private func observeScreenReturn() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.warmUp(reason: "wake") }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.warmUp(reason: "unlock") }
        }
    }

    /// `just run` starts a new instance; it replaces the running one.
    private func terminateOtherInstances() {
        let me = NSRunningApplication.current
        guard let id = me.bundleIdentifier else { return }
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: id) where other != me {
            other.terminate()
        }
    }

    private func setUpStatusItem() {
        let menu = StatusMenu(language: language,
                              hasLastArea: { [weak self] in self?.state.lastSel != nil },
                              capture: { [weak self] in self?.beginCapture(repeating: false) },
                              repeatCapture: { [weak self] in self?.beginCapture(repeating: true) },
                              settings: { [weak self] in self?.showSettings() })
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusMenu.icon()
        item.button?.setAccessibilityLabel("AInnotator")
        item.menu = menu.menu
        statusMenu = menu
        statusItem = item
    }

    private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(preferences: preferences, language: language) }
        settingsWindow?.show()
    }

    /// Also fires when no display moved, for instance for the Dock; that must not end a session. When one did, the
    /// session ends with its panels, otherwise the hidden cursor and a session without windows would stay behind.
    private func screensChanged() {
        guard Self.screenLayout() != panelLayout else { return }
        closeOverlay()
        rebuildPanels()
        Task { try? await capture.refreshDisplays() }
    }

    private static func screenLayout() -> [CGDirectDisplayID: CGRect] {
        Dictionary(NSScreen.screens.compactMap { screen in displayID(of: screen).map { ($0, screen.frame) } }) { first, _ in first }
    }

    private func rebuildPanels() {
        panelLayout = Self.screenLayout()
        for panel in panels.values { panel.close() }
        panels.removeAll()
        for screen in NSScreen.screens {
            guard let id = Self.displayID(of: screen) else { continue }
            panels[id] = OverlayPanel(screen: screen, language: language) { [weak self] event, panel in
                self?.handle(event, from: panel)
            }
        }
    }

    /// One capture without showing anything, so the first real hotkey is not the slow one.
    private func warmUp(reason: String) {
        guard CGPreflightScreenCaptureAccess() else { return }
        let ids = Array(panels.keys)
        let start = DispatchTime.now().uptimeNanoseconds
        Task {
            try? await capture.refreshDisplays()
            var captured = 0
            for id in ids {
                if (try? await capture.capture(id)) != nil { captured += 1 }
            }
            let millis = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            log.notice("warm-up \(reason, privacy: .public) \(captured)/\(ids.count) displays \(millis, format: .fixed(precision: 1)) ms")
        }
    }

    // MARK: Session

    func beginCapture(repeating: Bool) {
        hotkeyTime = DispatchTime.now().uptimeNanoseconds
        guard CGPreflightScreenCaptureAccess() else {
            requestScreenAccess()
            return
        }
        if repeating {
            // ⌥⇧R does nothing without a last area and while a mark is active.
            if state.lastSel == nil || state.active != nil && state.mode == .annotate { return }
        }
        closeOverlay()
        dismissReceipt()
        session += 1
        let current = session
        // The app name is there at once; the slower fields arrive while the user marks, or are left out.
        context = CaptureContext(app: NSWorkspace.shared.frontmostApplication?.localizedName)
        frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        remote = nil
        Task {
            async let found = probe.snapshot()
            async let target = probe.remoteTarget()
            let (context, remote) = await (found, target)
            guard current == session else { return }
            self.context = context
            self.remote = remote
            log.notice("context ready \(self.millisSinceHotkey(), format: .fixed(precision: 1)) ms, remote \(remote != nil)")
        }
        let cursorDisplay = Self.displayUnderCursor() ?? CGMainDisplayID()

        Task {
            // The display under the cursor comes first: that is where the user looks.
            do {
                let first = try await capture.capture(cursorDisplay)
                guard current == session else { return }
                log.notice("capture cursor display \(self.millisSinceHotkey(), format: .fixed(precision: 1)) ms")
                show(first, makeKey: true, repeating: repeating)
                log.notice("overlay cursor display \(self.millisSinceHotkey(), format: .fixed(precision: 1)) ms")
            } catch {
                log.error("capture failed: \(String(describing: error))")
                if current == session { presentError(alerts.captureFailed) }
                return
            }
            let others = panels.keys.filter { $0 != cursorDisplay }
            await withTaskGroup(of: CapturedDisplay?.self) { group in
                for id in others {
                    group.addTask { [capture] in try? await capture.capture(id) }
                }
                for await result in group {
                    guard current == session, let result else { continue }
                    show(result, makeKey: false, repeating: repeating)
                }
            }
            log.notice("overlay all displays \(self.millisSinceHotkey(), format: .fixed(precision: 1)) ms")
        }
    }

    private func millisSinceHotkey() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - hotkeyTime) / 1e6
    }

    private func show(_ captured: CapturedDisplay, makeKey: Bool, repeating: Bool) {
        guard let panel = panels[captured.displayID] else { return }
        surfaces[captured.displayID] = captured.surface
        panel.scene.setImage(captured.surface)
        if makeKey {
            activeDisplay = captured.displayID
            _ = reduce(&state, repeating ? .repeatLast(captured.stage) : .begin(captured.stage))
        }
        panel.scene.apply(state, isActive: captured.displayID == activeDisplay)
        CATransaction.flush()
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.overlayView)
            updateCursor()
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func handle(_ event: Event, from panel: OverlayPanel) {
        guard state.mode == .select || state.mode == .annotate else { return }
        // The first press on another display moves the selection there.
        if case .pointerDown = event, state.mode == .select, let id = displayID(of: panel), id != activeDisplay,
           let surface = surfaces[id] {
            activeDisplay = id
            panel.makeKey()
            panel.makeFirstResponder(panel.overlayView)
            _ = reduce(&state, .setStage(Self.stage(of: surface, panel: panel)))
        }
        if case .pointerMoved = event, displayID(of: panel) != activeDisplay { return }

        let effects = reduce(&state, event)
        applyToScenes()
        for effect in effects { perform(effect) }
    }

    private func displayID(of panel: OverlayPanel) -> CGDirectDisplayID? {
        panels.first { $0.value === panel }?.key
    }

    private func applyToScenes() {
        for (id, panel) in panels where panel.isVisible {
            panel.scene.apply(state, isActive: id == activeDisplay)
        }
        updateCursor()
    }

    /// Choosing the area draws its own crosshair, marking up uses the crosshair cursor. Works although the frontmost app stays the same
    /// (measured with `--cursor-probe`).
    private func updateCursor() {
        let overHUD = activeDisplay.flatMap { panels[$0]?.scene.wantsArrowCursor } ?? false
        let hide = state.mode == .select && !overHUD
        if hide != cursorHidden {
            if hide { NSCursor.hide() } else { NSCursor.unhide() }
            cursorHidden = hide
        }
        if overHUD {
            NSCursor.arrow.set()
        } else if state.mode == .annotate {
            NSCursor.crosshair.set()
        }
    }

    private func perform(_ effect: Effect) {
        switch effect {
        case .cancel:
            closeOverlay()
        case .finish:
            deliver()
        case .dismissReceipt:
            dismissReceipt()
        case .pickWindow(let point):
            _ = reduce(&state, .selectWindow(windowArea(under: point) ?? .full))
            applyToScenes()
        }
    }

    /// File, image and path are published as promises at once; the file follows off the main thread.
    private func deliver() {
        guard let display = activeDisplay, let surface = surfaces[display] else {
            closeOverlay()
            return
        }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let snapshot = state
        let context = self.context
        let store = self.store
        guard let url = try? store.reservePNG() else {
            presentError(alerts.saveFailed)
            closeOverlay()
            return
        }
        let path = CaptureStore.displayPath(url)
        let json = Data(Payload.json(snapshot, imagePath: path, context: context, createdAt: Date()).utf8)
        let retentionDays = preferences.retentionDays
        // Nothing is copied to a machine the user has not said yes to.
        let target = remote.flatMap { preferences.mayCopy(toRemote: $0.consentKey) ? $0 : nil }
        // A machine that was found but never confirmed: the receipt asks, and nothing is sent until then.
        let unconfirmed = target == nil && preferences.remoteCopyEnabled ? remote : nil
        let copier = self.copier
        let clip = PendingClip(file: url)
        pendingClip = clip
        follower.stop()
        if target != nil {
            // The clipboard carries what fits the app in front: the path on the other machine for the terminal,
            // the file for everything else.
            clip.expectRemote()
            Clipboard.publish(clip, form: ClipFollower.form(forFrontmost: frontBundle))
            follower.follow(clip)
        } else {
            Clipboard.publish(clip)
        }
        log.notice("clipboard published \(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6, format: .fixed(precision: 2)) ms")

        let input = CardRenderer.Input(source: .surface(surface), state: snapshot, footer: Payload.contextLine(context) ?? "", language: language)
        input.source.holdForExport()
        closeOverlay()
        let exportSession = session
        let log = self.log
        Task.detached(priority: .userInitiated) { [input] in
            defer { input.source.releaseAfterExport() }
            let png = CardRenderer.renderPNG(input)
            var saved = false
            if let png {
                do {
                    try store.write(png, to: url)
                    try store.write(json, to: url.deletingPathExtension().appendingPathExtension("json"))
                    saved = true
                } catch {
                    log.error("write failed: \(String(describing: error))")
                }
            }
            if !saved { store.discard(url) }
            clip.fulfill(png: png, saved: saved)
            // The copy follows the file: the path on the other machine reaches a target only once the capture
            // lies there. A paste in the meantime waits for it.
            var remotePath: String?
            if let target {
                if saved {
                    let begun = DispatchTime.now().uptimeNanoseconds
                    let result = copier.copy(url, to: target, retentionDays: retentionDays)
                    remotePath = try? result.get()
                    log.notice("remote copy \(remotePath != nil ? "done" : "failed") \(Double(DispatchTime.now().uptimeNanoseconds - begun) / 1e6, format: .fixed(precision: 0)) ms")
                }
                clip.fulfillRemote(path: remotePath)
            }
            let copyFailed = target != nil && remotePath == nil
            store.removeExpired(days: retentionDays)
            log.notice("export done \(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6, format: .fixed(precision: 1)) ms")
            let preview = saved ? CardRenderer.render(input, previewWidth: Self.previewWidth) : nil
            let pngBytes = png?.count ?? 0
            await MainActor.run {
                // No file, so nothing may name it. The pasteboard is this export's own even if a newer capture has begun.
                if !saved { Clipboard.keepOnlyImage(of: clip) }
                // Without a copy on the other machine the capture stays what it is everywhere else: a local file.
                if copyFailed {
                    self.follower.stop()
                    if saved { Clipboard.switchForm(of: clip, to: .file) }
                }
                // A newer capture has begun: this receipt would sit behind that overlay.
                guard exportSession == self.session else { return }
                guard let preview else {
                    self.presentError(png == nil ? self.alerts.saveFailed : self.alerts.saveFailedImageKept)
                    return
                }
                let sel = snapshot.sel ?? .full
                let model = ReceiptModel(
                    text: url.path, card: preview,
                    width: Int((sel.w * Double(snapshot.stage.pixelWidth)).rounded()),
                    height: Int((sel.h * Double(snapshot.stage.pixelHeight)).rounded()),
                    pngPath: path, jsonPath: CaptureStore.displayPath(url.deletingPathExtension().appendingPathExtension("json")),
                    pngBytes: pngBytes, jsonBytes: json.count, marks: snapshot.marks, time: Date(),
                    remote: target.map { remotePath != nil ? .copied($0.destination) : .failed($0.destination) }
                        ?? unconfirmed.map { .ask($0.destination) }
                )
                self.showReceipt(model, display: display, asking: unconfirmed.map { ($0, url, clip) })
                self.probe.requestAutomationConsent()
            }
        }
    }

    private func closeOverlay() {
        // Captures of other displays may still be on their way; they belong to the session that ends here.
        session += 1
        for panel in panels.values {
            panel.orderOut(nil)
            panel.scene.setImage(nil)
        }
        surfaces.removeAll()
        activeDisplay = nil
        if state.mode == .select || state.mode == .annotate {
            state.mode = .idle
        }
        updateCursor()
        NSCursor.arrow.set()
        CATransaction.flush()
    }

    // MARK: Receipt

    /// Twice the card's layout width of 320 points, sharp on Retina displays.
    private nonisolated static let previewWidth = 640

    private func showReceipt(_ model: ReceiptModel, display: CGDirectDisplayID, asking: (RemoteTarget, URL, PendingClip)? = nil) {
        dismissReceipt()
        let panel = ReceiptPanel(model: model, language: language) { [weak self] in self?.beginCapture(repeating: false) }
        panel.onClose = { [weak self] in self?.receiptClosed() }
        if let (target, file, clip) = asking {
            panel.onConfirmRemote = { [weak self] in self?.confirmRemote(target, file: file, clip: clip, model: model, display: display) }
        }
        receipt = panel
        panel.show(on: NSScreen.screens.first { Self.displayID(of: $0) == display } ?? NSScreen.main)
    }

    /// The user said yes for this machine: remember it, copy the capture that is still on the clipboard, and show
    /// what became of it. From the next capture on the copy happens without a question.
    private func confirmRemote(_ target: RemoteTarget, file: URL, clip: PendingClip, model: ReceiptModel, display: CGDirectDisplayID) {
        preferences.confirmRemote(target.consentKey)
        guard pendingClip === clip else { return }
        let copier = self.copier
        let retentionDays = preferences.retentionDays
        let log = self.log
        clip.expectRemote()
        follower.follow(clip)
        Clipboard.switchForm(of: clip, to: ClipFollower.form(forFrontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
        Task.detached(priority: .userInitiated) {
            let begun = DispatchTime.now().uptimeNanoseconds
            let path = try? copier.copy(file, to: target, retentionDays: retentionDays).get()
            clip.fulfillRemote(path: path)
            log.notice("remote copy after consent \(path != nil ? "done" : "failed") \(Double(DispatchTime.now().uptimeNanoseconds - begun) / 1e6, format: .fixed(precision: 0)) ms")
            await MainActor.run {
                guard self.pendingClip === clip else { return }
                if path == nil {
                    self.follower.stop()
                    Clipboard.switchForm(of: clip, to: .file)
                }
                var shown = model
                shown.remote = path != nil ? .copied(target.destination) : .failed(target.destination)
                self.showReceipt(shown, display: display)
            }
        }
    }

    private func dismissReceipt() {
        receipt?.close()
    }

    private func receiptClosed() {
        // Closing can start from a button inside the panel; the windows must outlive that click.
        let closing = receipt
        receipt = nil
        DispatchQueue.main.async { _ = closing }
    }

    // MARK: Helpers

    private func requestScreenAccess() {
        _ = CGRequestScreenCaptureAccess()
        presentError(settingsCopy.screenDenied, openSettings: true)
    }

    private func presentError(_ text: String, openSettings: Bool = false) {
        let alert = NSAlert()
        alert.messageText = text
        if openSettings { alert.addButton(withTitle: settingsCopy.openSettings) }
        alert.addButton(withTitle: alerts.ok)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, openSettings,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Space while choosing the area: the frontmost normal window under the pointer on the active display.
    private func windowArea(under point: NormPoint) -> NormRect? {
        guard let id = activeDisplay else { return nil }
        let bounds = CGDisplayBounds(id)
        let cursor = CGPoint(x: bounds.minX + point.x * bounds.width, y: bounds.minY + point.y * bounds.height)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict), rect.contains(cursor) else { continue }
            let clipped = rect.intersection(bounds)
            return NormRect(
                x: (clipped.minX - bounds.minX) / bounds.width, y: (clipped.minY - bounds.minY) / bounds.height,
                w: clipped.width / bounds.width, h: clipped.height / bounds.height
            )
        }
        return nil
    }

    private static func stage(of surface: IOSurfaceRef, panel: OverlayPanel) -> Stage {
        Stage(
            pixelWidth: IOSurfaceGetWidth(surface), pixelHeight: IOSurfaceGetHeight(surface),
            pointWidth: panel.frame.width, pointHeight: panel.frame.height
        )
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static func displayUnderCursor() -> CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }.flatMap(displayID(of:))
    }
}
