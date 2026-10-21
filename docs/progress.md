# Progress

Read this first, every session. Update it in max 5 lines after each completed plan step. When a phase is done, condense its entries to one summary line. Full history: `docs/history.md`.

## Last step

2026-10-21: moved the 323-line `CLAUDE.md` into `docs/` (goal, plan, rules, progress, history, tools). `CLAUDE.md` is now ≤ 40 lines. Nothing lost, only moved. Not committed yet: waiting for Damba to look at it.

## Next step

Nothing planned. Wait for Damba's next idea, or for the Cleanup phase (`docs/plan.md`, phase 11).

## Open issues

- Left open on purpose: #8 of the final review (`taydic uninstall Foo.app` by name says "Nothing matches"), spotting protected app containers before the move, grouping the review list per folder, a license.
- Never run for real yet: `launchctl bootout`, `brew uninstall`. Watch the first time.

## Current state

taydic **1.1.0** is installed as `~/.local/bin/taydic` (in his PATH), 133 tests, all pushed up to `940630a`. His Terminal has Full Disk Access since 2026-10-19; the Claude app doesn't.

## Finished phases (one line each)

- 0–7: package, safety core, `disk`, `uninstall` for apps and Homebrew, `junk`, main menu, first install.
- 8: two full code reviews (22 findings, fixed except the ones Damba left), rename to `taydic`, installed 0.2.0, first real uninstalls (AppCleaner, DuckDuckGo).
- 9: `taydic leftovers <name>` + menu option 4, installed as 0.3.0.
- 10: Roblox-test fixes (`~/Library` and temp/cache folders as strict locations, bundle ID prefix, privacy reset), orphans in the cache folder; installed as 1.0.0 and 1.1.0.
