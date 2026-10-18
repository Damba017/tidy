import Foundation

/// Stops launchd jobs before their plist goes to the Trash; otherwise they keep running until logout or reboot.
public enum Launchctl {
    public enum Domain: Equatable, Sendable {
        case user    // LaunchAgents: the logged-in user's gui domain, no root needed
        case system  // LaunchDaemons: needs root
    }

    /// The launchd domain a plist is loaded in, judging by its folder; nil if it isn't a launchd plist.
    public static func domain(of path: String) -> Domain? {
        guard path.hasSuffix(".plist") else { return nil }
        switch (Paths.parent(path) as NSString).lastPathComponent {
        case "LaunchAgents": return .user
        case "LaunchDaemons": return .system
        default: return nil
        }
    }

    /// `launchctl bootout` arguments for a job's plist. For `.system` they're run through sudo.
    static func bootout(_ path: String, in domain: Domain) -> [String] {
        ["bootout", domain == .system ? "system" : "gui/\(getuid())", path]
    }

    /// Runs /bin/launchctl quietly and returns its exit status. A job that isn't loaded just fails, which is fine.
    public static func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
