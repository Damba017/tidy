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
    var status: Int32 = 0

    func query(_ arguments: [String]) -> String { answers[arguments.joined(separator: " ")] ?? "" }

    func run(_ arguments: [String]) -> Int32 {
        runs.append(arguments)
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

/// Runs BrewFlow with fakes for brew, the questions and the safety core. macOS's own tools: the fixture's bin/.
private func flow(_ candidate: Candidate, in fx: Fixture, _ t: Transcript, _ brew: FakeBrew, dryRun: Bool = false,
                  others: [String] = []) -> Bool {
    BrewFlow.run(
        candidate, dryRun: dryRun, say: t.say, ask: t.ask, home: fx.home, toolFolders: [fx.root + "/bin"],
        others: others, query: brew.query, brew: brew.run,
        remove: { plan in
            _ = Remover.run(plan, dryRun: dryRun, say: t.say, ask: t.ask, choose: t.choose, log: fx.log, sudo: t.sudo,
                            launchctl: t.launchctl, trashItem: fx.trash)
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
    #expect(t.lines.contains { $0.contains(config) || $0.contains("/.config/tidytesttool") })
    #expect(Paths.exists(config))
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

    #expect(flow(cask, in: fx, t, brew, others: ["com.example.tidytest.beta"]))

    #expect(!Paths.exists(own))
    #expect(Paths.exists(beta))
    #expect(fx.trashed() == ["com.example.tidytest"])
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
