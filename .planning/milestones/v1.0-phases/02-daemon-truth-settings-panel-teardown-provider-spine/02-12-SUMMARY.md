---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 12
subsystem: panel-testing
tags: [flutter, linux, panel-window, iconify]
requires:
  - phase: 02-10
    provides: request-owned panel departures and existing DW-31 reconciliation rows
provides:
  - FakePanelWindow records native iconification separately from GTK mapping
  - Existing DW-31 rows assert iconified, restored, and hidden window states
affects: [PANEL-13, panel-window-tests]
actuals:
  tokens: 447
  tasks: 2
  commits: 2
commits: 2
plan_head_before: fb350c3fe09b5fa183cab41b49c1c9c2d25780e4
tech-stack:
  added: []
  patterns: [native window-state assertion alongside panel-mirror assertion]
key-files:
  created: []
  modified:
    - test/fakes/fake_panel_window.dart
    - test/infrastructure/panel/window_manager_panel_visibility_test.dart
key-decisions:
  - "The fake keeps GTK mapping and iconification as separate facts; native minimize and restore events change iconification."
patterns-established:
  - "Existing panel reconciliation rows inspect both native window state and the visibility mirror."
requirements-completed: [PANEL-13]
coverage:
  - id: PANEL-13-iconified-fake
    description: Existing DW-31 rows distinguish a mapped iconified window from a hidden window and verify restore clears iconification.
    requirement: PANEL-13
    verification:
      - kind: unit
        ref: test/infrastructure/panel/window_manager_panel_visibility_test.dart
        status: pass
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
    human_judgment: false
duration: 7min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 12: Iconified window fake summary

**The existing panel fake now distinguishes an iconified mapped window from a hidden window, and DW-31 assertions check that state through minimize and restore.**

## Performance

- **Started:** 2026-09-24T18:43:53Z
- **Completed:** 2026-09-24T18:50:26Z
- **Tasks:** 2
- **Files modified:** 2
- **Task commits:** 2, measured from `plan_head_before`

## Accomplishments

- `FakePanelWindow` records native `minimize` and `restore` as iconified state while retaining the mapped state. A completed hide clears iconification, making hidden and iconified distinct.
- Existing DW-31 rows assert iconification during an outstanding show, its removal on restore, and the hidden state after close. The tests also retain their original mirror, call-order, and departure assertions.

## Task Commits

1. **Task 1: Give the existing fake a separate iconified state** — `3523c86` (`test`).
2. **Task 2: Make existing minimize/restore assertions check the window side** — `9d566dd` (`test`).

## Verification

- `dart analyze --fatal-infos` passed after each task.
- The focused existing panel adapter suite passed after each task: 91 tests.
- The full existing Dart and Flutter phase suites passed.
- Source inspection confirms the adapter treats `minimize` as external and consumes a believed `restore` before applying its outstanding-request guard. The fake emits each native event after updating its iconified state. Native GTK event delivery order remains unobserved in a live session.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None in the changed files. Existing nullable error controls in the fake are intentional test inputs.

## Evidence Limits

The existing tests exercise event order against the fake. They do not observe GTK or compositor event order in a live session; that remains source-inspection evidence.

## Self-Check: PASSED

Both changed files and this summary exist; both task commits resolve; the persisted ledger measures two task commits; `git diff --check` is clean.

---
*Phase: 02-daemon-truth-settings-panel-teardown-provider-spine*
*Completed: 2026-09-24*
