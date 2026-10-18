import Foundation

public enum Sudo {
    /// Runs `/usr/bin/sudo` with `arguments` in the user's terminal, so it can ask for the password.
    /// Returns sudo's exit status, or -1 if it couldn't be started.
    public static func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = arguments
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Moves one root-owned item into the Trash. sudo's `-n` never prompts (the password was
    /// asked once up front with `sudo -v`); mv's `-n` never overwrites.
    static func moveCommand(from source: String, to destination: String) -> [String] {
        ["-n", "/bin/mv", "-n", "--", source, destination]
    }
}
