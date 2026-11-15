import AICore
import Foundation

public enum RemoteCopyError: Error, Equatable, Sendable {
    /// The ssh client could not be started.
    case unavailable
    /// No answer within the time limit.
    case timedOut
    /// ssh ended with this status (255: no connection, or no login without asking).
    case failed(Int32)
    /// The remote side did not report where it put the file.
    case noPath
}

/// Puts a capture on the machine a terminal tab is connected to, through the user's own ssh setup. It never asks
/// the user anything: a login that needs a password or a confirmation fails, and the capture stays local.
public struct RemoteCopier: Sendable {
    public let ssh: URL
    public let timeout: TimeInterval

    public init(ssh: URL = URL(fileURLWithPath: "/usr/bin/ssh"), timeout: TimeInterval = 4) {
        self.ssh = ssh
        self.timeout = timeout
    }

    /// Copies `file` into the private folder `~/.ainnotator` on the target and returns its absolute path there. The
    /// same call removes this app's own captures older than `retentionDays` from that folder. Blocks until done or
    /// until the time limit; call it off the main thread.
    public func copy(_ file: URL, to target: RemoteTarget, retentionDays: Int) -> Result<String, RemoteCopyError> {
        let name = file.lastPathComponent
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return .failure(.unavailable)
        }

        let days = min(365, max(1, retentionDays))
        // The file is written under another name first and never over an existing one: where both machines share
        // a home folder, or the target is this Mac itself, the capture already lies there and stays untouched.
        let command = """
        sh -c 'umask 077; d="$HOME/.ainnotator"; f="$d/\(name)"; mkdir -p "$d" || exit 1; if [ ! -e "$f" ]; then cat > "$d/.\(name).part" && mv "$d/.\(name).part" "$f" || { rm -f "$d/.\(name).part"; exit 1; }; fi; find "$d" -maxdepth 1 -type f -name "*.png" -mtime +\(days) -exec rm -f {} +; printf "%s\\n" "$f"'
        """

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let outputURL = directory.appendingPathComponent("output")
            guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
                return .failure(.unavailable)
            }
            let output = try FileHandle(forUpdating: outputURL)
            defer { try? output.close() }

            let process = Process()
            process.executableURL = ssh
            process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=\(String(format: "%.0f", ceil(timeout)))", "-T"]
                + target.arguments + [command]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()

            guard finished.wait(timeout: .now() + max(0, timeout)) == .success else {
                if process.isRunning { process.terminate() }
                return .failure(.timedOut)
            }
            guard process.terminationStatus == 0 else {
                return .failure(.failed(process.terminationStatus))
            }
            try output.seek(toOffset: 0)
            guard let data = try output.readToEnd(),
                  let path = String(data: data.prefix(while: { $0 != 10 }), encoding: .utf8),
                  path.hasPrefix("/"), path.hasSuffix("/\(name)") else {
                return .failure(.noPath)
            }
            return .success(path)
        } catch {
            return .failure(.unavailable)
        }
    }
}
