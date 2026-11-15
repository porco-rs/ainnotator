import Foundation
import Testing
@testable import AIPlatform

@Test func readsChildArgumentsUntilExit() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    let args = ["-c", "read line", "known-label", "with spaces", "", "ümlaut"]
    process.arguments = args
    let input = Pipe()
    process.standardInput = input
    try process.run()
    let pid = process.processIdentifier
    defer {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? input.fileHandleForWriting.close()
    }
    #expect(arguments(ofPID: pid) == ["/bin/sh"] + args)
    process.terminate()
    process.waitUntilExit()
    #expect(arguments(ofPID: pid) == nil)
}

@Test func invalidForegroundProcessInputs() {
    #expect(arguments(ofPID: 0) == nil)
    #expect(foregroundArguments(ofTTY: "../invalid") == nil)
}

/// Ghostty starts ssh through a helper of its own: the helper leads the foreground group and the ssh client is its
/// child. Seen in a real tab: the leader was "ghostty +ssh -- …", and the target was not found.
@Test func theSSHClientIsFoundBehindATerminalsOwnHelper() {
    let processes = [
        TTYProcess(pid: 10, group: 10, foreground: 20),
        TTYProcess(pid: 21, group: 20, foreground: 20),
        TTYProcess(pid: 20, group: 20, foreground: 20),
    ]
    let table: [pid_t: [String]] = [
        10: ["-zsh"],
        20: ["/Applications/Ghostty.app/Contents/MacOS/ghostty", "+ssh", "--", "-F", "/tmp/c", "devbox"],
        21: ["ssh", "-o", "ControlMaster=yes", "-o", "ControlPersist=no", "-o", "ControlPath=/tmp/sock", "-F", "/tmp/c", "devbox"],
    ]
    #expect(foregroundArguments(of: processes) { table[$0] } == table[21])
    #expect(foregroundGroup(processes) == [20, 21])
}

/// With a jump host a second ssh runs in the same group and only forwards; the session is the other one.
@Test func theSessionWinsOverTheForwardingClientOfAJumpHost() {
    let processes = [
        TTYProcess(pid: 31, group: 30, foreground: 30),
        TTYProcess(pid: 30, group: 30, foreground: 30),
    ]
    let table: [pid_t: [String]] = [
        30: ["ssh", "-J", "jump", "devbox"],
        31: ["ssh", "-W", "[devbox]:22", "jump"],
    ]
    #expect(foregroundArguments(of: processes) { table[$0] } == table[30])
}

/// Without any ssh client the leader's arguments are returned, as before.
@Test func withoutAnSSHClientTheLeaderOfTheGroupIsReturned() {
    let processes = [
        TTYProcess(pid: 41, group: 40, foreground: 40),
        TTYProcess(pid: 40, group: 40, foreground: 40),
    ]
    let table: [pid_t: [String]] = [40: ["vim", "notes.txt"], 41: ["git", "status"]]
    #expect(foregroundArguments(of: processes) { table[$0] } == ["vim", "notes.txt"])
    #expect(foregroundArguments(of: []) { table[$0] } == nil)
}
