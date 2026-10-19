import Foundation
import TidyCore

/// `taydic uninstall [name...]`: find what to remove, quit running apps, then the .app part (review +
/// safety core) and after that the brew flow per package. Saying no in one part skips only that part.
func runUninstall(names: [String], dryRun: Bool) -> Int32 {
    let interactive = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    if Brew.isInstalled { print("Asking Homebrew what's installed…") }
    let candidates = Candidates.all()
    var targets: [Candidate] = []
    func add(_ candidate: Candidate) {
        if !targets.contains(candidate) { targets.append(candidate) }
    }

    if names.isEmpty {
        guard interactive else {
            FileHandle.standardError.write(Data("taydic: give one or more names when not running in a terminal.\n".utf8))
            return 2
        }
        print("Measuring \(candidates.count) apps and packages…")
        let sizes = measure(candidates.map(\.path))
        Terminal.start()
        let picked = pick(candidates, sizes: sizes, dryRun: dryRun)
        Terminal.stop()
        guard let picked, !picked.isEmpty else {
            print("Nothing selected; nothing was changed.")
            return 0
        }
        picked.forEach(add)
    } else {
        for name in names {
            // A path to an app bundle is taken as is; one a cask owns still goes via brew. Any other path is refused.
            if name.contains("/") || name.lowercased().hasSuffix(".app") {
                if let candidate = Candidates.app(at: name, in: candidates) {
                    add(candidate)
                    continue
                }
                if name.contains("/") {
                    print("Not an app (a folder ending in .app, with an Info.plist): \(Paths.display(Paths.normalize(name))); skipped.")
                    continue
                }
            }
            let found = Candidates.matches(name, in: candidates)
            switch found.count {
            case 0: print("Nothing matches \"\(name)\"; skipped.")
            case 1: add(found[0])
            default:
                if let choice = pickOne(name, from: found, interactive: interactive) { add(choice) } else { print("Skipped \"\(name)\".") }
            }
        }
    }
    guard !targets.isEmpty else {
        print("Nothing to uninstall.")
        return 0
    }

    show("")
    show("Found \(targets.count):")
    for candidate in targets {
        show("  \(candidate.name)  ·  \(candidate.source.rawValue)  ·  \(candidate.path)")
    }

    let running = targets.filter { $0.app.map(RunningApps.isRunning) ?? false }
    if !running.isEmpty {
        let list = running.map(\.name).joined(separator: ", ")
        let one = running.count == 1
        show("")
        if dryRun {
            show("--dry-run: would ask to quit \(list) first.")
        } else if ask("\(list) \(one ? "is" : "are") running. Quit \(one ? "it" : "them") now?") {
            for candidate in running {
                if RunningApps.quit(candidate.app!) {
                    show("  quit    \(candidate.name)")
                } else {
                    show("\(candidate.name) didn't quit, so it's skipped. Quit it yourself and run taydic again.")
                    targets.removeAll { $0 == candidate }
                }
            }
        } else {
            show("Skipped \(list): \(one ? "it's" : "they're") still running.")
            targets.removeAll { running.contains($0) }
        }
    }

    var ok = true
    let apps = targets.filter { $0.package == nil }.compactMap(\.app)
    let viaBrew = targets.filter { $0.package != nil }
    if !apps.isEmpty {
        // Brew packages aren't in the review list (brew removes them, not taydic), so say they come next.
        let note = viaBrew.isEmpty ? nil
            : "After this list: " + viaBrew.map { "\($0.name) (\($0.source.rawValue))" }.joined(separator: ", ")
                + ", via brew with " + (viaBrew.count == 1 ? "its" : "their") + " own questions."
        ok = uninstallApps(apps, dryRun: dryRun, interactive: interactive, note: note)
    }
    for candidate in viaBrew {
        show("")
        _ = BrewFlow.run(candidate, dryRun: dryRun, say: show, ask: ask, choose: choose)
    }
    return ok ? 0 : 1
}

/// The .app part: one review list for all apps and their leftovers, then the safety core.
/// False if something failed to move.
private func uninstallApps(_ apps: [App], dryRun: Bool, interactive: Bool, note: String?) -> Bool {
    show("")
    show("Looking for leftovers…")
    let found = apps.map(group(for:))
    let list = ReviewList(groups: found.map(\.group))
    let privacyProtected = found.flatMap(\.privacyProtected)
    let selected: [String]
    if interactive {
        Terminal.start()
        let result = review(list, title: "uninstall", dryRun: dryRun, note: note)
        Terminal.stop()
        guard let result else {
            print("Cancelled; no apps were changed.")
            return true
        }
        selected = result
    } else {
        printPlain(list)
        if let note { print(note) }
        selected = list.selectedPaths
    }
    showPrivacyNotes(protected: privacyProtected, notSearched: Leftovers.unreadable(Leftovers.locations()))
    guard !selected.isEmpty else {
        print("Nothing selected; no apps were changed.")
        return true
    }

    // Ticked fuzzy matches get their own block and question in the plan.
    let fuzzyLabel = Leftover.Match.fuzzy.label
    let fuzzy = list.groups.flatMap { $0.items.filter { $0.label == fuzzyLabel }.map(\.path) }
    show("")
    let result = Remover.run(RemovalPlan(paths: selected, doubtful: .fuzzy(fuzzy)), dryRun: dryRun,
                             say: show, ask: ask, choose: choose)
    return result.failed == 0
}

/// The app bundle plus everything it left behind, as one group of the review list.
/// Protected or missing paths never make it into the list; the ones macOS privacy protection
/// keeps taydic out of are returned separately so the user hears about them.
private func group(for app: App) -> (group: ReviewList.Group, privacyProtected: [String]) {
    let candidates = [(app.path, "app", true)] + Leftovers.find(for: app).map { ($0.path, $0.match.label, $0.checkedByDefault) }
    var items: [ReviewList.Item] = []
    var privacyProtected: [String] = []
    for (path, label, checked) in candidates {
        guard let planned = RemovalPlan(paths: [path]).items.first else { continue }
        switch planned.status {
        case .trash, .sudo:
            items.append(ReviewList.Item(path: planned.path, size: planned.size, label: label,
                                         needsSudo: planned.status == .sudo, checked: checked))
        case .blocked(RemovalPlan.privacyReason):
            privacyProtected.append(planned.path)
        case .blocked, .missing:
            break
        }
    }
    let group = ReviewList.Group(title: app.name, detail: "\(app.source.rawValue) · \(Paths.display(app.path))", items: items)
    return (group, privacyProtected)
}

/// Several candidates match `name`: let the user pick one by number.
private func pickOne(_ name: String, from candidates: [Candidate], interactive: Bool) -> Candidate? {
    print("\"\(name)\" matches \(candidates.count):")
    for (index, candidate) in candidates.enumerated() {
        print("  \(index + 1)  \(fit(candidate.name, 24))  \(fit(candidate.source.rawValue, 16))  \(candidate.path)")
    }
    guard interactive else { return nil }
    print("Which one? (number, Enter to skip) ", terminator: "")
    fflush(stdout)
    guard let line = readLine(), let number = Int(line.trimmingCharacters(in: .whitespaces)),
          candidates.indices.contains(number - 1) else { return nil }
    return candidates[number - 1]
}

/// The multi-select list of apps and brew packages: type to filter, space to select, Enter to continue.
private func pick(_ candidates: [Candidate], sizes: [String: Int64], dryRun: Bool) -> [Candidate]? {
    var picker = AppPicker(candidates: candidates)
    var top = 0
    while true {
        let (height, width) = Terminal.size()
        let w = max(20, width - 1)
        let shown = picker.visible
        var lines = [
            fit("taydic uninstall  pick what to remove" + (dryRun ? "   [dry-run]" : ""), w),
            fit(picker.filter.isEmpty ? "type to filter" : "filter: \(picker.filter)▏", w),
            String(repeating: "─", count: w),
        ]
        let listHeight = max(1, height - lines.count - 3)
        if picker.cursor < top { top = picker.cursor }
        if picker.cursor >= top + listHeight { top = picker.cursor - listHeight + 1 }
        for index in shown.indices.dropFirst(top).prefix(listHeight) {
            let candidate = shown[index]
            let mark = picker.selected.contains(candidate.path) ? "[x]" : "[ ]"
            let size = rightAligned(Size.format(sizes[candidate.path] ?? 0), 8)
            let line = fit("  \(mark) \(fit(candidate.name, 32))  \(size)  \(candidate.source.rawValue)", w)
            lines.append(index == picker.cursor ? reverseVideo + line + resetStyle : line)
        }
        if shown.isEmpty { lines.append(fit("  (nothing matches \"\(picker.filter)\")", w)) }
        while lines.count < height - 3 { lines.append("") }
        lines.append(String(repeating: "─", count: w))
        lines.append(fit("\(shown.count) of \(candidates.count) · \(picker.selected.count) selected", w))
        lines.append(fit("type to filter · ↑↓ move · space select · enter continue · esc cancel", w))
        Terminal.draw(lines)

        switch Terminal.waitForKey() {
        case .up: picker.move(by: -1)
        case .down: picker.move(by: 1)
        case .pageUp: picker.move(by: -listHeight)
        case .pageDown: picker.move(by: listHeight)
        case .char(" "): picker.toggle()
        case .backspace: picker.backspace()
        case .enter: return picker.chosen
        case .escape, .interrupt: return nil
        case .char(let c) where !c.isWhitespace && !(c.asciiValue.map { $0 < 32 } ?? false): picker.type(c)
        default: break
        }
    }
}

/// Holds sizes measured on several threads at once.
private final class SizeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [String: Int64] = [:]

    func set(_ path: String, _ size: Int64) {
        lock.lock()
        sizes[path] = size
        lock.unlock()
    }

    var all: [String: Int64] {
        lock.lock()
        defer { lock.unlock() }
        return sizes
    }
}

private func measure(_ paths: [String]) -> [String: Int64] {
    let box = SizeBox()
    DispatchQueue.concurrentPerform(iterations: paths.count) { index in
        box.set(paths[index], Size.allocated(paths[index]))
    }
    return box.all
}
