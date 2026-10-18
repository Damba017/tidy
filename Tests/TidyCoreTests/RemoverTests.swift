import Foundation
import Testing
@testable import TidyCore

/// Records everything the remover says and asks, in order.
final class Transcript {
    var lines: [String] = []
    var questions: [String] = []
    var sudoCalls: [[String]] = []
    var answer = false
    var sudoStatus: Int32 = 0

    func say(_ line: String) { lines.append(line) }

    func ask(_ question: String) -> Bool {
        questions.append(question)
        lines.append("? " + question)
        return answer
    }

    /// Stands in for sudo: records the command and runs nothing.
    func sudo(_ arguments: [String]) -> Int32 {
        sudoCalls.append(arguments)
        return sudoStatus
    }
}

/// Runs the remover inside a fixture: fake Trash, fake sudo, log in the fixture.
func run(_ plan: RemovalPlan, in fx: Fixture, _ t: Transcript, dryRun: Bool = false) -> RemovalResult {
    Remover.run(plan, dryRun: dryRun, say: t.say, ask: t.ask, log: fx.log, sudo: t.sudo, trashItem: fx.trash)
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
    // The fake sudo moved nothing, so both must be reported as failed, not as moved.
    #expect(result.moved == 0)
    #expect(result.failed == 2)
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
        RemovalPlan(paths: [a, folder], home: fx.home), dryRun: false, say: t.say, ask: t.ask,
        log: fx.log, sudo: t.sudo, trashItem: Trash.system)

    #expect(result.moved == 2)
    #expect(!Paths.exists(a) && !Paths.exists(folder))
    let lines = try String(contentsOfFile: fx.log.path, encoding: .utf8).split(separator: "\n")
    #expect(lines.allSatisfy { $0.contains("\t\(Paths.home)/.Trash/tidy-test-") })
}
