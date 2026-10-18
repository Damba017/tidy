import Foundation
import TidyCore

let usage = """
tidy \(Tidy.version) - uninstall apps, browse disk usage, find junk

Usage:
  tidy                       Main menu
  tidy uninstall [name...]   Uninstall apps/brew packages and their leftovers
  tidy disk [path]           Disk-usage browser
  tidy junk [category]       Find junk: orphans | caches | large | dev
  tidy --help, -h            Show this help
  tidy --version             Show version

Options:
  --dry-run                  Show exactly what would happen. Never touches anything.

Every destructive action asks (y/N) first. There is no --yes.
"""

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("tidy: \(message)\n".utf8))
    exit(code)
}

var dryRun = false
var positional: [String] = []

for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "--help", "-h":
        print(usage)
        exit(0)
    case "--version":
        print("tidy \(Tidy.version)")
        exit(0)
    case "--dry-run":
        dryRun = true
    case "--yes", "-y":
        fail("--yes is not supported: every destructive action needs an interactive (y/N).")
    case _ where arg.hasPrefix("-"):
        fail("unknown option '\(arg)'. See 'tidy --help'.")
    default:
        positional.append(arg)
    }
}

let command = positional.first
let rest = Array(positional.dropFirst())

switch command {
case nil:
    fail("main menu is not implemented yet.", code: 1)
case "uninstall":
    fail("'uninstall' is not implemented yet.", code: 1)
case "disk":
    if rest.count > 1 { fail("'disk' takes at most one path.") }
    fail("'disk' is not implemented yet.", code: 1)
case "junk":
    if rest.count > 1 { fail("'junk' takes at most one category.") }
    if let category = rest.first, !["orphans", "caches", "large", "dev"].contains(category) {
        fail("unknown junk category '\(category)'. Use: orphans | caches | large | dev.")
    }
    fail("'junk' is not implemented yet.", code: 1)
default:
    fail("unknown command '\(command!)'. See 'tidy --help'.")
}
