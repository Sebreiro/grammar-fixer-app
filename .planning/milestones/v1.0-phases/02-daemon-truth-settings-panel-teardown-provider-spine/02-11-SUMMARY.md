---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 11
subsystem: ui
tags: [flutter, hotkey, settings, panel, lifecycle]
requires:
  - phase: 02-03
    provides: current hotkey outcome in Settings state
  - phase: 02-08
    provides: stable correction controller and editor state across panel remounts
provides:
  - a hotkey on visible Settings swaps to the panel without hiding the warm window
  - focus loss and view swaps discard an unapplied capture draft
  - reopening Settings seeds the capture field from the structured effective binding when reported
affects: [SETTINGS-05, SETTINGS-07, panel-session-lifecycle]
actuals:
  tokens: 4160
  tasks: 2
  commits: 4
commits: 4
plan_head_before: b2b6bea810a307ce76ac0f5d93e2b7c7163c7ced
tech-stack:
  added: []
  patterns: [synchronous view state for hotkey decisions, capture-field remount for draft discard]
key-files:
  created: []
  modified:
    - lib/src/application/panel_controller.dart
    - lib/src/ui/daemon_home.dart
    - lib/src/ui/settings/settings_screen.dart
    - lib/src/domain/panel/panel_visibility.dart
    - test/composition/daemon_graph_test.dart
key-decisions:
  - DaemonHome reports the visible view synchronously to PanelController so the hotkey decision never awaits a widget or native call.
  - A focus-loss notification remounts only the hotkey capture field; a Settings-to-panel swap unmounts Settings and preserves CorrectionController.
requirements-completed: [SETTINGS-05, SETTINGS-07]
coverage:
  - id: SETTINGS-07-visible-swap
    description: A hotkey on visible Settings requests the panel without hiding the window; the next press on the panel uses the ordinary toggle.
    requirement: SETTINGS-07
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: automated_ui
        ref: flutter test --exclude-tags=live test/ui test/platform test/composition
        status: pass
    human_judgment: true
    rationale: The existing suite covers summons and ordinary toggles, but native event ordering for this specific visible-Settings press was inspected in source rather than observed on a desktop.
  - id: SETTINGS-05-draft-discard
    description: View swaps and focus-loss departures reset the capture field to the current structured effective binding while retaining the panel session.
    requirement: SETTINGS-05
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: automated_ui
        ref: flutter test --exclude-tags=live test/ui test/platform test/composition
        status: pass
    human_judgment: true
    rationale: The reset and remount ordering is established by source inspection; the current portal supplies localized text rather than a structured Wayland effective combination.
duration: 11min
completed: 2026-09-24
status: complete
---

# Phase 2 Plan 11: Settings hotkey return and draft fate summary

**A hotkey on visible Settings now returns to the warm panel in one press, and abandoned hotkey captures reset to the reported effective shortcut when one is structured.**

## Performance

- **Started:** 2026-09-24T17:19:56Z
- **Completed:** 2026-09-24T17:30:15Z
- **Tasks:** 2
- **Files modified:** 5
- **Production commits:** 4, measured from `plan_head_before`

## Accomplishments

- `DaemonHome` reports when Settings is visible. `PanelController` routes a hotkey in that state through its show request, without issuing a hide. Once the panel is showing, the ordinary hotkey toggle still hides it.
- A Settings-to-panel swap unmounts the capture field and discards its draft. A native focus-loss departure remounts that field through the same widget lifecycle while leaving Settings on screen. The replacement reads the current structured effective binding from `SettingsState` when available.
- The view swap does not touch `CorrectionController`; editor text and an active correction remain owned by the warm panel session. The new visibility listener is canceled during controller teardown, and a late callback cannot publish into its closed focus-loss stream.

## Task Commits

1. **Task 1: Treat hotkey on Settings as a view swap** — `433ff13` (`feat`).
2. **Task 2: Show effective binding after an unapplied draft is discarded** — `e561da3` (`fix`).
3. **Rule 3 teardown assertion and port documentation correction** — `a6027f6` (`fix`).
4. **Rule 2 late-callback guard** — `c459f0f` (`fix`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Aligned existing teardown evidence with the new visibility listener**
- **Found during:** Phase-gate Flutter suite after Task 2.
- **Issue:** The existing teardown assertion expected one visibility-subscription cancellation report; Settings focus-loss handling adds a second production listener, so the assertion failed on the extra report.
- **Fix:** Updated the existing assertion and the port contract comment to name both listeners. No new test file or gate was added.
- **Files modified:** `test/composition/daemon_graph_test.dart`, `lib/src/domain/panel/panel_visibility.dart`.
- **Commit:** `a6027f6`.
- **Ledger:** `.planning/WINDOWS.md` entry 46, fixed.

**2. [Rule 2 - Correctness] Closed publication after cancellation failure**
- **Found during:** Final source inspection.
- **Issue:** If a broken visibility stream rejected cancellation but later invoked its callback, it could add to a closed focus-loss stream during teardown.
- **Fix:** Ignore focus-loss callbacks once the controller's output stream has closed.
- **Files modified:** `lib/src/application/panel_controller.dart`.
- **Commit:** `c459f0f`.
- **Ledger:** `.planning/WINDOWS.md` entry 47, fixed.

## Verification and Limits

- `dart analyze --fatal-infos` passed after each task and after both fixes. The existing Dart phase gate passed 982 tests with two existing skips. After the teardown assertion correction, the existing Flutter phase gate passed 165 tests with seven existing skips. The final late-callback guard was checked with the analyzer and the existing 21-test `panel_controller_test.dart` suite.
- Source inspection traced the Settings flag from `DaemonHome` into the synchronous hotkey decision, then the show request back to the panel swap. It also traced focus-loss through the visibility event to the capture-field remount. No live X11 or Wayland event ordering was observed here.
- **Wayland effective-binding limit:** The current portal reports localized `trigger_description` text but no machine-readable `HotkeyRegistration.effective`. The status view shows that authoritative description; the capture field uses the stored restart preference when no structured effective combination exists. This is the existing D-18 limit recorded in 02-02, not a new claim that the field can reconstruct the compositor's chosen keys.
- No new test file, gate, CI, runtime-observation work, history schema change, or frozen product SPEC edit was added.

## Known Stubs

None in the files changed by this plan.

## Self-Check: PASSED

All five modified source/test files and this summary exist. All four production
commit hashes resolve, and the persisted plan ledger measures four commits from
`b2b6bea` through the final production HEAD.
