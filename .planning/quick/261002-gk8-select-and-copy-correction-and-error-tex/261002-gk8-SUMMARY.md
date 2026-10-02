---
quick_id: 261002-gk8
status: complete
completed: 2026-10-02
execution: inline
key_files:
  created:
    - test/ui/panel/correction_panel_text_selection_test.dart
  modified:
    - lib/src/ui/panel/suggestion_card.dart
    - lib/src/ui/panel/correction_error_notice.dart
commits:
  - 031cff1
  - 902a7cd
---

# Quick Task 261002-gk8 — Select and copy panel text

Completed correction text, provider error messages, and inline copy errors now use read-only selectable text. Users can drag-select a substring or select the entire message, then copy with Ctrl+C or right-click → Copy. Copying keeps the panel open.

Existing whole-suggestion buttons, simple-tap and digit register selection, Retry, error announcements, and panel layout remain functional. Streamed partials stay non-actionable until the authoritative correction finishes.

## Commits

- `031cff1`: native selection for completed corrections and panel errors.
- `902a7cd`: nine Linux widget regressions for actual mouse, context-menu, and keyboard copying.

## Validation

- `dart format`: all changed Dart files formatted.
- `dart analyze --fatal-infos`: no issues.
- `git diff --check`: passed.
- Focused selection suite: 9 passed.
- Full panel suite: 77 passed.
- Required non-live Dart suite: 1,118 passed, 2 skipped.
- Required non-live Flutter UI/platform/composition suite: 241 passed, 7 skipped; includes the final strengthened selection tests.
- Full-mode code review: no findings.

## Implementation Decisions

- Use Flutter's existing native text-control selection and clipboard behavior, matching the original editor, with no direct clipboard I/O added to widget code. Whole-suggestion actions keep using the application's ClipboardPort.
- All full-mode stages ran inline under the requested skill's Codex spawn restriction.
- No generated spec, ROADMAP, provider interface, persistence schema, or configuration changes were needed.
- The ordinary command sandbox could not start because the container disallows bubblewrap namespaces; automatically reviewed escalations allowed the required workspace reads, tests, and commits.

## Verification Limits

Selection and copying were exercised with Linux widget gestures and captured platform clipboard messages. Existing suite skips retain their original reasons; real user-compositor selection behavior remains unobserved.

## Follow-up AppImage Rebuild

At the user's request, rebuilt the Linux release and replaced `build/releases/hotkey_grammar_corrector-1.0.0-linux-x86_64.AppImage` and its adjacent `.sha256` file.

- Source: committed text-selection changes at `d1a62f4`.
- `flutter build linux --release --no-pub`: passed.
- Reused the established AppImage dependency and pinned sidecar payload, replacing the Flutter bundle and refreshing the source launchers.
- Verified the cached linuxdeploy and AppImage runtime against the checksums pinned in the release workflow.
- Extracted the candidate and compared its runner, `libapp.so`, SQLite library, and launcher with the fresh build/source; all matched.
- Native shared-library dependency checks and packaged Claude SDK/CLI import/version checks passed.
- Actual candidate startup, persisted AppImage sidecar paths, and X11 hotkey panel opening passed on isolated Xvfb/openbox with private config/data/runtime directories and a private session bus.
- Atomically replaced the previous local artifact after those checks; final checksum verification passed.

Size: 111,905,272 bytes. SHA256: `416c91cbc76bde8421c4c75d75b3d5b9300b65022792c83c2942db7d28cc31d1`.

Build log: `/tmp/261002-gk8-linux-build.log`. Package and smoke evidence: `/tmp/hgc-selection-appimage.7Knzq6/`. The actual packaged selection interactions were not re-run on a user's desktop; those remain covered by the Linux widget tests. Quit the existing tray daemon before launching the replacement so the resident old process does not handle the second launch.
