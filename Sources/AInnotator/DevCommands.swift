import AICore
import AIPlatform
import AIRender
import AppKit
import IOSurface
import ServiceManagement
import UniformTypeIdentifiers

/// `--selftest <image> <out>`: plays the main path on a given image without windows, permissions or the real clipboard.
/// `--perf`: measures the real hot path. It shows only the frozen image without dimming, so nothing visibly changes.
///
/// The commands that need a picture (`--selftest`, `--render`, `--receipt`, `--receipt-probe`) take the path of an
/// example screen as an argument; all but `--selftest` fall back to `$AI_EXAMPLE_IMAGE`. `just selftest` draws such a
/// screen with `tools/readme-images/screen.swift`. The sample marks below are placed for that screen (1024 × 640 pt).
enum DevCommands {
    private static var probeClip: PendingClip?
    private static var probeFollower: ClipFollower?
    private static let exampleImageVariable = "AI_EXAMPLE_IMAGE"
    private static let exampleImageHelp = """
        An example screen is needed. `just selftest` draws one at build/example-screen.png, or by hand:
          swiftc -O -o build/example-screen tools/readme-images/screen.swift && build/example-screen build/example-screen.png
        Pass its path as an argument or set AI_EXAMPLE_IMAGE.
        """

    static func run(arguments: [String], language: Language = .en) -> Bool {
        guard let command = arguments.dropFirst().first else { return false }
        switch command {
        case "--clip-quit-probe":
            // Publishes on a named pasteboard, never the real one, and quits the way the menu does. Read it with --clip-read.
            guard arguments.count >= 3 else { print("usage: --clip-quit-probe <pasteboard>"); exit(64) }
            let clip = PendingClip(file: URL(fileURLWithPath: "/tmp/ainnotator-probe.png"))
            clip.fulfill(png: Data([0x89, 0x50, 0x4E, 0x47]), saved: true)
            probeClip = clip
            Clipboard.publish(clip, on: NSPasteboard(name: NSPasteboard.Name(arguments[2])))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return false
        case "--clip-read":
            guard arguments.count >= 3 else { print("usage: --clip-read <pasteboard>"); exit(64) }
            let board = NSPasteboard(name: NSPasteboard.Name(arguments[2]))
            let files = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).map(\.path)
            print("items: \(board.pasteboardItems?.map { $0.types.map(\.rawValue) } ?? []), files: \(files), text: \(board.string(forType: .string) ?? "nil"), png bytes: \(board.data(forType: .png)?.count ?? -1)")
            exit(0)
        case "--clip-hold":
            // Puts an existing PNG on the REAL clipboard the way a capture does, promises included, and keeps serving
            // them: for pasting into real targets by hand. The promises resolve late, as during an export.
            guard arguments.count >= 4, let seconds = Double(arguments[3]), let png = FileManager.default.contents(atPath: arguments[2]) else {
                print("usage: --clip-hold <card.png> <seconds>"); exit(64)
            }
            let clip = PendingClip(file: URL(fileURLWithPath: arguments[2]))
            probeClip = clip
            Clipboard.publish(clip)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { clip.fulfill(png: png, saved: true) }
            print("clipboard holds \(arguments[2]) for \(Int(seconds)) s")
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
            return false
        case "--clip-follow":
            // Puts an existing PNG on the REAL clipboard as a capture that was copied to another machine and lets
            // the clipboard follow the app in front: for pasting into a terminal and into a browser by hand.
            guard arguments.count >= 5, let seconds = Double(arguments[4]), let png = FileManager.default.contents(atPath: arguments[2]) else {
                print("usage: --clip-follow <card.png> <path-on-the-other-machine> <seconds>"); exit(64)
            }
            let clip = PendingClip(file: URL(fileURLWithPath: arguments[2]))
            clip.fulfill(png: png, saved: true)
            clip.expectRemote()
            clip.fulfillRemote(path: arguments[3])
            probeClip = clip
            let describe: (PendingClip.Form) -> String = { $0 == .remote ? "the path on the other machine" : "the file" }
            let front = NSWorkspace.shared.frontmostApplication
            let form = ClipFollower.form(forFrontmost: front?.bundleIdentifier)
            Clipboard.publish(clip, form: form)
            print("\(front?.localizedName ?? "?") in front: the clipboard carries \(describe(form))")
            let follower = ClipFollower()
            follower.onSwitch = { form, name in print("\(name) in front: the clipboard carries \(describe(form))") }
            follower.follow(clip)
            probeFollower = follower
            print("the clipboard follows the app in front for \(Int(seconds)) s")
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
            return false
        case "--menu-dump":
            let menu = StatusMenu(language: language, hasLastArea: { false }, capture: {}, repeatCapture: {}, settings: {})
            print(menu.dump())
            exit(0)
        case "--render":
            guard arguments.count == 4 || arguments.count == 5 else {
                print("usage: --render <state> <out.png> [image.png]\nstates: \(renderStates.joined(separator: ", "))\n\(exampleImageHelp)")
                exit(64)
            }
            renderReference(state: arguments[2], out: arguments[3], image: arguments.count == 5 ? arguments[4] : nil, language: language)
            exit(0)
        case "--selftest":
            guard arguments.count >= 4 else {
                print("usage: --selftest <image.png> <out-dir>\n\(exampleImageHelp)")
                exit(64)
            }
            selfTest(image: arguments[2], out: arguments[3], language: language)
            exit(0)
        case "--receipt":
            guard arguments.count >= 3 else { print("usage: --receipt <out.png> [image.png]\n\(exampleImageHelp)"); exit(64) }
            // An optional fifth word shows the row for another machine: ask, copied or failed.
            let remote: ReceiptRemote? = switch arguments.count > 4 ? arguments[4] : "" {
            case "ask": .ask("devbox")
            case "copied": .copied("devbox")
            case "failed": .failed("devbox")
            default: nil
            }
            renderReceipt(out: arguments[2], image: arguments.count > 3 ? arguments[3] : nil, language: language, remote: remote)
            exit(0)
        case "--receipt-probe":
            guard arguments.count >= 3 else { print("usage: --receipt-probe <out-dir> [image.png]\n\(exampleImageHelp)"); exit(64) }
            let image = loadExampleImage(arguments.count > 3 ? arguments[3] : nil)
            Task { @MainActor in
                await ReceiptProbe.run(out: arguments[2], image: image, language: language)
                exit(0)
            }
            return false
        case "--perf":
            Task { @MainActor in
                await Perf().run()
                exit(0)
            }
            return false
        case "--login-item":
            // The registration belongs to the copy that calls it, so a move to /Applications has to switch it over.
            guard arguments.count >= 3, ["status", "on", "off"].contains(arguments[2]) else { print("usage: --login-item <status|on|off>"); exit(64) }
            do {
                if arguments[2] == "on" { try SMAppService.mainApp.register() }
                if arguments[2] == "off" { try SMAppService.mainApp.unregister() }
            } catch {
                print("failed: \(error)")
                exit(1)
            }
            print("\(Bundle.main.bundlePath): \(SMAppService.mainApp.status == .enabled ? "enabled" : "not enabled (\(SMAppService.mainApp.status.rawValue))")")
            exit(0)
        case "--settings-probe":
            // Opens the real settings window for a moment and photographs only that window. Changes nothing.
            guard arguments.count >= 3 else { print("usage: --settings-probe <out.png>"); exit(64) }
            Task { @MainActor in
                let settings = SettingsWindow(preferences: Preferences(), language: language)
                settings.show()
                try? await Task.sleep(for: .milliseconds(700))
                await ReceiptProbe.photograph(settings.windowNumber, to: arguments[2])
                exit(0)
            }
            return false
        case "--idle-probe":
            // Shows nothing: warms up, stays idle for each given number of seconds, then captures twice.
            let waits = arguments.dropFirst(2).compactMap { Int($0) }
            guard !waits.isEmpty else { print("usage: --idle-probe <seconds>..."); exit(64) }
            Task { @MainActor in
                await Perf().idle(waits: waits)
                exit(0)
            }
            return false
        case "--cursor-probe":
            Task { @MainActor in
                await CursorProbe.run()
                exit(0)
            }
            return false
        default:
            return false
        }
    }

    // MARK: Example screen and sample state

    /// The states `--render` can draw: choosing the area, and marking up the area in its variants.
    private static let renderStates = [
        "select", "select-drag", "annotate-empty", "annotate", "annotate-note", "annotate-note-empty",
        "annotate-selected", "annotate-arrow-drag", "annotate-crop", "annotate-help",
    ]

    /// The area and context of the sample capture, placed for the example screen (1024 × 640 pt).
    private static let sampleSelection = NormRect(x: 108.0 / 1024, y: 176.0 / 640, w: 808.0 / 1024, h: 440.0 / 640)
    private static let sampleContext = CaptureContext(
        app: "Browser", window: "Checkout", url: "https://tinyplant.example/checkout?session=abc#top", repo: "tiny-plant", branch: "main"
    )

    /// Reads the example screen from the given path, else from `$AI_EXAMPLE_IMAGE`, else says how to make one.
    private static func loadExampleImage(_ path: String?) -> CGImage {
        let chosen = path ?? ProcessInfo.processInfo.environment[exampleImageVariable]
        guard let chosen, !chosen.isEmpty else {
            print("no example screen given\n\(exampleImageHelp)")
            exit(66)
        }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: chosen) as CFURL, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            print("cannot read \(chosen)\n\(exampleImageHelp)")
            exit(66)
        }
        return picture
    }

    /// A Retina capture: two pixels per point.
    private static func stage(of picture: CGImage) -> Stage {
        Stage(
            pixelWidth: picture.width, pixelHeight: picture.height,
            pointWidth: Double(picture.width) / 2, pointHeight: Double(picture.height) / 2
        )
    }

    /// The sample capture on the example screen, played through the real reducer: the checkout area with a box
    /// ("change"), a question oval, a bug arrow and a redaction over the e-mail address.
    private static func sampleState(stage: Stage) -> CaptureState {
        var state = CaptureState()
        func send(_ event: Event) { _ = reduce(&state, event) }
        func point(_ x: Double, _ y: Double) -> NormPoint { NormPoint(x: x / 1024, y: y / 640) }
        func drag(_ a: (Double, Double), _ b: (Double, Double)) {
            send(.pointerDown(point(a.0, a.1)))
            send(.pointerMoved(point(b.0, b.1), inside: true))
            send(.pointerUp)
        }

        send(.begin(stage))
        drag((108, 176), (916, 616))
        drag((116, 434), (552, 503))
        send(.insertText("Apply next to the field"))
        send(.key(KeyInput(key: .escape)))
        send(.insertText("o"))
        send(.insertText("4"))
        drag((640, 255), (742, 289))
        send(.insertText("Real stock?"))
        send(.key(KeyInput(key: .escape)))
        send(.insertText("a"))
        send(.insertText("1"))
        drag((752, 604), (828, 558))
        send(.insertText("Should be $46.35"))
        send(.key(KeyInput(key: .escape)))
        send(.insertText("x"))
        drag((134, 251), (334, 281))
        return state
    }

    // MARK: Reference states

    private static func renderReference(state key: String, out: String, image path: String?, language: Language) {
        guard renderStates.contains(key) else {
            print("unknown state: \(key)\nstates: \(renderStates.joined(separator: ", "))")
            exit(64)
        }
        let picture = loadExampleImage(path)
        let stage = stage(of: picture)
        var state: CaptureState
        if key.hasPrefix("select") {
            state = CaptureState()
            state.stage = stage
            state.mode = .select
        } else {
            state = sampleState(stage: stage)
        }
        let area = sampleSelection
        switch key {
        case "select": state.cursor = NormPoint(x: 0.42, y: 0.38)
        case "select-drag": state.drag = Drag(x0: area.x, y0: area.y, x1: area.x + area.w, y1: area.y + area.h)
        case "annotate-empty": state.marks = []
        case "annotate-note", "annotate-note-empty": state.active = 2; state.noteMode = true; state.marks[1].note = key == "annotate-note" ? "Real sto" : ""
        case "annotate-selected": state.active = 1
        case "annotate-arrow-drag": state.tool = .arrow; state.intent = .bug; state.drag = Drag(x0: 0.5, y0: 0.2, x1: 0.42, y1: 0.33)
        case "annotate-crop": state.tool = .crop
        case "annotate-help": state.help = true
        default: break
        }
        let scene = OverlayScene(size: CGSize(width: stage.pointWidth, height: stage.pointHeight), scale: 2, language: language)
        scene.setImage(picture); scene.apply(state, isActive: true); CATransaction.flush()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info) else { print("cannot create bitmap context"); exit(1) }
        context.translateBy(x: 0, y: CGFloat(picture.height)); context.scaleBy(x: 2, y: -2); scene.root.render(in: context)
        guard let rendered = context.makeImage(), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil) else { print("cannot create PNG at \(out)"); exit(1) }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else { print("cannot write PNG at \(out)"); exit(1) }
    }

    // MARK: Self-test

    private static func selfTest(image path: String, out: String, language: Language) {
        let picture = loadExampleImage(path)
        let stage = stage(of: picture)
        let state = sampleState(stage: stage)

        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let json = Payload.json(state, imagePath: "~/.ainnotator/selftest.png", context: sampleContext, createdAt: Date(timeIntervalSince1970: 1793725361))
        try? json.write(toFile: out + "/payload.json", atomically: true, encoding: .utf8)
        print(json, terminator: "")

        let input = CardRenderer.Input(source: .image(picture), state: state, footer: Payload.contextLine(sampleContext) ?? "", language: language)
        if let png = CardRenderer.renderPNG(input) {
            try? png.write(to: URL(fileURLWithPath: out + "/card.png"))
            print("card.png \(png.count / 1024) KiB")
        }

        // Offscreen picture of the overlay in the same state.
        let scene = OverlayScene(size: CGSize(width: stage.pointWidth, height: stage.pointHeight), scale: 2, language: language)
        scene.setImage(picture)
        scene.apply(state, isActive: true)
        CATransaction.flush()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        if let context = CGContext(data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) {
            // The window server shows the flipped root upright; a bare bitmap context needs the flip spelled out.
            context.translateBy(x: 0, y: CGFloat(picture.height))
            context.scaleBy(x: 2, y: -2)
            scene.root.render(in: context)
            if let rendered = context.makeImage(), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out + "/overlay.png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, rendered, nil)
                CGImageDestinationFinalize(destination)
                print("overlay.png")
            }
        }
    }

    private static func renderReceipt(out: String, image path: String?, language: Language, remote: ReceiptRemote? = nil) {
        var model = sampleReceiptModel(image: loadExampleImage(path), language: language)
        model.remote = remote
        let view = ReceiptView(model: model, language: language)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("cannot create receipt bitmap"); exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { print("cannot encode receipt"); exit(1) }
        do { try data.write(to: URL(fileURLWithPath: out)); print("receipt.png \(data.count) B") }
        catch { print("cannot write receipt: \(error)"); exit(1) }
    }

    static func sampleReceiptModel(image picture: CGImage, language: Language = .en) -> ReceiptModel {
        let state = sampleState(stage: stage(of: picture))
        let area = sampleSelection
        let path = "~/.ainnotator/2026-11-14_1012.png"
        let text = NSHomeDirectory() + "/.ainnotator/2026-11-14_1012.png"
        guard let card = CardRenderer.render(.init(source: .image(picture), state: state, footer: Payload.contextLine(sampleContext) ?? "", language: language), previewWidth: 640) else { print("cannot render receipt card"); exit(1) }
        return ReceiptModel(text: text, card: card, width: Int((area.w * Double(picture.width)).rounded()), height: Int((area.h * Double(picture.height)).rounded()), pngPath: path, jsonPath: path.replacingOccurrences(of: ".png", with: ".json"), pngBytes: 0, jsonBytes: 0, marks: state.marks, time: Date(timeIntervalSince1970: 1793725361))
    }
}

/// The real hot path against its budgets: overlay 150 ms, pointer frame 8 ms, ⏎ 300 ms, idle footprint 30 MB. Run it on
/// an otherwise idle machine, other builds running at the same time distort the numbers.
final class Perf: NSObject {
    private var frame: CheckedContinuation<Void, Never>?
    private var link: CADisplayLink?

    func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("no screen capture grant for this process")
            return
        }
        let capture = ScreenCapture()
        var panels: [CGDirectDisplayID: OverlayPanel] = [:]
        let tPanels = now()
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            panels[id] = OverlayPanel(screen: screen) { _, _ in }
        }
        print(String(format: "panels created: %.1f ms for %d displays", ms(tPanels), panels.count))
        try? await capture.refreshDisplays()

        let location = NSEvent.mouseLocation
        let cursorScreen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.screens[0]
        let cursor = cursorScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID

        var first: [Double] = []
        var all: [Double] = []
        var lastCapture: CapturedDisplay?
        for round in 0..<8 {
            let t0 = now()
            guard let captured = try? await capture.capture(cursor), let panel = panels[cursor] else { continue }
            lastCapture = captured
            panel.scene.setImage(captured.surface)
            panel.scene.apply(CaptureState(), isActive: true)
            CATransaction.flush()
            panel.orderFrontRegardless()
            await nextFrame(on: panel.overlayView)
            let cursorMs = ms(t0)

            let others = panels.keys.filter { $0 != cursor }
            await withTaskGroup(of: CapturedDisplay?.self) { group in
                for id in others { group.addTask { try? await capture.capture(id) } }
                for await result in group {
                    guard let result, let other = panels[result.displayID] else { continue }
                    other.scene.setImage(result.surface)
                    other.scene.apply(CaptureState(), isActive: false)
                    CATransaction.flush()
                    other.orderFrontRegardless()
                }
            }
            CATransaction.flush()
            let allMs = ms(t0)
            print(String(format: "round %d: cursor display first frame %.1f ms, all displays %.1f ms", round, cursorMs, allMs))
            if round > 0 {
                first.append(cursorMs)
                all.append(allMs)
            }
            for other in panels.values {
                other.orderOut(nil)
                other.scene.setImage(nil)
            }
            CATransaction.flush()
            try? await Task.sleep(for: .milliseconds(350))
        }
        print("BUDGET overlay <= 150 ms | cursor display: " + stats(first) + " | all displays: " + stats(all))

        // Pointer frame: one reducer step plus layer update while selecting.
        if let captured = lastCapture, let panel = panels[cursor] {
            var state = CaptureState()
            _ = reduce(&state, .begin(captured.stage))
            // The app applies this state before the panel appears, so it belongs to the overlay time, not to the pointer.
            panel.scene.apply(state, isActive: true)
            CATransaction.flush()
            var steps: [Double] = []
            for i in 0..<240 {
                let t = now()
                _ = reduce(&state, .pointerMoved(NormPoint(x: Double(i) / 240, y: 0.5), inside: true))
                panel.scene.apply(state, isActive: true)
                CATransaction.flush()
                steps.append(ms(t))
            }
            let slowest = steps.indices.max { steps[$0] < steps[$1] } ?? 0
            print("BUDGET frame <= 8 ms | pointer step: " + stats(steps) + " | slowest is step \(slowest), without step 0: " + stats(Array(steps.dropFirst())))

            // ⏎: publish on a private pasteboard, then the export with a real surface.
            _ = reduce(&state, .pointerDown(NormPoint(x: 0.1, y: 0.1)))
            _ = reduce(&state, .pointerMoved(NormPoint(x: 0.9, y: 0.9), inside: true))
            _ = reduce(&state, .pointerUp)
            _ = reduce(&state, .pointerDown(NormPoint(x: 0.2, y: 0.2)))
            _ = reduce(&state, .pointerMoved(NormPoint(x: 0.6, y: 0.6), inside: true))
            _ = reduce(&state, .pointerUp)
            _ = reduce(&state, .insertText("Probe"))
            let pasteboard = NSPasteboard(name: .init("de.leonschwahn.ainnotator.perf"))
            let t = now()
            let clip = PendingClip(file: URL(fileURLWithPath: NSHomeDirectory() + "/.ainnotator/perf.png"))
            Clipboard.publish(clip, on: pasteboard)
            let publish = ms(t)
            let t2 = now()
            let input = CardRenderer.Input(source: .surface(captured.surface), state: state, footer: "perf")
            let bytes = await Task.detached(priority: .userInitiated) { CardRenderer.renderPNG(input)?.count ?? 0 }.value
            clip.fulfill(png: nil, saved: false)
            pasteboard.releaseGlobally()
            print(String(format: "BUDGET enter <= 300 ms | clipboard published %.2f ms | card+PNG %.0f ms, %d KiB (not saved)", publish, ms(t2), bytes / 1024))
        }

        for panel in panels.values { panel.close() }
        panels.removeAll()
        lastCapture = nil
        CATransaction.flush()
        try? await Task.sleep(for: .seconds(2))
        print(String(format: "BUDGET idle < 30 MB | footprint after sessions: %.1f MB", footprint()))
    }

    /// Does idling alone make the next capture slow? The second capture right after it is the warm comparison.
    func idle(waits: [Int]) async {
        let capture = ScreenCapture()
        let display = CGMainDisplayID()
        try? await capture.refreshDisplays()
        _ = try? await capture.capture(display)
        for wait in waits {
            try? await Task.sleep(for: .seconds(wait))
            let t1 = now()
            let firstOK = (try? await capture.capture(display)) != nil
            let first = ms(t1)
            let t2 = now()
            let secondOK = (try? await capture.capture(display)) != nil
            print(String(format: "after %d s idle: capture %.1f ms (ok %d), right after %.1f ms (ok %d)", wait, first, firstOK ? 1 : 0, ms(t2), secondOK ? 1 : 0))
            fflush(stdout)
        }
    }

    private func nextFrame(on view: NSView) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            frame = continuation
            let displayLink = view.displayLink(target: self, selector: #selector(tick))
            displayLink.add(to: .main, forMode: .common)
            link = displayLink
        }
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        displayLink.invalidate()
        link = nil
        frame?.resume()
        frame = nil
    }

    private func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    private func ms(_ t: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6 }

    private func stats(_ values: [Double]) -> String {
        let sorted = values.sorted()
        guard let last = sorted.last else { return "-" }
        return String(format: "p50 %.1f  max %.1f ms (n=%d)", sorted[sorted.count / 2], last, sorted.count)
    }

    private func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
