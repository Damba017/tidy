import Foundation
import TidyCore

/// `taydic leftovers <name>`: what an app or tool that's already gone left behind, found by its name.
/// Refuses a name that's still installed (that's `taydic uninstall`). Then the review list and the
/// safety core, with the fuzzy matches unticked and asked about separately, like everywhere.
/// Without a name (from the menu) it asks for one.
func runLeftovers(name: String?, dryRun: Bool) -> Int32 {
    let interactive = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    guard let name = (name ?? askForName())?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
        print("Nothing searched; nothing was changed.")
        return 0
    }
    if let problem = LeftoverSearch.problem(with: name) {
        FileHandle.standardError.write(Data("taydic: \(problem).\n".utf8))
        return 2
    }
    if Brew.isInstalled { print("Asking Homebrew what's installed…") }
    let candidates = Candidates.all()
    let apps = Leftovers.otherApps(than: nil) + LeftoverSearch.macOSApps()  // installed, running and macOS's own
    if let installed = LeftoverSearch.stillInstalled(name, candidates: candidates, apps: apps,
                                                     commandFolders: LeftoverSearch.commandFolders,
                                                     processes: RunningApps.processPaths()) {
        show("")
        show("\(name) is still installed: \(installed.what).")
        show(installed.byUninstall
            ? "Its files are still in use. To remove it with what it left behind: taydic uninstall \(name)"
            : "Its files are still in use, so taydic leaves them alone.")
        return 1
    }

    show("")
    // An installed app with a name like it (or "google" in com.google.Chrome) may keep its files in the same
    // places, even in a folder called exactly that: then nothing starts ticked and everything is asked separately.
    let similar = LeftoverSearch.similar(name, candidates: candidates, apps: apps)
    if !similar.isEmpty {
        show("Careful: \(similar.joined(separator: ", ")) \(similar.count == 1 ? "is" : "are") installed with a name like it;"
            + " \(similar.count == 1 ? "its" : "their") files can look alike. Nothing starts ticked, and everything is asked separately.")
    }
    show("Looking for leftovers of \"\(name)\"…")
    let found = LeftoverSearch.find(name, others: apps)
    let (group, privacyProtected, sipProtected) = reviewGroup(
        title: "Leftovers of \"\(name)\"", detail: "not installed any more",
        entries: found.map { ($0.path, $0.match.label, similar.isEmpty && $0.checkedByDefault) })
    let list = ReviewList(groups: [group])
    let notSearched = Leftovers.unreadable(Leftovers.locations())
    guard !list.groups.isEmpty else {
        showSIPNote(sipProtected)
        showPrivacyNotes(protected: privacyProtected, notSearched: notSearched)
        show("")
        show("No leftovers of \"\(name)\" found; nothing was changed.")
        return 0
    }

    let selected: [String]
    if interactive {
        Terminal.start()
        let result = review(list, title: "leftovers", dryRun: dryRun)
        Terminal.stop()
        guard let result else {
            print("Cancelled; nothing was changed.")
            return 0
        }
        selected = result
    } else {
        printPlain(list)
        selected = list.selectedPaths
    }
    showSIPNote(sipProtected)
    showPrivacyNotes(protected: privacyProtected, notSearched: notSearched)
    guard !selected.isEmpty else {
        print("Nothing selected; nothing was changed.")
        return 0
    }

    // Ticked fuzzy matches get their own block and question in the plan (all of them, when it looks like an installed app).
    let fuzzy = found.filter { !similar.isEmpty || $0.match == .fuzzy }.map(\.path)
    show("")
    let result = Remover.run(RemovalPlan(paths: selected, doubtful: .fuzzy(fuzzy)), dryRun: dryRun,
                             say: show, ask: ask, choose: choose)
    return result.failed == 0 ? 0 : 1
}

/// From the menu: the name to look for, or nil when the user just presses Enter.
private func askForName() -> String? {
    print("Leftovers of which app or tool? (its name, Enter to cancel) ", terminator: "")
    fflush(stdout)
    return readLine()
}
