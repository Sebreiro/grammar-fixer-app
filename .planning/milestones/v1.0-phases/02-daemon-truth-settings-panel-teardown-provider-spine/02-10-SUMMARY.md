---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 10
subsystem: panel
tags: [flutter, linux, window-manager, session-attribution]
requires:
  - phase: 02-09
    provides: generation-owned native requests and stale-call repair
provides:
  - GTK hide echoes cannot create a new dismissal after a later show
  - stale focus-loss delivery cannot discard a Settings draft after the panel returns
affects: [PANEL-19, panel-session-lifecycle]
actuals:
  tokens: 4433
  tasks: 2
  commits: 3
commits: 3
plan_head_before: bf04faad9e2824f3aca8966eaa8d08c6135c8df5
tech-stack:
  added: []
  patterns: [request-owned panel departures, current-mirror check for asynchronous focus loss]
key-files:
  created: []
  modified:
    - lib/src/infrastructure/panel/window_manager_panel_visibility.dart
    - lib/src/application/panel_controller.dart
    - test/infrastructure/panel/window_manager_panel_visibility_test.dart
key-decisions:
  - "The Linux plugin's GTK hide callback is an unlabelled echo of the adapter's own hide request; only that request may report its session departure reason."
  - "PanelController checks current visibility before relaying a delayed focus-loss event to Settings; CorrectionController retains editor text and an active correction on hide."
patterns-established:
  - "Native request generation governs stale-call repair; a bare GTK echo does not infer a new session reason from the current mirror."
requirements-completed: [PANEL-19]
coverage:
  - id: PANEL-19-late-hide
    description: A late abandoned hide echo cannot turn a completed show into dismissal or clear nonempty editor text.
    requirement: PANEL-19
    verification:
      - kind: unit
        ref: test/infrastructure/panel/window_manager_panel_visibility_test.dart
        status: pass
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
    human_judgment: true
    rationale: Native GTK and compositor event ordering was established by installed plugin source inspection, not observed in a live session.
duration: 10min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 10: Panel hide echo attribution summary

**The panel keeps its editor session when an abandoned GTK hide echo arrives after a completed show, while stale focus loss cannot reset a returned Settings view.**

## Performance

- **Started:** 2026-09-24T18:13:28Z
- **Completed:** 2026-09-24T18:23:22Z
- **Tasks:** 2
- **Files modified:** 3
- **Production and assertion commits:** 3, measured from `plan_head_before`

## Accomplishments

- `WindowManagerPanelVisibility` reports `dismissed` or `focusLost` when the owning hide request is made. It ignores the unlabelled GTK `hide` callback, which may arrive after the request times out, settles, or a later show completes. Request generations still govern repair of stale native calls.
- `PanelController` relays only an attributed focus loss that still matches the current hidden mirror. It never edits correction text or cancels an active correction; `CorrectionController` continues to own both under AD-4. The editor text is neither trimmed nor re-encoded, and an empty editor needs no special action.
- Three existing fake-window assertions were aligned with the installed plugin's GTK signal path. The close-after-hidden case now uses an iconify to create its hidden mirror premise.

## Task Commits

1. **Task 1: Separate completed session reason from stale native echo** — `7f31f07` (`fix`).
2. **Task 2: Carry the corrected reason into panel state** — `d1d1282` (`fix`).
3. **Existing assertion alignment after phase-gate failure** — `af970a5` (`test`).

## Verification

- `dart analyze --fatal-infos` passed after each task and after the assertion alignment.
- Focused existing adapter suite: 91 passed.
- Existing Dart phase suite: 982 passed, 2 skipped. Existing Flutter phase suite: 165 passed, 7 skipped.
- Source inspection: installed `window_manager` 0.5.2 connects `on_window_hide` to GTK widget `hide` at `linux/window_manager_plugin.cc:991,1112`; the plugin's hide method calls `gtk_widget_hide` at lines 101–106. The repository's sole `windowManager.hide()` call is in `WindowManagerPanelWindow.hide()`. The callback supplies no request identity, so a native echo cannot safely name a later session's departure.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking verification issue] Corrected three false fake-window premises**
- **Found during:** Full phase suite after Task 2.
- **Issue:** Three existing assertions treated a spontaneous GTK widget `hide` callback as an external unmap or a new dismissal. The installed plugin emits this callback for its own `gtk_widget_hide` call; the callback contains no request id or departure reason.
- **Fix:** Updated those assertions in the existing adapter test file. The close-after-hidden row now uses a believed iconify to preserve its original close behavior claim.
- **Files modified:** `test/infrastructure/panel/window_manager_panel_visibility_test.dart`.
- **Verification:** Focused adapter suite and both existing phase suites passed.
- **Commit:** `af970a5`.

No new test file, gate, CI work, runtime-observation work, history schema change, or frozen product SPEC edit was added.

## Evidence Limits

The installed plugin source establishes the GTK widget signal and application call path. No live X11 or Wayland session observed the relative delivery order of the GTK callback, method reply, and later show. The source and existing fake tests prove the ownership policy, while native ordering remains unobserved.

## Known Stubs

None in the changed files.

## Self-Check: PASSED

All three changed files and this summary exist; all three production and assertion commits resolve; the persisted ledger measures three commits; `git diff --check` is clean.

---
*Phase: 02-daemon-truth-settings-panel-teardown-provider-spine*
*Completed: 2026-09-24*
