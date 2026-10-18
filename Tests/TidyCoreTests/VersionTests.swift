import Testing
@testable import TidyCore

@Test func versionIsSet() {
    #expect(!Tidy.version.isEmpty)
}
