@preconcurrency import ScreenCaptureKit
import AICore
import CoreGraphics
import CoreMedia
import CoreVideo
import IOSurface

/// One frozen display. The surface goes straight into `CALayer.contents`, so nothing is copied on the way to the screen.
public struct CapturedDisplay: @unchecked Sendable {
    public let displayID: CGDirectDisplayID
    public let surface: IOSurfaceRef
    public let stage: Stage
}

public enum CaptureError: Error {
    case displayNotFound
    case noSurface
}

/// Display list is cached because fetching it costs 13–18 ms on every hotkey (measured).
public actor ScreenCapture {
    private var displays: [CGDirectDisplayID: SCDisplay] = [:]

    public init() {}

    public func refreshDisplays() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        displays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
    }

    public var displayIDs: [CGDirectDisplayID] { Array(displays.keys) }

    public func capture(_ id: CGDirectDisplayID) async throws -> CapturedDisplay {
        if displays[id] == nil { try await refreshDisplays() }
        guard let display = displays[id] else { throw CaptureError.displayNotFound }

        let scale = CGDisplayCopyDisplayMode(id).map { Double($0.pixelWidth) / Double($0.width) } ?? 2
        let config = SCStreamConfiguration()
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config)
        guard let buffer = CMSampleBufferGetImageBuffer(sample),
              let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else {
            throw CaptureError.noSurface
        }
        let stage = Stage(
            pixelWidth: IOSurfaceGetWidth(surface), pixelHeight: IOSurfaceGetHeight(surface),
            pointWidth: Double(display.width), pointHeight: Double(display.height)
        )
        return CapturedDisplay(displayID: id, surface: surface, stage: stage)
    }
}
