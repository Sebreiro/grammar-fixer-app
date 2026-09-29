---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 05
subsystem: ui
tags: [flutter, linux, window-manager, panel]
requires:
  - phase: 01-hotkey-truth
    provides: hidden warm window and existing panel layout
provides:
  - startup geometry with a 640×520 preferred size and a 480×360 preferred minimum
  - display-clamped geometry and a text-scale-aware minimum
  - explicit D-16 placement limit with an I/O-free hotkey path
affects: [02-06, 02-07, PANEL-01]
actuals:
  tokens: 2619
  tasks: 2
  commits: 2
commits: 2
plan_head_before: 6bc711272f5609fcb9c4ee069a47bcabe7ec3917
tech-stack:
  added: []
  patterns: [startup-only window geometry, display-clamped minimum, bounded nested scrolling]
key-files:
  created: []
  modified:
    - lib/main.dart
    - lib/src/ui/panel/correction_panel.dart
    - test/architecture/hidden_window_test.dart
key-decisions:
  - Use the Flutter view's startup display size and text scale to prepare the hidden panel; fall back to preferred geometry when display data is unusable.
  - Center within the startup display's coordinate extent as a best effort; ordinary Wayland toplevel placement and later pointer movement remain outside the claim under D-16.
requirements-completed: [PANEL-01]
coverage:
  - id: PANEL-01-geometry
    description: The hidden window receives preferred or display-clamped size, minimum, and position before summons.
    requirement: PANEL-01
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos
        status: pass
      - kind: integration
        ref: dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart
        status: pass
    human_judgment: true
    rationale: Native X11 and Wayland placement was not observed; D-16 permits only best-effort startup placement.
  - id: PANEL-01-readability
    description: The panel retains its 2:3 pane split and whole-panel scrolling below its text-scale floor.
    requirement: PANEL-01
    verification:
      - kind: automated_ui
        ref: test/ui/panel/correction_panel_layout_test.dart
        status: pass
      - kind: integration
        ref: flutter test --exclude-tags=live test/ui test/platform test/composition
        status: pass
    human_judgment: false
duration: 10min
completed: 2026-09-24
status: complete
---

# Phase 2 Plan 05: Warm panel geometry summary

**The daemon now sizes its hidden panel before summons, clamps it to a smaller startup display, and leaves Wayland placement to the compositor.**

## Performance

- **Started:** 2026-09-24T14:35:09Z
- **Completed:** 2026-09-24T14:44:30Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Startup sets a 640×520 preferred window size, a 480×360 preferred minimum, and a best-effort centered position. The minimum grows with the panel's text-scale floor. Both sizes clamp to the startup display; unavailable geometry uses the preferred values and an origin position.
- The hotkey path remains the existing visibility toggle. Size, minimum, and position are applied to the hidden window before `runApp` and before summons.
- The panel's existing independent editor and suggestion scrolling, 2:3 vertical split, and whole-panel scroll below the readability floor were retained. Its layout contract now describes the startup minimum and small-display behavior accurately.

## Task Commits

1. **Task 1: Set warm-window size, minimum and best-effort position** — `a886210` (`feat`)
2. **Task 2: Keep both text regions readable when a display shrinks** — `a00e1e4` (`refactor`)

## Decisions Made

- Use the Flutter view's startup display dimensions in logical pixels. The view reports a size and device pixel ratio but no global display origin or current pointer display.
- Set a text-scale-aware minimum at least 60 logical pixels taller than `CorrectionPanel.minimumPanelHeightFor`, leaving room around the panel's content. A smaller display takes precedence over that preference and activates whole-panel scrolling.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Updated the existing hidden-window allowlist**
- **Found during:** Task 1
- **Issue:** The existing architecture suite rejected the new `setMinimumSize`, `setSize`, and `setPosition` calls because its startup allowlist still named only the older calls.
- **Fix:** Expanded that existing allowlist, documented the pinned Linux plugin's GTK calls, and extended its existing presence assertion. No new test, gate, CI, or runtime-observation work was added.
- **Files modified:** `test/architecture/hidden_window_test.dart`
- **Verification:** Analyzer and both existing suites passed.
- **Commit:** `a886210`

**Total deviations:** 1 auto-fixed (Rule 3). **Impact:** The existing architecture guard now recognizes the planned non-mapping geometry setters.

## Issues Encountered

None beyond the allowlist adjustment above.

## Verification and Limits

- `dart analyze --fatal-infos`: passed.
- Existing Dart suite: passed (982 tests, two existing skips).
- Existing Flutter suite: passed (165 tests, seven existing skips). The focused panel layout file also passed.
- Source inspection confirms all three geometry calls occur while the window is hidden. The existing panel layout test covers a 480×360 surface, a below-floor surface, narrow widths, scaled text, and reachable correction/error content.
- **D-16 limit:** Exact centering on the display currently containing the pointer is unproven and not guaranteed. The geometry is a startup snapshot; moving the pointer later does not reposition the window. An ordinary Wayland toplevel is placed by its compositor. No live X11 or Wayland placement was observed here.
- **D-17 limit:** API-key preservation is outside this plan and was not exercised.

## Known Stubs

None in the changed files. The word “placeholder” in the panel source prohibits placeholder text; it does not render one.

## Next Phase Readiness

The warm panel geometry and D-16 boundary are available for later panel work. Native placement remains an explicit verification limit.

## Self-Check: PASSED

All three modified files and both task commits exist.
