import Foundation

public struct RemovalResult: Sendable {
    public var moved = 0
    public var bytes: Int64 = 0
    public var failed = 0
}

/// The only way tidy removes anything: show the whole plan, ask, then move to the Trash.
public enum Remover {
    /// Prints the full `plan` with `say` (what, from where, how big), then asks with `ask`:
    /// once for everything that can go to the Trash, once for everything that needs sudo.
    /// `ask` gets the question without "(y/N)" and returns true only for an explicit yes.
    /// With `dryRun` it prints the plan and stops: no questions, no changes, no log.
    public static func run(
        _ plan: RemovalPlan,
        dryRun: Bool,
        say: (String) -> Void,
        ask: (String) -> Bool
    ) -> RemovalResult {
        run(plan, dryRun: dryRun, say: say, ask: ask, log: .standard, sudo: Sudo.run, launchctl: Launchctl.run,
            trashItem: Trash.system)
    }

    /// Same, with the log, sudo, launchctl and the final Trash move passed in. No defaults on purpose:
    /// tests must name their fakes, so they can never reach the real ones by accident.
    static func run(
        _ plan: RemovalPlan,
        dryRun: Bool,
        say: (String) -> Void,
        ask: (String) -> Bool,
        log: Log,
        sudo: ([String]) -> Int32,
        launchctl: ([String]) -> Int32,
        trashItem: (String) throws -> String
    ) -> RemovalResult {
        plan.render().forEach(say)
        let sure = plan.sure
        let fuzzy = plan.fuzzy
        var root = plan.root
        var result = RemovalResult()
        if sure.isEmpty && fuzzy.isEmpty && root.isEmpty {
            say("Nothing to remove.")
            return result
        }
        if dryRun {
            say("--dry-run: nothing was changed.")
            return result
        }

        var logFailed = false
        func record(_ write: () throws -> Void) {
            do { try write() } catch {
                if !logFailed { say("WARNING: \(error)") }
                logFailed = true
            }
        }
        func moved(_ item: RemovalPlan.Item, to destination: String, sudo: Bool) {
            result.moved += 1
            result.bytes += item.size
            say("  moved   \(Paths.display(item.path))  →  \(Paths.display(destination))")
            record { try log.moved(item.path, size: item.size, to: destination, sudo: sudo) }
        }
        func failed(_ item: RemovalPlan.Item, _ error: String, sudo: Bool) {
            result.failed += 1
            say("  FAILED  \(error)")
            record { try log.failed(item.path, error: error, sudo: sudo) }
        }

        func moveToTrash(_ items: [RemovalPlan.Item]) {
            for item in items {
                // Stop a launch agent before its plist goes, but never for a path the Trash would refuse.
                if Launchctl.domain(of: item.path) == .user, Denylist.reason(for: item.path, home: plan.home) == nil {
                    _ = launchctl(Launchctl.bootout(item.path, in: .user))
                }
                do {
                    moved(item, to: try Trash.move(item.path, home: plan.home, using: trashItem), sudo: false)
                } catch {
                    failed(item, "\(error)", sudo: false)
                }
            }
        }
        var askedBefore = false

        if !sure.isEmpty {
            askedBefore = true
            if ask("Move \(RemovalPlan.describe(sure)) to the Trash?") {
                moveToTrash(sure)
            } else {
                say("Nothing moved to the Trash.")
            }
        }

        // Fuzzy matches never go along on the same "y" as the sure ones.
        if !fuzzy.isEmpty {
            if askedBefore {
                // Show them again right before the question; the list above may have scrolled away.
                say("")
                say("Fuzzy matches (only the name looks alike): \(RemovalPlan.describe(fuzzy))")
                fuzzy.forEach { say("  " + Paths.display($0.path)) }
            }
            askedBefore = true
            let size = Size.format(fuzzy.reduce(0) { $0 + $1.size })
            let question = fuzzy.count == 1
                ? "Also move this fuzzy match (\(size)) to the Trash?"
                : "Also move these \(fuzzy.count) fuzzy matches (\(size)) to the Trash?"
            if ask(question) {
                moveToTrash(fuzzy.filter { $0.status == .trash })
                root += fuzzy.filter { $0.status == .sudo }  // they still get the sudo question below
            } else {
                say("Kept the fuzzy matches.")
            }
        }

        if !root.isEmpty {
            if askedBefore {
                // Show them again right before the question; the list above may have scrolled away.
                say("")
                say("Needs administrator rights (sudo): \(RemovalPlan.describe(root))")
                root.forEach { say("  " + Paths.display($0.path)) }
            }
            let question = root.count == 1
                ? "This item needs administrator rights (sudo). Continue?"
                : "These \(root.count) items need administrator rights (sudo). Continue?"
            if ask(question) {
                say("sudo asks for your password once. Finder's \"Put Back\" won't work for these;")
                say("the log records where they came from. Emptying the Trash will ask for your password too.")
                if sudo(["-v"]) == 0 {
                    for item in root {
                        if let reason = Denylist.reason(for: item.path, home: plan.home) {
                            failed(item, "refused \(Paths.display(item.path)): \(reason)", sudo: true)
                            continue
                        }
                        switch Launchctl.domain(of: item.path) {
                        case .user: _ = launchctl(Launchctl.bootout(item.path, in: .user))
                        case .system: _ = sudo(["-n", "/bin/launchctl"] + Launchctl.bootout(item.path, in: .system))
                        case nil: break
                        }
                        let destination = Trash.freeDestination(for: item.path, in: plan.home + "/.Trash")
                        let status = sudo(Sudo.moveCommand(from: item.path, to: destination))
                        if status == 0 && !Paths.exists(item.path) && Paths.exists(destination) {
                            moved(item, to: destination, sudo: true)
                        } else {
                            failed(item, "\(Paths.display(item.path)): sudo mv failed (exit \(status))", sudo: true)
                        }
                    }
                } else {
                    say("sudo failed: nothing was moved with sudo.")
                    result.failed += root.count
                }
            } else {
                say("Skipped the items that need sudo.")
            }
        }

        say("")
        if result.moved > 0 {
            let total = Size.format(result.bytes)
            say("Moved \(RemovalPlan.count(result.moved)) (\(total)) to the Trash. Log: \(Paths.display(log.path))")
        }
        if result.failed > 0 {
            say("\(RemovalPlan.count(result.failed)) failed, see above.")
        }
        return result
    }
}
