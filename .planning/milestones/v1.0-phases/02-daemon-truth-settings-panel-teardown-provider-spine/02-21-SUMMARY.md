---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 21
subsystem: architecture-documentation
tags: [bmad-architecture, hotkey, panel, provider, architecture-spine]
requires:
  - phase: 02-daemon-truth-settings-panel-teardown-provider-spine
    provides: Regenerated CAP-2 product SPEC and D-19 owner-ratified AD-9 input from plans 02-19 and 02-20
provides:
  - Source-grounded 19-AD architecture spine and append-only BMAD memlog
  - Reconciled runtime dependency, Stack, structural file map, panel session, and provider rules
  - Three independent reviewer reports and explicit unresolved protocol limits
affects: [02-22, 02-23, 02-24, 02-25, 02-26, ARCH-03, ARCH-04, ARCH-05, ARCH-06, ARCH-08, PANEL-17, PROVIDER-03]
actuals:
  tokens: 29584
  tasks: 2
  commits: 2
commits: 2
plan_head_before: a4718c0914fe809b2f38547a798ea38f1190ef68
tech-stack:
  added: []
  patterns: [Codex runs local BMAD UPDATE instructions, append decisions through memlog.py, re-derive stable AD identifiers, retain independent reviewer evidence]
key-files:
  created:
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-currency-2026-09-26.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-adversarial-2026-09-26.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-rubric-2026-09-26.md
  modified:
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/.memlog.md
    - _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md
    - lib/src/infrastructure/config/default_app_config.dart
    - lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart
    - lib/src/domain/panel/panel_visibility.dart
    - pubspec.yaml
key-decisions:
  - D-19's owner-ratified non-const HotkeyBinding defensive copy replaces the stale AD-9 declaration while retaining the earlier unattended selection as separate provenance.
  - Unknown provider IDs warn at startup and resolve an unconfigured provider, never a startup failure or fallback.
  - Wayland's localized trigger description is displayed as desktop text; no machine-readable effective combination is invented.
  - A selectable production provider must stream meaningful partials; AD-16's shipped grammar requires the END sentinel.
requirements-completed: [ARCH-03, ARCH-04, ARCH-05, ARCH-06, ARCH-08, PANEL-17, PROVIDER-03]
duration: 26min
completed: 2026-09-26
status: complete
---

# Phase 02 Plan 21: Architecture Spine Currency Summary

**Codex re-derived the 19-AD spine from shipped code and owner decisions, correcting the hotkey, panel, provider, Stack, runtime dependency, and file-map contracts.**

## Performance

- **Started:** approximately 2026-09-26 08:23 UTC
- **Completed:** 2026-09-26 08:48 UTC
- **Duration:** approximately 26 minutes
- **Tasks:** 2
- **Files created or modified:** 9

## Accomplishments

- Ran the local `bmad-architecture` UPDATE workflow with Codex. Decisions, evidence, review dispositions, and finalization were appended through `_bmad/scripts/memlog.py`; the spine was re-derived with stable AD-1 through AD-19 identifiers. No Claude CLI or external generator was invoked, and the product SPEC was not edited.
- Reconciled AD-2/9 collection equality and D-19 constructor; cached hotkey status, unavailable causes, event precedence, Wayland descriptions, and conditional portal registration; AD-8/18 dismissal versus iconify/focus-return sessions; AD-15's real Settings exception and unknown-provider result; AD-16's four-line sentinel and streaming requirement.
- Reconciled the pinned Dart constraint, removed plugin/EOL claims, X11 FFI, silent tray-host absence, and all 97 tracked `lib/` files in the Structural Seed. Corrected the two planned obsolete source comments plus two owner-approved comment-only drift locations.
- Ran the BMAD reviewer gate with independent currency, adversarial-seams, and rubric reviewers. Applied confirmed factual corrections and retained their dated reports. Possible Wayland signal/cache races and a source-level late-clipboard-seed defect are recorded without claiming live reproduction.

## Task Commits

1. **Task 1: Regenerate the 19-AD spine from implemented evidence** — `e163b1c` (`docs`).
2. **Task 2: Correct obsolete source comment citations** — `6bab0ec` (`docs`).

## Verification

- `git diff HEAD --check` passed before task commits; staged task 2 diff was comments only.
- `dart analyze --fatal-infos` passed with no issues.
- Existing `dart test --exclude-tags=live test/architecture` passed: 228 tests passed, 1 environment-dependent runtime observation skipped. No test, CI, gate, or live runtime observation was added.
- `lint_spine.py` found only the pre-existing low false positive `{sv}` inside the D-Bus signature `a{sv}`. The 19 AD identifiers remain present and ordered; the Structural Seed matches all 97 tracked `lib/` files with no omissions or extras.
- Currency, adversarial, and rubric reviewer reports were inspected and their clear source mismatches were fixed. Their remaining protocol counterexamples are disclosed under Deferred in the spine.

## Deviations from Plan

- **Rule 1, source-comment drift:** The regenerated AD-8 and Stack made existing comments in `lib/src/domain/panel/panel_visibility.dart` and `pubspec.yaml` false. The phase owner expanded 02-21 ownership to those two comment-only files. Both were corrected in `6bab0ec`; no behavior or dependency changed.
- **Reviewer-driven architecture corrections:** The shipped parser's required `END` line, suppressed sidecar stderr content, actual unavailable-view line count, CAP-5 partial-stream obligation, and incomplete infrastructure import gate were discovered while reviewing the generated spine. They were corrected in `e163b1c`; no new architecture ID or runtime behavior was introduced.

## Residual Findings

- **Wayland CAP-12:** The portal supplies localized `trigger_description`, not a structured effective binding. A compositor change between bind read-back and signal subscription could be missed; an outcome-only change event and separately cached description permit an event/cache interleaving. These are source/protocol counterexamples, not observed compositor failures. Literal display of the actual key combination remains unproven.
- **Clipboard CAP-3:** A pending seed read can overwrite a user's typed-then-cleared blank editor because the controller checks the current empty value, not whether the session was edited. The exact source interleaving was sent to the phase owner for a separate follow-up fix; 02-21 changed no runtime code.
- **D-16/D-17:** Exact pointer-display centering and the strict daemon-never-rewrites-a-user-authored-key wording remain owner-waived limits. This documentation update does not verify native placement, keyring access, or live provider endpoints.
- **AD-1:** The import gate covers domain, application, and UI, but not infrastructure's outward-import ban. Mechanical enforcement is deferred by the locked Phase 2 no-new-gate rule.

## Known Stubs

None in the files changed by this plan.

## Threat Flags

None. This plan changed documentation and comments only; no network endpoint, credential handling, file-access behavior, or schema changed.

## Next Phase Readiness

The generated architecture is available to plans 02-22 through 02-26. Later verification must keep the residual limits explicit and must not treat source inspection as live host observation.

## Self-Check: PASSED

The summary file exists; both task commits are present; `plan_head_before..HEAD` measured two task commits; analyzer, diff check, architecture tests, and the BMAD lint inspection completed with only the documented low D-Bus false positive.

## Post-plan CAP-3 follow-up (2026-09-26)

The source race reported above was fixed separately in `9880b9e`. The
controller now records an editor revision when the user edits and lets a
pending clipboard seed land only if that revision is unchanged. The existing
CAP-3 late-read test was strengthened to reproduce typed-then-cleared input;
it failed before the fix and passed after it. `dart analyze --fatal-infos`,
the 192-test application suite, and `git diff --check` passed. This is a
source-level fix with deterministic fake timing, not a native clipboard
runtime observation. The original reviewer finding is preserved above as
the reason for the follow-up.

## Post-plan AD-12 source-currency update (2026-09-26)

Commit `68eb358` appends the decision through BMAD `memlog.py` and re-derives
only AD-12's inaccurate "session identifies no display server" example. The
shipped selector chooses X11 when neither a recognized `XDG_SESSION_TYPE` nor a
nonempty `WAYLAND_DISPLAY` is present. If `XOpenDisplay` then fails, the
subsequent bind returns `HotkeyUnavailableCause.noBackend` as a value. All 19 AD
IDs and AD-12's refusal invariant remain intact; no source behavior changed.

The focused currency, adversarial-seams, and rubric reviewers each returned
PASS against `display_server.dart`, `x11_key_grab_registrar.dart`, and
`x11_global_hotkey.dart`. The reviewer precision was to name the **subsequent
bind** as the point that returns `noBackend`, not startup selection. Existing
display-server and X11 registrar tests passed 10/10; `git diff --check` passed.
BMAD lint retained only the known low false positive on D-Bus `a{sv}`. No live
display-server observation or new test/gate was added. Dart analysis was not
rerun because this update changed documentation only.

## Post-plan AD-12 surface-presentation update (2026-09-26)

Commit `606ba50` appends a source-grounded decision and reviewer disposition
through BMAD `memlog.py`, then re-derives only AD-12's presentation Rule. The
startup tray receives a neutral unavailable boolean; later typed
`HotkeyTrayStatus` updates can render cause-specific menu lines. Settings
renders a cause line, the adapter message verbatim or a fallback for blank
messages, then the cause's current-status line. The Rule preserves the ban on
inferring a display server or claiming active shortcut ownership from an
unavailable result. All 19 AD identifiers remain stable; no source, runtime,
test, or review-report file changed in this update.

The focused BMAD currency and good-spine rubric reviewers returned PASS. The
adversarial reviewer confirmed the edited Rule's rendering facts and flagged
one separate source-copy overclaim: X11 `XOpenDisplay` failure can yield
`noBackend`, but current Settings and tray strings say desktop shortcut
support or service is absent. Failed display access does not prove either
absence. The phase owner was notified and owns any source-copy correction.
`git diff --check` passed, and BMAD lint retained only its known low false
positive on the D-Bus `a{sv}` signature. Dart analysis and live desktop
observation were not repeated for this documentation-only follow-up.

## Post-plan Flutter Stack-row repair (2026-09-26)

Commit `72633f7` appends a decision and reviewer disposition through BMAD
`memlog.py` and restores the generated Stack row's exact `Flutter (stable)`
name. Its Version cell still cites `.github/workflows/ci.yml` without copying
the numerical pin. The existing `sidecar_pin_drift_test.dart` uses that row
name to locate and verify the citation; all 44 focused tests now pass. All 19
AD IDs and every other Stack row remain intact. No source or test was edited.

The focused adversarial and good-spine rubric reviewers returned PASS. The
currency reviewer noted that CI omits an explicit `channel: stable`; the
[action's v2 definition](https://github.com/subosito/flutter-action/blob/v2/action.yaml)
specifies `stable` as the default for that optional input, resolving the
configuration question. This verifies the current action configuration, not
an executed CI run; `@v2` is a movable ref. `git diff --check` passed. BMAD
lint retained only the known low false positive for D-Bus `a{sv}`. Dart
analysis was not rerun for this documentation-only correction.
