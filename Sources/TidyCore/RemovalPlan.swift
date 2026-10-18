import Foundation

/// What would happen to a list of paths: Trash, Trash with sudo, protected, or not found.
/// Building a plan never changes anything on disk.
public struct RemovalPlan: Sendable {
    public enum Status: Equatable, Sendable {
        case trash
        case sudo
        case blocked(String)
        case missing
    }

    public struct Item: Sendable {
        public let path: String
        public let size: Int64
        public let status: Status
    }

    public let items: [Item]
    let home: String

    public init(paths: [String]) {
        self.init(paths: paths, home: Paths.home)
    }

    init(paths: [String], home: String) {
        var seen = Set<String>()
        var items: [Item] = []
        for raw in paths {
            let path = Paths.normalize(raw)
            guard seen.insert(path).inserted else { continue }
            items.append(Self.classify(path, home: home))
        }
        // Anything inside a folder that's being removed goes along with that folder.
        let removing = Set(items.filter { $0.status == .trash || $0.status == .sudo }.map(\.path))
        items.removeAll { item in
            var ancestor = Paths.parent(item.path)
            while ancestor != "/" {
                if removing.contains(ancestor) { return true }
                ancestor = Paths.parent(ancestor)
            }
            return false
        }
        self.init(items: items, home: home)
    }

    init(items: [Item], home: String) {
        self.items = items
        self.home = home
    }

    public func items(_ status: Status) -> [Item] {
        items.filter { $0.status == status }
    }

    /// Every item with its full location, grouped by what will happen to it.
    public func render() -> [String] {
        var lines: [String] = []
        let blocked = items.filter { if case .blocked = $0.status { true } else { false } }
        for (title, group) in [("Move to the Trash", items(.trash)), ("Needs administrator rights (sudo)", items(.sudo))]
        where !group.isEmpty {
            lines.append("\(title): \(Self.describe(group))")
            lines += group.map { "  " + Self.pad(Size.format($0.size)) + "  " + Paths.display($0.path) }
            lines.append("")
        }
        if !blocked.isEmpty {
            lines.append("Protected, will not be touched: \(Self.count(blocked.count))")
            for item in blocked {
                if case .blocked(let reason) = item.status {
                    lines.append("  " + Self.pad("") + "  " + Paths.display(item.path) + "  (\(reason))")
                }
            }
            lines.append("")
        }
        let missing = items(.missing)
        if !missing.isEmpty {
            lines.append("Not found, skipped: \(Self.count(missing.count))")
            lines += missing.map { "  " + Self.pad("") + "  " + Paths.display($0.path) }
            lines.append("")
        }
        return lines
    }

    static func classify(_ path: String, home: String) -> Item {
        if let reason = Denylist.reason(for: path, home: home) {
            return Item(path: path, size: 0, status: .blocked(reason))
        }
        var st = stat()
        guard lstat(path, &st) == 0 else {
            let error = errno
            if error == ENOENT || error == ENOTDIR { return Item(path: path, size: 0, status: .missing) }
            return Item(path: path, size: 0, status: .blocked(String(cString: strerror(error))))
        }
        return Item(path: path, size: Size.allocated(path), status: needsRoot(path, st) ? .sudo : .trash)
    }

    /// Whether moving `path` out of its folder needs root.
    static func needsRoot(_ path: String, _ st: stat) -> Bool {
        let parent = Paths.parent(path)
        if access(parent, W_OK) != 0 { return true }
        // Moving a folder rewrites its ".." entry, so the folder itself must be writable too.
        if (st.st_mode & S_IFMT) == S_IFDIR && access(path, W_OK) != 0 { return true }
        // In a sticky folder (like /tmp) only the owner of the item or of the folder may move it.
        var parentStat = stat()
        if lstat(parent, &parentStat) == 0, parentStat.st_mode & S_ISVTX != 0,
           st.st_uid != getuid(), parentStat.st_uid != getuid() {
            return true
        }
        return false
    }

    /// "3 items, 1.2 MB"
    static func describe(_ items: [Item]) -> String {
        "\(count(items.count)), \(Size.format(items.reduce(0) { $0 + $1.size }))"
    }

    static func count(_ n: Int) -> String {
        n == 1 ? "1 item" : "\(n) items"
    }

    private static func pad(_ text: String) -> String {
        String(repeating: " ", count: max(0, 8 - text.count)) + text
    }
}
