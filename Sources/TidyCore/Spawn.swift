import Foundation

/// Runs a program in the user's terminal and waits for it, like system(3) but without a shell.
/// The program stays in taydic's own process group, the one the terminal belongs to, so it can ask
/// there (sudo's password). Foundation's Process starts it in a group of its own, in the background,
/// and macOS stops a background program as soon as it uses the terminal.
/// While it runs, Ctrl-C is the program's: taydic ignores it and carries on afterwards.
enum Spawn {
    /// The program's exit status, 128 + the signal when a signal ended it, or -1 when it couldn't start.
    static func run(_ executable: String, _ arguments: [String], environment extra: [String: String] = [:]) -> Int32 {
        // Default signal handling and no blocked signals in the program; only stdin, stdout and stderr open.
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var all = sigset_t()
        sigfillset(&all)
        posix_spawnattr_setsigdefault(&attributes, &all)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] { posix_spawn_file_actions_addinherit_np(&actions, fd) }

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = ProcessInfo.processInfo.environment.merging(extra) { $1 }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        let interrupt = signal(SIGINT, SIG_IGN)
        let quit = signal(SIGQUIT, SIG_IGN)
        defer {
            signal(SIGINT, interrupt)
            signal(SIGQUIT, quit)
        }
        var pid = pid_t()
        guard posix_spawn(&pid, executable, &actions, &attributes, argv, envp) == 0 else { return -1 }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            if errno != EINTR { return -1 }
        }
        // WIFEXITED, WEXITSTATUS and WTERMSIG are macros Swift doesn't import.
        let endedBy = status & 0x7f
        return endedBy == 0 ? (status >> 8) & 0xff : 128 + endedBy
    }
}
