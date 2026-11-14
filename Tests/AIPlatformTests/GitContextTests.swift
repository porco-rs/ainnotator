import Foundation
import Testing
@testable import AIPlatform

private func withDirectory(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

private func directory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}
private func write(_ text: String, _ url: URL) throws {
    try text.write(to: url, atomically: true, encoding: .utf8)
}

@Test func normalRepository() throws {
    try withDirectory { root in
        let repo = root.appendingPathComponent("project"), git = repo.appendingPathComponent(".git")
        let nested = repo.appendingPathComponent("src/nested")
        try directory(git); try directory(nested)
        try write("ref: refs/heads/feature/example\n", git.appendingPathComponent("HEAD"))
        #expect(GitContext.find(from: nested) == GitContext(repo: "project", branch: "feature/example"))
    }
}

@Test func linkedWorktreeUsesMainRepositoryName() throws {
    try withDirectory { root in
        let main = root.appendingPathComponent("main-repo/.git")
        let metadata = main.appendingPathComponent("worktrees/other")
        let worktree = root.appendingPathComponent("checkout")
        try directory(metadata); try directory(worktree)
        try write("gitdir: ../main-repo/.git/worktrees/other\n", worktree.appendingPathComponent(".git"))
        try write("../..\n", metadata.appendingPathComponent("commondir"))
        try write("ref: refs/heads/topic\n", metadata.appendingPathComponent("HEAD"))
        #expect(GitContext.find(from: worktree) == GitContext(repo: "main-repo", branch: "topic"))
    }
}

@Test func detachedHead() throws {
    try withDirectory { root in
        let repo = root.appendingPathComponent("project"), git = repo.appendingPathComponent(".git")
        try directory(git)
        try write("0123456789abcdef0123456789abcdef01234567\n", git.appendingPathComponent("HEAD"))
        #expect(GitContext.find(from: repo) == GitContext(repo: "project", branch: "0123456"))
    }
}

@Test func outsideRepository() throws {
    try withDirectory { root in
        let nested = root.appendingPathComponent("no/repo")
        try directory(nested)
        #expect(GitContext.find(from: nested) == nil)
    }
}

@Test func selectsForegroundGroupLeaderInsteadOfShell() {
    let records = [
        TTYProcess(pid: 10, group: 10, foreground: 20),
        TTYProcess(pid: 21, group: 20, foreground: 20),
        TTYProcess(pid: 20, group: 20, foreground: 20),
    ]
    #expect(foregroundLeader(records) == 20)
    #expect(foregroundLeader(Array(records.prefix(2))) == nil)
}

@Test func recognizedTerminals() {
    #expect(TerminalKind(bundle: "com.mitchellh.ghostty") == .ghostty)
    #expect(TerminalKind(bundle: "com.apple.Terminal") == .terminal)
    #expect(TerminalKind(bundle: "com.googlecode.iterm2") == .iterm)
    #expect(TerminalKind(bundle: "dev.warp.Warp-Stable") == .warp)
    #expect(TerminalKind(bundle: "unknown") == nil)
}
