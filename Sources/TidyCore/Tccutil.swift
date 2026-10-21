import Foundation

/// Resets what macOS's privacy protection (TCC) remembers about an app: access to your Downloads folder,
/// the camera, and so on. Otherwise a new install of the app silently gets the old permissions back.
public enum Tccutil {
    /// The reset for `app`, or nil: without a bundle ID (or an odd one), or when another app on this Mac
    /// has the same bundle ID (a second copy, Xcode-beta next to Xcode), whose permissions would go too.
    public static func reset(for app: App, others: [App]) -> RemovalPlan.PrivacyReset? {
        guard let id = app.bundleID, let first = id.first, first.isLetter || first.isNumber,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              !others.contains(where: { $0.bundleID?.lowercased() == id.lowercased() }) else { return nil }
        return RemovalPlan.PrivacyReset(app: app.path, name: app.name, bundleID: id)
    }

    /// `tccutil reset All <bundleID>`. tccutil asks macOS for the app by that bundle ID, and once the app is
    /// gone it says "No such bundle identifier", so it runs right before the app goes. No root needed.
    static func reset(_ bundleID: String) -> [String] {
        ["reset", "All", bundleID]
    }

    /// Runs /usr/bin/tccutil and returns its exit status, with what it said on stderr.
    public static func run(_ arguments: [String]) -> (status: Int32, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
