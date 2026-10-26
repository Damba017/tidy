# Progress

Read this first, every session. Update it in max 5 lines after each completed plan step. When a phase is done, condense its entries to one summary line. Full history: `docs/history.md`.

## Last step

2026-10-26: Damba's real Roblox uninstall: 18 moved, 1 FAILED (`$TMPDIR/com.apple.WebKit.GPU+com.roblox.RobloxPlayer`, SIP flag `sunlnk`). The denylist now refuses `sunlnk` too; such items aren't in the list, a note after it names them ("Not in the list: protected by System Integrity Protection"). 134 tests. Damba tested the dry-runs (fake app in `/tmp/tidy-test/sip-demo`, `uninstall marktplaats`); committed and pushed (`44c29c1`). Installed as **1.1.1** (his choice), checked with `cmp` and `--version`.

## Next step

Wait for Damba's next idea, or for the Cleanup phase (`docs/plan.md`, phase 11).

## Open issues

- Left open on purpose: #8 of the final review (`taydic uninstall Foo.app` by name says "Nothing matches"), spotting protected app containers before the move, grouping the review list per folder, a license.
- Never run for real yet: `launchctl bootout`, `brew uninstall`. Watch the first time.

## Current state

taydic **1.1.1** (1.1.0 plus the `sunlnk` change) is installed as `~/.local/bin/taydic` (in his PATH). 134 tests. His Terminal has Full Disk Access since 2026-10-19; the Claude app doesn't.

## Finished phases (one line each)

- 0–7: package, safety core, `disk`, `uninstall` for apps and Homebrew, `junk`, main menu, first install.
- 8: two full code reviews (22 findings, fixed except the ones Damba left), rename to `taydic`, installed 0.2.0, first real uninstalls (AppCleaner, DuckDuckGo).
- 9: `taydic leftovers <name>` + menu option 4, installed as 0.3.0.
- 10: Roblox-test fixes (`~/Library` and temp/cache folders as strict locations, bundle ID prefix, privacy reset), orphans in the cache folder; installed as 1.0.0 and 1.1.0.
