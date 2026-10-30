import Foundation
import RemindersCore

// macOS grants Reminders access to the "responsible" app of a process, and
// for this server that's whatever launched it — Claude. Claude doesn't
// declare Reminders usage in its own Info.plist, so the request is denied
// outright, without even a prompt. Relaunching with responsibility
// disclaimed makes this server the one asking, under the name and reason in
// its embedded Info.plist. The child inherits stdin/stdout, so MCP traffic passes
// straight through; this process only waits for it and relays signals.
//
// Only done when the binary carries that Info.plist (see Package.swift);
// without one there is nothing to be responsible with.
private let disclaimedEnv = "MAC_REMINDERS_DISCLAIMED"

func relaunchDisclaimedIfNeeded() {
    guard Bundle.main.bundleIdentifier != nil, getenv(disclaimedEnv) == nil else { return }

    // Private SPI in libSystem, the same one Terminal and Xcode use for
    // what they launch.
    typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim"),
          let path = Bundle.main.executablePath
    else {
        eprint("can't disclaim responsibility on this macOS; Reminders access will likely be denied")
        return
    }
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    _ = unsafeBitCast(symbol, to: SetDisclaim.self)(&attr, 1)
    setenv(disclaimedEnv, "1", 1)

    var pid: pid_t = 0
    let rc = posix_spawn(&pid, path, nil, &attr, CommandLine.unsafeArgv, environ)
    posix_spawnattr_destroy(&attr)
    guard rc == 0 else {
        eprint("relaunch failed: \(String(cString: strerror(rc)))")
        exit(1)
    }

    var relays: [DispatchSourceSignal] = []
    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler { kill(pid, sig) }
        source.resume()
        relays.append(source)
    }

    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    let signaled = status & 0x7f
    exit(signaled == 0 ? (status >> 8) & 0xff : 128 + signaled)
}
