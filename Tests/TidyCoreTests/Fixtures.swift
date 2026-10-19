import Foundation
@testable import TidyCore

/// A fresh folder under /tmp/tidy-test/ with a fake home and a fake Trash inside it.
/// Tests that move things only ever touch files in here, and pass `trash` instead of the real Trash.
struct Fixture {
    let root: String
    var home: String { root + "/home" }
    var trashFolder: String { root + "/trash" }
    var log: Log { Log(path: root + "/log") }

    init() throws {
        let path = "/tmp/tidy-test/" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path + "/home", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: path + "/trash", withIntermediateDirectories: true)
        root = Paths.normalize(path)  // /private/tmp/…, now that it exists
    }

    /// Stands in for the real Trash: moves into this fixture's own trash folder.
    /// Refuses anything outside /tmp/tidy-test, so even a broken test can't move a real file.
    func trash(_ path: String) throws -> String {
        guard path.hasPrefix("/private/tmp/tidy-test/") else {
            throw TidyError("test tried to trash \(path), outside /tmp/tidy-test")
        }
        let destination = try Trash.freeDestination(for: path, in: trashFolder)
        try FileManager.default.moveItem(atPath: path, toPath: destination)
        return destination
    }

    /// What ended up in this fixture's fake Trash.
    func trashed() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: trashFolder)) ?? []
    }

    @discardableResult
    func file(_ relative: String, bytes: Int = 10) throws -> String {
        let path = root + "/" + relative
        try FileManager.default.createDirectory(atPath: Paths.parent(path), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: URL(fileURLWithPath: path))
        return path
    }

    @discardableResult
    func folder(_ relative: String) throws -> String {
        let path = root + "/" + relative
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }
}
