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
        run(candidate, dryRun: dryRun, say: say, ask: ask, home: Paths.home, temp: Paths.userTempFolders,
            toolFolders: Leftovers.macOSToolFolders, others: Leftovers.otherApps(than: candidate.app),
            processes: RunningApps.processPaths(), query: Brew.query, brew: Brew.run,
            remove: { plan in _ = Remover.run(plan, dryRun: dryRun, say: say, ask: ask, choose: choose) })
    }

    /// Same, with brew and the removal passed in. No defaults on purpose: tests must name their fakes.
    static func run(
        _ candidate: Candidate,
        dryRun: Bool,
        say: (String) -> Void,
        ask: (String) -> Bool,
        home: String,
        temp: [String],
        toolFolders: [String],
        others: [App],
        processes: [String],
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
        // Without --zap, what the cask's zap list names is offered below, for the Trash. Read before the
        // uninstall, while brew certainly still has the cask. Nil: brew's answer couldn't be read.
        var zapList: [String]? = []
        let zapQuery = ["info", "--cask", "--json=v2", package.name]
        if dryRun {
            say("--dry-run: would run: brew \(arguments.joined(separator: " "))")
            if package.kind == .cask {
                say("(taydic would also ask whether to use --zap; the answer would default to No.)")
                zapList = Brew.zapPaths(query(zapQuery))
            }
        } else {
            guard ask("Uninstall \(package.name) (via brew)?") else {
                say("Skipped \(package.name); its leftovers stay too.")
                return false
            }
            if package.kind == .cask {
                say("brew can also --zap: it then deletes the files the cask lists as its own (settings, caches)")
                say("right away, NOT via the Trash. Without it, taydic offers those for the Trash below,")
                say("with what it finds itself; what may be another app's too is asked separately.")
                if ask("Use --zap?") {
                    arguments = Brew.uninstallArguments(package, zap: true)
                } else {
                    zapList = Brew.zapPaths(query(zapQuery))
                }
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
        let notSearched = Leftovers.unreadable(Leftovers.locations(home: home, temp: temp))
        if !notSearched.isEmpty {
            say("Not searched, so leftovers in there can't be found:")
            notSearched.forEach { say(Output.folderLine($0.path) + "  (\($0.reason))") }
        }
        if zapList == nil {
            say("Couldn't read \(package.name)'s zap list from brew, so only what taydic finds itself is offered.")
        }
        // The cask's app (and so its bundle ID) came from before the uninstall, so it still counts.
        let own = Leftovers.merge(
            (macOSTool == nil ? dotfiles : [])
                + Leftovers.find(bundleID: candidate.app?.bundleID, names: candidate.names, home: home, temp: temp, others: others))
        // What the zap list adds: only what taydic's own search didn't find.
        let found = Set(own.map { Paths.normalize($0.path) })
        let fromZap = ZapList.leftovers(zapList ?? [], bundleID: candidate.app?.bundleID, names: candidate.names,
                                        app: candidate.app?.path, home: home, others: others)
            .filter { !found.contains($0.path) }
        var leftovers = Leftovers.merge(own + fromZap)
        // A program of that name still running (a formula's server, say) uses its temp files: they stay.
        let inTemp = leftovers.filter { leftover in temp.contains { leftover.path.hasPrefix($0 + "/") } }
        if let running = processes.first(where: { ($0 as NSString).lastPathComponent.lowercased() == package.name.lowercased() }),
           !inTemp.isEmpty {
            say("Kept \(inTemp.map(\.path).map(Paths.display).joined(separator: ", ")): \(package.name) is still running (\(running)).")
            leftovers.removeAll { leftover in inTemp.contains { $0.path == leftover.path } }
        }
        guard !leftovers.isEmpty else {
            say("No \(kept.isEmpty ? "" : "other ")leftovers found for \(package.name).")
            return true
        }
        say("")
        say("Leftovers of \(package.name):")
        let fuzzy = leftovers.filter { $0.match == .fuzzy }.map(\.path)
        let unsure = leftovers.filter { $0.match == .zap }.map(\.path)
        let notes = Dictionary(fromZap.map { ($0.path, "from the cask's zap list") }, uniquingKeysWith: { first, _ in first })
        remove(RemovalPlan(paths: leftovers.map(\.path), doubtful: unsure.isEmpty ? .fuzzy(fuzzy) : .uncertain(fuzzy: fuzzy, zap: unsure),
                           notes: notes, home: home))
        return true
    }
}
