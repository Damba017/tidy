import Foundation

/// One thing `tidy uninstall` can remove, with how it was installed. The tool decides the source,
/// never the user: a .app that belongs to a cask is one candidate, labelled Homebrew cask.
public struct Candidate: Sendable, Equatable {
    public enum Source: String, Sendable {
        case appStore = "App Store"
        case manual = "manual"
        case brewCask = "Homebrew cask"
        case brewFormula = "Homebrew formula"
    }

    public let source: Source
    public let app: App?
    public let package: BrewPackage?

    public var name: String { app?.name ?? package?.name ?? "" }
    public var path: String { app?.path ?? package.map(Brew.location) ?? "" }

    /// Every name it goes by: the app's names plus the brew package name.
    public var names: [String] {
        var seen = Set<String>()
        return ((app?.names ?? []) + [package?.name].compactMap { $0 }).filter { seen.insert($0.lowercased()).inserted }
    }

    public init(app: App) {
        source = app.source == .appStore ? .appStore : .manual
        self.app = app
        package = nil
    }

    init(package: BrewPackage, app: App? = nil) {
        source = package.kind == .cask ? .brewCask : .brewFormula
        self.app = app
        self.package = package
    }
}

public enum Candidates {
    /// Installed apps plus, when brew is there, its formulae and casks (read-only queries).
    public static func all() -> [Candidate] {
        combine(apps: AppFinder.installedApps(), packages: Brew.isInstalled ? Brew.installed() : [])
    }

    static func combine(apps: [App], packages: [BrewPackage]) -> [Candidate] {
        var result: [Candidate] = []
        var caskApps = Set<String>()
        for package in packages {
            let app = package.kind == .cask
                ? apps.first { package.apps.contains(($0.path as NSString).lastPathComponent) }
                : nil
            if let app { caskApps.insert(app.path) }
            result.append(Candidate(package: package, app: app))
        }
        result += apps.filter { !caskApps.contains($0.path) }.map(Candidate.init(app:))
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// What a path to an app bundle (e.g. one outside /Applications) stands for: the cask that owns it,
    /// or else the app itself. Nil for anything that isn't an app bundle.
    public static func app(at path: String, in candidates: [Candidate]) -> Candidate? {
        let path = Paths.normalize(path)
        guard AppFinder.isAppBundle(path), let app = AppFinder.load(path) else { return nil }
        return candidates.first { $0.app?.path == app.path } ?? Candidate(app: app)
    }

    /// Candidates that match `query`, ignoring case: exact name or bundle ID matches if there are any,
    /// otherwise every candidate with `query` somewhere in one of its names.
    public static func matches(_ query: String, in candidates: [Candidate]) -> [Candidate] {
        let query = query.lowercased()
        let exact = candidates.filter { candidate in
            candidate.names.contains { $0.lowercased() == query } || candidate.app?.bundleID?.lowercased() == query
        }
        if !exact.isEmpty { return exact }
        return candidates.filter { candidate in candidate.names.contains { $0.lowercased().contains(query) } }
    }
}
