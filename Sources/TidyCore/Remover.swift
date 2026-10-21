import Foundation

public struct RemovalResult: Sendable {
    public var moved = 0
    public var bytes: Int64 = 0
    public var failed = 0
}

/// The only way taydic removes anything: show the whole plan, ask, then move to the Trash.
public enum Remover {
    /// The answer to the question about the doubtful items.
    public enum Choice: Sendable {
        case all
        case oneByOne
        case none
    }

    /// Prints the full `plan` with `say` (what, from where, how big), then asks:
    /// - `ask` (y/N) once for the sure items that can go to the Trash;
    /// - `choose` (all / one by one / none) for the doubtful items; after an N on one of them,
    ///   `choose` comes back for the ones that are left;
    /// - `ask` (y/N) once for everything that needs sudo.
    /// Right after the yes that moves an app with a privacy reset in the plan: `ask` (y/N) for that reset,
    /// which then runs right before the app goes (tccutil can't find the app once it's gone).
    /// `ask` returns true only for an explicit yes; `choose` returns `.none` for anything unclear.
    /// With `dryRun` it prints the plan and stops: no questions, no changes, no log.
    public static func run(
        _ plan: RemovalPlan,
        dryRun: Bool,
        say: (String) -> Void,
        ask: (String) -> Bool,
        choose: (String) -> Choice
    ) -> RemovalResult {
        run(plan, dryRun: dryRun, say: say, ask: ask, choose: choose, log: .standard, sudo: Sudo.run,
            launchctl: Launchctl.run, tccutil: Tccutil.run, trashItem: Trash.system)
    }

    /// Same, with the log, sudo, launchctl, tccutil and the final Trash move passed in. No defaults on purpose:
    /// tests must name their fakes, so they can never reach the real ones by accident.
    static func run(
        _ plan: RemovalPlan,
        dryRun: Bool,
        say: (String) -> Void,
        ask: (String) -> Bool,
        choose: (String) -> Choice,
        log: Log,
        sudo: ([String]) -> Int32,
        launchctl: ([String]) -> Int32,
        tccutil: ([String]) -> (status: Int32, message: String),
        trashItem: (String) throws -> String
    ) -> RemovalResult {
        plan.render().forEach(say)
        let sure = plan.sure
        let doubtful = plan.doubtful
        var root = plan.root
        var result = RemovalResult()
        if sure.isEmpty && doubtful.isEmpty && root.isEmpty {
            say("Nothing to remove.")
            return result
        }
        if dryRun {
            for reset in plan.privacy {
                say("--dry-run: would run tccutil \(Tccutil.reset(reset.bundleID).joined(separator: " ")) after its own yes.")
            }
            say("--dry-run: nothing was changed.")
            return result
        }

        var logFailed = false
        var logged = false
        func record(_ write: () throws -> Void) {
            do {
                try write()
                logged = true
            } catch {
                if !logFailed { say("WARNING: \(error)") }
                logFailed = true
            }
        }
        // Results go right under the answer, per folder like the plan: the folder once, then the names.
        var shownFolder: String?
        func underItsFolder(_ item: RemovalPlan.Item) {
            let folder = Paths.parent(item.path)
            if folder != shownFolder { say(Output.folderLine(folder)) }
            shownFolder = folder
        }
        func moved(_ item: RemovalPlan.Item, to destination: String, sudo: Bool) {
            result.moved += 1
            result.bytes += item.size
            underItsFolder(item)
            let name = (item.path as NSString).lastPathComponent
            // Where it went only when the Trash had to give it another name ("notes 2"); the log always says.
            let renamed = (destination as NSString).lastPathComponent == name ? "" : "  →  " + Paths.display(destination)
            say("    moved   " + name + renamed)
            record { try log.moved(item.path, size: item.size, to: destination, sudo: sudo) }
        }
        func failed(_ item: RemovalPlan.Item, _ reason: String, detail: String? = nil, sudo: Bool) {
            result.failed += 1
            underItsFolder(item)
            say("    FAILED  " + (item.path as NSString).lastPathComponent + ": " + reason)
            record { try log.failed(item.path, error: detail ?? reason, sudo: sudo) }
        }

        // Privacy resets: asked right after the yes that moves the app (once per app), run right before it goes.
        var resetAsked = Set<String>()
        var resetApproved = Set<String>()
        func offerReset(for items: [RemovalPlan.Item]) {
            let resets = plan.privacy.filter { reset in !resetAsked.contains(reset.app) && items.contains { $0.path == reset.app } }
            guard !resets.isEmpty else { return }
            resetAsked.formUnion(resets.map(\.app))
            let which = resets.count == 1
                ? "\(resets[0].name) (tccutil reset All \(resets[0].bundleID))"
                : "\(resets.map(\.name).joined(separator: ", ")) (tccutil reset All, per app)"
            if ask("Also reset the privacy permissions of \(which)?") { resetApproved.formUnion(resets.map(\.app)) }
        }
        /// Runs the approved reset for `item` (never for a path the Trash would refuse); the line to show under it.
        func resetPermissions(before item: RemovalPlan.Item) -> String? {
            guard resetApproved.contains(item.path), let reset = plan.privacy.first(where: { $0.app == item.path }),
                  Denylist.reason(for: item.path, home: plan.home) == nil else { return nil }
            let command = "tccutil " + Tccutil.reset(reset.bundleID).joined(separator: " ")
            let (status, message) = tccutil(Tccutil.reset(reset.bundleID))
            if status == 0 {
                record { try log.reset(reset.app, "privacy permissions: \(command)") }
                return "    reset   privacy permissions of \(reset.name)"
            }
            result.failed += 1
            let why = message.isEmpty ? "tccutil failed (exit \(status))" : message
            record { try log.failed(reset.app, error: "privacy permissions: \(command): \(why)", sudo: false) }
            return "    FAILED  privacy permissions of \(reset.name): " + why
        }

        func moveToTrash(_ items: [RemovalPlan.Item]) {
            shownFolder = nil
            for item in items {
                // Stop a launch agent before its plist goes, but never for a path the Trash would refuse.
                if Launchctl.domain(of: item.path) == .user, Denylist.reason(for: item.path, home: plan.home) == nil {
                    _ = launchctl(Launchctl.bootout(item.path, in: .user))
                }
                let reset = resetPermissions(before: item)
                do {
                    moved(item, to: try Trash.move(item.path, home: plan.home, using: trashItem), sudo: false)
                } catch let error as TidyError {
                    failed(item, error.description, detail: error.detail, sudo: false)
                } catch {
                    failed(item, "\(error)", sudo: false)
                }
                reset.map(say)
            }
        }
        func total(_ items: [RemovalPlan.Item]) -> String {
            Size.format(items.reduce(0) { $0 + $1.size })
        }
        var askedBefore = false

        if !sure.isEmpty {
            askedBefore = true
            if ask("Move \(RemovalPlan.describe(sure)) to the Trash?") {
                offerReset(for: sure)
                moveToTrash(sure)
            } else {
                say("Nothing moved to the Trash.")
            }
        }

        // Doubtful items never go along on the same "y" as the sure ones.
        if !doubtful.isEmpty {
            if askedBefore {
                // Show them again right before the question; the list above may have scrolled away.
                say("")
                say("Asked separately: \(plan.doubtfulCount(doubtful.count)), \(total(doubtful))")
                RemovalPlan.listed(doubtful) { item, name in
                    "      " + name + [item.note, item.status == .sudo ? "needs sudo" : nil].compactMap { $0 }
                        .map { "  (\($0))" }.joined()
                }.forEach(say)
                say("")
            }
            askedBefore = true
            var remaining = doubtful
            var approved: [RemovalPlan.Item] = []
            while !remaining.isEmpty {
                let which = remaining.count != doubtful.count ? "the remaining " : "the "
                switch choose("Move \(which)\(plan.doubtfulCount(remaining.count)) (\(total(remaining))) to the Trash?") {
                case .all:
                    approved += remaining
                    remaining = []
                case .none:
                    say("Kept \(plan.doubtfulCount(remaining.count)).")
                    remaining = []
                case .oneByOne:
                    // One at a time; an N keeps that one and goes back to the question above for the rest.
                    while let item = remaining.first {
                        remaining.removeFirst()
                        let extra = [Size.format(item.size), item.note, item.status == .sudo ? "needs sudo" : nil]
                            .compactMap { $0 }.joined(separator: ", ")
                        guard ask("Move \(Paths.display(item.path)) (\(extra)) to the Trash?") else { break }
                        approved.append(item)
                    }
                }
            }
            offerReset(for: approved)
            moveToTrash(approved.filter { $0.status == .trash })
            // They still get the sudo question below.
            root = RemovalPlan.byFolder(root + approved.filter { $0.status == .sudo })
        }

        if !root.isEmpty {
            if askedBefore { say("") }
            if askedBefore && root.count > 1 {
                // Show them again right before the question; the list above may have scrolled away.
                say("Needs administrator rights (sudo): \(RemovalPlan.describe(root))")
                RemovalPlan.listed(root) { _, name in "      " + name }.forEach(say)
                say("")
            }
            let question = root.count == 1
                ? "\(Paths.display(root[0].path)) (\(total(root))) needs administrator rights (sudo). Continue?"
                : "These \(root.count) items need administrator rights (sudo). Continue?"
            if ask(question) {
                offerReset(for: root)
                let it = root.count == 1 ? ("it", "it") : ("them", "they")
                say("sudo asks for your password once. \"Put Back\" won't work for \(it.0); the log says where \(it.1) came from.")
                say("Emptying the Trash will ask for your password too.")
                if sudo(["-v"]) == 0 {
                    shownFolder = nil
                    for (index, item) in root.enumerated() {
                        if let reason = Denylist.reason(for: item.path, home: plan.home) {
                            failed(item, "refused (\(reason))", sudo: true)
                            continue
                        }
                        // The name in the Trash first: when taydic can't see what's there, nothing is stopped or moved.
                        let destination: String
                        do {
                            destination = try Trash.freeDestination(for: item.path, in: plan.home + "/.Trash")
                        } catch {
                            say("\(error): nothing more is moved with sudo.")
                            for rest in root[index...] { failed(rest, "not moved", sudo: true) }
                            break
                        }
                        switch Launchctl.domain(of: item.path) {
                        case .user: _ = launchctl(Launchctl.bootout(item.path, in: .user))
                        case .system: _ = sudo(["-n", "/bin/launchctl"] + Launchctl.bootout(item.path, in: .system))
                        case nil: break
                        }
                        let reset = resetPermissions(before: item)
                        let status = sudo(Sudo.moveCommand(from: item.path, to: destination))
                        if status == 0 && !Paths.exists(item.path) && Paths.exists(destination) {
                            moved(item, to: destination, sudo: true)
                        } else if status == 0 && Paths.exists(item.path) {
                            // mv -n never overwrites: someone took the name in the meantime.
                            failed(item, "not moved, \(Paths.display(destination)) was taken", sudo: true)
                        } else {
                            failed(item, "sudo mv failed (exit \(status))", sudo: true)
                        }
                        reset.map(say)
                    }
                } else {
                    say("sudo failed: nothing was moved with sudo.")
                    result.failed += root.count
                }
            } else {
                say("Skipped the items that need sudo.")
            }
        }

        if result.moved > 0 || result.failed > 0 {
            let moved = result.moved == 0 ? "nothing moved"
                : "\(RemovalPlan.count(result.moved)) (\(Size.format(result.bytes))) moved to the Trash"
            say("")
            say("Done: " + moved + (result.failed == 0 ? "." : ", \(result.failed) failed (see above)."))
            if logged { say("Log: \(Paths.display(log.path))") }
        }
        return result
    }
}
