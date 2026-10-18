import Foundation
import Testing
@testable import TidyCore

/// Sets a file's last-opened and last-changed time to `days` ago.
private func age(_ path: String, days: Double) {
    let then = Date().addingTimeInterval(-days * 86_400)
    var times = [timeval(tv_sec: Int(then.timeIntervalSince1970), tv_usec: 0),
                 timeval(tv_sec: Int(then.timeIntervalSince1970), tv_usec: 0)]
    _ = utimes(path, &times)
}

@Test(arguments: [
    ("com.hnc.Discord", "com.hnc.discord"),
    ("com.hnc.Discord.plist", "com.hnc.discord"),
    ("com.hnc.Discord.savedState", "com.hnc.discord"),
    ("53Q6R32WPB.com.hnc.Discord", "com.hnc.discord"),
    ("group.net.whatsapp.WhatsApp", "net.whatsapp.whatsapp"),
    ("com.hnc.Discord.ShipIt.15EB2CEC-D7B0-50AB-A7CF-C414D0325337.plist", "com.hnc.discord.shipit"),
])
func bundleIDsAreReadFromLibraryNames(entry: String, expected: String) {
    #expect(Junk.bundleID(in: entry) == expected)
}

@Test(arguments: [
    "AddressBook", "Knowledge", "default.store", "io.branch", "21946402762.plist", "familycircled.plist",
    "0137DC29-AA41-4F0F-A74E-BE6E22B0F918", "FNaF Godot", "My App.plist", ".DS_Store", "com.foo.bar'x",
])
func plainNamesAreNoBundleIDs(entry: String) {
    #expect(Junk.bundleID(in: entry) == nil)
}

@Test func orphansAreOnlyUnclaimedBundleIDs() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let lib = "home/Library/"
    try fx.folder(lib + "Application Support/com.gone.oldapp")          // orphan, high
    try fx.folder(lib + "Application Support/com.gone.discordtools")    // orphan, low: "discord" is an app name
    try fx.file(lib + "Preferences/com.hnc.Discord.plist")              // claimed by Discord
    try fx.folder(lib + "Containers/com.utmapp.QEMUHelper")             // same vendor as UTM
    try fx.folder(lib + "Containers/com.apple.Safari")                  // Apple: never
    try fx.folder(lib + "Group Containers/group.com.apple.notes")       // Apple: never
    try fx.folder(lib + "Application Support/AddressBook")              // plain name: never
    try fx.file(lib + "Preferences/org.cups.PrintingPrefs.plist")       // macOS printing: never
    try fx.folder(lib + "Application Scripts/group.is.workflow.my.app") // Shortcuts: never
    try fx.folder(lib + "Application Support/com.elsewhere.app")        // an app Spotlight finds elsewhere
    try fx.file(lib + "Preferences/.GlobalPreferences.plist")

    let found = Junk.orphans(
        home: fx.home, claimedIDs: ["com.hnc.Discord", "com.utmapp.UTM"], names: ["Discord", "UTM"],
        spotlight: { $0 == "com.elsewhere.app" })

    #expect(found.map { ($0.path as NSString).lastPathComponent }.sorted() == ["com.gone.discordtools", "com.gone.oldapp"])
    #expect(found.first { $0.path.hasSuffix("oldapp") }?.note == "high confidence")
    #expect(found.first { $0.path.hasSuffix("discordtools") }?.note == "low confidence")
    #expect(found.allSatisfy { !$0.checked && $0.group == Junk.groupOrphans })
}

@Test func cachesLogsAndOnlyOldCrashReports() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.folder("home/Library/Caches/com.hnc.Discord")
    try fx.folder("home/Library/Caches/com.apple.Safari")
    try fx.folder("home/Library/Caches/Homebrew")
    try fx.file("home/Library/Caches/.DS_Store")
    try fx.folder("home/Library/Logs/Claude")
    let old = try fx.file("home/Library/Logs/DiagnosticReports/Old-2025.ips")
    try fx.file("home/Library/Logs/DiagnosticReports/New-2026.ips")
    age(old, days: 45)

    let found = Junk.caches(home: fx.home, now: Date(), crashReportDays: 30,
                            skipping: [fx.home + "/Library/Caches/Homebrew"])

    #expect(found.map { ($0.path as NSString).lastPathComponent } == ["com.hnc.Discord", "Claude", "Old-2025.ips"])
    #expect(found.map(\.label).prefix(2) == ["cache", "log"])
    #expect(found[2].label.hasPrefix("crash report, "))
    #expect(found.allSatisfy { $0.checked && $0.group == Junk.groupCaches })
}

@Test func walkFindsLargeOldFilesAndStaleBuildFolders() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let big = try fx.file("home/Downloads/big.iso", bytes: 300_000)
    let oldMedium = try fx.file("home/Movies/old.mov", bytes: 60_000)
    age(oldMedium, days: 400)
    try fx.file("home/Movies/recent.mov", bytes: 60_000)
    try fx.file("home/Library/huge-in-library", bytes: 300_000)       // ~/Library is never walked
    try fx.file("home/code/repo/.git/objects/pack.pack", bytes: 300_000)  // never inside .git
    let vm = try fx.file("home/VMs/Linux.utm/Data/disk.img", bytes: 300_000)  // a package: one item
    _ = vm

    // A stale Node project, a fresh Swift project, a lone "target" without Cargo.toml.
    try fx.file("home/code/old-web/package.json")
    try fx.file("home/code/old-web/node_modules/x/index.js")
    for path in ["home/code/old-web", "home/code/old-web/package.json"] { age(fx.root + "/" + path, days: 90) }
    try fx.file("home/code/swifty/Package.swift")
    try fx.file("home/code/swifty/.build/debug/app")
    try fx.file("home/code/random/target/stuff")
    try fx.file("home/code/py/__pycache__/m.pyc")

    var options = JunkOptions()
    options.minSize = 200_000
    options.oldMinSize = 50_000
    let walked = Junk.walk(home: fx.home, options: options, now: Date())

    #expect(walked.large.map(\.path).sorted() == [big, fx.home + "/Movies/old.mov", fx.home + "/VMs/Linux.utm"].sorted())
    #expect(walked.large.first?.group == "Large & old · Downloads" || walked.large.first?.group == "Large & old · VMs")
    #expect(walked.large.allSatisfy { !$0.checked && $0.label.hasPrefix("last used ") })
    #expect(walked.dev.map(\.path).sorted() == [fx.home + "/code/old-web/node_modules", fx.home + "/code/py/__pycache__"])
    #expect(walked.dev.allSatisfy { $0.checked })
}

@Test func virtualEnvironmentsAreOneItemOrNothing() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    // Stale bot with a manifest: its .venv is one item, nothing inside it is listed.
    try fx.file("home/oldbot/pyproject.toml")
    try fx.file("home/oldbot/bot/__pycache__/main.pyc")
    try fx.file("home/oldbot/.venv/pyvenv.cfg")
    try fx.file("home/oldbot/.venv/lib/python3.15/site-packages/telegram/__pycache__/x.pyc")
    for path in ["oldbot/pyproject.toml", "oldbot/bot"] { age(fx.home + "/" + path, days: 90) }
    // Fresh project: its venv stays. A venv without any manifest: never offered.
    try fx.file("home/newbot/requirements.txt")
    try fx.file("home/newbot/venv/pyvenv.cfg")
    try fx.file("home/scratch/env/pyvenv.cfg")
    for path in ["scratch"] { age(fx.home + "/" + path, days: 90) }
    // uv's own Pythons are never looked into.
    try fx.file("home/.local/share/uv/python/cpython-3.15/lib/json/__pycache__/x.pyc")

    let walked = Junk.walk(home: fx.home, options: JunkOptions(), now: Date())

    #expect(walked.dev.map(\.path).sorted() == [fx.home + "/oldbot/.venv", fx.home + "/oldbot/bot/__pycache__"])
    #expect(walked.dev.first { $0.path.hasSuffix(".venv") }?.label == "Python virtual environment")
}

@Test func largeListIsCappedBiggestFirst() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    for i in 1...5 { try fx.file("home/f\(i)", bytes: i * 50_000) }
    var options = JunkOptions()
    options.minSize = 40_000
    options.largeLimit = 3

    let walked = Junk.walk(home: fx.home, options: options, now: Date())

    #expect(walked.large.map { ($0.path as NSString).lastPathComponent } == ["f5", "f4", "f3"])
    #expect(walked.largeLeftOut == 2)
    #expect(walked.large.allSatisfy { $0.group == "Large & old · ~" })
}

@Test func packageCachesOnlyWhenThereAndArchivesUnchecked() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.folder("home/.cache/uv")
    try fx.folder("home/Library/Developer/Xcode/Archives")

    let found = Junk.packageCaches(home: fx.home)

    #expect(found.map(\.label) == ["uv cache", "Xcode archives"])
    #expect(found.map(\.checked) == [true, false])
}

@Test func unavailableSimulatorsFromSimctlJSON() {
    let json = """
    {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
      {"udid": "AAAA", "isAvailable": false, "name": "iPhone 15"},
      {"udid": "BBBB", "isAvailable": true, "name": "iPhone 15 Pro"}]}}
    """
    #expect(Junk.unavailableSimulators(json) == ["AAAA"])
    #expect(Junk.unavailableSimulators("nonsense").isEmpty)
}
