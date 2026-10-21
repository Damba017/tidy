# tidy

A macOS command-line tool that combines four things:

1. **AppCleaner** — fully uninstall an app (or a Homebrew package) *and* everything it left behind.
2. **DaisyDisk** — an interactive disk-usage browser for any mounted volume.
3. **Junk finder** — find orphaned app files, caches/logs, large/old files and developer junk.
4. **Leftovers finder** — what an app that's already gone (removed before taydic existed) left behind, by its name.

Built for one user (Damba) on one machine: MacBook Air M4, latest macOS. **macOS only.** Do not add Linux/Arch support, abstractions for it, or `#if os(Linux)` branches.

Philosophy: KISS. Powerful, not pretty. Every feature must earn its place.

**Naming:** the command you run is **`taydic`** ("taydi cleaner"; renamed 2026-10-19 because macOS ships its own `/usr/bin/tidy`, HTML Tidy). The project is still called tidy: this file, the folder `~/tidy`, the `TidyCore` module, the `tidy` executable target and the GitHub repo.

---

## Hard rules (never break these)

1. **Never install anything on this Mac without asking first and getting a clear "yes".** That includes Homebrew formulae/casks, `pip`, `npm`, `gem`, `curl | sh`, `xcode-select --install`, Swift toolchains, Swift packages, and copying files into `~/.local/bin` or any other location outside this project folder. Read-only checks (`swift --version`, `which brew`, `ls`) are fine.
2. **Never run `sudo`** — not to build, test, fix permissions, or anything else. The *tool* may use sudo at runtime (see "Root-owned files"), but you, the agent, never execute that code path for real.
3. **Never delete or move real user files during development.** No running `taydic uninstall`, `taydic leftovers`, `taydic junk` or a delete in `taydic disk` against real apps or real folders unless it's with `--dry-run`. Test destructive code only on fixtures you create under `/tmp/tidy-test/` (or a fixtures folder in the repo).
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
- Give **complete, copy-pasteable commands** (`.build/release/taydic junk --dry-run`, not `junk --dry-run`), each in its own block, with a before/after check (`stat -f '%Sm' ~/.Trash`, `ls ~/.local/state/taydic/log`) when something could change.
- After a phase or a fix he has tested: offer to push (he says yes each time; see rule 7).
- His routine for every change (new feature or fix): code → tests → check yourself for anything that could remove the wrong thing → he tests with the commands you give him (dry-runs first, real runs only when he wants) → commit → push and install (bump `Version.swift`, ask which version) when he says so. Nothing is committed before his test.
- Be honest about what you did *not* test, and about anything that went wrong.
- Say it up front when a command you run deletes anything (`rm -rf`, even on your own fixtures in `/tmp`); better, don't put deletes in commands at all.

---

## Stack

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
taydic                       Main menu (TUI)
taydic uninstall [name…]     Uninstall one or more apps/brew packages + leftovers
taydic leftovers name        What an app you already removed left behind, found by its name
taydic disk [path]           Disk-usage browser (TUI)
taydic junk [category]       Find junk: orphans | caches | large | dev
taydic --help / -h
taydic --version

Global flags:
  --dry-run    Show exactly what would happen. Never touches anything.
  --yes        NOT supported. Every destructive action needs an interactive y/N.

Junk flags:
  --min-size SIZE     large: files at least this big (default 1GB; 500MB, 1.5G, … decimal units)
  --older-than DAYS   large: also files ≥ 100 MB unused this long (default 180)

Dev aid (not in --help):
  taydic _plan PATH…  Show the removal plan for these paths. Always a dry run, never asks.
```

### `taydic` (no arguments) → main menu
```
taydic
  1  Uninstall an app
  2  Disk overview
  3  Find junk
  4  Find leftovers   (asks for the name)
  q  Quit
```
Number keys or arrows + Enter. Each option drops into the same flow as its subcommand (`--dry-run` and the junk flags pass through). Afterwards: "Press Enter for the menu, or q and Enter to quit", so the flow's output stays readable and he can do several things in one go. When stdout/stdin isn't a terminal, `taydic` prints the help instead.

### `taydic uninstall [name…]`
Accepts **multiple names** (`taydic uninstall discord firefox fastfetch cava`). With no name, the app list is **multi-select** (space to toggle) with **type-to-filter**: typing narrows the list live (case-insensitive substring on app/package name), backspace widens it again, and selections persist while the filter changes. Each row shows name, size and source; footer shows `N of M · K selected`. Multiple targets are handled as one batch:
- First a "Found N" summary: name, full path, source per target. Ambiguous names get a pick-one prompt each; names with no match are reported and skipped.
- One combined "quit running apps?" prompt for all running targets.
- One combined review list, **grouped per app** (collapsible, with per-app totals; groups needing sudo are labelled). Each group header has its own checkbox: toggling it selects/deselects all items in that group; it shows `[x]` when all are selected, `[ ]` when none, `[~]` when some. Individual items stay toggleable. Then **one** `y/N` for everything that can go to the Trash without root. Brew packages aren't in this list (brew removes them, not taydic); the review screen says which come after it ("After this list: cava (Homebrew formula), via brew with its own questions.").
- **Fuzzy matches are never removed on that same y.** Ticked fuzzy items get their own block in the plan ("Fuzzy matches, asked separately") and their own question: `y = all · o = one by one · N = none (Enter)`. One by one asks `y/N` per item; an N keeps that item and goes back to the question for the rest. Ticked fuzzy items that need root join the sudo prompt only after they were approved.
- Then **one** sudo prompt for all root-owned items across all targets (e.g. App Store `.app` bundles).
- **Privacy permissions (TCC)** (added 2026-10-21): each app with a bundle ID that's in the plan gets a block "Privacy permissions, asked separately" (`tccutil reset All <bundleID>`). Right after the yes that moves the app (the sure `y/N`, or the sudo one for App Store apps) comes its own `y/N`: "Also reset the privacy permissions of Roblox (tccutil reset All com.roblox.RobloxPlayer)?". On a yes, `tccutil` runs right **before** the app moves: it asks LaunchServices for the app by bundle ID, and once the app is gone it fails with "No such bundle identifier" (OSStatus -10814). Damba chose that order, 2026-10-21. No reset when he says N to the app, when the app wasn't ticked, or when another installed or running app has the same bundle ID (a second copy). No sudo. The result comes under the app's own line (`reset   privacy permissions of Roblox`, or `FAILED` with what tccutil said), and in the log as a `reset` line. `--dry-run` prints "would run tccutil reset All …". Not for brew casks (brew deletes the app before the leftovers step, so tccutil would no longer find it).
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
   - **Strict locations** (added 2026-10-21, after Damba's Roblox test): `~/Library` itself, one level deep (`~/Library/Roblox`), and his own temp and cache folders in `/var/folders` (`confstr(_CS_DARWIN_USER_TEMP_DIR)` = `$TMPDIR` = `…/T`, and `_CS_DARWIN_USER_CACHE_DIR` = `…/C`; `Paths.userTempFolders`), direct children only. There bundle ID (+ prefix, + WebKit) and exact name count; **fuzzy never in `~/Library` itself**, and in `T`/`C` only for names shaped like a bundle ID (`com.roblox.player.installer.lock`, `com.discord.discord.ShipIt.xxxx`; `Junk.bundleID(in:)`), unticked and asked separately like every fuzzy match, in `uninstall` and `leftovers` alike (Damba's choice, 2026-10-21; plain names like `discord-ipc-0`, Discord's live socket, never). And never a name of macOS's own `~/Library` folders (a fixed list in `Leftovers.macOSFolderNames` plus every name in `/System/Library`): an app called Developer (Apple has one) would otherwise get `~/Library/Developer`, Xcode's simulators and builds.
   - WebKit's temp folders for an app, `com.apple.WebKit.<Process>+<bundleID>` (in `T` and `C`), match the app's bundle ID by the part after the `+` only.
   Mark each match with how it matched: **bundle ID** (exact bundle ID, or bundle ID + suffix like `com.hnc.Discord.ShipIt`), **bundle ID prefix** (starts with the bundle ID, right after it a letter or digit: `com.roblox.RobloxPlayerChannel.plist`), **name** (a path component equals the app/executable name, case-insensitive — e.g. `Application Support/discord`), or **fuzzy** (name only appears as a substring — e.g. `BetterDiscord`). Bundle ID, prefix and name matches are checked by default; fuzzy ones are unchecked.
   - Bundle ID prefix is its own level (decided 2026-10-21) because it can be another app of the same maker that's no longer installed (`com.hnc.DiscordPTB` when uninstalling `com.hnc.Discord`): the label shows that. And the code that relies on `.bundleID` meaning "this very ID" stays as it was: which pkg receipts belong to the app, which folders a receipt may take whole, which orphans are claimed. Never for Apple's names (`com.apple.RemoteDesktopAgent` is macOS's, not Apple Remote Desktop's), only for bundle IDs of three parts or more (`com.foo` + `bar` would be another maker).
   - What another installed or running app claims as well isn't offered at all: with a longer bundle ID it's that app's (`com.google.Chrome.canary…` when uninstalling `com.google.Chrome`, `com.foo.AppBeta` and `com.foo.AppBetaHelper` when uninstalling `com.foo.App`); with the same bundle ID (a second copy, Xcode-beta next to Xcode) or by the same name (Firefox Nightly's executable is `firefox` too, in the same `Application Support/Firefox`) it's shared. An app's own helpers live inside its bundle, so they don't count as other apps.
   - pkg receipts: files inside another installed app are that app's, and a folder that holds another app is never offered whole (one .pkg can install several apps).
   - Apple's own entries (anything with `com.apple.` in the name, so also `group.com.apple.notes`) only match through the app's bundle ID, never by name or fuzzy.
5. Show the list with sizes, let him toggle items, then one final `y/N` (plus the separate fuzzy `y/N` above, if he ticked any).
   - A path to an app bundle (e.g. `~/Downloads/Foo.app`: a real folder ending in `.app` with an Info.plist) is accepted as a name and used as is. Any other path is refused ("Not an app …; skipped"), so no other folder is ever taken for an app.
   - Leftovers macOS privacy protection keeps taydic out of (EPERM, not root-owned) are not offered; they're listed afterwards with the Full Disk Access hint. sudo doesn't help there. A location taydic can't look in at all (`~/Library/Cookies` without Full Disk Access) is named there too, as "Not searched" (also in the brew flow).
6. **For brew packages** the flow is (this is the real output):
   ```
   $ taydic uninstall fastfetch
   fastfetch is installed via Homebrew (formula).
   Uninstall fastfetch (via brew)? (y/N) y
   Running: brew uninstall fastfetch
   ...
   Leftovers of fastfetch:
   Move to the Trash: 1 item, 4.1 KB
       4.1 KB  ~/.config/fastfetch
   Move 1 item, 4.1 KB to the Trash? (y/N)
   ```
   - The uninstall itself runs `brew uninstall <name>` (casks: `brew uninstall --cask <name>`). For casks taydic explains `--zap` (it deletes the cask's listed files right away, **not** via the Trash) and asks separately; default No.
   - Leftovers: `~/.config/<name>`, `~/.cache/<name>`, `~/.local/share/<name>`, `~/.local/state/<name>`, `~/.<name>` / `~/.<name>rc`, plus the `~/Library` locations above and the strict ones (by the cask app's bundle ID and names). They go through the safety core (plan, `y/N`, fuzzy asked separately) → Trash.
   - A formula has no quit step, so when a running program has the package's name (a server it started, say), its leftovers in the temp folders stay: "Kept …: ollama is still running (…)." (running programs via `proc_listallpids`/`proc_pidpath`, `RunningApps.processPaths`).
   - When macOS has its own tool of that name (`/bin`, `/usr/bin`, `/usr/sbin`: `zsh`, `bash`, `vim`, `git`, …), those dotfiles are shared with it: never offered, taydic says "Kept ~/.zshrc: macOS's own zsh (/bin/zsh) uses it too."
   - If something else depends on it (`brew uses --installed <name>`), warn before asking.
   - Said no, or `brew uninstall` failed → its leftovers are left alone too. `--dry-run` never runs brew; it prints "would run: brew uninstall …" and the leftover plan.
   - brew queries run with `HOMEBREW_NO_AUTO_UPDATE=1`. Even read-only queries let brew refresh its own cache in `~/Library/Caches/Homebrew/api`; that's brew's housekeeping, not an install.

### `taydic leftovers name` (added 2026-10-20)
For apps and tools that are already gone, e.g. dragged to the Trash before taydic existed: `junk orphans` only finds bundle-ID-shaped names, this finds `Application Support/discord`, `Logs/Discord`, `~/.config/discord` too. Menu option 4 asks for the name.
- Looks where `uninstall` looks (the `~/Library` and `/Library` locations, and the strict ones: `~/Library` itself, `$TMPDIR` and `C`) and at the brew-style dotfiles (`~/.config/<name>`, …, not when macOS has a tool of that name), by name and fuzzy (in the strict locations as described under `uninstall`); no bundle ID to go by, so `com.hnc.Discord` and `C/com.roblox.RobloxPlayer` are fuzzy. Name matches start ticked, fuzzy ones unticked and asked separately (`y = all · o = one by one · N = none`). Then the safety core as always.
- Refused: a path, fewer than 3 letters or a generic word (`helper`, `app`, …), and anything still installed — an app or brew package by that name or bundle ID (→ "use taydic uninstall"), one of macOS's own apps (`/System/Applications`, `/System/Library/CoreServices`, Safari's cryptex) or a running one, a command of that name in the PATH (`git`, `bun`, …), or a running program of that name (a helper whose app is gone; its temp files are in use) (→ "taydic leaves them alone").
- What another app on this Mac (installed, running or macOS's own) claims, by bundle ID (or a longer one starting with it) or by name, is left out; Apple's names only ever match by bundle ID.
- When an installed app has the name in its name or bundle ID (Discord PTB for "discord", `com.google.Chrome` for "google": its files may even sit in a folder called exactly that), taydic says so, nothing starts ticked and everything is asked separately.

### `taydic disk [path]`
- No path → list mounted volumes (Macintosh HD + any externals) with used/free, let him pick.
- **Boot volume:** scan the data volume (`/System/Volumes/Data`), not `/` — the sealed system volume and firmlinks otherwise double-count. Show the system volume's size as a single line item.
- Don't cross into other filesystems (compare `st_dev`), don't follow symlinks, count hard links once (by inode), use **allocated size** (`st_blocks * 512`), not logical size. Note in the UI that APFS clones/snapshots can make totals differ from Finder.
- ncdu-style browser: entries sorted by size, size + percentage + a bar, `Enter` into a folder, `Backspace`/`←` up, `d` delete (→ Trash, y/N), `o` reveal in Finder (`open -R`), `r` rescan, `/` search this folder by name (Enter keeps it, Esc clears it; changing folder clears it), `q` quit, `?` help.
- `d` leaves the TUI, runs the safety core (plan first, then the questions), waits for Enter, comes back; the entry disappears from the tree only if it's really gone.
- Unreadable folders: show them as a line with "permission denied" instead of silently skipping.
- Scanning must be fast and show progress (files scanned, current path). Use concurrency where it helps. (Done: `getattrlistbulk`, up to 16 threads; `/Applications` with 124k files in < 1 s, totals equal to `du`.)
- Symlinks show their target (`Safari.app → ../System/Cryptexes/…`); the link itself is counted, never followed.
- A whole-volume scan gets a **"not scanned"** line: volume used − (scan + system volume), i.e. other APFS volumes (VM, Preboot, Recovery), snapshots and unreadable folders, so the top total matches "used".

### `taydic junk [category]`
Categories (no argument = all, grouped with totals per category):
- **orphans** — folders/plists in the `~/Library` locations whose bundle ID / name doesn't match any installed app. Always unchecked by default; mark confidence.
  - Only **bundle-ID-shaped** names count (`com.foo.bar`, `TEAMID.com.foo.bar`, `group.com.foo.bar`, ≥ 3 parts): plain names in `~/Library` are mostly macOS's own (`AddressBook`, `Knowledge`, `familycircled.plist`, …).
  - Never anything containing `com.apple`, nor Apple parts with other names (`org.cups`, `is.workflow` = Shortcuts, …).
  - Claimed (not an orphan): same bundle ID as an installed or running app, same vendor (`com.utmapp.*` next to UTM), or Spotlight (`mdfind kMDItemCFBundleIdentifier`) finds an app with that ID anywhere.
  - Confidence: **low** when one of his app names appears in it, else **high**.
  - **Own group "Orphans · cache folder"** (added 2026-10-21, Damba's idea): the same rules for the direct children of his cache folder in `/var/folders` (`Paths.userCacheFolder`, the `C` of `Paths.userTempFolders`), plus one more: nothing in it (the folder and everything inside, `fts`, symlinks not followed) changed for **21 days** (`orphanCacheDays`; first 30, Damba made it 21: short enough that "but I still used that" doesn't happen, long enough for the rest); a folder taydic can't read all of isn't offered. That keeps out caches of programs that aren't apps but still run (Prism Launcher's Java runtimes, `net.java.openjdk.java`, written the same day). The label gives the last change ("orphan, high confidence, last changed 2026-04-11"). Not `$TMPDIR` (live temp files: sockets, locks, half-done downloads; macOS clears old ones itself; only three empty Discord folders were there) and not `~/Library` itself (`org.swift.swiftpm` there is a tool's, no app's).
- **caches** — `~/Library/Caches/*`, `~/Library/Logs/*`, crash reports in `~/Library/Logs/DiagnosticReports` older than **30 days**. Apple's `com.apple.*` caches are left alone.
- **large** — in `~` (skip `~/Library`, `~/.Trash`, `.git`): files ≥ `--min-size` (default 1 GB), plus files ≥ 100 MB not used for `--older-than` days (default 180; "used" = later of last opened/changed). Packages (`.app`, `.photoslibrary`, `.utm`, `.sparsebundle`, …) count as one item and are never looked into. Grouped per top folder of `~` ("Large & old · Downloads"), biggest first, at most 100 (the rest is counted). Show last-used date.
- **dev** — Xcode `DerivedData`, `Archives` (unchecked: needed to symbolicate shipped builds), unavailable simulators (`xcrun simctl list` read-only; only UDIDs that are UUIDs), `node_modules` (next to `package.json`), `.build` (next to `Package.swift`), `target` (next to `Cargo.toml`) when the project wasn't changed for **60 days**, `__pycache__`, package-manager caches. Only if they exist.
  - Many items of one kind? Don't build nested groups (decided 2026-10-18: not worth the complexity). If Dev junk ever gets crowded, split it into top-level groups per kind ("Dev junk · node_modules", "Dev junk · Python caches", …), like "Large & old · Downloads".
  - Python virtual environments (any folder with a `pyvenv.cfg`) are never looked into; a project's venv is offered **whole** ("Python virtual environment") when the project wasn't changed for 60 days and has `pyproject.toml`, `requirements.txt`, `uv.lock`, `Pipfile` or `setup.py` next to it (otherwise it can't easily be set up again). `~/.local/share/uv` (uv's own Pythons and tools) is skipped entirely. So `__pycache__` only shows for his own code.
  - A venv is only offered when it holds nothing but venv parts (`bin`, `lib`, `include`, `share`, `etc`, `pyvenv.cfg`, `.gitignore`, `CACHEDIR.TAG`, …): after `python -m venv .` the venv is the folder with his code, and that's never offered.
  - Nothing in hidden folders directly in `~` counts as dev junk (`~/.vscode/extensions`, `~/.bun/install/global`, a tool's own venv in `~/.config/…`): tools keep their installs there, and a `node_modules` in there is part of an install that doesn't rebuild itself. Large files in there still count for **large**.
  - A folder named like a build folder that isn't one (a Maven project's `target` without `Cargo.toml`, a tool's own `node_modules`) is looked into for **large** files, and nothing in it counts as dev junk.

Review list grouped per category, with the same group-checkbox rules as `uninstall` (`[x]` all / `[~]` some / `[ ]` none). **Default selection:** Caches & logs and Dev junk are checked (apps regenerate them); Large & old and Orphans are unchecked (his own files / risk of false positives) — he ticks those himself. Then one `y/N` → Trash. Ticked **orphans** are asked about separately, like fuzzy matches: `y = all · o = one by one · N = none (Enter)`; in one-by-one mode an N keeps that item and goes back to that question for the rest.

### Review-list keys (shared by `uninstall`, `leftovers` and `junk`)
`↑`/`↓` move · `tab`/`⇧tab` next/previous group header (goes round at the ends; from an item, `⇧tab` goes to its own header first) · `/` search · `space` toggle item (or whole group when on its header) · `→` expand group · `←` collapse group (or jump to its header) · `a` toggle all items of the group the cursor is in (works on the header or on any item inside it; all → none → all) · `enter` continue to confirmation · `q`/`esc` cancel. No `n`/`y` keys in lists, so they never get confused with the `(y/N)` prompt. Groups start collapsed except small ones (≤ 5 items). Always show this key line at the bottom.

**Search (`/`):** type to filter on path, label or group name (case-insensitive); only groups with matches show, opened, with just the matching items; the status line shows `/term  N matches`. Enter (or ↑/↓/tab) keeps the results and returns to the keys above; Esc clears the search. With a search active, the first Esc clears it and a second one cancels. While searching, `space` on a header and `a` only touch the **matching** items — what you can't see never changes. Checks are kept when the search changes.

The uninstall app picker filters by just typing (no `/`), space selects, Enter continues (the highlighted one if nothing is selected), Esc cancels.

---

## Safety design (built into the tool)

- **One removal path:** everything that removes goes through `Remover.run` (the safety core). It first prints the whole plan — every path with size, grouped as *Move to the Trash* / *asked separately* (fuzzy matches, orphans) / *Needs sudo* / *Privacy permissions* / *Protected* / *Not found* — and only then asks, in this order: one `y/N` for the sure items → `y = all · o = one by one · N = none` for the doubtful ones → one `y/N` for sudo. Right after whichever of those moves an app with a privacy reset in the plan comes that reset's own `y/N` (see `uninstall`). `--dry-run` stops right after the plan.
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
  - **Standard folders themselves** (their contents may go, the folder may not): `/Applications`, `/Applications/Utilities`, `~/Applications`, `/Library`, `/Users/Shared`, `/Volumes`, `/opt`, `/opt/homebrew`, `/usr/local`, `/private`, `/private/tmp`, `/etc`, `/tmp`, `/var`; in `~`: `Desktop`, `Documents`, `Downloads`, `Movies`, `Music`, `Pictures`, `Public`, `Library`, `.config`, `.cache`, `.local` (+ `bin`, `share`, `state`); the `~/Library` and `/Library` scan locations listed under `uninstall` (`Caches`, `Application Support`, `Preferences`, `LaunchAgents`, …).
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

---

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

## Development & testing

- `swift test` runs everything (Swift Testing). Every test works on fixtures in `/tmp/tidy-test/<uuid>` (`Fixture` in `Tests/TidyCoreTests/Fixtures.swift`) with a fake home.
- **No test may ever reach the real Trash, sudo, launchctl, tccutil or brew.** The internal overloads of `Remover.run`, `Trash.move` and `BrewFlow.run` have **no defaults** on purpose: tests pass `fx.trash` (a fake Trash inside the fixture, which also refuses anything outside `/tmp/tidy-test`), `Transcript` (fake `ask`/`choose`/`sudo`/`launchctl`/`tccutil` that record and run nothing) and `FakeBrew`. Fixture `T/` and `C/` folders stand in for his temp and cache folders; the denylist exception is tested on real `/private/var/folders` paths that don't exist (names only, nothing moved). The two tests that use the real Trash only run with `TIDY_TRASH_TESTS=1` — ask Damba first. One moves two fixtures, the other one symlink: the link goes, what it points to stays (run 2026-10-19 with his OK, passed). (On 2026-10-18 a denylist bug, `/tmp` vs `/private/tmp`, made refusal tests move empty fixture folders into his real Trash; that's why.)
- Never run `tccutil` yourself, not even with a made-up bundle ID (hard rule 5); only taydic runs it, for Damba.
- To check the real Trash wasn't touched: `stat -f '%Sm' ~/.Trash` before and after (listing `~/.Trash` is blocked by privacy protection).
- TUI checks: `python3 -I scripts/drive_tui.py COLS ROWS STEPS… -- .build/debug/taydic …` runs it in a pseudo-terminal and prints screens (cursor row marked `>>`). Only with `--dry-run` or on fixtures, answering `n`.
- Don't scan Damba's whole home or disk from the agent (`junk large/dev/caches`, `disk` on `~`): macOS then shows privacy pop-ups for the Claude app. Give him the commands to run in his own Terminal instead. Reading names in `~/Library` and Spotlight (`junk orphans`) is fine.
- `taydic _plan PATH…` shows what taydic would do with any path, always as a dry run.
- From the agent, `uninstall`/`leftovers` dry-runs are fine for apps without a sandbox container (AppCleaner, `mozilla`): they read names in the Library folders and measure what matched. Measuring another app's container can make macOS ask the Claude app for access, so give Damba those commands instead.

## Code conventions

- Small files, one responsibility each (see the code map).
- No clever abstractions. No protocols with one implementation. No Linux shims.
- Human-readable sizes: decimal units like Finder (1 GB = 1,000,000,000 bytes).
- Errors: say what failed and on which path. Never crash on a permission error mid-scan.
- Colors: minimal and respect `NO_COLOR` (only when stdout is a terminal): `moved` and `quit` green, `FAILED` red, headers bold, folder lines dim. TidyCore prints plain text; `show` in the tidy target adds the colour. Output must also work when piped (no TUI when stdout isn't a TTY — fall back to plain lists for `junk`/`uninstall`, refuse `disk` with a clear message).

---

## Roadmap (build in this order, commit after each)

0. ✅ **Environment check** (read-only): `swift --version`, `xcode-select -p`, `which brew`. Report to Damba. Set up the SwiftPM package + git repo + `.gitignore` (`.build/`). Skeleton `tidy --help` / `--version`. (Swift 6.4, Command Line Tools only, no Xcode; brew at `/opt/homebrew`.)
1. ✅ **Safety core:** Trash wrapper, denylist, dry-run plumbing, y/N prompt, sudo-batch prompt (implemented, never executed by you), log. Tests on `/tmp/tidy-test/` fixtures.
2. ✅ **`tidy disk`:** volume picker, fast scanner, ncdu-style TUI browser.
3. ✅ **`tidy uninstall`** for `.app` bundles.
4. ✅ **Homebrew** support in `uninstall`.
5. ✅ **`tidy junk`:** caches → large → dev → orphans (orphans last; most risk of false positives).
6. ✅ **Main menu** (`tidy` without arguments).
7. ✅ **Release build + install** to `~/.local/bin` — ask first. Check that `~/.local/bin` is in his `PATH`; if not, tell him the line to add himself.
8. ✅ **Full code review, at max effort**, looking for anything that could remove the wrong thing — before Damba's first real uninstalls (AppCleaner first, then an App Store app he doesn't care about: the first real run of the sudo path).
   - Review done 2026-10-18: every file read, 12 findings. Fixes 1–6 are done, each with tests, checked by Damba with `--dry-run` (`.build/release/tidy`, not installed yet) and committed together:
     1. Case got past the denylist (`~/applications`, `~/.local/state/TIDY`) → the denylist ignores case, `normalize` takes the spelling from disk.
     2. `tidy uninstall <path>` took any folder for an app → only app bundles.
     3. Brew dotfiles of tools macOS also has (`zsh` → `~/.zshrc`) were leftovers → kept.
     4. Files of another app with a longer bundle ID (`com.google.Chrome.canary`) counted as Chrome's → left out.
     5. `node_modules` and venvs in tool folders (`~/.vscode/extensions`, `~/.bun`) were dev junk → nothing in hidden folders in `~`.
     6. An in-place venv (`python -m venv .`, his code inside) was offered whole → only plain venvs.
   - 2026-10-19: fixes 7–11 done, each with tests; 12 stays as it is (Damba's choice):
     7. `/private/var` and `/Library/Preferences/SystemConfiguration` are protected trees: `tidy disk` + sudo could move `/private/var/folders`, `/private/var/root`, the network settings.
     8. Typed-ahead input is flushed (`tcflush`) right before reading a `(y/N)`. Checked in a pseudo-terminal with a stand-in program: with it, an `x⏎` typed before the question is dropped; without it, it answered the question.
     9. `/System/Volumes/Data/X` maps to `/X` only inside a firmlink, else it keeps its full path (→ Protected). It used to show "Not found" (`macOS Install Data`) or point at the sealed `/home` symlink.
     10. `Trash.freeDestination` only takes a name `lstat` says isn't there; otherwise the sudo batch stops before anything is stopped or moved. A skipped `mv -n` says "was taken".
     11. The log escapes tab, newline and backslash; simulator UDIDs must be UUIDs before they go into a path.
     12. Root-owned items on another volume are still copied into `~/.Trash`: fine for Damba, it's rare.
   - Fixes 7–12 committed and pushed as `06c87b9` after Damba's test.
   - Renamed the command to `taydic` (2026-10-19, see "Naming" at the top): the product in `Package.swift`, every text the user sees, and the log in `~/.local/state/taydic`. The old log in `~/.local/state/tidy` stays where it is, protected.
   - Final review of all code in a fresh session, 2026-10-19: 10 findings. Damba: fix all of them except #8 (`taydic uninstall Foo.app` by name says "Nothing matches"; cosmetic, he never types it), in two halves.
     - Half 1, committed and pushed as `c695758` after Damba's test (the sudo prompt, Ctrl-C at it, a real sudo move of a fixture into `~/.Trash`, dry-runs of AppCleaner and uBlock Origin Lite): #5 sudo and `brew uninstall` could never ask in the terminal (see "Root-owned files": `Spawn`); #1 what a second copy or an app by the same name uses stays; #2 pkg files inside another app stay; #3 Apple's names only match by bundle ID; #4 `trashItem` on a symlink moves the link, not its target (real-Trash test, passed).
     - Half 2, committed and pushed after Damba's test (`junk dev`/`junk large` and AppCleaner dry-runs, `_plan` on a mounted Firefox .dmg → "read-only volume"): #6 Library locations taydic can't list are named ("Not searched"); #7 a read-only volume is Protected, not "needs sudo"; #9 `junk large` looks inside a `target`/`.build`/`node_modules` that isn't a build folder; #10 old `tidy` in comments.
   - Installed 2026-10-19 as `~/.local/bin/taydic`, version 0.2.0 (`b69db00`), checked with `cmp` and `~/.local/bin/taydic --version`. Damba added the PATH line to `~/.zprofile` (`which taydic` says `~/.local/bin/taydic`) and moved the old `~/.local/bin/tidy` (0.1.0) to the Trash with `taydic disk` itself, so `which tidy` is macOS's `/usr/bin/tidy` again.
   - **Commits (Damba's rule for this phase):** nothing is committed until he has tested it. Fixes 1–6: one commit (done); 7–12: the next (done); then the rename (done); then the final review's fixes, one commit per half, each pushed after his test (done).
   - Then the clearer output (per folder, colours, short FAILED reasons, his spacing rules; see "Safety design"), 0.2.1, and a README with logo and icon.
9. ✅ **`taydic leftovers <name>`** + menu option 4 (2026-10-20, Damba's idea, see its section above). Built with tests, checked for dangers (macOS's own apps, running apps and commands in the PATH count as still installed; vendor folders like `Application Support/Google` when an app has the name in its bundle ID → nothing ticked), dry-runs from the agent (`mozilla` found `~/Library/Caches/Mozilla` and the root-owned `/Library/Application Support/Mozilla`; `notes`, `discord`, `git` refused; `anthropic` warned about Claude and offered none of its files). Damba tested it (dry-runs, menu option 4, a real run for `mozilla` with sudo); committed as `9c61d7a`, installed as 0.3.0 (`7ca322d`), pushed.
10. ✅ **What the Roblox test found** (2026-10-21, Damba's request). He installed Roblox Player, played, diffed his disk (`find` before/after) and ran `taydic uninstall roblox`: 7 items (308 MB) right, but it missed `~/Library/Roblox`, `$TMPDIR/Roblox` (3,400 files, 323 MB), `$TMPDIR/com.roblox.RobloxPlayer`, the WebKit temp folders, and called `com.roblox.RobloxPlayerChannel.plist` fuzzy. Four fixes, in his order (see `uninstall` and "Safety design"): 1. `~/Library` itself as a strict location; 2. his temp and cache folders, with the `/private/var` exception and the WebKit names; 3. the bundle ID prefix match; 4. the privacy reset with `tccutil`. Built with tests (131), checked for dangers, agent dry-runs (`_plan` on `T`/`C` paths: items inside → Trash, `T`, `0/…`, `/var/folders` → Protected; `uninstall appcleaner godot` found the WebKit folders and caches in `C`, showed the privacy block; `leftovers roblox` found a 338 MB `$TMPDIR/Roblox` that was still there). Damba ran `leftovers roblox --dry-run` and `_plan "$TMPDIR" "$TMPDIR/Roblox"` himself, then chose: fuzzy in `T`/`C` only for names shaped like a bundle ID, never in `~/Library` itself (done, 131 tests; `leftovers roblox` now also lists `C/com.roblox.*` and `T/com.roblox.*` unticked). Damba's real run, 2026-10-21: `taydic leftovers roblox` moved `T/Roblox` (338 MB) and, after `y` to the fuzzy question, the five `com.roblox.*` items from `T` and `C` into `~/.Trash` (Finder shows them; the second `com.roblox.RobloxPlayer` got macOS's timestamp name, shown with `→` and in the log). No Roblox reinstall needed: Damba ran `taydic uninstall appcleaner` for real instead (2026-10-21). All 8 items moved (incl. the three `com.apple.WebKit.*+net.freemacsoft.AppCleaner` folders and the cache in `C`), and `tccutil reset All net.freemacsoft.AppCleaner` ran right before the app moved, without sudo, and worked: the system database's row (`/Library/Application Support/com.apple.TCC/TCC.db`, `kTCCServiceSystemPolicyAllFiles`, i.e. the Full Disk Access list) was there before and gone after (`sqlite3 -readonly …`, read by Damba; his own `~/Library/…/TCC.db` won't open, even with Full Disk Access). Two log lines looked broken in his terminal (`…AppCleane/Users/…`): a tab right at the last column of a 159-wide window; the file itself is fine (`cat -et`). Then, at his request, a `reset` line in the log for each privacy reset. Committed as `9c9c2ba`, installed as **1.0.0** (his choice: "the last step"), pushed.
    - After 1.0.0, Damba's idea: `junk orphans` also looks in the cache folder, in its own group (see `junk`). Agent dry-run: 16 caches of apps that are gone (Corsair iCUE, Among Us, Deezer, ChatGPT, Spotify, Zen, Firefox; ~33 MB), while Java, Word, Zed, DuckDuckGo and a Firefox helper (changed in the last 21 days) stayed out. 133 tests. Damba tested the dry-run in his Terminal: it found caches he thought were long gone (AppCleaner had left them).
    - Out of scope (his call): the Dock item (Roblox put itself in his Dock; taydic leaves `com.apple.dock` alone), login items (`sfltool` showed nothing left).

Nothing else is planned. Left open on purpose: #8 of the final review (`taydic uninstall Foo.app` by name says "Nothing matches"; he never types it), spotting protected app containers before the move (with Full Disk Access it doesn't happen to him), grouping the review list per folder too (the full paths help choosing), a license.

**Where things stand (2026-10-21):** phases 0–10 are done, every step tested by Damba and pushed. taydic **1.0.0** is installed as `~/.local/bin/taydic` and in his PATH, checked with `cmp` and `--version`; the old `tidy` 0.1.0 is gone. His terminal has Full Disk Access since 2026-10-19 (his choice).

His first real uninstalls, 2026-10-19, each twice (once with the old output, once with the new per-folder layout):
- **AppCleaner** (manual): the app plus its bundle-ID leftovers, all to the Trash without sudo. A name the Trash already had got macOS's timestamp suffix, shown with `→`.
- **DuckDuckGo** from the App Store (bundle ID `com.duckduckgo.mobile.ios`; Damba's choice instead of uBlock Origin Lite): quit while running (`NSRunningApplication.terminate`), leftovers, its two `…macos.browser.*` group containers as fuzzy matches (same team ID, asked separately), and the app with sudo. Without Full Disk Access, macOS refused to move its container (`~/Library/Containers/…`) although `access()` said writable: a safe FAILED with a short reason. With Full Disk Access everything moved.

Other real removals: `junk orphans` and `junk caches` (user-owned only): Trash, log and "Put Back" work. The sudo path also ran on a fixture in `/tmp/tidy-test` (password prompt, Ctrl-C at it, `sudo mv` into `~/.Trash`, " 2" for a taken name, the log), and `taydic leftovers mozilla` moved a root-owned `/Library/Application Support/Mozilla` with sudo (2026-10-20). `tccutil reset All` ran for real on AppCleaner (2026-10-21, worked without sudo). Never run for real yet: `launchctl bootout`, `brew uninstall`: watch the first time.

Stop and ask whenever a decision isn't covered here instead of guessing.
