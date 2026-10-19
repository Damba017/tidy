import Foundation

public struct BrewPackage: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case formula, cask
    }

    public let name: String
    public let kind: Kind
    /// Casks only: the .app bundles it installs, by folder name (e.g. "Discord.app").
    public let apps: [String]
}

/// Read-only Homebrew queries, plus running `brew uninstall` once the user said yes.
public enum Brew {
    public static let executable = "/opt/homebrew/bin/brew"

    public static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: executable)
    }

    public static func installed() -> [BrewPackage] {
        installed(query: query)
    }

    static func installed(query: ([String]) -> String) -> [BrewPackage] {
        let formulae = lines(query(["list", "--formula"])).map { BrewPackage(name: $0, kind: .formula, apps: []) }
        let caskApps = Dictionary(parseCasks(query(["info", "--cask", "--json=v2", "--installed"])).map { ($0.name, $0) },
                                  uniquingKeysWith: { first, _ in first })
        let casks = lines(query(["list", "--cask"])).map { caskApps[$0] ?? BrewPackage(name: $0, kind: .cask, apps: []) }
        return formulae + casks
    }

    /// Casks and their .app artifacts from `brew info --cask --json=v2`.
    static func parseCasks(_ json: String) -> [BrewPackage] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else { return [] }
        return casks.compactMap { cask in
            guard let token = cask["token"] as? String else { return nil }
            var apps: [String] = []
            for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
                guard let entries = artifact["app"] as? [Any] else { continue }
                // {"app": ["Discord.app"], "target": "/Applications/Discord.app"}: the target wins.
                if let target = artifact["target"] as? String {
                    apps.append((target as NSString).lastPathComponent)
                    continue
                }
                for entry in entries {
                    if let name = entry as? String { apps.append((name as NSString).lastPathComponent) }
                    if let options = entry as? [String: Any], let target = options["target"] as? String {
                        apps.append((target as NSString).lastPathComponent)
                    }
                }
            }
            return BrewPackage(name: token, kind: .cask, apps: Array(Set(apps)).sorted())
        }
    }

    /// Where brew keeps the package itself.
    public static func location(of package: BrewPackage) -> String {
        "/opt/homebrew/" + (package.kind == .formula ? "Cellar/" : "Caskroom/") + package.name
    }

    /// `brew uninstall` arguments; casks get `--cask`, and `--zap` only when asked for.
    static func uninstallArguments(_ package: BrewPackage, zap: Bool) -> [String] {
        ["uninstall"] + (zap ? ["--zap"] : []) + (package.kind == .cask ? ["--cask"] : []) + [package.name]
    }

    /// Runs a read-only brew query and returns what it printed. No auto-update.
    static func query(_ arguments: [String]) -> String {
        let process = brewProcess(arguments)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs brew in the user's terminal (its output shows, and it can ask for a password) and returns
    /// the exit status. No auto-update.
    public static func run(_ arguments: [String]) -> Int32 {
        Spawn.run(executable, arguments, environment: noAutoUpdate)
    }

    private static let noAutoUpdate = ["HOMEBREW_NO_AUTO_UPDATE": "1"]

    private static func brewProcess(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(noAutoUpdate) { $1 }
        return process
    }

    static func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
