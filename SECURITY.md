# Security policy

Magpie is Source Alpha. No signed public binary release or long-term security-support
commitment has been published. Fixes are developed against the current source; review
open changes and release notes before installing.

## Threat boundaries

Magpie reads the user's pasteboard and stores history, snippets and search text in
`~/Library/Application Support/Magpie/clips.sqlite`, with managed PNGs in `images/`.
SQLite is **not encrypted**. The application support directory is restricted to the
current user and new database/image files use private permissions. This does not isolate
history from other authorized processes running as that user, administrators, backups
or filesystem snapshots. Accessibility permission is not required to read an accessible
SQLite file and must not be presented as a database access control.

The optional panel lock uses Apple's `deviceOwnerAuthentication` policy (Touch ID,
account-password fallback or other system-approved mechanisms). It fails closed and
relocks on hide, sleep, screen lock and session changes. Changing the setting requires
fresh authentication. It is a UI access barrier,
not encryption or protection against a compromised logged-in account. Auto-expansion
of snippets pauses while this privacy setting is enabled.

Concealed/Transient and compatible pasteboard markers are checked before reading
content. Regex filtering is supplementary and can both miss secrets and reject benign
text. No OCR-based secret filter is applied to copied images. Explicit screenshots can
contain anything the user captured; automatic redaction must be reviewed manually.

## Content handling

Production diagnostic logs must not include clipboard/snippet text, titles, file paths,
search queries, raw SQL errors or provider error descriptions. Use fixed events and
numeric errors. A conservative source regression guard runs in CI; it is not a proof of
complete information-flow isolation. Old logs created by older versions are not erased
by an upgrade.

Retention and Clear History delete clip rows and FTS entries transactionally, then clean
managed PNGs. Clearing also invalidates previously queued clipboard snapshots. Orphans from interrupted writes are reconciled on later cleanup. Failed
file removal can leave recoverable files and is reported. Clear History preserves snippets,
settings, originals referenced by file clips, the system clipboard and application backups.
It does **not** guarantee secure erasure from WAL files, SQLite free pages, disks, snapshots
or external backups. Close Magpie before making a consistent backup of the support directory.

The current app has no implemented telemetry, cloud sync or cloud OCR/translation client.
Apple translation can request language downloads; system sharing and opened links are
handled by user-selected services. The optional developer asset-generation script can
call an external image API and is not part of application execution.

## Permissions and dependencies

Accessibility is used for synthetic paste, Input Monitoring may be needed for optional
snippet observation, and Screen Recording is required for explicit capture. Capture does
not record microphone or system audio. LocalAuthentication handles the account password;
Magpie never receives it.

The current SPM dependency is [GRDB.swift](https://github.com/groue/GRDB.swift), version 6.x;
Carbon, LocalAuthentication, Vision, ScreenCaptureKit and Translation are Apple frameworks.
There is no HotKey package, Sparkle updater or SQLCipher integration in the current app.
Public distributions require Developer ID verification, hardened runtime, notarization
and Gatekeeper assessment. Local ad-hoc builds are a separate, explicitly trusted workflow.

## Report a vulnerability

Do not post exploit details, private screenshots or credentials in a public Issue.
If the repository Security tab offers **Report a vulnerability**, use the
[private reporting form](https://github.com/sanwan99/magpie/security/advisories/new).
Availability depends on the maintainer enabling private vulnerability reporting; this
review does not change repository security settings. If the option is absent, open a
minimal Issue requesting a private contact channel, with no sensitive details.

Provide the commit/version, macOS version, affected boundary, synthetic reproduction,
expected/observed behavior and any proposed fix. Include whether the attacker needs
another account, same-user code execution or an unlocked desktop. Reports involving
filter bypasses, incorrect paste targets, unsafe file cleanup, auth bypasses and accidental
content disclosure are welcome. Findings outside Magpie should go to the relevant vendor.

The project does not currently promise a response SLA. Coordinate disclosure with the
maintainer and avoid sharing working secrets. See [release acceptance](docs/RELEASING.md)
for outstanding system-level checks.
