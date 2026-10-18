import Foundation
import TidyCore

/// `tidy` without arguments: a menu that runs the same flows as the subcommands, and comes back
/// after each one until the user quits.
func runMenu(dryRun: Bool, junkOptions: JunkOptions) -> Int32 {
    guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
        print(usage)
        return 0
    }
    var status: Int32 = 0
    while true {
        Terminal.start()
        let choice = pickFromMenu(dryRun: dryRun)
        Terminal.stop()
        switch choice {
        case 1: status = runUninstall(names: [], dryRun: dryRun)
        case 2: status = runDisk(path: nil, dryRun: dryRun)
        case 3: status = runJunk(category: nil, options: junkOptions, dryRun: dryRun)
        default: return status
        }
        // Leave what the flow printed on screen until the user is done reading it.
        print("")
        print("Press Enter for the menu, or q and Enter to quit. ", terminator: "")
        fflush(stdout)
        guard let line = readLine(), line.trimmingCharacters(in: .whitespaces).lowercased() != "q" else {
            return status
        }
    }
}

/// The menu itself: 1, 2, 3 or arrows + Enter. Nil means quit.
private func pickFromMenu(dryRun: Bool) -> Int? {
    let options = [
        ("1", "Uninstall an app", "apps and Homebrew packages, with everything they left behind"),
        ("2", "Disk overview", "what takes up space, per volume and folder"),
        ("3", "Find junk", "caches & logs, dev junk, large & old files, orphans"),
        ("q", "Quit", ""),
    ]
    var cursor = 0
    while true {
        let (height, width) = Terminal.size()
        let w = max(20, width - 1)
        var lines = [fit("tidy \(Tidy.version)" + (dryRun ? "   [dry-run]" : ""), w), ""]
        for (index, option) in options.enumerated() {
            let line = fit("  \(option.0)  \(fit(option.1, 20))  \(option.2)", w)
            lines.append(index == cursor ? reverseVideo + line + resetStyle : line)
        }
        while lines.count < height - 1 { lines.append("") }
        lines.append(fit("↑↓ move · enter choose · 1 2 3 · q quit", w))
        Terminal.draw(lines)

        switch Terminal.waitForKey() {
        case .up: cursor = max(0, cursor - 1)
        case .down: cursor = min(options.count - 1, cursor + 1)
        case .enter: return cursor < 3 ? cursor + 1 : nil
        case .char("1"): return 1
        case .char("2"): return 2
        case .char("3"): return 3
        case .char("q"), .escape, .interrupt: return nil
        default: break
        }
    }
}
