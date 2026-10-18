import Foundation

public enum Paths {
    public static let home = NSHomeDirectory()
    public static let logFile = home + "/.local/state/tidy/log"

    /// Absolute path with `~` expanded, trailing slashes dropped and symlinks in the
    /// parent folders resolved. The last component is never resolved: removing a symlink
    /// removes the link, never its target. Its case comes from the disk, though: on a
    /// case-insensitive volume `~/library` is `~/Library`. Paths on the boot data volume
    /// (`/System/Volumes/Data/...`) are mapped back to their normal location.
    public static func normalize(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        if !p.hasPrefix("/") { p = FileManager.default.currentDirectoryPath + "/" + p }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }

        let name = (p as NSString).lastPathComponent
        if p == "/" || name == "." || name == ".." {
            p = realPath(p) ?? p
        } else if let parent = realPath(parent(p)) {
            p = (parent == "/" ? "" : parent) + "/" + (storedName(of: name, in: parent) ?? name)
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

    /// How `name` is spelled on disk in `folder` ("library" → "Library"), on a volume that ignores case.
    /// A symlink's own name, never its target's. Nil when it isn't there or the volume minds case.
    static func storedName(of name: String, in folder: String) -> String? {
        guard pathconf(folder, _PC_CASE_SENSITIVE) == 0 else { return nil }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_NAME)
        var buffer = [UInt8](repeating: 0, count: 2048)
        let path = (folder == "/" ? "" : folder) + "/" + name
        let status = buffer.withUnsafeMutableBytes {
            getattrlist(path, &request, $0.baseAddress, $0.count, UInt32(FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return nil }
        // Layout: u_int32_t length, then an attrreference_t pointing at the name.
        let stored = buffer.withUnsafeBytes { raw in
            let field = raw.baseAddress! + 4
            let reference = field.loadUnaligned(as: attrreference_t.self)
            return String(cString: (field + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
        }
        // Only another spelling of the same name: a hard link's other names don't count.
        return stored.lowercased() == name.lowercased() ? stored : nil
    }
}
