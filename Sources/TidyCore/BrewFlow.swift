import Foundation

/// The Homebrew part of `taydic uninstall`, one package at a time: warn about dependents, ask,
/// `brew uninstall` (brew owns that step), then the leftovers through the safety core.
public enum BrewFlow {
    /// True when the package was uninstalled, or would be in a dry run.
    public static func run(
        _ candidate: Candidate,
        dryRun: Bool,
        say: (String) -> Void,
        ask: (String) -> Bool,
        choose: (String) -> Remover.Choice
    ) -> Bool {
        run(candidate, dryRun: dryRun, say: say, ask: ask, home: Paths.home, toolFolders: Leftovers.macOSToolFolders,
            others: Leftovers.otherApps(than: candidate.app), query: Brew.query, brew: Brew.run,
            remove: { plan in _ = Remover.run(plan, dryRun: dryRun, say: say, ask: ask, choose: choose) })
    }

    /// Same, with brew and the removal passed in. No defaults on purpose: tests must name their fakes.
    static func run(
        _ candidate: Candidate,
        dryRun: Bool,
        say: (String) -> Void,
        ask: (String) -> Bool,
        home: String,
        toolFolders: [String],
        others: [App],
        query: ([String]) -> String,
        brew: ([String]) -> Int32,
        remove: (RemovalPlan) -> Void
    ) -> Bool {
        guard let package = candidate.package else { return false }
        say("\(package.name) is installed via Homebrew (\(package.kind.rawValue)).")
        if package.kind == .formula {
            let users = Brew.lines(query(["uses", "--installed", package.name]))
            if !users.isEmpty {
                say("Warning: \(users.joined(separator: ", ")) \(users.count == 1 ? "depends" : "depend") on \(package.name), "
                    + "so brew will likely refuse to uninstall it.")
            }
        }

        var arguments = Brew.uninstallArguments(package, zap: false)
        if dryRun {
            say("--dry-run: would run: brew \(arguments.joined(separator: " "))")
            if package.kind == .cask { say("(taydic would also ask whether to use --zap; the answer would default to No.)") }
        } else {
            guard ask("Uninstall \(package.name) (via brew)?") else {
                say("Skipped \(package.name); its leftovers stay too.")
                return false
            }
            if package.kind == .cask {
                say("brew can also --zap: it then deletes the files the cask lists as its own (settings, caches)")
                say("right away, NOT via the Trash. Without it, taydic offers those leftovers for the Trash below.")
                if ask("Use --zap?") { arguments = Brew.uninstallArguments(package, zap: true) }
            }
            say("Running: brew \(arguments.joined(separator: " "))")
            let status = brew(arguments)
            guard status == 0 else {
                say("brew uninstall failed (exit \(status)), so the leftovers were left alone.")
                return false
            }
        }

        // Dotfiles of a tool macOS has too (zsh, vim, git, …) are shared with macOS's own one: they stay.
        let dotfiles = Leftovers.dotfiles(for: package.name, home: home)
        let macOSTool = Leftovers.macOSTool(package.name, in: toolFolders)
        let kept = macOSTool == nil ? [] : dotfiles.map(\.path)
        if let macOSTool, !kept.isEmpty {
            say("Kept \(kept.map(Paths.display).joined(separator: ", ")): macOS's own \(package.name) "
                + "(\(macOSTool)) uses \(kept.count == 1 ? "it" : "them") too.")
        }
        let notSearched = Leftovers.unreadable(Leftovers.locations(home: home))
        if !notSearched.isEmpty {
            say("Not searched, so leftovers in there can't be found:")
            notSearched.forEach { say("  \(Paths.display($0.path))  (\($0.reason))") }
        }
        // The cask's app (and so its bundle ID) came from before the uninstall, so it still counts.
        let leftovers = Leftovers.merge(
            (macOSTool == nil ? dotfiles : [])
                + Leftovers.find(bundleID: candidate.app?.bundleID, names: candidate.names, home: home, others: others))
        guard !leftovers.isEmpty else {
            say("No \(kept.isEmpty ? "" : "other ")leftovers found for \(package.name).")
            return true
        }
        say("")
        say("Leftovers of \(package.name):")
        let fuzzy = leftovers.filter { $0.match == .fuzzy }.map(\.path)
        remove(RemovalPlan(paths: leftovers.map(\.path), doubtful: .fuzzy(fuzzy), home: home))
        return true
    }
}
