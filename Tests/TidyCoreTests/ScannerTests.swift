import Foundation
import Testing
@testable import TidyCore

@Test func scannerMatchesAllocatedSizeAndCountsHardLinksOnce() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let one = try fx.file("home/a/one", bytes: 100_000)
    try fx.file("home/a/b/two", bytes: 50_000)
    try fx.file("home/a/b/c/three", bytes: 7_000)
    try fx.folder("home/empty")
    try FileManager.default.linkItem(atPath: one, toPath: fx.home + "/a/b/hard")
    try FileManager.default.createSymbolicLink(atPath: fx.home + "/a/link-to-root", withDestinationPath: "/")

    let root = Scanner().scan(fx.home)

    #expect(root.error == nil)
    #expect(root.size == Size.allocated(fx.home))
    #expect(root.fileCount == 5)  // one, two, three, hard, link-to-root
    let a = try #require(root.dirs.first { $0.name == "a" })
    #expect(a.files.map(\.name).sorted() == ["link-to-root", "one"])
    #expect(a.dirs.map(\.name) == ["b"])
    #expect(a.dirs[0].parent === a)
    #expect(a.size < 300_000)  // the symlink to / wasn't followed
    let sizes = [a.files.first { $0.name == "one" }!.size, a.dirs[0].files.first { $0.name == "hard" }!.size]
    #expect(sizes.filter { $0 == 0 }.count == 1)  // one of the two hard-link names counts, the other is 0
    #expect(root.dirs.first { $0.name == "empty" }?.size == 0)
}

@Test func scannerMarksUnreadableFolders() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let locked = try fx.folder("home/locked")
    try fx.file("home/locked/secret", bytes: 5000)
    try fx.file("home/fine", bytes: 5000)
    chmod(locked, 0)
    defer { chmod(locked, 0o755) }

    let root = Scanner().scan(fx.home)

    let node = try #require(root.dirs.first { $0.name == "locked" })
    #expect(node.error == "permission denied")
    #expect(node.size == 0)
    #expect(root.files.map(\.name) == ["fine"])
}

@Test func scannerHandlesManyEntries() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    for d in 0..<20 {
        for f in 0..<150 { try fx.file("home/d\(d)/file-with-a-longer-name-\(f).txt", bytes: 100 + f) }
    }

    let root = Scanner().scan(fx.home)

    #expect(root.fileCount == 3000)
    #expect(root.dirs.count == 20)
    #expect(root.size == Size.allocated(fx.home))
}

@Test func removingAndRescanningKeepTotalsRight() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.file("home/a/b/big", bytes: 200_000)
    try fx.file("home/a/small", bytes: 1000)
    let root = Scanner().scan(fx.home)
    let a = try #require(root.dirs.first)
    let b = try #require(a.dirs.first)
    let before = root.size

    a.removeEntry(named: "b")
    #expect(a.dirs.isEmpty)
    #expect(root.size == before - b.size)
    #expect(root.fileCount == 1)

    try fx.file("home/a/new", bytes: 50_000)
    a.replaceContents(with: Scanner().scan(a.path))
    #expect(a.files.map(\.name).sorted() == ["new", "small"])
    #expect(root.size == Size.allocated(fx.home))
    #expect(root.fileCount == 2 + 1)  // a/b/big is still on disk, so the rescan finds it again
}

@Test func bootVolumeIsScannedThroughItsDataVolume() throws {
    let boot = try #require(Volumes.mounted().first { $0.isBoot })
    #expect(boot.scanRoot == "/System/Volumes/Data")
    #expect(boot.total > boot.used && boot.used > 0)
    let system = try #require(Volumes.spaceUsed("/"))
    #expect(system > 1_000_000_000 && system < boot.total)
}
