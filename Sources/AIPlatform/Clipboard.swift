import AppKit

/// File, image and path are promises: all three reach a target only once the file is readable, because two of them
/// name that file. Pasting before the export is done waits briefly in the provider callback. The overlay is closed
/// by then.
public final class PendingClip: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let condition = NSCondition()
    private let file: URL
    private let timeout: TimeInterval
    /// Nil while the export runs.
    private var saved: Bool?
    private var png: Data?
    private var changeCount: Int?

    public init(file: URL, timeout: TimeInterval = 5) {
        self.file = file
        self.timeout = timeout
    }

    /// Called from the export. Without `saved` no file exists, and nothing names it any more.
    public func fulfill(png: Data?, saved: Bool) {
        condition.lock()
        self.png = png
        self.saved = saved
        condition.broadcast()
        condition.unlock()
    }

    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        condition.lock()
        let deadline = Date().addingTimeInterval(timeout)
        while saved == nil, condition.wait(until: deadline) {}
        // Still nil after the wait: the path goes out and the file follows, so a paste never blocks its target for long.
        let named = saved != false
        let png = self.png
        condition.unlock()

        if type == .fileURL, named {
            item.setString(file.absoluteString, forType: .fileURL)
        } else if type == .string, named {
            item.setString(file.path, forType: .string)
        } else if type == .png, let png {
            item.setData(png, forType: .png)
        }
    }

    fileprivate func published(as changeCount: Int) {
        condition.lock()
        self.changeCount = changeCount
        condition.unlock()
    }

    fileprivate var imageIfStillOurs: (changeCount: Int?, png: Data?) {
        condition.lock()
        defer { condition.unlock() }
        return (changeCount, png)
    }
}

public enum Clipboard {
    /// The target pasteboard. Self-tests pass a private one so the user's clipboard stays untouched.
    /// One item that is a file, the way Finder copies one: a browser then hands a web page nothing but the file, and a
    /// terminal pastes its path, which terminal coding assistants attach as an image. With image and text side by side
    /// the target chooses, and ChatGPT chose the text, whose path it cannot read (seen when pasting into each target by
    /// hand). The text is the path for terminals that read text only.
    public static func publish(_ clip: PendingClip, on pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setDataProvider(clip, forTypes: [.fileURL, .png, .string])
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        clip.published(as: pasteboard.changeCount)
    }

    /// After a failed save: a declared file without a file makes browsers offer nothing at all, so the pasteboard is
    /// rewritten with the image alone. Only while it is still ours; what the user copied since stays.
    public static func keepOnlyImage(of clip: PendingClip, on pasteboard: NSPasteboard = .general) {
        let (changeCount, png) = clip.imageIfStillOurs
        guard changeCount == pasteboard.changeCount else { return }
        pasteboard.clearContents()
        guard let png else { return }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        pasteboard.writeObjects([item])
    }
}
