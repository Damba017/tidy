# taydic

A macOS command-line tool that keeps a Mac tidy, in three parts:

- **Uninstall** an app or a Homebrew package *and* everything it left behind (like AppCleaner).
- **Browse disk usage** of any volume, folder by folder, biggest first (like DaisyDisk or ncdu).
- **Find junk**: caches and logs, leftovers of apps that are long gone, large and old files, developer junk.

Nothing is ever deleted. Everything goes to the Trash, and only after you've seen exactly what will happen and said yes.

> Built for one person's Mac (Apple silicon, latest macOS) and used there. It should work on any recent Mac,
> but it's a personal tool: read what it shows you before you answer `y`.

The project is called *tidy*; the command is `taydic` ("taydi cleaner") because macOS already has a `/usr/bin/tidy` (HTML Tidy).

## Safety first

- **Plan first, then questions.** taydic always prints the full plan first: every path, its size and what will happen to it. Only then does it ask. `--dry-run` stops right after the plan and changes nothing.
- **Default is No.** Every question is `(y/N)`: Enter means no, and only `y` or `yes` counts. There is no `--yes`, and input that isn't a terminal answers no.
- **Doubtful items are asked about separately.** Fuzzy name matches and orphans never go along on the same `y` as the sure items: `y = all · o = one by one · N = none`.
- **Everything goes to the Trash**, never deleted. Items that need administrator rights are moved with `sudo mv` after one explicit question, and the log says where they came from.
- **A denylist** keeps taydic away from macOS itself and from what matters most, whatever the matching says: `/System`, `/usr`, `/private/var`, keychains, Mail, Messages, iCloud Drive, your Photos library, `~/.ssh`, your home folder and the standard folders themselves, mount points, anything SIP-protected. It's checked when the plan is made and again right before every move.
- **A log** of every move: `~/.local/state/taydic/log` (time, what, size, where it went in the Trash, whether sudo was used).

## Requirements

- macOS 15 or later.
- Swift 6 to build it: the Xcode Command Line Tools are enough (`xcode-select --install`) or full Xcode.
- Homebrew is optional. When it's installed (in `/opt/homebrew`, the Apple silicon location), `taydic uninstall` handles formulae and casks too.
- No other dependencies: only Swift's standard library and Apple's frameworks.

## Install

```bash
git clone https://github.com/Damba017/tidy.git
cd tidy
swift build -c release
mkdir -p ~/.local/bin
cp .build/release/taydic ~/.local/bin/taydic
```

If `~/.local/bin` isn't in your `PATH` yet, add it once and open a new terminal:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
```

Then check:

```bash
taydic --version
```

To update later: `git pull`, build again and copy the binary over the old one.

## Usage

```
taydic                       Main menu
taydic uninstall [name...]   Uninstall apps/brew packages and their leftovers
taydic disk [path]           Disk-usage browser
taydic junk [category]       Find junk: orphans | caches | large | dev
taydic --help, -h            Show this help
taydic --version             Show version

Options:
  --dry-run                  Show exactly what would happen. Never touches anything.
  --min-size SIZE            junk large: files at least this big (default 1GB; e.g. 500MB, 2GB)
  --older-than DAYS          junk large: also files from 100MB unused this long (default 180)
```

Try anything with `--dry-run` first:

```bash
taydic uninstall appcleaner --dry-run
taydic junk caches --dry-run
```

### `taydic uninstall`

Give one or more names (`taydic uninstall discord firefox fastfetch`), or none for a list of everything installed: type to filter, space to select, Enter to continue.

- It finds `.app` bundles in `/Applications`, `/Applications/Utilities` and `~/Applications`, and Homebrew formulae and casks. A cask's app is one item, removed through `brew`.
- Leftovers are found by bundle ID, by name and, unticked and asked about separately, by fuzzy name match, in the usual `~/Library` and `/Library` folders and in `.pkg` receipts. What another installed app also uses (a second copy, a beta with the same bundle ID, an app by the same name) stays.
- A running app is quit first (like ⌘Q), after you say yes.
- Homebrew packages are removed with `brew uninstall` (after a yes); their leftovers (`~/.config/<name>`, `~/.cache/<name>`, …) go to the Trash.

### `taydic disk`

Pick a volume (or give a folder) and browse it, biggest first: Enter opens a folder, ← goes back, `/` searches, `d` moves the selected item to the Trash (after the plan and a `y`), `o` shows it in Finder, `?` lists all keys. Sizes are the space actually used on disk; hard links count once.

### `taydic junk`

- **caches**: everything in `~/Library/Caches` and `~/Library/Logs` (not Apple's `com.apple.*` ones), and crash reports older than 30 days.
- **dev**: Xcode DerivedData, package-manager caches, unavailable simulators, and `node_modules`, `.build`, `target` and Python virtual environments of projects you haven't touched for 60 days.
- **large**: big files in your home folder, and medium ones you haven't used for a long time. Never ticked for you.
- **orphans**: `~/Library` folders and preferences of apps that are no longer installed. Never ticked for you, and asked about separately.

## Permissions

macOS privacy protection keeps some folders (like `~/Library/Cookies`, or other apps' containers) out of reach of your terminal. taydic tells you what it couldn't see or touch, and how to let it in: *System Settings → Privacy & Security → Full Disk Access → add your terminal app*. That's your choice: without it, taydic just does less.

## Development

```bash
swift build
swift test
```

All tests work on fixtures in `/tmp/tidy-test` with a fake home and a fake Trash; none of them touches your real Trash, sudo, launchctl or Homebrew. Two tests that do use the real Trash (with tiny test files only) run only with `TIDY_TRASH_TESTS=1`.

The code is split into `Sources/TidyCore` (all the logic, testable without a terminal) and `Sources/tidy` (arguments, prompts and the terminal UI). `Remover.swift` is the only place that removes anything.
