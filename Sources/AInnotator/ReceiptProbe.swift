import AICore
import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// `--receipt-probe <out-dir>`: shows the real receipt with sample data, photographs only its own windows and presses
/// its buttons. The real panels render text differently from an offscreen bitmap, and the release order of a closing
/// panel only shows up here.
enum ReceiptProbe {
    static func run(out: String, image: CGImage, language: Language = .en) async {
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        var newCount = 0
        var closeCount = 0
        var panel: ReceiptPanel? = ReceiptPanel(model: DevCommands.sampleReceiptModel(image: image, language: language), language: language) { newCount += 1 }
        panel?.onClose = {
            closeCount += 1
            // Same as the controller: the owner lets go while the panel is closing.
            panel = nil
        }
        guard let shown = panel else { return }
        let window = shown.windowNumber
        shown.show(on: NSScreen.main)
        try? await Task.sleep(for: .milliseconds(400))
        await photograph(window, to: out + "/panel.png")

        shown.pressNew()
        print("new pressed: \(newCount) times, closed: \(closeCount) times")
        try? await Task.sleep(for: .milliseconds(100))
    }

    static func photograph(_ windowNumber: Int, to path: String) async {
        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { Int($0.windowID) == windowNumber }) else {
                print("window \(windowNumber) not listed")
                return
            }
            guard let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) else {
                print("no display for window frame \(window.frame), displays \(content.displays.map(\.frame))")
                return
            }
            // The display filter with only this window: nothing else on the screen ends up in the picture.
            let filter = SCContentFilter(display: display, including: [window])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: window.frame.minX - display.frame.minX, y: window.frame.minY - display.frame.minY, width: window.frame.width, height: window.frame.height)
            configuration.width = Int(window.frame.width) * 2
            configuration.height = Int(window.frame.height) * 2
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image, nil)
            print("photographed \(path): \(CGImageDestinationFinalize(destination))")
        } catch {
            print("photograph failed: \(error)")
        }
    }
}
