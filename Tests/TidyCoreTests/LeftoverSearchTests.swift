import Foundation
import Testing
@testable import TidyCore

// `taydic leftovers <name>`. Everything here reads only; the fixtures stand in for ~/Library and the PATH.

private func app(_ name: String, _ bundleID: String?, executable: String? = nil) -> App {
    App(path: "/Applications/\(name).app", bundleID: bundleID, bundleName: nil, displayName: nil,
        executable: executable, source: .manual)
}

@Test(arguments: ["discord", "Visual Studio Code", "  cava  "])
func namesThatCanBeSearchedFor(name: String) {
    #expect(LeftoverSearch.problem(with: name) == nil)
}

@Test(arguments: ["", "go", "app", "Helper", "../discord", "~/Library", ".config", "---"])
func namesThatCantBeSearchedFor(name: String) {
    #expect(LeftoverSearch.problem(with: name) != nil)
}

@Test func whatsStillInstalledIsNeverSearched() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let tool = try fx.file("bin/tidytesttool")
    chmod(tool, 0o755)
    try fx.file("bin/notacommand")  // not executable
    let candidates = [
        Candidate(app: app("Discord", "com.hnc.Discord")),
        Candidate(package: BrewPackage(name: "fastfetch", kind: .formula, apps: [])),
    ]
    let apps = [app("Notes", "com.apple.Notes")]  // macOS's own, or a running one
    let folders = [fx.root + "/bin"]
    func installed(_ name: String) -> (what: String, byUninstall: Bool)? {
        LeftoverSearch.stillInstalled(name, candidates: candidates, apps: apps, commandFolders: folders)
    }

    #expect(installed("DISCORD")?.what.hasPrefix("Discord") == true)
    #expect(installed("DISCORD")?.byUninstall == true)
    #expect(installed("com.hnc.discord") != nil)
    #expect(installed("fastfetch")?.byUninstall == true)
    #expect(installed("notes")?.what.hasPrefix("Notes") == true)
    #expect(installed("notes")?.byUninstall == false)  // macOS's own: taydic uninstall doesn't do that
    #expect(installed("tidytesttool")?.what == tool)
    #expect(installed("notacommand") == nil)
    #expect(installed("betterdiscord") == nil)
    // macOS's own tools are in the PATH too: git is installed, so its files are in use.
    #expect(LeftoverSearch.stillInstalled("git", candidates: [], apps: [], commandFolders: ["/usr/bin"])?.what == "/usr/bin/git")
}

@Test func macOSsOwnAppsCountAsInstalled() {
    let names = LeftoverSearch.macOSApps().flatMap(\.names).map { $0.lowercased() }
    for name in ["notes", "photos", "finder", "safari"] { #expect(names.contains(name), "\(name)") }
}

@Test func appsWithANameOrBundleIDLikeItAreNamed() {
    let candidates = [Candidate(app: app("Discord PTB", "com.hnc.DiscordPTB")), Candidate(app: app("Firefox", "org.mozilla.firefox"))]
    let apps = [app("Chrome", "com.google.Chrome")]
    #expect(LeftoverSearch.similar("discord", candidates: candidates, apps: apps) == ["Discord PTB"])
    // A vendor's folder (Application Support/Google) holds the installed app's own files.
    #expect(LeftoverSearch.similar("google", candidates: candidates, apps: apps) == ["Chrome"])
    #expect(LeftoverSearch.similar("tidytestapp", candidates: candidates, apps: apps).isEmpty)
}

@Test func leftoversAreFoundByNameAndOtherAppsKeepTheirs() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let lib = "home/Library/"
    let support = try fx.folder(lib + "Application Support/tidytestapp")           // name
    let logs = try fx.folder(lib + "Logs/TidyTestApp")                               // name, other case
    let cache = try fx.folder(lib + "Caches/com.example.tidytestapp")              // only fuzzy: no bundle ID to go by
    let config = try fx.file("home/.config/tidytestapp/settings.json")
    try fx.folder(lib + "Caches/com.example.tidytestapp.plus")                     // another app's bundle ID
    try fx.folder(lib + "Application Support/TidyTestApp Pro")                     // another app's name
    try fx.folder(lib + "Group Containers/group.com.apple.tidytestapp")            // Apple's: never by name
    let others = [app("TidyTestApp Pro", "com.example.tidytestapp.plus")]

    let found = LeftoverSearch.find("TidyTestApp", home: fx.home, toolFolders: [fx.root + "/bin"], others: others)

    #expect(Set(found.map(\.path)) == [support, logs, cache, Paths.parent(config)])
    #expect(found.first { $0.path == cache }?.match == .fuzzy)
    #expect(found.filter { $0.path != cache }.allSatisfy { $0.match == .name })
}

@Test func dotfilesOfAToolMacOSHasStayInTheSearchToo() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.file("bin/tidytesttool")  // macOS's own tool of that name
    try fx.file("home/.config/tidytesttool/config")

    #expect(LeftoverSearch.find("tidytesttool", home: fx.home, toolFolders: [fx.root + "/bin"], others: []).isEmpty)
    #expect(LeftoverSearch.find("helper", home: fx.home, toolFolders: [], others: []).isEmpty)  // too common: nothing
}
