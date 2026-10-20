import Foundation
import TidyCore

let usage = """
taydic \(Tidy.version) - uninstall apps, browse disk usage, find junk

Usage:
  taydic                       Main menu
  taydic uninstall [name...]   Uninstall apps/brew packages and their leftovers
  taydic leftovers name        Find what an app you already removed left behind
  taydic disk [path]           Disk-usage browser
  taydic junk [category]       Find junk: orphans | caches | large | dev
  taydic --help, -h            Show this help
  taydic --version             Show version

Options:
  --dry-run                    Show exactly what would happen. Never touches anything.
  --min-size SIZE              junk large: files at least this big (default 1GB; e.g. 500MB, 2GB)
  --older-than DAYS            junk large: also files from 100MB unused this long (default 180)

Every destructive action asks (y/N) first. There is no --yes.
"""

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("taydic: \(message)\n".utf8))
    exit(code)
}

var dryRun = false
var junkOptions = JunkOptions()
var positional: [String] = []

var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let arg = arguments.removeFirst()
    switch arg {
    case "--min-size":
        guard let value = arguments.first, let size = Size.parse(value), size > 0 else {
            fail("--min-size needs a size, e.g. --min-size 500MB.")
        }
        arguments.removeFirst()
        junkOptions.minSize = size
    case "--older-than":
        guard let value = arguments.first, let days = Int(value), days > 0 else {
            fail("--older-than needs a number of days, e.g. --older-than 365.")
        }
        arguments.removeFirst()
        junkOptions.olderThanDays = days
    case "--help", "-h":
        print(usage)
        exit(0)
    case "--version":
        print("taydic \(Tidy.version)")
        exit(0)
    case "--dry-run":
        dryRun = true
    case "--yes", "-y":
        fail("--yes is not supported: every destructive action needs an interactive (y/N).")
    case _ where arg.hasPrefix("-"):
        fail("unknown option '\(arg)'. See 'taydic --help'.")
    default:
        positional.append(arg)
    }
}

let command = positional.first
let rest = Array(positional.dropFirst())

switch command {
case nil:
    exit(runMenu(dryRun: dryRun, junkOptions: junkOptions))
case "uninstall":
    exit(runUninstall(names: rest, dryRun: dryRun))
case "leftovers":
    if rest.count != 1 { fail("'leftovers' needs one name, e.g. taydic leftovers discord (quotes around a name with spaces).") }
    exit(runLeftovers(name: rest[0], dryRun: dryRun))
case "disk":
    if rest.count > 1 { fail("'disk' takes at most one path.") }
    exit(runDisk(path: rest.first, dryRun: dryRun))
case "junk":
    if rest.count > 1 { fail("'junk' takes at most one category.") }
    let category = rest.first.map { JunkCategory(rawValue: $0) }
    if category == .some(nil) {
        fail("unknown junk category '\(rest[0])'. Use: orphans | caches | large | dev.")
    }
    exit(runJunk(category: category ?? nil, options: junkOptions, dryRun: dryRun))
case "_plan":
    // Dev aid, not in --help: shows what taydic would do with these paths. Always a dry run.
    if rest.isEmpty { fail("'_plan' needs one or more paths.") }
    _ = Remover.run(RemovalPlan(paths: rest), dryRun: true, say: show, ask: { _ in false }, choose: { _ in .none })
    exit(0)
default:
    fail("unknown command '\(command!)'. See 'taydic --help'.")
}
