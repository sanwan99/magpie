# Contributing to Magpie

欢迎贡献。中文或英文 Issue / PR 均可。Please keep contributions focused,
reviewable, and accompanied by evidence of the behavior you changed.

## Scope and principles

- Native macOS: SwiftUI, AppKit, Carbon hotkeys, GRDB and SQLite. No Electron/Tauri rewrite.
- Local-first. No telemetry, account system or implicit content upload. System translation,
  language downloads and explicitly chosen sharing services must remain visible to users.
- Preserve existing shortcuts, layouts, themes, screenshots and user data unless the change
  explicitly discusses compatibility. Optional global rebinding keeps Cmd-P/J as defaults.
- Never log clip/snippet bodies, titles, paths, search queries or raw provider/SQL errors.
  Use fixed events and `DiagnosticLog.failure` numeric codes.
- Historical prototypes are design references, not evidence that a feature is implemented.

## Setup

Runtime target is macOS 14; build and all tests require full Xcode 26+ and the macOS 26 SDK.
Check `xcodebuild -version`. The committed Xcode project works without XcodeGen.

```bash
git clone https://github.com/sanwan99/magpie.git
cd magpie
git switch -c fix/your-change
Scripts/build-local.sh
Scripts/test.sh
python3 -m unittest discover -s Tests/Tooling -v
python3 Scripts/check-privacy-logs.py
python3 Scripts/check-doc-links.py
```

Source builds default to ad-hoc signing. A stable personal signing identity is optional
(`MAGPIE_CODE_SIGN_IDENTITY`); never commit its private key, certificate or passwords.
`python3 Scripts/setup-local-signing.py --create` explicitly changes your local keychain and is not a CI
or end-user prerequisite. `install-release.sh` installs already signed public apps;
`install-app.py --local-build` is the explicit local developer path.

`project.yml` is the source of truth. If you change it, run `xcodegen generate` and
commit the resulting project together. Do not use a repository `build/` directory
for DerivedData: launchers may discover stale duplicate application bundles.

## Structure and boundaries

| Directory | Responsibility |
| --- | --- |
| `Sources/Magpie/Clipboard` | Main-thread pasteboard snapshot; serial background filtering and ingestion |
| `Sources/Magpie/Storage` | Versioned migrations, repositories, transactional clip/FTS writes |
| `Sources/Magpie/Privacy` | Best-effort secret heuristics, system authentication, safe diagnostics |
| `Sources/Magpie/Image`, `History` | Managed PNG lifecycle and retention |
| `Sources/Magpie/Paste`, `Hotkey` | Focus-safe paste and Carbon registrations/lifecycle |
| `Sources/Magpie/Screenshot` | Native capture, editor model, rendering, OCR and result windows |
| `Sources/Magpie/Panel`, `UI`, `Settings`, `Theme` | AppKit window orchestration and SwiftUI interface |
| `Tests/MagpieTests` | XCTest behavior and integration tests |
| `Tests/Tooling` | Installer transaction, source-log and SQL checks using Python standard library |
| `docs` | Public design decisions, performance, review and release records |

## Data changes

Add migrations; never rewrite an already shipped migration or recreate a user's database.
Use `Database.makeInMemoryForTests()` or a unique temporary file. Image cleanup tests
must inject their own temporary directory, never sweep the real image cache. For old
schema fixtures use `Database.migrate(_:upTo:)`, reopen with the current migrations and
assert content, pins, notes, snippets, search results and repeatability.

PNG creation/commit and history cleanup share `Database.withStorageLock`. Acquire it
before `dbQueue`, release it before any `await`, and do not invert the order. Never
remove a file solely because a payload contains its path. Only managed, non-symlink
PNG files may be swept. File/folder clips refer to user originals.

## Tests and performance

Run the entire XCTest target. Do not delete, filter out or silently skip a failing test.
The existing live Screen Recording and installed-language tests have environmental
preconditions; retain their skip reasons and run them manually on an authorized Mac.
CI does not have Touch ID or a production Developer ID identity.

Performance work needs a reproducible fixture and measurements before and after.
`Scripts/benchmark-storage.py` measures SQLite queries, not UI responsiveness;
`RepositoryPerformanceTests` exercises GRDB at 1k/10k/50k rows. See [PERFORMANCE.md](docs/PERFORMANCE.md).
Use Instruments for main-thread stalls and image peak memory. Do not infer FPS or memory
improvements from SQL timings.

Use cancellation/generation checks for UI tasks. Distinguish a suppressed result from
work actually cancelled. Keep file/image decoding off the main actor where the API allows.

## PRs

Use Conventional Commits and the PR template. State the problem, changed behavior,
compatibility, verification results and remaining limits. Include screenshots when
changing appearance, using synthetic content. Discuss broad product changes in an Issue
before implementation. The maintainer decides merge and release; a green CI run alone
is not a signing/notarization or manual-acceptance approval.

Report vulnerabilities according to [SECURITY.md](SECURITY.md), without real credentials.
All contributions use the repository's [MIT license](LICENSE); identify the origin and
license of any new assets or dependencies.
