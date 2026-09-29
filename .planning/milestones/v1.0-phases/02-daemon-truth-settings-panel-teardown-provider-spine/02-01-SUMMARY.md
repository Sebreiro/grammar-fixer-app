---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 01
subsystem: application
tags: [flutter, riverpod, settings, correction]
requires:
  - phase: 01-hotkey-truth
    provides: stable daemon graph and settings write-through
provides:
  - committed preset selection refreshes the active provider and preset without rebuilding the correction controller
  - each correction retains its submitted pair for streaming and history
affects: [02-02, 02-08, 02-20]
actuals:
  tokens: 2109
  tasks: 2
  commits: 2
commits: 2
plan_head_before: 57488b6456b85d7eacafb81f0bab2618820b332e
tech-stack:
  added: []
  patterns: [composition-root pair resolution, per-run pair snapshot]
key-files:
  created: []
  modified:
    - lib/main.dart
    - lib/src/application/settings_controller.dart
    - lib/src/application/correction_controller.dart
    - lib/src/application/composition/controller_providers.dart
    - lib/src/application/composition/daemon_graph.dart
    - lib/src/ui/settings/preset_choice_list.dart
    - test/ui/settings/settings_screen_config_test.dart
key-decisions:
  - Keep one CorrectionController instance and replace its active provider and preset together after a committed config change.
  - Store the submitted pair on each run so later settings changes cannot relabel history.
patterns-established:
  - The composition root resolves provider IDs; controllers receive only a provider and prompt/model preset.
requirements-completed: [SETTINGS-01]
coverage:
  - id: SETTINGS-01
    description: A committed preset selection changes the next correction while an active run retains its pair.
    requirement: SETTINGS-01
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: integration
        ref: dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart && flutter test --exclude-tags=live test/ui test/platform test/composition
        status: pass
    human_judgment: false
duration: 8min
completed: 2026-09-24
status: complete
---

# Phase 2 Plan 01: Live preset selection summary

**A committed Settings preset choice now supplies the next correction, while streaming and history keep the pair captured by each run.**

## Performance

- **Started:** 2026-09-24T14:20:47Z
- **Completed:** 2026-09-24T14:28:05Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Settings applies successful writes and store change events through one composition-root callback, which resolves one active provider and preset and updates the stable correction controller.
- Each run captures its provider and prompt/model preset at submit. Terminal history rows use that captured preset even when Settings changes during streaming.
- Settings now says that a selection applies to the next correction. The existing UI assertion was updated to match the new behavior.

## Task Commits

1. **Task 1: Trace preset change to a correction** — `7ee53b8` (`feat`)
2. **Task 2: Preserve the in-flight pair** — `f21ed56` (`fix`)

## Decisions Made

- Resolve provider IDs only at the composition root; the controller's mutable record replaces provider and preset in one assignment.
- Leave controller identity stable so a settings write does not cancel an active correction or detach the panel.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Correctness] Production wiring needed the outer composition root**
- **Found during:** Task 1
- **Issue:** The four named application files could not construct a different provider without crossing the infrastructure boundary.
- **Fix:** Added the resolver callback in `lib/main.dart` and injected it into `DaemonGraph`.
- **Verification:** Analyzer and existing suite passed.
- **Committed in:** `7ee53b8`

**2. [Rule 1 - Bug] Settings described the old restart behavior**
- **Found during:** Task 2
- **Issue:** Live preset selection made the existing restart warning false.
- **Fix:** Changed the Settings explanation and its existing assertion.
- **Verification:** Existing Flutter suite passed.
- **Committed in:** `f21ed56`

## Verification and Limits

- `dart analyze --fatal-infos`: passed, including the tracer feedback rerun.
- Existing Dart and Flutter suite: passed. No new test or gate was added.
- Source inspection confirms committed writes call the pair update before `changeActivePreset` returns, and each `_Run` carries the pair used for its provider call and history record.
- `JsonConfigStore.changes` currently emits for store writes but has no filesystem watcher. The same callback handles an external change event if one is emitted; a hand edit of `config.json` is not observed live by the shipped store. This existing limitation should be addressed by the later config-file synchronization work.
- D-16 pointer-display placement was not observed or changed by this plan. D-17's owner-approved key-preservation exception was not exercised by this plan; no key write behavior was changed. These limits are source-level only.

## Known Stubs

None in files changed by this plan.

## Next Phase Readiness

The stable correction controller and pair-update path are available for subsequent Settings and provider plans. The config-file watcher gap remains for the Settings/config synchronization work.

## Self-Check: PASSED

All seven modified source or test files and this summary exist; both task commits are present.
