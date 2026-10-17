# Repository guidance

Magpie is a native, local-first macOS clipboard and screenshot application, currently
Source Alpha. Current source and tests define implemented behavior; historical prototypes
and old notes may be stale. No private notes repository is required for contribution.

## Read first

Read README.md / README_EN.md, CONTRIBUTING.md, SECURITY.md, project.yml and the relevant
source and tests before editing. Public decisions live in `docs/decisions/`; review and
acceptance records live in `docs/`. `prototype/` is visual/interaction reference only;
do not implement new features there. Document intentional interaction deviations.

## Engineering rules

- Keep SwiftUI + AppKit + GRDB + SQLite; no Tauri/Electron or unnecessary dependencies.
- Runtime macOS 14+, full Xcode 26+ for current builds/tests. Project source of truth is
  `project.yml`; commit regenerated Xcode project changes alongside it.
- Preserve existing features, default Cmd-P/J shortcuts, themes, screenshot tools and data.
- Use additive migrations and old-database regression fixtures. Never destroy user data to
  make migration tests pass. Do not log content or raw error descriptions.
- UI state is MainActor-isolated; expensive work belongs off that actor. Check cancellation
  and stale results. Do not await while holding the storage lock or invert lock/DB ordering.
- Test databases and image directories must be isolated from real user storage.
- Use small, evidence-backed refactors; prefer descriptive names and comments explaining why.
- Keep diagnostic/source checks and actual execution results distinct. A Linux source review
  cannot stand in for Xcode, XCTest, TCC, Gatekeeper or Touch ID acceptance.

## Commands

```bash
Scripts/build-local.sh
Scripts/test.sh
python3 -m unittest discover -s Tests/Tooling -v
python3 Scripts/check-privacy-logs.py
python3 Scripts/check-doc-links.py
python3 Scripts/benchmark-storage.py
```

Poll long-running tools with short waits and communicate progress; do not hide failing or
skipped tests. Keep complete native `.xcresult` evidence. Developer certificate setup is
optional and must never be a CI or public-install prerequisite.

## Collaboration and changes

Communicate in Chinese when working with the maintainer. Quote paths containing spaces
or Chinese characters. Use Conventional Commits with behavior and verification details.
Work on a separate branch; do not directly commit to main. Push only within the user's
authorized scope. Obtain explicit authorization for merges, releases, visibility changes,
destructive data operations, prototype changes, dependency major upgrades, production API
calls or global tool installation/removal. Do not publish secrets, personal paths or keys.
Keep valuable development conventions when updating stale documentation.
