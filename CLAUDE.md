# Claude Code guidance

Read and follow [AGENTS.md](AGENTS.md), which is the shared repository engineering guide.

Magpie is Source Alpha with an existing SwiftUI/AppKit Xcode project, GRDB/SQLite storage,
Carbon hotkeys and a native screenshot editor. It is not a v0.1 skeleton. No private notes
checkout is needed. Use current source and tests over historical prototype claims.

Start with [README.md](README.md), [CONTRIBUTING.md](CONTRIBUTING.md),
[SECURITY.md](SECURITY.md) and `project.yml`. Keep changes on an authorized working branch,
use the shared build/test scripts, preserve data with migrations, and report native checks
that could not run. Do not introduce content-level logs or require personal certificates
for CI. Never merge, publish a Release, change visibility or remove user data without
explicit authorization.
