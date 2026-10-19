import Foundation

/// Paths taydic never offers to remove, whatever the matching says.
public enum Denylist {
    /// Why `path` may never be removed, or nil if it may be offered.
    public static func reason(for path: String, home: String = Paths.home) -> String? {
        // Compare resolved paths only, or a symlink (/tmp → /private/tmp) slips past every rule.
        let path = Paths.normalize(path)
        let home = Paths.realPath(home) ?? home
        guard path.hasPrefix("/"), path != "/" else { return "root of the disk" }
        // And compare without case, like the disk does: ~/library is ~/Library.
        let lower = path.lowercased()
        if lower == home.lowercased() { return "your home folder" }

        for (tree, why) in trees(home: home) {
            let treeLower = tree.lowercased()
            if lower == treeLower || lower.hasPrefix(treeLower + "/") {
                if tree == "/usr" && (lower == "/usr/local" || lower.hasPrefix("/usr/local/")) { continue }
                return why
            }
            if treeLower.hasPrefix(lower + "/") { return "contains \(Paths.display(tree))" }
        }
        if folders(home: home).contains(where: { $0.lowercased() == lower }) {
            return "standard folder, only what's inside may go"
        }

        if (path as NSString).lastPathComponent.hasPrefix(".") && isVolumeRoot(Paths.parent(path)) {
            return "hidden system item at the root of a volume"
        }
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        if st.st_flags & UInt32(SF_RESTRICTED) != 0 { return "protected by System Integrity Protection" }
        if isVolumeRoot(path) { return "mount point" }
        return nil
    }

    /// Never removed, and nothing inside them either. Their parents are protected too.
    static func trees(home: String) -> [(String, String)] {
        [
            ("/System", "macOS system"),
            ("/bin", "macOS system"),
            ("/sbin", "macOS system"),
            ("/usr", "macOS system"),  // except /usr/local, see above
            ("/dev", "devices"),
            ("/private/etc", "system configuration"),
            ("/private/var/db", "system databases"),
            ("/private/var", "macOS system data"),  // temp files of running apps, root's home, logs, …
            ("/Library/Apple", "Apple system files"),
            ("/Library/Keychains", "system keychains"),
            ("/Library/Preferences/SystemConfiguration", "network settings"),
            (home + "/Library/Keychains", "keychains"),
            (home + "/Library/Mail", "Mail"),
            (home + "/Library/Messages", "Messages"),
            (home + "/Library/Mobile Documents", "iCloud Drive"),
            (home + "/Pictures/Photos Library.photoslibrary", "Photos library"),
            (home + "/.ssh", "SSH keys"),
            (home + "/.gnupg", "GPG keys"),
            (home + "/.Trash", "already in the Trash"),
            (home + "/.local/state/taydic", "taydic's own log"),
            (home + "/.local/state/tidy", "taydic's old log, from when it was called tidy"),
        ]
    }

    /// Never removed themselves, but what's inside may go.
    static func folders(home: String) -> Set<String> {
        let homeFolders = [
            "Applications", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public",
            "Library", ".config", ".cache", ".local", ".local/bin", ".local/share", ".local/state",
        ]
        let userLibrary = [
            "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers",
            "Group Containers", "Saved Application State", "HTTPStorages", "WebKit", "Logs",
            "Logs/DiagnosticReports", "LaunchAgents", "Cookies", "Application Scripts",
        ]
        let systemLibrary = [
            "Application Support", "Caches", "Preferences", "LaunchAgents", "LaunchDaemons",
            "PrivilegedHelperTools",
        ]
        var set: Set<String> = [
            "/Applications", "/Applications/Utilities", "/Library", "/Users", "/Users/Shared", "/Volumes",
            "/opt", "/opt/homebrew", "/usr/local", "/private", "/private/tmp", "/private/var",
            "/etc", "/tmp", "/var",
        ]
        set.formUnion(homeFolders.map { home + "/" + $0 })
        set.formUnion(userLibrary.map { home + "/Library/" + $0 })
        set.formUnion(systemLibrary.map { "/Library/" + $0 })
        return set
    }

    /// True for "/" and for folders on a different filesystem than their parent.
    static func isVolumeRoot(_ path: String) -> Bool {
        if path == "/" { return true }
        var st = stat()
        var parent = stat()
        guard lstat(path, &st) == 0, lstat(Paths.parent(path), &parent) == 0 else { return false }
        return st.st_dev != parent.st_dev
    }
}
