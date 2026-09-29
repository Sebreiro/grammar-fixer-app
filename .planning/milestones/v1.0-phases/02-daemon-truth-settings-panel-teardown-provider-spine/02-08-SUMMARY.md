---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 08
subsystem: panel
tags: [flutter, riverpod, correction, lifecycle]
requires:
  - phase: 02-01
    provides: stable correction controller with in-place active pair updates
  - phase: 02-07
    provides: correction panel copy status and controller-owned state
provides:
  - correction controller dependencies remain fixed for the container lifetime
  - panel rebinds its state stream if the controller provider is explicitly replaced
affects: [PANEL-06, 02-09]
actuals:
  tokens: 1886
  tasks: 2
  commits: 2
commits: 2
plan_head_before: 51f8f23f52630ebe4d1e001703d54abdf538fbd8
tech-stack:
  added: []
  patterns: [stable controller identity, observed provider replacement]
key-files:
  created: []
  modified:
    - lib/src/application/composition/controller_providers.dart
    - lib/src/application/composition/daemon_graph.dart
    - lib/src/ui/panel/correction_panel.dart
key-decisions:
  - A config commit updates the active provider and preset on one correction controller, without a reactive rebuild.
  - The panel observes explicit controller replacement and transfers unfinished editor text when the new controller has no text.
patterns-established:
  - Container-lifetime ports are read when building the correction controller; active correction settings are updated in place.
requirements-completed: [PANEL-06]
coverage:
  - id: PANEL-06
    description: Provider and preset refresh keep the warm panel attached to its live controller; an explicit replacement rebinds its state stream.
    requirement: PANEL-06
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: integration
        ref: dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart && flutter test --exclude-tags=live test/ui test/platform test/composition
        status: pass
      - kind: other
        ref: source inspection of controller_providers.dart, daemon_graph.dart, and correction_panel.dart
        status: pass
    human_judgment: false
duration: 5min
completed: 2026-09-24
status: complete
---

# Phase 2 Plan 08: Live correction controller binding summary

**Provider and preset changes retain the warm panel's controller, while an explicit controller replacement moves the panel's state subscription and keeps its editor text.**

## Performance

- **Started:** 2026-09-24T16:32:11Z
- **Completed:** 2026-09-24T16:36:59Z
- **Tasks:** 2
- **Files modified:** 3
- **Production commits:** 2, measured from `plan_head_before`

## Accomplishments

- The correction controller reads its fixed container ports without reactive dependencies. A committed config change continues to update its provider and preset pair in place, leaving the controller and any in-flight run alive.
- The panel observes correction controller identity. If the provider is explicitly replaced, it cancels the old state subscription, subscribes to the new stream, and keeps the current editor text when the new controller has none.
- The panel closes its provider and stream subscriptions on widget disposal; a late close from a superseded controller cannot be mistaken for the current controller's shutdown.

## Task Commits

1. **Task 1: Pin the stable controller identity in composition** — `d13bf14` (`fix`).
2. **Task 2: Bind the widget to the lifetime actually guaranteed** — `8a92cca` (`fix`).

## Decisions Made

- Keep `CorrectionController` stable for normal config changes. The only shipped config refresh path calls `DaemonGraph._applyActiveConfig`, which updates the pair on the existing instance.
- Observe explicit provider invalidation at the panel boundary because Riverpod's provider type alone does not guarantee identity. Preserve the editor's text during that exceptional handoff without touching normal provider changes.

## Deviations from Plan

None - plan executed exactly as written.

## Verification and Limits

- `dart analyze --fatal-infos` passed after each task.
- Existing Dart phase suite passed with 982 tests and two existing skips. Existing Flutter phase suite passed with 165 tests and seven existing skips. No new tests, gate, CI, or runtime observation work was added.
- Source inspection traces config writes to in-place pair replacement, with no production controller invalidation path. The panel listener covers an explicit replacement and transfers editor text. The existing suites do not contain a dedicated controller-invalidation scenario, so that exceptional handoff is supported by source inspection and analysis rather than a behavior assertion.
- D-16 exact current-pointer placement was not observed; startup placement remains best effort and Wayland compositor controlled. D-17 API-key preservation was outside this plan and was not exercised; its owner-approved exception remains in phase context.

## Known Stubs

None. The existing `placeholder` comment in the panel prohibits fabricated suggestion text; it is not a UI stub.

## Next Phase Readiness

The panel follows the live correction controller while retaining text across provider changes. The phase can continue with the later settings and panel plans.

## Self-Check: PASSED

All three modified source files and this summary exist. Both task commit hashes resolve, and the measured production commit count is two.
