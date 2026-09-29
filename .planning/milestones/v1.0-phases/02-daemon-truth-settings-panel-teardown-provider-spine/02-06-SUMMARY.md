---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 06
subsystem: ui
tags: [flutter, panel, keyboard, pointer, settings]
requires:
  - phase: 02-05
    provides: warm panel geometry and bounded editor and suggestion regions
provides:
  - actionable suggestion cards select by click without copying
  - selection remains stable on repeated click or digit press
  - physical digit-row positions select variants across keyboard layouts
  - Settings hit area is outside the outlined editor
affects: [02-07, 02-11, PANEL-02, PANEL-04, PANEL-07]
actuals:
  tokens: 4167
  tasks: 2
  commits: 3
commits: 3
plan_head_before: 433ac869cf90a7b346be9f609383052deff2359e
tech-stack:
  added: []
  patterns: [controller-owned selection with UI idempotence guard, physical digit-row event handling, responsive Settings gutter]
key-files:
  created: []
  modified:
    - lib/src/ui/panel/suggestion_card.dart
    - lib/src/ui/panel/suggestion_list.dart
    - lib/src/ui/panel/correction_panel.dart
    - lib/src/ui/daemon_home.dart
    - test/ui/panel/correction_panel_selection_and_copy_test.dart
key-decisions:
  - Treat the displayed digit as a top-row key position; retain the keypad and logical-digit shortcuts while accepting the corresponding physical position on other layouts.
  - Reserve a right gutter for Settings at ordinary widths and use a separate header below 200 logical pixels.
requirements-completed: [PANEL-02, PANEL-04, PANEL-07]
coverage:
  - id: PANEL-02-selection
    description: A completed card selects on pointer activation without a clipboard write; repeated selection remains stable and the selected card shows a check.
    requirement: PANEL-02
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: automated_ui
        ref: test/ui/panel/correction_panel_selection_and_copy_test.dart
        status: pass
    human_judgment: true
    rationale: Existing tests cover keyboard selection and copy separation; the new pointer hit route was inspected in source but not observed on a desktop.
  - id: PANEL-04-layout-key
    description: Physical digit-row positions select the same indexed variants even when logical digit keys differ by layout.
    requirement: PANEL-04
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
    human_judgment: true
    rationale: The physical-key path was inspected against the installed Flutter SDK; no non-QWERTY desktop layout was observed.
  - id: PANEL-07-editor-corner
    description: Settings occupies a gutter or narrow-screen header outside the editor outline.
    requirement: PANEL-07
    verification:
      - kind: automated_ui
        ref: flutter test --exclude-tags=live test/ui/panel/correction_panel_layout_test.dart test/ui/daemon_home_test.dart
        status: pass
    human_judgment: true
    rationale: The geometry and focused widget suites passed; a native pointer hit test on X11 or Wayland was not run.
duration: 13min
completed: 2026-09-24
status: complete
---

# Phase 2 Plan 06: Card selection and editor hit area summary

**Completed suggestion cards now select without copying by pointer or digit-row position, and Settings no longer covers the editor outline.**

## Performance

- **Started:** 2026-09-24T15:03:35Z
- **Completed:** 2026-09-24T15:16:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- The card surface selects its register only after the correction has completed and its text is nonblank. The Copy button remains a separate action. The selected card keeps its highlight and shows a check with named semantics.
- The suggestions focus region accepts the physical top-row positions for `1`/`2`/`3`, alongside existing logical digit and keypad shortcuts. The editor remains outside that shortcut scope, so digits typed there remain text. Both pointer and key routes guard an already-selected register before calling the controller.
- Settings now occupies reserved horizontal space beside the editor at ordinary widths. Below 200 logical pixels it moves to a separate header. The panel's measured height and 2:3 content split remain intact.

## Task Commits

1. **Task 1: Make card selection a deliberate, idempotent action** — `eb5305f` (`feat`).
2. **Task 2: Move Settings affordance out of editor hit bounds** — `059ed8a` (`fix`), followed by `aa2b21e` (`fix`) for the panel-height regression found at the phase gate.

## Decisions Made

- The visible `1`/`2`/`3` hints name the physical top-row key positions. The physical route makes those positions work when a non-QWERTY layout produces a different logical key; existing keypad shortcuts remain.
- The narrow-width branch uses a header because a 48 px side gutter would make the editor's Correct button unreachable on a 120 px surface.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Routed selection through the existing list and corrected an obsolete assertion**
- **Found during:** Task 1.
- **Issue:** `SuggestionList` owns card construction, and its old test asserted that pressing the same digit deselects, contradicting PANEL-02's stable selection.
- **Fix:** Added a selection callback through `SuggestionList` and changed the existing assertion to the new behavior. No new test was created.
- **Files modified:** `lib/src/ui/panel/suggestion_list.dart`, `test/ui/panel/correction_panel_selection_and_copy_test.dart`.
- **Verification:** Analyzer and the existing focused panel tests passed.
- **Committed in:** `eb5305f`.

**2. [Rule 3 - Blocking issue] Moved the actual Settings owner**
- **Found during:** Task 2.
- **Issue:** The Settings `IconButton` is built by `DaemonHome`, outside the plan's named files; changing the editor alone could not relocate its hit box.
- **Fix:** Updated `DaemonHome` and reserved space in `CorrectionPanel`; a narrow panel uses a separate header.
- **Files modified:** `lib/src/ui/daemon_home.dart`, `lib/src/ui/panel/correction_panel.dart`.
- **Verification:** Analyzer and existing panel layout and DaemonHome tests passed.
- **Committed in:** `059ed8a`, `aa2b21e`.

**3. [Rule 1 - Bug] Restored the documented panel-height behavior**
- **Found during:** Phase-gate Flutter suite after Task 2.
- **Issue:** An initial 48 px header reduced the panel viewport at its documented height floor, causing its existing layout test to fail.
- **Fix:** Kept the full-height panel and used a reserved right gutter at ordinary widths; the header remains only for very narrow widths.
- **Files modified:** `lib/src/ui/daemon_home.dart`, `lib/src/ui/panel/correction_panel.dart`.
- **Verification:** Focused panel layout and DaemonHome suites passed, 20 tests total.
- **Committed in:** `aa2b21e`.

## Verification and Limits

- `dart analyze --fatal-infos` passed after each task and after the layout fix.
- The existing panel layout and DaemonHome tests passed after the fix (20 tests). The full Flutter phase-gate suite then had 163 passes, seven skips, and two failures, both in `test/ui/settings/settings_screen_hotkey_test.dart` (A1 AD-10 effective X11 binding; A4 AD-10 requested-versus-effective wording). No 02-06 panel test failed in the final run.
- The existing Dart phase-gate suite failed in `test/application/settings_controller_test.dart` (18 failures in the full run; six on a focused rerun). These Settings paths are outside this plan's changes and are recorded in `deferred-items.md` for the 02-02 owner. The full suite is therefore not claimed as passing.
- Source inspection confirms that pointer selection and physical-key handling call only the controller's selection path, not clipboard write. Physical-key and native pointer behavior were not observed on X11 or Wayland.
- **D-16 limit:** This plan did not observe or change exact current-pointer placement; the startup placement remains best effort and Wayland compositor controlled.
- **D-17 limit:** This plan did not exercise keyring/config API-key behavior; the approved preservation exception remains as recorded in 02-02.

## Known Stubs

None in the changed files. The only “placeholder” occurrence is a comment prohibiting placeholder text.

## Next Phase Readiness

The panel interaction changes are committed. The unrelated Settings suite failures are recorded for their owner; the native pointer and non-QWERTY paths remain observation limits for phase verification.

## Self-Check: PASSED

All five modified source and test files, this summary, and the deferred-items file exist. All three task commits exist, and the measured plan commit count is three.
