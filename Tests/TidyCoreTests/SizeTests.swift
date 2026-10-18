import Foundation
import Testing
@testable import TidyCore

@Test func formatUsesDecimalUnits() {
    #expect(Size.format(0) == "0 B")
    #expect(Size.format(999) == "999 B")
    #expect(Size.format(1000) == "1.0 KB")
    #expect(Size.format(92_000) == "92 KB")
    #expect(Size.format(840_000) == "840 KB")
    #expect(Size.format(999_600) == "1.0 MB")
    #expect(Size.format(1_200_000) == "1.2 MB")
    #expect(Size.format(9_960_000) == "10 MB")
    #expect(Size.format(3_400_000_000) == "3.4 GB")
}

@Test func allocatedSizeCountsFolderContentsAndHardLinksOnce() throws {
    let fx = try Fixture()
    defer { fx.remove() }
    let file = try fx.file("data/big", bytes: 100_000)
    try FileManager.default.linkItem(atPath: file, toPath: fx.root + "/data/hardlink")
    try FileManager.default.createSymbolicLink(atPath: fx.root + "/data/symlink", withDestinationPath: file)

    let fileSize = Size.allocated(file)
    #expect(fileSize >= 100_000)
    let folderSize = Size.allocated(fx.root + "/data")
    #expect(folderSize >= fileSize)
    #expect(folderSize < fileSize * 2)  // the hard link isn't counted twice
}
