import Foundation
import TidyCore

/// Shows a ReviewList and lets the user tick items. The checked paths on Enter, nil on cancel.
/// `note` is an extra line above the footer, e.g. what comes after this list.
/// Shared by `uninstall` and `junk`; call between Terminal.start() and Terminal.stop().
func review(_ list: ReviewList, title: String, dryRun: Bool, note: String? = nil) -> [String]? {
    var list = list
    var top = 0
    while true {
        let (height, width) = Terminal.size()
        let w = max(20, width - 1)
        let footer = note == nil ? 3 : 4
        var lines = [
            fit("tidy \(title)  review what goes" + (dryRun ? "   [dry-run]" : ""), w),
            fit("\(list.selectedPaths.count) selected · \(Size.format(list.selectedSize))", w),
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
        lines.append(fit("↑↓ move · space toggle · → expand · ← collapse · a all in group · enter continue · q cancel", w))
        Terminal.draw(lines)

        let page = max(1, listHeight - 1)
        switch Terminal.waitForKey() {
        case .up: list.move(by: -1)
        case .down: list.move(by: 1)
        case .pageUp: list.move(by: -page)
        case .pageDown: list.move(by: page)
        case .home: list.move(by: -rows.count)
        case .end: list.move(by: rows.count)
        case .char(" "): list.toggle()
        case .right: list.expand()
        case .left: list.collapse()
        case .char("a"): list.toggleAllInGroup()
        case .enter: return list.selectedPaths
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
        return (group.expanded ? "▾ " : "▸ ") + checkbox(group.state) + " " + group.title + "   " + group.detail
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
