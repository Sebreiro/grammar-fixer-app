---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 23
subsystem: architecture-documentation
tags: [architecture-reviews, dispositions, source-inspection]
requires:
  - phase: 02-daemon-truth-settings-panel-teardown-provider-spine
    provides: Regenerated 19-AD architecture spine from plan 02-21 and six review dispositions from plan 02-22
provides:
  - Dated dispositions in the five remaining frozen currency and rubric reviews
  - Explicit current AD-12 presentation mismatch and unobserved tray-host limitation
affects: [02-24, 02-25, 02-26, ARCH-07]
actuals:
  tokens: 2983
  tasks: 2
  commits: 2
commits: 2
plan_head_before: 0b785993d464eb56523f83d51fd323bc092226bb
tech-stack:
  added: []
  patterns: [dated append-only dispositions outside frozen historical review bodies]
key-files:
  created: []
  modified:
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-currency-check-2026-08-14.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-currency-check.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-rubric-walker-2026-08-14-ad12-premise.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-rubric-walker-2026-08-14-amendments.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-rubric-walker-2026-08-14.md
key-decisions:
  - Historical verdicts remain intact; current source and regenerated AD evidence determines each appended disposition.
  - AD-12 presentation wording remains open where it describes a two-line Settings view and boolean-only tray, while current source renders a three-line view and typed cause-specific tray status.
requirements-completed: [ARCH-07]
duration: 18min
completed: 2026-09-26
status: complete
---

# Phase 02 Plan 23: Remaining Architecture Review Dispositions Summary

**Five frozen currency and rubric reports now identify how their findings stand against the regenerated spine and shipped source, completing dispositions for all eleven tracked reports.**

## Performance

- **Completed:** 2026-09-26 09:27 UTC
- **Duration:** approximately 18 minutes
- **Tasks:** 2
- **Files modified:** 5 review reports

## Accomplishments

- Appended dated, finding-by-finding dispositions to both currency reports and all three rubric reports, preserving every original verdict and body.
- Separated resolved historical issues from the current AD-12 presentation wording gap and the source-inspected, unobserved StatusNotifier host limit.
- Confirmed `## Disposition — 2026-09-26` appears in all eleven tracked reports across plans 02-22 and 02-23. ARCH-07's report-disposition scope is complete.

## Task Commits

1. **Task 1: Append evidence-backed dispositions to first reports** — `d98bf74` (`docs`).
2. **Task 2: Append evidence-backed dispositions to remaining reports** — `af5858f` (`docs`).

## Verification

- `git diff --check` and `git diff --cached --check` passed before task commits.
- Both task commits add lines only to their owned reports; no historical review text was removed, and no source, test, gate, CI, or generated spine file was edited.
- Compared the dispositions with the regenerated AD-1 through AD-19 spine and relevant checked-in source. This was source inspection, not an upstream freshness query or native compositor/tray-host observation.

## Open Findings for Follow-up

- **AD-12 surface Rule:** `ARCHITECTURE-SPINE.md:350` says the tray has only neutral boolean unavailability and the Settings view renders the backend message followed by one ownership line. Current `lib/src/domain/tray/tray_port.dart:23-33` offers a startup boolean plus typed `setHotkeyStatus`; `lib/src/infrastructure/tray/tray_manager_tray.dart:134-181` renders cause-specific menu lines. `lib/src/ui/settings/hotkey_status_view.dart:164-182` renders a cause line, message or blank-message fallback, and status line. A generated AD-12 wording correction is needed; the historical reports disclose the mismatch without changing the spine.
- **TrayPort comment:** `lib/src/domain/tray/tray_port.dart:23-26` still calls every unavailable state “on this compositor,” although per-key refusal is possible. Correct that documentation with the AD-12 follow-up.
- **Tray host:** the regenerated spine's Operational envelope records `tray_manager`'s silent success when no StatusNotifier host displays the indicator. No native host-less behavior was observed here, so the fallback remains an operational limit.
- **Infrastructure import gate:** AD-1 and Deferred explicitly record that the current architecture test does not scan infrastructure imports. Plan 02-23 did not add a gate under the locked phase scope.

Suggested AD-12 Rule wording for the follow-up: “At startup the tray receives a boolean unavailable state; later typed `HotkeyTrayStatus` updates may render cause-specific menu lines. Settings renders a cause-specific line, then the adapter message verbatim (or the tray fallback when blank), then a current-status line. Neither surface infers a display server or claims an active ownership regime for `HotkeyUnavailable`.”

## Deviations from Plan

None. The five specified reports alone were edited and their original bodies and filenames were preserved.

## Known Stubs

None introduced. The open wording and host limitations above are existing conditions disclosed by the appendices.

## Threat Flags

None. These append-only documentation changes introduce no executable or trust-boundary surface.

## Next Phase Readiness

ARCH-07's eleven review dispositions are complete. A narrow generated AD-12 wording correction and `TrayPort` comment correction remain for the phase owner before milestone closure; neither requires a new review pass or native observation for this plan's scope.

## Self-Check: PASSED

The summary exists, both task commits exist, the persisted `plan_head_before..HEAD` range contains two commits, all eleven tracked reports have a dated disposition, and `git diff --check` passed. No tracked file was deleted.

## Post-plan closure — 2026-09-26

The “Open Findings for Follow-up” section above is the accurate snapshot at plan 02-23's metadata commit. Its AD-12 presentation and `TrayPort` wording findings were closed afterward: Codex ran the local BMAD generator to update AD-12's Rule in `606ba50` and recorded the generator follow-up in `7646898`; `89b4487` corrected the startup boolean port comment; `21c26bd` changed `noBackend` Settings/tray copy and its existing widget assertions so an inaccessible backend is not misdescribed as a desktop with no shortcut capability. Dated closure notes were appended to the three relevant rubric reports. The phase owner reports the focused 49 widget tests passed and `dart analyze --fatal-infos` was clean for the source copy change; this summary did not rerun a test or make a native observation.

The missing StatusNotifier host can still silently remove the tray fallback, and AD-1's infrastructure-import gate remains deferred. Their open status is unchanged by these wording corrections. The two measured task commits and `actuals` above remain the original plan's numbers; this appendix is a post-plan follow-up.
