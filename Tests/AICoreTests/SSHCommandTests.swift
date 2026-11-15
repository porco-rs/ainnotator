import Testing
@testable import AICore

@Test(arguments: [
    (["ssh", "devbox"], ["devbox"]),
    (["/usr/bin/ssh", "-p", "2200", "me@host"], ["-p", "2200", "me@host"]),
    (["ssh", "-p2200", "host"], ["-p", "2200", "host"]),
    (["ssh", "-F", "/tmp/c", "-t", "devbox"], ["-F", "/tmp/c", "devbox"]),
    (["ssh", "-o", "ProxyCommand=evil", "-o", "Port=2200", "host"], ["-o", "Port=2200", "host"]),
    (["ssh", "-oproxycommand=x", "host"], ["host"]),
    (["ssh", "-L", "8080:localhost:80", "-A", "host"], ["host"]),
    (["ssh", "-J", "jump", "-i", "/k", "host"], ["-J", "jump", "-i", "/k", "host"]),
    (["ssh", "host", "tmux", "attach"], ["host"]),
    (["ssh", "-46vqp2222", "-luser", "-S", "/tmp/socket", "--", "host"], ["-4", "-6", "-p", "2222", "-l", "user", "-S", "/tmp/socket", "host"]),
    (["ssh", "-o", "uSeR=me", "-oHostName=example", "-oIdentityFile=/key", "-oIdentitiesOnly=yes", "-oProxyJump=jump", "-oUserKnownHostsFile=/file", "-oControlPath=/sock", "host"], ["-o", "uSeR=me", "-o", "HostName=example", "-o", "IdentityFile=/key", "-o", "IdentitiesOnly=yes", "-o", "ProxyJump=jump", "-o", "UserKnownHostsFile=/file", "-o", "ControlPath=/sock", "host"]),
    (["ssh", "-oLocalCommand=evil", "-oRemoteCommand=evil", "-oKnownHostsCommand=evil", "host"], ["host"]),
    (["ssh", "-p", "1", "-p65535", "host"], ["-p", "1", "-p", "65535", "host"]),
    (["ssh", "-e", "x", "-cfoo", "-m", "bar", "-b", "addr", "-B", "iface", "-D1080", "-R", "x", "-w", "1:2", "-E", "/tmp/log", "host"], ["host"]),
    (["ssh", "-1246atTvqCAaXxYykKgnM", "host"], ["-4", "-6", "host"]),
    (["ssh", "--", "host", "-N"], ["host"]),
    // ssh also reads options that follow the destination; the first other word begins the remote command.
    (["ssh", "host", "-p", "2200"], ["-p", "2200", "host"]),
    (["ssh", "devbox", "-t", "tmux", "attach", "-d"], ["devbox"]),
    (["ssh", "host", "-oProxyCommand=x", "ls", "-N"], ["host"]),
]) func parsesSSHTarget(input: [String], expected: [String]) {
    let target = SSHCommand.target(fromArguments: input)
    #expect(target?.arguments == expected)
    #expect(target?.destination == expected.last)
    #expect(target?.consentKey == expected.joined(separator: " "))
}

@Test(arguments: [
    ["scp", "a", "host:b"], ["git", "push"], [], ["ssh"], ["ssh", "-N", "host"],
    ["ssh", "-W", "h:22", "jump"], ["ssh", "-p", "abc", "host"], ["ssh", "-p"],
    ["ssh", "--", "-oProxyCommand=x"], ["ssh", "-Z", "host"], ["ssh", "-p0", "host"],
    ["ssh", "-p65536", "host"], ["ssh", "-p+22", "host"], ["ssh", "-p２２", "host"],
    ["ssh", "-oPort=0", "host"], ["ssh", "-oUser=", "host"], ["ssh", "-l", "", "host"],
    ["ssh", "-F", "bad\nfile", "host"], ["ssh", ""], ["ssh", "host name"],
    ["ssh", "host\nname"], ["ssh", "-"], ["ssh", "--"], ["ssh", "-L"],
    ["ssh", "-Nf", "host"], ["ssh", "-o", "User=bad\tname", "host"],
    ["ssh", "host", "-N"], ["ssh", "host", "-p", "abc"],
]) func rejectsInvalidSSHTarget(input: [String]) {
    #expect(SSHCommand.target(fromArguments: input) == nil)
}

@Test(arguments: ["N", "f", "s", "G", "V", "W", "O", "Q", "I", "P"]) func rejectsUnsafeModes(option: String) {
    #expect(SSHCommand.target(fromArguments: ["ssh", "-" + option, "value", "host"]) == nil)
}
