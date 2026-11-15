import Foundation
import Testing
@testable import AICore
import AIPlatform

private struct RemoteCopyFixture {
    let directory: URL
    let script: URL
    let file: URL
    let target = RemoteTarget(arguments: ["-p", "2200", "devbox"])

    init(scriptBody: String, fileName: String = "2026-11-15_1300.png", contents: Data = Data([0, 1, 2, 255])) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        script = directory.appendingPathComponent("ssh")
        file = directory.appendingPathComponent(fileName)
        try contents.write(to: file)
        try ("#!/bin/sh\n" + scriptBody + "\n").write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    // A generous limit: starting a script that was written a moment ago can take seconds on a busy machine.
    func copy(timeout: TimeInterval = 20, days: Int = 7) -> Result<String, RemoteCopyError> {
        RemoteCopier(ssh: script, timeout: timeout).copy(file, to: target, retentionDays: days)
    }
}

@Test func remoteCopyPassesArgumentsAndFileContents() throws {
    let contents = Data((0..<262_144).map { UInt8(truncatingIfNeeded: $0) })
    let fixture = try RemoteCopyFixture(scriptBody: """
        dir="$(dirname "$0")"
        printf '%s\\n' "$@" > "$dir/arguments"
        cat > "$dir/input"
        printf '/home/user/.ainnotator/2026-11-15_1300.png\\nignored\\n'
        """, contents: contents)
    defer { fixture.cleanUp() }
    #expect(fixture.copy(timeout: 10.5) == .success("/home/user/.ainnotator/2026-11-15_1300.png"))
    let arguments = try String(contentsOf: fixture.directory.appendingPathComponent("arguments"), encoding: .utf8)
        .split(separator: "\n").map(String.init)
    let command = """
        sh -c 'umask 077; d="$HOME/.ainnotator"; f="$d/2026-11-15_1300.png"; mkdir -p "$d" || exit 1; if [ ! -e "$f" ]; then cat > "$d/.2026-11-15_1300.png.part" && mv "$d/.2026-11-15_1300.png.part" "$f" || { rm -f "$d/.2026-11-15_1300.png.part"; exit 1; }; fi; find "$d" -maxdepth 1 -type f -name "*.png" -mtime +7 -exec rm -f {} +; printf "%s\\n" "$f"'
        """
    #expect(arguments == ["-o", "BatchMode=yes", "-o", "ConnectTimeout=11", "-T", "-p", "2200", "devbox", command])
    #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("input")) == contents)
}

@Test(arguments: [(-1, 1), (1, 1), (365, 365), (999, 365)])
func remoteCopyClampsRetention(input: Int, expected: Int) throws {
    let fixture = try RemoteCopyFixture(scriptBody: """
        printf '%s\\n' "$@" > "$(dirname "$0")/arguments"
        printf '/home/user/.ainnotator/2026-11-15_1300.png\\n'
        """)
    defer { fixture.cleanUp() }
    #expect(fixture.copy(days: input) == .success("/home/user/.ainnotator/2026-11-15_1300.png"))
    let arguments = try String(contentsOf: fixture.directory.appendingPathComponent("arguments"), encoding: .utf8)
    #expect(arguments.contains("-mtime +\(expected) -exec"))
}

@Test func remoteCopyReportsExitStatus() throws {
    let fixture = try RemoteCopyFixture(scriptBody: "exit 255")
    defer { fixture.cleanUp() }
    #expect(fixture.copy() == .failure(.failed(255)))
}

@Test func remoteCopyStopsAtTimeout() throws {
    let fixture = try RemoteCopyFixture(scriptBody: "exec /bin/sleep 10")
    defer { fixture.cleanUp() }
    let start = Date()
    #expect(fixture.copy(timeout: 0.5) == .failure(.timedOut))
    #expect(Date().timeIntervalSince(start) < 3)
}

@Test(arguments: ["", "/home/user/.ainnotator/other.png", "relative/2026-11-15_1300.png", "\n/home/user/.ainnotator/2026-11-15_1300.png"])
func remoteCopyRequiresAnAbsolutePathOnTheFirstLine(output: String) throws {
    let fixture = try RemoteCopyFixture(scriptBody: "printf '%s' '\(output)'")
    defer { fixture.cleanUp() }
    #expect(fixture.copy() == .failure(.noPath))
}

@Test func remoteCopyRejectsUnsafeNamesWithoutStartingProcess() throws {
    let fixture = try RemoteCopyFixture(scriptBody: "touch \"$(dirname \"$0\")/started\"", fileName: "bad name.png")
    defer { fixture.cleanUp() }
    #expect(fixture.copy() == .failure(.unavailable))
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("started").path))
}

@Test func remoteCopyReportsMissingSSH() throws {
    let fixture = try RemoteCopyFixture(scriptBody: "exit 0")
    defer { fixture.cleanUp() }
    let copier = RemoteCopier(ssh: fixture.directory.appendingPathComponent("missing"))
    #expect(copier.copy(fixture.file, to: fixture.target, retentionDays: 7) == .failure(.unavailable))
}

/// The command that runs on the other machine, run here with a temporary folder as its home. Where both machines
/// share a home folder, or the target is this Mac itself, the capture already lies at the target path: it must stay
/// what it is and must not be emptied by a copy onto itself.
@Test func theRemoteCommandNeverOverwritesAnExistingCapture() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: home) }
    // Stands in for ssh: runs the last argument, the remote command, with that folder as HOME.
    let fixture = try RemoteCopyFixture(scriptBody: """
        for last; do :; done
        HOME='\(home.path)' /bin/sh -c "$last"
        """, contents: Data([9, 8, 7]))
    defer { fixture.cleanUp() }
    let target = home.appendingPathComponent(".ainnotator/2026-11-15_1300.png")

    // First copy: the file arrives, private, and the path is reported.
    #expect(fixture.copy() == .success(target.path))
    #expect(try Data(contentsOf: target) == Data([9, 8, 7]))
    let mode = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)

    // The same name again, with other content on the way: what lies there stays.
    try Data([1, 1, 1, 1]).write(to: fixture.file)
    #expect(fixture.copy() == .success(target.path))
    #expect(try Data(contentsOf: target) == Data([9, 8, 7]))
    #expect(try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".ainnotator").path) == ["2026-11-15_1300.png"])
}
