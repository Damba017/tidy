import Foundation
import TidyCore

/// `taydic junk [category]`: find junk, review it grouped per category, then the safety core.
/// Orphans are asked about separately (all / one by one / none).
func runJunk(category: JunkCategory?, options: JunkOptions, dryRun: Bool) -> Int32 {
    let interactive = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    let categories = category.map { Set([$0]) } ?? Set(JunkCategory.allCases)
    let walks = categories.contains(.large) || categories.contains(.dev)
    print("Looking for junk" + (walks ? " (this reads your home folder, except ~/Library)…" : "…"))
    let found = Junk.find(categories, options: options)

    print("Measuring \(found.items.count) items…")
    var order: [String] = []
    var itemsByGroup: [String: [ReviewList.Item]] = [:]
    var privacyProtected: [String] = []
    var notes: [String: String] = [:]
    for junk in found.items {
        guard let planned = RemovalPlan(paths: [junk.path]).items.first else { continue }
        switch planned.status {
        case .trash, .sudo:
            if itemsByGroup[junk.group] == nil { order.append(junk.group) }
            itemsByGroup[junk.group, default: []].append(ReviewList.Item(
                path: planned.path, size: planned.size, label: junk.label, needsSudo: planned.status == .sudo,
                checked: junk.checked))
            if let note = junk.note { notes[planned.path] = note }
        case .blocked(RemovalPlan.privacyReason):
            privacyProtected.append(planned.path)
        case .blocked, .missing:
            break
        }
    }
    // Caches & logs, Dev junk, the Large & old groups, Orphans, Orphans · cache folder.
    func rank(_ group: String) -> Int {
        group == Junk.groupCaches ? 0 : group == Junk.groupDev ? 1 : group == Junk.groupOrphans ? 3
            : group == Junk.groupOrphanCaches ? 4 : 2
    }
    let groups = order.sorted { (rank($0), $0) < (rank($1), $1) }.map { title in
        ReviewList.Group(title: title, detail: detail(for: title, options: options), items: itemsByGroup[title] ?? [])
    }
    let list = ReviewList(groups: groups)
    guard !list.groups.isEmpty else {
        print("No junk found.")
        return 0
    }

    let note = found.largeLeftOut > 0
        ? "…and \(found.largeLeftOut) more large files not shown, biggest first. Use --min-size to narrow it down."
        : nil
    let selected: [String]
    if interactive {
        Terminal.start()
        let result = review(list, title: "junk", dryRun: dryRun, note: note)
        Terminal.stop()
        guard let result else {
            print("Cancelled; nothing was changed.")
            return 0
        }
        selected = result
    } else {
        printPlain(list)
        if let note { print(note) }
        selected = list.selectedPaths
    }
    showPrivacyNotes(protected: privacyProtected)
    guard !selected.isEmpty else {
        print("Nothing selected; nothing was changed.")
        return 0
    }

    show("")
    let plan = RemovalPlan(paths: selected, doubtful: .orphans(notes.filter { selected.contains($0.key) }))
    let result = Remover.run(plan, dryRun: dryRun, say: show, ask: ask, choose: choose)
    return result.failed > 0 ? 1 : 0
}

private func detail(for group: String, options: JunkOptions) -> String {
    switch group {
    case Junk.groupCaches: "apps rebuild these when needed"
    case Junk.groupDev: "rebuilt or re-downloaded when needed"
    case Junk.groupOrphans: "no installed app claims these; check each one"
    case Junk.groupOrphanCaches: "caches no installed app claims, untouched for \(options.orphanCacheDays)+ days; check each one"
    default: "your own files, biggest first"
    }
}
