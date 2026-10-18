import Foundation

/// Append-only record of every removal, one tab-separated line each:
/// `time  moved|failed  size  original path  where it went (or the error)  sudo=yes|no`.
/// Items moved with sudo have no Finder "Put Back", so this is how to find where they came from.
public struct Log: Sendable {
    public let path: String
    public static let standard = Log(path: Paths.logFile)

    public init(path: String) {
        self.path = path
    }

    func moved(_ original: String, size: Int64, to destination: String, sudo: Bool) throws {
        try append(["moved", Size.format(size), original, destination, "sudo=\(sudo ? "yes" : "no")"])
    }

    func failed(_ original: String, error: String, sudo: Bool) throws {
        try append(["failed", "-", original, error, "sudo=\(sudo ? "yes" : "no")"])
    }

    private func append(_ fields: [String]) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let line = ([formatter.string(from: Date())] + fields).joined(separator: "\t") + "\n"
        try FileManager.default.createDirectory(atPath: Paths.parent(path), withIntermediateDirectories: true)
        guard let file = fopen(path, "a") else {
            throw TidyError("can't open the log \(Paths.display(path)): \(String(cString: strerror(errno)))")
        }
        defer { fclose(file) }
        fputs(line, file)
    }
}
