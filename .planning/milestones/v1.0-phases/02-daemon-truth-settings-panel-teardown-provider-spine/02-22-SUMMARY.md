---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 22
subsystem: architecture-documentation
tags: [architecture-reviews, dispositions, source-inspection]
requires:
  - phase: 02-daemon-truth-settings-panel-teardown-provider-spine
    provides: Regenerated 19-AD architecture spine from plan 02-21
provides:
  - Dated finding-by-finding dispositions in six historical architecture reviews
  - Explicit open wording and protocol findings with current source anchors
affects: [02-23, 02-24, 02-25, 02-26, ARCH-07]
actuals:
  tokens: 4610
  tasks: 2
  commits: 2
commits: 2
plan_head_before: 0feecf9ca1058d3a2eaec393d6b3ef0a723bbea5
tech-stack:
  added: []
  patterns: [dated append-only dispositions outside frozen historical review bodies]
key-files:
  created: []
  modified:
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-adversarial-seams-2026-08-14-ad12-premise.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-adversarial-seams-2026-08-14-amendments.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-adversarial-seams-2026-08-14.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-adversarial-seams.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-currency-check-2026-08-14-ad12-premise.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-currency-check-2026-08-14-amendments.md
key-decisions:
  - Historical verdicts remain intact; current dispositions distinguish source inspection from unobserved native behavior and upstream freshness.
  - The revoked-shortcut ownership copy and AD-12 no-display-server example remain open at this commit point.
requirements-completed: [ARCH-07]
duration: 10min
completed: 2026-09-26
status: complete
---

# Phase 02 Plan 22: Historical Architecture Review Dispositions Summary

**Six frozen adversarial and currency reports now identify which findings current code resolves and which still need narrow follow-up, without replacing their 2026-08-14 verdicts.**

## Performance

- **Started:** approximately 2026-09-26 08:55 UTC
- **Completed:** 2026-09-26 09:05 UTC
- **Duration:** approximately 10 minutes
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Appended a dated disposition after the unchanged historical body of each of the six owned reports. Every material finding is classified as accepted, superseded, or still open with an AD/source reason.
- Marked source-only closures as such, including AD-9's cached hotkey status, AD-12's cause and value selection, tray fan-out, AD-15's provider resolution, the removed keybinder loader path, and the corrected Stack/Structural Seed.
- Preserved the distinction between dated historical dependency measurements and current checked-in manifests; no upstream release query, native host observation, new review pass, test, gate, or CI change was performed.

## Task Commits

1. **Task 1: Append evidence-backed dispositions to first reports** — `8a81cff` (`docs`).
2. **Task 2: Append evidence-backed dispositions to remaining reports** — `35b35c0` (`docs`).

## Verification

- `git diff HEAD --check` passed before each task commit; all six reports contain a `## Disposition — 2026-09-26` section.
- Diff inspection showed append-only changes to the six reports, preserving the original text and verdicts.
- Compared disposition claims with the regenerated AD-1 through AD-19 spine and relevant current source. No runtime or upstream freshness claim was inferred from this inspection.

## Open Findings at This Commit Point

- **Revoked-shortcut ownership copy:** `lib/src/ui/settings/hotkey_status_view.dart:202` says the desktop took the shortcut away, but its common closing line at `:170` says the owner is unknown until a shortcut is registered. AD-12 at `ARCHITECTURE-SPINE.md:350` intends no **active** regime. The narrow source fix is to give `revoked` a closing line saying no shortcut is currently in effect, without erasing that the former owner was the desktop. This is marked open in S-2's disposition; no native session was run.
- **Phantom no-display-server refusal:** `ARCHITECTURE-SPINE.md:348` lists a session identifying no display server as a peer refusal, while `DisplayServer.fromEnvironment` chooses X11 as a total fallback at `lib/src/infrastructure/hotkey/display_server.dart:27-44`. The narrow generated-spine fix is to remove that peer example or describe a refusal from the selected fallback adapter. This is marked open in A-4 and currency F3.
- **Stale outcome comment:** `lib/src/domain/hotkey/hotkey_bind_outcome.dart:83` still says every `HotkeyUnavailable` means no backend could bind, although the enum also covers `keyRefused` and `revoked`. Narrow comment fix: “No binding is held.” This remains open in A-2/H2 dispositions.
- Other low-level report residuals include app-bind echo semantics for `bindingChanges`, stream completion/subscription wording, the sealed-family file convention, the default-model Stack label, the message-contract enforcement gap, and the Python floor error string. These are disclosed in the individual dispositions; none is claimed newly observed.

## Deviations from Plan

None. The six specified reports alone were edited, and each original review body and filename was retained.

## Known Stubs

None introduced. The appendices describe existing open wording and enforcement gaps; they do not add a placeholder implementation.

## Threat Flags

None. This was an append-only documentation change with no new trust boundary or executable surface.

## Next Phase Readiness

ARCH-07's six owned review dispositions are complete. Plan 02-23 can disposition the remaining five reports. The open findings above were sent to the phase owner for a separate, narrow follow-up before milestone closure.

`ARCH-07` remains pending in `REQUIREMENTS.md` until plan 02-23 dispositions complete the full eleven-report set; this summary records plan 02-22's share of that requirement.

## Self-Check: PASSED

The summary file exists; both task commits exist; the persisted `plan_head_before..HEAD` range contains two commits; all six report appendices are present and `git diff --check` passed. Historical report bodies were preserved.

## Post-plan closure — 2026-09-26

The three wording findings in “Open Findings at This Commit Point” were closed after plan 02-22's metadata commit; that section remains the accurate snapshot of its commit point. Commit `9514e54` gives revoked shortcuts a current-status closing line in `HotkeyStatusView` and corrects the `HotkeyUnavailable` class comment. Commit `68eb358` regenerates AD-12 through the local BMAD memlog/spine workflow so the no-session-hints case selects X11 and only a failed fallback bind reports `noBackend`. Corresponding dated closure notes were appended to the S-2, A-2/H2, A-4, and currency F3 review reports.

The owner reports the existing settings widget suite passed 20/20 with clean analyzer for `9514e54`; the focused fallback tests passed 10/10 and three reviewers passed for `68eb358`. These are source, test, and document checks. No native compositor or tray-host observation is claimed, and the other residuals listed above are unaffected.
