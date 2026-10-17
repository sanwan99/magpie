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

Python tooling: 32 passed, 0 failed, 0 skipped on Linux; macOS native results pending CI.
Added native cases for pause expiry/restart/sleep/no-replay, queued writes, settings policy
changes, first-run completion, paste-recovery decisions and screenshot baselines.
Existing tests and environmental skip conditions remain intact.

## Outstanding native gates

Real Touch ID/password, permissions, multiwindow paste, keyboard focus while the notice is
visible, menu language/VoiceOver, screenshot UI and Intel/minimum-OS validation still need
actual devices. Follow [RELEASING.md](../RELEASING.md). Use synthetic data.

No Developer ID identity or notarization credentials are available in this execution
environment. DMG system commands are mocked in regression tests; no distributable package
has been signed, notarized or published. A new DMG container needs its own distribution
validation even when its enclosed app is stapled.

The synthetic screenshot benchmark cannot establish Instruments peak RSS, dropped frames,
photographic-image timings or cancellation latency. Existing screenshots still need
replacement captures with synthetic content and cleared artwork rights.
