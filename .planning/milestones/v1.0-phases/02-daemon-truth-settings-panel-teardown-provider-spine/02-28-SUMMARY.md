---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 28
subsystem: hotkey
tags: [architecture, wayland, settings, tray]
requires:
  - phase: 02-27
    provides: Typed retained shortcut and source-level proof
provides:
  - AD-9, AD-10, and AD-12 reconciled with D-21 and shipped source
  - WINDOW 41 fixed after focused existing-row proof
affects: [SETTINGS-02, SETTINGS-03, SETTINGS-06, SETTINGS-08]
actuals:
  tasks: 2
  commits: 2
commits: 2
key-files:
  created:
    - .planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-28-SUMMARY.md
  modified:
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/.memlog.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md
    - lib/src/domain/hotkey/hotkey_status.dart
    - lib/src/application/settings_state.dart
    - .planning/WINDOWS.md
key-decisions:
  - D-21 ratifies HotkeyRetained as a third typed outcome without changing the prior AD-9 fields or constructors.
  - D-20 waives eight live checks for v1.0 closure without claiming observation.
requirements-completed: [SETTINGS-02, SETTINGS-03, SETTINGS-06, SETTINGS-08]
completed: 2026-09-26
duration: approximately 20min
status: complete
---

# Phase 02 Plan 28: Retained shortcut architecture and ledger

**The architecture now describes the retained Wayland refusal that Plan 02-27 implements, and the source-proven defect record is closed.**

## Accomplishments

- Appended D-21 and D-20 to the architecture memlog, then re-distilled AD-9, AD-10, and AD-12 from the committed implementation. All 19 AD identifiers and the prior AD-9 fields and constructors remain. The spine distinguishes a saved restart seed from the shortcut a compositor reports and describes the temporary refusal in Settings and tray.
- Corrected `HotkeyStatus` and `SettingsState` comments so they describe the third outcome.
- Closed WINDOW 41 through the canonical GSD writer after the existing focused rows passed. The original defect description and timestamps remain in the ledger.

## Task Commits

1. **Task 1: Reconcile frozen architecture with D-21 and source** — `7fc0971`.
2. **Task 2: Close the proved retained-refusal defect record** — `3e28601`.

## Verification

- `dart analyze --fatal-infos` and `git diff --check` passed.
- Existing focused Wayland adapter, Settings controller, and tray Dart suites: 152 passed. Existing Settings hotkey widget suite: 20 passed.
- Final existing full local suites: Dart 982 passed, 2 skipped; Flutter 165 passed, 7 skipped.
- Architecture lint reports only its pre-existing low false positive on the literal D-Bus `a{sv}` type. All 19 AD headings remain.

These are local checks. D-20's eight live desktop checks remain waived and unobserved. No real compositor, tray host, or event/cache timing result is claimed. The locked Phase 02 scope excluded new test, gate, CI, and runtime observation work; this plan added none.

## Deviations from Plan

None. The product SPEC was not edited, and no Claude CLI or external BMAD generator ran.

## Self-Check: PASSED

Both task commits exist, the generated architecture and source comments agree on the third outcome, and WINDOW 41 is fixed only after focused proof.
