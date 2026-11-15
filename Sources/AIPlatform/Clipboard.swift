import AppKit

/// File, image and path are promises: all three reach a target only once the file is readable, because two of them
/// name that file. Pasting before the export is done waits briefly in the provider callback. The overlay is closed
/// by then.
public final class PendingClip: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    /// How the capture lies on the clipboard.
    public enum Form: Sendable {
        /// A file, the way Finder copies one: file, image, and the local path as text.
        case file
        /// For a terminal that is connected to another machine: the image, and as text the path of the copy on that
        /// machine. No file, because a terminal would paste the local path of a file it is given.
        case remote
    }

    private let condition = NSCondition()
    private let file: URL
    private let timeout: TimeInterval
    /// Nil while the export runs.
    private var saved: Bool?
    private var png: Data?
    private var changeCount: Int?
    private var form = Form.file
    /// A copy to another machine: not asked for, running, or over (with the path there, or nil when it failed).
    private var remote = Remote.none
    private enum Remote { case none, running, done(String?) }

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

    /// A copy to another machine has begun. Until it is over, a paste of the remote form waits for its path.
    public func expectRemote() {
        condition.lock()
        remote = .running
        condition.unlock()
    }

    /// The copy is over. `path` is where the capture lies on the other machine, or nil when the copy failed.
    public func fulfillRemote(path: String?) {
        condition.lock()
        remote = .done(path)
        condition.broadcast()
        condition.unlock()
    }

    /// The path on the other machine, once the copy has succeeded.
    public var remotePath: String? {
        condition.lock()
        defer { condition.unlock() }
        if case .done(let path) = remote { return path }
        return nil
    }

    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        // The item itself says which form it is: only the file form declares a file.
        let asFile = item.types.contains(.fileURL)
        condition.lock()
        let deadline = Date().addingTimeInterval(timeout)
        while saved == nil, condition.wait(until: deadline) {}
        if !asFile, type == .string {
            while case .running = remote, condition.wait(until: deadline) {}
        }
        // Still nil after the wait: the path goes out and the file follows, so a paste never blocks its target for long.
        let named = saved != false
        let png = self.png
        var remotePath: String?
        if case .done(let path) = remote { remotePath = path }
        condition.unlock()

        if type == .fileURL, named {
            item.setString(file.absoluteString, forType: .fileURL)
        } else if type == .string, asFile, named {
            item.setString(file.path, forType: .string)
        } else if type == .string, !asFile, let remotePath {
            // Without a copy on the other machine there is no path that would mean anything there.
            item.setString(remotePath, forType: .string)
        } else if type == .png, let png {
            item.setData(png, forType: .png)
        }
    }

    fileprivate func published(as changeCount: Int, form: Form) {
        condition.lock()
        self.changeCount = changeCount
        self.form = form
        condition.unlock()
    }

    fileprivate var state: (changeCount: Int?, form: Form, png: Data?) {
        condition.lock()
        defer { condition.unlock() }
        return (changeCount, form, png)
    }
}

public enum Clipboard {
    /// The target pasteboard. Self-tests pass a private one so the user's clipboard stays untouched.
    /// One item that is a file, the way Finder copies one: a browser then hands a web page nothing but the file, and a
    /// terminal pastes its path, which terminal coding assistants attach as an image. With image and text side by side
    /// the target chooses, and ChatGPT chose the text, whose path it cannot read (seen when pasting into each target by
    /// hand). The text is the path for terminals that read text only.
    public static func publish(_ clip: PendingClip, form: PendingClip.Form = .file, on pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setDataProvider(clip, forTypes: form == .file ? [.fileURL, .png, .string] : [.png, .string])
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        clip.published(as: pasteboard.changeCount, form: form)
    }

    /// Puts the same capture on the clipboard in the other form, for the target that is in front now. Only while the
    /// clipboard is still this capture's; what the user copied since stays. Returns whether the form changed.
    @discardableResult
    public static func switchForm(of clip: PendingClip, to form: PendingClip.Form, on pasteboard: NSPasteboard = .general) -> Bool {
        let state = clip.state
        guard state.changeCount == pasteboard.changeCount, state.form != form else { return false }
        publish(clip, form: form, on: pasteboard)
        return true
    }

    /// After a failed save: a declared file without a file makes browsers offer nothing at all, so the pasteboard is
    /// rewritten with the image alone. Only while it is still ours; what the user copied since stays.
    public static func keepOnlyImage(of clip: PendingClip, on pasteboard: NSPasteboard = .general) {
        let state = clip.state
        guard state.changeCount == pasteboard.changeCount else { return }
        pasteboard.clearContents()
        guard let png = state.png else { return }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        pasteboard.writeObjects([item])
    }
}
