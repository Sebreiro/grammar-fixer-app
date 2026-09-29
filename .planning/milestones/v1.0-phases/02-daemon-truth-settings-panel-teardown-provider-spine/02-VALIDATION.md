---
phase: "02"
slug: "daemon-truth-settings-panel-teardown-provider-spine"
status: validated
nyquist_compliant: false
wave_0_complete: true
created: "2026-09-24"
validated: "2026-09-26"
---

# Phase 02 — Validation Strategy

The locked Phase 02 spec excludes new test, gate, CI, and runtime-observation work. This document records the existing feedback path and the resulting evidence limit. It does not add a Wave 0 task or expand the phase boundary.

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | Existing Dart and Flutter test runners |
| Config file | `analysis_options.yaml`, `pubspec.yaml`, existing `test/` tree |
| Quick run | `dart analyze --fatal-infos` after touched Dart code |
| Existing suite | `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart && flutter test --exclude-tags=live test/ui test/platform test/composition` |
| New test files | None; prohibited by the Phase 02 spec |

## Sampling Rate

- Run `dart analyze --fatal-infos` after a code change that can affect Dart analysis.
- Run the existing suite after each dependency wave or at the phase gate. Address regressions introduced by Phase 02 without deleting or weakening existing tests.
- Review each Wave A–F acceptance criterion in `02-SPEC.md` against the final code and record evidence in `02-VERIFICATION.md`.
- Treat unobserved X11, Wayland, OpenAI, or Ollama behavior as unobserved; a local passing suite cannot substitute for a live target.

## Per-Wave Verification Map

| Wave | Requirements | Existing feedback | Evidence limit |
|------|--------------|-------------------|----------------|
| A | SETTINGS-01–04, 06, 08–09; CONFIG-01 | Analyzer, existing settings/config/tray tests, code inspection | Live compositor transitions remain unobserved unless a target is available |
| B | PANEL-01–07 | Analyzer, existing panel/controller tests, code inspection | Pointer-display placement on Wayland needs an explicit owner decision |
| C | PANEL-09–15, 17, 19; SETTINGS-05, 07 | Analyzer, existing panel/window tests, code inspection | Native event ordering is not proven by a fake alone |
| D | STARTUP-01–03, 05 | Analyzer, existing lifecycle/startup tests, code inspection | A real portal stop during an open dialog may remain unobserved |
| E | PROVIDER-02–03 | Analyzer, existing provider/controller tests, code inspection | OpenAI and Ollama live streaming are unavailable in this workspace |
| F | ARCH-01, 03–08; LEDGER-01 | Source diff and ledger heading/status inspection | Documentation must describe implemented code, not planned behavior |

## Wave 0 Requirements

None. The spec's no-new-test boundary governs this phase. An existing fake may be corrected where its behavior is a Phase 02 acceptance item.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Method |
|----------|-------------|------------|--------|
| Current pointer display and compositor placement | PANEL-01 | Wayland has no ordinary absolute toplevel positioning API | Record the approved placement policy and inspect each display-server path honestly |
| Provider interoperability | PROVIDER-02 | No configured live OpenAI or Ollama target in this workspace | Record as unobserved unless a real target becomes available |
| Ledger and frozen-document currency | ARCH-01, ARCH-03–08, LEDGER-01 | Requires comparison with shipped code and regeneration rules | Inspect diffs, preserve all entry headings, and use the authorized generators for frozen source documents |

## Validation Sign-Off

- [x] Existing analyzer and suite pass on the final tree after the retained Wayland fix: 982 Dart passed/2 skipped, 165 Flutter passed/7 skipped. The focused Wayland, Settings, and tray Dart suites passed 152/152, and the Settings hotkey widget suite passed 20/20.
- [x] Every in-scope requirement has code or document evidence; the retained Wayland rebind defect was fixed by 02-27/02-28 and WINDOW 41 records its source-level closure. Final phase verification will refresh `02-VERIFICATION.md`.
- [x] Unobserved behavior is labeled explicitly in the verifier's eight human checks.
- [x] No new test, gate, CI, or runtime-observation task was added.

**Approval:** local validation evidence recorded; the source-proven retained Wayland defect is fixed and awaits final phase verification. On 2026-09-26 the owner explicitly waived the separate eight unobserved live checks for v1.0 progression; no live pass is claimed. `nyquist_compliant` remains false because the user removed new test-shaped work from this milestone.
