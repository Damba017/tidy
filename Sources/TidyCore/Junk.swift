import Foundation

public enum JunkCategory: String, CaseIterable, Sendable {
    case caches, large, dev, orphans
}

public struct JunkItem: Sendable, Equatable {
    public let path: String
    /// Why it's in the list, e.g. "cache", "last used 2025-03-01", "orphan, high confidence".
    public let label: String
    /// The review-list group, e.g. "Caches & logs" or "Large & old · Downloads".
    public let group: String
    public let checked: Bool
    /// Orphans only: their confidence, shown in the plan and when asked one by one.
    public let note: String?
}

public struct JunkOptions: Sendable {
    public var minSize: Int64 = 1_000_000_000           // large: any file at least this big
    public var olderThanDays = 180                       // large: or unused this long ...
    public var oldMinSize: Int64 = 100_000_000           // ... and at least this big
    public var largeLimit = 100                          // biggest first, at most this many
    public var crashReportDays = 30
    public var staleDays = 60                            // dev: project untouched this long
    public init() {}
}

/// Finds junk. Reads only; everything it returns still goes through the review list and the safety core.
public enum Junk {
    public static let groupCaches = "Caches & logs"
    public static let groupDev = "Dev junk"
    public static let groupOrphans = "Orphans"

    /// Junk in the asked categories, plus how many large files didn't fit under the limit.
    public static func find(_ categories: Set<JunkCategory>, options: JunkOptions) -> (items: [JunkItem], largeLeftOut: Int) {
        let home = Paths.home
        let now = Date()
        var items: [JunkItem] = []
        var leftOut = 0
        let devCaches = categories.contains(.dev) ? packageCaches(home: home) : []
        if categories.contains(.caches) {
            items += caches(home: home, now: now, crashReportDays: options.crashReportDays,
                            skipping: Set(devCaches.map(\.path)))
        }
        if categories.contains(.dev) || categories.contains(.large) {
            let walked = walk(home: home, options: options, now: now)
            if categories.contains(.dev) { items += devCaches + walked.dev + simulators(home: home) }
            if categories.contains(.large) {
                items += walked.large
                leftOut = walked.largeLeftOut
            }
        }
        if categories.contains(.orphans) {
            let claimed = AppFinder.installedApps().compactMap(\.bundleID) + RunningApps.bundleIDs()
            let names = AppFinder.installedApps().flatMap(\.names) + (Brew.isInstalled ? Brew.installed().map(\.name) : [])
            items += orphans(home: home, claimedIDs: claimed, names: names, spotlight: spotlightHasApp)
        }
        return (items, leftOut)
    }

    // MARK: Caches & logs

    /// Everything in ~/Library/Caches and ~/Library/Logs, plus crash reports older than `crashReportDays`.
    /// Apple's own com.apple.* caches are left alone.
    static func caches(home: String, now: Date, crashReportDays: Int, skipping: Set<String>) -> [JunkItem] {
        var items: [JunkItem] = []
        for (folder, label) in [("Caches", "cache"), ("Logs", "log")] {
            let location = home + "/Library/" + folder
            for entry in AppFinder.contents(of: location)
            where !entry.hasPrefix(".") && !entry.hasPrefix("com.apple.") && entry != "DiagnosticReports" {
                let path = location + "/" + entry
                if !skipping.contains(path) {
                    items.append(JunkItem(path: path, label: label, group: groupCaches, checked: true, note: nil))
                }
            }
        }
        let reports = home + "/Library/Logs/DiagnosticReports"
        let cutoff = now.addingTimeInterval(-Double(crashReportDays) * 86_400)
        for entry in AppFinder.contents(of: reports) where !entry.hasPrefix(".") {
            let path = reports + "/" + entry
            if let changed = modified(path), changed < cutoff {
                items.append(JunkItem(path: path, label: "crash report, \(day(changed))", group: groupCaches,
                                      checked: true, note: nil))
            }
        }
        return items
    }

    // MARK: Dev junk

    /// Package-manager caches and Xcode leftovers that exist. Xcode archives start unchecked:
    /// they're needed to symbolicate crash logs of builds you shipped.
    static func packageCaches(home: String) -> [JunkItem] {
        let known: [(String, String, Bool)] = [
            ("Library/Caches/Homebrew", "Homebrew downloads", true),
            ("Library/Caches/pip", "pip cache", true),
            (".cache/pip", "pip cache", true),
            (".cache/uv", "uv cache", true),
            ("Library/Caches/org.swift.swiftpm", "SwiftPM cache", true),
            (".npm/_cacache", "npm cache", true),
            ("Library/Caches/Yarn", "Yarn cache", true),
            ("Library/Caches/pnpm", "pnpm cache", true),
            (".cargo/registry/cache", "Cargo downloads", true),
            (".gradle/caches", "Gradle cache", true),
            ("Library/Caches/CocoaPods", "CocoaPods cache", true),
            ("Library/Caches/go-build", "Go build cache", true),
            ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData", true),
            ("Library/Developer/Xcode/Archives", "Xcode archives", false),
        ]
        return known.compactMap { relative, label, checked in
            let path = home + "/" + relative
            return Paths.exists(path) ? JunkItem(path: path, label: label, group: groupDev, checked: checked, note: nil) : nil
        }
    }

    /// Simulators Xcode marks as unavailable (`xcrun simctl`, read-only). Nothing without Xcode.
    static func simulators(home: String) -> [JunkItem] {
        guard run("/usr/bin/xcrun", ["--find", "simctl"]).status == 0 else { return [] }
        let json = run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "--json"]).output
        return unavailableSimulators(json).compactMap { udid in
            let path = home + "/Library/Developer/CoreSimulator/Devices/" + udid
            return Paths.exists(path)
                ? JunkItem(path: path, label: "unavailable simulator", group: groupDev, checked: true, note: nil) : nil
        }
    }

    static func unavailableSimulators(_ json: String) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let runtimes = root["devices"] as? [String: [[String: Any]]] else { return [] }
        return runtimes.values.flatMap { $0 }
            .filter { ($0["isAvailable"] as? Bool) == false }
            .compactMap { $0["udid"] as? String }
            .filter { UUID(uuidString: $0) != nil }  // it becomes part of a path: a UUID and nothing else
            .sorted()
    }

    // MARK: Large & old, and project build folders (one walk through ~)

    /// Folders that are one document to the user; never look inside, but they can be large themselves.
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary",
        "fcpbundle", "logicx", "band", "xcarchive", "utm", "vmwarevm", "pvm", "sparsebundle", "rtfd", "pages",
        "numbers", "key", "playground", "xcodeproj", "xcworkspace", "lrlibrary", "lrdata", "aplibrary",
    ]

    /// Build folders, by the manifest that must sit next to them. `nil`: no manifest needed.
    static let buildFolders: [String: (manifest: String?, label: String, stale: Bool)] = [
        "node_modules": ("package.json", "node_modules", true),
        ".build": ("Package.swift", "SwiftPM build folder", true),
        "target": ("Cargo.toml", "Rust build folder", true),
        "__pycache__": (nil, "Python cache", false),
    ]

    /// A Python virtual environment (any folder with a pyvenv.cfg) is offered whole, and only next to
    /// one of these: without them it can't easily be set up again.
    static let pythonManifests = ["pyproject.toml", "requirements.txt", "uv.lock", "Pipfile", "setup.py"]

    static func walk(home: String, options: JunkOptions, now: Date) -> (large: [JunkItem], largeLeftOut: Int, dev: [JunkItem]) {
        let oldBefore = now.addingTimeInterval(-Double(options.olderThanDays) * 86_400)
        let staleBefore = now.addingTimeInterval(-Double(options.staleDays) * 86_400)
        var large: [(path: String, size: Int64, used: Date)] = []
        var dev: [JunkItem] = []
        func consider(_ path: String, size: Int64, used: Date) {
            if size >= options.minSize || (size >= options.oldMinSize && used < oldBefore) {
                large.append((path, size, used))
            }
        }

        guard let cPath = strdup(home) else { return ([], 0, []) }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else { return ([], 0, []) }
        defer { fts_close(fts) }
        // A folder named like a build folder that isn't one (a Maven project's target, a tool's own
        // node_modules): looked into for large files, but nothing in it counts as dev junk.
        var notBuild: String?
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)
            let name = (path as NSString).lastPathComponent
            if info == FTS_DP {
                if path == notBuild { notBuild = nil }  // out of it again
            } else if info == FTS_D {
                if path == home { continue }
                // Tools keep their own installs in hidden folders in ~ (~/.vscode/extensions, ~/.bun, …):
                // a node_modules or venv in there is part of an install, not a build folder.
                let devJunkHere = !path.dropFirst(home.count + 1).hasPrefix(".") && notBuild == nil
                if path == home + "/Library" || path == home + "/.Trash" || name == ".git"
                    || path == home + "/.local/share/uv" {  // uv's own Pythons and tools
                    fts_set(fts, entry, FTS_SKIP)
                } else if Paths.exists(path + "/pyvenv.cfg") {
                    // Never look inside a virtual environment; a stale project's one is offered whole.
                    fts_set(fts, entry, FTS_SKIP)
                    let project = Paths.parent(path)
                    if devJunkHere, pythonManifests.contains(where: { Paths.exists(project + "/" + $0) }),
                       isPlainVenv(path), (lastChange(in: project, ignoring: name) ?? now) < staleBefore {
                        dev.append(JunkItem(path: path, label: "Python virtual environment", group: groupDev,
                                            checked: true, note: nil))
                    }
                } else if let build = buildFolders[name] {
                    let project = Paths.parent(path)
                    guard devJunkHere, build.manifest.map({ Paths.exists(project + "/" + $0) }) ?? true else {
                        if notBuild == nil { notBuild = path }
                        continue
                    }
                    fts_set(fts, entry, FTS_SKIP)
                    if !build.stale || (lastChange(in: project, ignoring: name) ?? now) < staleBefore {
                        dev.append(JunkItem(path: path, label: build.label, group: groupDev, checked: true, note: nil))
                    }
                } else if packageExtensions.contains((name as NSString).pathExtension.lowercased()) {
                    fts_set(fts, entry, FTS_SKIP)
                    if let st = entry.pointee.fts_statp?.pointee {
                        consider(path, size: Size.allocated(path), used: lastUsed(st))
                    }
                }
            } else if info == FTS_F, let st = entry.pointee.fts_statp?.pointee {
                consider(path, size: Int64(st.st_blocks) * 512, used: lastUsed(st))
            }
        }

        large.sort { $0.size > $1.size }
        let shown = large.prefix(options.largeLimit).map { file in
            let relative = String(file.path.dropFirst(home.count + 1))
            let folder = relative.contains("/") ? String(relative.prefix { $0 != "/" }) : "~"
            return JunkItem(path: file.path, label: "last used \(day(file.used))", group: "Large & old · \(folder)",
                            checked: false, note: nil)
        }
        return (shown, max(0, large.count - options.largeLimit), dev)
    }

    /// What a virtual environment holds. One with anything else in it (your own code, after
    /// `python -m venv .`) is never offered.
    static let venvParts: Set<String> = [
        "bin", "include", "lib", "lib64", "share", "etc", "pyvenv.cfg", ".gitignore", "cachedir.tag", ".lock",
        ".ds_store", "pip-selfcheck.json",
    ]

    static func isPlainVenv(_ folder: String) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return false }
        return entries.allSatisfy { venvParts.contains($0.lowercased()) }
    }

    /// The most recent change to anything directly in `folder`, build folders and `ignoring` left out.
    static func lastChange(in folder: String, ignoring: String) -> Date? {
        AppFinder.contents(of: folder)
            .filter { buildFolders[$0] == nil && $0 != ".DS_Store" && $0 != ignoring }
            .compactMap { modified(folder + "/" + $0) }
            .max()
    }

    // MARK: Orphans

    /// Parts of macOS that don't use a com.apple name: the CUPS printing system, Shortcuts (once
    /// "Workflow"), and open-source pieces Apple ships. Never orphans.
    static let appleVendors: Set<String> = ["org.cups", "is.workflow", "com.openssh", "org.openbsd", "org.ntp", "org.postfix"]

    static let orphanLocations = [
        "Application Support", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
        "Saved Application State", "HTTPStorages", "WebKit", "Application Scripts",
    ]

    /// Library items named like a bundle ID that no installed or running app claims.
    /// Only bundle-ID-shaped names count: plain names are mostly macOS's own (AddressBook, Knowledge, …).
    /// Never anything of Apple's. Same vendor as an installed app (com.utmapp.QEMUHelper next to UTM)
    /// counts as claimed. High confidence, unless one of your app names appears in it.
    static func orphans(home: String, claimedIDs: [String], names: [String], spotlight: (String) -> Bool) -> [JunkItem] {
        let claimed = claimedIDs.map { $0.lowercased() }
        let vendors = Set(claimed.compactMap(vendor))
        let names = Leftovers.usableNames(names)
        var items: [JunkItem] = []
        for location in orphanLocations.map({ home + "/Library/" + $0 }) {
            for entry in AppFinder.contents(of: location) {
                guard let id = bundleID(in: entry), !id.contains("com.apple"), !appleVendors.contains(vendor(id) ?? ""),
                      !claimed.contains(where: { Leftovers.match(entry, bundleID: $0, names: []) == .bundleID }),
                      !vendors.contains(vendor(id) ?? ""),
                      !spotlight(id) else { continue }
                let confidence = names.contains { id.contains($0) } ? "low confidence" : "high confidence"
                items.append(JunkItem(path: location + "/" + entry, label: "orphan, \(confidence)", group: groupOrphans,
                                      checked: false, note: confidence))
            }
        }
        return items
    }

    /// The bundle ID in a Library entry's name, lowercased: "com.foo.bar.plist" → "com.foo.bar",
    /// "ABCDE12345.com.foo.bar" → "com.foo.bar", "group.com.foo.bar" → "com.foo.bar".
    /// Nil unless it looks like reverse DNS with at least three parts (com/org/net/io/… first).
    static func bundleID(in entry: String) -> String? {
        var name = entry.lowercased()
        for suffix in [".plist", ".savedstate", ".binarycookies"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        guard name.allSatisfy({ ($0.isLetter || $0.isNumber || "-_.".contains($0)) && $0.isASCII }) else { return nil }
        var parts = name.split(separator: ".").map(String.init)
        if parts.first == "group" || parts.first.map({ $0.count == 10 && $0.allSatisfy { $0.isLetter || $0.isNumber } }) == true {
            parts.removeFirst()  // "group." or a 10-character team ID
        }
        // ByHost plists end in a hardware UUID: "com.foo.bar.0A1B2C3D-…"
        if let last = parts.last, last.count == 36, last.filter({ $0 == "-" }).count == 4 { parts.removeLast() }
        guard parts.count >= 3, let first = parts.first, (2...4).contains(first.count), first.allSatisfy(\.isLetter),
              parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parts.joined(separator: ".")
    }

    /// "com.hnc.discord" → "com.hnc"
    static func vendor(_ id: String) -> String? {
        let parts = id.split(separator: ".")
        return parts.count >= 2 ? parts[0] + "." + parts[1] : nil
    }

    /// Whether Spotlight knows an app with this bundle ID anywhere on the Mac (read-only).
    static func spotlightHasApp(_ id: String) -> Bool {
        !run("/usr/bin/mdfind", ["kMDItemCFBundleIdentifier == '\(id)'c"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Helpers

    static func modified(_ path: String) -> Date? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
    }

    /// The later of last opened and last changed.
    static func lastUsed(_ st: stat) -> Date {
        Date(timeIntervalSince1970: TimeInterval(max(st.st_atimespec.tv_sec, st.st_mtimespec.tv_sec)))
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
