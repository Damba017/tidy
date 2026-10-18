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
- Give **complete, copy-pasteable commands** (`.build/release/tidy junk --dry-run`, not `junk --dry-run`), each in its own block, with a before/after check (`stat -f '%Sm' ~/.Trash`, `ls ~/.local/state/tidy/log`) when something could change.
- After a phase or a fix he has tested: offer to push (he says yes each time; see rule 7).
- Be honest about what you did *not* test, and about anything that went wrong.
- Say it up front when a command you run deletes anything (`rm -rf`, even on your own fixtures in `/tmp`); better, don't put deletes in commands at all.

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

Junk flags:
  --min-size SIZE     large: files at least this big (default 1GB; 500MB, 1.5G, … decimal units)
  --older-than DAYS   large: also files ≥ 100 MB unused this long (default 180)

Dev aid (not in --help):
  tidy _plan PATH…    Show the removal plan for these paths. Always a dry run, never asks.
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
- One combined review list, **grouped per app** (collapsible, with per-app totals; groups needing sudo are labelled). Each group header has its own checkbox: toggling it selects/deselects all items in that group; it shows `[x]` when all are selected, `[ ]` when none, `[~]` when some. Individual items stay toggleable. Then **one** `y/N` for everything that can go to the Trash without root. Brew packages aren't in this list (brew removes them, not tidy); the review screen says which come after it ("After this list: cava (Homebrew formula), via brew with its own questions.").
- **Fuzzy matches are never removed on that same y.** Ticked fuzzy items get their own block in the plan ("Fuzzy matches, asked separately") and their own question: `y = all · o = one by one · N = none (Enter)`. One by one asks `y/N` per item; an N keeps that item and goes back to the question for the rest. Ticked fuzzy items that need root join the sudo prompt only after they were approved.
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
   - iPhone/iPad apps on the Mac (e.g. Marktplaats) are wrapped: `X.app/WrappedBundle -> Wrapper/X.app`, Info.plist at `WrappedBundle/Info.plist`, App Store when `Wrapper/iTunesMetadata.plist` exists.
   - Symlinked apps (`/Applications/Safari.app` → the sealed system) are not candidates.
   - Show the source and full path on the first line of output so it's never a guess.
   - Homebrew → brew flow (step 6). App Store / manual → `.app` flow (step 4).
2. If several match, let him pick.
3. If the app is running: say so and ask to quit it (y/N). Don't proceed while it runs. Quitting uses AppKit's `NSRunningApplication.terminate()` (like ⌘Q, so apps can save) and waits up to 15 s; an app that doesn't quit is skipped.
4. **For a `.app`:** collect related files by bundle ID, app name, and executable name in:
   - `~/Library/Application Support`, `Caches`, `Preferences` (+ `ByHost`), `Containers`, `Group Containers`, `Saved Application State`, `HTTPStorages`, `WebKit`, `Logs`, `LaunchAgents`, `Cookies`, `Application Scripts`
   - `/Library/Application Support`, `/Library/Caches`, `/Library/Preferences`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`
   - `/private/var/db/receipts` (pkg receipts — read `pkgutil --pkgs` / `--files` read-only to find pkg-installed files)
   Mark each match with how it matched: **bundle ID** (exact bundle ID, or bundle ID + suffix like `com.hnc.Discord.ShipIt`), **name** (a path component equals the app/executable name, case-insensitive — e.g. `Application Support/discord`), or **fuzzy** (name only appears as a substring — e.g. `BetterDiscord`). Bundle ID and name matches are checked by default; fuzzy ones are unchecked.
5. Show the list with sizes, let him toggle items, then one final `y/N` (plus the separate fuzzy `y/N` above, if he ticked any).
   - A path to a `.app` (e.g. `~/Downloads/Foo.app`) is accepted as a name and used as is.
   - Leftovers macOS privacy protection keeps tidy out of (EPERM, not root-owned) are not offered; they're listed afterwards with the Full Disk Access hint. sudo doesn't help there.
6. **For brew packages** the flow is (this is the real output):
   ```
   $ tidy uninstall fastfetch
   fastfetch is installed via Homebrew (formula).
   Uninstall fastfetch (via brew)? (y/N) y
   Running: brew uninstall fastfetch
   ...
   Leftovers of fastfetch:
   Move to the Trash: 1 item, 4.1 KB
       4.1 KB  ~/.config/fastfetch
   Move 1 item, 4.1 KB to the Trash? (y/N)
   ```
   - The uninstall itself runs `brew uninstall <name>` (casks: `brew uninstall --cask <name>`). For casks tidy explains `--zap` (it deletes the cask's listed files right away, **not** via the Trash) and asks separately; default No.
   - Leftovers: `~/.config/<name>`, `~/.cache/<name>`, `~/.local/share/<name>`, `~/.local/state/<name>`, `~/.<name>` / `~/.<name>rc`, plus the `~/Library` locations above (by the cask app's bundle ID and names). They go through the safety core (plan, `y/N`, fuzzy asked separately) → Trash.
   - If something else depends on it (`brew uses --installed <name>`), warn before asking.
   - Said no, or `brew uninstall` failed → its leftovers are left alone too. `--dry-run` never runs brew; it prints "would run: brew uninstall …" and the leftover plan.
   - brew queries run with `HOMEBREW_NO_AUTO_UPDATE=1`. Even read-only queries let brew refresh its own cache in `~/Library/Caches/Homebrew/api`; that's brew's housekeeping, not an install.

### `tidy disk [path]`
- No path → list mounted volumes (Macintosh HD + any externals) with used/free, let him pick.
- **Boot volume:** scan the data volume (`/System/Volumes/Data`), not `/` — the sealed system volume and firmlinks otherwise double-count. Show the system volume's size as a single line item.
- Don't cross into other filesystems (compare `st_dev`), don't follow symlinks, count hard links once (by inode), use **allocated size** (`st_blocks * 512`), not logical size. Note in the UI that APFS clones/snapshots can make totals differ from Finder.
- ncdu-style browser: entries sorted by size, size + percentage + a bar, `Enter` into a folder, `Backspace`/`←` up, `d` delete (→ Trash, y/N), `o` reveal in Finder (`open -R`), `r` rescan, `/` search this folder by name (Enter keeps it, Esc clears it; changing folder clears it), `q` quit, `?` help.
- `d` leaves the TUI, runs the safety core (plan first, then the questions), waits for Enter, comes back; the entry disappears from the tree only if it's really gone.
- Unreadable folders: show them as a line with "permission denied" instead of silently skipping.
- Scanning must be fast and show progress (files scanned, current path). Use concurrency where it helps. (Done: `getattrlistbulk`, up to 16 threads; `/Applications` with 124k files in < 1 s, totals equal to `du`.)
- Symlinks show their target (`Safari.app → ../System/Cryptexes/…`); the link itself is counted, never followed.
- A whole-volume scan gets a **"not scanned"** line: volume used − (scan + system volume), i.e. other APFS volumes (VM, Preboot, Recovery), snapshots and unreadable folders, so the top total matches "used".

### `tidy junk [category]`
Categories (no argument = all, grouped with totals per category):
- **orphans** — folders/plists in the `~/Library` locations whose bundle ID / name doesn't match any installed app. Always unchecked by default; mark confidence.
  - Only **bundle-ID-shaped** names count (`com.foo.bar`, `TEAMID.com.foo.bar`, `group.com.foo.bar`, ≥ 3 parts): plain names in `~/Library` are mostly macOS's own (`AddressBook`, `Knowledge`, `familycircled.plist`, …).
  - Never anything containing `com.apple`, nor Apple parts with other names (`org.cups`, `is.workflow` = Shortcuts, …).
  - Claimed (not an orphan): same bundle ID as an installed or running app, same vendor (`com.utmapp.*` next to UTM), or Spotlight (`mdfind kMDItemCFBundleIdentifier`) finds an app with that ID anywhere.
  - Confidence: **low** when one of his app names appears in it, else **high**.
- **caches** — `~/Library/Caches/*`, `~/Library/Logs/*`, crash reports in `~/Library/Logs/DiagnosticReports` older than **30 days**. Apple's `com.apple.*` caches are left alone.
- **large** — in `~` (skip `~/Library`, `~/.Trash`, `.git`): files ≥ `--min-size` (default 1 GB), plus files ≥ 100 MB not used for `--older-than` days (default 180; "used" = later of last opened/changed). Packages (`.app`, `.photoslibrary`, `.utm`, `.sparsebundle`, …) count as one item and are never looked into. Grouped per top folder of `~` ("Large & old · Downloads"), biggest first, at most 100 (the rest is counted). Show last-used date.
- **dev** — Xcode `DerivedData`, `Archives` (unchecked: needed to symbolicate shipped builds), unavailable simulators (`xcrun simctl list` read-only), `node_modules` (next to `package.json`), `.build` (next to `Package.swift`), `target` (next to `Cargo.toml`) when the project wasn't changed for **60 days**, `__pycache__`, package-manager caches. Only if they exist.
  - Many items of one kind? Don't build nested groups (decided 2026-10-18: not worth the complexity). If Dev junk ever gets crowded, split it into top-level groups per kind ("Dev junk · node_modules", "Dev junk · Python caches", …), like "Large & old · Downloads".
  - Python virtual environments (any folder with a `pyvenv.cfg`) are never looked into; a project's venv is offered **whole** ("Python virtual environment") when the project wasn't changed for 60 days and has `pyproject.toml`, `requirements.txt`, `uv.lock`, `Pipfile` or `setup.py` next to it (otherwise it can't easily be set up again). `~/.local/share/uv` (uv's own Pythons and tools) is skipped entirely. So `__pycache__` only shows for his own code.

Review list grouped per category, with the same group-checkbox rules as `uninstall` (`[x]` all / `[~]` some / `[ ]` none). **Default selection:** Caches & logs and Dev junk are checked (apps regenerate them); Large & old and Orphans are unchecked (his own files / risk of false positives) — he ticks those himself. Then one `y/N` → Trash. Ticked **orphans** are asked about separately, like fuzzy matches: `y = all · o = one by one · N = none (Enter)`; in one-by-one mode an N keeps that item and goes back to that question for the rest.

### Review-list keys (shared by `uninstall` and `junk`)
`↑`/`↓` move · `tab`/`⇧tab` next/previous group header (goes round at the ends; from an item, `⇧tab` goes to its own header first) · `/` search · `space` toggle item (or whole group when on its header) · `→` expand group · `←` collapse group (or jump to its header) · `a` toggle all items of the group the cursor is in (works on the header or on any item inside it; all → none → all) · `enter` continue to confirmation · `q`/`esc` cancel. No `n`/`y` keys in lists, so they never get confused with the `(y/N)` prompt. Groups start collapsed except small ones (≤ 5 items). Always show this key line at the bottom.

**Search (`/`):** type to filter on path, label or group name (case-insensitive); only groups with matches show, opened, with just the matching items; the status line shows `/term  N matches`. Enter (or ↑/↓/tab) keeps the results and returns to the keys above; Esc clears the search. With a search active, the first Esc clears it and a second one cancels. While searching, `space` on a header and `a` only touch the **matching** items — what you can't see never changes. Checks are kept when the search changes.

The uninstall app picker filters by just typing (no `/`), space selects, Enter continues (the highlighted one if nothing is selected), Esc cancels.

---

## Safety design (built into the tool)

- **One removal path:** everything that removes goes through `Remover.run` (the safety core). It first prints the whole plan — every path with size, grouped as *Move to the Trash* / *asked separately* (fuzzy matches, orphans) / *Needs sudo* / *Protected* / *Not found* — and only then asks, in this order: one `y/N` for the sure items → `y = all · o = one by one · N = none` for the doubtful ones → one `y/N` for sudo. `--dry-run` stops right after the plan.
- **Everything goes to the Trash**, never `unlink`/`removeItem`. The only exceptions are `brew uninstall` itself (brew owns that) — always behind a `y/N`.
- **Default answer is always No.** `(y/N)`, Enter = no. Only `y`/`yes` counts. When stdin isn't a terminal every question is answered No, so a yes can't be piped in.
- **Privacy protection is not root:** `access()` failing with `EACCES` (permission bits, e.g. root-owned App Store apps) → sudo batch. `EPERM` (macOS privacy protection, or a lock flag) → *Protected*, with the Full Disk Access hint; sudo from a terminal can't get past it either.
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
  - For LaunchDaemons/Agents: `launchctl bootout` the job before removing the plist (also behind the same confirmation). Done in the safety core: agents `launchctl bootout gui/<uid> <plist>`, daemons `sudo -n /bin/launchctl bootout system <plist>`; never for a path the denylist refuses; the plan marks them "(stops its launchd job first)".
- **Full Disk Access:** some `~/Library/Containers` etc. are TCC-protected. Detect this once (EPERM on a known protected path) and print how to grant it: *System Settings → Privacy & Security → Full Disk Access → add your terminal app*. Continue with what's readable.
- **Log:** append every removal (timestamp, original path, size, where it went in the Trash, whether sudo was used) to `~/.local/state/tidy/log`. Items moved with `sudo mv` don't get Finder's "Put Back", so the log is how to find their origin. Format: one tab-separated line per item, `time  moved|failed  size  original  destination-or-error  sudo=yes|no`. If the Trash already holds that name, macOS adds a timestamp (`com.spotify.installer 20-27-47-232.installer`); the log has the exact name.

---

## Code map

`Sources/TidyCore/` (logic, no terminal):
- `Remover.swift` — the safety core: prints the plan, asks, trashes, sudo batch, launchctl, log. The only removal path.
- `RemovalPlan.swift` — what would happen to each path (Trash / sudo / protected / missing), the doubtful block, rendering.
- `Denylist.swift` — what may never be removed. `Paths.swift` — normalize (symlinks, `/System/Volumes/Data`), display with `~`.
- `Trash.swift` (move to Trash, refuses denylisted paths itself), `Sudo.swift`, `Launchctl.swift`, `Log.swift`.
- `Size.swift` — allocated size (`fts`), formatting, parsing ("500MB"). `Scanner.swift` — `getattrlistbulk` tree scan for `disk`. `Volumes.swift`.
- `AppFinder.swift` (.app bundles), `Brew.swift` (read-only queries + running `brew uninstall`), `Candidates.swift` (apps + brew in one list), `Leftovers.swift` (bundle ID / name / fuzzy / pkg receipts / dotfiles), `BrewFlow.swift`, `RunningApps.swift` (AppKit, only for quitting/bundle IDs).
- `Junk.swift` — caches, large & old + dev (one `fts` walk through `~`), orphans.
- `ReviewList.swift` — the review-list model (groups, checks, search, Tab jumps) and the uninstall picker model.

`Sources/tidy/` (terminal): `main.swift` (arguments), `Prompt.swift` (`ask` y/N, `choose` y/o/N), `DiskCommand.swift`, `UninstallCommand.swift`, `JunkCommand.swift`, `TUI/Terminal.swift` (raw mode, keys, restore on exit/signals), `TUI/ReviewView.swift`, `TUI/Text.swift`.

## Development & testing

- `swift test` runs everything (Swift Testing). Every test works on fixtures in `/tmp/tidy-test/<uuid>` (`Fixture` in `Tests/TidyCoreTests/Fixtures.swift`) with a fake home.
- **No test may ever reach the real Trash, sudo, launchctl or brew.** The internal overloads of `Remover.run`, `Trash.move` and `BrewFlow.run` have **no defaults** on purpose: tests pass `fx.trash` (a fake Trash inside the fixture, which also refuses anything outside `/tmp/tidy-test`), `Transcript` (fake `ask`/`choose`/`sudo`/`launchctl` that record and run nothing) and `FakeBrew`. The one test that uses the real Trash only runs with `TIDY_TRASH_TESTS=1` — ask Damba first. (On 2026-10-18 a denylist bug, `/tmp` vs `/private/tmp`, made refusal tests move empty fixture folders into his real Trash; that's why.)
- To check the real Trash wasn't touched: `stat -f '%Sm' ~/.Trash` before and after (listing `~/.Trash` is blocked by privacy protection).
- TUI checks: `python3 -I scripts/drive_tui.py COLS ROWS STEPS… -- .build/debug/tidy …` runs tidy in a pseudo-terminal and prints screens (cursor row marked `>>`). Only with `--dry-run` or on fixtures, answering `n`.
- Don't scan Damba's whole home or disk from the agent (`junk large/dev/caches`, `disk` on `~`): macOS then shows privacy pop-ups for the Claude app. Give him the commands to run in his own Terminal instead. Reading names in `~/Library` and Spotlight (`junk orphans`) is fine.
- `tidy _plan PATH…` shows what tidy would do with any path, always as a dry run.

## Code conventions

- Small files, one responsibility each (see the code map).
- No clever abstractions. No protocols with one implementation. No Linux shims.
- Human-readable sizes: decimal units like Finder (1 GB = 1,000,000,000 bytes).
- Errors: say what failed and on which path. Never crash on a permission error mid-scan.
- Colors: minimal and respect `NO_COLOR`. Output must also work when piped (no TUI when stdout isn't a TTY — fall back to plain lists for `junk`/`uninstall`, refuse `disk` with a clear message).

---

## Roadmap (build in this order, commit after each)

0. ✅ **Environment check** (read-only): `swift --version`, `xcode-select -p`, `which brew`. Report to Damba. Set up the SwiftPM package + git repo + `.gitignore` (`.build/`). Skeleton `tidy --help` / `--version`. (Swift 6.4, Command Line Tools only, no Xcode; brew at `/opt/homebrew`.)
1. ✅ **Safety core:** Trash wrapper, denylist, dry-run plumbing, y/N prompt, sudo-batch prompt (implemented, never executed by you), log. Tests on `/tmp/tidy-test/` fixtures.
2. ✅ **`tidy disk`:** volume picker, fast scanner, ncdu-style TUI browser.
3. ✅ **`tidy uninstall`** for `.app` bundles.
4. ✅ **Homebrew** support in `uninstall`.
5. ✅ **`tidy junk`:** caches → large → dev → orphans (orphans last; most risk of false positives).
6. **Main menu** (`tidy` without arguments).
7. **Release build + install** to `~/.local/bin` — ask first. Check that `~/.local/bin` is in his `PATH`; if not, tell him the line to add himself.
8. **Full code review, at max effort**, looking for anything that could remove the wrong thing — before Damba's first real uninstalls (AppCleaner first, then an App Store app he doesn't care about: the first real run of the sudo path).

**Where things stand (2026-10-18):** phases 0–5 are done, tested by Damba with `--dry-run`, and pushed. Real removals have been tried once, on purpose and small (`junk orphans` and `junk caches`, user-owned items only): Trash, log and "Put Back" work. Never run for real yet: the sudo path, `launchctl bootout`, `brew uninstall`, quitting a running app.

Stop and ask whenever a decision isn't covered here instead of guessing.
