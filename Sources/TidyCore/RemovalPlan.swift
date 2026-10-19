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
        /// Only a guess (a fuzzy match, an orphan): shown and asked about separately.
        public internal(set) var isDoubtful = false
        /// Shown next to a doubtful item, e.g. "high confidence".
        public internal(set) var note: String?
    }

    /// The items that are only a guess, and how to talk about them.
    public struct Doubtful: Sendable {
        public let paths: [String]
        let one: String
        let many: String
        let why: String
        let notes: [String: String]

        /// Uninstall leftovers that only matched because their name looks like the app's.
        public static func fuzzy(_ paths: [String]) -> Doubtful {
            Doubtful(paths: paths, one: "fuzzy match", many: "fuzzy matches", why: "only the name looks alike", notes: [:])
        }

        /// Library items no installed app claims; `notes` holds each one's confidence.
        public static func orphans(_ notes: [String: String]) -> Doubtful {
            Doubtful(paths: Array(notes.keys), one: "orphan", many: "orphans", why: "no installed app claims them",
                     notes: notes)
        }
    }

    public let items: [Item]
    let home: String
    let doubt: Doubtful?

    /// `doubtful`: the paths among `paths` that are only a guess. They get their own block in the plan
    /// and their own question, so they never go along on the same "y" as the sure ones.
    public init(paths: [String], doubtful: Doubtful? = nil) {
        self.init(paths: paths, doubtful: doubtful, home: Paths.home)
    }

    init(paths: [String], doubtful: Doubtful? = nil, home: String) {
        let notes = Dictionary((doubtful?.notes ?? [:]).map { (Paths.normalize($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
        let guesses = Set((doubtful?.paths ?? []).map(Paths.normalize))
        var seen = Set<String>()
        var items: [Item] = []
        for raw in paths {
            let path = Paths.normalize(raw)
            guard seen.insert(path).inserted else { continue }
            var item = Self.classify(path, home: home)
            item.isDoubtful = guesses.contains(path)
            item.note = notes[path]
            items.append(item)
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
        self.init(items: items, home: home, doubt: doubtful)
    }

    init(items: [Item], home: String, doubt: Doubtful? = nil) {
        self.items = items
        self.home = home
        self.doubt = doubt
    }

    public func items(_ status: Status) -> [Item] {
        items.filter { $0.status == status }
    }

    /// First question: sure items that can go to the Trash without root.
    var sure: [Item] { Self.byFolder(items.filter { $0.status == .trash && !$0.isDoubtful }) }
    /// Second question: the doubtful items, with or without root.
    var doubtful: [Item] { Self.byFolder(items.filter { $0.isDoubtful && ($0.status == .trash || $0.status == .sudo) }) }
    /// Third question: sure items that need root.
    var root: [Item] { Self.byFolder(items.filter { $0.status == .sudo && !$0.isDoubtful }) }

    /// `items` with the ones in the same folder together, the order the plan shows them in (and moves them in).
    static func byFolder(_ items: [Item]) -> [Item] {
        var folders: [String] = []
        var inFolder: [String: [Item]] = [:]
        for item in items {
            let folder = Paths.parent(item.path)
            if inFolder[folder] == nil { folders.append(folder) }
            inFolder[folder, default: []].append(item)
        }
        return folders.flatMap { inFolder[$0] ?? [] }
    }

    /// "fuzzy match" / "2 fuzzy matches"
    func doubtfulCount(_ n: Int) -> String {
        let doubt = doubt ?? .fuzzy([])
        return n == 1 ? "1 \(doubt.one)" : "\(n) \(doubt.many)"
    }

    /// Every item with its full location (its folder, then its name), grouped by what will happen to it,
    /// in the order of the questions.
    public func render() -> [String] {
        var lines: [String] = []
        let blocked = Self.byFolder(items.filter { if case .blocked = $0.status { true } else { false } })
        let doubt = doubt ?? .fuzzy([])
        let groups = [
            ("Move to the Trash", sure),
            (doubt.many.prefix(1).uppercased() + doubt.many.dropFirst() + ", asked separately (\(doubt.why))", doubtful),
            ("Needs administrator rights (sudo)", root),
        ]
        for (title, group) in groups where !group.isEmpty {
            lines.append("\(title): \(Self.describe(group))")
            lines += Self.listed(group) { item, name in
                var note = Launchctl.domain(of: item.path) == nil ? "" : "  (stops its launchd job first)"
                if item.isDoubtful && item.status == .sudo { note += "  (needs sudo)" }
                if let extra = item.note { note += "  (\(extra))" }
                return "    " + Self.pad(Size.format(item.size)) + "  " + name + note
            }
            lines.append("")
        }
        if !blocked.isEmpty {
            lines.append("Protected, will not be touched: \(Self.count(blocked.count))")
            lines += Self.listed(blocked) { item, name in
                guard case .blocked(let reason) = item.status else { return "" }
                return "    " + Self.pad("") + "  " + name + "  (\(reason))"
            }
            lines.append("")
        }
        let missing = Self.byFolder(items(.missing))
        if !missing.isEmpty {
            lines.append("Not found, skipped: \(Self.count(missing.count))")
            lines += Self.listed(missing) { _, name in "    " + Self.pad("") + "  " + name }
            lines.append("")
        }
        return lines
    }

    /// `items` per folder (see `Output.grouped`), one `line(item, name)` each.
    static func listed(_ items: [Item], _ line: (Item, String) -> String) -> [String] {
        let byPath = Dictionary(items.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return Output.grouped(items.map(\.path)) { path, name in byPath[path].map { line($0, name) } ?? "" }
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

    /// Who may move `path` out of its folder.
    static func permission(_ path: String, _ st: stat) -> Permission {
        if st.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) != 0 { return .nobody("locked") }
        let parent = Paths.parent(path)
        // Moving a folder rewrites its ".." entry, so the folder itself must be writable too.
        let targets = (st.st_mode & S_IFMT) == S_IFDIR ? [parent, path] : [parent]
        for target in targets where access(target, W_OK) != 0 {
            return permission(forAccessError: errno)
        }
        // In a sticky folder (like /tmp) only the owner of the item or of the folder may move it.
        var parentStat = stat()
        if lstat(parent, &parentStat) == 0, parentStat.st_mode & S_ISVTX != 0,
           st.st_uid != getuid(), parentStat.st_uid != getuid() {
            return .root
        }
        return .user
    }

    /// What a failed `access(W_OK)` means. EACCES: the file permissions say no, which root gets past.
    /// EPERM: macOS itself says no (privacy protection or a lock), and EROFS: a read-only volume
    /// (a mounted .dmg); sudo from a terminal gets past neither.
    static func permission(forAccessError error: Int32) -> Permission {
        switch error {
        case EPERM: .nobody(privacyReason)
        case EROFS: .nobody("read-only volume")
        default: .root
        }
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
