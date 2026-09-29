---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 04
subsystem: settings-and-config-diagnostics
tags: [flutter, settings, config, diagnostics, privacy]
requires:
  - phase: 02-02
    provides: serialized Settings mutations and config file change handling
  - phase: 02-03
    provides: shared Settings and tray hotkey status
provides:
  - one outstanding value-based Settings write echo instead of unreachable counted multiplicity
  - safe application-authored startup log messages for config load failures
  - documentation matching the hotkey status line actually rendered
affects: [02-15, 02-25, SETTINGS-04, SETTINGS-09, CONFIG-01]
actuals:
  tokens: 1463
  tasks: 2
  commits: 2
commits: 2
plan_head_before: 2cae186cfce132b553c9c25fd171e85d884099c4
tech-stack:
  added: []
  patterns: [value-based own-write echo set, separate surfaced and logged config warnings]
key-files:
  created: []
  modified:
    - lib/src/application/settings_controller.dart
    - lib/src/domain/config/config_load_result.dart
    - lib/src/infrastructure/config/json_config_store.dart
    - lib/src/infrastructure/system/daemon_startup.dart
    - lib/src/ui/settings/hotkey_status_view.dart
key-decisions:
  - Keep one value-based outstanding echo because SettingsController refuses overlapping mutations.
  - Preserve detailed load-result warnings for existing config diagnostics while logging a separate generic sentence and safe error type at startup.
patterns-established:
  - Startup logs ConfigLoadResult.logWarning when detailed warning text contains user-authored config values.
requirements-completed: [SETTINGS-04, SETTINGS-09]
requirements-pending: [CONFIG-01]
coverage:
  - id: SETTINGS-04-echo
    description: A completed own write suppresses its one echo; a later unmatched external edit enters the Settings refresh queue.
    requirement: SETTINGS-04
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: integration
        ref: dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart
        status: pass
    human_judgment: false
  - id: SETTINGS-09-comment
    description: The unavailable-hotkey documentation names the closing ownership status line that the widget appends.
    requirement: SETTINGS-09
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
    human_judgment: false
  - id: CONFIG-01-local
    description: Config load and seed errors log application-authored warnings and only a safe error type in structured context.
    requirement: CONFIG-01
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: integration
        ref: dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart
        status: pass
    human_judgment: true
    rationale: Two out-of-scope Claude provider log sites still interpolate exception values; the global requirement remains pending 02-15.
duration: 9min
completed: 2026-09-24
status: complete
---

# Phase 2 Plan 04: Settings echoes and config diagnostics

**Settings now tracks one outstanding own-write echo, while config startup logs safe problem sentences and error types without printing caught exception text.**

## Performance

- **Started:** 2026-09-24T16:18:08Z
- **Completed:** 2026-09-24T16:27:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Replaced the counted `Map<AppConfig,int>` with a `Set<AppConfig>`. `_beginMutation` refuses overlapping mutations, `_expectEcho` marks one value, `_forgetEcho` removes it, and an unmatched later config event still reaches `_applyExternalConfig`.
- Config read, JSON parse, and first-run seed failures retain defaults and a warning naming the config path. Startup logs only an application-authored sentence and `error_type` when an exception was caught. Detailed parser and validation warnings remain on the load result for existing diagnostics, while a separate generic sentence is used in the daemon log.
- Corrected `HotkeyStatusView` documentation to describe the closing shortcut-ownership line appended to every unavailable outcome.

## Task Commits

1. **Task 1: Replace obsolete counted echo bookkeeping** — `61c22cc` (`fix`).
2. **Task 2: Remove exception interpolation and fix the false Settings comment** — `3cc4a5d` (`fix`).

## Decisions Made

- Keep the echo set instead of deleting bookkeeping: the store emits the write's config before `write()` resolves, so the controller must recognize its own event while leaving external edits to refresh Settings.
- Keep field-specific parser feedback in `ConfigLoadResult.warning`, as established AD-13 assertions require it. `ConfigLoadResult.logWarning` is the safe text for stderr; startup never logs the detailed value-bearing form for the real JSON store.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking integration] Carry safe diagnostics to the existing startup logger**
- **Found during:** Task 2.
- **Issue:** The plan named only the store and widget, but the store returns `ConfigLoadResult` and `DaemonStartup` performs the actual log call; the type could not reach structured context through the original result.
- **Fix:** Added optional `warningErrorType` and `logWarning` to the result and forwarded them at startup. Detailed warnings remain available without entering the log.
- **Files modified:** `lib/src/domain/config/config_load_result.dart`, `lib/src/infrastructure/system/daemon_startup.dart`.
- **Verification:** Analyzer and existing full suites passed; source inspection traced both warning forms.
- **Committed in:** `3cc4a5d`.

**Total deviations:** 1 blocking integration fix. **Impact:** Two adjacent files beyond the plan's file list carry the safe warning to the existing logger.

## Verification and Limits

- `dart analyze --fatal-infos` passed after each task. The existing full Dart suite passed 982 tests with 2 skips; the existing Flutter suite passed 165 tests with 7 skips. No new test, gate, CI, or runtime-observation work was added.
- Source inspection checked the zero-outstanding-echo path and the later external-edit queue. The full suites exercise the existing Settings transitions; no live file watcher, display server, or tray host was observed in this workspace.
- **CONFIG-01 remains pending globally:** `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart:275` and `:289` still interpolate caught errors in logger context. The file belongs to plan 02-15. These are open `.planning/WINDOWS.md` entries 44 and 45; this plan did not change that provider.
- **D-16:** This plan did not change or observe pointer-display placement. Startup-prepared placement remains best effort on Wayland.
- **D-17:** This plan did not change API-key persistence. The approved exception for preserving a user-authored plaintext config key on a later whole-file Settings save remains in effect; no keyring or provider operation was observed.

## Known Stubs

None in the files changed by this plan.

## Self-Check: PASSED

All five modified source files and both task commits exist. The persisted plan ledger measures two commits from `2cae186` through the task commits. The summary exists on disk.
