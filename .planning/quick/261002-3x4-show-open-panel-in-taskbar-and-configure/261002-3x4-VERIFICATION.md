---
quick_id: 261002-3x4
status: human_needed
verified: 2026-10-02
---
# Verification

## Automated evidence

| Required behavior | Evidence | Result |
|---|---|---|
| Open warm panel eligible for taskbar/dock | main.dart sets setSkipTaskbar(false) before startup; hidden_window_test pins the value and forbids show/construct calls on startup | Passed |
| Native Close defaults to tray | AppConfig default, old-file decoder test, real visibility adapter plus application-policy tests, warm reopen test | Passed |
| Quit preference reaches ordered shutdown | graph eager-wiring and persisted-selection tests; shared handler architecture check requires await lifecycle.shutdown before exit; existing lifecycle/graph tests drain pending history | Passed |
| Settings and file edits share the persisted preference | config round trip, invalid-value and equality tests; settings mutation and widget external-edit/failure/pending-lock tests | Passed |
| Hotkey/focus dismissal stays independent | CAP-14 policy test plus existing full panel controller and window reconciliation suites | Passed |
| New resources dispose safely | close-controller idempotence, cancel-error, closed-quit-stream tests; graph teardown/disposal tests | Passed |

Full commands:

- dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart: 1,032 passed, 2 skipped.
- flutter test --no-pub --exclude-tags=live test/ui test/platform test/composition: 194 passed, 7 skipped.
- Final hidden-window/composition architecture checks after comment cleanup: 48 passed, 1 existing skip.
- dart analyze --fatal-infos: no issues.
- flutter build linux --release --no-pub: succeeded.
- dart format --output=none --set-exit-if-changed for final touched Dart files and git diff --check: clean.

No unresolved code-review findings. Broad suite results describe this task's implementation before unrelated concurrent keyring work appeared in the shared checkout; that work was excluded from commits.

## Human check needed

Run the taskbar and native Close preference section of test/platform/runtime-observation-checklist.md on real X11 and Wayland desktops. Verify entry appearance/removal, minimized restoration, both Close modes from the panel and Settings, and persistence across restart. The local DISPLAY=:0 is inaccessible and no Wayland session is available, so this report does not claim a live dock observation.
