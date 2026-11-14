import AIPlatform
import AppKit
import Foundation
import Testing

private func privateBoard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("de.leonschwahn.ainnotator.test.\(UUID().uuidString)"))
}

private let file = URL(fileURLWithPath: "/Users/someone/.ainnotator/2026-11-14_1012.png")

/// The capture goes onto the clipboard the way Finder copies a file. A browser then hands a web page nothing but the
/// file, and a terminal pastes its path, which terminal coding assistants turn into an attached image; with image and
/// text side by side ChatGPT took the text (seen when pasting into each target by hand). The path is absolute because
/// `~` does not count as an image path for them.
@Test func theCaptureIsOneItemWithFileImageAndPath() throws {
    let board = privateBoard()
    defer { board.releaseGlobally() }
    let clip = PendingClip(file: file)
    clip.fulfill(png: Data([1, 2, 3]), saved: true)
    Clipboard.publish(clip, on: board)
    #expect(board.pasteboardItems?.map(\.types) == [[.fileURL, .png, .string]])
    #expect(board.string(forType: .string) == "/Users/someone/.ainnotator/2026-11-14_1012.png")
    #expect(board.data(forType: .png) == Data([1, 2, 3]))
    // The way the Ghostty terminal reads a pasted file: per item, the file URL first.
    let item = try #require(board.pasteboardItems?.first)
    let list = try #require(item.propertyList(forType: .fileURL))
    #expect(NSURL(pasteboardPropertyList: list, ofType: .fileURL)?.path == file.path)
    // The way AppKit targets and browsers read it.
    #expect(board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] == [file])
}

/// Nothing reaches a target before the file is readable. A paste during the export waits for it.
@Test func aPasteDuringTheExportWaitsForTheFile() {
    let board = privateBoard()
    defer { board.releaseGlobally() }
    let clip = PendingClip(file: file)
    Clipboard.publish(clip, on: board)
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { clip.fulfill(png: Data([1, 2, 3]), saved: true) }
    let started = Date()
    #expect(board.string(forType: .string) == file.path)
    #expect(Date().timeIntervalSince(started) >= 0.1)
    #expect(board.data(forType: .png) == Data([1, 2, 3]))
}

/// After a failed save there is no file, so nothing may point to it; the image itself stays pasteable.
@Test func aFailedSaveLeavesOnlyTheImage() {
    let board = privateBoard()
    defer { board.releaseGlobally() }
    let clip = PendingClip(file: file)
    Clipboard.publish(clip, on: board)
    clip.fulfill(png: Data([1, 2, 3]), saved: false)
    #expect(board.string(forType: .string) == nil)
    Clipboard.keepOnlyImage(of: clip, on: board)
    #expect(board.pasteboardItems?.map(\.types) == [[.png]])
    #expect(board.data(forType: .png) == Data([1, 2, 3]))
}

/// What the user copied in the meantime is theirs.
@Test func aFailedSaveLeavesANewerClipboardAlone() {
    let board = privateBoard()
    defer { board.releaseGlobally() }
    let clip = PendingClip(file: file)
    Clipboard.publish(clip, on: board)
    board.clearContents()
    board.setString("something else", forType: .string)
    clip.fulfill(png: Data([1, 2, 3]), saved: false)
    Clipboard.keepOnlyImage(of: clip, on: board)
    #expect(board.string(forType: .string) == "something else")
    #expect(board.data(forType: .png) == nil)
}

/// An export slower than the wait lets the path go out and the file follows, so a paste never blocks its target for long.
@Test func aPasteGivesThePathOnceTheWaitIsOver() {
    let board = privateBoard()
    defer { board.releaseGlobally() }
    let clip = PendingClip(file: file, timeout: 0.05)
    Clipboard.publish(clip, on: board)
    #expect(board.string(forType: .string) == file.path)
}
