import Foundation
import Testing
@testable import TidyCore

/// Records everything the remover says and asks, in order.
final class Transcript {
    var lines: [String] = []
    var questions: [String] = []
    var sudoCalls: [[String]] = []
    var launchctlCalls: [[String]] = []
    /// launchctl and sudo calls in the order they happened.
    var events: [String] = []
    var answer = false
    /// Answers per question, in order; once used up, `answer` is given.
    var answers: [Bool] = []
    /// Answers to the all / one by one / none question, in order; once used up, `.none`.
    var choices: [Remover.Choice] = []
    var sudoStatus: Int32 = 0

    func say(_ line: String) { lines.append(line) }

    func ask(_ question: String) -> Bool {
        questions.append(question)
        lines.append("? " + question)
        return answers.isEmpty ? answer : answers.removeFirst()
    }

    func choose(_ question: String) -> Remover.Choice {
        questions.append(question)
        lines.append("?? " + question)
        return choices.isEmpty ? .none : choices.removeFirst()
    }

    /// Stands in for sudo: records the command and runs nothing.
    func sudo(_ arguments: [String]) -> Int32 {
        sudoCalls.append(arguments)
        events.append("sudo " + arguments.joined(separator: " "))
        return sudoStatus
    }

    /// Stands in for launchctl: records the command and runs nothing.
    func launchctl(_ arguments: [String]) -> Int32 {
        launchctlCalls.append(arguments)
        events.append("launchctl " + arguments.joined(separator: " "))
        return 0
    }
}

/// Runs the remover inside a fixture: fake Trash, fake sudo, fake launchctl, log in the fixture.
func run(_ plan: RemovalPlan, in fx: Fixture, _ t: Transcript, dryRun: Bool = false) -> RemovalResult {
    Remover.run(
        plan, dryRun: dryRun, say: t.say, ask: t.ask, choose: t.choose, log: fx.log, sudo: t.sudo, launchctl: t.launchctl,
        trashItem: { path in
            t.events.append("trash " + path)
            return try fx.trash(path)
        })
}

@Test func planSortsPathsByWhatWillHappen() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let file = try fx.file("home/.config/thing/config.toml", bytes: 5000)
    let folder = fx.home + "/.config/thing"
    try fx.folder("home/Library/Keychains")
    try FileManager.default.createSymbolicLink(atPath: fx.home + "/link", withDestinationPath: file)

    let plan = RemovalPlan(
        paths: [folder, folder + "/", file, fx.home + "/link", fx.home + "/nope", fx.home + "/Library/Keychains"],
        home: fx.home)

    #expect(plan.items.map(\.path) == [folder, fx.home + "/link", fx.home + "/nope", fx.home + "/Library/Keychains"])
    #expect(plan.items.map(\.status) == [.trash, .trash, .missing, .blocked("keychains")])
    #expect(plan.items[0].size >= 5000)
    #expect(plan.items[1].size < 5000)  // the symlink itself, not its target
}

@Test func lockedItemsAreProtectedNotSudo() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let file = try fx.file("home/locked.txt")
    chflags(file, UInt32(UF_IMMUTABLE))
    defer { chflags(file, 0) }
    let readOnlyFolder = try fx.folder("home/readonly")
    try fx.file("home/readonly/inside.txt")
    chmod(readOnlyFolder, 0o555)
    defer { chmod(readOnlyFolder, 0o755) }

    let plan = RemovalPlan(paths: [file, readOnlyFolder, readOnlyFolder + "/inside.txt"], home: fx.home)

    #expect(plan.items.map(\.status) == [.blocked("locked"), .sudo])  // EPERM: nobody; EACCES: root
}

@Test func renderShowsEveryPathWithWhatHappensToIt() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let file = try fx.file("home/a.txt", bytes: 2000)
    try fx.folder("home/Library/Keychains")
    let plan = RemovalPlan(paths: [file, fx.home + "/Library/Keychains", fx.home + "/gone"], home: fx.home)
    let text = plan.render().joined(separator: "\n")

    #expect(text.contains("Move to the Trash: 1 item"))
    #expect(text.contains(file))
    #expect(text.contains("Protected, will not be touched: 1 item"))
    #expect(text.contains(fx.home + "/Library/Keychains  (keychains)"))
    #expect(text.contains("Not found, skipped: 1 item"))
    #expect(text.contains(fx.home + "/gone"))
}

@Test func dryRunShowsThePlanAndChangesNothing() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let file = try fx.file("home/a.txt")
    let t = Transcript()
    t.answer = true

    let result = run(RemovalPlan(paths: [file], home: fx.home), in: fx, t, dryRun: true)

    #expect(result.moved == 0)
    #expect(t.questions.isEmpty)
    #expect(t.sudoCalls.isEmpty)
    #expect(t.lines.contains { $0.contains(file) })
    #expect(t.lines.last == "--dry-run: nothing was changed.")
    #expect(Paths.exists(file))
    #expect(fx.trashed().isEmpty)
    #expect(!Paths.exists(fx.log.path))
}

@Test func answeringNoChangesNothing() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let a = try fx.file("home/a.txt")
    let b = try fx.file("home/b.txt")
    let t = Transcript()

    let result = run(RemovalPlan(paths: [a, b], home: fx.home), in: fx, t)

    #expect(result.moved == 0)
    #expect(t.questions.count == 1)
    #expect(t.questions[0].hasPrefix("Move 2 items"))
    #expect(Paths.exists(a) && Paths.exists(b))
    #expect(fx.trashed().isEmpty)
    #expect(!Paths.exists(fx.log.path))
}

@Test func thePlanIsAlwaysShownBeforeTheQuestion() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let file = try fx.file("home/a.txt")
    let t = Transcript()

    _ = run(RemovalPlan(paths: [file], home: fx.home), in: fx, t)

    let shown = try #require(t.lines.firstIndex { $0.contains(file) })
    let asked = try #require(t.lines.firstIndex { $0.hasPrefix("? ") })
    #expect(shown < asked)
}

@Test func answeringYesMovesEverythingAndLogsIt() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let a = try fx.file("home/a.txt")
    let folder = fx.home + "/stuff"
    try fx.file("home/stuff/b.txt")
    let t = Transcript()
    t.answer = true

    let result = run(RemovalPlan(paths: [a, folder], home: fx.home), in: fx, t)

    #expect(result.moved == 2)
    #expect(result.failed == 0)
    #expect(t.sudoCalls.isEmpty)
    #expect(!Paths.exists(a) && !Paths.exists(folder))
    #expect(fx.trashed().sorted() == ["a.txt", "stuff"])
    let lines = try String(contentsOfFile: fx.log.path, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines.allSatisfy { $0.contains("\tmoved\t") && $0.hasSuffix("\tsudo=no") })
    #expect(lines[0].contains("\t\(a)\t\(fx.trashFolder)/a.txt\t"))
}

@Test func oddCharactersInAPathKeepTheLogAtOneLinePerItem() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let odd = try fx.file("home/tab\there\nnewline\\backslash")
    let t = Transcript()
    t.answer = true

    let result = run(RemovalPlan(paths: [odd], home: fx.home), in: fx, t)

    #expect(result.moved == 1)
    let text = try String(contentsOfFile: fx.log.path, encoding: .utf8)
    #expect(text.split(separator: "\n").count == 1)
    #expect(text.split(separator: "\t").count == 6)  // time, moved, size, original, destination, sudo
    #expect(text.contains("/tab\\there\\nnewline\\\\backslash\t"))
}

@Test func trashRefusesProtectedPathsEvenIfThePlanSaysOtherwise() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let keychains = try fx.folder("home/Library/Keychains")
    let t = Transcript()
    t.answer = true

    let result = run(RemovalPlan(items: [.init(path: keychains, size: 10, status: .trash)], home: fx.home), in: fx, t)

    #expect(result.moved == 0)
    #expect(result.failed == 1)
    #expect(Paths.exists(keychains))
    #expect(fx.trashed().isEmpty)
}

@Test func sudoBatchAsksOnceThenMovesEachItemWithoutPrompting() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let a = try fx.file("home/A.app/x")
    let b = try fx.file("home/b.plist")
    try fx.folder("home/.Trash")
    let items = [a, b].map { RemovalPlan.Item(path: $0, size: 10, status: .sudo) }
    let t = Transcript()
    t.answer = true

    let result = run(RemovalPlan(items: items, home: fx.home), in: fx, t)

    #expect(t.questions == ["These 2 items need administrator rights (sudo). Continue?"])
    #expect(t.sudoCalls == [
        ["-v"],
        ["-n", "/bin/mv", "-n", "--", a, fx.home + "/.Trash/x"],
        ["-n", "/bin/mv", "-n", "--", b, fx.home + "/.Trash/b.plist"],
    ])
    // The fake sudo moved nothing, so both must be reported as failed, not as moved. Exit 0 with the item
    // still there is what mv -n does when the name is taken.
    #expect(result.moved == 0)
    #expect(result.failed == 2)
    #expect(t.lines.filter { $0.contains("not moved") && $0.contains("was taken") }.count == 2)
}

@Test func sudoStopsWhenTheTrashCantBeChecked() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let daemon = try fx.file("home/Library/LaunchDaemons/com.example.daemon.plist")
    let other = try fx.file("home/b.plist")
    let trash = try fx.folder("home/.Trash")
    chmod(trash, 0)  // like privacy protection: tidy can't see which names are taken
    defer { chmod(trash, 0o755) }
    let items = [daemon, other].map { RemovalPlan.Item(path: $0, size: 10, status: .sudo) }
    let t = Transcript()
    t.answer = true

    let result = run(RemovalPlan(items: items, home: fx.home), in: fx, t)

    #expect(t.events == ["sudo -v"])  // no launchd job stopped, nothing moved
    #expect(result.failed == 2)
    #expect(t.lines.contains { $0.contains("can't look into") && $0.hasSuffix("nothing more is moved with sudo.") })
    #expect(Paths.exists(daemon) && Paths.exists(other))
}

@Test func sudoIsNotUsedWhenThePasswordCheckFails() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let a = try fx.file("home/a.plist")
    let t = Transcript()
    t.answer = true
    t.sudoStatus = 1

    let result = run(RemovalPlan(items: [.init(path: a, size: 10, status: .sudo)], home: fx.home), in: fx, t)

    #expect(t.sudoCalls == [["-v"]])
    #expect(result.failed == 1)
    #expect(Paths.exists(a))
}

@Test func sudoRefusesProtectedPathsEvenIfThePlanSaysOtherwise() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let keychains = try fx.folder("home/Library/Keychains")
    let t = Transcript()
    t.answer = true

    let result = run(RemovalPlan(items: [.init(path: keychains, size: 10, status: .sudo)], home: fx.home), in: fx, t)

    #expect(t.sudoCalls == [["-v"]])
    #expect(result.failed == 1)
    #expect(Paths.exists(keychains))
}

@Test func fuzzyMatchesGetTheirOwnBlockAndQuestion() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let sure = try fx.file("home/Library/Caches/com.example.app")
    let fuzzy = try fx.file("home/Library/Application Support/My Example Project")
    let t = Transcript()
    t.answers = [true]  // yes to the sure match; the fuzzy question gets the default: none

    let plan = RemovalPlan(paths: [sure, fuzzy], doubtful: .fuzzy([fuzzy]), home: fx.home)
    let result = run(plan, in: fx, t)

    let text = plan.render().joined(separator: "\n")
    #expect(text.contains("Move to the Trash: 1 item"))
    #expect(text.contains("Fuzzy matches, asked separately (only the name looks alike): 1 item"))
    #expect(t.questions.count == 2)
    #expect(t.questions[0].hasPrefix("Move 1 item"))
    #expect(t.questions[1].hasPrefix("Move 1 fuzzy match"))
    #expect(result.moved == 1)
    #expect(!Paths.exists(sure))
    #expect(Paths.exists(fuzzy))
}

@Test func oneYesTakesAllFuzzyMatches() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let sure = try fx.file("home/sure")
    let fuzzyA = try fx.file("home/fuzzy-a")
    let fuzzyB = try fx.file("home/fuzzy-b")
    let t = Transcript()
    t.answers = [false]  // no to the sure match
    t.choices = [.all]   // y: all fuzzy ones

    let plan = RemovalPlan(paths: [sure, fuzzyA, fuzzyB], doubtful: .fuzzy([fuzzyA, fuzzyB]), home: fx.home)
    let result = run(plan, in: fx, t)

    #expect(t.questions[1].hasPrefix("Move all 2 fuzzy matches"))
    #expect(result.moved == 2)
    #expect(Paths.exists(sure))
    #expect(!Paths.exists(fuzzyA) && !Paths.exists(fuzzyB))
}

@Test func oneByOneThenNoGoesBackToTheQuestionForTheRest() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let a = try fx.file("home/orphan-a")
    let b = try fx.file("home/orphan-b")
    let c = try fx.file("home/orphan-c")
    let t = Transcript()
    t.choices = [.oneByOne, .oneByOne]
    t.answers = [true, false, true]  // a: yes, b: no (back to the question), then c: yes

    let notes = [a: "high confidence", b: "low confidence", c: "high confidence"]
    let result = run(RemovalPlan(paths: [a, b, c], doubtful: .orphans(notes), home: fx.home), in: fx, t)

    #expect(t.questions.count == 5)
    #expect(t.questions[0].hasPrefix("Move all 3 orphans"))
    #expect(t.questions[1].contains("orphan-a") && t.questions[1].contains("high confidence"))
    #expect(t.questions[2].contains("orphan-b") && t.questions[2].contains("low confidence"))
    #expect(t.questions[3].hasPrefix("Move the remaining 1 orphan"))
    #expect(t.questions[4].contains("orphan-c"))
    #expect(result.moved == 2)
    #expect(!Paths.exists(a) && Paths.exists(b) && !Paths.exists(c))
}

@Test func oneByOneThenNoneKeepsTheRest() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let a = try fx.file("home/orphan-a")
    let b = try fx.file("home/orphan-b")
    let c = try fx.file("home/orphan-c")
    let t = Transcript()
    t.choices = [.oneByOne, .none]
    t.answers = [true, false]  // a: yes, b: no → back to the question → Enter: none of the rest

    let result = run(RemovalPlan(paths: [a, b, c], doubtful: .orphans([a: "high", b: "high", c: "high"]),
                                 home: fx.home), in: fx, t)

    #expect(t.questions.count == 4)
    #expect(result.moved == 1)
    #expect(!Paths.exists(a) && Paths.exists(b) && Paths.exists(c))
    #expect(t.lines.contains("Kept 1 orphan."))
}

@Test func orphanNotesShowInThePlan() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let a = try fx.file("home/Library/Preferences/com.gone.app.plist")
    let text = RemovalPlan(paths: [a], doubtful: .orphans([a: "high confidence"]), home: fx.home).render()
        .joined(separator: "\n")
    #expect(text.contains("Orphans, asked separately (no installed app claims them): 1 item"))
    #expect(text.contains("com.gone.app.plist  (high confidence)"))
}

@Test func fuzzyMatchesNeedingSudoOnlyReachSudoWhenApproved() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let path = try fx.file("home/root-owned-lookalike")
    try fx.folder("home/.Trash")
    let item = RemovalPlan.Item(path: path, size: 10, status: .sudo, isDoubtful: true)

    let no = Transcript()
    _ = run(RemovalPlan(items: [item], home: fx.home), in: fx, no)
    #expect(no.questions.count == 1)  // only the fuzzy question
    #expect(no.sudoCalls.isEmpty)

    let yes = Transcript()
    yes.choices = [.all]
    yes.answers = [true]
    _ = run(RemovalPlan(items: [item], home: fx.home), in: fx, yes)
    #expect(yes.questions.count == 2)
    #expect(yes.questions[1].contains("administrator rights"))
    #expect(yes.sudoCalls.first == ["-v"])
}

@Test func dryRunShowsTheFuzzyBlockWithoutAsking() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let fuzzy = try fx.file("home/lookalike")
    let t = Transcript()

    _ = run(RemovalPlan(paths: [fuzzy], doubtful: .fuzzy([fuzzy]), home: fx.home), in: fx, t, dryRun: true)

    #expect(t.questions.isEmpty)
    #expect(t.lines.contains { $0.hasPrefix("Fuzzy matches, asked separately") })
    #expect(Paths.exists(fuzzy))
}

@Test func launchAgentIsStoppedBeforeItsPlistMoves() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let plist = try fx.file("home/Library/LaunchAgents/com.example.agent.plist")
    let t = Transcript()
    t.answer = true

    let plan = RemovalPlan(paths: [plist], home: fx.home)
    #expect(plan.render().contains { $0.contains("(stops its launchd job first)") })
    let result = run(plan, in: fx, t)

    #expect(result.moved == 1)
    #expect(t.events == ["launchctl bootout gui/\(getuid()) \(plist)", "trash \(plist)"])
}

@Test func launchDaemonIsStoppedWithSudoBeforeItsPlistMoves() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let plist = try fx.file("home/Library/LaunchDaemons/com.example.daemon.plist")
    try fx.folder("home/.Trash")
    let t = Transcript()
    t.answer = true

    _ = run(RemovalPlan(items: [.init(path: plist, size: 10, status: .sudo)], home: fx.home), in: fx, t)

    #expect(t.events == [
        "sudo -v",
        "sudo -n /bin/launchctl bootout system \(plist)",
        "sudo -n /bin/mv -n -- \(plist) \(fx.home)/.Trash/com.example.daemon.plist",
    ])
    #expect(t.launchctlCalls.isEmpty)
}

@Test func nothingIsStoppedInADryRunOrWhenTheAnswerIsNo() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let plist = try fx.file("home/Library/LaunchAgents/com.example.agent.plist")
    let t = Transcript()

    _ = run(RemovalPlan(paths: [plist], home: fx.home), in: fx, t, dryRun: true)
    _ = run(RemovalPlan(paths: [plist], home: fx.home), in: fx, t)

    #expect(t.events.isEmpty)
    #expect(Paths.exists(plist))
}

@Test func protectedPlistsAreNeverStopped() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let plist = try fx.file("home/.Trash/LaunchAgents/com.example.agent.plist")  // protected: already in the Trash
    let t = Transcript()
    t.answer = true

    let result = run(RemovalPlan(items: [.init(path: plist, size: 10, status: .trash)], home: fx.home), in: fx, t)

    #expect(t.events.isEmpty)
    #expect(result.failed == 1)
    #expect(Paths.exists(plist))
}

/// The only test that uses the real Trash: moves two tidy-test-* fixtures into ~/.Trash.
/// Runs only with TIDY_TRASH_TESTS=1.
@Test(.enabled(if: ProcessInfo.processInfo.environment["TIDY_TRASH_TESTS"] == "1"))
func realTrashMovesFixturesAndLogsThem() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let a = try fx.file("home/tidy-test-a.txt")
    let folder = fx.home + "/tidy-test-folder"
    try fx.file("home/tidy-test-folder/b.txt")
    let t = Transcript()
    t.answer = true

    let result = Remover.run(
        RemovalPlan(paths: [a, folder], home: fx.home), dryRun: false, say: t.say, ask: t.ask, choose: t.choose,
        log: fx.log, sudo: t.sudo, launchctl: t.launchctl, trashItem: Trash.system)

    #expect(result.moved == 2)
    #expect(!Paths.exists(a) && !Paths.exists(folder))
    let lines = try String(contentsOfFile: fx.log.path, encoding: .utf8).split(separator: "\n")
    #expect(lines.allSatisfy { $0.contains("\t\(Paths.home)/.Trash/tidy-test-") })
}

/// Uses the real Trash too: moves one symlink (to a fixture folder) into ~/.Trash. The link must go,
/// what it points to must stay. Runs only with TIDY_TRASH_TESTS=1.
@Test(.enabled(if: ProcessInfo.processInfo.environment["TIDY_TRASH_TESTS"] == "1"))
func realTrashMovesASymlinkNotWhatItPointsTo() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let target = try fx.folder("home/tidy-test-target")
    try fx.file("home/tidy-test-target/keep.txt")
    let link = fx.home + "/tidy-test-link"
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

    let destination = try Trash.move(link, home: fx.home, using: Trash.system)

    var st = stat()
    #expect(!Paths.exists(link))
    #expect(Paths.exists(target + "/keep.txt"))
    #expect(destination.hasPrefix(Paths.home + "/.Trash/tidy-test-link"))
    #expect(lstat(destination, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK)
}
