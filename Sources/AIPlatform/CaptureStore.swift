import Foundation

/// ~/.ainnotator: private folder, unique names, atomic writes, automatic retention.
public struct CaptureStore: Sendable {
    public let folder: URL

    public init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ainnotator")) {
        self.folder = folder
    }

    /// Reserves a base name `YYYY-MM-DD_HHmm`, with `_2`, `_3` on collision, by creating the empty file: the name is
    /// taken before the export has written anything. Returns the PNG location.
    public func reservePNG(now: Date = Date()) throws -> URL {
        try prepareFolder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let base = formatter.string(from: now)
        var candidate = folder.appendingPathComponent("\(base).png")
        var counter = 2
        while true {
            let descriptor = open(candidate.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
            if descriptor >= 0 {
                close(descriptor)
                return candidate
            }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            candidate = folder.appendingPathComponent("\(base)_\(counter).png")
            counter += 1
        }
    }

    /// Readers never see a partial file: the rename is atomic.
    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// After a failed export: a reservation or half a capture must not stay behind.
    public func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("json"))
    }

    /// The path as it appears in the payload: with `~`, short and without the user name.
    public static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    /// Deletes captures older than the retention period. Runs at launch and after each capture, never on a timer.
    public func removeExpired(days: Int = 7, now: Date = Date()) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else {
            return
        }
        let limit = now.addingTimeInterval(-Double(days) * 86_400)
        for item in items where ["png", "json"].contains(item.pathExtension) {
            let modified = try? item.resourceValues(forKeys: Set(keys)).contentModificationDate
            if let modified, modified < limit {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    private func prepareFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    }
}
