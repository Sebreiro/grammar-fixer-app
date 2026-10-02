---
quick_id: 261001-cfz
status: passed
verified: 2026-10-01
---

# Verification — Provider settings

Goal and all automated must-haves pass. Verified inline under the Codex spawn restriction.

| Must-have | Evidence | Result |
|---|---|---|
| Masked key entry and keyring-only persistence | API field widget tests; provider settings controller tests; private D-Bus write/read tests | PASS |
| One active provider through complete preset/config | Settings radio/first-setup tests; controller round-trip switches; composition graph | PASS |
| Conditional fields and filtered presets | Provider widget tests and updated existing Settings suite | PASS |
| Inactive provider settings retained | Fresh setup and repeated switch tests preserve Claude and URL entries/presets | PASS |
| Fresh-install URL setup | Controller and widget tests starting with Claude-only config | PASS |
| Inline retryable failures and mutation serialization | Keyring failure/draft retry tests; prompt pending controls; existing config write failure tests | PASS |
| External config edits remain synchronized | Existing endpoint/model conflict and external edit widget rows pass after form extraction | PASS |
| Clean formatting, analyzer and headless suites | Exact commands and counts below | PASS |

## Commands and results

- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` — 1007 pass, 2 existing skips.
- `flutter test --exclude-tags=live test/ui test/platform test/composition` — 188 pass, 7 existing skips.
- `flutter test --exclude-tags=live test/ui/settings test/composition/daemon_graph_test.dart test/integration` — 112 pass after provider/keyring review fixes.
- `dart test test/integration/secret_service_lookup_test.dart` — 9 pass after cleanup bounds and invalid-signal handling.
- `flutter test test/ui/settings/provider_settings_test.dart` — 5 pass after explicit future-discard callback.
- `dart test test/fakes_smoke_test.dart` — 1 pass after adding the new fake port.
- `dart analyze --fatal-infos` — no issues on final source.
- `dart format --output=none --set-exit-if-changed` — no changes; all later edited Dart files also formatted.
- `git diff --check` — clean.

The initial combined Dart run included a Flutter-dependent integration test and
failed at loading dart:ui; the corrected Dart and Flutter runs both passed.

## Manual observation limit

Actual GNOME/KWallet dialogs have not been exercised. Protocol behavior, immediate
prompt replies, dismissal, timeouts, malformed replies, replacement, source lookup,
and UI failure handling are verified with a private D-Bus service. This report
does not claim a production keyring or compositor was exercised.
