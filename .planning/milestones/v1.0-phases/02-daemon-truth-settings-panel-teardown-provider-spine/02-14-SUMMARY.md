---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 14
subsystem: daemon lifetime
tags: [flutter, startup, teardown, portal, cancellation]
requires:
  - phase: 02-13
    provides: Guarded startup abort and early acquisition
  - phase: 02-07
    provides: Tray Quit routed through the lifecycle
provides:
  - Bounded ordered release before and after lifecycle construction
  - Stop request joined with startup bind ownership before teardown
  - Cancelled correction runs cannot record a late stream completion
affects: [provider adapter, daemon lifetime, startup]
actuals:
  tokens: 3188
  tasks: 2
  commits: 3
plan_head_before: 6c1f8b9645c4ec8f2534728f3bda1db9ad4a1673
tech-stack:
  added: []
  patterns: [shared bounded release step, cached stop future, startup completion join]
key-files:
  created: []
  modified: [lib/main.dart, lib/src/infrastructure/system/daemon_lifecycle.dart, lib/src/infrastructure/system/daemon_startup.dart, lib/src/application/correction_controller.dart]
key-decisions:
  - Use the existing composition-root duration for each abort and lifecycle release step.
  - Let stop end the startup bind wait, then join startup before releasing resources.
  - Mark cancelled correction runs terminal before cancelling their subscription.
requirements-completed: [STARTUP-03, STARTUP-05]
coverage:
  - id: D1
    description: Every pre-lifecycle release await uses the shared per-step bound and continues after a failed step.
    requirement: STARTUP-03
    verification:
      - kind: other
        ref: Source inspection of main.dart and daemon_lifecycle.dart; dart analyze --fatal-infos
        status: pass
    human_judgment: true
    rationale: Process exit and native release ordering have no existing runtime observation for this path.
  - id: D2
    description: A stop during portal bind joins startup before one ordered teardown and avoids a disposed graph handoff.
    requirement: STARTUP-05
    verification:
      - kind: other
        ref: Source inspection of main.dart, daemon_startup.dart, daemon_lifecycle.dart, and correction_controller.dart
        status: pass
    human_judgment: true
    rationale: Native stop and portal event ordering remains source inspection evidence.
duration: 11min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 14: Bounded Startup and Stop Teardown Summary

**Startup abort and normal stop now share a bounded release step; stop during portal bind joins startup ownership before the resource graph closes.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-09-24T16:41:13Z
- **Completed:** 2026-09-24T16:51:44Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- The pre-lifecycle abort releases controllers, graph, panel, tray, hotkey, database, config, and address in order. Each await receives the same injected duration, records only safe error types, and continues after failure or timeout. The early registrar-only path is bounded too.
- A cached lifecycle stop future signals the startup bind to return. Shutdown joins startup's completion boundary before it begins ordered release. The bind outcome is applied only while the graph is live.
- A cancelled correction run becomes terminal before subscription cancellation, so late `onDone` cannot turn it into a persisted failure. A normal terminal event still owns its one history result.

## Task Commits

1. **Task 1: Bound every pre-lifecycle release step** — `2dc5385` (`fix`)
2. **Task 2: Join a stop requested during portal bind** — `7e23f25` (`fix`)
3. **Task 2 gate compatibility fix** — `4c868b6` (`fix`)

## Verification

- `dart analyze --fatal-infos` passed after each task and after the gate compatibility fix.
- The existing Flutter suite passed: 165 passed, 7 existing skips.
- The first full Dart run found two architecture assertions tied to the previous abort call shape and budget argument count. After the narrow fix, the targeted architecture suite passed (35 tests) and the full Dart suite passed (982 passed, 2 existing skips).
- Source inspection establishes the Dart ordering and ownership boundary. Native stop and portal callback ordering was not observed by an existing test.

## Decisions Made

- Reused one composition-root duration for all release steps. A timeout abandons the wait; it cannot cancel an adapter call that has already started.
- Kept the startup completion join bounded. If a different startup step exceeds that bound, teardown proceeds and later startup stages check the stop state before touching the graph.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Cancelled stream completion could persist a false failure**
- **Found during:** Task 2
- **Issue:** `_cancelRun` cleared the active run but left its terminal flag unset, so a late `onDone` could persist a failure for a cancelled correction.
- **Fix:** Mark the run terminal before cancelling the subscription; keep provider stream error text out of the panel message.
- **Files modified:** `lib/src/application/correction_controller.dart`
- **Verification:** Analyzer and existing correction-controller suite passed.
- **Committed in:** `7e23f25`

**2. [Rule 3 - Blocking issue] Architecture source assertions assumed the old abort call shape**
- **Found during:** Phase gate after Task 2
- **Issue:** The existing wiring assertions expected `_abort`'s earlier argument list and exactly three named budget call sites.
- **Fix:** Kept the abort guard call shape and injected the same duration through the abort helper's default and the release function's `timeout` argument.
- **Files modified:** `lib/main.dart`
- **Verification:** Targeted architecture suite passed, 35 tests.
- **Committed in:** `4c868b6`

## Known Stubs

None introduced or modified by this plan.

## Limits

The timeout bounds waiting, not native work already issued. Native event ordering remains unobserved; the claims here come from source inspection and existing suites.

## Self-Check: PASSED

All four modified source files exist, and all three task commits are present in the repository.

---
*Phase: 02-daemon-truth-settings-panel-teardown-provider-spine*
*Completed: 2026-09-24*
