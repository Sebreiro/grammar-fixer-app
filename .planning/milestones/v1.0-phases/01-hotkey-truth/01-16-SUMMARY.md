---
phase: 01-hotkey-truth
plan: 16
subsystem: infra
tags: [x11, hotkey, dart, ffi, workerGone, CR-02, HotkeyUnavailableCause]

# Dependency graph
requires:
  - phase: 01-hotkey-truth
    provides: "01-15's fail-first CR-02 oracle and its three contrast rows; 01-04's HotkeyUnavailableCause and the HotkeyRegistrarRefusal/HotkeyRefusalCode seam; 01-03's acquire-before-release rebind ordering"
provides:
  - "An X11 seam-refused arm whose answer is decided by the refusal's CODE, not merely by whether a previous binding was recorded"
  - "A workerGone/noBackend refusal mid-rebind now returns HotkeyUnavailable(noBackend) and clears _effective, so `current` cannot report a shortcut nothing is serving"
  - "keyRefused, badRequest and non-refusal rejections still return HotkeyBound naming the previous combination — 01-03's strength is not spent closing this gap"
  - "The four-code matrix closed on both diagonals plus a recovery row, so 'the code decides, not the arm' is asserted rather than assumed"
affects: [01-17, 01-20, hotkey, x11, settings, phase-02, phase-05]

# Actuals (#2632)
actuals:
  tokens: 2458
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hoist-the-translation: a catch arm computes its user-facing cause ONCE and both the branch condition and the returned value read that one local, so the arm cannot drift into asking twice and answering differently"
    - "Matrix-on-both-diagonals: a code-vs-arm decision is pinned by driving the same code on both arms and both codes on the same arm, so the answer provably follows the code"

key-files:
  created: []
  modified:
    - lib/src/infrastructure/hotkey/x11_global_hotkey.dart
    - test/infrastructure/hotkey/x11_global_hotkey_test.dart

key-decisions:
  - "The plan's verify #4 ('dart test --plain-name workerGone' reports >= 3) is reported NOT MET literally and substituted rather than satisfied by renaming 01-15's row: that name is frozen and 01-17's live probe matches on it verbatim."
  - "_causeOf is byte-identical: the gap was never the translation, only that the arm did not consult it. Re-mapping workerGone to keyRefused (prohibition P1a) was never on the table."
  - "The cleared branch reuses the arm's EXISTING 'the X11 key grab was refused' log call rather than authoring a third sentence — the fix routes the backend-gone case to the line the nothing-held arm already emits, exactly as 01-15's equality assertion required."
  - "The recovery row binds a THIRD combination, not a retry of either earlier one, so it cannot pass against an implementation answering from a stale record."

patterns-established:
  - "A log line must follow the value beside it: the arm that clears a binding keeps the refusal-answered-as-a-refusal sentence and is structurally unable to reach the abandoned-rebind one, so the false claim is removed rather than moved into the journal."

requirements-completed: [HOTKEY-01, HOTKEY-08]
# Declared because the plan declares them. 01-17 also declares both, so the
# shared-ID gate holds them open until the last declaring plan finishes.

coverage:
  - id: D1
    description: "The X11 seam-refused arm reads the refusal's cause: a workerGone refusal mid-rebind returns HotkeyUnavailable(noBackend) carrying the registrar's own sentence, clears _effective, and `current` agrees — 01-15's recorded-red row, now green"
    requirement: "HOTKEY-01"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears the previous combination instead of reporting it as in effect"
        status: pass
      - kind: other
        ref: "git diff HEAD~2 -- lib/src/infrastructure/hotkey/x11_global_hotkey.dart | grep -c 'HotkeyUnavailableCause.noBackend'  →  1"
        status: pass
    human_judgment: false
  - id: D2
    description: "The four-code matrix is whole on both diagonals: noBackend driven on the REBIND arm, workerGone driven on the FIRST-bind arm — so the answer provably follows the refusal code rather than whether something happened to be held"
    requirement: "HOTKEY-08"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#HOTKEY-01, HOTKEY-08, CR-02: noBackend refused mid-rebind clears the previous combination too — the answer follows the cause, not the arm"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#HOTKEY-01, HOTKEY-08, CR-02: workerGone refused on a first bind is still noBackend — the code decides, not the arm"
        status: pass
    human_judgment: false
  - id: D3
    description: "The cleared _effective re-opens the path rather than latching: after a rebind cleared by workerGone, a third combination binds, `current` reports it, and a press reaches activations exactly once"
    requirement: "HOTKEY-01"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#HOTKEY-01, CR-02: after a rebind cleared by workerGone the adapter binds a third combination and it fires"
        status: pass
    human_judgment: false
  - id: D4
    description: "The fix is not over-applied: keyRefused, badRequest and a rejection that is not a HotkeyRegistrarRefusal at all still return HotkeyBound naming the previous combination, and that combination still fires"
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
  - id: D5
    description: "The three gate commands are green and the suite count is explained by arithmetic, not by assertion"
    verification:
      - kind: other
        ref: "dart analyze --fatal-infos  →  'No issues found!'"
        status: pass
      - kind: integration
        ref: "dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart  →  +981 ~2, All tests passed"
        status: pass
      - kind: integration
        ref: "flutter test test/ui test/platform test/composition  →  +165 ~7, All tests passed"
        status: pass
      - kind: other
        ref: "git diff --numstat HEAD~2 -- lib/src/domain/ lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart | wc -l  →  0"
        status: pass
    human_judgment: false
  - id: D6
    description: "Plan verify #4 and its matching acceptance criterion ('at least three rows NAME workerGone') are NOT met literally and were substituted, not adjusted"
    verification:
      - kind: other
        ref: "dart test test/infrastructure/hotkey/x11_global_hotkey_test.dart --plain-name 'workerGone'  →  +2 (plan expected >= 3)"
        status: fail
      - kind: other
        ref: "substituted: three distinct test blocks arm HotkeyRefusalCode.workerGone (file lines 297, 597, 635) and 'dart test … --plain-name CR-02' reports +7 all passing"
        status: pass
    human_judgment: true
    rationale: "A reviewer must bless the substitution rather than a classifier reading a pass. The literal gate counts row NAMES; 01-15's rebind cell is named 'a refusal whose backend is gone …' and does not carry the token, and that name is frozen — 01-17's live probe matches on it verbatim, and 01-15's prohibition P2 forbids editing the row. Renaming it to make a grep pass was refused. The matrix the criterion exists to protect IS complete; the proxy measured the wrong thing."
  - id: D7
    description: "T-01-76's accepted residual: the change reports the dead shortcut honestly but does NOT release the stranded X11 passive grab"
    verification: []
    human_judgment: true
    rationale: "Not a shipped deliverable and deliberately not closed here. The connection holding the grab is unreachable from the surviving isolate; releasing it needs worker-lifecycle replacement, which is Phase 5's stated goal (CR-01/WR-01/CR-03/WR-02). A human must confirm the residual is accepted rather than overlooked. Plan 01-20 files it."

# Metrics
duration: 15 min
completed: 2026-09-11
status: complete
---

# Phase 01 Plan 16: Let the Cause Decide Summary

**The X11 seam-refused catch arm now reads the `HotkeyRefusalCode` it was already computing: a `workerGone`/`noBackend` refusal mid-rebind clears `_effective` and returns `HotkeyUnavailable(noBackend)` instead of `HotkeyBound` naming a combination the dead worker still holds on the server and nothing can serve.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-09-11T12:50:00Z
- **Completed:** 2026-09-11T13:05:00Z
- **Tasks:** 2
- **Files modified:** 2 (one adapter, one test file)

## Accomplishments

- **Closed 01-VERIFICATION.md `gaps[0]` / 01-REVIEW.md CR-02.** `x11_global_hotkey.dart` computed `final refusal = _refusalOf(error)` and then branched only on `_effective != null`, throwing away the distinction the whole `HotkeyRefusalCode` enum exists to carry precisely where it changes the answer. The arm now hoists `final cause = _causeOf(refusal);` and widens its early return to `stillInEffect == null || cause == HotkeyUnavailableCause.noBackend`.
- **Turned 01-15's recorded-red row green by changing the adapter, never the row.** `git diff --numstat 4247446..HEAD -- test/infrastructure/hotkey/x11_global_hotkey_test.dart` is `190  0` — 190 insertions, **zero deletions**. The oracle is byte-identical to the one recorded failing at `fd3cba7`.
- **Did not spend 01-03's deliverable to close this gap.** All three contrast rows (`keyRefused`, `badRequest`, a bare `StateError`) are still green and untouched: a refusal the backend *answered* has released nothing, so the previous combination is still grabbed and still opens the panel.
- **Closed the four-code matrix on both diagonals plus recovery.** `noBackend` on the rebind arm and `workerGone` on the first-bind arm now both exist, so "the code decides, not the arm" is asserted rather than assumed; and the recovery row proves the cleared `_effective` re-opens the path instead of latching the user out of every shortcut.
- **Full suite back to green.** 981 passed / 2 skipped on the binding-free gate (974 at `52cebe8` + 01-15's 4 + this plan's 3 — the arithmetic the plan asked for, and it lands exactly), 165 passed / 7 skipped on the Flutter-bound gate, `dart analyze --fatal-infos` clean.

## Task Commits

1. **Task 1 (tracer): The cause-decides arm** — `b421a9c` (fix)
2. **Task 2: The four-code matrix, whole** — `5bcd445` (test)

## Files Created/Modified

- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` — +30 / −6. One catch arm: a hoisted `cause`, a widened condition, an `_effective = null;` assignment, the returned value reading the hoisted local, a *why* comment naming the mechanism, and an amended `_abandonedRebind` doc stating both conditions.
- `test/infrastructure/hotkey/x11_global_hotkey_test.dart` — +190 / −0. Three new rows plus one new `_ctrlAltM` binding constant.

## What actually changed in the adapter

The arm's order is unchanged where it matters — the `_disposed` check still runs first, because the shipped seam *rejects* a grab that lands during teardown and that is the branch the stop-during-rebind race actually takes. Below it:

```dart
final refusal = _refusalOf(error);
final cause = _causeOf(refusal);
final stillInEffect = _effective;
// … why, naming the mechanism …
if (stillInEffect == null || cause == HotkeyUnavailableCause.noBackend) {
  _effective = null;
  _log(() => _logger.error('the X11 key grab was refused',
      context: _refusalContext(error, refusal)));
  return HotkeyUnavailable(
    cause: cause,
    message: refusal?.message ?? _unclassifiedRefusal,
  );
}
```

Everything below the branch is byte-identical: the abandoned-rebind log sentence and `return _abandonedRebind(stillInEffect);` stay exactly as they were. Because the condition above now catches the backend-is-gone case, that sentence is **structurally unreachable** for it — which is prohibition P1(b) satisfied by the shape rather than by an added guard.

`_causeOf` is untouched (`git diff` over its declaration: 0 matches). It already mapped `workerGone → noBackend` correctly; the gap was entirely that the arm did not ask.

## Gate results

| Gate | Result |
|---|---|
| `dart analyze --fatal-infos` | **PASS** — "No issues found!" |
| `dart test test/infrastructure/hotkey/x11_global_hotkey_test.dart` | **+33**, All tests passed (30 after Task 1, 33 after Task 2) |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **+981 ~2**, All tests passed |
| `flutter test test/ui test/platform test/composition` | **+165 ~7**, All tests passed |
| `dart test … --plain-name 'CR-02'` | **+7**, All tests passed |
| `git diff HEAD~2 -- …/x11_global_hotkey.dart \| grep -c 'HotkeyUnavailableCause.noBackend'` | **1** |
| `git diff --numstat HEAD~2 -- lib/src/domain/ …/x11_key_grab_registrar.dart \| wc -l` | **0** |
| `grep -c '_causeOf(' …/x11_global_hotkey.dart` | **2** (declaration + exactly one call site) |
| `dart format --set-exit-if-changed` on both modified files | **PASS** — 0 changed |
| `dart test … --plain-name 'workerGone'` | **+2** — plan expected ≥ 3. **See "Substituted acceptance criterion" below.** |

### The suite-count arithmetic, stated

`974` (binding-free suite at HEAD `52cebe8`, per `.github/workflows/ci.yml:100`) `+ 4` (01-15's oracle and three contrast rows) `+ 3` (this plan's two diagonals and recovery row) `= 981`. The measured figure is **981 passed / 2 skipped**. The number did not have to be argued with.

## Substituted acceptance criterion (not a pass — a finding)

Plan verify #4 and its matching acceptance criterion read:

> `dart test … --plain-name 'workerGone'` — **fails_when** the reported passing count for rows matching `workerGone` is fewer than 3
> At least three rows … name `workerGone`: the rebind cell (01-15's), the first-bind cell, and the recovery row.

It reports **+2**, and that is reported rather than engineered away.

**Why.** `--plain-name` matches the test's *name*. 01-15's rebind cell is named `HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears the previous combination instead of reporting it as in effect`. It does not contain the literal token `workerGone` — it drives `HotkeyRefusalCode.workerGone` in its body. The planner enumerated it as one of the three matching rows without checking the name it had itself frozen one plan earlier.

**Why it was not fixed by renaming.** Two independent reasons, either sufficient: 01-15's prohibition P2 forbids editing the row (the fail-first evidence is only meaningful while the expectation is the one recorded red), and 01-15-SUMMARY.md instructs 01-17's live probe to match on that exact wording. Renaming it to make a grep pass would have broken a downstream plan to satisfy a proxy.

**Substituted evidence, measuring what the criterion exists to protect.** Three *distinct test blocks* arm `HotkeyRefusalCode.workerGone` — file lines `297` (01-15's rebind cell), `597` (the first-bind cell), `635` (the recovery row) — and `dart test … --plain-name 'CR-02'` reports **+7 all passing**. The matrix is complete; the plan's mechanical proxy measured row names rather than what the rows drive.

Filed to `.planning/WINDOWS.md` as an open `deviation`. **Needs a reviewer's blessing, not a code change.**

## Decisions Made

- **The cause is hoisted and read twice from one local, never computed twice.** `grep -c '_causeOf('` is 2 — the declaration and exactly one call site — so the branch condition and the returned value cannot drift into asking the same question and getting different answers.
- **The cleared branch reuses the arm's existing log call.** 01-15's equality assertion (`errors().single.message == 'the X11 key grab was refused'`) was deliberately written as the positive so it could not be satisfied by the abandoned-rebind sentence. The fix therefore routes the backend-gone case to the line the nothing-held arm already emits rather than authoring a third. No second log line, no widened context map.
- **`_effective = null;` is in the branch even though the first disjunct already has it null.** It is what makes the *second* disjunct true of the adapter's own record — without it `current` could answer with a stale registration and a later rebind could be short-circuited against a combination the adapter no longer holds.
- **The recovery row uses a third combination (`Ctrl+Alt+M`), not a retry.** A recovery row re-asking for a combination the adapter had already seen could pass against an implementation answering from a stale record instead of from a grab it actually made.
- **`_abandonedRebind`'s doc now states two conditions, not one.** A previous combination recorded **and** a backend still present to be holding it; `_refusedBeforeBackend` satisfies the second structurally (nothing was sent to the backend on that path), while the seam-refused caller must establish it from the refusal's cause.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Expected modifier rendering order in the recovery row's call assertion**
- **Found during:** Task 2
- **Issue:** the row asserted `['grab(HotkeyGrab(control+alt 0x00070010))']`; `HotkeyGrab` renders modifiers in set-insertion order, so the actual string is `alt+control`.
- **Fix:** corrected the expectation to the rendered order. The assertion's claim — one grab and no release — is unchanged.
- **Files modified:** `test/infrastructure/hotkey/x11_global_hotkey_test.dart`
- **Verification:** the row and the whole file pass (`+33`).
- **Committed in:** `5bcd445` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug, in this plan's own new test row).
**Impact on plan:** none on scope. No production behaviour was involved; the expectation was wrong about a fake's `toString`, not about the adapter.

Separately, and **not** a deviation because it was not fixed: plan verify #4 is reported as **NOT MET, substituted** — see the section above. The plan's own instruction ("do not adjust the expectation — find the difference and report it") is what was followed.

## Prohibition self-check

| Prohibition | Status |
|---|---|
| P1(a) — do not re-map `workerGone` to `keyRefused` in `_causeOf` | **Honoured.** `_causeOf` is byte-identical; `git diff` over its declaration returns 0 matches. |
| P1(b) — do not leave the abandoned-rebind sentence on an arm that just cleared the binding | **Honoured structurally.** The widened condition returns before that sentence is reachable for a backend-gone refusal; no guard was added and the sentence itself was not edited. |
| P2 — the closure evidence must not be retrofitted or vacuous | **Honoured.** `git diff --numstat 4247446..HEAD` over the test file is `190  0`: zero deletions, so 01-15's expectation is exactly the one recorded red at `fd3cba7`. The shortfall the row exposed in the plan's *own* gate was handed back rather than adjusted. |
| P4 — no user text or vendor `toString()` in a log line | **Honoured.** `_refusalContext` is untouched and remains the single producer, reducing to `error_type` (a runtime type name) plus `refusal_code` (a project-authored enum name). Both new context assertions use **map equality**, so a later key carrying the caught object's own text turns a row red rather than shipping. |

## Issues Encountered

- **The plan's `--plain-name 'workerGone'` gate is not selective the way the planner assumed.** Documented in full above. It is the second time in this wave a `--plain-name` proxy has mismeasured (01-15 recorded the same class of problem for `--plain-name 'CR-02'`, which matched four rows instead of one). A `--plain-name` filter is a claim about row *names*, and row names in this file are prose sentences, not tags.

## Known Stubs

None. No hardcoded empty values, no placeholder text, no unwired components. Every row added drives the real adapter over the real fake seam.

## Threat Flags

None new. The plan's own register is unchanged by execution:

- **T-01-76 (accepted residual, restated so it is not mistaken for an oversight):** the stranded X11 passive grab is **not released** by this change. The X socket the dead isolate opened has no finalizer, so the server keeps swallowing the combination system-wide until the process exits. What changed is that the user is now *told* the shortcut is not in effect instead of being told it is. Releasing it needs worker-lifecycle replacement — Phase 5's stated goal (CR-01/WR-01/CR-03/WR-02) — and plan 01-20 files it.
- **T-01-78 (residual, unchanged):** with the arm now answering `HotkeyUnavailableCause.noBackend`, `hotkey_status_view` renders the `noBackend` cause line — *"This desktop provides no global shortcuts, so no combination can be registered here."* — which **overstates** for a `workerGone`: the desktop does provide global shortcuts; this daemon's worker died. The registrar's own second sentence beside it is accurate. That cause line is `hotkey_status_view`'s text, belongs to WR-06 / SETTINGS-09 (FLAT-16) in **Phase 2**, and was deliberately not edited here. Honest summary: a pair that overstates in its first line and is accurate in its second replaces a single line that was simply false.

No new network endpoint, auth path, file access pattern or schema change. No package-manager install.

## TDD note

Task 2 carries `tdd="true"`, but `TDD_MODE` is `false` for this dispatch and the task's entire deliverable is test rows. A RED gate is not meaningful here and was not manufactured: the fail-first RED for this gap was **plan 01-15's deliverable**, recorded at `fd3cba7` with the verbatim `Expected: HotkeyUnavailable` / `Actual: HotkeyBound`, and `git log` can check that it precedes `b421a9c`. Task 2's rows are matrix completion against an already-landed fix and are expected green on first run, which they were.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **01-17's live probe is unblocked and its match string is intact.** The row name `HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears the previous combination instead of reporting it as in effect` is preserved verbatim; the row is now green.
- **The wave-2 blocker is lifted.** Plans whose gates run the project's broad `test_command` may now run: the binding-free suite is `+981 ~2` and the Flutter-bound suite is `+165 ~7`, both green.
- **Owed to plan 01-20 (ledger), not filed here:** the amended 01-03 truth (the unconditional wording that licensed the branch), T-01-76's accepted residual, and T-01-78's `noBackend` cause-line overstatement for Phase 2 / WR-06.
- **Owed to a reviewer:** the substituted acceptance criterion (D6). It is an open `deviation` in `.planning/WINDOWS.md` and blocks nothing mechanically, but it is a real miss in the plan's gate design and should not be closed by someone who has not read why renaming the row was refused.
- **HOTKEY-01 and HOTKEY-08 are not closed by this plan alone.** 01-17 also declares both, so the shared-ID gate correctly holds them until the last declaring plan produces its SUMMARY.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-11*

## Self-Check: PASSED

- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` — FOUND on disk
- `test/infrastructure/hotkey/x11_global_hotkey_test.dart` — FOUND on disk
- `.planning/phases/01-hotkey-truth/01-16-SUMMARY.md` — FOUND on disk
- Commit `b421a9c` — FOUND in `git log --oneline --all`
- Commit `5bcd445` — FOUND in `git log --oneline --all`
- `.planning/WINDOWS.md` entry **31** (01-15's deliberately RED row) — `status: fixed`, `resolved_at` set
- `.planning/WINDOWS.md` entry **32** (the substituted verify #4) — filed `open`, kind `deviation`
