---
quick_id: 261002-4z2
status: human_needed
score: 5/7 must-have observations verified automatically or on synthetic X11
---
# Quick task 261002-4z2 — Verification

| Must-have | Evidence | Result |
|---|---|---|
| Valid portal activations preserve fresh tokens without hotkey I/O | Portal private-bus tests; synchronous preparation after all identity filters | Passed |
| KDE tray tokens reach presentation without raising on receipt | Six native private-bus tests; receiver links to GIO only, with no GTK calls | Passed |
| Tokens are one-use and scoped to their request | Five panel activation tests; native replacement/empty/once rows; generation guards still pass | Passed |
| Toggle, focus-loss, session, and teardown rules survive | 1048 pure-Dart and 199 Flutter passes; native rebuilt-app X11 smoke | Passed |
| Linux build, analyzer, formatting, and native protocol checks pass | Clean analyzer/format/diff; release bundle build; six native tests | Passed |
| Both routes foreground/focus the panel on affected KDE Wayland after other-app interaction | No affected KDE compositor available; requests are not focus acknowledgements | Human needed |
| CAP-1 latency and resident behavior beyond ten minutes | No compositor timing or ten-minute affected-desktop observation | Human needed |

## Human checks
Follow the KDE Wayland raising section at `test/platform/runtime-observation-checklist.md`. Record compositor/backend/build identity, actual keyboard focus, preserved session, tray menu replacement, minimize/restore, second-key hide, focus-loss hide, ten-minute residency, and measured hotkey latency.

The implementation does not claim to override compositor policy without a valid token. No source-level blocker remains. Private-bus success proves method delivery and order; synthetic X11 focus does not prove KDE Wayland activation.

Verification performed inline under the skill adapter's spawn restriction. See SUMMARY.md for exact final commands/counts/logs and REVIEW.md for review evidence.
