import Foundation

public struct App: Sendable, Equatable {
    public enum Source: String, Sendable {
        case appStore = "App Store"
        case manual = "manual"
    }

    public let path: String
    public let bundleID: String?
    public let bundleName: String?
    public let displayName: String?
    public let executable: String?
    public let source: Source

    /// The bundle folder's name without ".app".
    public var name: String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Every name the app goes by: folder name, CFBundleName, CFBundleDisplayName, executable.
    public var names: [String] {
        var seen = Set<String>()
        return [name, bundleName, displayName, executable].compactMap { $0 }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

public enum AppFinder {
    public static var defaultFolders: [String] {
        ["/Applications", "/Applications/Utilities", Paths.home + "/Applications"]
    }

    /// Every .app in `folders`, plus one level of subfolders (like /Applications/Microsoft Office/).
    /// Symlinked apps (e.g. /Applications/Safari.app, which points into the sealed system) are skipped.
    public static func installedApps(in folders: [String] = defaultFolders) -> [App] {
        var seen = Set<String>()
        var apps: [App] = []
        func add(_ path: String) {
            if seen.insert(path).inserted, let app = load(path) { apps.append(app) }
        }
        for folder in folders {
            for entry in contents(of: folder) {
                let path = folder + "/" + entry
                if entry.hasSuffix(".app") {
                    add(path)
                } else if isRealFolder(path) {
                    for inner in contents(of: path) where inner.hasSuffix(".app") { add(path + "/" + inner) }
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads one .app bundle. Nil if it isn't a real folder.
    /// iPhone/iPad apps on a Mac are wrapped: their Info.plist is in WrappedBundle/, and they come
    /// from the App Store when Wrapper/iTunesMetadata.plist is there.
    public static func load(_ path: String) -> App? {
        guard isRealFolder(path) else { return nil }
        let plist = Paths.exists(path + "/Contents/Info.plist") ? "/Contents/Info.plist" : "/WrappedBundle/Info.plist"
        let info = NSDictionary(contentsOfFile: path + plist) as? [String: Any] ?? [:]
        let receipt = Paths.exists(path + "/Contents/_MASReceipt") || Paths.exists(path + "/Wrapper/iTunesMetadata.plist")
        return App(
            path: path,
            bundleID: info["CFBundleIdentifier"] as? String,
            bundleName: info["CFBundleName"] as? String,
            displayName: info["CFBundleDisplayName"] as? String,
            executable: info["CFBundleExecutable"] as? String,
            source: receipt ? .appStore : .manual)
    }

    /// True for an app bundle: a real folder named *.app with an Info.plist (in Contents/, or in
    /// WrappedBundle/ for an iPhone/iPad app). Any other folder is never taken for an app.
    public static func isAppBundle(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".app") && isRealFolder(path)
            && (Paths.exists(path + "/Contents/Info.plist") || Paths.exists(path + "/WrappedBundle/Info.plist"))
    }

    static func contents(of folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted()
    }

    static func isRealFolder(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }
}
