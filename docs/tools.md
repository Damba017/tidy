# Tools

Every tool, config line or permission this project depends on or added to the Mac. Log new ones here the moment Damba confirms an install: name, how it was installed, how to remove it, what stays behind, and whether it's dev-only. Nothing here may be removed without asking Damba first (see the Cleanup phase in `docs/plan.md`).

Checked on 2026-10-21 (read-only): `swift` and `python3` are in `/usr/bin`, `brew` in `/opt/homebrew/bin`, Swift 6.4, `xcode-select -p` = `/Library/Developer/CommandLineTools`.

## Swift toolchain (Xcode Command Line Tools)

- **Installed:** Command Line Tools only, no Xcode. Installed before this project was written down; how exactly isn't recorded.
- **Uninstall:** not run and not checked. Apple's usual way is deleting `/Library/Developer/CommandLineTools` (needs sudo, so only Damba runs it). Verify before trusting this.
- **Left behind:** not checked.
- **Needed for:** building and testing (`swift build`, `swift test`). Dev-only: the built `taydic` binary doesn't need it (not verified).

## python3 (`/usr/bin/python3`)

- **Installed:** ships with macOS / the Command Line Tools. Not installed by this project.
- **Uninstall:** n/a.
- **Used for:** `scripts/drive_tui.py` only (TUI checks in a pseudo-terminal, run with `python3 -I`). Dev-only.

## Homebrew (`/opt/homebrew`)

- **Installed:** already on the Mac before this project. Not installed by it.
- **Uninstall:** Homebrew's own uninstall script; not run, not needed.
- **Used for:** `taydic uninstall` on brew packages. The agent only runs read-only queries (`brew list`, `brew info --json`, `brew --prefix`). Needed at runtime for the brew features only.

## taydic itself (`~/.local/bin/taydic`)

- **Installed:** `cp .build/release/taydic ~/.local/bin/taydic` after Damba's yes, checked with `cmp` and `taydic --version` (procedure: "Stack, build and install" in `docs/rules.md`). Version: ask `taydic --version` (1.1.0 on 2026-10-21).
- **Uninstall:** move `~/.local/bin/taydic` to the Trash (Finder, or `taydic disk`). No `rm`.
- **Left behind:** the log `~/.local/state/taydic/log` and the old log `~/.local/state/tidy/log`. Keep them: they're the only way to find where sudo-moved items went in the Trash.
- **Needed for:** this is the product.

## Config changes on the Mac (made by Damba himself)

- **PATH line in `~/.zprofile`:** `export PATH="$HOME/.local/bin:$PATH"`, added 2026-10-19. Remove by deleting that line. Needed to run `taydic` by name.
- **Full Disk Access for Damba's Terminal**, granted 2026-10-19 (System Settings → Privacy & Security → Full Disk Access). Remove there. Needed so `taydic` can see all of `~/Library`; without it some items show as "Not searched".
