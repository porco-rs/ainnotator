import AICore
import Darwin
import Foundation

/// The argument vector of the program in the foreground of a terminal's tty (program name first), or nil when the
/// tty has no foreground program or its arguments cannot be read.
func foregroundArguments(ofTTY rawTTY: String) -> [String]? {
    guard let processes = foregroundProcesses(ofTTY: rawTTY) else { return nil }
    return foregroundArguments(of: processes, arguments: arguments(ofPID:))
}

/// A terminal may start ssh through a helper of its own, which then leads the foreground group with the ssh
/// client as its child; a jump host adds a second ssh that only forwards. The client that is a session with a
/// machine wins; without one, the leader of the group.
func foregroundArguments(of processes: [TTYProcess], arguments: (pid_t) -> [String]?) -> [String]? {
    let group = foregroundGroup(processes)
    for pid in group {
        if let argv = arguments(pid), SSHCommand.target(fromArguments: argv) != nil { return argv }
    }
    return group.first.flatMap(arguments)
}

/// Reads a process's argument vector without including its environment.
func arguments(ofPID pid: pid_t) -> [String]? {
    guard pid > 0 else { return nil }
    var maxSize: Int32 = 0
    var maxSizeLength = MemoryLayout<Int32>.size
    var maxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
    guard sysctl(&maxMIB, 2, &maxSize, &maxSizeLength, nil, 0) == 0, maxSize > 0 else { return nil }

    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var bytes = [UInt8](repeating: 0, count: Int(maxSize))
    var size = bytes.count
    guard bytes.withUnsafeMutableBytes({ sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) }) == 0,
          size >= MemoryLayout<Int32>.size, size <= bytes.count else { return nil }
    let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
    guard argc > 0, argc <= size else { return nil }

    var position = MemoryLayout<Int32>.size
    guard let pathEnd = bytes[position..<size].firstIndex(of: 0) else { return nil }
    position = pathEnd + 1
    while position < size && bytes[position] == 0 { position += 1 }
    var arguments: [String] = []
    for _ in 0..<argc {
        guard position < size, let end = bytes[position..<size].firstIndex(of: 0),
              let argument = String(bytes: bytes[position..<end], encoding: .utf8) else { return nil }
        arguments.append(argument)
        position = end + 1
    }
    return arguments
}
