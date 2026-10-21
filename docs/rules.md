# Rules

Project-specific rules for tidy/taydic. The general rules (language, secrets, no sudo, no installs, never guess, git basics) are in `CLAUDE.md`; this file adds the detail and everything that only applies to this project. What each command must do: `docs/goal.md`.

## Details of the rules in CLAUDE.md

- **Install** means: Homebrew formulae/casks, `pip`, `npm`, `gem`, `curl | sh`, `xcode-select --install`, Swift toolchains, Swift packages, and copying files into `~/.local/bin` or any other location outside this project folder. Read-only checks (`swift --version`, `which brew`, `ls`) are fine. Every install gets logged in `docs/tools.md`.
- **sudo:** the *tool* may use sudo at runtime (see "Root-owned files" below), but you, the agent, never execute that code path for real.
- **Never delete or move real user files during development.** No running `taydic uninstall`, `taydic leftovers`, `taydic junk` or a delete in `taydic disk` against real apps or real folders unless it's with `--dry-run`. Test destructive code only on fixtures you create under `/tmp/tidy-test/` (or a fixtures folder in the repo).
- **Never run `brew uninstall`, `brew install` or `brew` commands that change state.** Read-only brew queries (`brew list`, `brew info --json`, `brew --prefix`) are fine.
- **Never change system settings** (Full Disk Access, privacy permissions, defaults, launchctl). If something needs a permission, tell Damba how to grant it himself.
- **Zero external dependencies.** Only the Swift standard library and Apple system frameworks (Foundation, Darwin, and AppKit only if truly needed). No SwiftPM packages. If you genuinely believe one is necessary, stop and ask.
- **Git:** commit locally after each working step with a clear message, but nothing is committed before Damba has tested it (see the routine below). Remote `origin` = `https://github.com/Damba017/tidy.git` (HTTPS with a fine-grained per-repo access token in the macOS keychain; no SSH). **Push only when Damba explicitly asks**, every time. Never force-push, never rewrite history, never add other remotes.

## Working with Damba

- Chat with him in **Dutch**, casual and direct. Swearing and humor are fine.
- Everything in the project is **English**: code, comments, commit messages, tool output, menus, `CLAUDE.md` and `docs/`.
- **Whenever you show him a command, explain what it does, why, and what every flag means.**
- Before starting a new phase (see `docs/plan.md`), say in a few lines what you're going to build. After finishing it, give him one or two `--dry-run` commands to try himself.
- Give **complete, copy-pasteable commands** (`.build/release/taydic junk --dry-run`, not `junk --dry-run`), each in its own block, with a before/after check (`stat -f '%Sm' ~/.Trash`, `ls ~/.local/state/taydic/log`) when something could change.
- After a phase or a fix he has tested: offer to push (he says yes each time; see the Git rule above).
- His routine for every change (new feature or fix): code → tests → check yourself for anything that could remove the wrong thing → he tests with the commands you give him (dry-runs first, real runs only when he wants) → commit → push and install (bump `Version.swift`, ask which version) when he says so. Nothing is committed before his test.
- Be honest about what you did *not* test, and about anything that went wrong.
- Say it up front when a command you run deletes anything (`rm -rf`, even on your own fixtures in `/tmp`); better, don't put deletes in commands at all.
- Stop and ask whenever a decision isn't covered here instead of guessing.

## Safety design (built into the tool)

- **One removal path:** everything that removes goes through `Remover.run` (the safety core). It first prints the whole plan — every path with size, grouped as *Move to the Trash* / *asked separately* (fuzzy matches, orphans) / *Needs sudo* / *Privacy permissions* / *Protected* / *Not found* — and only then asks, in this order: one `y/N` for the sure items → `y = all · o = one by one · N = none` for the doubtful ones → one `y/N` for sudo. Right after whichever of those moves an app with a privacy reset in the plan comes that reset's own `y/N` (see `taydic uninstall` in `docs/goal.md`). `--dry-run` stops right after the plan.
  - Layout (Damba's choice, 2026-10-19): within each block, paths per folder: the folder once (`  ~/Library/Caches/`), the names under it, items moved in that same order. Results (`moved` / `FAILED` + a short reason; macOS's own long message goes to the log) come right under the answer, also per folder; `→ ~/.Trash/…` only when the Trash gave another name. A list shown again before a question gets a blank line before that question; no blank line between a question and its results. Ends with `Done: N items (size) moved to the Trash[, N failed (see above)].` and the log path. The sudo question names the item when there's one.
- **Everything goes to the Trash**, never `unlink`/`removeItem`. The only exceptions are `brew uninstall` itself (brew owns that) — always behind a `y/N`.
- **Default answer is always No.** `(y/N)`, Enter = no. Only `y`/`yes` counts. When stdin isn't a terminal every question is answered No, so a yes can't be piped in. Only what's typed after a question appears counts: typed-ahead input is thrown away first (`tcflush`), so a `y⏎` typed while the plan was still loading never answers it.
- **Privacy protection is not root:** `access()` failing with `EACCES` (permission bits, e.g. root-owned App Store apps) → sudo batch. `EPERM` (macOS privacy protection, or a lock flag) → *Protected*, with the Full Disk Access hint; sudo from a terminal can't get past it either. `EROFS` (a read-only volume, e.g. a mounted .dmg) → *Protected* ("read-only volume"), never a password prompt for nothing.
- **`--dry-run` everywhere**, and it must be truly side-effect free (no brew calls that change state, no trash, no sudo, no quitting running apps — the quit prompt is skipped and listed as "would quit").
- **Denylist** — never offer to delete, regardless of what matching says:
  `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, `/private/var` (except what's inside his own temp and cache folders, see below; the receipts in `/private/var/db` are only read), `/Library/Apple`, `/Library/Preferences/SystemConfiguration` (network settings), `~/Library/Keychains`, `~/Library/Mail`, `~/Library/Messages`, `~/Library/Mobile Documents` (iCloud Drive), `~/Pictures/Photos Library.photoslibrary`, anything `com.apple.*` in orphan detection, the home folder itself, and any mount point.
  Also (implemented in `Denylist.swift`):
  - **Protected trees** (never removed, nor anything inside): `/dev`, `/private/etc`, `/private/var` (other users' and macOS's temp files in `folders`, root's home, logs, …), `/Library/Keychains`, `/Library/Preferences/SystemConfiguration`, `~/.ssh`, `~/.gnupg`, `~/.Trash` (already in the Trash), `~/.local/state/taydic` (its own log), `~/.local/state/tidy` (the log from before the rename).
  - **One exception inside `/private/var`** (added 2026-10-21), like `/usr/local` in `/usr`: what's *inside* his own temp and cache folders (`Paths.userTempFolders`: `confstr(_CS_DARWIN_USER_TEMP_DIR)` and `…_CACHE_DIR`, i.e. `/private/var/folders/<xx>/<yyy>/T` and `C`, checked to be just that). `T` and `C` themselves stay protected, and so do their siblings `0` and `X`, other users' folders and the rest of `/private/var`. A path with `..` in it never gets the exception. Temp files of running apps: `uninstall` quits the app first, `leftovers` refuses a name that's running, the brew flow keeps a running formula's temp files.
  - **Parents of protected trees**, e.g. `~/Library` (contains Keychains), `~/Pictures` (contains the Photos library), `/Users`, `/`.
  - **Standard folders themselves** (their contents may go, the folder may not): `/Applications`, `/Applications/Utilities`, `~/Applications`, `/Library`, `/Users/Shared`, `/Volumes`, `/opt`, `/opt/homebrew`, `/usr/local`, `/private`, `/private/tmp`, `/etc`, `/tmp`, `/var`; in `~`: `Desktop`, `Documents`, `Downloads`, `Movies`, `Music`, `Pictures`, `Public`, `Library`, `.config`, `.cache`, `.local` (+ `bin`, `share`, `state`); the `~/Library` and `/Library` scan locations listed under `taydic uninstall` in `docs/goal.md` (`Caches`, `Application Support`, `Preferences`, `LaunchAgents`, …).
  - **Hidden items at the root of a volume** (`.Spotlight-V100`, `.fseventsd`, `.Trashes`, …) and anything with the SIP `restricted` flag.
  - Paths are compared only after resolving symlinks on both sides (`/tmp` → `/private/tmp`), and `/System/Volumes/Data/…` is mapped to its normal path first — but only inside a firmlinked folder (`/Users`, `/Applications`, `/usr/local`, …: same device and inode on both sides). What exists on the data volume only (`macOS Install Data`, the autofs `home`) keeps its full path, so it falls under `/System` and is protected. The denylist is checked when the plan is built **and** again right before every move.
  - Case never matters: APFS ignores it (`~/applications` *is* `~/Applications`), so the denylist compares without case, and `Paths.normalize` takes each path's last name as it's spelled on disk (`getattrlist`, without following a symlink). Found in the phase 8 review: before that, `taydic uninstall ~/applications` would have offered his whole `~/Applications`.
- **Root-owned files** (App Store apps, `/Library/LaunchDaemons`, `PrivilegedHelperTools`, etc.):
  - The tool *can* remove them, but every time it needs root it says so explicitly and asks: `These 3 items need administrator rights (sudo). Continue? (y/N)`.
  - Then one `sudo` prompt for the batch, moving items into `~/.Trash/` with a collision-safe name (`sudo /bin/mv`). Mention that emptying the Trash will ask for his password later.
  - sudo and `brew uninstall` run through `Spawn` (`posix_spawn`), in taydic's own process group, so sudo can ask for the password in the terminal. Foundation's `Process` starts them in a process group of their own, in the background, and macOS stops a background program as soon as it touches the terminal: `sudo -v` used to hang there (found in the final review, 2026-10-19). While they run, taydic ignores Ctrl-C, so Ctrl-C at the password prompt cancels only sudo.
  - The name in the Trash is picked before anything is stopped or moved, and only a name `lstat` says doesn't exist (`ENOENT`) counts as free: if taydic can't look into the Trash (privacy protection), nothing more is moved with sudo. `mv -n` exits 0 without moving when the name was taken in the meantime; taydic reports that as "not moved, … was taken". (Looking up one name in `~/.Trash` works without Full Disk Access; only listing it doesn't.)
  - Root-owned items on another volume are moved into `~/.Trash` too, which copies them (decided 2026-10-19: fine, it's rare).
  - SIP-protected paths: report and skip, don't try.
  - For LaunchDaemons/Agents: `launchctl bootout` the job before removing the plist (also behind the same confirmation). Done in the safety core: agents `launchctl bootout gui/<uid> <plist>`, daemons `sudo -n /bin/launchctl bootout system <plist>`; never for a path the denylist refuses; the plan marks them "(stops its launchd job first)".
- **Full Disk Access:** without it, macOS privacy protection (TCC) keeps the terminal out of e.g. `~/Library/Cookies`, other apps' Group Containers, and sometimes an app's container (moving `~/Library/Containers/<id>` can fail although `access()` says writable: a safe FAILED, "no permission (macOS protects it; Full Disk Access may help)"). taydic carries on with what it can reach, and after the review list says what it couldn't: items ("Not in the list") and whole folders ("Not searched"), with *System Settings → Privacy & Security → Full Disk Access → add your terminal app*. Damba's Terminal has Full Disk Access since 2026-10-19 (his choice); the Claude app doesn't, so `~/Library/Cookies` shows as "Not searched" in the agent's dry-runs.
- **Log:** append every removal (timestamp, original path, size, where it went in the Trash, whether sudo was used) to `~/.local/state/taydic/log` (until 2026-10-19 it was `~/.local/state/tidy/log`; that old log stays where it is). Items moved with `sudo mv` don't get Finder's "Put Back", so the log is how to find their origin. Format: one tab-separated line per item, `time  moved|failed  size  original  destination-or-error  sudo=yes|no`; a privacy reset (permissions revoked) gets `time  reset  -  <app path>  privacy permissions: tccutil reset All <bundleID>  sudo=no` (before the app's own line, as it runs first; a failed one is a `failed` line saying so); a tab, newline or backslash in a path is written as `\t`, `\n`, `\\`. If the Trash already holds that name, macOS adds a timestamp (`com.spotify.installer 20-27-47-232.installer`); the log has the exact name.

## Code conventions

- Small files, one responsibility each (see the code map below).
- No clever abstractions. No protocols with one implementation. No Linux shims.
- Human-readable sizes: decimal units like Finder (1 GB = 1,000,000,000 bytes).
- Errors: say what failed and on which path. Never crash on a permission error mid-scan.
- Colors: minimal and respect `NO_COLOR` (only when stdout is a terminal): `moved` and `quit` green, `FAILED` red, headers bold, folder lines dim. TidyCore prints plain text; `show` in the tidy target adds the colour. Output must also work when piped (no TUI when stdout isn't a TTY — fall back to plain lists for `junk`/`uninstall`, refuse `disk` with a clear message).

## Development & testing

- `swift test` runs everything (Swift Testing). Every test works on fixtures in `/tmp/tidy-test/<uuid>` (`Fixture` in `Tests/TidyCoreTests/Fixtures.swift`) with a fake home.
- **No test may ever reach the real Trash, sudo, launchctl, tccutil or brew.** The internal overloads of `Remover.run`, `Trash.move` and `BrewFlow.run` have **no defaults** on purpose: tests pass `fx.trash` (a fake Trash inside the fixture, which also refuses anything outside `/tmp/tidy-test`), `Transcript` (fake `ask`/`choose`/`sudo`/`launchctl`/`tccutil` that record and run nothing) and `FakeBrew`. Fixture `T/` and `C/` folders stand in for his temp and cache folders; the denylist exception is tested on real `/private/var/folders` paths that don't exist (names only, nothing moved). The two tests that use the real Trash only run with `TIDY_TRASH_TESTS=1` — ask Damba first. One moves two fixtures, the other one symlink: the link goes, what it points to stays (run 2026-10-19 with his OK, passed). (On 2026-10-18 a denylist bug, `/tmp` vs `/private/tmp`, made refusal tests move empty fixture folders into his real Trash; that's why.)
- Never run `tccutil` yourself, not even with a made-up bundle ID (never change system settings, see above); only taydic runs it, for Damba.
- To check the real Trash wasn't touched: `stat -f '%Sm' ~/.Trash` before and after (listing `~/.Trash` is blocked by privacy protection).
- TUI checks: `python3 -I scripts/drive_tui.py COLS ROWS STEPS… -- .build/debug/taydic …` runs it in a pseudo-terminal and prints screens (cursor row marked `>>`). Only with `--dry-run` or on fixtures, answering `n`.
- Don't scan Damba's whole home or disk from the agent (`junk large/dev/caches`, `disk` on `~`): macOS then shows privacy pop-ups for the Claude app. Give him the commands to run in his own Terminal instead. Reading names in `~/Library` and Spotlight (`junk orphans`) is fine.
- `taydic _plan PATH…` shows what taydic would do with any path, always as a dry run.
- From the agent, `uninstall`/`leftovers` dry-runs are fine for apps without a sandbox container (AppCleaner, `mozilla`): they read names in the Library folders and measure what matched. Measuring another app's container can make macOS ask the Claude app for access, so give Damba those commands instead.

## Stack, build and install

- **Language:** Swift (whatever version ships with the installed Command Line Tools — check with `swift --version` first, don't assume).
- **Build system:** Swift Package Manager, `Package.swift` with **no dependencies**.
- **Targets:**
  - `TidyCore` (library): all logic — scanning, matching, trashing, brew, volumes. Testable without a terminal.
  - `tidy` (executable target, built as the `taydic` product in `Package.swift`): argument parsing, TUI, prompts. Thin layer over `TidyCore`.
  - Tests (`TidyCoreTests`): **Swift Testing** (`import Testing`, `@Test`, `#expect`) works with the Command Line Tools alone; XCTest is not available. The CLT keep the `TestingMacros` plugin in `usr/lib/swift/host/plugins/testing/`, which SwiftPM doesn't search, so `Package.swift` passes `-plugin-path` on the test target. Plain `swift test` just works.
- **Build:** `swift build -c release` → `.build/release/taydic`.
- **Install:** copy to `~/.local/bin/taydic` — **only after Damba says yes**, every time: bump the version in `Sources/TidyCore/Version.swift` (ask which), `swift build -c release`, then `mkdir -p ~/.local/bin && cp .build/release/taydic ~/.local/bin/taydic`, then check with `cmp` and `~/.local/bin/taydic --version`.
  - `~/.local/bin` is in his PATH: he added `export PATH="$HOME/.local/bin:$PATH"` to `~/.zprofile` himself on 2026-10-19 (it also has brew's `shellenv` line; there's no `~/.zshrc`), and `which taydic` says `~/.local/bin/taydic`. macOS's own `/usr/bin/tidy` (HTML Tidy) is why the command isn't called tidy; the old `~/.local/bin/tidy` (0.1.0) is gone. Never `/usr/bin`: it's on the sealed system volume (SIP).
- **Repo extras:** `README.md` (English, for anyone who wants to use it: features, safety rules, install, usage; keep it in step when commands change) and `assets/` (`logo.png` shown at the top of the README, `icon.png`). No license file yet: Damba's choice.

### Useful system APIs (so you don't reach for packages)
- Fast directory scans: `getattrlistbulk` (much faster than `FileManager.enumerator` on big trees); fall back to `fts`/`opendir` if needed.
- Trash: `FileManager.default.trashItem(at:resultingItemURL:)`.
- Volumes: `getmntinfo` / `FileManager.mountedVolumeURLs` + `URLResourceValues` (`volumeTotalCapacity`, `volumeAvailableCapacityForImportantUsage` for purgeable-aware free space).
- App info: read `Contents/Info.plist` (`CFBundleIdentifier`, `CFBundleName`, `CFBundleExecutable`), team ID via `codesign -dv` output if needed.
- Running apps: `pgrep -x` or `NSRunningApplication` (AppKit).
- TUI: raw mode via `termios` (`tcgetattr`/`tcsetattr`), ANSI escape codes, alternate screen buffer (`\e[?1049h`), terminal size via `ioctl(TIOCGWINSZ)`, redraw on `SIGWINCH`. **Always restore the terminal** on exit, Ctrl-C, and crashes (signal handlers + `defer`).

## Code map

`Sources/TidyCore/` (logic, no terminal):
- `Remover.swift` — the safety core: prints the plan, asks, trashes, sudo batch, launchctl, tccutil, log. The only removal path.
- `RemovalPlan.swift` — what would happen to each path (Trash / sudo / protected / missing), the doubtful block, the privacy resets, rendering.
- `Denylist.swift` — what may never be removed. `Paths.swift` — normalize (symlinks, `/System/Volumes/Data`), display with `~`, his temp and cache folders.
- `Trash.swift` (move to Trash, refuses denylisted paths itself), `Sudo.swift`, `Spawn.swift` (runs sudo and `brew uninstall` in the terminal, in taydic's process group), `Launchctl.swift`, `Tccutil.swift` (which app gets a privacy reset, running `tccutil reset All`), `Log.swift`.
- `Size.swift` — allocated size (`fts`), formatting, parsing ("500MB"). `Scanner.swift` — `getattrlistbulk` tree scan for `disk`. `Volumes.swift`.
- `Output.swift` — lists of paths per folder, and the colours (which lines get which).
- `AppFinder.swift` (.app bundles), `Brew.swift` (read-only queries + running `brew uninstall`), `Candidates.swift` (apps + brew in one list), `Leftovers.swift` (bundle ID / prefix / name / fuzzy / pkg receipts / dotfiles; the strict locations and macOS's own `~/Library` names), `BrewFlow.swift`, `RunningApps.swift` (AppKit, only for quitting/bundle IDs; plus the executables of all running programs, via libproc).
- `Junk.swift` — caches, large & old + dev (one `fts` walk through `~`), orphans.
- `LeftoverSearch.swift` — `taydic leftovers`: which names may be searched, what counts as still installed, the search itself.
- `ReviewList.swift` — the review-list model (groups, checks, search, Tab jumps) and the uninstall picker model.

`Sources/tidy/` (terminal): `main.swift` (arguments), `Prompt.swift` (`ask` y/N, `choose` y/o/N), `Show.swift` (`show`: prints a line, coloured on a terminal; the Full Disk Access notes), `MenuCommand.swift`, `DiskCommand.swift`, `UninstallCommand.swift` (also `reviewGroup`, shared with leftovers), `LeftoversCommand.swift`, `JunkCommand.swift`, `TUI/Terminal.swift` (raw mode, keys, restore on exit/signals), `TUI/ReviewView.swift`, `TUI/Text.swift`.
