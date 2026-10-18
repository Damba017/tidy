# tidy

A macOS command-line tool that combines three things:

1. **AppCleaner** — fully uninstall an app (or a Homebrew package) *and* everything it left behind.
2. **DaisyDisk** — an interactive disk-usage browser for any mounted volume.
3. **Junk finder** — find orphaned app files, caches/logs, large/old files and developer junk.

Built for one user (Damba) on one machine: MacBook Air M4, latest macOS. **macOS only.** Do not add Linux/Arch support, abstractions for it, or `#if os(Linux)` branches.

Philosophy: KISS. Powerful, not pretty. Every feature must earn its place.

---

## Hard rules (never break these)

1. **Never install anything on this Mac without asking first and getting a clear "yes".** That includes Homebrew formulae/casks, `pip`, `npm`, `gem`, `curl | sh`, `xcode-select --install`, Swift toolchains, Swift packages, and copying files into `~/.local/bin` or any other location outside this project folder. Read-only checks (`swift --version`, `which brew`, `ls`) are fine.
2. **Never run `sudo`** — not to build, test, fix permissions, or anything else. The *tool* may use sudo at runtime (see "Root-owned files"), but you, the agent, never execute that code path for real.
3. **Never delete or move real user files during development.** No running `tidy uninstall`, `tidy junk` or a delete in `tidy disk` against real apps or real folders unless it's with `--dry-run`. Test destructive code only on fixtures you create under `/tmp/tidy-test/` (or a fixtures folder in the repo).
4. **Never run `brew uninstall`, `brew install` or `brew` commands that change state.** Read-only brew queries (`brew list`, `brew info --json`, `brew --prefix`) are fine.
5. **Never change system settings** (Full Disk Access, privacy permissions, defaults, launchctl). If something needs a permission, tell Damba how to grant it himself.
6. **Zero external dependencies.** Only the Swift standard library and Apple system frameworks (Foundation, Darwin, and AppKit only if truly needed). No SwiftPM packages. If you genuinely believe one is necessary, stop and ask.
7. **Git:** commit locally after each working step with a clear message. Remote `origin` = `https://github.com/Damba017/tidy.git` (HTTPS with a fine-grained per-repo access token in the macOS keychain; no SSH). **Push only when Damba explicitly asks**, every time. Never force-push, never rewrite history, never add other remotes.

---

## Talking to Damba

- Chat with him in **Dutch**, casual and direct. Swearing and humor are fine.
- Everything in the project is **English**: code, comments, commit messages, tool output, menus, this file.
- **Whenever you show him a command, explain what it does, why, and what every flag means.**
- Before starting a new phase (see Roadmap), say in a few lines what you're going to build. After finishing it, give him one or two `--dry-run` commands to try himself.

---

## Stack

- **Language:** Swift (whatever version ships with the installed Command Line Tools — check with `swift --version` first, don't assume).
- **Build system:** Swift Package Manager, `Package.swift` with **no dependencies**.
- **Targets:**
  - `TidyCore` (library): all logic — scanning, matching, trashing, brew, volumes. Testable without a terminal.
  - `tidy` (executable): argument parsing, TUI, prompts. Thin layer over `TidyCore`.
  - Tests (`TidyCoreTests`): **Swift Testing** (`import Testing`, `@Test`, `#expect`) works with the Command Line Tools alone; XCTest is not available. The CLT keep the `TestingMacros` plugin in `usr/lib/swift/host/plugins/testing/`, which SwiftPM doesn't search, so `Package.swift` passes `-plugin-path` on the test target. Plain `swift test` just works.
- **Build:** `swift build -c release` → `.build/release/tidy`.
- **Install:** copy to `~/.local/bin/tidy` — **only after Damba says yes**, every time.

Useful system APIs (so you don't reach for packages):
- Fast directory scans: `getattrlistbulk` (much faster than `FileManager.enumerator` on big trees); fall back to `fts`/`opendir` if needed.
- Trash: `FileManager.default.trashItem(at:resultingItemURL:)`.
- Volumes: `getmntinfo` / `FileManager.mountedVolumeURLs` + `URLResourceValues` (`volumeTotalCapacity`, `volumeAvailableCapacityForImportantUsage` for purgeable-aware free space).
- App info: read `Contents/Info.plist` (`CFBundleIdentifier`, `CFBundleName`, `CFBundleExecutable`), team ID via `codesign -dv` output if needed.
- Running apps: `pgrep -x` or `NSRunningApplication` (AppKit).
- TUI: raw mode via `termios` (`tcgetattr`/`tcsetattr`), ANSI escape codes, alternate screen buffer (`\e[?1049h`), terminal size via `ioctl(TIOCGWINSZ)`, redraw on `SIGWINCH`. **Always restore the terminal** on exit, Ctrl-C, and crashes (signal handlers + `defer`).

---

## Commands

```
tidy                       Main menu (TUI)
tidy uninstall [name…]     Uninstall one or more apps/brew packages + leftovers
tidy disk [path]           Disk-usage browser (TUI)
tidy junk [category]       Find junk: orphans | caches | large | dev
tidy --help / -h
tidy --version

Global flags:
  --dry-run    Show exactly what would happen. Never touches anything.
  --yes        NOT supported. Every destructive action needs an interactive y/N.
```

### `tidy` (no arguments) → main menu
```
tidy
  1  Uninstall an app
  2  Disk overview
  3  Find junk
  q  Quit
```
Number keys or arrows + Enter. Each option drops into the same flow as its subcommand.

### `tidy uninstall [name…]`
Accepts **multiple names** (`tidy uninstall discord firefox fastfetch cava`). With no name, the app list is **multi-select** (space to toggle) with **type-to-filter**: typing narrows the list live (case-insensitive substring on app/package name), backspace widens it again, and selections persist while the filter changes. Each row shows name, size and source; footer shows `N of M · K selected`. Multiple targets are handled as one batch:
- First a "Found N" summary: name, full path, source per target. Ambiguous names get a pick-one prompt each; names with no match are reported and skipped.
- One combined "quit running apps?" prompt for all running targets.
- One combined review list, **grouped per app** (collapsible, with per-app totals; groups needing sudo are labelled). Each group header has its own checkbox: toggling it selects/deselects all items in that group; it shows `[x]` when all are selected, `[ ]` when none, `[~]` when some. Individual items stay toggleable. Then **one** `y/N` for everything that can go to the Trash without root.
- **Fuzzy matches are never removed on that same y.** Ticked fuzzy items get their own block in the plan ("Fuzzy matches, asked separately") and their own single `y/N`: one y takes all of them, N keeps all of them. Ticked fuzzy items that need root join the sudo prompt only after that y.
- Then **one** sudo prompt for all root-owned items across all targets (e.g. App Store `.app` bundles).
- Then the brew flow (step 6) **per brew package**, each with its own two questions.
- Answering N anywhere skips only that part; the rest continues. End with a short summary (total moved, log path).

For each name:
1. Find candidates matching `name` (case-insensitive, fuzzy/substring) in:
   - `/Applications`, `/Applications/Utilities`, `~/Applications` (`.app` bundles)
   - Homebrew formulae and casks (only if `brew` exists; detect `/opt/homebrew/bin/brew`)
   - No name given → show a searchable/scrollable list of all installed apps with sizes.
   **Source detection** — the tool decides how something was installed, never the user:
   - Build one candidate list from: `.app` bundles (match `name` against the bundle folder name, `CFBundleName` and `CFBundleDisplayName`), `brew list --formula`, `brew list --cask`.
   - Link casks to their apps: `brew info --cask --json=v2 --installed` lists each cask's `app` artifacts (e.g. `Discord.app`). A `.app` that belongs to a cask is **one** candidate, labelled `Homebrew cask`, not two.
   - Classify every candidate as exactly one of: `Homebrew cask`, `Homebrew formula`, `App Store` (bundle has `Contents/_MASReceipt` → root-owned, needs the sudo prompt), or `manual` (DMG/zip install).
   - Show the source and full path on the first line of output so it's never a guess.
   - Homebrew → brew flow (step 6). App Store / manual → `.app` flow (step 4).
2. If several match, let him pick.
3. If the app is running: say so and ask to quit it (y/N). Don't proceed while it runs.
4. **For a `.app`:** collect related files by bundle ID, app name, and executable name in:
   - `~/Library/Application Support`, `Caches`, `Preferences` (+ `ByHost`), `Containers`, `Group Containers`, `Saved Application State`, `HTTPStorages`, `WebKit`, `Logs`, `LaunchAgents`, `Cookies`, `Application Scripts`
   - `/Library/Application Support`, `/Library/Caches`, `/Library/Preferences`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`
   - `/private/var/db/receipts` (pkg receipts — read `pkgutil --pkgs` / `--files` read-only to find pkg-installed files)
   Mark each match with how it matched: **bundle ID** (exact bundle ID, or bundle ID + suffix like `com.hnc.Discord.ShipIt`), **name** (a path component equals the app/executable name, case-insensitive — e.g. `Application Support/discord`), or **fuzzy** (name only appears as a substring — e.g. `BetterDiscord`). Bundle ID and name matches are checked by default; fuzzy ones are unchecked.
5. Show the list with sizes, let him toggle items, then one final `y/N` (plus the separate fuzzy `y/N` above, if he ticked any).
   - A path to a `.app` (e.g. `~/Downloads/Foo.app`) is accepted as a name and used as is.
   - Leftovers macOS privacy protection keeps tidy out of (EPERM, not root-owned) are not offered; they're listed afterwards with the Full Disk Access hint. sudo doesn't help there.
6. **For brew packages** the flow is exactly:
   ```
   $ tidy uninstall fastfetch
   fastfetch is installed via Homebrew (formula).
   Uninstall fastfetch (via brew)? (y/N) y
   ...
   Found 3 leftovers (1.2 MB):
     ~/.config/fastfetch            840 KB
     ~/Library/Caches/fastfetch     310 KB
     ~/.cache/fastfetch              92 KB
   Remove all leftovers? (y/N)
   ```
   - The uninstall itself runs `brew uninstall <name>` (casks: `brew uninstall --cask <name>`; mention `--zap` exists and ask before using it).
   - Leftovers: `~/.config/<name>`, `~/.cache/<name>`, `~/.local/share/<name>`, `~/.<name>` / `~/.<name>rc`, plus the `~/Library` locations above. Leftovers go to Trash.
   - If something else depends on it (`brew uses --installed <name>`), warn before asking.

### `tidy disk [path]`
- No path → list mounted volumes (Macintosh HD + any externals) with used/free, let him pick.
- **Boot volume:** scan the data volume (`/System/Volumes/Data`), not `/` — the sealed system volume and firmlinks otherwise double-count. Show the system volume's size as a single line item.
- Don't cross into other filesystems (compare `st_dev`), don't follow symlinks, count hard links once (by inode), use **allocated size** (`st_blocks * 512`), not logical size. Note in the UI that APFS clones/snapshots can make totals differ from Finder.
- ncdu-style browser: entries sorted by size, size + percentage + a bar, `Enter` into a folder, `Backspace`/`←` up, `d` delete (→ Trash, y/N), `o` reveal in Finder (`open -R`), `r` rescan, `q` quit, `?` help.
- Unreadable folders: show them as a line with "permission denied" instead of silently skipping.
- Scanning must be fast and show progress (files scanned, current path). Use concurrency where it helps.

### `tidy junk [category]`
Categories (no argument = all, grouped with totals per category):
- **orphans** — folders/plists in the `~/Library` locations whose bundle ID / name doesn't match any installed app. Always unchecked by default; mark confidence.
- **caches** — `~/Library/Caches/*`, `~/Library/Logs/*`, old crash reports in `~/Library/Logs/DiagnosticReports`.
- **large** — files over `--min-size` (default 1 GB) and/or not accessed in `--older-than` (default 180 days) in `~` (skip `~/Library`). Show last-used date.
- **dev** — Xcode `DerivedData`, `Archives`, unavailable simulators (`xcrun simctl list` read-only), stale `node_modules`, `.build`, `target`, `__pycache__`, package-manager caches. Only if they exist.

Review list grouped per category, with the same group-checkbox rules as `uninstall` (`[x]` all / `[~]` some / `[ ]` none). **Default selection:** Caches & logs and Dev junk are checked (apps regenerate them); Large & old and Orphans are unchecked (his own files / risk of false positives) — he ticks those himself. Then one `y/N` → Trash.

### Review-list keys (shared by `uninstall` and `junk`)
`↑`/`↓` move · `space` toggle item (or whole group when on its header) · `→` expand group · `←` collapse group (or jump to its header) · `a` toggle all items of the group the cursor is in (works on the header or on any item inside it; all → none → all) · `enter` continue to confirmation · `q`/`esc` cancel. No `n`/`y` keys in lists, so they never get confused with the `(y/N)` prompt. Groups start collapsed except small ones (≤ 5 items). Always show this key line at the bottom.

---

## Safety design (built into the tool)

- **Everything goes to the Trash**, never `unlink`/`removeItem`. The only exceptions are `brew uninstall` itself (brew owns that) — always behind a `y/N`.
- **Default answer is always No.** `(y/N)`, Enter = no.
- **`--dry-run` everywhere**, and it must be truly side-effect free (no brew calls that change state, no trash, no sudo, no quitting running apps — the quit prompt is skipped and listed as "would quit").
- **Denylist** — never offer to delete, regardless of what matching says:
  `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, `/private/var/db` (except reading receipts), `/Library/Apple`, `~/Library/Keychains`, `~/Library/Mail`, `~/Library/Messages`, `~/Library/Mobile Documents` (iCloud Drive), `~/Pictures/Photos Library.photoslibrary`, anything `com.apple.*` in orphan detection, the home folder itself, and any mount point.
  Also (implemented in `Denylist.swift`):
  - **Protected trees** (never removed, nor anything inside): `/dev`, `/private/etc`, `/Library/Keychains`, `~/.ssh`, `~/.gnupg`, `~/.Trash` (already in the Trash), `~/.local/state/tidy` (tidy's own log).
  - **Parents of protected trees**, e.g. `~/Library` (contains Keychains), `~/Pictures` (contains the Photos library), `/Users`, `/`.
  - **Standard folders themselves** (their contents may go, the folder may not): `/Applications`, `/Applications/Utilities`, `~/Applications`, `/Library`, `/Users/Shared`, `/Volumes`, `/opt`, `/opt/homebrew`, `/usr/local`, `/private`, `/private/tmp`, `/private/var`, `/etc`, `/tmp`, `/var`; in `~`: `Desktop`, `Documents`, `Downloads`, `Movies`, `Music`, `Pictures`, `Public`, `Library`, `.config`, `.cache`, `.local` (+ `bin`, `share`, `state`); the `~/Library` and `/Library` scan locations listed under `uninstall` (`Caches`, `Application Support`, `Preferences`, `LaunchAgents`, …).
  - **Hidden items at the root of a volume** (`.Spotlight-V100`, `.fseventsd`, `.Trashes`, …) and anything with the SIP `restricted` flag.
  - Paths are compared only after resolving symlinks on both sides (`/tmp` → `/private/tmp`), and `/System/Volumes/Data/…` is mapped to its normal path first. The denylist is checked when the plan is built **and** again right before every move.
- **Root-owned files** (App Store apps, `/Library/LaunchDaemons`, `PrivilegedHelperTools`, etc.):
  - The tool *can* remove them, but every time it needs root it says so explicitly and asks: `These 3 items need administrator rights (sudo). Continue? (y/N)`.
  - Then one `sudo` prompt for the batch, moving items into `~/.Trash/` with a collision-safe name (`sudo /bin/mv`). Mention that emptying the Trash will ask for his password later.
  - SIP-protected paths: report and skip, don't try.
  - For LaunchDaemons/Agents: `launchctl bootout` the job before removing the plist (also behind the same confirmation).
- **Full Disk Access:** some `~/Library/Containers` etc. are TCC-protected. Detect this once (EPERM on a known protected path) and print how to grant it: *System Settings → Privacy & Security → Full Disk Access → add your terminal app*. Continue with what's readable.
- **Log:** append every removal (timestamp, original path, size, where it went in the Trash, whether sudo was used) to `~/.local/state/tidy/log`. Items moved with `sudo mv` don't get Finder's "Put Back", so the log is how to find their origin.

---

## Code conventions

- Small files, one responsibility each (`Scanner.swift`, `Trash.swift`, `Volumes.swift`, `AppFinder.swift`, `Brew.swift`, `Junk.swift`, `TUI/…`).
- No clever abstractions. No protocols with one implementation. No Linux shims.
- Human-readable sizes: decimal units like Finder (1 GB = 1,000,000,000 bytes).
- Errors: say what failed and on which path. Never crash on a permission error mid-scan.
- Colors: minimal and respect `NO_COLOR`. Output must also work when piped (no TUI when stdout isn't a TTY — fall back to plain lists for `junk`/`uninstall`, refuse `disk` with a clear message).

---

## Roadmap (build in this order, commit after each)

0. **Environment check** (read-only): `swift --version`, `xcode-select -p`, `which brew`. Report to Damba. Set up the SwiftPM package + git repo + `.gitignore` (`.build/`). Skeleton `tidy --help` / `--version`.
1. **Safety core:** Trash wrapper, denylist, dry-run plumbing, y/N prompt, sudo-batch prompt (implemented, never executed by you), log. Tests on `/tmp/tidy-test/` fixtures.
2. **`tidy disk`:** volume picker, fast scanner, ncdu-style TUI browser.
3. **`tidy uninstall`** for `.app` bundles.
4. **Homebrew** support in `uninstall`.
5. **`tidy junk`:** caches → large → dev → orphans (orphans last; most risk of false positives).
6. **Main menu** (`tidy` without arguments).
7. **Release build + install** to `~/.local/bin` — ask first. Check that `~/.local/bin` is in his `PATH`; if not, tell him the line to add himself.

Stop and ask whenever a decision isn't covered here instead of guessing.
