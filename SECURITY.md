# Security Policy

## Magpie is local-only

Magpie does not transmit clipboard data anywhere. There is no telemetry,
no analytics, no cloud sync, no account system. The "Send analytics" toggle
in Settings → Privacy is permanently disabled.

Clip history lives in `~/Library/Application Support/Magpie/clips.sqlite`
with macOS user-only file permissions. Image attachments live next to it
in `images/`. v1.0 will add SQLCipher encryption (key in Keychain) for
defense against physical disk theft; until then those files are protected
by macOS file ACLs only.

## Dependencies

Source-of-truth: `Magpie.xcodeproj` / `project.yml`. Currently:

- [HotKey](https://github.com/soffes/HotKey) — global hotkeys (Carbon API wrapper)
- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite + FTS5

v1.0 will add:
- [Sparkle](https://github.com/sparkle-project/Sparkle) — auto-update framework

All dependencies are vetted open-source projects with active maintenance.
We don't pull anything else.

## Permissions Magpie requests

| Permission | Why | When prompted |
|---|---|---|
| Accessibility | Synthesize ⌘V keystroke into the previously frontmost app for paste-back | First time you press ↵ / double-click a clip |
| Input Monitoring | (Optional) Watch typing globally for `;sig`-style snippet auto-expansion | Only if you enable Settings → "Auto-expand snippet shortcuts" |
| Touch ID | (Optional) Unlock the panel on first show after launch | Only if you enable Settings → "Require Touch ID" |

Magpie does not request: Network, Photos, Contacts, Calendars, Microphone,
Camera, Location, AppleScript automation of other apps.

## Reporting a vulnerability

**Please do not file public GitHub issues for security bugs.** Send a private
report through GitHub Security Advisory:

1. Go to the repo's Security tab → Advisories → New draft advisory
2. Describe the issue with reproduction steps

You'll receive acknowledgement within 7 days, and (assuming we can
reproduce) a fix within 30 days for high-severity issues. We coordinate
public disclosure with you.

## Out of scope

- Issues that require physical access to an unlocked device
- Issues that require the user to grant permissions to a malicious actor
- Bugs in Apple's frameworks (NSPasteboard / LocalAuthentication / etc.)
- Issues with apps that interact with clipboards in unusual ways
  (we capture what the system pasteboard reports — by design)

## What we are interested in

- Anything that lets a malicious app read Magpie's database without
  Accessibility permission
- Anything that bypasses the "Skip secret-looking content" filter to
  store credentials we shouldn't
- Anything that lets a user bypass Touch ID (when enabled)
- Code execution / privilege escalation through synthesized keystrokes
