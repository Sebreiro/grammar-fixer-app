---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 27
subsystem: hotkey
tags: [wayland, portal, settings, tray, retained-session]
requires:
  - phase: 02-03
    provides: Settings-owned typed status pushed to the tray
  - phase: 01-hotkey-truth
    provides: Wayland session filtering and backend-event precedence
provides:
  - Typed HotkeyRetained result for a refused Wayland Session.Close with the old session live
  - Saved restart seed and truthful Settings and tray refusal presentation
  - Existing-row source-level checks for retained activation and later event precedence
affects: [02-28-generated-record-reconciliation, SETTINGS-02, SETTINGS-03, SETTINGS-06, SETTINGS-08]
actuals:
  tokens: 5408
  tasks: 2
  commits: 2
commits: 2
plan_head_before: 81e06c2498eff3997f3bd91efe75e27669659a8f
tech-stack:
  added: []
  patterns: [typed retained outcome, saved-seed precedence, status-owned temporary refusal]
key-files:
  created:
    - .planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-27-SUMMARY.md
  modified:
    - lib/src/domain/hotkey/hotkey_bind_outcome.dart
    - lib/src/domain/hotkey/global_hotkey.dart
    - lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart
    - lib/src/application/settings_controller.dart
    - lib/src/ui/settings/settings_screen.dart
    - lib/src/ui/settings/hotkey_status_view.dart
    - lib/src/infrastructure/tray/tray_manager_tray.dart
    - test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart
    - test/application/settings_controller_test.dart
    - test/ui/settings/settings_screen_hotkey_test.dart
    - test/infrastructure/tray/tray_manager_tray_test.dart
key-decisions:
  - D-21's owner-ratified HotkeyRetained is a third typed outcome; the existing AD-9 fields and constructors are unchanged.
  - A newer observed backend event wins over a bind answer; structured effective data becomes the restart seed, while an unstructured event preserves the prior saved seed.
  - D-20 waives eight live checks without treating them as observed passes.
requirements-completed: [SETTINGS-02, SETTINGS-03, SETTINGS-06, SETTINGS-08]
duration: approximately 20min
completed: 2026-09-26
status: complete
---

# Phase 02 Plan 27: Retained Wayland Rebind Summary

**A refused Wayland Session.Close now reports the still-working old shortcut, keeps its saved restart seed, and shows a temporary refusal in Settings and tray.**

## Accomplishments

- Added value-equal `HotkeyRetained` with the prior `HotkeyRegistration`. The Wayland adapter returns it only after a refused Close on a live session. It preserves the old Activated filter and localized description; a later `ShortcutsChanged` can replace it with bound or revoked status.
- Settings treats a retained result as a rejected replacement. The rejected request is not saved or shown as effective. When the portal supplies no structured combination, the capture field returns to the saved prior seed after refusal. The typed status renders the refusal, so a newer backend event removes it.
- The tray keeps the normal available icon and enabled Open the panel action while showing a temporary refusal line. A newer bound status removes that line; revocation replaces it with the unavailable status.
- Strengthened existing Wayland A6, Settings controller, Settings widget, and tray rows in place. No named test row or test file was added.

## Task Commits

1. **Task 1: Return a typed retained outcome and keep the old restart seed** — `6646639`.
2. **Task 2: Carry retained refusal through tray and strengthen existing proof** — `f629189`.

## Verification

- `dart analyze --fatal-infos` — passed with no issues.
- Focused Dart suites for Wayland adapter, Settings controller, and tray — 152 passed.
- Focused Settings widget suite — 20 passed after the final capture reseeding fix.
- Existing full local Dart gate (`test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart`, excluding `live`) — 982 passed, 2 skipped.
- Existing full local Flutter gate (`test/ui test/platform test/composition`, excluding `live`) — 165 passed, 7 skipped. This gate ran before the final capture reseeding change; the focused widget suite and analyzer were rerun afterward and passed.
- `git diff --check` — passed. The task diff measured 21,633 characters / 4 = 5,408 estimate-scale tokens and two commits from the persisted plan base.

These are local source-level checks. The eight D-20 live checks remain waived and unobserved; no real compositor, tray host, or event/cache timing measurement is claimed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserve a newer observed backend event when a fake bind records a stale answer**
- **Found during:** Task 1 source review and Task 2 C6 row.
- **Issue:** `changeHotkey` consulted `current` before its already-observed event state. A delayed bind answer could therefore replace the event's structured effective binding in config, despite the generation guard preserving the event on screen.
- **Fix:** Prefer the observed event state after generation changes. Keep the prior seed for an unstructured event and persist a structured effective binding per D-18. Strengthened the existing C6 row.
- **Files:** `settings_controller.dart`, `settings_controller_test.dart`.
- **Commits:** `6646639`, `f629189`.

**2. [Rule 1 - Bug] Reseed the capture field after a retained refusal**
- **Found during:** Task 2 final source review.
- **Issue:** The field retained the rejected draft when its saved binding value did not change, even though config correctly kept the old restart seed.
- **Fix:** Remount the capture field when the retained mutation completes and assert the saved prior combination in the existing A3 widget row.
- **Files:** `settings_screen.dart`, `settings_screen_hotkey_test.dart`.
- **Commits:** `6646639`, `f629189`.

The existing A24 logger-resilience row also changed its expected refused-Close result from `HotkeyBound` to `HotkeyRetained`; its first focused run timed out before that expectation was updated. The corrected focused and full local Dart runs passed.

## Known Stubs

None introduced. No skipped test or unrun planned local verification was added.

## Threat Surface

No new endpoint or file-access boundary was introduced. The existing portal-to-status boundary now distinguishes a refused Close with a live old session from a dead transport or revocation; the status-to-config boundary keeps rejected requests out of persisted restart state.

## Self-Check: PASSED

All eleven assigned source and test files exist, both task commits resolve, and the persisted plan ledger measures two task commits. The generated architecture and WINDOWS.md follow-up remains assigned to plan 02-28.
