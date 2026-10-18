import Foundation

public enum Size {
    /// Allocated size on disk (`st_blocks * 512`) of `path` and everything under it.
    /// Doesn't follow symlinks, stays on one filesystem, counts hard links once.
    /// Unreadable parts are skipped.
    public static func allocated(_ path: String) -> Int64 {
        guard let cPath = strdup(path) else { return 0 }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else { return 0 }
        defer { fts_close(fts) }

        struct Inode: Hashable { let dev: Int32; let ino: UInt64 }
        var seen = Set<Inode>()
        var total: Int64 = 0
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            // FTS_DP is the second (post-order) visit of a folder; FTS_NS/FTS_ERR have no stat.
            if info == FTS_DP || info == FTS_NS || info == FTS_ERR { continue }
            guard let st = entry.pointee.fts_statp?.pointee else { continue }
            if st.st_nlink > 1 && (st.st_mode & S_IFMT) != S_IFDIR {
                guard seen.insert(Inode(dev: st.st_dev, ino: st.st_ino)).inserted else { continue }
            }
            total += Int64(st.st_blocks) * 512
        }
        return total
    }

    /// "500MB", "1.5G", "2 GB", "300000" → bytes, decimal units like Finder. Nil if it isn't a size.
    public static func parse(_ text: String) -> Int64? {
        let text = text.trimmingCharacters(in: .whitespaces).uppercased()
        let number = text.prefix { $0.isNumber || $0 == "." }
        let unit = text.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        let factors: [String: Double] = ["": 1, "B": 1, "K": 1e3, "KB": 1e3, "M": 1e6, "MB": 1e6, "G": 1e9, "GB": 1e9,
                                         "T": 1e12, "TB": 1e12]
        guard let value = Double(number), let factor = factors[unit] else { return nil }
        return Int64(value * factor)
    }

    /// Decimal units like Finder: 1 KB = 1000 bytes. "92 KB", "1.2 MB", "840 KB".
    public static func format(_ bytes: Int64) -> String {
        if bytes < 1000 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes) / 1000
        var unit = 0
        while unit < units.count - 1 && rounded(value) >= 1000 {
            value /= 1000
            unit += 1
        }
        let shown = rounded(value)
        let number = shown < 10 ? String(format: "%.1f", shown) : String(format: "%.0f", shown)
        return number + " " + units[unit]
    }

    /// One decimal below 10, whole numbers above.
    private static func rounded(_ value: Double) -> Double {
        let oneDecimal = (value * 10).rounded() / 10
        return oneDecimal < 10 ? oneDecimal : value.rounded()
    }
}
