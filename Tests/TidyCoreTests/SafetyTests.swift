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
    "~/.Trash", "~/.Trash/something", "~/.local/state/tidy/log", "~/.local/state/taydic", "~/.local/state/taydic/log",
    "~/.ssh/id_ed25519",
    "/System/Volumes/Data", "/System/Volumes/Data/Users", "/System/Volumes/Data/.Spotlight-V100",
    "/private/tmp", "/tmp",
    // The disk ignores case, so the denylist does too.
    "~/LIBRARY", "~/library/keychains", "~/applications", "~/.local/state/TIDY", "/APPLICATIONS", "/system/library",
    // macOS's own data: temp files of running apps, root's home, the network settings.
    "/private/var/folders", "/var/folders/xy", "/private/var/root", "/private/var/log",
    "/Library/Preferences/SystemConfiguration", "/Library/Preferences/SystemConfiguration/preferences.plist",
])
func protectedPathsAreRefused(path: String) {
    #expect(Denylist.reason(for: Paths.normalize(path)) != nil, "\(path) should be protected")
}

@Test(arguments: [
    "/usr/local/bin/fastfetch", "/Applications/Discord.app", "/Library/Caches/com.example",
    "/Library/Preferences/com.example.plist",
    "~/Library/Caches/com.hnc.Discord", "~/Library/Application Support/discord", "~/.config/fastfetch",
    "~/Downloads/big.iso", "/tmp/tidy-test/x",
])
func ordinaryPathsMayBeOffered(path: String) {
    #expect(Denylist.reason(for: Paths.normalize(path)) == nil, "\(path) should be allowed")
}

@Test func onlyWhatsInsideYourOwnTempAndCacheFoldersMayGo() throws {
    let folders = Paths.userTempFolders
    #expect(folders.count == 2)
    #expect(folders.allSatisfy { $0.hasPrefix("/private/var/folders/") })
    #expect(folders.map { ($0 as NSString).lastPathComponent } == ["T", "C"])
    let user = Paths.parent(folders[0])  // /private/var/folders/xx/…, which holds 0, C, T and X
    // Only names are checked here: none of these exist, and nothing is moved.
    for folder in folders {
        #expect(Denylist.reason(for: folder + "/com.example.tidy-test-nothing-here") == nil)
        #expect(Denylist.reason(for: folder + "/tidy-test/inside") == nil)
        #expect(Denylist.reason(for: folder) != nil, "\(folder) itself stays")
        #expect(Denylist.reason(for: folder.replacingOccurrences(of: "/private/var/", with: "/var/") + "/tidy-test-x") == nil)
    }
    for path in [
        user, user + "/0/tidy-test-x", user + "/X/tidy-test-x", "/private/var/folders", "/private/var/folders/zz",
        "/private/var/folders/zz/someone-else/T/tidy-test-x", folders[0] + "/../0/tidy-test-x", folders[0] + "/../X",
        folders[0] + "/tidy-test-not-there/../../0/x",  // can't be resolved, so it can't sneak out of T either
        "/private/var/db/tidy-test-x", "/private/var/root",
    ] {
        #expect(Denylist.reason(for: Paths.normalize(path)) != nil, "\(path) should be protected")
    }
}

@Test func onlyFirmlinkedDataVolumePathsAreMapped() {
    // Firmlinked folders are the same file on both sides.
    #expect(Paths.normalize("/System/Volumes/Data/Users") == "/Users")
    #expect(Paths.normalize("/System/Volumes/Data/usr/local") == "/usr/local")
    #expect(Paths.normalize("/System/Volumes/Data/Applications/Nope.app") == "/Applications/Nope.app")
    // /home on the sealed system is a different thing (a symlink); the other one isn't there at all.
    for path in ["/System/Volumes/Data/home", "/System/Volumes/Data/tidy-test-nothing-here"] {
        #expect(Paths.normalize(path) == path)
        #expect(Denylist.reason(for: path) != nil)
    }
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

@Test func noUnlinkFlagIsProtectedBySIP() {
    // Only the system can set `sunlnk`, so the check is tested on its own and on a real folder that has it.
    #expect(Denylist.isSIPProtected(flags: UInt32(SF_NOUNLINK)))
    #expect(Denylist.isSIPProtected(flags: UInt32(SF_RESTRICTED)))
    #expect(!Denylist.isSIPProtected(flags: 0))
    #expect(!Denylist.isSIPProtected(flags: UInt32(UF_IMMUTABLE) | UInt32(UF_HIDDEN)))  // his own flags: "locked", not SIP

    // In no list of its own, so only the flag keeps it out (it used to land under sudo, and fail).
    var st = stat()
    #expect(lstat("/Library/Frameworks", &st) == 0)
    #expect(st.st_flags & UInt32(SF_NOUNLINK) != 0)
    #expect(Denylist.reason(for: "/Library/Frameworks") == "protected by System Integrity Protection")
    let plan = RemovalPlan(paths: ["/Library/Frameworks"], home: Paths.home)
    #expect(plan.items.map(\.status) == [.blocked("protected by System Integrity Protection")])

    // A leftover SIP protects stays in the list, so the user hears it was left alone (the plan never moves it);
    // other protected paths still drop out, /System/Library too although it has SIP's flag.
    let leftovers = [Leftover(path: "/Library/Frameworks", match: .name), Leftover(path: "/System/Library", match: .name),
                     Leftover(path: Paths.home + "/Library/Keychains", match: .name)]
    #expect(Leftovers.merge(leftovers).map(\.path) == ["/Library/Frameworks"])
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
    #expect(try Trash.freeDestination(for: "/x/Foo.app", in: trash) == trash + "/Foo.app")
    try fx.folder("trash/Foo.app")
    #expect(try Trash.freeDestination(for: "/x/Foo.app", in: trash) == trash + "/Foo 2.app")
    try fx.folder("trash/Foo 2.app")
    #expect(try Trash.freeDestination(for: "/x/Foo.app", in: trash) == trash + "/Foo 3.app")
    try fx.file("trash/notes")
    #expect(try Trash.freeDestination(for: "/y/notes", in: trash) == trash + "/notes 2")
}

@Test func freeDestinationNeverGuesses() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let trash = try fx.folder("locked-trash")
    chmod(trash, 0)  // can't look inside, like a Trash behind privacy protection
    defer { chmod(trash, 0o755) }

    #expect(throws: TidyError.self) { try Trash.freeDestination(for: "/x/Foo.app", in: trash) }
}
