import Foundation
import Testing
@testable import TidyCore

@Test func pathsAreListedPerFolder() {
    let lines = Output.grouped(["/a/x", "/b/y", "/a/z", "/top"]) { _, name in "    " + name }
    #expect(lines == ["  /a/", "    x", "    z", "  /b/", "    y", "  /", "    top"])
    #expect(Output.folderLine(Paths.home + "/Library") == "  ~/Library/")
}

@Test func coloursMarkWhatHappened() {
    #expect(Output.colored("    moved   a") == "    \u{1B}[32mmoved\u{1B}[0m   a")
    #expect(Output.colored("    FAILED  a: no permission") == "    \u{1B}[31mFAILED\u{1B}[0m  a: no permission")
    #expect(Output.colored("  quit    DuckDuckGo") == "  \u{1B}[32mquit\u{1B}[0m    DuckDuckGo")
    #expect(Output.colored("  ~/Library/Caches/") == "\u{1B}[2m  ~/Library/Caches/\u{1B}[0m")
    for header in ["Move to the Trash: 4 items, 45 KB", "Found 1:", "Done: 6 items (222 MB) moved to the Trash."] {
        #expect(Output.colored(header) == "\u{1B}[1m" + header + "\u{1B}[0m")
    }
    for plain in ["Log: ~/.local/state/taydic/log", "To include them: System Settings → Full Disk Access",
                  "         0 B  name", "sudo failed: nothing was moved with sudo.", "--dry-run: nothing was changed."] {
        #expect(Output.colored(plain) == plain)
    }
}
