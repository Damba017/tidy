import Foundation
import TidyCore

/// Asks `question (y/N)`. Only "y" or "yes" counts; Enter, anything else or end of input is No.
/// Answers No without reading when stdin isn't a terminal, so a yes can't be piped in.
func ask(_ question: String) -> Bool {
    readAnswer(question + " (y/N)") == "y"
}

/// Asks about the doubtful items: y = all, o = one by one, anything else (Enter) = none.
func choose(_ question: String) -> Remover.Choice {
    switch readAnswer(question + "  y = all · o = one by one · N = none (Enter)") {
    case "y": .all
    case "o": .oneByOne
    default: .none
    }
}

/// The trimmed, lowercased first letter of the answer ("yes" → "y"), or "" for Enter, end of input
/// or no terminal.
private func readAnswer(_ prompt: String) -> String {
    print(prompt + " ", terminator: "")
    fflush(stdout)
    guard isatty(STDIN_FILENO) == 1 else {
        print("\nNot an interactive terminal: answering No.")
        return ""
    }
    guard let line = readLine() else {
        print()
        return ""
    }
    let answer = line.trimmingCharacters(in: .whitespaces).lowercased()
    switch answer {
    case "y", "yes": return "y"
    case "o": return "o"
    default: return ""
    }
}
