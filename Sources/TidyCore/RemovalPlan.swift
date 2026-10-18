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
            lines += group.map { item in
                let note = Launchctl.domain(of: item.path) == nil ? "" : "  (stops its launchd job first)"
                return "  " + Self.pad(Size.format(item.size)) + "  " + Paths.display(item.path) + note
            }
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
        switch permission(path, st) {
        case .user: return Item(path: path, size: Size.allocated(path), status: .trash)
        case .root: return Item(path: path, size: Size.allocated(path), status: .sudo)
        case .nobody(let reason): return Item(path: path, size: 0, status: .blocked(reason))
        }
    }

    public static let privacyReason = "macOS privacy protection; needs Full Disk Access for your terminal"

    enum Permission: Equatable {
        case user
        case root
        case nobody(String)
    }

    /// Who may move `path` out of its folder. EACCES means the file permissions say no, which root
    /// gets past. EPERM means macOS itself says no (privacy protection or a lock), and sudo from a
    /// terminal doesn't get past that either.
    static func permission(_ path: String, _ st: stat) -> Permission {
        if st.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) != 0 { return .nobody("locked") }
        let parent = Paths.parent(path)
        // Moving a folder rewrites its ".." entry, so the folder itself must be writable too.
        let targets = (st.st_mode & S_IFMT) == S_IFDIR ? [parent, path] : [parent]
        for target in targets where access(target, W_OK) != 0 {
            return errno == EPERM ? .nobody(privacyReason) : .root
        }
        // In a sticky folder (like /tmp) only the owner of the item or of the folder may move it.
        var parentStat = stat()
        if lstat(parent, &parentStat) == 0, parentStat.st_mode & S_ISVTX != 0,
           st.st_uid != getuid(), parentStat.st_uid != getuid() {
            return .root
        }
        return .user
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
