import Foundation
import TidyCore

/// `tidy uninstall [name...]`: find the apps, quit them, review app + leftovers, then the safety core.
func runUninstall(names: [String], dryRun: Bool) -> Int32 {
    let interactive = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    let apps = AppFinder.installedApps()
    var targets: [App] = []
    func add(_ app: App) {
        if !targets.contains(app) { targets.append(app) }
    }

    if names.isEmpty {
        guard interactive else {
            FileHandle.standardError.write(Data("tidy: give one or more app names when not running in a terminal.\n".utf8))
            return 2
        }
        print("Measuring \(apps.count) apps…")
        let sizes = measure(apps.map(\.path))
        Terminal.start()
        let picked = pickApps(apps, sizes: sizes, dryRun: dryRun)
        Terminal.stop()
        guard let picked, !picked.isEmpty else {
            print("Nothing selected; nothing was changed.")
            return 0
        }
        picked.forEach(add)
    } else {
        for name in names {
            // A path to a .app (e.g. one outside /Applications) is taken as is.
            if name.contains("/") || name.lowercased().hasSuffix(".app"), let app = AppFinder.load(Paths.normalize(name)) {
                add(app)
                continue
            }
            let found = AppFinder.matches(name, in: apps)
            switch found.count {
            case 0: print("No app matches \"\(name)\"; skipped.")
            case 1: add(found[0])
            default:
                if let app = pickOne(name, from: found, interactive: interactive) { add(app) } else { print("Skipped \"\(name)\".") }
            }
        }
    }
    guard !targets.isEmpty else {
        print("Nothing to uninstall.")
        return 0
    }

    print("")
    print("Found \(targets.count == 1 ? "1 app" : "\(targets.count) apps"):")
    for app in targets {
        print("  \(app.name)  ·  \(app.source.rawValue)  ·  \(app.path)")
    }

    let running = targets.filter(RunningApps.isRunning)
    if !running.isEmpty {
        let list = running.map(\.name).joined(separator: ", ")
        let one = running.count == 1
        if dryRun {
            print("--dry-run: would ask to quit \(list) first.")
        } else if ask("\(list) \(one ? "is" : "are") running. Quit \(one ? "it" : "them") now?") {
            for app in running where !RunningApps.quit(app) {
                print("\(app.name) didn't quit, so it's skipped. Quit it yourself and run tidy again.")
                targets.removeAll { $0 == app }
            }
        } else {
            print("Skipped \(list): \(one ? "it's" : "they're") still running.")
            targets.removeAll { running.contains($0) }
        }
        guard !targets.isEmpty else { return 0 }
    }

    print("Looking for leftovers…")
    let found = targets.map(group(for:))
    let list = ReviewList(groups: found.map(\.group))
    let privacyProtected = found.flatMap(\.privacyProtected)
    let selected: [String]
    if interactive {
        Terminal.start()
        let result = review(list, title: "uninstall", dryRun: dryRun)
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
    if !privacyProtected.isEmpty {
        print("")
        print("Not in the list: macOS won't let tidy touch these without Full Disk Access:")
        privacyProtected.forEach { print("  " + Paths.display($0)) }
        print("To include them: System Settings → Privacy & Security → Full Disk Access → add your terminal app,")
        print("then run tidy again.")
    }
    guard !selected.isEmpty else {
        print("Nothing selected; nothing was changed.")
        return 0
    }

    print("")
    let result = Remover.run(RemovalPlan(paths: selected), dryRun: dryRun, say: { print($0) }, ask: ask)
    return result.failed > 0 ? 1 : 0
}

/// The app bundle plus everything it left behind, as one group of the review list.
/// Protected or missing paths never make it into the list; the ones macOS privacy protection
/// keeps tidy out of are returned separately so the user hears about them.
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

/// Several apps match `name`: let the user pick one by number.
private func pickOne(_ name: String, from apps: [App], interactive: Bool) -> App? {
    print("\"\(name)\" matches \(apps.count) apps:")
    for (index, app) in apps.enumerated() {
        print("  \(index + 1)  \(fit(app.name, 24))  \(fit(app.source.rawValue, 9))  \(app.path)")
    }
    guard interactive else { return nil }
    print("Which one? (number, Enter to skip) ", terminator: "")
    fflush(stdout)
    guard let line = readLine(), let number = Int(line.trimmingCharacters(in: .whitespaces)),
          apps.indices.contains(number - 1) else { return nil }
    return apps[number - 1]
}

/// The multi-select app list: type to filter, space to select, Enter to continue.
private func pickApps(_ apps: [App], sizes: [String: Int64], dryRun: Bool) -> [App]? {
    var picker = AppPicker(apps: apps)
    var top = 0
    while true {
        let (height, width) = Terminal.size()
        let w = max(20, width - 1)
        let shown = picker.visible
        var lines = [
            fit("tidy uninstall  pick apps" + (dryRun ? "   [dry-run]" : ""), w),
            fit(picker.filter.isEmpty ? "type to filter" : "filter: \(picker.filter)▏", w),
            String(repeating: "─", count: w),
        ]
        let listHeight = max(1, height - lines.count - 3)
        if picker.cursor < top { top = picker.cursor }
        if picker.cursor >= top + listHeight { top = picker.cursor - listHeight + 1 }
        for index in shown.indices.dropFirst(top).prefix(listHeight) {
            let app = shown[index]
            let mark = picker.selected.contains(app.path) ? "[x]" : "[ ]"
            let line = fit("  \(mark) \(fit(app.name, 32))  \(rightAligned(Size.format(sizes[app.path] ?? 0), 8))  \(app.source.rawValue)", w)
            lines.append(index == picker.cursor ? reverseVideo + line + resetStyle : line)
        }
        if shown.isEmpty { lines.append(fit("  (no app matches \"\(picker.filter)\")", w)) }
        while lines.count < height - 3 { lines.append("") }
        lines.append(String(repeating: "─", count: w))
        lines.append(fit("\(shown.count) of \(apps.count) · \(picker.selected.count) selected", w))
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
