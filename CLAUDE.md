# tidy

`taydic` (project name: tidy): macOS-only Swift command-line tool that uninstalls apps with their leftovers, browses disk usage and finds junk. Built for one user (Damba). KISS.
Stack: Swift + SwiftPM, Command Line Tools only, zero dependencies. Build: `swift build -c release`. Test: `swift test`.

## Rules
- Always respond to the user in Dutch. Keep all code, comments and docs in English.
- Never commit secrets, API keys or tokens. Keep them in .env and make sure .env and .DS_Store are in .gitignore.
- Never guess. If you're unsure or stuck, stop and ask the user.
- Never run sudo, not to build, test or fix anything. (taydic itself may use it at runtime; you never run that path for real.)
- Never install tools, packages, SDKs or dependencies (Homebrew, pip, npm, curl | sh, anything outside the project folder) without asking first and getting a clear yes. Give the exact command, explain what each command and flag does, then log it in docs/tools.md with how to remove it.
- Show commands complete and copy-pasteable, each in its own block, with what it does and what every flag means.
- If you notice outdated or unused files, code, docs entries or dependencies, list them and ask the user before removing anything.
- Never delete or move real user files while developing: real apps and folders only with `--dry-run`, destructive tests only on fixtures in /tmp/tidy-test/.
- Never run commands that change state outside the project: brew install/uninstall, launchctl, tccutil, system settings, permissions. Read-only queries are fine.
- Zero external dependencies: Swift standard library and Apple frameworks only. Need a package? Stop and ask.

## Workflow
- After each completed plan step, update docs/progress.md in max 5 lines.
- When a phase is done: condense its entries in docs/progress.md to one summary line, then remind the user to run /clear before the next phase.
- Per change: code → tests → check for anything that could remove the wrong thing → Damba tests with dry-runs → commit. Details: docs/rules.md.

## Git
- Commit locally only after Damba has tested the change, with a clear English message. Push only when he explicitly asks, every time. Never force-push, rewrite history or add remotes. Remote and details: docs/rules.md.

## Docs
- At the start of every session, read docs/progress.md first, then only the current phase in docs/plan.md.
- Every .md file in docs/ must be listed below with when to read it. If you create a new one, add it here.
- docs/progress.md — read first, every session: last step, next step, open issues.
- docs/plan.md — read the current phase before starting work.
- docs/goal.md — read before changing how a command behaves (full spec of every command).
- docs/rules.md — read before writing or changing code or running anything: safety design, conventions, tests, build/install, code map.
- docs/tools.md — read before installing or removing anything; log every install here.
- docs/history.md — read only for the why behind past decisions and real-run results.
- Keep this file at 40 lines or fewer: put detail in docs/, not here.
