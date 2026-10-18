import Foundation

/// Asks `question (y/N)`. Only "y" or "yes" counts; Enter, anything else or end of input is No.
/// Answers No without reading when stdin isn't a terminal, so a yes can't be piped in.
func ask(_ question: String) -> Bool {
    print("\(question) (y/N) ", terminator: "")
    fflush(stdout)
    guard isatty(STDIN_FILENO) == 1 else {
        print("\nNot an interactive terminal: answering No.")
        return false
    }
    guard let answer = readLine() else {
        print()
        return false
    }
    let normalized = answer.trimmingCharacters(in: .whitespaces).lowercased()
    return normalized == "y" || normalized == "yes"
}
