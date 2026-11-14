import Foundation

struct GitContext: Equatable, Sendable {
    let repo: String
    let branch: String?

    static func find(from directory: URL) -> GitContext? {
        let files = FileManager.default
        var current = directory.standardizedFileURL.resolvingSymlinksInPath()
        while true {
            let marker = current.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if files.fileExists(atPath: marker.path, isDirectory: &isDirectory) {
                let gitDir: URL
                if isDirectory.boolValue {
                    gitDir = marker
                } else {
                    guard let content = try? String(contentsOf: marker, encoding: .utf8),
                          content.hasPrefix("gitdir: ") else { return nil }
                    let path = content.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !path.isEmpty else { return nil }
                    gitDir = resolve(path, relativeTo: current)
                }
                guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty else { return nil }
                let commonFile = gitDir.appendingPathComponent("commondir")
                let commonDir: URL
                if let common = try? String(contentsOf: commonFile, encoding: .utf8) {
                    let path = common.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !path.isEmpty else { return nil }
                    commonDir = resolve(path, relativeTo: gitDir)
                } else {
                    commonDir = gitDir
                }
                let repo = commonDir.lastPathComponent == ".git"
                    ? commonDir.deletingLastPathComponent().lastPathComponent : current.lastPathComponent
                let branch: String?
                if head.hasPrefix("ref: refs/heads/") {
                    let name = String(head.dropFirst("ref: refs/heads/".count))
                    branch = name.isEmpty ? nil : name
                } else if (head.count == 40 || head.count == 64), head.allSatisfy({ $0.isHexDigit }) {
                    branch = String(head.prefix(7))
                } else {
                    branch = nil
                }
                return GitContext(repo: repo, branch: branch)
            }
            // Standardized: the parent of the root is "/../", which would never compare equal and loop forever.
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    private static func resolve(_ path: String, relativeTo base: URL) -> URL {
        (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path))
            .standardizedFileURL.resolvingSymlinksInPath()
    }
}
