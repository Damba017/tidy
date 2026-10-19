import Foundation
import TidyCore

/// `taydic disk [path]`: pick a volume (or take `path`), scan it, browse it.
func runDisk(path: String?, dryRun: Bool) -> Int32 {
    guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
        FileHandle.standardError.write(Data("taydic: 'disk' is an interactive browser and needs a terminal; it doesn't work when piped.\n".utf8))
        return 2
    }
    var root = ""
    var systemSize: Int64?
    if let path {
        guard let resolved = resolvedFolder(path) else {
            FileHandle.standardError.write(Data("taydic: not a folder: \(path)\n".utf8))
            return 1
        }
        root = resolved == "/" ? "/System/Volumes/Data" : resolved
        systemSize = resolved == "/" ? Volumes.spaceUsed("/") : nil
    }

    Terminal.start()
    defer { Terminal.stop() }
    if path == nil {
        guard let volume = pickVolume(Volumes.mounted()) else { return 0 }
        root = volume.scanRoot
        systemSize = volume.isBoot ? Volumes.spaceUsed("/") : nil
    }
    guard let (tree, needsFullDiskAccess) = scanWithProgress(root) else { return 0 }
    // For a whole volume, also show what it uses beyond the scan, so the total matches "used".
    var extras: [DiskBrowser.Row] = []
    if let systemSize { extras.append(.system(systemSize)) }
    if let volume = Volumes.mounted().first(where: { $0.scanRoot == root }) {
        let unaccounted = volume.unaccounted(scanned: tree.size + (systemSize ?? 0))
        if unaccounted > 0 { extras.append(.unscanned(unaccounted)) }
    }
    DiskBrowser(root: tree, extras: extras, dryRun: dryRun, needsFullDiskAccess: needsFullDiskAccess).run()
    return 0
}

/// What a symlink points to, as written in the link.
private func linkTarget(_ path: String) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let count = readlink(path, &buffer, buffer.count)
    guard count >= 0 else { return nil }
    return String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// Fully resolved path of an existing folder, or nil.
private func resolvedFolder(_ path: String) -> String? {
    guard let resolved = realpath((path as NSString).expandingTildeInPath, nil) else { return nil }
    defer { free(resolved) }
    var st = stat()
    guard stat(resolved, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return nil }
    return String(cString: resolved)
}

private func pickVolume(_ volumes: [Volume]) -> Volume? {
    guard !volumes.isEmpty else { return nil }
    var cursor = 0
    while true {
        let (height, width) = Terminal.size()
        let w = max(20, width - 1)
        var lines = [fit("taydic disk  pick a volume", w), ""]
        let nameWidth = min(24, volumes.map(\.name.count).max() ?? 10)
        for (i, volume) in volumes.enumerated() {
            let fraction = volume.total > 0 ? Double(volume.used) / Double(volume.total) : 0
            let text = "  " + fit(volume.name, nameWidth) + "  " + fit(volume.mountPoint, 16)
                + "  " + rightAligned(Size.format(volume.used), 8) + " used  "
                + rightAligned(Size.format(volume.available), 8) + " free  " + bar(fraction, 20)
            let line = fit(text, w)
            lines.append(i == cursor ? reverseVideo + line + resetStyle : line)
        }
        while lines.count < height - 1 { lines.append("") }
        lines.append(fit("↑↓ move · enter scan · q quit", w))
        Terminal.draw(lines)

        switch Terminal.waitForKey() {
        case .up: cursor = max(0, cursor - 1)
        case .down: cursor = min(volumes.count - 1, cursor + 1)
        case .enter, .right: return volumes[cursor]
        case .char("q"), .escape, .interrupt: return nil
        default: break
        }
    }
}

/// Holds the result of the background scan.
private final class ScanJob: @unchecked Sendable {
    var tree: DirNode?
}

/// Scans `path` on a background thread while showing progress. Nil when cancelled.
private func scanWithProgress(_ path: String) -> (DirNode, Bool)? {
    let scanner = Scanner()
    let job = ScanJob()
    let finished = DispatchSemaphore(value: 0)
    Thread {
        job.tree = scanner.scan(path)
        finished.signal()
    }.start()

    let started = Date()
    while finished.wait(timeout: .now()) == .timedOut {
        let progress = scanner.progress()
        let (height, width) = Terminal.size()
        let w = max(20, width - 1)
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        var lines = [
            fit("taydic disk  scanning " + Paths.display(Paths.normalize(path)), w),
            "",
            fit("  \(grouped(progress.files)) files · \(grouped(progress.folders)) folders · \(seconds) s", w),
            fitKeepingEnd("  " + Paths.display(Paths.normalize(progress.current)), w),
        ]
        while lines.count < height - 1 { lines.append("") }
        lines.append(fit("q cancel", w))
        Terminal.draw(lines)
        if let key = Terminal.readKey(), key == .char("q") || key == .escape || key == .interrupt {
            scanner.cancel()
            finished.wait()
            return nil
        }
    }
    return (job.tree!, scanner.needsFullDiskAccess)
}

/// The ncdu-style browser: one folder at a time, biggest first.
private final class DiskBrowser {
    enum Row {
        case folder(DirNode)
        case file(FileEntry)
        case system(Int64)  // the sealed macOS system volume, shown as one line
        case unscanned(Int64)  // what the volume uses beyond the scan

        var name: String {
            switch self {
            case .folder(let node): node.name
            case .file(let file): file.name
            case .system: "macOS system volume"
            case .unscanned: "not scanned"
            }
        }

        var size: Int64 {
            switch self {
            case .folder(let node): node.size
            case .file(let file): file.size
            case .system(let size), .unscanned(let size): size
            }
        }

        /// Summary lines at the top level: not on disk as such, so not openable or removable.
        var isSummary: Bool {
            switch self {
            case .system, .unscanned: true
            case .folder, .file: false
            }
        }
    }

    let root: DirNode
    /// Summary rows shown (and counted) at the top level only.
    let extras: [Row]
    let dryRun: Bool
    var needsFullDiskAccess: Bool
    var current: DirNode
    var rows: [Row] = []
    var cursor = 0
    var top = 0
    var message = ""
    /// `/` search in the current folder, by name; cleared when moving to another folder.
    var search = ""
    var searching = false

    init(root: DirNode, extras: [Row], dryRun: Bool, needsFullDiskAccess: Bool) {
        self.root = root
        self.extras = extras
        self.dryRun = dryRun
        self.needsFullDiskAccess = needsFullDiskAccess
        current = root
    }

    var total: Int64 {
        current.size + (current === root ? extras.reduce(0) { $0 + $1.size } : 0)
    }

    func run() {
        reload()
        while true {
            draw()
            guard let key = Terminal.waitForKey() else { continue }
            message = ""
            let page = max(1, Terminal.size().rows - 8)
            if searching {
                switch key {
                case .enter: searching = false
                case .up, .down:
                    searching = false
                    cursor = max(0, min(rows.count - 1, cursor + (key == .up ? -1 : 1)))
                case .escape:
                    searching = false
                    setSearch("")
                case .backspace:
                    if search.isEmpty { searching = false } else { setSearch(String(search.dropLast())) }
                case .interrupt: return
                case .char(let c) where !(c.asciiValue.map { $0 < 32 } ?? false): setSearch(search + String(c))
                default: break
                }
                continue
            }
            switch key {
            case .char("/"): searching = true
            case .escape where !search.isEmpty: setSearch("")  // first Esc clears the search
            case .up: cursor = max(0, cursor - 1)
            case .down: cursor = max(0, min(rows.count - 1, cursor + 1))
            case .pageUp: cursor = max(0, cursor - page)
            case .pageDown: cursor = max(0, min(rows.count - 1, cursor + page))
            case .home: cursor = 0
            case .end: cursor = max(0, rows.count - 1)
            case .enter, .right: open()
            case .left, .backspace: goUp()
            case .char("d"): trashSelected()
            case .char("o"): revealSelected()
            case .char("r"): rescan()
            case .char("?"): showHelp()
            case .char("q"), .escape, .interrupt: return
            default: break
            }
        }
    }

    private func reload(selecting name: String? = nil) {
        rows = current.dirs.map(Row.folder) + current.files.map(Row.file)
        if current === root { rows += extras }
        if !search.isEmpty { rows = rows.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        rows.sort { $0.size != $1.size ? $0.size > $1.size : $0.name < $1.name }
        if let name, let index = rows.firstIndex(where: { $0.name == name }) { cursor = index }
        cursor = max(0, min(cursor, rows.count - 1))
    }

    /// Changes the search and keeps the cursor on the same entry when it's still shown.
    private func setSearch(_ text: String) {
        let name = selected?.name
        search = text
        cursor = 0
        top = 0
        reload(selecting: name)
    }

    private var selected: Row? {
        rows.indices.contains(cursor) ? rows[cursor] : nil
    }

    private func path(of row: Row) -> String {
        current.path == "/" ? "/" + row.name : current.path + "/" + row.name
    }

    private func open() {
        switch selected {
        case .folder(let node):
            if let error = node.error {
                message = "Can't open \(node.name): \(error)"
                return
            }
            current = node
            cursor = 0
            top = 0
            search = ""
            reload()
        case .file(let file):
            message = file.isSymlink ? "That's a symlink; taydic doesn't follow links." : "That's a file, not a folder."
        case .system: message = "The macOS system volume is sealed; taydic doesn't look inside it."
        case .unscanned: message = "That's an estimate of space the scan couldn't see, not a folder. See ? for what's in it."
        case nil: break
        }
    }

    private func goUp() {
        guard let parent = current.parent else { return }
        let name = current.name
        current = parent
        top = 0
        search = ""
        reload(selecting: name)
    }

    /// Leaves the browser, lets the safety core show the plan and ask, then comes back.
    private func trashSelected() {
        guard let row = selected else { return }
        if row.isSummary {
            message = "\(row.name) is a summary line; there's nothing to remove."
            return
        }
        let path = path(of: row)
        Terminal.stop()
        print("")
        _ = Remover.run(RemovalPlan(paths: [path]), dryRun: dryRun, say: { print($0) }, ask: ask, choose: choose)
        print("")
        print("Press Enter to go back to taydic disk. ", terminator: "")
        fflush(stdout)
        _ = readLine()
        Terminal.start()

        var st = stat()
        if lstat(path, &st) != 0 && errno == ENOENT {
            current.removeEntry(named: row.name)
            reload()
            message = "Moved \(row.name) to the Trash."
        }
    }

    private func revealSelected() {
        guard let row = selected else { return }
        if row.isSummary {
            message = "\(row.name) is a summary line; there's nothing to show in Finder."
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-R", path(of: row)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            message = "Shown in Finder."
        } catch {
            message = "Couldn't open Finder: \(error.localizedDescription)"
        }
    }

    private func rescan() {
        let name = selected?.name
        guard let (fresh, needsAccess) = scanWithProgress(current.path) else {
            message = "Rescan cancelled."
            return
        }
        current.replaceContents(with: fresh)
        needsFullDiskAccess = needsFullDiskAccess || needsAccess
        reload(selecting: name)
        message = "Rescanned."
    }

    private func showHelp() {
        let (height, width) = Terminal.size()
        let w = max(20, width - 1)
        var lines = [
            "taydic disk keys",
            "",
            "  ↑ ↓  PgUp PgDn  Home End    move",
            "  enter or →                  open folder",
            "  ← or backspace              up one level",
            "  d                           move to the Trash (shows exactly what and asks y/N first)",
            "  o                           show in Finder",
            "  r                           rescan this folder",
            "  /                           search this folder by name (enter keeps it, esc clears it)",
            "  q or esc                    quit (with a search active, esc first clears the search)",
            "",
            "Sizes are space actually used on disk (allocated), hard links count once.",
            "APFS clones and snapshots share space, so totals can differ from what Finder shows.",
            "The boot disk is scanned through its data volume; the sealed macOS system volume is one line.",
            "\"not scanned\" is what the volume uses that the scan didn't see: other APFS volumes (VM, Preboot,",
            "Recovery), snapshots (e.g. Time Machine) and folders taydic wasn't allowed to read. It's an estimate.",
            "Symlinks show where they point (→); taydic counts the link itself, never what it points to.",
            "",
            "Press any key.",
        ].map { fit($0, w) }
        while lines.count < height { lines.append("") }
        Terminal.draw(lines)
        _ = Terminal.waitForKey()
    }

    private func draw() {
        let (height, width) = Terminal.size()
        let w = max(20, width - 1)
        var lines: [String] = []
        lines.append(fit("taydic disk  " + Paths.display(Paths.normalize(current.path)) + (dryRun ? "   [dry-run]" : ""), w))
        var summary = "\(Size.format(total)) · \(grouped(current.fileCount)) " + (current.fileCount == 1 ? "file" : "files")
        if let error = current.error { summary += " · \(error)" }
        if current === root { summary += " · sizes can differ from Finder, see ?" }
        if searching || !search.isEmpty {
            summary = "/\(search)" + (searching ? "▏" : "") + "   \(rows.count) matches   ·   " + summary
        }
        lines.append(fit(summary, w))
        if needsFullDiskAccess {
            lines.append(fit("Some folders need Full Disk Access: System Settings → Privacy & Security → Full Disk Access → add your terminal app.", w))
        }
        lines.append(String(repeating: "─", count: w))

        let listHeight = max(1, height - lines.count - 3)
        if cursor < top { top = cursor }
        if cursor >= top + listHeight { top = cursor - listHeight + 1 }
        if rows.isEmpty {
            let empty = !search.isEmpty ? "  (nothing here matches \"\(search)\")"
                : current.error == nil ? "  (empty folder)" : "  (can't read this folder)"
            lines.append(fit(empty, w))
        }
        for i in rows.indices.dropFirst(top).prefix(listHeight) {
            let line = fit(text(of: rows[i], width: w), w)
            lines.append(i == cursor ? reverseVideo + line + resetStyle : line)
        }
        while lines.count < height - 3 { lines.append("") }
        lines.append(String(repeating: "─", count: w))
        lines.append(fit(message, w))
        lines.append(fit(searching
            ? "type to search this folder · enter keep these results · esc clear search"
            : "↑↓ move · enter open · ← back · / search · d trash · o finder · r rescan · ? help · q quit", w))
        Terminal.draw(lines)
    }

    private func text(of row: Row, width: Int) -> String {
        let fraction = Double(row.size) / Double(max(1, total))
        var size = Size.format(row.size)
        var name = row.name
        var note = ""
        switch row {
        case .folder(let node):
            name += "/"
            if let error = node.error {
                size = "?"
                note = "  (\(error))"
            }
        case .file(let file):
            if file.isSymlink { name += " → " + (linkTarget(path(of: row)) ?? "?") }
        case .system: note = "  (sealed, read-only)"
        case .unscanned: note = "  (other volumes, snapshots, unreadable folders; estimate, see ?)"
        }
        var text = "  " + rightAligned(size, 8) + "  " + rightAligned(String(format: "%.1f%%", fraction * 100), 6)
        if width >= 70 { text += "  " + bar(fraction, 20) }
        return text + "  " + name + note
    }
}
