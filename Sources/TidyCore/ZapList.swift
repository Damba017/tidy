import Foundation

/// What a cask's zap stanza names (see `Brew.zapPaths`), for the brew flow when the user said no to `--zap`:
/// taydic offers what of it is on this Mac for the Trash, through the safety core, instead of brew deleting it
/// right away. It reaches what taydic's own search can't, one level deep
/// (~/Library/Caches/Mozilla/updates/Applications/Zen). Reads only.
enum ZapList {
    /// The leftovers among `patterns`, for the app with `bundleID` and `names` (its bundle at `app`, if any).
    /// Sure only inside a Library folder (~/Library, /Library) and named after the app (bundle ID, prefix or name,
    /// as in `Leftovers.match`); anything else is `.zap`, asked separately: casks list shared folders too
    /// (microsoft-word: ~/Library/Application Support/Microsoft, which Excel and Outlook use as well).
    /// What's another app's is left out: an app bundle (`app` itself or one of `others`), a folder holding one,
    /// what another app claims by bundle ID or name (as in `Leftovers.find`), and Apple's own names unless they
    /// match the app's bundle ID. Denylisted paths are left to `Leftovers.merge`.
    static func leftovers(_ patterns: [String], bundleID: String?, names: [String], app: String?, home: String,
                          others: [App]) -> [Leftover] {
        let names = Leftovers.usableNames(names)
        let bundles = ([app].compactMap { $0 } + others.map(\.path)).map(Paths.normalize)
        // Without a bundle ID to compare with, every other app's ID counts.
        let ids = others.compactMap(\.bundleID)
        let theirIDs = bundleID.map { id in ids.filter { $0.count >= id.count } } ?? ids
        let theirNames = Leftovers.usableNames(others.flatMap(\.names))
        let libraries = [Paths.normalize(home + "/Library"), "/Library"].map { $0.lowercased() + "/" }
        var found: [Leftover] = []
        for path in patterns.flatMap({ expand($0, home: home) }) {
            if bundles.contains(where: { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) { continue }
            let entry = (path as NSString).lastPathComponent
            let match = Leftovers.match(entry, bundleID: bundleID, names: names)
            // Apple's own (com.apple.sharedfilelist) only ever through the app's bundle ID, as in taydic's own search.
            if match == nil && entry.lowercased().contains("com.apple.") { continue }
            if Leftovers.othersClaim(entry, match: match, theirIDs: theirIDs, theirNames: theirNames) { continue }
            let inLibrary = libraries.contains { path.lowercased().hasPrefix($0) }
            if let match, match != .fuzzy, inLibrary {
                found.append(Leftover(path: path, match: match))
            } else {
                found.append(Leftover(path: path, match: .zap))
            }
        }
        return Leftovers.merge(found)
    }

    /// Where `pattern` is on this Mac, the way brew finds it: `~` is `home`, then wildcards and braces expanded
    /// (glob). Only what exists, normalized. Nothing for a relative path, `~otheruser` or one with `..` in it.
    static func expand(_ pattern: String, home: String) -> [String] {
        var path = pattern
        if path == "~" || path.hasPrefix("~/") { path = home + path.dropFirst() }
        guard path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return [] }
        var found = glob_t()
        defer { globfree(&found) }
        // Without GLOB_NOCHECK a path without wildcards only comes back when it exists.
        guard glob(path, GLOB_BRACE, nil, &found) == 0 else { return [] }
        return (0..<Int(found.gl_pathc)).compactMap { found.gl_pathv[$0].map { String(cString: $0) } }
            .map(Paths.normalize)
    }
}
