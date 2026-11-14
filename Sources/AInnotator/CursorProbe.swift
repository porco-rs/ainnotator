import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// Answers without a human whether the app can hide or replace the cursor while it stays inactive: it captures the area
/// around the pointer with and without the cursor. Equal pixels mean the cursor is not drawn. Nothing is saved.
enum CursorProbe {
    static func run() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("no screen capture grant for this process")
            return
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == id }) else { return }

        // A process started from a terminal is active at first; after a hotkey the real app is not.
        NSApp.deactivate()
        try? await Task.sleep(for: .milliseconds(200))
        print("before panel: app active: \(NSApp.isActive), frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")

        let panel = OverlayPanel(screen: screen) { _, _ in }
        guard let frozen = try? await grab(display, cursor: false, around: nil) else { return }
        panel.scene.setImage(frozen)
        panel.scene.apply(.init(), isActive: true)
        CATransaction.flush()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.overlayView)
        try? await Task.sleep(for: .milliseconds(120))

        let pixelPoint = CGPoint(x: location.x - screen.frame.minX, y: screen.frame.maxY - location.y)
        print("panel open: app active: \(NSApp.isActive), key window: \(panel.isKeyWindow), frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        print("cursor drawn, panel only: \(await cursorDrawn(display, around: pixelPoint))")

        NSCursor.hide()
        try? await Task.sleep(for: .milliseconds(120))
        print("after NSCursor.hide: drawn=\(await cursorDrawn(display, around: pixelPoint))")
        NSCursor.unhide()

        CGDisplayHideCursor(id)
        try? await Task.sleep(for: .milliseconds(120))
        print("after CGDisplayHideCursor: drawn=\(await cursorDrawn(display, around: pixelPoint))")
        CGDisplayShowCursor(id)

        NSCursor.crosshair.set()
        try? await Task.sleep(for: .milliseconds(120))
        print("after crosshair.set: current is crosshair=\(NSCursor.current == NSCursor.crosshair), system hotspot=\(NSCursor.currentSystem?.hotSpot ?? .zero)")
        NSCursor.arrow.set()

        panel.orderOut(nil)
        CATransaction.flush()
        try? await Task.sleep(for: .milliseconds(150))
        print("panel closed: app active: \(NSApp.isActive), frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
    }

    private static func cursorDrawn(_ display: SCDisplay, around point: CGPoint) async -> String {
        guard let with = try? await grab(display, cursor: true, around: point),
              let without = try? await grab(display, cursor: false, around: point) else { return "capture failed" }
        return difference(with, without) > 0 ? "yes" : "no"
    }

    private static func grab(_ display: SCDisplay, cursor: Bool, around point: CGPoint?) async throws -> IOSurfaceRef {
        let config = SCStreamConfiguration()
        config.showsCursor = cursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        if let point {
            config.sourceRect = CGRect(x: max(point.x - 24, 0), y: max(point.y - 24, 0), width: 48, height: 48)
            config.width = 96
            config.height = 96
        } else {
            let scale = CGDisplayCopyDisplayMode(display.displayID).map { Double($0.pixelWidth) / Double($0.width) } ?? 2
            config.width = Int(Double(display.width) * scale)
            config.height = Int(Double(display.height) * scale)
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config)
        guard let buffer = CMSampleBufferGetImageBuffer(sample), let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else {
            throw CocoaError(.featureUnsupported)
        }
        return surface
    }

    private static func difference(_ a: IOSurfaceRef, _ b: IOSurfaceRef) -> Int {
        IOSurfaceLock(a, .readOnly, nil)
        IOSurfaceLock(b, .readOnly, nil)
        defer {
            IOSurfaceUnlock(a, .readOnly, nil)
            IOSurfaceUnlock(b, .readOnly, nil)
        }
        let height = min(IOSurfaceGetHeight(a), IOSurfaceGetHeight(b))
        let width = min(IOSurfaceGetWidth(a), IOSurfaceGetWidth(b))
        var changed = 0
        for y in 0..<height {
            let rowA = IOSurfaceGetBaseAddress(a).advanced(by: y * IOSurfaceGetBytesPerRow(a)).assumingMemoryBound(to: UInt32.self)
            let rowB = IOSurfaceGetBaseAddress(b).advanced(by: y * IOSurfaceGetBytesPerRow(b)).assumingMemoryBound(to: UInt32.self)
            for x in 0..<width where rowA[x] != rowB[x] { changed += 1 }
        }
        return changed
    }
}
