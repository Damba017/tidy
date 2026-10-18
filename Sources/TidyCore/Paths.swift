import Foundation

public enum Paths {
    public static let home = NSHomeDirectory()
    public static let logFile = home + "/.local/state/tidy/log"

    /// Absolute path with `~` expanded, trailing slashes dropped and symlinks in the
    /// parent folders resolved. The last component is kept as is: removing a symlink
    /// removes the link, never its target. Paths on the boot data volume
    /// (`/System/Volumes/Data/...`) are mapped back to their normal location.
    public static func normalize(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        if !p.hasPrefix("/") { p = FileManager.default.currentDirectoryPath + "/" + p }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }

        let name = (p as NSString).lastPathComponent
        if p == "/" || name == "." || name == ".." {
            p = realPath(p) ?? p
        } else if let parent = realPath(parent(p)) {
            p = parent == "/" ? "/" + name : parent + "/" + name
        }

        let data = "/System/Volumes/Data"
        if p == data { return "/" }
        if p.hasPrefix(data + "/") { p.removeFirst(data.count) }
        return p
    }

    /// `~/…` for paths in the home folder, the path itself otherwise.
    public static func display(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    static func parent(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
