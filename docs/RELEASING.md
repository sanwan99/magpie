# Release preparation and manual acceptance

Proposed first public binary: **v0.4.0-alpha.1** (prerelease). Not yet published.
The app version remains 0.3.0 until a maintainer authorizes a release/version bump.
Do not describe the current branch as a stable release.

## Required gates

- [ ] Review the final diff and exact commit; merge only with maintainer authorization.
- [ ] `Scripts/build-local.sh` succeeds in Release configuration on Xcode 26+.
- [ ] `Scripts/test.sh` runs all XCTest; record passed, failed and skipped counts and retain `.xcresult`.
- [ ] Python tooling tests, privacy-log guard and documentation links pass.
- [ ] Test on Apple silicon and Intel; macOS 14 minimum, macOS 15 translation, macOS 26 glass.
- [ ] Run old v1/v2/v3 database upgrade fixtures on disk, reopen twice, confirm clips, pins,
  notes, snippets, tags and searches. Test interrupted migration/disk-full recovery with
  disposable data. GRDB migrations are additive, but rollback of an app is not a schema downgrade.
- [ ] Review the 1k/10k/50k benchmark and profile large payloads/Chinese searches in Instruments.
- [ ] Inspect all distributed images and branding. Existing `panel-stripe.png` includes a
  personal path and desktop content, and both old screenshots include third-party artwork.
  The homepage uses only the less revealing existing `panel-splat.png`. Retake screenshots
  with synthetic content and cleared redistribution rights before distributing marketing assets.
  Old binary images/history were not rewritten or deleted during this review.
- [ ] Verify private vulnerability reporting/contact route actually works for an external reporter.

## Native manual acceptance (not established by mocked tests)

Use a disposable macOS account and synthetic data. Never test deletion against real history.

| Area | Procedure | Expected result |
| --- | --- | --- |
| First install | Clean account with no old app, signing metadata or certificates | Signed/notarized app installs and opens without developer setup |
| Getting started | First launch, close/reopen guide, complete, relaunch; deny permission | Guide remains available from menu; completion persists; permissions requested only by user action |
| Recording pause | Pause 15 minutes/1 hour, copy, restart, sleep past expiry, resume | Deadline persists; paused contents are not replayed; queued writes discarded; already executing writes may finish |
| Quick ignore | Open menu in a normal app, already ignored app and Magpie; change language | Correct app identified; unavailable actions disabled; preference persists and can be removed in Settings |
| Paste feedback | Revoke AX, change clipboard, switch windows; use keyboard while notice appears | Useful localized message without content; no focus theft; replaced clipboard never suggests pasting the old record |
| Upgrade | Old signed app, populated history and images | Old app verified and backed up; new app starts; data survives |
| Bad package | Corrupt signature, wrong bundle/team, failed staged copy | No replacement; old app remains usable |
| Rollback | Force launch failure after replacement | Restore old app, preserve backup; report rollback failures honestly |
| Privacy markers | Copy from a password manager; include empty Concealed/Transient marker data | No row, FTS content, saved image or content-level log |
| Authentication | Touch ID success/failure, cancel, no enrolled fingers, Mac without Touch ID | System password fallback when available; unavailable/failed policy stays locked |
| Lock settings | Enable/disable the lock from Settings; cancel/fail authentication | Setting remains unchanged unless fresh system authentication succeeds |
| Lock lifecycle | Hide/reopen, sleep/wake, screen lock/unlock, fast user switch, relaunch | Fresh auth; pending auth/paste cannot re-open old content |
| Secondary windows | Leave expanded preview/snippet editor open, lock or sleep | History-related preview/editor closes when privacy lock enabled |
| Paste race | Start paste then switch apps or documents; exit target; copy new content | Cancel rather than send to the wrong destination |
| Repeated paste | Rapid Cmd-1/2/3 and Queue Mode | Only current request may send; queue reopens after success |
| AX compatibility | TextEdit, Terminal, browser, common Electron editors; permission revoked | Normal paste works when focused window is readable; otherwise safe manual fallback |
| Hotkeys | Custom binding, conflict with app/system, restart, sleep, Space/full-screen changes | Persisted binding works, conflict is visible, failed edit leaves previous binding |
| Capture | Deny/allow Screen Recording; Retina/multiple displays; save cancellation; OCR | Correct scale/content, no unintended history on cancel/save |
| Scrolling | Long capture, fixed headers, moving content, 30k-pixel/40MP limit, cancel during encode | Bounds enforced; no late callbacks/windows after cancellation; memory released |
| Translation/share | Offline packs missing/present, cancel download, explicit system sharing | No unrequested download/share; system failures surfaced |
| Cleanup | Retention, type cap, clear all, orphan PNG, outside path, symlink and filesystem denial | FTS removed; managed PNG cleanup only; snippets/originals/backup preserved; failure visible |

Capture the timestamp, OS/build/CPU, commit and outcome for each row. CI permission skips
are outstanding acceptance work, not passing results. Record cold/warm memory and frame-time
measurements on representative large screenshots; SQL microbenchmarks cannot supply these.

## Public signing and notarization

These steps are for an authorized maintainer with an Apple Developer ID identity.
No private key or notarization credentials belong in the repository. Keep CI test jobs
free of signing secrets; perform release signing separately after approval.

```bash
# In an authorized local maintainer shell; use your real, verified team identity.
MAGPIE_CODE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' Scripts/build-local.sh
codesign --verify --deep --strict /path/to/Magpie.app
codesign -dv --verbose=4 /path/to/Magpie.app
# Package an application archive, submit with a locally configured keychain profile.
ditto -c -k --sequesterRsrc --keepParent /path/to/Magpie.app Magpie-notarization.zip
xcrun notarytool submit Magpie-notarization.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple /path/to/Magpie.app
xcrun stapler validate /path/to/Magpie.app
spctl --assess --type execute --verbose=2 /path/to/Magpie.app
```

Confirm hardened runtime and a secure timestamp on the Developer ID build; review nested
framework signatures and entitlements. Never re-sign a public app ad-hoc to make a failing
signature check disappear. Build/package both intended architectures and inspect `lipo -archs`.
A final DMG must itself be validated for packaging, notarization/stapling where applicable,
quarantine/Gatekeeper on another Mac, checksum and an Applications shortcut.

## Local DMG packaging

`Scripts/package-dmg.py` prepares a local distribution container from an **already
Developer ID-signed, notarized and stapled** app. It requires Python 3 and macOS's
`ditto`, `codesign`, `spctl`, `hdiutil` and `xcrun stapler`; it has no third-party Python
dependencies. Use a team identifier independently verified by the maintainer. This
script does not create a signing identity, sign code, submit to Apple, staple tickets,
install/launch the app, mount a volume, or publish a Release.

```bash
# Run after the app's signing, notarization and stapling steps above.
# The output name is an example, not authorization to create a version/tag/Release.
python3 Scripts/package-dmg.py \
  "/path/to/Magpie.app" \
  "dist/Magpie-0.4.0-alpha.1.dmg" \
  --team-id YOURTEAMID

# Check the local bytes against the generated sidecar.
(cd dist && shasum -a 256 -c Magpie-0.4.0-alpha.1.dmg.sha256)
```

Replace `YOURTEAMID` with the real ten-character team ID; the placeholder is not a
usable signing identity. The script checks the bundle identifier, executable name,
Developer ID requirement/team, Gatekeeper assessment and stapled ticket both before
and after copying the app. The read-only compressed DMG contains `Magpie.app` and an
`Applications` link to `/Applications`. `hdiutil verify` must succeed before output.
Neither the source bundle nor an existing output is modified.

The DMG and `.dmg.sha256` sidecar are staged beside the destination, then published with
atomic, no-overwrite hard links. The destination filesystem must support hard links;
if it does not, use a local APFS volume. An existing file, directory or dangling symlink
at either output path is an error, including one created by a concurrent packager.
Each file appears complete, but the pair is not one filesystem transaction: an abrupt
process/power interruption can leave only the checksum. Inspect that state and select
a new output name before retrying; the script never automatically removes old output.

**The newly created DMG container is not itself signed or notarized.** The tool only
packages a verified, stapled app. An authorized maintainer must still complete the final
container signing/notarization workflow as applicable, inspect the mounted contents,
and test a quarantined download and drag-and-drop installation on another Mac. If any
subsequent signing/stapling changes the DMG bytes, regenerate and independently verify
the release checksum; the packaging-stage sidecar no longer describes those new bytes.
Follow Apple's [packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
and [notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
guidance for the final distribution container.

Automated Python tests use synthetic bundles and mocked macOS commands; they cover
validation failures, copy/image failures, checksum integrity, output collisions and
publication cleanup. Those tests do not establish real signed-app/DMG tool behavior.

The separate macOS CI step runs `python3 Scripts/test-package-dmg-native.py`. It creates
a disposable minimal app with a no-op shell executable, applies temporary ad-hoc signing,
and calls the production packager with **only** its public-app verification callback
replaced inside that test process by the installer's local signature verifier. It uses
real `ditto`, `hdiutil create/verify`, a read-only mount, and checks the mounted app,
Applications link, SHA-256 and no-overwrite behavior. The volume is detached in `finally`
and temporary files are removed; the app is never launched and no artifact is published.
This test requires macOS and is not run by the cross-platform unittest discovery command.
The production packaging CLI has no ad-hoc bypass option.

**A successful native smoke test validates packaging mechanics only.** It does not prove
Developer ID identity, Gatekeeper, notarization/stapling, quarantined downloads or real
installation. Record its actual CI result separately from those release gates. Record the
real distribution's macOS tools, app identity, final checksum and clean-device outcomes
before treating a DMG as distributable.

`install-release.sh` verifies a provided app; first public installation requires the
expected `--team-id` from independently verified release instructions. The release notes
must publish that team identifier and checksums. The optional script requires Python 3;
a public DMG should support Finder drag-and-drop without developer tooling. It does not produce or download a DMG.
Backups under the application support directory are application bundles, not automatic
database snapshots. A data backup must be taken after quitting Magpie, including sidecars
and image files; do not copy a live SQLite main file alone.

## Draft release notes (not a published Release)

**Magpie v0.4.0-alpha.1 — proposed**

- Respect concealed/transient pasteboard content before reads and persistence.
- Remove content diagnostics; add system-password authentication fallback and relocking.
- Repair stale FTS data and tie clip deletion to its search index; bound image cleanup.
- Cancel paste on changed targets; allow custom global shortcuts with conflict rollback.
- Separate developer builds from signed public installation; add first-install/rollback tests.
- Index dedup lookup without changing payload/app semantics; improve stale-search cancellation.
- Refresh bilingual documentation and macOS CI.
- Add timed recording pause, quick application exclusion and an explicit first-run permission guide.
- Explain canceled/failed paste without activating another window or exposing clipboard content.
- Add verified local DMG packaging, native packaging smoke coverage and 4K/40MP image baselines.

Known limitations: unencrypted local storage, heuristic secret detection, AX-dependent safe
paste, environmental capture/translation tests, large CJK scans and main-thread screenshot
rendering/stitching still needing device profiling. List exact tested versions and artifacts;
do not mark this draft released until all gates and explicit release approval are complete.
