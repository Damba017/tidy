import Foundation
import Testing
@testable import TidyCore

// sudo and brew uninstall run through Spawn. These only run /bin/sh.

@Test func spawnedProgramsStayInTaydicsProcessGroup() {
    // Only the terminal's own process group may ask there (sudo's password); a program in a group of
    // its own is stopped by macOS as soon as it tries. Foundation's Process does the latter.
    let sameGroup = #"[ "$(ps -o pgid= -p $$ | tr -d ' ')" = "$1" ]"#
    #expect(Spawn.run("/bin/sh", ["-c", sameGroup, "sh", String(getpgrp())]) == 0)
}

@Test func spawnPassesTheExitStatusAndEnvironment() {
    #expect(Spawn.run("/bin/sh", ["-c", "exit 3"]) == 3)
    #expect(Spawn.run("/bin/sh", ["-c", #"[ "$TAYDIC_SPAWN_TEST" = yes ]"#], environment: ["TAYDIC_SPAWN_TEST": "yes"]) == 0)
    #expect(Spawn.run("/tidy-test/no-such-program", []) == -1)
}

@Test func ctrlCStillReachesTheSpawnedProgram() {
    // taydic ignores Ctrl-C while it waits; the program must not inherit that, or Ctrl-C at sudo's
    // password prompt would do nothing.
    #expect(Spawn.run("/bin/sh", ["-c", "kill -INT $$; sleep 5"]) == 128 + SIGINT)
}
