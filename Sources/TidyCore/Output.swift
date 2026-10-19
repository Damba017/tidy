import Foundation

/// How taydic prints lists of paths, and its few colours.
public enum Output {
    /// `paths` per folder: each folder once ("  ~/Library/Caches/"), then `line(path, name)` for each
    /// path in it. Folders in the order they first come up, paths in their own order.
    public static func grouped(_ paths: [String], _ line: (_ path: String, _ name: String) -> String) -> [String] {
        var folders: [String] = []
        var inFolder: [String: [String]] = [:]
        for path in paths {
            let folder = Paths.parent(path)
            if inFolder[folder] == nil { folders.append(folder) }
            inFolder[folder, default: []].append(path)
        }
        return folders.flatMap { folder in
            [folderLine(folder)] + (inFolder[folder] ?? []).map { line($0, ($0 as NSString).lastPathComponent) }
        }
    }

    /// "  ~/Library/Caches/"
    public static func folderLine(_ folder: String) -> String {
        let shown = Paths.display(folder)
        return "  " + shown + (shown.hasSuffix("/") ? "" : "/")
    }

    /// `line` with taydic's colours: "moved" and "quit" green, "FAILED" red, folder lines dim and
    /// headers ("Move to the Trash: 4 items, 45 KB", "Found 1:") bold. Everything else as is.
    public static func colored(_ line: String) -> String {
        for (word, color) in [("    moved ", green), ("  quit ", green), ("    FAILED ", red)] where line.hasPrefix(word) {
            let indent = String(word.prefix { $0 == " " })
            let name = String(word.dropFirst(indent.count).dropLast())
            return indent + color + name + reset + String(line.dropFirst(indent.count + name.count))
        }
        if line.hasPrefix("  ") && !line.hasPrefix("   ") && line.hasSuffix("/") { return dim + line + reset }
        if isHeader(line) { return bold + line + reset }
        return line
    }

    /// A header starts at the left and ends in a colon, or has a count right after its colon.
    static func isHeader(_ line: String) -> Bool {
        guard let first = line.first, first != " " else { return false }
        if line.hasSuffix(":") { return true }
        guard let colon = line.firstIndex(of: ":") else { return false }
        let after = line[line.index(after: colon)...]
        return after.hasPrefix(" ") && after.dropFirst().first?.isNumber == true
    }

    static let green = "\u{1B}[32m"
    static let red = "\u{1B}[31m"
    static let bold = "\u{1B}[1m"
    static let dim = "\u{1B}[2m"
    static let reset = "\u{1B}[0m"
}
