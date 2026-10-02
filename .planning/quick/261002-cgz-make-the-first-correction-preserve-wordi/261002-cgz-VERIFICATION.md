---
quick_id: 261002-cgz
status: human_needed
verified: 2026-10-02
execution: inline
automated_checks: passed
---

# Quick Task 261002-cgz — Verification

## Automated Evidence

| Required property | Evidence | Result |
|---|---|---|
| Minimal native first correction | Shared prompt requires preserving wording/tone/meaning, only grammar/native phrasing fixes, and unchanged already-natural text; default/legacy/custom prompt tests pass | Passed |
| Casual second and short third | Shared ordered CASUAL/SHORTER instructions preserve meaning and key details; parser tag-order and completion tests pass | Passed |
| Both adapters and existing presets | Captured Claude sidecar and compatible HTTP requests contain the requirements; file/Settings prompt-flow test preserves prompt/model pairing | Passed |
| Corrected/1, Casual/2, Short/3 labels | Actual rendered panel label and key-hint assertions; digit-selection and copy widget tests | Passed |
| Streaming/history compatibility | Provider cancellation, parser streaming, local persistence round trips, and daemon copy workflow tests | Passed |

288 pure Dart tests and 69 widget/workflow tests passed. Dart analysis found no
issues. Both source tasks were committed atomically and reviewed without findings.

## Human or Live Check

Run a correction using the selected real provider and confirm that the first
suggestion makes only necessary changes, the second sounds casual, and the third
is concise without losing essential meaning. Automated request tests validate
instructions rather than subjective model output.

The deliberate Claude live smoke was blocked by automatic approval review:
it can use credentials and send synthetic input to an external service, which
was not specifically authorized. Approval is needed before running it.

No source, formatting, analyzer, parser, history, or panel verification gaps remain.

## Follow-up Package Verification

- `flutter build linux --release --no-pub` passed.
- Rebuilt AppImage native/AOT text and rodata sections match the release bundle.
- The compiled correction instructions and Corrected label are present.
- Bundled sidecar SDK 0.2.132, CLI version, assets, dependency resolution,
  executable launcher, and temporary desktop installation checks passed.
- Actual package startup, focus, keep-above, taskbar visibility, focus-loss hide,
  and repeated hotkey toggling passed on an isolated X11 desktop.
- Candidate and final release checksums match
  `a9fe8301bbb7b54118232fff84cfa235e9184a6bfd93376fbc51b6dab27cb1e2`.

Real-provider output-quality verification remains pending; rebuilding and
package checks did not make any correction/provider request.
