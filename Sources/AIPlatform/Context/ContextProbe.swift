import AICore
import AppKit
@preconcurrency import ApplicationServices
import Darwin
import Foundation

/// Start on launch; take a snapshot before the capture UI becomes frontmost.
@MainActor public final class ContextProbe {
    private var lastTerminal: String?
    private var lastBrowser: String?
    private var observer: NSObjectProtocol?

    public init() {}

    public func startTracking() {
        guard observer == nil else { return }
        remember(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let bundle = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.remember(bundle) }
        }
    }

    private func remember(_ bundle: String?) {
        if let bundle, TerminalKind(bundle: bundle) != nil { lastTerminal = bundle }
    }

    public func snapshot() async -> CaptureContext {
        let front = NSWorkspace.shared.frontmostApplication
        let name = front?.localizedName
        let pid = front?.processIdentifier
        let browser = front?.bundleIdentifier.flatMap { browserScripts[$0] == nil ? nil : $0 }
        let terminal = lastTerminal
        lastBrowser = browser
        async let window: String? = bounded { pid.flatMap(windowTitle) }
        async let url: String? = bounded { browser.flatMap(browserURL) }
        async let git: GitContext? = bounded {
            guard let terminal, let tty = terminalTTY(terminal), let cwd = foregroundDirectory(tty) else { return nil }
            return GitContext.find(from: URL(fileURLWithPath: cwd, isDirectory: true))
        }
        let (title, address, repository) = await (window, url, git)
        return CaptureContext(app: name, window: title, url: address, repo: repository?.repo, branch: repository?.branch)
    }

    /// The machine the last used terminal tab is connected to through ssh, or nil. Reads nothing but that tab's
    /// foreground program and its arguments.
    public func remoteTarget() async -> RemoteTarget? {
        let terminal = lastTerminal
        return await bounded {
            guard let terminal, let tty = terminalTTY(terminal), let arguments = foregroundArguments(ofTTY: tty) else { return nil }
            return SSHCommand.target(fromArguments: arguments)
        }
    }

    /// macOS asks once per target and remembers the answer. Called after a capture, because the question would sit
    /// behind the overlay during one; until then URL and repository are simply left out.
    public func requestAutomationConsent() {
        let targets = [lastBrowser, lastTerminal.flatMap { terminalScripts[$0] == nil ? nil : $0 }].compactMap { $0 }
        DispatchQueue.global(qos: .utility).async {
            for target in targets { _ = automationStatus(target, ask: true) }
        }
    }

    isolated deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

enum TerminalKind: Sendable {
    case ghostty, terminal, iterm, warp
    init?(bundle: String) {
        switch bundle {
        case "com.mitchellh.ghostty": self = .ghostty
        case "com.apple.Terminal": self = .terminal
        case "com.googlecode.iterm2": self = .iterm
        case "dev.warp.Warp-Stable", "dev.warp.Warp-Preview": self = .warp
        default: return nil
        }
    }
}

// A timeout resumes the caller even if an OS service or permission dialog stalls.
private final class Once<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    init(_ continuation: CheckedContinuation<Value?, Never>) { self.continuation = continuation }
    func finish(_ value: Value?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

private func bounded<Value: Sendable>(_ work: @escaping @Sendable () -> Value?) async -> Value? {
    await withCheckedContinuation { continuation in
        let once = Once(continuation)
        DispatchQueue.global(qos: .userInitiated).async { once.finish(work()) }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) { once.finish(nil) }
    }
}

private func windowTitle(_ pid: pid_t) -> String? {
    guard AXIsProcessTrusted() else { return nil }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.3)
    var window: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
          let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
    let element = window as! AXUIElement
    AXUIElementSetMessagingTimeout(element, 0.3)
    var title: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success,
          let value = title as? String, !value.isEmpty else { return nil }
    return value
}

private let browserScripts = [
    "com.apple.Safari": "tell application id \"com.apple.Safari\" to get URL of front document",
    "com.google.Chrome": "tell application id \"com.google.Chrome\" to get URL of active tab of front window",
    "company.thebrowser.Browser": "tell application id \"company.thebrowser.Browser\" to get URL of active tab of front window",
]

// Warp does not expose a documented per-pane TTY through AppleScript, so it has no entry.
private let terminalScripts = [
    "com.mitchellh.ghostty": "tell application id \"com.mitchellh.ghostty\" to get tty of focused terminal of selected tab of front window",
    "com.apple.Terminal": "tell application id \"com.apple.Terminal\" to get tty of selected tab of front window",
    "com.googlecode.iterm2": "tell application id \"com.googlecode.iterm2\" to get tty of current session of current window",
]

private func automationStatus(_ bundle: String, ask: Bool) -> OSStatus {
    var target = AEAddressDesc()
    let status = bundle.withCString { AECreateDesc(DescType(typeApplicationBundleID), $0, bundle.utf8.count, &target) }
    guard status == noErr else { return OSStatus(status) }
    defer { AEDisposeDesc(&target) }
    return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
}

/// A child process because NSAppleScript is main-thread only, and this must never run there. It is attributed to
/// this app, so the permission asked for in `requestAutomationConsent` applies.
private func runScript(_ source: String, target: String) -> String? {
    guard automationStatus(target, ask: false) == noErr else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do { try process.run() } catch { return nil }
    guard finished.wait(timeout: .now() + .milliseconds(450)) == .success else {
        process.terminate()
        return nil
    }
    guard process.terminationStatus == 0 else { return nil }
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty || text == "missing value" ? nil : text
}

private func browserURL(_ bundle: String) -> String? {
    browserScripts[bundle].flatMap { runScript($0, target: bundle) }
}

private func terminalTTY(_ bundle: String) -> String? {
    terminalScripts[bundle].flatMap { runScript($0, target: bundle) }
}

private func foregroundDirectory(_ rawTTY: String) -> String? {
    guard let pid = foregroundPID(ofTTY: rawTTY) else { return nil }
    var path = proc_vnodepathinfo()
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &path, Int32(MemoryLayout<proc_vnodepathinfo>.size)) == MemoryLayout<proc_vnodepathinfo>.size else { return nil }
    return withUnsafeBytes(of: path.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
}

func foregroundPID(ofTTY rawTTY: String) -> pid_t? {
    foregroundProcesses(ofTTY: rawTTY).flatMap(foregroundLeader)
}

/// The processes on a terminal's tty, each with its group and the group that is in the foreground.
func foregroundProcesses(ofTTY rawTTY: String) -> [TTYProcess]? {
    let tty = rawTTY.hasPrefix("/dev/") ? String(rawTTY.dropFirst(5)) : rawTTY
    guard tty.hasPrefix("tty"), !tty.contains("/") else { return nil }
    var device = stat()
    guard stat("/dev/" + tty, &device) == 0 else { return nil }
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, device.st_rdev]
    for attempt in 0..<2 {
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0,
              size % MemoryLayout<kinfo_proc>.stride == 0 else { return nil }
        var records = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        let capacity = size
        let status = records.withUnsafeMutableBytes { sysctl(&mib, 4, $0.baseAddress, &size, nil, 0) }
        if status != 0 {
            if errno == ENOMEM && attempt == 0 { continue }
            return nil
        }
        guard size <= capacity, size % MemoryLayout<kinfo_proc>.stride == 0 else { return nil }
        return records.prefix(size / MemoryLayout<kinfo_proc>.stride).map {
            TTYProcess(pid: $0.kp_proc.p_pid, group: $0.kp_eproc.e_pgid, foreground: $0.kp_eproc.e_tpgid)
        }
    }
    return nil
}

struct TTYProcess: Sendable {
    let pid: pid_t
    let group: pid_t
    let foreground: pid_t
}

/// Every process of the foreground group, its leader first.
func foregroundGroup(_ processes: [TTYProcess]) -> [pid_t] {
    let members = processes.filter { $0.foreground > 0 && $0.group == $0.foreground }.map(\.pid)
    guard let leader = foregroundLeader(processes) else { return members }
    return [leader] + members.filter { $0 != leader }
}

func foregroundLeader(_ processes: [TTYProcess]) -> pid_t? {
    processes.first { $0.foreground > 0 && $0.pid == $0.foreground && $0.group == $0.foreground }?.pid
}
