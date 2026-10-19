import Foundation
import TidyCore

/// Shows a ReviewList and lets the user tick items. The checked paths on Enter, nil on cancel.
/// `note` is an extra line above the footer, e.g. what comes after this list.
/// Shared by `uninstall` and `junk`; call between Terminal.start() and Terminal.stop().
func review(_ list: ReviewList, title: String, dryRun: Bool, note: String? = nil) -> [String]? {
    var list = list
    var top = 0
    var searching = false  // typing after `/`
    while true {
        let (height, width) = Terminal.size()
        let w = max(20, width - 1)
        let footer = note == nil ? 3 : 4
        var status = "\(list.selectedPaths.count) selected · \(Size.format(list.selectedSize))"
        if searching || !list.search.isEmpty {
            status = "/\(list.search)" + (searching ? "▏" : "") + "   \(list.matchCount) matches   ·   " + status
        }
        var lines = [
            fit("taydic \(title)  review what goes" + (dryRun ? "   [dry-run]" : ""), w),
            fit(status, w),
            String(repeating: "─", count: w),
        ]
        let rows = list.rows
        let listHeight = max(1, height - lines.count - footer)
        if list.cursor < top { top = list.cursor }
        if list.cursor >= top + listHeight { top = list.cursor - listHeight + 1 }
        for index in rows.indices.dropFirst(top).prefix(listHeight) {
            let line = fit(text(of: rows[index], in: list), w)
            lines.append(index == list.cursor ? reverseVideo + line + resetStyle : line)
        }
        while lines.count < height - footer { lines.append("") }
        lines.append(String(repeating: "─", count: w))
        if let note { lines.append(fit(note, w)) }
        lines.append(fit("Nothing is removed yet: after Enter you see the full list and get a (y/N).", w))
        lines.append(fit(searching
            ? "type to search path or label · enter keep these results · esc clear search"
            : "↑↓ move · tab/⇧tab group · / search · space toggle · → expand · ← collapse · a all in group · enter continue · q cancel",
            w))
        Terminal.draw(lines)

        let page = max(1, listHeight - 1)
        guard let key = Terminal.waitForKey() else { continue }
        if searching {
            switch key {
            case .enter, .up, .down, .tab, .backTab: searching = false
            case .escape:
                list.setSearch("")
                searching = false
            case .backspace:
                if list.search.isEmpty { searching = false } else { list.setSearch(String(list.search.dropLast())) }
            case .interrupt: return nil
            case .char(let c) where !(c.asciiValue.map { $0 < 32 } ?? false): list.setSearch(list.search + String(c))
            default: break
            }
            if key == .up || key == .down { list.move(by: key == .up ? -1 : 1) }
            if key == .tab || key == .backTab { list.jumpToGroup(forward: key == .tab) }
            continue
        }
        switch key {
        case .up: list.move(by: -1)
        case .down: list.move(by: 1)
        case .pageUp: list.move(by: -page)
        case .pageDown: list.move(by: page)
        case .home: list.move(by: -rows.count)
        case .end: list.move(by: rows.count)
        case .tab: list.jumpToGroup(forward: true)
        case .backTab: list.jumpToGroup(forward: false)
        case .char("/"): searching = true
        case .char(" "): list.toggle()
        case .right: list.expand()
        case .left: list.collapse()
        case .char("a"): list.toggleAllInGroup()
        case .enter: return list.selectedPaths
        case .escape where !list.search.isEmpty: list.setSearch("")  // first Esc clears the search
        case .char("q"), .escape, .interrupt: return nil
        default: break
        }
    }
}

private func checkbox(_ state: ReviewList.Group.State) -> String {
    switch state {
    case .all: "[x]"
    case .some: "[~]"
    case .none: "[ ]"
    }
}

private func text(of row: ReviewList.Row, in list: ReviewList) -> String {
    switch row {
    case .group(let g):
        let group = list.groups[g]
        let checked = group.items.filter(\.checked).count
        let open = group.expanded || !list.search.isEmpty  // a search opens every group with matches
        return (open ? "▾ " : "▸ ") + checkbox(group.state) + " " + group.title + "   " + group.detail
            + "   \(checked) of \(group.items.count) · \(Size.format(group.checkedSize))"
            + (group.needsSudo ? "   [needs sudo]" : "")
    case .item(let g, let i):
        let item = list.groups[g].items[i]
        return "      " + (item.checked ? "[x]" : "[ ]") + "  " + rightAligned(Size.format(item.size), 8)
            + "  " + Paths.display(item.path) + "  (\(item.label)" + (item.needsSudo ? ", sudo" : "") + ")"
    }
}

/// The same list as plain text, for when there's no terminal to draw in.
func printPlain(_ list: ReviewList) {
    for group in list.groups {
        print("\(checkbox(group.state)) \(group.title)   \(group.detail)" + (group.needsSudo ? "   [needs sudo]" : ""))
        for item in group.items {
            print("      " + (item.checked ? "[x]" : "[ ]") + "  " + rightAligned(Size.format(item.size), 8)
                + "  " + Paths.display(item.path) + "  (\(item.label))")
        }
    }
}
