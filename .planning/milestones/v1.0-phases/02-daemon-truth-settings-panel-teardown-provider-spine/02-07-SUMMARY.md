---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 07
subsystem: panel
tags: [flutter, clipboard, correction, accessibility]
requires:
  - phase: 02-01
    provides: stable correction controller and per-run provider pair
  - phase: 02-06
    provides: selectable suggestion cards and separate Copy actions
provides:
  - serialized clipboard writes with generation-owned feedback and refusal of absent text
  - card-local pending, success, and failure status with register-named live semantics
affects: [PANEL-03, PANEL-05, 02-11]
actuals:
  tokens: 5468
  tasks: 2
  commits: 3
commits: 3
plan_head_before: 0ad5c91f33edde0baaaf8bdf528fa2ecbb6a1b3c
tech-stack:
  added: []
  patterns: [serialized effect queue, monotonic feedback generation, card-local status]
key-files:
  created: []
  modified:
    - lib/src/application/correction_controller.dart
    - lib/src/application/correction_state.dart
    - lib/src/ui/panel/suggestion_card.dart
    - lib/src/ui/panel/suggestion_list.dart
    - lib/src/ui/panel/correction_panel.dart
    - test/application/correction_controller_test.dart
    - test/ui/panel/correction_panel_layout_test.dart
    - test/ui/panel/correction_panel_selection_and_copy_test.dart
key-decisions:
  - Keep clipboard writes in a controller-owned future queue and identify each request by generation, including identical text.
  - Bound a stalled write at eight seconds so the card reports failure and a later queued request can proceed.
requirements-completed: [PANEL-03, PANEL-05]
coverage:
  - id: PANEL-03
    description: Valid clipboard writes follow request order, and absent or blank text is refused before a write.
    requirement: PANEL-03
    verification:
      - kind: unit
        ref: test/application/correction_controller_test.dart
        status: pass
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
    human_judgment: true
    rationale: Platform clipboard timing and the behavior of a write after its future times out were not observed on X11 or Wayland.
  - id: PANEL-05
    description: Only the latest requesting card shows progress, success, or failure, with a register-named live announcement.
    requirement: PANEL-05
    verification:
      - kind: automated_ui
        ref: test/ui/panel/correction_panel_selection_and_copy_test.dart test/ui/panel/correction_panel_layout_test.dart
        status: pass
      - kind: integration
        ref: flutter test --exclude-tags=live test/ui test/platform test/composition
        status: pass
    human_judgment: true
    rationale: The native panel and clipboard were not observed on a desktop compositor.
duration: 20min
completed: 2026-09-24
status: complete
---

# Phase 2 Plan 07: Serialized copy and card feedback summary

**Clipboard copy requests now use one ordered write queue, and the requesting suggestion card shows real pending, success, or failure feedback.**

## Performance

- **Completed:** 2026-09-24T16:10Z
- **Tasks:** 2
- **Files modified:** 8
- **Production commits:** 3, measured from `plan_head_before`

## Accomplishments

- The controller accepts a newer copy while a write is pending, orders platform writes, and lets only the latest request report an outcome. The generation changes for identical text as well as different registers.
- Empty or absent completed text is refused before clipboard access with the reason `There is no suggestion text to copy.` New corrections, new sessions, and disposal invalidate old feedback.
- The affected card alone shows a spinner and `Copying…`, `Copied` after completion, or the approved failure copy. Its polite live region names the register. All Copy controls remain enabled during pending work; copying does not close the panel.

## Task Commits

1. **Task 1: Order clipboard effects by request generation** — `2232f44` (`fix`).
2. **Task 2: Show per-card pending, success and failure** — `ca56d2a` (`feat`), followed by `f671b5f` (`fix`) for the exact card wording and existing assertions.

## Decisions Made

- A single controller-owned future chain orders actual writes. Generation checks prevent a superseded, failed, or disposed request from painting feedback.
- An eight-second timeout reports a hung write as failure and releases the queue for subsequent requests. The clipboard port has no cancellation operation, so a platform write that completes after timeout cannot be forcibly stopped by this controller.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Routed card feedback through the existing list owner**
- **Found during:** Task 2.
- **Issue:** `SuggestionList` constructs the cards, so the planned controller-to-panel state could not reach them through only the listed UI files.
- **Fix:** Passed the latest request's register and status through `SuggestionList`.
- **Files modified:** `lib/src/ui/panel/suggestion_list.dart`.
- **Verification:** Analyzer and existing Flutter panel suites passed.
- **Committed in:** `ca56d2a`.

**2. [Rule 1 - Existing assertions] Aligned tests with refusal and ordered writes**
- **Found during:** Phase-gate Dart suite.
- **Issue:** Three existing assertions encoded silent invalid copies or concurrent write completion order, which PANEL-03 replaces.
- **Fix:** Updated those assertions and the existing UI text assertions; no new test or gate was added.
- **Files modified:** Three existing test files.
- **Verification:** Focused controller and panel suites passed, followed by the full phase-gate suite.
- **Committed in:** `f671b5f`.

## Verification and Limits

- `dart analyze --fatal-infos`: passed after each task and after the final wording change.
- Existing Dart phase-gate suite: 982 passed, two skipped. Existing Flutter phase-gate suite: 165 passed, seven skipped. Both commands completed successfully before the final wording change; both affected Flutter panel suites and the analyzer passed after that change.
- Source inspection confirms the queue, generation checks, blank refusal, per-card status, and live semantics. A write that completes after its eight-second timeout may still affect the platform clipboard because `ClipboardPort.writeText` has no cancellation facility; strict last-request-wins across such a late platform effect remains unproven.
- D-16 exact current-pointer placement was not observed; startup placement remains best effort and Wayland compositor controlled. D-17 API-key preservation was not exercised by this plan; its owner-approved exception remains recorded in the phase context.
- No native X11 or Wayland clipboard or accessibility observation was performed.

## Known Stubs

None. The existing `placeholder` comment in the panel prohibits fabricated suggestion text; it is not a UI stub.

## Next Phase Readiness

The copy queue and card status are available to later panel work. Native clipboard behavior after a timed-out write remains an observation and port-capability limit.

## Self-Check: PASSED

All eight changed source or existing test files and this summary exist. All three production commit hashes resolve, and the measured plan commit count is three. Both deviation ledger entries were marked fixed.
