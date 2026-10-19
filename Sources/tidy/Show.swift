import Foundation
import TidyCore

/// Prints one line of output, with taydic's few colours when stdout is a terminal and NO_COLOR isn't set.
func show(_ line: String) {
    print(useColor ? Output.colored(line) : line)
}

private let useColor = isatty(STDOUT_FILENO) == 1 && (ProcessInfo.processInfo.environment["NO_COLOR"] ?? "").isEmpty

/// What macOS privacy protection kept out of the list (`protected` items, and `notSearched` folders
/// taydic couldn't look in at all), and how to let taydic in. Nothing when there's nothing to say.
func showPrivacyNotes(protected: [String], notSearched: [(path: String, reason: String)] = []) {
    guard !protected.isEmpty || !notSearched.isEmpty else { return }
    show("")
    if !protected.isEmpty {
        show("Not in the list: macOS won't let taydic touch these without Full Disk Access:")
        Output.grouped(protected) { _, name in "      " + name }.forEach(show)
    }
    let privacy = notSearched.filter { $0.reason == RemovalPlan.privacyReason }
    if !notSearched.isEmpty && !protected.isEmpty && privacy.count == notSearched.count {
        show("Not searched, same reason:")
        notSearched.forEach { show(Output.folderLine($0.path)) }
    } else if !notSearched.isEmpty {
        show("Not searched, so leftovers in there aren't in the list either:")
        notSearched.forEach { show(Output.folderLine($0.path) + "  (\($0.reason))") }
    }
    if !protected.isEmpty || !privacy.isEmpty {
        show("To include them: System Settings → Privacy & Security → Full Disk Access → add your terminal app.")
    }
}
