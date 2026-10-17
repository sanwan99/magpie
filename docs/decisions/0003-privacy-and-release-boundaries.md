# ADR-0003: Privacy, storage and distribution boundaries

Status: proposed implementation on `fix/open-source-readiness-20261018`, 2026-10-18.

- Pasteboard privacy markers are unconditional. Heuristic filtering is optional and occurs
  before detection can persist images. Diagnostic events accept no content strings.
- The panel uses system owner authentication, including system password fallback. Unlock
  lasts until hide, sleep or session/lock changes, not for the whole process lifetime.
  This intentionally strengthens the old prototype's session-long unlock. Queue Mode may
  prompt again with privacy lock enabled; typed snippet expansion pauses under that setting.
- Every panel-show entry uses the same gate. Process-targeted synthetic paste requires a
  stable target AX window. Apps without a usable focused window use manual paste.
- FTS remains a contentful index. v4 adds a durable FTS row ID to each clip and deletion
  triggers, removes old orphans, preserves old indexed text, and repairs missing entries.
  This avoids full-index scans for every production deletion without tying FTS to the
  non-integer clip table rowid (which VACUUM may change).
- v5 adds a SHA-256 payload lookup index, still comparing full payload/type/app to preserve
  exact dedup semantics even in the event of a hash collision. Backfill uses bounded batches.
- Application bundle rollback and database downgrade are distinct. Installation backs up
  the app only. Users must quit Magpie and back up their data before testing migration or
  downgrade paths. No secure-erasure guarantee is made.
- Public installation requires Developer ID and Gatekeeper; default development/CI use
  ad-hoc signing. Optional personal certificates remain local and are not a prerequisite.
- Custom global shortcuts keep Cmd-P/J defaults. Invalid/duplicate/Carbon-conflicting
  choices roll back; operating-system reserved shortcuts still need manual acceptance.

Sources: [Apple system owner authentication](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication),
[pasteboard marker conventions](https://nspasteboard.org/),
[Apple process-targeted events](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid(_:)).
