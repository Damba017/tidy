# Plan

Phases in build order, each small enough for one session. Read only the current phase. Status and next step: `docs/progress.md`. Full details of finished phases: `docs/history.md`.

Model, effort and plan mode are only noted for phases that aren't started yet. The finished phases were built before this format and their models weren't recorded.

## Phases 0–10 — all done ✅

0. ✅ **Environment check** (read-only): `swift --version`, `xcode-select -p`, `which brew`. SwiftPM package + git repo + `.gitignore`. Skeleton `tidy --help` / `--version`. (Swift 6.4, Command Line Tools only, no Xcode; brew at `/opt/homebrew`.)
1. ✅ **Safety core:** Trash wrapper, denylist, dry-run plumbing, y/N prompt, sudo-batch prompt (implemented, never executed by the agent), log. Tests on `/tmp/tidy-test/` fixtures.
2. ✅ **`taydic disk`:** volume picker, fast scanner, ncdu-style TUI browser.
3. ✅ **`taydic uninstall`** for `.app` bundles.
4. ✅ **Homebrew** support in `uninstall`.
5. ✅ **`taydic junk`:** caches → large → dev → orphans (orphans last; most risk of false positives).
6. ✅ **Main menu** (`taydic` without arguments).
7. ✅ **Release build + install** to `~/.local/bin` — ask first. Check that `~/.local/bin` is in his `PATH`; if not, tell him the line to add himself.
8. ✅ **Full code review, at max effort**, looking for anything that could remove the wrong thing, before Damba's first real uninstalls. Two reviews (2026-10-18 and 2026-10-19), 12 + 10 findings, all fixed except the ones Damba chose to leave; renamed to `taydic`; installed 0.2.0. Per-finding details: `docs/history.md`.
9. ✅ **`taydic leftovers <name>`** + menu option 4 (2026-10-20, Damba's idea). Installed as 0.3.0.
10. ✅ **What the Roblox test found** (2026-10-21): `~/Library` itself and the temp/cache folders as strict locations, the bundle ID prefix match, the privacy reset with `tccutil`; then orphans in the cache folder. Installed as 1.0.0 and 1.1.0.

## Phase 11 — Cleanup (not started)

Only when Damba says the project is finished or abandoned.

- Model: not chosen yet (no `/model` list was given for this project; pick when the phase starts).
- Effort: low. Plan mode: not needed.
- Remove dev-only tools listed in docs/tools.md. Ask per tool if it's still needed to run the project. First give the user the full list of commands and explain what each command and flag does. Run nothing until he approves.

## Not planned (left open on purpose)

Nothing else is planned. Left open: #8 of the final review (`taydic uninstall Foo.app` by name says "Nothing matches"; he never types it), spotting protected app containers before the move (with Full Disk Access it doesn't happen to him), grouping the review list per folder too (the full paths help choosing), a license.

Out of scope (his call): the Dock item (Roblox put itself in his Dock; taydic leaves `com.apple.dock` alone), login items (`sfltool` showed nothing left).
