import Foundation
import Testing
@testable import AIPlatform

private func withStore(_ body: (CaptureStore) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(CaptureStore(folder: folder))
}

/// Two exports in one minute, the second before the first has written: they must not share a name, or the older text
/// would point at the newer picture.
@Test func aReservationHoldsTheNameBeforeAnythingIsWritten() throws {
    try withStore { store in
        let now = Date()
        let first = try store.reservePNG(now: now)
        let second = try store.reservePNG(now: now)
        #expect(first != second)
        #expect(second.lastPathComponent.hasSuffix("_2.png"))
    }
}

@Test func aFinishedWriteReplacesTheReservation() throws {
    try withStore { store in
        let url = try store.reservePNG()
        try store.write(Data([1, 2, 3]), to: url)
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }
}

@Test func discardingRemovesTheCaptureAndItsSidecar() throws {
    try withStore { store in
        let url = try store.reservePNG()
        let sidecar = url.deletingPathExtension().appendingPathExtension("json")
        try store.write(Data([1]), to: sidecar)
        store.discard(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
    }
}
