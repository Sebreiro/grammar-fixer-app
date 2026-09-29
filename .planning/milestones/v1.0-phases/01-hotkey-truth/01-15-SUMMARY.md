---
phase: 01-hotkey-truth
plan: 15
subsystem: testing
tags: [x11, hotkey, dart-test, fail-first, oracle, workerGone, CR-02]

# Dependency graph
requires:
  - phase: 01-hotkey-truth
    provides: "HotkeyRegistrarRefusal / HotkeyRefusalCode crossing the registrar seam (plan 01-04), the acquire-before-release rebind ordering (plan 01-03), and FakeHotkeyRegistrar.grabError"
provides:
  - "A fail-first oracle for G-01-15 / CR-02: a `workerGone` refusal during an X11 rebind must clear the previous combination, not report it as in effect"
  - "A recorded RED run of that oracle against the unfixed adapter, with the verbatim Expected/Actual and the commit sha it was produced at"
  - "`HotkeyRefusalCode.workerGone` named under `test/` for the first time (0 matches at HEAD 8dab2e7)"
  - "Three green contrast rows — keyRefused, badRequest, and a non-refusal rejection — that bound the fix so it cannot be over-applied"
affects: [01-16, 01-17, hotkey, x11, settings]

# Actuals (#2632)
actuals:
  tokens: 2735
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fail-first oracle: the expectation is authored and its failure recorded at a commit that predates the fix, so `git log` can later prove it was not retrofitted"
    - "Control-set matrix: the three inputs on which the answer must NOT change are baselined green at the same commit, so the fix's run is a comparison rather than an assertion"

key-files:
  created: []
  modified:
    - test/infrastructure/hotkey/x11_global_hotkey_test.dart

key-decisions:
  - "The log assertion is written as an equality against the adapter's existing refusal-answered-as-a-refusal message (`'the X11 key grab was refused'`) rather than as the absence of the abandoned-rebind sentence — stating the positive, so the row cannot pass against an adapter that emits neither."
  - "The `workerGone` message is the registrar's own production sentence verbatim (`x11_key_grab_registrar.dart:281-284`), so the row also pins that the seam's authored diagnosis is carried through rather than replaced."
  - "The third contrast row (a bare `StateError`) overlaps the existing `:243` row on its claim and was written anyway, with an in-code comment saying it is the matrix's null case, so a later editor deleting it as a duplicate knows what the deletion costs."

patterns-established:
  - "Fail-first evidence: quote the verbatim `Expected:`/`Actual:`/row-name in the SUMMARY together with the sha, so a later reader re-runs it rather than taking the claim on trust (T-01-73)."

requirements-completed: [HOTKEY-01, HOTKEY-08]
# Declared because the plan's frontmatter declares them. NOT closed by this plan:
# the oracle exists and is red; 01-16 lands the fix. 01-16 and 01-17 also declare
# both IDs, so the shared-ID gate holds them until the last declaring plan finishes.

coverage:
  - id: D1
    description: "A test row that drives the registrar seam into a `workerGone` refusal mid-rebind and asserts `HotkeyUnavailable(noBackend)` on both the returned outcome and `GlobalHotkey.current` — recorded FAILING against the unfixed adapter"
    requirement: "HOTKEY-01"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears the previous combination instead of reporting it as in effect"
        status: fail
    human_judgment: true
    rationale: "The deliverable IS a recorded failure. No classifier can read a `fail` status as a shipped deliverable; a human must confirm that the red is the intended red — Expected `HotkeyUnavailable`, Actual `HotkeyBound` — and not a row broken for some other reason. It turns green in 01-16, and that is where it becomes a pass."
  - id: D2
    description: "Three contrast rows pinning the refusals that must KEEP abandoning the rebind — `keyRefused`, `badRequest`, and a rejection that is not a `HotkeyRegistrarRefusal` at all — each green against the unfixed adapter"
    requirement: "HOTKEY-08"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#D-10, AD-10, CR-02: keyRefused leaves the previous combination in effect, because a backend that answered has released nothing"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#D-10, AD-10, CR-02: badRequest leaves the previous combination in effect — a protocol defect is not an absent backend"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#D-10, AD-10, CR-02: a rejection that is not a refusal leaves the previous combination in effect"
        status: pass
    human_judgment: false
  - id: D3
    description: "`HotkeyRefusalCode.workerGone` is named under `test/` for the first time, closing the zero-coverage finding that let the defect through a phase, a verification and a code review"
    verification:
      - kind: other
        ref: "grep -rn 'workerGone' test/ | wc -l  →  8  (0 at HEAD 8dab2e7)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Nothing under `lib/` changed, and the project's two non-globbing gates are unmoved: `dart analyze --fatal-infos` clean, `flutter test test/ui test/platform test/composition` 165 passed / 7 skipped"
    verification:
      - kind: other
        ref: "git diff --numstat -- lib/  →  empty"
        status: pass
      - kind: other
        ref: "dart analyze --fatal-infos  →  'No issues found!'"
        status: pass
      - kind: integration
        ref: "flutter test --exclude-tags=live test/ui test/platform test/composition  →  +165 ~7"
        status: pass
    human_judgment: false

# Metrics
duration: 16 min
completed: 2026-09-11
status: complete
---

# Phase 01 Plan 15: The workerGone Rebind Oracle, Written Red Summary

**A fail-first test row that catches `workerGone`-during-rebind being reported as `HotkeyBound(previous)`, recorded failing at `fd3cba7` against the unfixed adapter, plus three green contrast rows that stop the fix from being over-applied.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-09-11T12:31:00Z
- **Completed:** 2026-09-11T12:47:29Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Built the oracle for G-01-15 / 01-REVIEW.md CR-02 **before** the fix, and recorded a run in which it fails. `HotkeyRefusalCode.workerGone` was named in **zero** places under `test/` at HEAD `8dab2e7`; that absence is exactly why the adapter could compute `_refusalOf(error)` at `x11_global_hotkey.dart:213` and then branch only on `_effective != null` with the whole suite green.
- Pinned both halves of the defect in one row: the value `bind()` **returns** and the status `GlobalHotkey.current` **records**. A fix that corrected the return value and left `_recordStatus` holding a stale `HotkeyBound` would still show a later-mounting settings screen "In effect: Ctrl+Shift+G" under a dead backend (HOTKEY-06).
- Baselined the three refusals that must **keep** abandoning the rebind — `keyRefused`, `badRequest`, and a bare `StateError` — green at this same commit. These are the routes that must not change, so 01-16's run is a comparison rather than an assertion.
- Left `lib/` byte-identical and the analyzer merge gate clean. The suite is deliberately red for exactly one row.

## Task Commits

1. **Task 1: The workerGone rebind row, written red and recorded red** — `a615061` (test)
2. **Task 2: The three contrast rows that bound the fix** — `fd3cba7` (test)

## Files Created/Modified

- `test/infrastructure/hotkey/x11_global_hotkey_test.dart` — +232 lines, 0 deletions. Four new rows in the `binding (CAP-1, CAP-12, AD-10, AD-12)` group, placed immediately after the existing `D-10, AD-10: a grab the seam refuses mid-rebind abandons the rebind …` row at `:243`, so the refusal that must abandon and the refusal that must not sit together as the pair they are.

## The fail-first evidence (T-01-73)

**Produced at commit `fd3cba7`** (`feat/bootstrap-domain-ring`), against the adapter as it stands with `lib/` untouched. Re-runnable at that sha with:

```
export PATH=$PATH:/home/vscode/flutter/bin:/home/vscode/flutter/bin/cache/dart-sdk/bin
dart test test/infrastructure/hotkey/x11_global_hotkey_test.dart --plain-name 'CR-02'
```

Verbatim (`/tmp/g0115-failfirst.txt`, backed up to the session scratchpad):

```
00:00 +0 -1: binding (CAP-1, CAP-12, AD-10, AD-12) HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears the previous combination instead of reporting it as in effect [E]
  Expected: <Instance of 'HotkeyUnavailable'>
    Actual: <Instance of 'HotkeyBound'>
  the worker that owned the previous grab is gone, so reporting the previous combination as effective would name a shortcut nothing is serving while it is still taken from every other application. `HotkeyUnavailableCause.noBackend` is the answer because there is nothing left to ask: inviting the user to pick a different combination is advice no combination on this host can take

  package:matcher                                               expect
  test/infrastructure/hotkey/x11_global_hotkey_test.dart 343:7  main.<fn>.<fn>
```

`Expected: HotkeyUnavailable` / `Actual: HotkeyBound` is precisely the defect CR-02 describes: `refusal` is computed and then discarded on the rebind arm, so the distinction the whole `HotkeyRefusalCode` enum exists to carry is thrown away exactly where it changes the answer.

The expectation was authored and committed **before any edit to `lib/` exists**, which is the property this plan's prohibition P2 turns on and which `git log` can check later: `git diff --numstat 8dab2e7..fd3cba7 -- lib/` is empty.

## The deliberately red row, and what restores it

**The suite is red at this commit for exactly one row, on purpose.**

- Failing row: `binding (CAP-1, CAP-12, AD-10, AD-12) HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears the previous combination instead of reporting it as in effect`
- File-scoped run: `dart test test/infrastructure/hotkey/x11_global_hotkey_test.dart` → **+29 -1**, and the one failure is the row above.
- **Plan 01-16 is what turns it green** (wave 2). Every other gap-closure plan whose gate runs the project's broad suite command sits behind 01-16 for this reason: a broad `dart test … test/infrastructure …` globs this file.

**The three contrast rows are expected to stay green through 01-16, untouched:**

| Row | Arms | Expected through 01-16 |
|---|---|---|
| `D-10, AD-10, CR-02: keyRefused leaves the previous combination in effect, because a backend that answered has released nothing` | `HotkeyRegistrarRefusal(code: keyRefused)` | **Stays green.** Asserts `HotkeyBound(effective: Ctrl+Shift+G, authority: application)`, one error line containing `abandoned`, and one delivered activation after `registrar.emitPress()` — the half a call-sequence check cannot state. |
| `D-10, AD-10, CR-02: badRequest leaves the previous combination in effect — a protocol defect is not an absent backend` | `HotkeyRegistrarRefusal(code: badRequest)` | **Stays green.** Same expectation. `_causeOf`'s doc says `badRequest` takes the non-defeatist reading deliberately; this row is what pins it. |
| `D-10, AD-10, CR-02: a rejection that is not a refusal leaves the previous combination in effect` | bare `StateError` | **Stays green.** Same expectation, plus `context == {'error_type': 'StateError'}` with no `refusal_code` key, which is what `_refusalContext` produces when `_refusalOf` answers null. |

If any of the three goes red in 01-16, the fix has been over-applied into answering `HotkeyUnavailable` for every refusal — which would silently undo plan 01-03's whole deliverable, D-10's product rule and UAT test 3's live pass. That is the failure mode this control set exists to make loud.

## Verification results

| Gate | Result |
|---|---|
| `dart analyze --fatal-infos` | **PASS** — "No issues found!" (a red row analyzes clean; the merge gate AGENTS.md §6 names is unaffected) |
| `dart test test/infrastructure/hotkey/x11_global_hotkey_test.dart` | **+29 -1**, exactly one failing test, and it is the `CR-02` row |
| `dart test … --plain-name 'keyRefused leaves the previous combination'` | **PASS** — "All tests passed!" |
| `dart test … --plain-name 'badRequest leaves the previous combination'` | **PASS** — "All tests passed!" |
| `dart test … --plain-name 'a rejection that is not a refusal leaves the'` | **PASS** — "All tests passed!" |
| `grep -rn 'workerGone' test/ \| wc -l` | **8** (was **0** at HEAD `8dab2e7`) |
| `flutter test --exclude-tags=live test/ui test/platform test/composition` | **PASS** — +165 ~7, unchanged from baseline |
| `git diff --numstat -- lib/` | **empty** — no production code touched |
| `dart format --set-exit-if-changed` on the modified file | **PASS** — 0 changed |

**The broad `dart test` suite command was deliberately NOT run as a gate.** It globs `test/infrastructure`, which includes this file, so it would report this plan's intended red as this plan's failure. The plan's frontmatter scopes every gate to the single file for exactly this reason.

## Decisions Made

- **The log assertion is an equality, not a `contains`, and not an absence.** The adapter has two messages on this catch arm: `'the X11 key grab was refused'` (the refusal answered as a refusal) and `'the X11 key grab was refused, so the rebind was abandoned and the previous combination is still in effect'`. A `contains('refused')` would be satisfied by both, so it could not distinguish the fixed adapter from the unfixed one; an absence assertion would pass against an adapter that logs nothing. Equality against the first states the positive and excludes the second. **Consequence for 01-16:** the fix should route the backend-gone case to the same `_log` call the nothing-held arm already makes, rather than authoring a third sentence.
- **The `workerGone` message is the registrar's own, verbatim.** Taken from `_onWorkerMessage`'s call to `_failPending` at `x11_key_grab_registrar.dart:281-284`. This lets the row assert that the seam's project-authored diagnosis is carried through rather than replaced — the half the existing `noBackend` row at `:174` already pins for the other code on this arm.
- **The first bind's success assertion is load-bearing and says so in its `reason:`.** Without it, a future change that made the first bind fail would silently move the row onto the nothing-held arm, where the unfixed adapter *already* returns `HotkeyUnavailable` — turning the row green for the wrong reason and destroying its value as an oracle.
- **The `StateError` contrast row was written despite overlapping the existing `:243` row**, with an in-code comment naming it as the matrix's null case rather than as new coverage, per the plan's instruction. A later editor deleting it as a duplicate now knows the deletion costs the matrix its third input.

## Deviations from Plan

None - plan executed exactly as written.

Both tasks' actions, verifications and acceptance criteria were carried out literally. No deviation rule fired: no bug was found in the code under test that this plan was allowed to fix (the defect is 01-16's to fix by design), nothing blocked either task, and no architectural question arose.

## Issues Encountered

- **`--plain-name 'CR-02'` is no longer selective after Task 2.** The three contrast rows also carry `CR-02` in their names, so Task 1's capture command now matches four rows and reports `+3 -1` rather than `+0 -1`. The gate's substance is unaffected — the file still contains `CR-02`, `Expected:`, `HotkeyBound`, and does not contain "All tests passed" — and the whole-file run independently confirms exactly one failure. Noted so a later reader is not surprised by the re-run's row count. Narrowing to the single row: `--plain-name 'a refusal whose backend is gone'`.

## Known Stubs

None. No hardcoded empty values, no placeholder text, no unwired components. The one intentionally-failing row is not a stub — it is the plan's deliverable, is documented above, and is closed by 01-16.

## Threat Flags

None. No new network endpoint, auth path, file access pattern or schema change. The asserted log `context` maps are exactly `{'error_type': …, 'refusal_code': …}` — an enum name and a type name, both project-authored — asserted by equality rather than `containsPair`, which is what keeps a later addition of a leaky key visible (T-01-75). No `toString()`, no message body, no clipboard content enters a log assertion.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **01-16 is unblocked and has its oracle.** It should: read the cause on the rebind arm, route `noBackend` and `workerGone` to `HotkeyUnavailable` (and clear the recorded status), leave `keyRefused`, `badRequest` and non-refusal rejections on `_abandonedRebind`, and log the backend-gone case with the existing `'the X11 key grab was refused'` line. Success is the `CR-02` row green and the three contrast rows untouched and still green.
- **01-17's live probe** should match on the row name `HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears the previous combination instead of reporting it as in effect`, which is the exact wording the plan specified and which is preserved verbatim in the file.
- **HOTKEY-01 and HOTKEY-08 are not closed by this plan.** The oracle exists and is red. 01-16 and 01-17 declare the same two IDs, so the shared-ID gate correctly holds them open until the last declaring plan produces its SUMMARY.
- **Blocker for the wave boundary:** no plan whose gate runs the project's broad `test_command` may run before 01-16 lands. This is already encoded in the plans' `wave:` values.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-11*

## Self-Check: PASSED

- `test/infrastructure/hotkey/x11_global_hotkey_test.dart` — FOUND on disk
- `.planning/phases/01-hotkey-truth/01-15-SUMMARY.md` — FOUND on disk
- Commit `a615061` — FOUND in `git log --oneline --all`
- Commit `fd3cba7` — FOUND in `git log --oneline --all`
