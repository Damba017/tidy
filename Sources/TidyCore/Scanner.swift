import Foundation

public struct FileEntry: Sendable {
    public let name: String
    /// Allocated bytes; 0 for the second and later names of a hard-linked file.
    public let size: Int64
    /// A symlink: its size is the link itself, the target isn't followed.
    public let isSymlink: Bool
}

/// A scanned folder. Only folders are nodes; files are plain entries to keep memory down.
///
/// `@unchecked Sendable`: while scanning, a node is only written by the one worker that reads
/// its folder, and the tree is only read after the scan has finished.
public final class DirNode: @unchecked Sendable {
    public let path: String
    public private(set) weak var parent: DirNode?
    public private(set) var dirs: [DirNode] = []
    public private(set) var files: [FileEntry] = []
    /// Allocated bytes of everything inside, filled in when the scan finishes.
    public private(set) var size: Int64 = 0
    public private(set) var fileCount = 0
    /// Why this folder wasn't scanned, e.g. "permission denied".
    public private(set) var error: String?

    init(path: String, parent: DirNode?) {
        self.path = path
        self.parent = parent
    }

    public var name: String { (path as NSString).lastPathComponent }

    /// Forgets the entry called `name` (after it went to the Trash) and shrinks the totals above it.
    public func removeEntry(named name: String) {
        if let i = dirs.firstIndex(where: { $0.name == name }) {
            let removed = dirs.remove(at: i)
            adjust(size: -removed.size, files: -removed.fileCount)
        } else if let i = files.firstIndex(where: { $0.name == name }) {
            let removed = files.remove(at: i)
            adjust(size: -removed.size, files: -1)
        }
    }

    /// Takes over the contents of a fresh scan of this same folder.
    public func replaceContents(with fresh: DirNode) {
        let sizeChange = fresh.size - size
        let fileChange = fresh.fileCount - fileCount
        dirs = fresh.dirs
        dirs.forEach { $0.parent = self }
        files = fresh.files
        error = fresh.error
        adjust(size: sizeChange, files: fileChange)
    }

    private func adjust(size change: Int64, files fileChange: Int) {
        var node: DirNode? = self
        while let current = node {
            current.size += change
            current.fileCount += fileChange
            node = current.parent
        }
    }

    fileprivate func add(_ dir: DirNode) { dirs.append(dir) }
    fileprivate func add(_ file: FileEntry) { files.append(file) }
    fileprivate func fail(_ reason: String) { error = reason }

    /// Adds up sizes bottom-up once every folder has been read.
    fileprivate func finish() {
        var total: Int64 = 0
        for file in files { total += file.size }
        var count = files.count
        for dir in dirs {
            dir.finish()
            total += dir.size
            count += dir.fileCount
        }
        size = total
        fileCount = count
    }
}

/// Reads a folder tree with several threads at once, using getattrlistbulk (one call returns
/// names, types and sizes for a whole batch of entries). Stays on one filesystem, never follows
/// symlinks, counts hard links once and uses allocated size. One Scanner per scan.
public final class Scanner: @unchecked Sendable {
    public struct Progress: Sendable {
        public var files = 0
        public var folders = 0
        public var current = ""
    }

    private let condition = NSCondition()  // guards everything below except `seen`
    private var pending: [DirNode] = []
    private var busy = 0
    private var cancelled = false
    private var state = Progress()
    private var sawEPERM = false
    private var device: dev_t = 0

    private let seenLock = NSLock()
    private var seen = Set<UInt64>()

    private static let bufferSize = 256 * 1024

    public init() {}

    /// Scans `path` and returns the finished tree. Blocks until done or cancelled.
    public func scan(_ path: String) -> DirNode {
        let root = DirNode(path: path, parent: nil)
        var st = stat()
        guard lstat(path, &st) == 0 else {
            root.fail(describe(errno))
            return root
        }
        device = st.st_dev
        pending = [root]
        let workers = min(16, max(4, ProcessInfo.processInfo.activeProcessorCount * 2))
        let group = DispatchGroup()
        for _ in 0..<workers {
            group.enter()
            Thread {
                self.work()
                group.leave()
            }.start()
        }
        group.wait()
        root.finish()
        return root
    }

    public func progress() -> Progress {
        condition.lock()
        defer { condition.unlock() }
        return state
    }

    public func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    /// True if a folder was refused with EPERM: usually macOS privacy protection (Full Disk Access).
    public var needsFullDiskAccess: Bool {
        condition.lock()
        defer { condition.unlock() }
        return sawEPERM
    }

    private func work() {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            condition.lock()
            while pending.isEmpty && busy > 0 && !cancelled { condition.wait() }
            if pending.isEmpty || cancelled {
                condition.broadcast()
                condition.unlock()
                return
            }
            let node = pending.removeLast()
            busy += 1
            state.current = node.path
            condition.unlock()

            let subfolders = read(node, into: buffer)

            condition.lock()
            pending += subfolders
            busy -= 1
            state.folders += 1
            state.files += node.files.count
            condition.broadcast()
            condition.unlock()
        }
    }

    /// Reads one folder: files become entries, subfolders become nodes to scan next.
    private func read(_ node: DirNode, into buffer: UnsafeMutableRawPointer) -> [DirNode] {
        let fd = open(node.path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else {
            node.fail(describe(errno))
            return []
        }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_dev == device else {
            node.fail("other volume, not scanned")
            return []
        }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)
        request.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

        var subfolders: [DirNode] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, Self.bufferSize, 0)
            if count == 0 { break }
            if count < 0 {
                node.fail(describe(errno))
                break
            }
            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                defer { entry += length }
                // Fields follow in a fixed order; each is only there if its bit is in `returned`.
                var field = entry + 4
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size
                if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                    let error = field.loadUnaligned(as: UInt32.self)
                    field += 4
                    if error != 0 { continue }
                }
                guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { continue }
                let nameRef = field.loadUnaligned(as: attrreference_t.self)
                let name = String(cString: (field + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                field += MemoryLayout<attrreference_t>.size
                var type: UInt32 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    type = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }
                var fileID: UInt64 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                    fileID = field.loadUnaligned(as: UInt64.self)
                    field += 8
                }
                if type == VDIR.rawValue {
                    let child = DirNode(path: node.path == "/" ? "/" + name : node.path + "/" + name, parent: node)
                    node.add(child)
                    subfolders.append(child)
                    continue
                }
                var links: UInt32 = 1
                if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
                    links = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }
                var size: Int64 = 0
                if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    size = field.loadUnaligned(as: Int64.self)
                }
                if links > 1 && !firstSighting(of: fileID) { size = 0 }
                node.add(FileEntry(name: name, size: size, isSymlink: type == VLNK.rawValue))
            }
        }
        return subfolders
    }

    private func firstSighting(of fileID: UInt64) -> Bool {
        seenLock.lock()
        defer { seenLock.unlock() }
        return seen.insert(fileID).inserted
    }

    private func describe(_ code: Int32) -> String {
        if code == EPERM {
            condition.lock()
            sawEPERM = true
            condition.unlock()
        }
        return code == EPERM || code == EACCES ? "permission denied" : String(cString: strerror(code))
    }
}
