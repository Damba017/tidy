# Progress

Read this first, every session. Update it in max 5 lines after each completed plan step. When a phase is done, condense its entries to one summary line. Full history: `docs/history.md`.

## Last step

2026-11-02 (night): his Zen uninstall missed `~/Library/Caches/Mozilla/updates/Applications/Zen` (four levels deep; the cask's zap list has it). Now, when the answer to `--zap` is No (and in `--dry-run`), the brew flow reads the cask's zap list (`ZapList.swift`) and offers what exists: sure only in a Library folder and named after the app, the rest asked separately with the fuzzy ones; no `rmdir` (his choice). 146 tests. Damba tested the dry-runs: `zen` (the Mozilla folder, noted), `vscodium` (`com.vscodium.sfl4` ticked, `~/.vscode-oss` 327 MB asked separately). Committed (`f0534fa`), installed as **1.2.0** (his choice), checked with `cmp` and `--version`, pushed. Small gap: without Full Disk Access, zap paths in protected folders are silently not found.

2026-11-02 (later): `leftovers mozilla` offered `/Library/Application Support/Mozilla`, which is macOS's (Apple Passwords for Firefox, from its data template). The denylist now refuses every path macOS's data template installed (`pkgutil --files com.apple.files.data-template`, read once). 138 tests. Damba tested it (`leftovers mozilla` finds nothing now) and removed the empty Chrome and Spotify download folders. Committed (`e2d150b`), installed as **1.1.3** (his choice), checked with `cmp` and `--version`, pushed.

2026-11-02: after his real Helium uninstall, leftovers are also searched in `~/Library/Caches/com.apple.nsurlsessiond/Downloads` (one folder per app, by bundle ID; rules of `T`/`C`), and that folder is a standard folder in the denylist. `X` and `0` stay alone (his choice; see `docs/history.md`). 137 tests. Damba tested it: `leftovers helium` (fuzzy) and a real `uninstall helium` (5 moved, the new folder too; only `X` left). Committed, installed as **1.1.2** (his choice), checked with `cmp` and `--version`, pushed.

## Next step

His next idea, or the Cleanup phase (`docs/plan.md`, phase 11).

## Open issues

- Left open on purpose: #8 of the final review (`taydic uninstall Foo.app` by name says "Nothing matches"), spotting protected app containers before the move, grouping the review list per folder, a license.
- Never run for real yet: `launchctl bootout`. Watch the first time. (`brew uninstall --cask` ran for real on 2026-11-02, Helium: worked.)

## Current state

taydic **1.2.0** (1.1.3 plus the cask's zap list in the brew flow) is installed as `~/.local/bin/taydic` (in his PATH). 146 tests. His Terminal has Full Disk Access since 2026-10-19; the Claude app doesn't.

## Finished phases (one line each)

- 0–7: package, safety core, `disk`, `uninstall` for apps and Homebrew, `junk`, main menu, first install.
- 8: two full code reviews (22 findings, fixed except the ones Damba left), rename to `taydic`, installed 0.2.0, first real uninstalls (AppCleaner, DuckDuckGo).
- 9: `taydic leftovers <name>` + menu option 4, installed as 0.3.0.
- 10: Roblox-test fixes (`~/Library` and temp/cache folders as strict locations, bundle ID prefix, privacy reset), orphans in the cache folder; installed as 1.0.0 and 1.1.0.
