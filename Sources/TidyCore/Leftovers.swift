import Foundation

public struct Leftover: Sendable, Equatable {
    /// How a leftover was matched to its app, strongest first.
    public enum Match: Int, Sendable, Comparable {
        case bundleID, pkgReceipt, bundleIDPrefix, name, fuzzy

        public var label: String {
            switch self {
            case .bundleID: "bundle ID"
            case .pkgReceipt: "pkg receipt"
            case .bundleIDPrefix: "bundle ID prefix"
            case .name: "name"
            case .fuzzy: "fuzzy"
            }
        }

        public static func < (a: Match, b: Match) -> Bool { a.rawValue < b.rawValue }
    }

    public let path: String
    public let match: Match

    /// Fuzzy matches (the name only appears somewhere in it) start unchecked.
    public var checkedByDefault: Bool { match != .fuzzy }
}

/// Finds what an app left behind in the Library folders and in its .pkg receipts.
public enum Leftovers {
    /// Every folder leftovers are looked for in, one level deep. `temp`: the user's own temp and cache
    /// folders (see `Paths.userTempFolders`).
    public static func locations(home: String = Paths.home, temp: [String] = Paths.userTempFolders) -> [String] {
        libraryLocations(home: home) + [home + "/Library"] + temp
    }

    static func libraryLocations(home: String) -> [String] {
        let user = [
            "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
            "Saved Application State", "HTTPStorages", "WebKit", "Logs", "LaunchAgents", "Cookies", "Application Scripts",
        ]
        let system = [
            "Application Support", "Caches", "Preferences", "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools",
        ]
        return user.map { home + "/Library/" + $0 } + system.map { "/Library/" + $0 }
    }

    /// Everything that belongs to `app`, strongest match first. Reads only.
    public static func find(for app: App) -> [Leftover] {
        let others = otherApps(than: app)
        return merge(find(bundleID: app.bundleID, names: app.names, home: Paths.home, temp: Paths.userTempFolders, others: others)
            + pkgLeftovers(for: app, others: others))
    }

    /// The Library and temp leftovers for something with this bundle ID (if any) and these names.
    /// `temp`: the user's temp and cache folders. `others`: the other apps on this Mac (see `otherApps`).
    public static func find(bundleID: String?, names: [String], home: String, temp: [String], others: [App]) -> [Leftover] {
        find(bundleID: bundleID, names: names, in: libraryLocations(home: home), strict: [home + "/Library"], temp: temp,
             others: others)
    }

    /// Looks one level deep in each of `locations`, `strict` and `temp`. In `strict` (~/Library itself, full of
    /// macOS's own folders) only a bundle ID or the exact name counts, never a fuzzy match. In `temp` (the user's
    /// temp and cache folders, full of every program's files) a fuzzy match counts only for a name shaped like a
    /// bundle ID (com.roblox.player.installer.lock), never for a plain one. Neither ever offers a name of macOS's
    /// own folders. What another app claims as well is left out: with a longer bundle ID it's that
    /// app's (com.google.Chrome.canary next to com.google.Chrome, com.foo.AppBeta next to com.foo.App);
    /// with the same bundle ID (a second copy, Xcode-beta next to Xcode) or by the same name
    /// (Firefox Nightly is "firefox" too, in the same Application Support/Firefox) it's shared.
    static func find(bundleID: String?, names: [String], in locations: [String], strict: [String] = [],
                     temp: [String] = [], others: [App]) -> [Leftover] {
        let names = usableNames(names)
        let theirIDs = bundleID.map { id in others.compactMap(\.bundleID).filter { $0.count >= id.count } } ?? []
        let theirNames = usableNames(others.flatMap(\.names))
        var found: [Leftover] = []
        for location in locations + strict + temp {
            let isStrict = strict.contains(location)
            let isTemp = temp.contains(location)
            for entry in AppFinder.contents(of: location) where !theirIDs.contains(where: { claims($0, entry) }) {
                guard let match = match(entry, bundleID: bundleID, names: names) else { continue }
                if (isStrict || isTemp) && macOSFolderNames.contains(entry.lowercased()) { continue }
                if match == .fuzzy && (isStrict || (isTemp && Junk.bundleID(in: entry) == nil)) { continue }
                if match != .bundleID && Self.match(entry, bundleID: nil, names: theirNames) == .name { continue }
                found.append(Leftover(path: location + "/" + entry, match: match))
            }
        }
        return merge(found)
    }

    /// True when `entry` is named after `bundleID`: that ID itself, or it with more after it (com.foo.AppBeta
    /// claims com.foo.AppBeta.plist and com.foo.AppBetaHelper).
    static func claims(_ bundleID: String, _ entry: String) -> Bool {
        let match = match(entry, bundleID: bundleID, names: [])
        return match == .bundleID || match == .bundleIDPrefix
    }

    /// Names of macOS's own folders in ~/Library (and in /System/Library). An app with one of these names
    /// never gets that folder: Apple's Developer app would otherwise take ~/Library/Developer (Xcode's
    /// simulators and build files), an app called Weather or Photos would take macOS's own.
    static let macOSFolderNames: Set<String> = {
        let library = [
            "Accessibility", "Accounts", "AppleMediaServices", "Application Scripts", "Application Support", "Assistant",
            "Assistants", "Audio", "Autosave Information", "Biome", "Caches", "Calendars", "CallServices", "CloudStorage",
            "ColorPickers", "ColorSync", "Colors", "Components", "Compositions", "Contacts", "ContainerManager",
            "Containers", "Cookies", "CoreData", "CoreFollowUp", "Daemon Containers", "DataAccess",
            "DataDeliveryServices", "Developer", "Dictionaries", "DoNotDisturb", "DuetExpertCenter", "Extensions",
            "Favorites", "FileProvider", "Filters", "Finance", "FinanceBackup", "FontCollections", "Fonts",
            "Fonts Disabled", "Frameworks", "FrontBoard", "GameController", "GameKit", "Group Containers",
            "GroupContainersAlias", "HTTPStorages", "HomeKit", "IdentityServices", "Image Capture", "Input Methods",
            "IntelligencePlatform", "Intents", "Internet Plug-Ins", "iTunes", "Keyboard", "Keyboard Layouts",
            "KeyboardServices", "Keychains", "LanguageModeling", "LaunchAgents", "LockdownMode", "Logs", "Mail", "Maps",
            "MediaAnalysis", "Messages", "Metadata", "Mobile Documents", "Music", "News", "Notes", "Passes", "PDF Services",
            "PersonalizationPortrait", "Photos", "PPM", "PreferencePanes", "Preferences", "Printers",
            "PrivateCloudCompute", "QuickLook", "Reminders", "ResponseKit", "Safari", "SafariSafeBrowsing",
            "Saved Application State", "Saved Searches", "Screen Savers", "Scripts", "Services", "Sharing", "Shortcuts",
            "Sounds", "Speech", "Spelling", "Spotlight", "StatusKit", "Stickers", "Suggestions", "SyncedPreferences",
            "Translation", "Trial", "UnifiedAssetFramework", "VoiceTrigger", "Weather", "WebKit", "Workflows",
        ]
        return Set((library + AppFinder.contents(of: "/System/Library")).map { $0.lowercased() })
    }()

    /// Folders among `folders` taydic can't look in, with why (mostly macOS privacy protection, e.g.
    /// ~/Library/Cookies without Full Disk Access). Leftovers in there can't be found, so the user hears
    /// about the folder instead. Folders that aren't there don't count.
    public static func unreadable(_ folders: [String]) -> [(path: String, reason: String)] {
        folders.compactMap { folder in
            if let dir = opendir(folder) {
                closedir(dir)
                return nil
            }
            let error = errno
            if error == ENOENT || error == ENOTDIR { return nil }
            return (folder, error == EPERM ? RemovalPlan.privacyReason : String(cString: strerror(error)))
        }
    }

    /// The other apps on this Mac, installed or running. Reads only.
    public static func otherApps(than app: App?) -> [App] {
        let installed = AppFinder.installedApps()
        let paths = Set(installed.map(\.path))
        let running = RunningApps.bundles().filter { !paths.contains($0.path) }.map { id, path in
            let info = AppFinder.load(path)
            return App(path: path, bundleID: id, bundleName: info?.bundleName, displayName: info?.displayName,
                       executable: info?.executable, source: .manual)
        }
        return otherApps(than: app, among: installed + running)
    }

    /// `apps` minus `app` itself and its helpers, which live inside its bundle.
    static func otherApps(than app: App?, among apps: [App]) -> [App] {
        guard let app else { return apps }
        return apps.filter { $0.path != app.path && !$0.path.hasPrefix(app.path + "/") }
    }

    /// What a command-line tool leaves in the home folder: ~/.config/<name>, ~/.cache/<name>,
    /// ~/.local/share/<name>, ~/.local/state/<name>, ~/.<name> and ~/.<name>rc. Only the ones that exist.
    public static func dotfiles(for name: String, home: String = Paths.home) -> [Leftover] {
        guard !name.isEmpty, !name.contains("/") else { return [] }
        let paths = [".config/", ".cache/", ".local/share/", ".local/state/", "."].map { home + "/" + $0 + name }
            + [home + "/." + name + "rc"]
        return merge(paths.filter(Paths.exists).map { Leftover(path: $0, match: .name) })
    }

    /// Where macOS keeps its own command-line tools.
    public static let macOSToolFolders = ["/bin", "/usr/bin", "/usr/sbin"]

    /// macOS's own tool called `name` (/bin/zsh, /usr/bin/vim), if there is one. It reads the same
    /// dotfiles as the Homebrew one, so those aren't leftovers.
    public static func macOSTool(_ name: String, in folders: [String]) -> String? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        return folders.map { $0 + "/" + name }.first(where: Paths.exists)
    }

    /// How `entry` (a file or folder name) relates to the app, if at all.
    static func match(_ entry: String, bundleID: String?, names: [String]) -> Leftover.Match? {
        let lower = entry.lowercased()
        var base = lower
        for suffix in [".plist", ".savedstate", ".binarycookies"] where base.hasSuffix(suffix) {
            base.removeLast(suffix.count)
        }
        if let id = bundleID?.lowercased(), !id.isEmpty {
            // com.hnc.Discord, com.hnc.Discord.ShipIt, 53Q6R32WPB.com.hnc.Discord, group.com.hnc.Discord, ByHost plists
            if base == id || base.hasPrefix(id + ".") || base.hasSuffix("." + id) || base.contains("." + id + ".") {
                return .bundleID
            }
            // WebKit's temp folders for the app: com.apple.WebKit.WebContent+com.roblox.RobloxPlayer. Only the
            // part after the + counts.
            if lower.hasPrefix("com.apple.webkit."), let plus = lower.firstIndex(of: "+"),
               match(String(lower[lower.index(after: plus)...]), bundleID: id, names: []) == .bundleID {
                return .bundleID
            }
            // com.roblox.RobloxPlayerChannel: the bundle ID with more letters or digits right after it. That can
            // be another app of the same maker (com.hnc.DiscordPTB), so it gets its own label. Never for Apple's
            // names (com.apple.RemoteDesktopAgent is macOS's, not Remote Desktop's), and only for a bundle ID of
            // three parts or more (com.foo + "bar" would be another maker).
            if !lower.contains("com.apple."), id.split(separator: ".").count >= 3, base.hasPrefix(id),
               let next = base.dropFirst(id.count).first, next.isASCII && (next.isLetter || next.isNumber) {
                return .bundleIDPrefix
            }
        }
        // Apple's own files only ever match through the app's bundle ID, also the ones that don't start with
        // com.apple. (group.com.apple.notes, 2BUA8C4S2C.com.apple.…).
        if lower.contains("com.apple.") { return nil }
        if names.contains(base) || names.contains(lower) { return .name }
        if names.contains(where: { $0.count >= 4 && lower.contains($0) }) { return .fuzzy }
        return nil
    }

    /// Names in lowercase, minus ones too short or too generic to match on.
    static func usableNames(_ names: [String]) -> [String] {
        let generic: Set<String> = [
            "app", "application", "applications", "helper", "electron", "launcher", "updater", "update", "installer", "setup",
            "service", "agent", "client", "data", "cache", "caches", "library", "support", "preferences",
            "apple", "mac", "macos", "main", "default",
        ]
        return names.map { $0.lowercased() }.filter { $0.count >= 3 && !generic.contains($0) }
    }

    /// Files a .pkg installed for this app, found with pkgutil (read-only). `others`: the other apps on this Mac.
    static func pkgLeftovers(for app: App, others: [App]) -> [Leftover] {
        let names = usableNames(app.names)
        let packages = pkgutil(["--pkgs"]).split(separator: "\n").map(String.init).filter {
            match($0, bundleID: app.bundleID, names: names) == .bundleID
        }
        return packages.flatMap { id -> [Leftover] in
            // "volume: /" and "location: Applications" → files are relative to /Applications
            var volume = "/"
            var location = ""
            for line in pkgutil(["--pkg-info", id]).split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                if parts[0] == "volume" { volume = parts[1] }
                if parts[0] == "location" { location = parts[1] }
            }
            let root = (volume as NSString).appendingPathComponent(location)
            let files = pkgutil(["--files", id, "--only-files"]).split(separator: "\n").map(String.init)
            return pkgPaths(files: files, root: root, app: app, others: others)
        }
    }

    /// Turns a receipt's file list into leftovers: each file that still exists outside the app bundle,
    /// or the highest folder above it that's named after the app (so a whole support folder is one item).
    /// What lies inside another app is that app's, and a folder that holds another app never goes whole
    /// (one .pkg can install several apps).
    static func pkgPaths(files: [String], root: String, app: App, others: [App]) -> [Leftover] {
        let names = usableNames(app.names)
        let bundles = [app.path] + others.map(\.path)
        var result = Set<String>()
        for file in files {
            let path = Paths.normalize((root as NSString).appendingPathComponent(file))
            guard Paths.exists(path), !bundles.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { continue }
            var keep = path
            var folder = Paths.parent(path)
            while folder != "/" && folder.count > 1 {
                let name = (folder as NSString).lastPathComponent
                if let match = match(name, bundleID: app.bundleID, names: names), match == .bundleID || match == .name,
                   !others.contains(where: { $0.path.hasPrefix(folder + "/") }) {
                    keep = folder
                }
                folder = Paths.parent(folder)
            }
            result.insert(keep)
        }
        return result.sorted().map { Leftover(path: $0, match: .pkgReceipt) }
    }

    /// One entry per path (the strongest match), protected paths dropped, items inside other items dropped.
    static func merge(_ leftovers: [Leftover]) -> [Leftover] {
        var best: [String: Leftover.Match] = [:]
        for leftover in leftovers where Denylist.reason(for: leftover.path) == nil {
            best[leftover.path] = min(best[leftover.path] ?? leftover.match, leftover.match)
        }
        let paths = Set(best.keys)
        return best.filter { path, _ in
            var parent = Paths.parent(path)
            while parent != "/" {
                if paths.contains(parent) { return false }
                parent = Paths.parent(parent)
            }
            return true
        }
        .map { Leftover(path: $0.key, match: $0.value) }
        .sorted { ($0.match, $0.path) < ($1.match, $1.path) }
    }

    private static func pkgutil(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
