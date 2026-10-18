import Foundation

/// The grouped, checkable list shown before anything is removed (shared by uninstall and junk).
/// Pure state: the terminal UI draws it and feeds it keys.
public struct ReviewList: Sendable {
    public struct Item: Sendable {
        public let path: String
        public let size: Int64
        /// Why it's in the list, e.g. "bundle ID", "fuzzy", "app".
        public let label: String
        public let needsSudo: Bool
        public var checked: Bool

        public init(path: String, size: Int64, label: String, needsSudo: Bool, checked: Bool) {
            self.path = path
            self.size = size
            self.label = label
            self.needsSudo = needsSudo
            self.checked = checked
        }
    }

    public struct Group: Sendable {
        public let title: String
        public let detail: String
        public var items: [Item]
        public var expanded: Bool

        public init(title: String, detail: String, items: [Item]) {
            self.title = title
            self.detail = detail
            self.items = items
            expanded = items.count <= 5  // small groups start open
        }

        public enum State { case all, some, none }

        public var state: State {
            let checked = items.filter(\.checked).count
            return checked == items.count ? .all : checked == 0 ? .none : .some
        }

        public var checkedSize: Int64 { items.filter(\.checked).reduce(0) { $0 + $1.size } }
        public var needsSudo: Bool { items.contains(where: \.needsSudo) }
    }

    public enum Row: Equatable, Sendable {
        case group(Int)
        case item(Int, Int)
    }

    public private(set) var groups: [Group]
    public private(set) var cursor = 0

    public init(groups: [Group]) {
        self.groups = groups.filter { !$0.items.isEmpty }
    }

    /// What's on screen: each group header, followed by its items when it's expanded.
    public var rows: [Row] {
        groups.indices.flatMap { g in
            [Row.group(g)] + (groups[g].expanded ? groups[g].items.indices.map { Row.item(g, $0) } : [])
        }
    }

    public var current: Row? { rows.indices.contains(cursor) ? rows[cursor] : nil }

    public var selectedPaths: [String] {
        groups.flatMap { $0.items.filter(\.checked).map(\.path) }
    }

    public var selectedSize: Int64 { groups.reduce(0) { $0 + $1.checkedSize } }

    public mutating func move(by offset: Int) {
        cursor = max(0, min(rows.count - 1, cursor + offset))
    }

    /// Space: one item, or the whole group when on its header.
    public mutating func toggle() {
        switch current {
        case .group(let g): toggleGroup(g)
        case .item(let g, let i): groups[g].items[i].checked.toggle()
        case nil: break
        }
    }

    /// `a`: all items of the group the cursor is in, from the header or from any item.
    public mutating func toggleAllInGroup() {
        switch current {
        case .group(let g), .item(let g, _): toggleGroup(g)
        case nil: break
        }
    }

    /// →
    public mutating func expand() {
        switch current {
        case .group(let g), .item(let g, _): groups[g].expanded = true
        case nil: break
        }
    }

    /// ←: collapses the group, or from an item jumps to its header first.
    public mutating func collapse() {
        switch current {
        case .group(let g):
            groups[g].expanded = false
        case .item(let g, _):
            if let header = rows.firstIndex(of: .group(g)) { cursor = header }
        case nil: break
        }
    }

    /// All checked → none, otherwise → all.
    private mutating func toggleGroup(_ g: Int) {
        let check = groups[g].state != .all
        for i in groups[g].items.indices { groups[g].items[i].checked = check }
    }
}

/// The list for `tidy uninstall` without names (apps and brew packages): type to filter, space to select.
public struct AppPicker: Sendable {
    public let candidates: [Candidate]
    public private(set) var filter = ""
    public private(set) var selected = Set<String>()  // candidate paths; kept while the filter changes
    public private(set) var cursor = 0

    public init(candidates: [Candidate]) {
        self.candidates = candidates
    }

    public var visible: [Candidate] {
        guard !filter.isEmpty else { return candidates }
        return candidates.filter { candidate in candidate.names.contains { $0.localizedCaseInsensitiveContains(filter) } }
    }

    public mutating func type(_ character: Character) {
        filter.append(character)
        cursor = 0
    }

    public mutating func backspace() {
        if !filter.isEmpty { filter.removeLast() }
        cursor = 0
    }

    public mutating func move(by offset: Int) {
        cursor = max(0, min(visible.count - 1, cursor + offset))
    }

    public mutating func toggle() {
        let shown = visible
        guard shown.indices.contains(cursor) else { return }
        let path = shown[cursor].path
        if selected.remove(path) == nil { selected.insert(path) }
    }

    /// What Enter means: the selected ones, or the highlighted one when nothing is selected.
    public var chosen: [Candidate] {
        if !selected.isEmpty { return candidates.filter { selected.contains($0.path) } }
        let shown = visible
        return shown.indices.contains(cursor) ? [shown[cursor]] : []
    }
}
