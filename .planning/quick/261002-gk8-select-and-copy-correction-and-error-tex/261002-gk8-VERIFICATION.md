---
quick_id: 261002-gk8
status: passed
verified: 2026-10-02
execution: inline
score: 4/4
---

# Quick Task 261002-gk8 — Verification

## Goal Achievement

| Must-have | Evidence | Result |
|---|---|---|
| Mouse-select all or part of corrected text; copy by keyboard or right-click | Linux mouse drags copy exactly `corrected` via Ctrl+C and right-click; Ctrl+A/C copies every entire register variant. | Passed |
| Apply the same interactions to panel errors | Provider failure drags copy exactly `provider stopped answering` via both routes; Ctrl+A/C copies the full failure and copy-failure notice. | Passed |
| Keep panel open and output read-only | All selection-copy routes preserve visibility; Backspace leaves the rendered correction/error control value intact; copying creates no new history record. | Passed |
| Preserve existing actions, streaming rules, Retry, announcements, and layout | A click selects the register; a subsequent digit still selects another variant; Retry submits the captured original; no selection copy exists while deltas stream; current panel accessibility and layout regressions pass. | Passed |

## Artifacts and Links

- `SuggestionCard` renders `SelectableText` only for actionable authoritative suggestion text and inline copy failures.
- `CorrectionErrorNotice` keeps its read-only selectable message inside the existing error live region and scroll container with Retry.
- `correction_panel_text_selection_test.dart` runs nine Linux interaction tests against the real panel composition with faked domain ports and a captured framework clipboard channel.
- Existing whole-suggestion copying remains connected to `CorrectionController.copySuggestion` and ClipboardPort.

## Executed Checks

| Check | Result |
|---|---|
| `dart analyze --fatal-infos` | No issues |
| `git diff --check` | Passed |
| Focused selection/copy suite | 9 passed |
| `flutter test --no-pub --exclude-tags=live --reporter expanded test/ui/panel` | 77 passed |
| `dart test --exclude-tags=live --reporter expanded test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | 1,118 passed, 2 skipped |
| `flutter test --no-pub --exclude-tags=live --reporter expanded test/ui test/platform test/composition` | 241 passed, 7 skipped |
| Full-mode code review | Clean; 0 findings |

Logs from this run are at `/tmp/261002-gk8-panel-tests.log`, `/tmp/261002-gk8-dart-tests.log`, and `/tmp/261002-gk8-flutter-tests.log`.

## Scope of Evidence

The task's mouse, keyboard, and menu behavior is verified at the Linux Flutter widget/platform boundary. Actual packaged startup and hotkey opening were subsequently verified on isolated X11 during the requested rebuild. User-compositor selection behavior remains unobserved. No new dependency, provider behavior, hotkey path, persistence shape, or generated-spec change is involved.

## Requested AppImage Rebuild

| Check | Result |
|---|---|
| Linux release compilation | Passed |
| Checksum-pinned cached packaging tools | Matched release workflow pins |
| Extracted runner, AOT library, SQLite library, and launcher | Matched the new release/source |
| Native dependencies and bundled sidecar SDK/CLI | Passed |
| Actual AppImage startup and persisted sidecar paths | Passed on isolated Xvfb/openbox |
| Actual hotkey opens the resident panel | Passed on isolated X11 |
| Installed local artifact checksum | Passed |

Delivered: `build/releases/hotkey_grammar_corrector-1.0.0-linux-x86_64.AppImage` (111,905,272 bytes), with an updated adjacent SHA256 file.

SHA256: `416c91cbc76bde8421c4c75d75b3d5b9300b65022792c83c2942db7d28cc31d1`.

Build log: `/tmp/261002-gk8-linux-build.log`; packaging/extraction/native-check/smoke logs: `/tmp/hgc-selection-appimage.7Knzq6/`.
