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
