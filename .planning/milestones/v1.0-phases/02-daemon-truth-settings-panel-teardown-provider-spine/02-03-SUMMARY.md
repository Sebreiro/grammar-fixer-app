---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 03
subsystem: hotkey-and-tray
tags: [flutter, hotkey, tray, settings]
requires:
  - phase: 02-02
    provides: effective binding and serialized Settings state
provides:
  - Settings-owned hotkey outcomes reach the tray after startup and on later changes
  - tray icon and one disabled menu line reflect availability and cause
  - retained X11 rebind refusal is visible in Settings and tray together
affects: [SETTINGS-03, SETTINGS-06, SETTINGS-08, 02-04]
tech-stack:
  added: []
  patterns: [typed tray status snapshot, serialized tray updates]
key-files:
  created:
    - lib/src/domain/tray/hotkey_tray_status.dart
  modified:
    - lib/src/application/settings_controller.dart
    - lib/src/application/settings_state.dart
    - lib/src/application/composition/daemon_graph.dart
    - lib/src/domain/tray/tray_port.dart
    - lib/src/infrastructure/tray/tray_manager_tray.dart
    - lib/main.dart
    - test/fakes/fake_tray_port.dart
    - test/infrastructure/system/daemon_startup_test.dart
key-decisions:
  - Keep SettingsController as the single subscription to bindingChanges; the graph forwards its state snapshots to the tray.
  - Retain the boolean tray setter solely for the startup bind hand-off and existing port users; typed snapshots own subsequent status.
  - Mark a retained X11 rebind refusal on SettingsFailure so the tray note has exactly the same lifetime as the visible Settings error.
actuals:
  tokens: 4736
  tasks: 2
  commits: 3
commits: 3
plan_head_before: 6fdd06eb664bcf18fa077a00947d67d53348f37b
duration: 12min
completed: 2026-09-24
status: complete
---

# Phase 2 Plan 03: Hotkey status reaches Settings and tray

**The tray now follows the same current hotkey outcome as Settings, showing a warning icon and one cause-specific line only while no shortcut works.**

## Accomplishments

- `SettingsController` remains the sole subscriber to backend binding changes. `DaemonGraph` forwards its current outcome to `TrayPort` after the startup seed and on every later Settings transition, serializing native tray calls so an older push cannot overtake a newer one.
- The tray renders distinct lines for no backend, refused binding, and compositor revocation. Each line sits below the enabled Open the panel action; Quit remains enabled. Restoration removes the line and warning icon without a notification.
- When an X11 rebind returns the previous working registration, Settings displays a refusal error. The typed tray snapshot carries that same error state, so its temporary refusal line clears when Settings clears the error. The icon stays normal while the previous shortcut works.

## Task Commits

1. **Task 1: Fan out one hotkey status snapshot to both consumers** — `dfb8335`.
2. **Task 2: Render accurate tray icon and one line** — `ea5bcd7`.
3. **Rule 2 correctness fix: Guard tray status teardown** — `e9f03d6`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Correctness] Guarded the new tray subscription during shutdown**
- **Found during:** Final source inspection after Task 2.
- **Issue:** A rejecting `StreamSubscription.cancel()` could stop the existing ordered controller teardown.
- **Fix:** Route cancellation and pending status updates through `DaemonGraph`'s guarded disposal helper.
- **Files modified:** `lib/src/application/composition/daemon_graph.dart`.
- **Commit:** `e9f03d6`.

## Verification and Limits

- `dart analyze --fatal-infos` passed after each task and after the teardown fix. The existing focused Settings and tray suites passed 81/81.
- The required full Dart suite passed 982 tests with 2 existing skips; the required Flutter suite passed 165 tests with 7 existing skips. No new test, gate, CI, or runtime-observation work was added.
- Static inspection traced startup binding, later backend changes, refused X11 rebinds, and restoration through the one controller state stream into the tray. This workspace did not observe a live compositor or StatusNotifier host.
- **Wayland retained-binding limit:** The current portal adapter can return the prior `HotkeyBound` status when closing the old session is refused, but that status carries no typed indication that the attempted replacement was refused. A bound result with no structured effective trigger is also the normal Wayland success shape. This plan does not guess from localized description text or report a working shortcut as unavailable. That particular retained Wayland refusal therefore keeps the accurate normal icon but has no temporary refusal line. A distinct adapter outcome would be needed to close this edge without a false refusal claim. Tracked as `.planning/WINDOWS.md` entry 41 (`unmet-truth`).
- **D-16:** No pointer-display positioning was changed or measured; startup-prepared placement remains best effort on Wayland.
- **D-17:** No API-key path was changed. The previously approved preservation of a user-authored plaintext config key on whole-file Settings saves remains the documented exception to the phase spec's literal no-write wording.

## Known Stubs

None in the files changed by this plan.

## Self-Check: PASSED

The new status type and this summary exist; all three task and correctness commits exist. The plan ledger measures three commits from `6fdd06e` through HEAD.
