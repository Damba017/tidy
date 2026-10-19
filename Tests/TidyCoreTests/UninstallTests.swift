import Foundation
import Testing
@testable import TidyCore

/// Writes a minimal .app bundle with an Info.plist into the fixture.
@discardableResult
func makeApp(_ fx: Fixture, _ relative: String, bundleID: String, name: String? = nil,
             executable: String? = nil, appStore: Bool = false) throws -> String {
    let path = try fx.folder(relative)
    try fx.folder(relative + "/Contents/MacOS")
    var info: [String: Any] = ["CFBundleIdentifier": bundleID]
    if let name { info["CFBundleName"] = name }
    if let executable { info["CFBundleExecutable"] = executable }
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: path + "/Contents/Info.plist"))
    if appStore { try fx.file(relative + "/Contents/_MASReceipt/receipt") }
    return path
}

@Test func findsAppsAndTheirSource() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try makeApp(fx, "apps/Discord.app", bundleID: "com.hnc.Discord", executable: "Discord")
    try makeApp(fx, "apps/Pages.app", bundleID: "com.apple.iWork.Pages", appStore: true)
    try makeApp(fx, "apps/Microsoft Office/Word.app", bundleID: "com.microsoft.Word")
    try FileManager.default.createSymbolicLink(atPath: fx.root + "/apps/Linked.app", withDestinationPath: fx.root + "/apps/Pages.app")
    try fx.file("apps/readme.txt")

    let apps = AppFinder.installedApps(in: [fx.root + "/apps"])

    #expect(apps.map(\.name) == ["Discord", "Pages", "Word"])
    #expect(apps.map(\.source) == [.manual, .appStore, .manual])
    #expect(apps[0].bundleID == "com.hnc.Discord")
}

@Test func wrappedIPhoneAppsAreReadToo() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    // Like /Applications/Marktplaats.app: WrappedBundle -> Wrapper/Marktplaats.app, plus iTunesMetadata.plist.
    try makeApp(fx, "apps/Marktplaats.app/Wrapper/Marktplaats.app", bundleID: "com.marktplaats.iphone")
    let inner = fx.root + "/apps/Marktplaats.app/Wrapper/Marktplaats.app"
    try FileManager.default.moveItem(atPath: inner + "/Contents/Info.plist", toPath: inner + "/Info.plist")
    try FileManager.default.createSymbolicLink(atPath: fx.root + "/apps/Marktplaats.app/WrappedBundle",
                                               withDestinationPath: "Wrapper/Marktplaats.app")
    try fx.file("apps/Marktplaats.app/Wrapper/iTunesMetadata.plist")

    let app = try #require(AppFinder.load(fx.root + "/apps/Marktplaats.app"))

    #expect(app.bundleID == "com.marktplaats.iphone")
    #expect(app.source == .appStore)
}

@Test func onlyAppBundlesAreTakenForApps() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let discord = try makeApp(fx, "apps/Discord.app", bundleID: "com.hnc.Discord")
    try makeApp(fx, "apps/Marktplaats.app/Wrapper/Marktplaats.app", bundleID: "com.marktplaats.iphone")
    let inner = fx.root + "/apps/Marktplaats.app/Wrapper/Marktplaats.app"
    try FileManager.default.moveItem(atPath: inner + "/Contents/Info.plist", toPath: inner + "/Info.plist")
    try FileManager.default.createSymbolicLink(atPath: fx.root + "/apps/Marktplaats.app/WrappedBundle",
                                               withDestinationPath: "Wrapper/Marktplaats.app")
    let projects = try fx.folder("apps/Projects")
    let empty = try fx.folder("apps/Empty.app")  // no Info.plist
    try FileManager.default.createSymbolicLink(atPath: fx.root + "/apps/Linked.app", withDestinationPath: discord)

    #expect(AppFinder.isAppBundle(discord))
    #expect(AppFinder.isAppBundle(fx.root + "/apps/Marktplaats.app"))
    #expect(!AppFinder.isAppBundle(projects))
    #expect(!AppFinder.isAppBundle(empty))
    #expect(!AppFinder.isAppBundle(fx.root + "/apps/Linked.app"))

    // A path to an app a cask owns goes via brew, however it's spelled; any other folder is no app at all.
    let cask = Candidate(package: BrewPackage(name: "discord", kind: .cask, apps: ["Discord.app"]),
                         app: AppFinder.load(discord))
    #expect(Candidates.app(at: fx.root + "/apps/discord.app", in: [cask]) == cask)
    #expect(Candidates.app(at: projects, in: [cask]) == nil)
    #expect(Candidates.app(at: empty, in: [cask]) == nil)
}

@Test func matchingPrefersExactNamesOverSubstrings() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try makeApp(fx, "apps/Discord.app", bundleID: "com.hnc.Discord")
    try makeApp(fx, "apps/Discord PTB.app", bundleID: "com.hnc.DiscordPTB")
    try makeApp(fx, "apps/Firefox.app", bundleID: "org.mozilla.firefox", name: "Firefox")
    let candidates = Candidates.combine(
        apps: AppFinder.installedApps(in: [fx.root + "/apps"]),
        packages: [BrewPackage(name: "fastfetch", kind: .formula, apps: [])])

    #expect(Candidates.matches("discord", in: candidates).map(\.name) == ["Discord"])
    #expect(Candidates.matches("DISC", in: candidates).map(\.name) == ["Discord", "Discord PTB"])
    #expect(Candidates.matches("org.mozilla.firefox", in: candidates).map(\.name) == ["Firefox"])
    #expect(Candidates.matches("FASTFETCH", in: candidates).map(\.source) == [.brewFormula])
    #expect(Candidates.matches("nope", in: candidates).isEmpty)
}

@Test(arguments: [
    ("com.hnc.Discord", Leftover.Match.bundleID),
    ("com.hnc.Discord.plist", .bundleID),
    ("com.hnc.Discord.ShipIt", .bundleID),
    ("com.hnc.Discord.savedState", .bundleID),
    ("com.hnc.Discord.0A1B2C3D-AAAA-BBBB-CCCC-123456789ABC.plist", .bundleID),
    ("53Q6R32WPB.com.hnc.Discord", .bundleID),
    ("group.com.hnc.Discord", .bundleID),
    ("discord", .name),
    ("Discord", .name),
    ("BetterDiscord", .fuzzy),
    ("com.hnc.DiscordPTB", .fuzzy),
])
func leftoverNamesMatch(entry: String, expected: Leftover.Match) {
    #expect(Leftovers.match(entry, bundleID: "com.hnc.Discord", names: ["discord"]) == expected)
}

@Test(arguments: [
    "com.spotify.client", "Google", "com.apple.discord.helper", "dis", "com.hnc.Discor",
    // Apple's, even where the name doesn't start with com.apple.
    "group.com.apple.discord", "2BUA8C4S2C.com.apple.discord.plist",
])
func unrelatedEntriesDontMatch(entry: String) {
    #expect(Leftovers.match(entry, bundleID: "com.hnc.Discord", names: ["discord"]) == nil)
}

@Test func applesOwnFilesOnlyMatchThroughTheBundleID() {
    // An app called Notes never gets the Notes database; Apple's Pages still finds its own group container.
    #expect(Leftovers.match("group.com.apple.notes", bundleID: "com.example.notes", names: ["notes"]) == nil)
    #expect(Leftovers.match("group.com.apple.Pages", bundleID: "com.apple.Pages", names: ["pages"]) == .bundleID)
}

/// Another app on this Mac, as Leftovers.otherApps returns it.
private func other(_ bundleID: String?, at path: String, name: String? = nil, executable: String? = nil) -> App {
    App(path: path, bundleID: bundleID, bundleName: name, displayName: nil, executable: executable, source: .manual)
}

@Test func genericAndShortNamesAreNotUsed() {
    let app = App(path: "/Applications/Go.app", bundleID: "com.example.go", bundleName: "Electron",
                  displayName: nil, executable: "Helper", source: .manual)
    #expect(Leftovers.usableNames(app.names).isEmpty)
}

@Test func findsLeftoversInLibraryFolders() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let path = try makeApp(fx, "apps/Discord.app", bundleID: "com.hnc.Discord", executable: "Discord")
    let app = try #require(AppFinder.load(path))
    try fx.file("lib/Application Support/discord/settings.json")
    try fx.file("lib/Application Support/BetterDiscord/plugin.js")
    try fx.file("lib/Application Support/Spotify/prefs")
    try fx.folder("lib/Caches/com.hnc.Discord")
    try fx.folder("lib/Caches/com.hnc.Discord.ShipIt")
    try fx.file("lib/Preferences/com.hnc.Discord.plist")
    try fx.folder("lib/Group Containers/53Q6R32WPB.com.hnc.Discord")
    try fx.file("lib/Preferences/com.apple.finder.plist")
    let locations = ["Application Support", "Caches", "Preferences", "Group Containers"].map { fx.root + "/lib/" + $0 }

    let found = Leftovers.find(bundleID: app.bundleID, names: app.names, in: locations, others: [])

    // Strongest match first, then by full path (Caches, Group Containers, Preferences).
    #expect(found.map { ($0.path as NSString).lastPathComponent } == [
        "com.hnc.Discord", "com.hnc.Discord.ShipIt", "53Q6R32WPB.com.hnc.Discord", "com.hnc.Discord.plist",
        "discord", "BetterDiscord",
    ])
    #expect(found.map(\.match) == [.bundleID, .bundleID, .bundleID, .bundleID, .name, .fuzzy])
    #expect(found.filter(\.checkedByDefault).count == 5)
}

@Test func filesOfAnotherAppWithALongerBundleIDStayOut() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.folder("lib/Caches/com.google.Chrome")
    try fx.folder("lib/Caches/com.google.Chrome.helper")        // Chrome's own helper
    try fx.folder("lib/Caches/com.google.Chrome.canary")        // Chrome Canary, another app
    try fx.file("lib/Preferences/com.google.Chrome.canary.plist")
    try fx.file("lib/Preferences/com.google.Chrome.plist")
    let locations = ["Caches", "Preferences"].map { fx.root + "/lib/" + $0 }

    let chrome = Leftovers.find(bundleID: "com.google.Chrome", names: ["Google Chrome"], in: locations, others: [
        other("com.google.Chrome.canary", at: "/Applications/Google Chrome Canary.app"),
        other("com.hnc.Discord", at: "/Applications/Discord.app"),
    ])
    let canary = Leftovers.find(bundleID: "com.google.Chrome.canary", names: ["Google Chrome Canary"], in: locations,
                                others: [other("com.google.Chrome", at: "/Applications/Google Chrome.app")])

    #expect(chrome.map { ($0.path as NSString).lastPathComponent }
            == ["com.google.Chrome", "com.google.Chrome.helper", "com.google.Chrome.plist"])
    #expect(canary.map { ($0.path as NSString).lastPathComponent }
            == ["com.google.Chrome.canary", "com.google.Chrome.canary.plist"])
}

@Test func whatASecondCopyOrAnAppByTheSameNameUsesStays() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.folder("lib/Application Support/Firefox")                // regular Firefox's profiles too
    try fx.folder("lib/Caches/org.mozilla.nightly")                 // Nightly's own
    try fx.file("lib/Preferences/com.apple.dt.Xcode.plist")         // Xcode's, and Xcode-beta's
    try fx.folder("lib/Caches/com.apple.dt.Xcode")
    let locations = ["Application Support", "Caches", "Preferences"].map { fx.root + "/lib/" + $0 }

    // Firefox Nightly's executable is "firefox", just like Firefox's.
    let nightly = Leftovers.find(bundleID: "org.mozilla.nightly", names: ["Firefox Nightly", "firefox"], in: locations,
                                 others: [other("org.mozilla.firefox", at: "/Applications/Firefox.app", executable: "firefox")])
    // Xcode-beta has the same bundle ID as Xcode.
    let beta = Leftovers.find(bundleID: "com.apple.dt.Xcode", names: ["Xcode-beta", "Xcode"], in: locations,
                              others: [other("com.apple.dt.Xcode", at: "/Applications/Xcode.app", name: "Xcode")])
    let alone = Leftovers.find(bundleID: "org.mozilla.nightly", names: ["Firefox Nightly", "firefox"], in: locations,
                               others: [])

    #expect(nightly.map { ($0.path as NSString).lastPathComponent } == ["org.mozilla.nightly"])
    #expect(beta.isEmpty)
    #expect(alone.map { ($0.path as NSString).lastPathComponent } == ["org.mozilla.nightly", "Firefox"])
}

@Test func anAppsOwnHelpersAreNoOtherApps() {
    let chrome = other("com.google.Chrome", at: "/Applications/Google Chrome.app")
    let canary = "/Applications/Google Chrome Canary.app"
    let apps = [
        chrome,
        other("com.google.Chrome.canary", at: canary),
        other("com.google.Chrome.helper", at: chrome.path + "/Contents/Frameworks/Google Chrome Helper.app"),
        other("com.google.Chrome.canary.helper", at: canary + "/Contents/Frameworks/Helper.app"),
    ]
    #expect(Leftovers.otherApps(than: chrome, among: apps).compactMap(\.bundleID)
            == ["com.google.Chrome.canary", "com.google.Chrome.canary.helper"])
    #expect(Leftovers.otherApps(than: nil, among: apps).count == 4)  // a formula: every app is another app
}

@Test func pkgReceiptFilesBecomeLeftovers() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let path = try makeApp(fx, "root/Applications/Foo.app", bundleID: "com.example.foo", executable: "Foo")
    let app = try #require(AppFinder.load(path))
    try fx.file("root/Library/Application Support/Foo/data.db")
    try fx.file("root/Library/Application Support/Foo/sub/more.db")
    try fx.file("root/usr/local/bin/foo-cli")
    let files = [
        "Applications/Foo.app/Contents/Info.plist",  // inside the app: not a leftover
        "Library/Application Support/Foo/data.db",
        "Library/Application Support/Foo/sub/more.db",
        "usr/local/bin/foo-cli",
        "usr/local/bin/gone",  // no longer on disk
    ]

    let found = Leftovers.pkgPaths(files: files, root: fx.root + "/root", app: app, others: [])

    #expect(found.map(\.path) == [
        fx.root + "/root/Library/Application Support/Foo",  // the whole folder named after the app
        fx.root + "/root/usr/local/bin/foo-cli",
    ])
    #expect(found.allSatisfy { $0.match == .pkgReceipt })
}

@Test func pkgFilesOfAnotherAppStayOut() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    // One .pkg installed both apps, in a folder named after the first one.
    let path = try makeApp(fx, "root/Applications/Foo/Foo.app", bundleID: "com.example.foo", executable: "Foo")
    let app = try #require(AppFinder.load(path))
    let bar = try #require(AppFinder.load(try makeApp(fx, "root/Applications/Foo/Bar.app", bundleID: "com.example.bar")))
    try fx.file("root/Applications/Foo/Bar.app/Contents/MacOS/Bar")
    try fx.file("root/Applications/Foo/readme.txt")
    try fx.file("root/Library/Application Support/Foo/data.db")
    let files = [
        "Applications/Foo/Foo.app/Contents/Info.plist",
        "Applications/Foo/Bar.app/Contents/MacOS/Bar",  // inside the other app
        "Applications/Foo/readme.txt",                 // its folder holds the other app: only the file
        "Library/Application Support/Foo/data.db",
    ]

    let found = Leftovers.pkgPaths(files: files, root: fx.root + "/root", app: app, others: [bar])

    #expect(found.map(\.path) == [
        fx.root + "/root/Applications/Foo/readme.txt",
        fx.root + "/root/Library/Application Support/Foo",
    ])
}

@Test func mergeKeepsTheStrongestMatchAndDropsNestedItems() {
    let merged = Leftovers.merge([
        Leftover(path: "/tmp/tidy-test/x/a", match: .fuzzy),
        Leftover(path: "/tmp/tidy-test/x/a", match: .bundleID),
        Leftover(path: "/tmp/tidy-test/x/a/inner", match: .name),
        Leftover(path: Paths.home + "/Library/Keychains", match: .bundleID),
    ])
    #expect(merged == [Leftover(path: "/tmp/tidy-test/x/a", match: .bundleID)])
}
