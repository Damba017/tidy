import Foundation
import Testing
@testable import TidyCore

// These only ask the denylist about real paths; nothing here moves anything.

@Test func normalizeResolvesParentsButNotTheItem() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try FileManager.default.createSymbolicLink(atPath: fx.root + "/link", withDestinationPath: fx.home)

    #expect(Paths.normalize("/tmp/x") == "/private/tmp/x")
    #expect(Paths.normalize("~/foo/") == Paths.home + "/foo")
    #expect(Paths.normalize(fx.root + "/link") == fx.root + "/link")
    #expect(Paths.normalize(fx.root + "/link/a") == fx.home + "/a")
    #expect(Paths.normalize(fx.root + "/home/../home/a") == fx.home + "/a")
    #expect(Paths.normalize("/System/Volumes/Data" + Paths.home + "/foo") == Paths.home + "/foo")
    #expect(Paths.normalize("/System/Volumes/Data") == "/")
}

@Test(arguments: [
    "/", "~", "~/", "/Users", "/System", "/System/Library/CoreServices", "/usr", "/usr/bin/ls", "/bin",
    "/sbin", "/etc", "/etc/hosts", "/var", "/private/var/db/receipts", "/Library", "/Library/Apple",
    "/Applications", "/Applications/Utilities", "/usr/local", "/Volumes", "/opt/homebrew",
    "~/Library", "~/Library/Keychains", "~/Library/Keychains/login.keychain-db", "~/Library/Mail",
    "~/Library/Messages", "~/Library/Mobile Documents", "~/Library/Mobile Documents/com~apple~CloudDocs",
    "~/Pictures", "~/Pictures/Photos Library.photoslibrary", "~/Library/Caches", "~/Library/Application Support",
    "~/Library/Preferences", "~/Library/Containers", "~/Desktop", "~/Documents", "~/Downloads",
    "~/.Trash", "~/.Trash/something", "~/.local/state/tidy/log", "~/.ssh/id_ed25519",
    "/System/Volumes/Data", "/System/Volumes/Data/Users", "/System/Volumes/Data/.Spotlight-V100",
    "/private/tmp", "/tmp",
    // The disk ignores case, so the denylist does too.
    "~/LIBRARY", "~/library/keychains", "~/applications", "~/.local/state/TIDY", "/APPLICATIONS", "/system/library",
])
func protectedPathsAreRefused(path: String) {
    #expect(Denylist.reason(for: Paths.normalize(path)) != nil, "\(path) should be protected")
}

@Test(arguments: [
    "/usr/local/bin/fastfetch", "/Applications/Discord.app", "/Library/Caches/com.example",
    "~/Library/Caches/com.hnc.Discord", "~/Library/Application Support/discord", "~/.config/fastfetch",
    "~/Downloads/big.iso", "/tmp/tidy-test/x",
])
func ordinaryPathsMayBeOffered(path: String) {
    #expect(Denylist.reason(for: Paths.normalize(path)) == nil, "\(path) should be allowed")
}

@Test func normalizeTakesTheCaseFromTheDisk() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.folder("home/Library/Keychains")
    try FileManager.default.createSymbolicLink(atPath: fx.root + "/Link", withDestinationPath: fx.home)

    #expect(Paths.normalize(fx.home + "/library") == fx.home + "/Library")
    #expect(Paths.normalize(fx.home + "/LIBRARY/keychains") == fx.home + "/Library/Keychains")
    #expect(Paths.normalize(fx.root + "/LINK") == fx.root + "/Link")  // the link's own name, not its target's
    #expect(Paths.normalize(fx.home + "/Nope") == fx.home + "/Nope")  // not there: as typed
}

@Test func caseNeverGetsPastTheDenylist() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.folder("home/Library/Keychains")
    try fx.folder("home/Applications")
    try fx.folder("home/.local/state/tidy")

    // .SSH isn't there, so normalize can't fix its case: the denylist itself ignores case.
    for path in ["/library/KEYCHAINS", "/LIBRARY", "/applications", "/.local/state/TIDY", "/.LOCAL", "/.SSH"] {
        #expect(Denylist.reason(for: fx.home + path, home: fx.home) != nil, "\(path) should be protected")
        #expect(throws: TidyError.self) { try Trash.move(fx.home + path, home: fx.home, using: fx.trash) }
    }
    let plan = RemovalPlan(paths: [fx.home + "/applications", fx.home + "/Applications"], home: fx.home)
    #expect(plan.items.map(\.path) == [fx.home + "/Applications"])  // one folder, however it's spelled
    #expect(plan.items.map(\.status) == [.blocked("standard folder, only what's inside may go")])
    #expect(fx.trashed().isEmpty)
    #expect(Paths.exists(fx.home + "/Applications"))
}

@Test func restrictedFlagIsDetected() {
    var st = stat()
    #expect(lstat("/System/Library", &st) == 0)
    #expect(st.st_flags & UInt32(SF_RESTRICTED) != 0)
}

@Test func trashRefusesProtectedPathsInsideAFakeHome() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let keychains = try fx.folder("home/Library/Keychains")
    let library = fx.home + "/Library"

    for path in [keychains, library, fx.home] {
        #expect(throws: TidyError.self) { try Trash.move(path, home: fx.home, using: fx.trash) }
        #expect(Paths.exists(path))
    }
    #expect(fx.trashed().isEmpty)
}

@Test func fakeTrashRefusesAnythingOutsideTheFixtures() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    // Doesn't exist either, so even without the guard nothing could move.
    let outside = Paths.home + "/tidy-test-does-not-exist"
    #expect(throws: TidyError.self) { try fx.trash(outside) }
}

@Test func denylistHoldsWhenHomeOrPathGoThroughASymlink() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let keychains = try fx.folder("home/Library/Keychains")
    let viaTmp = { (path: String) in path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/") }

    #expect(Denylist.reason(for: keychains, home: viaTmp(fx.home)) != nil)
    #expect(Denylist.reason(for: viaTmp(keychains), home: fx.home) != nil)
    #expect(throws: TidyError.self) { try Trash.move(keychains, home: viaTmp(fx.home), using: fx.trash) }
    #expect(Paths.exists(keychains))
    #expect(fx.trashed().isEmpty)
}

@Test func freeDestinationNeverReusesAName() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let trash = try fx.folder("trash")
    #expect(Trash.freeDestination(for: "/x/Foo.app", in: trash) == trash + "/Foo.app")
    try fx.folder("trash/Foo.app")
    #expect(Trash.freeDestination(for: "/x/Foo.app", in: trash) == trash + "/Foo 2.app")
    try fx.folder("trash/Foo 2.app")
    #expect(Trash.freeDestination(for: "/x/Foo.app", in: trash) == trash + "/Foo 3.app")
    try fx.file("trash/notes")
    #expect(Trash.freeDestination(for: "/y/notes", in: trash) == trash + "/notes 2")
}
