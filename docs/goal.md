# Goal

What taydic is and how every command must behave. How it is built and what it may never do: `docs/rules.md`.

## End goal

A macOS command-line tool that combines four things:

1. **AppCleaner** — fully uninstall an app (or a Homebrew package) *and* everything it left behind.
2. **DaisyDisk** — an interactive disk-usage browser for any mounted volume.
3. **Junk finder** — find orphaned app files, caches/logs, large/old files and developer junk.
4. **Leftovers finder** — what an app that's already gone (removed before taydic existed) left behind, by its name.

Built for one user (Damba) on one machine: MacBook Air M4, latest macOS. **macOS only.** Do not add Linux/Arch support, abstractions for it, or `#if os(Linux)` branches.

Philosophy: KISS. Powerful, not pretty. Every feature must earn its place.

**Naming:** the command you run is **`taydic`** ("taydi cleaner"; renamed 2026-10-19 because macOS ships its own `/usr/bin/tidy`, HTML Tidy). The project is still called tidy: the folder `~/tidy`, the `TidyCore` module, the `tidy` executable target and the GitHub repo.

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
   - Leftovers System Integrity Protection keeps where they are (the `restricted` or `sunlnk` flag, e.g. `com.apple.WebKit.GPU+<bundle ID>` in his temp folder) are not offered either; they're named right before that note: "Not in the list: protected by System Integrity Protection, nothing can move these:" (added 2026-10-26). The brew flow, which has no review list, shows them in its plan under *Protected*.
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
