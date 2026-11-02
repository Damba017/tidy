import Foundation
import Testing
@testable import TidyCore

/// The shape `brew info --cask --json=v2 --installed` gives (taken from Homebrew 7.0.9).
private let casksJSON = """
{
  "formulae": [],
  "casks": [
    {
      "token": "discord",
      "artifacts": [
        {"uninstall": [{"launchctl": "com.discord.discord.ShipIt", "quit": ["com.hnc.Discord"]}]},
        {"app": ["Discord.app"], "target": "/Applications/Discord.app"},
        {"zap": [{"trash": ["~/Library/Application Support/discord"]}]}
      ]
    },
    {"token": "renamed", "artifacts": [{"app": ["Weird Name.app", {"target": "Nice Name.app"}]}]},
    {"token": "some-font", "artifacts": [{"font": ["SomeFont.ttf"]}]}
  ]
}
"""

/// Stands in for brew: answers queries from a table and records uninstall runs, running nothing.
final class FakeBrew {
    var answers: [String: String] = [:]
    var runs: [[String]] = []
    /// Every query and run, in order: "query info --cask …", "run uninstall --cask …".
    var calls: [String] = []
    var status: Int32 = 0

    func query(_ arguments: [String]) -> String {
        calls.append("query " + arguments.joined(separator: " "))
        return answers[arguments.joined(separator: " ")] ?? ""
    }

    func run(_ arguments: [String]) -> Int32 {
        runs.append(arguments)
        calls.append("run " + arguments.joined(separator: " "))
        return status
    }
}

@Test func casksAreReadFromBrewJSON() {
    let casks = Brew.parseCasks(casksJSON)
    #expect(casks.map(\.name) == ["discord", "renamed", "some-font"])
    #expect(casks.map(\.apps) == [["Discord.app"], ["Nice Name.app", "Weird Name.app"], []])
    #expect(Brew.parseCasks("not json").isEmpty)
}

@Test func installedListsFormulaeAndCasks() {
    let brew = FakeBrew()
    brew.answers = [
        "list --formula": "cava\nfastfetch\n",
        "list --cask": "discord\n",
        "info --cask --json=v2 --installed": casksJSON,
    ]
    let packages = Brew.installed(query: brew.query)
    #expect(packages.map(\.name) == ["cava", "fastfetch", "discord"])
    #expect(packages.map(\.kind) == [.formula, .formula, .cask])
    #expect(packages[2].apps == ["Discord.app"])
    #expect(brew.runs.isEmpty)
}

@Test func aCaskAppIsOneCandidate() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try makeApp(fx, "apps/Discord.app", bundleID: "com.hnc.Discord")
    try makeApp(fx, "apps/Godot.app", bundleID: "org.godotengine.godot")
    try makeApp(fx, "apps/Pages.app", bundleID: "com.apple.iWork.Pages", appStore: true)
    let packages = [
        BrewPackage(name: "discord", kind: .cask, apps: ["Discord.app"]),
        BrewPackage(name: "fastfetch", kind: .formula, apps: []),
    ]

    let candidates = Candidates.combine(apps: AppFinder.installedApps(in: [fx.root + "/apps"]), packages: packages)

    #expect(candidates.map(\.name) == ["Discord", "fastfetch", "Godot", "Pages"])
    #expect(candidates.map(\.source) == [.brewCask, .brewFormula, .manual, .appStore])
    #expect(candidates[0].path == fx.root + "/apps/Discord.app")
    #expect(candidates[1].path == "/opt/homebrew/Cellar/fastfetch")
    #expect(candidates[0].names == ["Discord"])  // the cask token "discord" is the same name, listed once
}

@Test func uninstallArgumentsOnlyZapWhenAsked() {
    let cask = BrewPackage(name: "discord", kind: .cask, apps: [])
    let formula = BrewPackage(name: "fastfetch", kind: .formula, apps: [])
    #expect(Brew.uninstallArguments(formula, zap: false) == ["uninstall", "fastfetch"])
    #expect(Brew.uninstallArguments(cask, zap: false) == ["uninstall", "--cask", "discord"])
    #expect(Brew.uninstallArguments(cask, zap: true) == ["uninstall", "--zap", "--cask", "discord"])
}

@Test func dotfilesOfACommandLineTool() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.file("home/.config/tidytesttool/config.toml")
    try fx.folder("home/.cache/tidytesttool")
    try fx.file("home/.tidytesttoolrc")
    try fx.file("home/.config/other/x")

    let found = Leftovers.dotfiles(for: "tidytesttool", home: fx.home)

    #expect(found.map(\.path).sorted() == [
        fx.home + "/.cache/tidytesttool", fx.home + "/.config/tidytesttool", fx.home + "/.tidytesttoolrc",
    ])
    #expect(found.allSatisfy { $0.match == .name })
    #expect(Leftovers.dotfiles(for: "../etc", home: fx.home).isEmpty)
}

// MARK: - The brew flow, with fake brew and the fake Trash

private func formula(_ name: String) -> Candidate {
    Candidate(package: BrewPackage(name: name, kind: .formula, apps: []))
}

/// Runs BrewFlow with fakes for brew, the questions and the safety core. macOS's own tools: the fixture's bin/;
/// the temp and cache folders: its T/ and C/. `processes`: the executables of what's running.
private func flow(_ candidate: Candidate, in fx: Fixture, _ t: Transcript, _ brew: FakeBrew, dryRun: Bool = false,
                  others: [App] = [], processes: [String] = []) -> Bool {
    BrewFlow.run(
        candidate, dryRun: dryRun, say: t.say, ask: t.ask, home: fx.home, temp: [fx.root + "/T", fx.root + "/C"],
        toolFolders: [fx.root + "/bin"], others: others, processes: processes, query: brew.query, brew: brew.run,
        remove: { plan in
            _ = Remover.run(plan, dryRun: dryRun, say: t.say, ask: t.ask, choose: t.choose, log: fx.log, sudo: t.sudo,
                            launchctl: t.launchctl, tccutil: t.tccutil, trashItem: fx.trash)
        })
}

@Test func dryRunNeverRunsBrewAndOnlyShowsTheLeftovers() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let config = try fx.file("home/.config/tidytesttool/config")
    let brew = FakeBrew()
    let t = Transcript()
    t.answer = true

    #expect(flow(formula("tidytesttool"), in: fx, t, brew, dryRun: true))

    #expect(brew.runs.isEmpty)
    #expect(t.questions.isEmpty)
    #expect(t.lines.contains("--dry-run: would run: brew uninstall tidytesttool"))
    #expect(t.lines.contains(Output.folderLine(fx.home + "/.config")) && t.lines.contains { $0.hasSuffix("  tidytesttool") })
    #expect(Paths.exists(config))
}

@Test func libraryFoldersBrewLeftoversCantBeSearchedInAreNamed() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let cookies = try fx.folder("home/Library/Cookies")
    chmod(cookies, 0)
    defer { chmod(cookies, 0o755) }
    let t = Transcript()

    _ = flow(formula("tidytesttool"), in: fx, t, FakeBrew(), dryRun: true)

    #expect(t.lines.contains("Not searched, so leftovers in there can't be found:"))
    #expect(t.lines.contains("  \(cookies)/  (Permission denied)"))
}

@Test func sayingNoSkipsBrewAndTheLeftovers() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let config = try fx.file("home/.config/tidytesttool/config")
    let brew = FakeBrew()
    let t = Transcript()

    #expect(!flow(formula("tidytesttool"), in: fx, t, brew))

    #expect(brew.runs.isEmpty)
    #expect(t.questions == ["Uninstall tidytesttool (via brew)?"])
    #expect(Paths.exists(config))
}

@Test func yesRunsBrewThenOffersTheLeftoversForTheTrash() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let config = try fx.folder("home/.config/tidytesttool")
    let brew = FakeBrew()
    let t = Transcript()
    t.answers = [true, true]

    #expect(flow(formula("tidytesttool"), in: fx, t, brew))

    #expect(brew.runs == [["uninstall", "tidytesttool"]])
    #expect(t.questions.count == 2)
    #expect(t.questions[1].hasPrefix("Move 1 item"))
    #expect(!Paths.exists(config))
    #expect(fx.trashed() == ["tidytesttool"])
}

@Test func dotfilesOfAToolMacOSHasTooStay() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    try fx.file("bin/tidytesttool")  // macOS's own tool of that name, like /bin/zsh
    let rc = try fx.file("home/.tidytesttoolrc")
    let config = try fx.file("home/.config/tidytesttool/config")
    let brew = FakeBrew()
    let t = Transcript()
    t.answer = true

    #expect(flow(formula("tidytesttool"), in: fx, t, brew))

    #expect(brew.runs == [["uninstall", "tidytesttool"]])
    #expect(t.lines.contains {
        $0.hasPrefix("Kept ") && $0.contains(".tidytesttoolrc") && $0.contains("(\(fx.root)/bin/tidytesttool) uses them too")
    })
    #expect(t.lines.contains("No other leftovers found for tidytesttool."))
    #expect(Paths.exists(rc) && Paths.exists(config))
    #expect(fx.trashed().isEmpty)
}

@Test func aCasksLeftoversLeaveAnotherAppsFilesAlone() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let own = try fx.folder("home/Library/Caches/com.example.tidytest")
    let beta = try fx.folder("home/Library/Caches/com.example.tidytest.beta")  // another app, still installed
    let app = App(path: fx.root + "/apps/TidyTest.app", bundleID: "com.example.tidytest", bundleName: nil,
                  displayName: nil, executable: nil, source: .manual)
    let cask = Candidate(package: BrewPackage(name: "tidytestcask", kind: .cask, apps: ["TidyTest.app"]), app: app)
    let brew = FakeBrew()
    let t = Transcript()
    t.answers = [true, false, true]  // uninstall: yes, --zap: no, leftovers: yes

    let installedBeta = App(path: fx.root + "/apps/TidyTest Beta.app", bundleID: "com.example.tidytest.beta",
                            bundleName: nil, displayName: nil, executable: nil, source: .manual)
    #expect(flow(cask, in: fx, t, brew, others: [installedBeta]))

    #expect(!Paths.exists(own))
    #expect(Paths.exists(beta))
    #expect(fx.trashed() == ["com.example.tidytest"])
}

@Test func aCasksBackgroundDownloadFolderIsASureLeftover() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let own = try fx.folder("home/Library/Caches/com.apple.nsurlsessiond/Downloads/com.example.tidytest")
    let apples = try fx.folder("home/Library/Caches/com.apple.nsurlsessiond/Downloads/com.apple.bird")
    let app = App(path: fx.root + "/apps/TidyTest.app", bundleID: "com.example.tidytest", bundleName: nil,
                  displayName: nil, executable: nil, source: .manual)
    let cask = Candidate(package: BrewPackage(name: "tidytestcask", kind: .cask, apps: ["TidyTest.app"]), app: app)
    let t = Transcript()
    t.answers = [true, false, true]  // uninstall: yes, --zap: no, leftovers: yes

    #expect(flow(cask, in: fx, t, FakeBrew()))

    // On the one y/N for the sure items, not asked separately.
    #expect(t.questions.last?.hasPrefix("Move 1 item, ") == true)
    #expect(!Paths.exists(own))
    #expect(Paths.exists(apples))
    #expect(fx.trashed() == ["com.example.tidytest"])
}

@Test func tempFilesOfAToolThatStillRunsStay() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let temp = try fx.folder("T/tidytesttool")
    let cache = try fx.folder("C/tidytesttool")
    let config = try fx.folder("home/.config/tidytesttool")
    let t = Transcript()
    t.answer = true

    // A server of the formula still runs (its binary may already be gone): it uses its temp files.
    #expect(flow(formula("tidytesttool"), in: fx, t, FakeBrew(), processes: ["/opt/homebrew/Cellar/x/bin/TidyTestTool"]))

    #expect(t.lines.contains { $0.hasPrefix("Kept ") && $0.hasSuffix("tidytesttool is still running (/opt/homebrew/Cellar/x/bin/TidyTestTool).") })
    #expect(Paths.exists(temp) && Paths.exists(cache))
    #expect(!Paths.exists(config))

    // Once it's stopped, they're leftovers like the rest.
    let again = Transcript()
    again.answer = true
    #expect(flow(formula("tidytesttool"), in: fx, again, FakeBrew()))
    #expect(!Paths.exists(temp) && !Paths.exists(cache))
}

@Test func macOSOwnToolsAreFound() {
    #expect(Leftovers.macOSTool("zsh", in: Leftovers.macOSToolFolders) == "/bin/zsh")
    #expect(Leftovers.macOSTool("vim", in: Leftovers.macOSToolFolders) == "/usr/bin/vim")
    #expect(Leftovers.macOSTool("fastfetch", in: Leftovers.macOSToolFolders) == nil)
    #expect(Leftovers.macOSTool("../bin/zsh", in: Leftovers.macOSToolFolders) == nil)
}

@Test func failedBrewUninstallLeavesTheLeftoversAlone() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let config = try fx.folder("home/.config/tidytesttool")
    let brew = FakeBrew()
    brew.status = 1
    let t = Transcript()
    t.answer = true

    #expect(!flow(formula("tidytesttool"), in: fx, t, brew))

    #expect(t.questions.count == 1)
    #expect(Paths.exists(config))
}

@Test func dependentsAreWarnedAbout() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let brew = FakeBrew()
    brew.answers = ["uses --installed fftw": "cava\n"]
    let t = Transcript()

    _ = flow(formula("fftw"), in: fx, t, brew, dryRun: true)

    #expect(t.lines.contains { $0.hasPrefix("Warning: cava depends on fftw") })
}

@Test func casksAskAboutZapAndDefaultToNo() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let cask = Candidate(package: BrewPackage(name: "tidytestcask", kind: .cask, apps: []))
    let brew = FakeBrew()

    let noZap = Transcript()
    noZap.answers = [true, false]
    _ = flow(cask, in: fx, noZap, brew)
    let zap = Transcript()
    zap.answers = [true, true]
    _ = flow(cask, in: fx, zap, brew)

    #expect(noZap.questions == ["Uninstall tidytestcask (via brew)?", "Use --zap?"])
    #expect(brew.runs == [["uninstall", "--cask", "tidytestcask"], ["uninstall", "--zap", "--cask", "tidytestcask"]])
}

// MARK: - The cask's zap list, offered for the Trash when the answer to --zap is no

/// What `brew info --cask --json=v2 tidytestcask` gives, with these zap stanzas.
private func zapJSON(_ stanzas: String) -> String {
    """
    {"formulae": [], "casks": [{"token": "tidytestcask", "artifacts": [
      {"uninstall": [{"quit": "com.example.tidytest", "delete": "/Library/TidyTest/uninstall-only"}]},
      {"app": ["TidyTest.app"]},
      {"zap": [\(stanzas)]}
    ]}]}
    """
}

/// A cask with an app TidyTest.app (bundle ID com.example.tidytest).
private func tidyTestCask(_ fx: Fixture) -> Candidate {
    let app = App(path: fx.root + "/apps/TidyTest.app", bundleID: "com.example.tidytest", bundleName: nil,
                  displayName: nil, executable: nil, source: .manual)
    return Candidate(package: BrewPackage(name: "tidytestcask", kind: .cask, apps: ["TidyTest.app"]), app: app)
}

@Test func zapPathsAreReadFromBrewJSON() {
    // As Homebrew gave it for the zen cask on 2026-11-02 (shortened).
    let zen = """
        {"formulae": [], "casks": [{"token": "zen", "artifacts": [
          {"app": ["Zen.app"]},
          {"uninstall": [{"quit": "app.zen-browser.zen"}]},
          {"zap": [{"trash": ["~/Library/Application Support/Zen", "~/Library/Caches/Mozilla/updates/Applications/Zen"],
                    "rmdir": "~/Library/Caches/Mozilla"}]}
        ]}]}
        """
    #expect(Brew.zapPaths(zen) == ["~/Library/Application Support/Zen", "~/Library/Caches/Mozilla/updates/Applications/Zen"])

    // trash and delete, as a list or one string; the uninstall stanza's delete is brew's own business.
    let json = zapJSON("""
        {"trash": "~/Library/Caches/TidyTest", "delete": ["~/.tidytest"], "launchctl": "com.example.tidytest.agent"},
        {"trash": ["~/Library/Preferences/com.example.tidytest*.plist"], "pkgutil": "com.example.tidytest.pkg"}
        """)
    #expect(Brew.zapPaths(json) == ["~/Library/Caches/TidyTest", "~/.tidytest", "~/Library/Preferences/com.example.tidytest*.plist"])

    #expect(Brew.zapPaths(#"{"casks": [{"token": "x", "artifacts": [{"app": ["X.app"]}]}]}"#) == [])
    #expect(Brew.zapPaths(#"{"formulae": [], "casks": []}"#) == nil)
    #expect(Brew.zapPaths("") == nil)
}

@Test func zapPatternsAreExpandedLikeBrewDoes() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let prefs = try fx.file("home/Library/Preferences/com.example.tidytest.plist")
    let helper = try fx.file("home/Library/Preferences/com.example.tidytest.helper.plist")
    let support = try fx.folder("home/Library/Application Support/TidyTest")

    #expect(ZapList.expand("~/Library/Preferences/com.example.tidytest*.plist", home: fx.home).sorted() == [helper, prefs])
    #expect(ZapList.expand("~/Library/Application Support/{TidyTest,Gone}", home: fx.home) == [support])
    #expect(ZapList.expand("~/Library/Application Support/tidytest", home: fx.home) == [support])  // as spelled on disk
    #expect(ZapList.expand(support, home: fx.home) == [support])
    #expect(ZapList.expand("~/Library/Caches/Gone", home: fx.home).isEmpty)
    #expect(ZapList.expand("~/Library/Caches/Gone*", home: fx.home).isEmpty)
    // Never relative, someone else's home, or with .. in it.
    #expect(ZapList.expand("Library/Preferences/com.example.tidytest.plist", home: fx.home).isEmpty)
    #expect(ZapList.expand("~root/Library", home: fx.home).isEmpty)
    #expect(ZapList.expand("~/Library/../Library/Preferences/com.example.tidytest.plist", home: fx.home).isEmpty)
}

@Test func zapListItemsAreSureOnlyWhenNamedAfterTheAppInALibraryFolder() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let deep = try fx.folder("home/Library/Caches/Vendor/updates/Applications/TidyTest")  // name
    let prefs = try fx.file("home/Library/Preferences/com.example.tidytest.plist")  // bundle ID
    let shared = try fx.folder("home/Library/Application Support/Vendor")  // the maker's, maybe shared
    let crash = try fx.file("home/Library/Logs/TidyTest_2026-11-02.crash")  // only fuzzy
    let documents = try fx.folder("home/Documents/TidyTest")  // named after it, but not in a Library folder
    let dotfile = try fx.folder("home/.tidytest")
    let recents = try fx.file("home/Library/Application Support/com.apple.sharedfilelist/x/com.example.tidytest.sfl3")
    try fx.folder("home/Library/Application Support/com.apple.sharedfilelist/x/com.apple.Safari.sfl3")  // Apple's own

    let found = ZapList.leftovers(
        ["~/Library/Caches/Vendor/updates/Applications/TidyTest", "~/Library/Preferences/com.example.tidytest*",
         "~/Library/Application Support/Vendor", "~/Library/Logs/TidyTest_*", "~/Documents/TidyTest", "~/.tidytest",
         "~/Library/Caches/Gone", "~/Library/Application Support/com.apple.sharedfilelist/x/*.sfl3",
         "~/Library/Application Support/com.apple.sharedfilelist"],
        bundleID: "com.example.tidytest", names: ["TidyTest", "tidytestcask"], app: nil, home: fx.home, others: [])
    let matches = Dictionary(found.map { ($0.path, $0.match) }, uniquingKeysWith: { first, _ in first })

    #expect(matches == [deep: .name, prefs: .bundleID, shared: .zap, crash: .zap, documents: .zap, dotfile: .zap,
                        recents: .bundleID])
    #expect(Leftover(path: shared, match: .zap).checkedByDefault == false)
}

@Test func zapListItemsOfAnotherAppAreLeftOut() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let own = try fx.folder("home/Library/Caches/com.example.tidytest")
    let holder = try fx.folder("home/Library/Application Support/Vendor")
    let inside = try makeApp(fx, "home/Library/Application Support/Vendor/Other.app", bundleID: "com.example.other")
    try fx.folder("home/Library/Caches/com.example.tidytest.beta")  // an installed beta's, longer bundle ID
    try fx.folder("home/Library/Caches/Other")  // the other app's name
    let app = try makeApp(fx, "apps/TidyTest.app", bundleID: "com.example.tidytest")  // still there in a dry run
    let others = [
        App(path: inside, bundleID: "com.example.other", bundleName: nil, displayName: nil, executable: nil, source: .manual),
        App(path: fx.root + "/apps/TidyTest Beta.app", bundleID: "com.example.tidytest.beta", bundleName: nil,
            displayName: nil, executable: nil, source: .manual),
    ]

    let found = ZapList.leftovers(
        ["~/Library/Caches/com.example.tidytest*", "~/Library/Application Support/Vendor", "~/Library/Caches/Other",
         holder + "/Other.app/Contents", app],
        bundleID: "com.example.tidytest", names: ["TidyTest"], app: app, home: fx.home, others: others)

    #expect(found.map(\.path) == [own])
}

@Test func zapListItemsTheDenylistRefusesAreLeftOut() {
    // Real folders, names only: nothing is moved, the list is just built.
    let found = ZapList.leftovers(["~/Library/Caches", "~/Library", "~", "/Library/Application Support", "/System/Library/*"],
                                  bundleID: "com.example.tidytest", names: ["TidyTest"], app: nil, home: Paths.home, others: [])
    #expect(found.isEmpty)
}

@Test func withoutZapTheCasksZapListIsOfferedForTheTrash() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let deep = try fx.folder("home/Library/Caches/Vendor/updates/Applications/TidyTest")
    try fx.file("home/Library/Caches/Vendor/updates/Applications/TidyTest/.parentlock")
    let cache = try fx.folder("home/Library/Caches/com.example.tidytest")  // taydic finds this one itself too
    let fuzzy = try fx.folder("home/Library/Caches/BetterTidyTest")  // only taydic's own search, fuzzy
    let shared = try fx.folder("home/Library/Application Support/Vendor")
    let brew = FakeBrew()
    brew.answers["info --cask --json=v2 tidytestcask"] = zapJSON("""
        {"trash": ["~/Library/Caches/Vendor/updates/Applications/TidyTest", "~/Library/Caches/com.example.tidytest",
                   "~/Library/Application Support/Vendor", "~/Library/Caches/Gone"],
         "rmdir": "~/Library/Caches/Vendor"}
        """)
    let t = Transcript()
    t.answers = [true, false, true]  // uninstall: yes, --zap: no, the sure items: yes; the uncertain ones: none

    #expect(flow(tidyTestCask(fx), in: fx, t, brew))

    // Read before the uninstall, while brew still has the cask.
    #expect(brew.calls == ["query info --cask --json=v2 tidytestcask", "run uninstall --cask tidytestcask"])
    #expect(t.lines.contains { $0.hasSuffix("  TidyTest  (from the cask's zap list)") })
    #expect(t.lines.contains { $0.hasSuffix("  com.example.tidytest") })  // found by taydic itself: no note
    #expect(t.lines.contains { $0.hasPrefix("Uncertain items, asked separately (they may belong to another app too): 2 items") })
    #expect(t.lines.contains { $0.hasSuffix("  Vendor  (from the cask's zap list)") })
    #expect(t.lines.contains { $0.hasSuffix("  BetterTidyTest  (fuzzy match)") })
    #expect(t.questions[2].hasPrefix("Move 2 items, "))
    #expect(t.questions.last?.hasPrefix("Move the 2 uncertain items (") == true)
    #expect(fx.trashed().sorted() == ["TidyTest", "com.example.tidytest"])
    #expect(!Paths.exists(deep) && !Paths.exists(cache))
    #expect(Paths.exists(shared) && Paths.exists(fuzzy))
    #expect(Paths.exists(fx.home + "/Library/Caches/Vendor/updates/Applications"))  // rmdir is left out
}

@Test func withZapOrForAFormulaTheZapListIsNotRead() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let deep = try fx.folder("home/Library/Caches/Vendor/updates/Applications/TidyTest")
    let brew = FakeBrew()
    brew.answers["info --cask --json=v2 tidytestcask"] = zapJSON(#"{"trash": "~/Library/Caches/Vendor/updates/Applications/TidyTest"}"#)
    let t = Transcript()
    t.answers = [true, true]  // uninstall: yes, --zap: yes

    #expect(flow(tidyTestCask(fx), in: fx, t, brew))
    #expect(flow(formula("tidytesttool"), in: fx, Transcript(), brew, dryRun: true))

    // brew's --zap deletes it (the fake one deletes nothing); taydic doesn't offer it as well.
    #expect(brew.calls == ["run uninstall --zap --cask tidytestcask", "query uses --installed tidytesttool"])
    #expect(!t.lines.contains { $0.contains("zap list") })
    #expect(Paths.exists(deep))
}

@Test func aDryRunShowsTheZapListOrSaysItCouldntBeRead() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let deep = try fx.folder("home/Library/Caches/Vendor/updates/Applications/TidyTest")
    try fx.folder("home/Library/Caches/com.example.tidytest")
    let brew = FakeBrew()
    brew.answers["info --cask --json=v2 tidytestcask"] = zapJSON(#"{"trash": "~/Library/Caches/Vendor/updates/Applications/TidyTest"}"#)
    let t = Transcript()
    t.answer = true

    #expect(flow(tidyTestCask(fx), in: fx, t, brew, dryRun: true))

    #expect(brew.runs.isEmpty && t.questions.isEmpty)
    #expect(t.lines.contains { $0.hasSuffix("  TidyTest  (from the cask's zap list)") })
    #expect(Paths.exists(deep))

    // brew's answer can't be read: taydic says so and offers what it finds itself.
    let unread = Transcript()
    #expect(flow(tidyTestCask(fx), in: fx, unread, FakeBrew(), dryRun: true))
    #expect(unread.lines.contains("Couldn't read tidytestcask's zap list from brew, so only what taydic finds itself is offered."))
    #expect(unread.lines.contains { $0.hasSuffix("  com.example.tidytest") })
    #expect(!unread.lines.contains { $0.contains("TidyTest  (from") })
}
