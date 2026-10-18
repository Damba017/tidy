// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tidy",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "TidyCore"),
        .executableTarget(name: "tidy", dependencies: ["TidyCore"]),
        .testTarget(
            name: "TidyCoreTests",
            dependencies: ["TidyCore"],
            // Command Line Tools ship the Swift Testing macro plugin in a subfolder
            // that SwiftPM doesn't search, so point the compiler at it.
            swiftSettings: [.unsafeFlags([
                "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
            ])]
        ),
    ]
)
