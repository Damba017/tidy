import Foundation

/// `taydic leftovers <name>`: what an app or tool that's already gone left behind, found by its name
/// (e.g. one dragged to the Trash before taydic existed). Only for things that aren't installed any
/// more; whatever it finds still goes through the review list and the safety core.
public enum LeftoverSearch {
    /// Why `name` can't be searched for, or nil when it can.
    public static func problem(with name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        if name.contains("/") || name.hasPrefix(".") { return "give the name of an app or tool, not a path" }
        if Leftovers.usableNames([name]).isEmpty || !name.contains(where: { $0.isLetter || $0.isNumber }) {
            return "\"\(name)\" is too short or too common to search for (at least 3 letters, not a word like \"helper\")"
        }
        return nil
    }

    /// Where `name` is still installed, if anywhere: an app or Homebrew package going by exactly that name
    /// (or with it as bundle ID), another app on this Mac that does (macOS's own, a running one), or a
    /// command of that name in `commandFolders`. Its files are in use then. `byUninstall`: it's one
    /// `taydic uninstall` can remove, with what it left behind.
    public static func stillInstalled(_ name: String, candidates: [Candidate], apps: [App], commandFolders: [String])
        -> (what: String, byUninstall: Bool)? {
        let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
        let installed = candidates.first { candidate in
            candidate.names.contains { $0.lowercased() == lower } || candidate.app?.bundleID?.lowercased() == lower
        }
        if let installed { return ("\(installed.name) (\(installed.source.rawValue), \(installed.path))", true) }
        if let app = apps.first(where: { $0.names.contains { $0.lowercased() == lower } || $0.bundleID?.lowercased() == lower }) {
            return ("\(app.name) (\(app.path))", false)
        }
        return commandFolders.map { $0 + "/" + lower }.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { ($0, false) }
    }

    /// Installed or running apps and packages with `name` in their name or bundle ID (Discord PTB for "discord",
    /// Google Chrome and com.google.Chrome for "google"). Their files can look alike, or sit in the same
    /// folder (~/Library/Application Support/Google), so then nothing starts ticked.
    public static func similar(_ name: String, candidates: [Candidate], apps: [App]) -> [String] {
        let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
        func contains(_ names: [String], _ bundleID: String?) -> Bool {
            names.contains { $0.lowercased().contains(lower) } || bundleID?.lowercased().contains(lower) == true
        }
        let found = candidates.filter { contains($0.names, $0.app?.bundleID) }.map(\.name)
            + apps.filter { contains($0.names, $0.bundleID) }.map(\.name)
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }

    /// macOS's own apps (Photos, Notes, Finder, Safari, …): not in /Applications, but very much installed.
    public static func macOSApps() -> [App] {
        AppFinder.installedApps(in: ["/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices",
                                     "/System/Cryptexes/App/System/Applications"])
    }

    /// The folders a command is looked for in: the PATH, plus where Homebrew and ~/.local put theirs.
    public static var commandFolders: [String] {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return (path + ["/opt/homebrew/bin", Paths.home + "/.local/bin"]).filter { $0.hasPrefix("/") }
    }

    /// What's left of `name`: in the Library folders `taydic uninstall` looks in (by name, or fuzzy) and the
    /// dotfiles a command-line tool leaves (~/.config/<name>, …). What another app on this Mac claims, by
    /// bundle ID or by name, is left out, and so are dotfiles macOS's own tool of that name uses.
    public static func find(_ name: String, home: String = Paths.home, others: [App]) -> [Leftover] {
        find(name, home: home, toolFolders: Leftovers.macOSToolFolders, others: others)
    }

    static func find(_ name: String, home: String, toolFolders: [String], others: [App]) -> [Leftover] {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard problem(with: name) == nil else { return [] }
        let library = Leftovers.find(bundleID: nil, names: [name], home: home, others: others)
        // As spelled on disk: the user may type "Discord" for ~/.config/discord.
        let dotfiles = Leftovers.macOSTool(name, in: toolFolders) != nil ? []
            : Leftovers.dotfiles(for: name, home: home).map { Leftover(path: Paths.normalize($0.path), match: $0.match) }
        let theirIDs = others.compactMap(\.bundleID)
        return Leftovers.merge((library + dotfiles).filter { leftover in
            let entry = (leftover.path as NSString).lastPathComponent
            return !theirIDs.contains { Leftovers.match(entry, bundleID: $0, names: []) == .bundleID }
        })
    }
}
