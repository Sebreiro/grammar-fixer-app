---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 02
subsystem: settings
tags: [flutter, hotkey, config, file-watch]
requires:
  - phase: 02-01
    provides: committed Settings changes reach the live daemon graph
provides:
  - rebinds persist the structured effective shortcut instead of a refused request
  - external config edits are observed and serialized with in-app mutations
  - stale writes retry against the hand-edited config without discarding unrelated settings
affects: [02-03, 02-04, SETTINGS-02, DW-84]
actuals:
  tokens: 3896
  tasks: 2
  commits: 2
commits: 2
plan_head_before: ce978e32ae668f6471a6cb00ced288591a681bac
tech-stack:
  added: []
  patterns: [effective-binding write-through, directory watch for atomic replacement, config compare-and-retry]
key-files:
  created:
    - lib/src/domain/config/config_write_conflict.dart
  modified:
    - lib/src/application/settings_controller.dart
    - lib/src/infrastructure/config/json_config_store.dart
    - test/application/settings_controller_test.dart
    - test/ui/settings/settings_screen_hotkey_test.dart
key-decisions:
  - Persist a machine-readable effective binding when the backend supplies one; retain the configured binding as a restart seed when no structured effective value exists.
  - Treat an external file change as a conflict before replacing the file, then rederive the intended Settings mutation from the newer config.
patterns-established:
  - External config and backend binding changes pass through the SettingsController mutation sequence.
requirements-completed: [SETTINGS-02]
coverage:
  - id: SETTINGS-02-effective
    description: A refused rebind retains the previous structured shortcut and a later structured backend read-back writes the effective one.
    requirement: SETTINGS-02
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: integration
        ref: dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart
        status: pass
      - kind: automated_ui
        ref: flutter test --exclude-tags=live test/ui test/platform test/composition
        status: pass
    human_judgment: true
    rationale: The existing suites pass after the post-close repair, but real Wayland read-back is limited to a localized description.
  - id: SETTINGS-02-external
    description: File edits reach Settings and concurrent saves preserve unrelated edited fields.
    requirement: SETTINGS-02
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: integration
        ref: dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart
        status: pass
    human_judgment: true
    rationale: The existing suite passes; native file watcher behavior remains a source-level claim in this workspace.
duration: 9min
completed: 2026-09-24
status: complete
---

# Phase 2 Plan 02: Effective hotkey and config synchronization summary

**Settings now writes the backend's structured effective shortcut, observes hand edits, and retries a concurrent save from the latest file contents.**

## Performance

- **Started:** 2026-09-24T14:50:37Z
- **Completed:** 2026-09-24T14:58:56Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- `changeHotkey` derives its persisted combination from the backend's current or returned outcome. A refused rebind keeps the previously configured working shortcut; an unavailable status remains visible in Settings while the configured value serves as a restart seed.
- Startup and backend-originated structured read-backs enter the same serialized Settings path and update the one config binding. A newer backend event supersedes an in-flight bind answer.
- `JsonConfigStore` watches the containing directory to survive atomic replacement. Before a Settings write, it checks disk against its cached config; a hand edit updates the cache and triggers a retry so unrelated provider and preset fields survive. External edits are applied through `SettingsController` after a pending mutation.

## Task Commits

1. **Task 1: Persist the effective binding after every bind outcome** — `8d2dbfc` (`fix`)
2. **Task 2: Preserve external config and mutation ordering** — `14b01aa` (`fix`)

## Decisions Made

- `AppConfig.hotkeyBinding` stays one nonnullable field. When no machine-readable effective binding exists, its value is a restart seed; `HotkeyBindOutcome` distinguishes bound, refused, revoked, and no-backend state. No second persisted preference was added.
- D-17 owner exception applies: a key already hand-placed under provider settings is carried through a whole-config Settings save. This code creates no key and copies no environment or keyring key into config. The Phase 2 spec's literal no-write wording therefore cannot be claimed for that preserved field.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Correctness] Added a write-conflict value at the config port**
- **Found during:** Task 2
- **Issue:** A directory watch alone cannot guarantee that a hand edit arriving just before a Settings write has been observed.
- **Fix:** The store rereads disk immediately before replacement, reports a `ConfigWriteConflict`, and Settings retries its change against the refreshed value.
- **Files modified:** `lib/src/domain/config/config_write_conflict.dart`, `lib/src/infrastructure/config/json_config_store.dart`, `lib/src/application/settings_controller.dart`
- **Verification:** `dart analyze --fatal-infos` passed; source inspection traced the conflict and retry.
- **Committed in:** `14b01aa`

**Total deviations:** 1 correctness addition. **Impact:** A third domain file names the conflict across the existing port boundary.

## Verification and Limits

- `dart analyze --fatal-infos` passed after each task and after the post-close repair. At initial plan closure the existing suites were reserved for the phase gate; they were subsequently run for the repair. Dart passed 982 tests with two existing skips, and Flutter passed 165 tests with seven existing skips. No new test, gate, CI, or runtime observation work was added.
- Source inspection traced a refused X11 rebind to its retained prior effective value, an external config edit through the watcher and Settings queue, and a stale write through compare-and-retry. SETTINGS-02 carries DW-84's contingent closure.
- **D-18 limit:** The shipped Wayland portal adapter reports `HotkeyRegistration.effective == null`; its localized `trigger_description` is display text and cannot safely be parsed as a key combination. The code persists a compositor-reported combination if a backend supplies one. With today's portal reply, the config retains the submitted binding as a restart seed while Settings shows the portal's authoritative description or unavailable status. A future backend or portal API that exposes a structured trigger is required before the config can name Wayland's exact effective combination.
- **D-16 limit:** Pointer-display placement was not changed or observed by this plan.
- **D-17 limit:** Preservation of a user-authored plaintext config key is the approved exception described above; this plan did not observe keyring or provider operation.

## Known Stubs

None in the files changed by this plan.

## Next Phase Readiness

Settings and config now have a file-change path for the later provider/settings work. Real Wayland structured effective read-back remains unavailable from the current portal response; the phase verifier must keep that limit explicit.

## Self-Check: PASSED

All three changed source files and this summary exist; both task commits are present. The measured task-commit count is two.

## Post-close regression repair — 2026-09-24

The first phase-gate run after plan 02-06 exposed six focused `SettingsController` failures, two Settings hotkey widget failures, and twelve `JsonConfigStore` failures in the full Dart suite. Commit `2308f5b` repaired the regressions without changing the one-effective-binding decision.

- A duplicate config event reaching a second controller after its state already matched caused an extra terminal frame. The external-change path now ignores equal state, preserving one result frame for an in-app bind.
- The store's disk comparison ran even before its first `load()`, when it had no cached baseline. Writes before load now remain valid; loaded stores still compare disk and retry a hand edit before replacement.
- Existing Settings assertions that required persisting a refused request or a separate Wayland preference were updated to D-18: config follows a structured effective read-back and retains the prior restart seed on refusal. No new tests were added.

**Repair verification:** `dart analyze --fatal-infos` passed; focused `settings_controller_test.dart` passed 52/52, `json_config_store_test.dart` passed 26/26, and `settings_screen_hotkey_test.dart` passed 20/20. The full existing Dart suite passed 982 tests with two existing skips; the full existing Flutter suite passed 165 tests with seven existing skips. There are no residual test failures.
