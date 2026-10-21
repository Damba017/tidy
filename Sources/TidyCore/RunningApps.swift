import AppKit

/// AppKit is only here to quit apps the normal way (like ⌘Q), so they can save their work first.
public enum RunningApps {
    public static func isRunning(_ app: App) -> Bool {
        !instances(of: app).isEmpty
    }

    /// Bundle IDs of everything running now, wherever it was started from.
    public static func bundleIDs() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    }

    /// Bundle IDs of everything running now, with the bundle each was started from.
    public static func bundles() -> [(id: String, path: String)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, var path = app.bundleURL?.path(percentEncoded: false) else { return nil }
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            return (id, path)
        }
    }

    /// The executables of the running processes taydic may look at (your own, mostly), also plain programs
    /// that aren't apps. Reads only.
    public static func processPaths() -> [String] {
        var pids = [pid_t](repeating: 0, count: Int(max(0, proc_listallpids(nil, 0))) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))  // PROC_PIDPATHINFO_MAXSIZE
        return pids.prefix(Int(max(0, count))).compactMap { pid in
            guard pid > 0, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
            return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        }
    }

    /// Asks every instance to quit and waits up to `timeout` seconds. True once they're all gone.
    public static func quit(_ app: App, timeout: TimeInterval = 15) -> Bool {
        let running = instances(of: app)
        let pids = running.map(\.processIdentifier)
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pids.allSatisfy({ kill($0, 0) != 0 && errno == ESRCH }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private static func instances(of app: App) -> [NSRunningApplication] {
        guard let id = app.bundleID else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
    }
}
