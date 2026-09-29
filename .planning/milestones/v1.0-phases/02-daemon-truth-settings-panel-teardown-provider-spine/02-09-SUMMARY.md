---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 09
subsystem: panel
tags: [flutter, linux, window-manager, focus, async]
requires:
  - phase: 02-05
    provides: warm panel window and visibility adapter
  - phase: 02-08
    provides: stable panel correction controller across refresh
provides:
  - native panel request ownership through timeout and settlement
  - repair of stale native show, focus, and hide calls
  - distinct self and user focus handling for deferred blur
affects: [panel, compositor-observation, phase-02-verification]
actuals:
  tokens: 12240
  tasks: 2
  commits: 3
plan_head_before: 53829b1d670fcde693a97279e2ad6a424844df4d
tech-stack:
  added: []
  patterns: [generation-owned native requests, focus provenance at PanelWindow]
key-files:
  created: []
  modified:
    - lib/src/infrastructure/panel/window_manager_panel_visibility.dart
    - lib/src/infrastructure/panel/panel_window.dart
    - lib/src/infrastructure/panel/window_manager_panel_window.dart
    - test/architecture/panel_event_forwarding_test.dart
    - test/infrastructure/panel/window_manager_panel_visibility_test.dart
key-decisions:
  - "Retain native ownership after a caller timeout; repair stale calls after the latest intent has settled."
  - "Tag expected present focus at PanelWindow and count only user focus when releasing a deferred blur."
patterns-established:
  - "Request generation and native settlement jointly govern panel echo reconciliation."
requirements-completed: [PANEL-10, PANEL-12, PANEL-14, PANEL-15]
coverage:
  - id: D1
    description: Timed-out native calls retain ownership and a stale settlement restores the current panel intent.
    requirement: PANEL-14
    verification:
      - kind: unit
        ref: test/infrastructure/panel/window_manager_panel_visibility_test.dart
        status: pass
    human_judgment: true
    rationale: Real compositor event ordering was not observed in this plan.
  - id: D2
    description: A latched blur suppresses trailing present and self focus cannot cancel dismissal.
    requirement: PANEL-15
    verification:
      - kind: unit
        ref: test/infrastructure/panel/window_manager_panel_visibility_test.dart
        status: pass
    human_judgment: true
    rationale: The native adapter labels focus by expected presentation, and real compositor ordering was not observed.
duration: 18min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 09: Native Panel Request Reconciliation Summary

**Panel native calls retain identity after timeout, stale settlements repair the latest visibility intent, and self focus no longer cancels a deferred click-away.**

## Performance

- **Started:** 2026-09-24T16:56:18Z
- **Completed:** 2026-09-24T17:14:12Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- A timed-out native call remains in flight until its underlying future settles. Its echo cannot be treated as an external panel transition, and a deferred blur waits for settlement.
- A stale show, focus, or hide that lands after the latest intent has settled queues repair in that intent's direction without a second session transition.
- The PanelWindow adapter labels focus expected from its own presentation separately. A latched blur blocks the show's trailing `focus()`, and only a user focus-in can cancel its release.

## Task Commits

1. **Task 1: Retain native request identity** — `2776e24`
2. **Task 2: Discriminate self focus** — `b22fd5d`
3. **Phase-gate repair and existing assertion alignment** — `6aa725d`

## Verification

- `dart analyze --fatal-infos`: no issues.
- Existing Dart suite: 982 passed, 2 skipped.
- Existing Flutter suite: 165 passed, 7 skipped.
- Source inspection establishes the call-boundary checks and retained native ownership. Real X11 and Wayland focus event ordering remains unobserved.

## Deviations from Plan

### Auto-fixed Issues

1. **[Rule 2 - Missing critical functionality] Concrete native focus attribution.** Task 2 also required `window_manager_panel_window.dart`, beyond the plan's file list, because the visibility adapter cannot identify the origin of a bare focus event itself. The change keeps platform event handling behind PanelWindow. Committed in `b22fd5d`.
2. **[Rule 1 - Bug] Normal show queued a redundant repair hide.** The first full gate exposed duplicate hide calls. Recovery now applies only to a successfully settled call that was actually abandoned, after the newer intent settled. A late hide also restores a newer shown intent. Committed in `6aa725d`.
3. **[Rule 1 - Bug] Direct blur after timeout could race native work.** The blur path now checks native calls still in flight as well as active queue links. Existing assertions that encoded the superseded timeout and trailing-focus behavior were revised without adding tests. Committed in `6aa725d`.

## Evidence Limits

The native plugin provides a bare focus event. The concrete adapter tags an expected focus-in from its own show or present call; a compositor that delays or denies that event can still leave origin ambiguous for a later focus-in. This plan adds no runtime observation, so compositor event ordering and keyboard ownership after a late native present remain source-inspection claims.

## Self-Check: PASSED

All five changed files and all three production commits exist; the measured commit count is three and `git diff --check` is clean.

---
*Phase: 02-daemon-truth-settings-panel-teardown-provider-spine*
*Completed: 2026-09-24*
