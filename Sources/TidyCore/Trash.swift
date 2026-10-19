import Foundation

public enum Trash {
    /// Moves `path` to the Trash and returns where it ended up.
    /// Refuses anything on the denylist, whoever calls it.
    public static func move(_ path: String) throws -> String {
        try move(path, home: Paths.home, using: system)
    }

    /// The denylist check always runs here; only the final move is `trashItem`,
    /// which tests replace so they can never reach the real Trash.
    static func move(_ path: String, home: String, using trashItem: (String) throws -> String) throws -> String {
        let path = Paths.normalize(path)
        if let reason = Denylist.reason(for: path, home: home) {
            throw TidyError("refused \(Paths.display(path)): \(reason)")
        }
        do {
            return try trashItem(path)
        } catch let error as TidyError {
            throw error
        } catch {
            throw TidyError("\(Paths.display(path)): \(error.localizedDescription)")
        }
    }

    /// The real Trash, the same one Finder uses (with "Put Back").
    static func system(_ path: String) throws -> String {
        var result: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &result)
        return result?.path ?? "the Trash"
    }

    /// A path in `trashFolder` that isn't taken yet: `name`, `name 2`, `name 3`, … (extension kept).
    /// Throws when it can't tell whether a name is taken (e.g. privacy protection on the Trash):
    /// a guess could move the item onto, or into, something that's already there.
    public static func freeDestination(for path: String, in trashFolder: String) throws -> String {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var candidate = trashFolder + "/" + name
        var number = 2
        while true {
            var st = stat()
            if lstat(candidate, &st) != 0 {
                let error = errno
                if error == ENOENT { return candidate }
                throw TidyError("can't look into \(Paths.display(trashFolder)): \(String(cString: strerror(error)))")
            }
            candidate = trashFolder + "/" + base + " \(number)" + (ext.isEmpty ? "" : "." + ext)
            number += 1
        }
    }
}
