# Progress

Read this first, every session. Update it in max 5 lines after each completed plan step. When a phase is done, condense its entries to one summary line. Full history: `docs/history.md`.

## Last step

2026-11-02 (later): `leftovers mozilla` offered `/Library/Application Support/Mozilla`, which is macOS's (Apple Passwords for Firefox, from its data template). The denylist now refuses every path macOS's data template installed (`pkgutil --files com.apple.files.data-template`, read once). 138 tests. Damba tested it (`leftovers mozilla` finds nothing now) and removed the empty Chrome and Spotify download folders.

2026-11-02: after his real Helium uninstall, leftovers are also searched in `~/Library/Caches/com.apple.nsurlsessiond/Downloads` (one folder per app, by bundle ID; rules of `T`/`C`), and that folder is a standard folder in the denylist. `X` and `0` stay alone (his choice; see `docs/history.md`). 137 tests. Damba tested it: `leftovers helium` (fuzzy) and a real `uninstall helium` (5 moved, the new folder too; only `X` left). Committed, installed as **1.1.2** (his choice), checked with `cmp` and `--version`, pushed.

## Next step

Damba tests the macOS-template rule (`leftovers mozilla --dry-run`, `_plan`), and removes the empty Chrome and Spotify download folders with `taydic leftovers`. Then commit; install and push only when he asks.

## Open issues

- Left open on purpose: #8 of the final review (`taydic uninstall Foo.app` by name says "Nothing matches"), spotting protected app containers before the move, grouping the review list per folder, a license.
- Never run for real yet: `launchctl bootout`. Watch the first time. (`brew uninstall --cask` ran for real on 2026-11-02, Helium: worked.)

## Current state

taydic **1.1.2** (1.1.1 plus nsurlsessiond's download folder) is installed as `~/.local/bin/taydic` (in his PATH). 137 tests. His Terminal has Full Disk Access since 2026-10-19; the Claude app doesn't.

## Finished phases (one line each)

- 0–7: package, safety core, `disk`, `uninstall` for apps and Homebrew, `junk`, main menu, first install.
- 8: two full code reviews (22 findings, fixed except the ones Damba left), rename to `taydic`, installed 0.2.0, first real uninstalls (AppCleaner, DuckDuckGo).
- 9: `taydic leftovers <name>` + menu option 4, installed as 0.3.0.
- 10: Roblox-test fixes (`~/Library` and temp/cache folders as strict locations, bundle ID prefix, privacy reset), orphans in the cache folder; installed as 1.0.0 and 1.1.0.
