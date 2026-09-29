---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 13
subsystem: daemon startup
tags: [flutter, startup, single-instance, abort]
requires:
  - phase: 02-05
    provides: Startup window preparation and composition-root context
provides:
  - Fatal abort exits even when logging or cleanup fails
  - Startup acquisition and secondary-instance exit covered by the main abort guard
affects: [daemon lifetime, startup teardown]
actuals:
  tokens: 2792
  tasks: 2
  commits: 2
plan_head_before: ab5ff8f8b6ab5dde767450c445429d62a1ba7437
tech-stack:
  added: []
  patterns: [guarded startup acquisition, fatal exit in finally]
key-files:
  created: []
  modified: [lib/main.dart, lib/src/infrastructure/system/daemon_startup.dart]
key-decisions:
  - Keep the lock owned by DaemonStartup.begin until it returns or releases it on failure.
  - Use the existing privacy-safe logger guard, with process exit in a finally tail.
requirements-completed: [STARTUP-01, STARTUP-02]
coverage:
  - id: D1
    description: Abort logger and cleanup failures reach exit(1).
    requirement: STARTUP-01
    verification:
      - kind: other
        ref: Source inspection of lib/main.dart _abort; dart analyze --fatal-infos
        status: pass
    human_judgment: true
    rationale: The real GTK process exit ordering was not observed by an existing test.
  - id: D2
    description: Begin and secondary-instance exit run within the startup abort guard.
    requirement: STARTUP-02
    verification:
      - kind: other
        ref: Source inspection of lib/main.dart main and daemon_startup.dart begin; existing phase suites
        status: pass
    human_judgment: true
    rationale: Native process ordering remains inspection evidence in this plan.
duration: 7min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 13: Guard Startup Abort Paths Summary

**Fatal startup cleanup now reaches process exit, and early daemon acquisition and secondary-instance exit run under the same abort guard as later startup.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-09-24T15:31:01Z
- **Completed:** 2026-09-24T15:37:40Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `_abort` keeps its privacy-safe `_log` wrapper and invokes `exit(1)` from `finally`, even if cleanup throws.
- `main` catches a rejection from `DaemonStartup.begin` and a failure in the secondary-instance exit branch. Before `begin` returns, abort closes its registrar; `begin` owns and releases the lock on its own failure path.
- The lock acquisition and warning path is inside `DaemonStartup.begin`'s release guard, closing the gap between binding the address and constructing the startup object.

## Task Commits

1. **Task 1: Make abort logging unable to abort the abort** — `f726aa4` (`fix`)
2. **Task 2: Move all early startup branches inside the abort guard** — `0e5e28c` (`fix`)

## Verification

- `dart analyze --fatal-infos` passed after each task.
- Existing phase gate passed: Dart suite 982 passed, 2 skipped; Flutter suite 165 passed, 7 skipped.
- The `begin`, secondary exit, and fatal exit order was checked in source. No new native runtime observation was made, so native event ordering remains unobserved.

## Decisions Made

- `DaemonStartup.begin` retains responsibility for a lock that has not yet reached `main` as a completed startup object. `main` handles the registrar and process exit in that interval.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Cleanup failure could bypass fatal exit**
- **Found during:** Task 1
- **Issue:** The planned logger isolation already existed through `_log`, but a thrown cleanup step could still skip the trailing `exit(1)`.
- **Fix:** Put the abort cleanup inside `try` and the fatal exit inside `finally`.
- **Files modified:** `lib/main.dart`
- **Commit:** `f726aa4`

## Known Stubs

None introduced or modified by this plan.

## Limits

- Existing tests exercise startup and architecture seams, but do not execute `main`'s actual GTK process exit branch. The exit guarantee here is source-order evidence.

## Self-Check: PASSED

Both modified source files, this summary, and both task commits exist.
