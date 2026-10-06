---
phase: 261002-ka3
reviewed: 2026-10-02T22:23:06Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - prototype/ui-baseline/index.html
  - prototype/ui-baseline/styles.css
  - prototype/ui-baseline/fixtures.js
  - prototype/ui-baseline/state.js
  - prototype/ui-baseline/app.js
  - prototype/ui-baseline/README.md
  - docs/UI_UX_REFERENCE.md
  - README.md
findings:
  critical: 2
  warning: 3
  info: 0
  total: 5
status: resolved
resolved_commit: 8b803f2
unresolved_findings: 0
---

# Quick Task 261002-ka3: Code Review Report

**Reviewed:** 2026-10-02T22:23:06Z
**Depth:** standard (focused, time-bounded source review)
**Files Reviewed:** 8
**Status:** resolved in `8b803f2`; original findings retained below for traceability

## Summary

Reviewed the exact prototype/documentation scope against the current Flutter widgets and the task's locked decision to mirror the current UI. Findings concern invented recovery UI, reset consistency, baseline fidelity, accessible failure feedback, and incorrect capability attribution. No source was changed and no commit was made. Existing browser smoke results and analyzer success do not check the source discrepancies below. Browser approximations and simulated backend/desktop effects are intentional and are not defects.

## Resolution evidence

All five findings were fixed in `8b803f2`. Settings replay is labeled as a sample action outside the app; production recovery is documented as repeating the original control. Custom-provider visibility follows the reset config. Correct is right-aligned, Keep current matches the source, and its explanation is present. Persistent polite failure live regions are updated only when their text changes. CAP-9 now refers to correction quality.

The final all-group browser check passed after fixes and refreshed the screenshots. [Focused regression evidence](evidence/review-fixes-results.json) records six passing checks, including original-control recovery and provider reset. Live-region assertions establish DOM/text behavior, not an observed screen-reader announcement.

## Original Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: BLOCKER — Settings recovery introduces a production-looking control absent from the source

**File:** `/workspace/prototype/ui-baseline/index.html:38`
**Related:** `/workspace/prototype/ui-baseline/app.js:354-356`, `/workspace/docs/UI_UX_REFERENCE.md:39`, `/workspace/prototype/ui-baseline/README.md:17`
**Issue:** The app frame renders a Settings **Retry** button and replays a cached failed mutation. The Flutter `SettingsFailureNotice` renders only the failure text (`lib/src/ui/settings/settings_failure_notice.dart:43-48`), and `settings_screen.dart:290` supplies no retry callback. Its recovery uses the original setting control. The reference and walkthrough describe the invented button as current production behavior. This violates the explicit requirement to preserve existing controls and keep scenario controls outside the app, and makes the baseline unsafe to use as a later redesign inventory.
**Fix:** Remove Settings Retry from the simulated app and its handler; demonstrate recovery by repeating the original setting action. If replaying a cached failure remains useful to reviewers, place it in Sample scenarios and label it as a fixture action. Correct the reference and walkthrough. Keep the correction panel's real Retry unchanged.

### CR-02: BLOCKER — Reset leaves a provider choice whose configuration was removed

**File:** `/workspace/prototype/ui-baseline/app.js:302-308`
**Related:** `/workspace/prototype/ui-baseline/app.js:264-269,364-368`, `/workspace/prototype/ui-baseline/index.html:58`
**Issue:** Reproduction: click **Custom provider / log size**, then **Reset sample**, open Settings, and select **sample-local**. Reset replaces config with `initialConfig()`, removing the custom preset, but never hides `custom-provider`, which the custom fixture previously exposed. `providerChanged()` therefore treats the visible provider as an unconfigured setup draft. The compatible setup fields are hidden because the selected provider is not `openai-compatible`, and there is no save path for this phantom provider. Reset consequently leaves an unreachable activation flow rather than a consistent sample state.
**Fix:** Derive custom provider visibility from committed config in `renderSettings()` (and reset transient setup/draft state), or explicitly restore the custom choice to hidden during reset. Verify custom fixture → reset → Settings exposes only providers present in the initial fixture plus the supported compatible setup choice.

## Warnings

### WR-01: WARNING — Important baseline control placement and wording diverge from the widgets

**File:** `/workspace/prototype/ui-baseline/styles.css:31`
**Related:** `/workspace/prototype/ui-baseline/index.html:51`, `/workspace/docs/UI_UX_REFERENCE.md:31`
**Issue:** `align-items: start` puts **Correct** at the editor's left edge, while `OriginalTextPane` explicitly uses `Alignment.centerRight` (`lib/src/ui/panel/original_text_pane.dart:112-113`). The hotkey button is also labeled **Keep current shortcut**, while the rendered source label is **Keep current** (`lib/src/ui/settings/hotkey_capture_field.dart:435`). These are objective placement/label discrepancies under the user's mirror-current-UI decision, rather than requests for exact Flutter pixels or a different design.
**Fix:** Add `#correct { align-self: flex-end; }` and use **Keep current** in the sample and reference. Preserve the source's explanation that the registered X11 shortcut cannot be entered into the capture field; the sample currently replaces it with a short current-binding hint.

### WR-02: WARNING — Failure notices lose the source's accessible announcements

**File:** `/workspace/prototype/ui-baseline/index.html:30,38`
**Related:** `/workspace/prototype/ui-baseline/app.js:44-46,180-181`
**Issue:** Both failure containers and their message nodes lack `role="alert"`, `role="status"`, or an ARIA live region. A correction failure clears the sole correction status message instead of announcing the error, and a settings failure simply unhides plain text. Users reviewing with a screen reader receive no reliable failure announcement while focus remains elsewhere. The Flutter Settings failure is explicitly a `Semantics(liveRegion: true, container: true)` notice (`settings_failure_notice.dart:24-25,42`), and the reference promises terminal-status announcements (`docs/UI_UX_REFERENCE.md:48`).
**Fix:** Provide persistent named live-region nodes for terminal correction/settings failures and update their text when failures occur. Keep token-by-token partial text outside live regions. Verify failure messages are announced without moving focus or announcing every streaming update.

### WR-03: WARNING — CAP-9 is attributed to autostart/residency instead of correction quality

**File:** `/workspace/docs/UI_UX_REFERENCE.md:83`
**Issue:** The sample-limit paragraph calls autostart/residency **CAP-9**. Canonical `SPEC.md:52-54` defines CAP-9 as producing fluent native-sounding English while preserving meaning. Residency/pre-created windows belong to the constraints, and the summon budget is CAP-1. This source-linked reference misidentifies a requirement and can misdirect later validation.
**Fix:** Replace the phrase with unnumbered "autostart/residency" and separately identify "CAP-9 correction quality" as outside this sample's validation, consistent with the fixture-quality limitation already stated at line 81. Do not edit the canonical SPEC.

---

_Reviewed: 2026-10-02T22:23:06Z_
_Reviewer: gsd-code-reviewer_
_Depth: standard_
