# Alpha usability follow-up — 2026-10-18

Base: `035efdd2270be1313ee892d7185c969076b8aa0e`.
Branch: `fix/open-source-readiness-20261018`. No merge, tag or publication.

## Implemented

- Menu-bar recording pause for 15 minutes / 1 hour, explicit resume, persisted deadline,
  pause status icon/tooltip, automatic expiry on polling/wake. Capture is gated before
  content reads, including screenshot history ingestion. Resume discards paused contents;
  queued snapshots are invalidated. Already executing writes may finish; history is retained.
- Quick ignore of the app identified when the menu opens, with unavailable/already-ignored
  states. All ignored-app/heuristic setting changes invalidate queued ingestion synchronously.
- Chinese/English first-run guide, persistent completion and menu-bar reopening. Explain
  unencrypted storage and optional permissions before requesting Accessibility explicitly.
  Removed the automatic startup permission prompt.
- Nonactivating, content-free paste feedback for missing permission/target/window, changed
  focus, replaced clipboard, unavailable events and failed clipboard writes. Superseded
  requests stay silent. Never suggest pasting the old record after clipboard replacement.
  Allocate all key events before posting any; preserve existing focus validation/Queue Mode.
- Local DMG packaging tool for an already signed, notarized, stapled app; explicit team
  verification, staged-copy verification, Applications link, hdiutil verification, checksum,
  no-clobber atomic file publication. No automatic signing, notarization or Release creation.
- [P2 encryption and recovery design](../decisions/0004-encrypted-storage-design.md), explicitly unimplemented; no dependency or storage-format change.
- Synthetic 4K and 40MP rendering/PNG baseline test with decoded-dimension checks and scoped
  autorelease pools. No UI/RSS speedup claim or speculative rendering rewrite.

## Verification

Validated source commit: `035920122a1b6f21b693ded5c05ebaee3172a783`.
[macOS CI run 39054745870](https://github.com/sanwan99/magpie/actions/runs/39054745870)
completed successfully on macOS 15.7.9 arm64 / Xcode 26.0.1.

- XCTest: **219 total, 216 passed, 0 failed, 3 skipped**.
- Skips retain their existing requirements: Screen Recording for live frame/scroll capture
  (two tests), and macOS 26 plus installed language support for live translation (one test).
- Release configuration build: passed with local ad-hoc signing.
- Python tooling: **32 passed, 0 failed, 0 skipped**, both Linux and macOS.
- Real macOS DMG smoke test: passed (ad-hoc fixture only, not public distribution acceptance).
- Privacy-log guard, Markdown internal-link checks and `git diff --check`: passed.
- [Complete xcresult artifact](https://github.com/sanwan99/magpie/actions/runs/39054745870/artifacts/12109705181);
  archive SHA-256 `7c8242c6855b3958ecf65dfe92172f321ac0ea364e5564a6c3f969c76164c711`.
- [Native image measurements](native-image-benchmark.json): final run 4K/40MP render
  7.090/286.834 ms; AppKit PNG 58.314/305.250 ms; ImageIO PNG 56.898/283.708 ms.
  Two runs show substantial variation; no production speedup or encoder replacement claimed.

Added native cases for pause expiry/restart/sleep/no-replay, queued writes, settings policy
changes, first-run completion, paste-recovery decisions, nonactivating notice and screenshot baselines.
Existing tests and environmental skip conditions remain intact.
The earlier run 39054458269 passed 218 XCTest (215 passed, 3 skipped) and was automatically
superseded during Release build after adding the native smoke/focus tests. Final acceptance
uses the complete successful run above. The subsequent evidence commit changes documentation
and benchmark JSON only; runtime, tests and workflow are identical to the validated source.

## Outstanding native gates

Real Touch ID/password, permissions, multiwindow paste, keyboard focus while the notice is
visible, menu language/VoiceOver, screenshot UI and Intel/minimum-OS validation still need
actual devices. Follow [RELEASING.md](../RELEASING.md). Use synthetic data.

No Developer ID identity or notarization credentials are available in this execution
environment. Python regression tests mock system commands. The additional macOS smoke test
uses a disposable ad-hoc fixture and real codesign/ditto/hdiutil creation, verification and
read-only mounting. It does not establish public signing, Gatekeeper or notarization.
No distributable package has been signed, notarized or published. A new DMG container needs
its own distribution validation even when its enclosed app is stapled.

The synthetic screenshot benchmark cannot establish Instruments peak RSS, dropped frames,
photographic-image timings or cancellation latency. Existing screenshots still need
replacement captures with synthetic content and cleared artwork rights.

## Changed files in this follow-up

Runtime and UI:

- `Sources/Magpie/App/AppDelegate.swift`
- `Sources/Magpie/App/StatusItemController.swift`
- `Sources/Magpie/Clipboard/ClipboardWatcher.swift`
- `Sources/Magpie/Panel/PanelController.swift`
- `Sources/Magpie/Paste/Paster.swift`
- `Sources/Magpie/Settings/SettingsStore.swift`
- `Sources/Magpie/Settings/SettingsView.swift`
- `Sources/Magpie/Settings/SettingsWindowController.swift`
- `Sources/Magpie/Storage/Database.swift` (policy-boundary comment)

Packaging and regression coverage:

- `.github/workflows/ci.yml`
- `Scripts/package-dmg.py`
- `Scripts/test-package-dmg-native.py`
- `Tests/MagpieTests/MagpieTests.swift`
- `Tests/MagpieTests/ScreenshotEditorTests.swift`
- `Tests/MagpieTests/SecretDetectorTests.swift`
- `Tests/Tooling/test_package_dmg.py`

Documentation and evidence:

- `README.md`, `README_EN.md`, `SECURITY.md`
- `docs/RELEASING.md`, `docs/PERFORMANCE.md`
- `docs/decisions/0004-encrypted-storage-design.md`
- `docs/review/2026-10-18-alpha-followup.md`
- `docs/review/native-image-benchmark.json`

This follow-up does not alter the database schema, storage encryption, default hotkeys,
themes or screenshot tools. The preceding readiness review's migration/cleanup/security
tests remain in the complete XCTest run. No existing test or source file was deleted.
