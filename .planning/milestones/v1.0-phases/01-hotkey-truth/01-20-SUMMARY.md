---
phase: 01-hotkey-truth
plan: 20
subsystem: infra
tags: [ledger, deferred-work, append-only, WR-05, WR-08, CR-02, G-01-15, G-01-16, x11, hotkey]

# Dependency graph
requires:
  - phase: 01-16
    provides: "the cause-decides seam-refused arm, the amended must-have truth this entry quotes as the replacement, and the two residuals (T-01-76, T-01-78) it recorded as owed to this plan"
  - phase: 01-17
    provides: "`test/platform/worker-gone-observation.md` — the live before/after record entry B cites as its runtime evidence, and the directly observed shutdown-abandonment symptom that upgraded the stranded grab from a source-read argument"
  - phase: 01-18
    provides: "a clean lib/ and test/ tree at this plan's start, so the ledger-only scope fence is measurable rather than asserted"
  - phase: 01-19
    provides: "the WR-08 fork actually taken (option (a), `de50896`), its pre-deletion measurement, and the replacement assertion's `reason:` string entry E records"
provides:
  - "DW-126 — WR-05 filed rather than fixed, as a ratified decision, with the three anchors re-derived at HEAD, a fourth anchor 01-REVIEW.md does not carry, and the proposed fix in substance"
  - "DW-127 — the stranded X11 passive grab the G-01-15 closure makes visible without releasing, owner Phase 5, with what was measured separated from what was reasoned"
  - "DW-128 — the `noBackend` cause line that overstates for a dead worker, owner Phase 2 / WR-06 / SETTINGS-09"
  - "DW-129 — plan 01-03's must-have truth amended IN THE LEDGER, with both wordings quoted and the planning-gap-not-executor-failure distinction stated outright"
  - "DW-130 — the WR-08 fork recorded as a decision with its measured reason and the option not taken"
  - "A measured append-only proof over the whole gap-closure set: +43 insertions, 0 deletions on the ledger; the `01-01-*` … `01-14-*` diff across `52cebe8..HEAD` empty"
affects: [phase-02, phase-05, phase-07, deferred-work ledger, hotkey, settings]

# Actuals (#2632) — estimateTokens scale (chars/4 over the realized diff), not a harness count.
actuals:
  tokens: 6696
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A residual is filed with its measured half and its reasoned half written in different voices, and the reasoned half says plainly what nobody watched happen (DW-124's register)"
    - "A must-have truth that was wrong is amended by APPENDING the amendment beside the executed plan, never by editing it — both texts survive and the later entry is the finding"
    - "Append-only compliance is measured with `git diff --numstat`'s deletions column BEFORE the commit and against the whole set's base, so it can be neither defeated by a markdown bullet nor passed vacuously post-commit"

key-files:
  created: []
  modified:
    - _bmad-output/implementation-artifacts/deferred-work.md

key-decisions:
  - "Entry A's severity is `low`, matching 01-VERIFICATION.md:341's 'Cosmetic relative to the goal' adjudication rather than inflating it — nothing user-visible changes either way and the caller already learns of both failures through the modelled refusal; what is filed is a false comment and two dead constructs, not a lost error path."
  - "Entry A records the ratification by citing the planning-run artefacts that carry it (01-16-PLAN.md:269-270, 01-18-PLAN.md:9, 01-19-PLAN.md:76, committed as 375a6d5 / 8dab2e7) and says outright that it is citing those texts rather than a transcript — a ledger entry must not imply a quotation it does not hold."
  - "Entry A adds a fourth anchor 01-REVIEW.md does not carry: the `[_errorContext]` square-bracket doc link at `x11_key_grab_registrar.dart:498`, which a deletion will trip over. Re-derived at this HEAD because 01-VERIFICATION.md:341 records WR-05 as 'not independently re-derived line by line'."
  - "The `workerGone`-reachable-but-not-triggerable finding is folded into entry B rather than given a sixth entry: it is the same mechanism (no `on Object` guard on `handle` plus `errorsAreFatal`), the same owner (WR-01, Phase 5), and it is the reason 01-17 had to inject."
  - "The executed-plan scope fence is measured against `52cebe8` (the pre-gap-closure base) rather than only against the working tree, because a post-commit working-tree diff is empty and the check would go vacuous."

patterns-established:
  - "Credit the part that is right inside an entry that files what is wrong: DW-128 records the verbatim carry-through of the registrar's sentence, the single AD-12 tray mention and the absent 'In effect:' line beside the overstatement, so a Phase 2 reader does not 'fix' the half that works."
  - "A closure entry cites its runtime evidence by artefact path (`test/platform/worker-gone-observation.md`) rather than asserting the behaviour in its own voice — the DW-122 precedent, applied again."

requirements-completed: []
# The plan declares `requirements: []` deliberately: no ROADMAP requirement owns the ledger,
# and HOTKEY-01..10 / ARCH-02 are already recorded satisfied by the executed plans
# (01-VERIFICATION.md § Requirements Coverage). Naming one here would read as re-work.

coverage:
  - id: D1
    description: "WR-05 is on the record as an open, ratified deferral carrying the finding, its anchors and 01-REVIEW.md's proposed fix, so the later cluster inherits the work rather than the search"
    verification:
      - kind: other
        ref: "grep -c 'x11_key_grab_registrar.dart:967' _bmad-output/implementation-artifacts/deferred-work.md  →  1 (and `:1075` ×2, `:531-533` ×3, `:498` ×2)"
        status: pass
      - kind: other
        ref: "git diff --numstat -- lib/ test/ | wc -l  →  0 (filed, not fixed — the ratified decision honoured mechanically)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Both residuals the G-01-15 closure accepts are filed as open with the phase that owns them named, and each separates what was measured from what was reasoned"
    verification:
      - kind: other
        ref: "grep -c 'worker-gone-observation' …/deferred-work.md  →  4 (DW-127 cites the live record for what WAS measured)"
        status: pass
      - kind: other
        ref: "grep -ciE 'SETTINGS-09|WR-06' …/deferred-work.md  →  1 (DW-128 names the Phase 2 owner 01-VERIFICATION.md's `deferred:` block already assigned)"
        status: pass
      - kind: other
        ref: "DW-127 status: open, owner Phase 5 (CR-01/WR-01, CR-03, WR-02); DW-128 status: open, owner Phase 2"
        status: pass
    human_judgment: false
  - id: D3
    description: "Plan 01-03's must-have truth is amended in the ledger with both wordings quoted and the planning-gap-not-executor-failure distinction stated outright, while 01-03-PLAN.md is byte-identical"
    verification:
      - kind: other
        ref: "git diff --numstat 52cebe8 -- '.planning/phases/01-hotkey-truth/01-0*' '.planning/phases/01-hotkey-truth/01-1[0-4]-*' | wc -l  →  0"
        status: pass
      - kind: other
        ref: "awk '/^### DW-/{h=$0} /^resolution:/{print h}' … | tail -2  →  DW-129, DW-130; grep -c '^resolution:'  →  73 (was 71, rose by exactly 2)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The append-only rule and the executed-plan scope fence are measured rather than asserted"
    verification:
      - kind: other
        ref: "git diff --numstat 52cebe8 -- …/deferred-work.md  →  43  0  (43 insertions, 0 deletions across the whole gap-closure set)"
        status: pass
      - kind: other
        ref: "per-task, measured before each commit: Task 1 +25 −0, Task 2 +18 −0"
        status: pass
      - kind: other
        ref: "DW-9, DW-26, DW-44 all still read `status: done 2026-08-14`; DW-33 `done 2026-08-15`; DW-122 … DW-125 unedited (implied by the 0-deletion count)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Neither suite moved and the analyzer stayed clean — this plan edits one markdown file and nothing else"
    verification:
      - kind: other
        ref: "dart analyze --fatal-infos  →  'No issues found!'"
        status: pass
      - kind: integration
        ref: "dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart  →  +982 ~2, All tests passed"
        status: pass
      - kind: integration
        ref: "flutter test test/ui test/platform test/composition  →  +165 ~7, All tests passed"
        status: pass
    human_judgment: false
  - id: D6
    description: "The five entries say the right things — the register, the honesty clauses, the severities and the quoted fix are editorial judgments no grep settles"
    verification: []
    human_judgment: true
    rationale: "Every mechanical gate this plan carries measures SHAPE (an anchor is present, a status reads open, a deletion count is zero). None of them can measure whether DW-127's reasoned half is written in a voice a reader will not mistake for an observed one, whether DW-126's severity is honest, or whether DW-130 records the option-not-taken well enough that a reversal is knowing. A reviewer should read all five against DW-124 and DW-125, which are the register they are written in."

# Metrics
duration: 14 min
completed: 2026-09-11
status: complete
---

# Phase 01 Plan 20: The Record Summary

**Five append-only ledger entries — DW-126 … DW-130 — that put the whole gap-closure set on the record: WR-05 filed as a ratified decision rather than fixed, the two residuals the G-01-15 closure accepts named with the phases that own them, plan 01-03's wrong must-have truth amended beside the executed plan instead of inside it, and the WR-08 fork recorded with the option not taken. +43 insertions, 0 deletions.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-09-11T14:04:00Z
- **Completed:** 2026-09-11T14:18:00Z
- **Tasks:** 2
- **Files modified:** 1 (`_bmad-output/implementation-artifacts/deferred-work.md`)

## The five entry ids actually used

The highest canonical id at this plan's start was **DW-125**, re-derived with `grep -o '^### DW-[0-9]*' | sort -n | tail -1` rather than taken from the plan's prediction. The five entries are therefore:

| Entry | Id | Subject | Status |
|---|---|---|---|
| A | **DW-126** | WR-05 — two no-op statements under comments claiming the error was handled, and the dead helper they call; **filed rather than fixed, by decision** | `open` (+ `decision:`) |
| B | **DW-127** | the stranded X11 passive grab the G-01-15 fix makes **visible without releasing**; owner **Phase 5** | `open` |
| C | **DW-128** | the `noBackend` cause line that **overstates** for a dead worker; owner **Phase 2**, WR-06 / SETTINGS-09 (FLAT-16) | `open` |
| D | **DW-129** | plan 01-03's must-have truth, **amended in the ledger** | `done 2026-09-11` + `resolution:` |
| E | **DW-130** | the **WR-08 fork**, decided — deletion, not a new assertion | `done 2026-09-11` + `resolution:` |

## The append-only figures, quoted

Measured with `git diff --numstat`'s deletions column — never by grepping the diff for `^-`, because a deleted markdown bullet diffs as `-- foo` and this file is full of bullets — and taken **before** each commit, because a working-tree diff is empty afterwards and a deletions-only check would pass vacuously.

| Scope | Insertions | Deletions |
|---|---|---|
| Task 1 (DW-126, DW-127, DW-128), before commit `e531253` | **+25** | **0** |
| Task 2 (DW-129, DW-130), before commit `693b5af` | **+18** | **0** |
| **The whole set: `git diff --numstat 52cebe8 -- …/deferred-work.md`** | **43** | **0** |

`grep -c '^resolution:'` on the ledger read **71** at this plan's start and **73** at its end — rose by exactly 2, one for each `status: done` entry, which is the shape DW-95 and DW-122 establish and this file's own rule requires.

## The executed-plan scope fence

```
git diff --numstat 52cebe8 -- '.planning/phases/01-hotkey-truth/01-0*' \
                              '.planning/phases/01-hotkey-truth/01-1[0-4]-*' | wc -l
0
```

**Empty.** Measured against `52cebe8` — the pre-gap-closure base 01-VERIFICATION.md re-verified at — rather than only against the working tree, because a post-commit working-tree diff is empty and the check would have gone vacuous exactly where it matters. `01-03-PLAN.md`, its SUMMARY, and every other plan and SUMMARY numbered 01-01 through 01-14 are byte-identical after this plan. The amendment is filed, never applied.

`git diff --numstat -- lib/ test/ | wc -l` is also **0**: WR-05 was filed, not fixed, which is the user's ratified decision honoured mechanically rather than promised.

## The amended 01-03 truth, restated verbatim

So the correction is legible from this SUMMARY alone.

**The original**, from `01-03-PLAN.md` `must_haves.truths`, second entry — **not edited, still exactly this**:

> `HotkeyUnavailable` is returned from the X11 bind path only when nothing is held — when a previous combination is still in effect, a refused rebind returns `HotkeyBound` naming that previous combination and logs the abandonment.

**The replacement**, from `01-16-PLAN.md` `must_haves.truths`, third entry:

> AMENDED 01-03 TRUTH (the unconditional wording is what licensed the defect, and this is its replacement): `HotkeyUnavailable` is returned from the X11 bind path whenever nothing is held OR the backend that held it is gone; a refused rebind returns `HotkeyBound` naming the previous combination only while that combination is still grabbed by a live backend.

**And the clause that is the entire point of DW-129: this was a PLANNING gap, not an executor failure.** 01-03's executor implemented the truth exactly as written. 01-VERIFICATION.md says so twice — in `gaps[0].reason` ("The executor implemented the truth as written. The truth was wrong.") and at truth row 8 of the Observable Truths table, which marks 01-03 "✓ VERIFIED **(as written — and the wording is the licence for truth 0's defect)**" and closes "Executor did what was planned". The acquire-then-release ordering the truth asked for is intact in the code to this day. The defect was in the sentence, not in the code that satisfied it.

## What this set did NOT fix

Written here and not only in the entries, because a record that lists only closures reads as a claim that nothing was left standing.

1. **WR-05 is not fixed.** Two bare `_errorContext(error);` statements (`x11_key_grab_registrar.dart:967`, `:1075`) still swallow a `DynamicLibrary.open` failure and every guarded teardown failure inside the worker, under comments claiming the error was handled; `_errorContext` (`:531-533`) is still dead. **DW-126, open.** This is a ratified decision, not an omission.
2. **The stranded X11 passive grab is not released.** A dead worker's connection still holds the combination for the life of the process. The G-01-15 fix makes the state visible — the user is told the shortcut is not in effect instead of being told it is — and does nothing else about it, because the connection is unreachable from the surviving isolate. **DW-127, open, Phase 5.**
3. **The `workerGone` arm remains reachable in production and not triggerable from outside the process.** `_X11Worker.handle` still carries no `on Object` guard and `Isolate.spawn` still defaults to `errorsAreFatal: true`, while every throw the worker can actually take today is already guarded into a modelled refusal. That gap is why 01-17 had to inject a fault. Filed inside **DW-127** (same mechanism, same owner: WR-01, Phase 5).
4. **The `noBackend` cause line still overstates for a dead worker.** The desktop does provide global shortcuts; this daemon's worker died. **DW-128, open, Phase 2 / WR-06 / SETTINGS-09.**
5. **Nobody watched the stranded grab swallow the combination.** DW-127 says this in its own words. Two 5000 ms shutdown-abandonment lines were observed; what the X server does with the grab in the meantime is a reading of the code plus the absence of a finalizer.
6. **Both `behavior_unverified_items` in 01-VERIFICATION.md stand.** The Wayland arm is untouched and unobservable in this container.

## Task Commits

1. **Task 1: The ratified deferral and the two residuals — entries A, B and C** — `e531253` (docs)
2. **Task 2: The amended must-have truth and the deletion decision — entries D and E** — `693b5af` (docs)

**Plan metadata:** see the `docs(01-20): complete the record plan` commit.

## Files Created/Modified

- `_bmad-output/implementation-artifacts/deferred-work.md` — +43 / −0. Five new Format-1 entries appended after DW-125. Nothing else in the file was touched.

## Gate results

| Gate | Result |
|---|---|
| `dart analyze --fatal-infos` | **PASS** — "No issues found!" |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **+982 ~2**, All tests passed |
| `flutter test test/ui test/platform test/composition` | **+165 ~7**, All tests passed |
| ledger `git diff --numstat`, before each commit | **+25 −0** then **+18 −0**; **43 / 0** across the set |
| `grep -c '^resolution:'` | **71 → 73** (exactly +2) |
| DW-9 / DW-26 / DW-44 status | all still `status: done 2026-08-14` |
| `git diff --numstat 52cebe8 -- 01-0* 01-1[0-4]-*` | **0 lines** |
| `git diff --numstat -- lib/ test/` | **0 lines** |

Both suites are **unchanged from 01-19** (982 / 165), which is what a plan that edits one markdown file must produce.

## Decisions Made

- **Entry A's severity is `low`, not medium.** 01-VERIFICATION.md:341 adjudicates WR-05 "Cosmetic relative to the goal" and that stands on re-derivation: nothing user-visible changes either way, the caller already learns of both failures through the modelled refusal, and the privacy property the comments were protecting is satisfied trivially because nothing is logged at all. What is filed is a false comment and two dead constructs, not a lost error path. The plan said "do not inflate it"; it was not inflated.
- **The ratification is cited by artefact, and the entry says so.** 01-REVIEW.md, 01-16-PLAN.md:269-270, 01-18-PLAN.md:9 and 01-19-PLAN.md:76 all record WR-05 as ledger-only by the user's ratified decision, committed as `375a6d5` and `8dab2e7`. No transcript of the exchange exists in the repository, so DW-126 names those plan texts as its evidence and states plainly that it is citing them rather than quoting the answer. A ledger entry must not imply a quotation it does not hold — which is the same rule as DW-127's honesty clause, applied to provenance instead of to mechanism.
- **A fourth anchor was added to entry A that 01-REVIEW.md does not carry.** `x11_key_grab_registrar.dart:498` contains the square-bracket doc link `see [_errorContext]`, so deleting the helper without re-wording that line leaves a dangling reference. This is the same analyzer-visible class of link plan 01-19 measured for `hotkey_key_catalogue.dart` — where the doc link alone was what kept an import alive. 01-VERIFICATION.md:341 records WR-05 as "not independently re-derived line by line"; this filing did that work once so the later cluster need not.
- **The `workerGone`-reachable-but-not-triggerable finding went inside entry B rather than becoming a sixth entry.** It is the same mechanism as the stranded grab (no `on Object` guard on `handle` plus `errorsAreFatal: true`), the same owner (WR-01, Phase 5), and it is the reason the 01-17 observation needed an injection at all. Splitting it would have produced two entries a Phase 5 reader must join back together.
- **Entry C credits what is right beside what is wrong.** The registrar's sentence is carried through verbatim, the tray is named exactly once across the pair (AD-12), and no "In effect:" line appears at all — that last one *is* the G-01-15 closure showing on the screen. Recorded in 01-REVIEW.md's WR-09 register so a Phase 2 pass does not "fix" the half that works.
- **The scope fence is measured against `52cebe8`, not against the working tree.** The plan's own verify block runs `git diff --numstat -- '01-0*' '01-1[0-4]-*'`, which after Task 1's commit compares the tree to HEAD and returns 0 whether or not an executed plan was edited earlier in the run. The set-base form was run as well and is the figure reported.

## Deviations from Plan

None - plan executed exactly as written.

The plan's `<interfaces>` predicted "**DW-126 … DW-130 if the highest is still DW-125**"; it was, and the ids were re-derived rather than assumed, so the prediction and the outcome agree. No task hit a deviation rule, no auth gate fired, and no checkpoint was reached.

## Issues Encountered

None. The two mechanical hazards the plan warned about were both avoided by following its instructions rather than by recovering from them: the deletion count was read from `git diff --numstat`'s second column (not from a `^-` grep, which a deleted markdown bullet defeats), and both measurements were taken **before** their commits (not after, where the deletions-only half goes vacuous).

One thing worth naming for a later reader: the plan's own executed-plan fence command is vacuous when run post-commit, for the same reason its ledger check would be. It was run in the non-vacuous form against `52cebe8` and that is the figure this SUMMARY reports. The plan's command was also run, and also returns 0.

## Known Stubs

None. This plan writes five prose records into an append-only ledger; there is no code, no component to leave unwired, and no placeholder value. Every claim in every entry is either carried with a file:line anchor, cited to an observation record, or explicitly marked as reasoning rather than observation.

## Threat Flags

None new. The plan's register (T-01-95 … T-01-99) was exercised rather than assumed:

- **T-01-95** (an existing entry deleted, re-wrapped or rewritten) — measured `0` deletions before both commits and `0` across the whole set; `dart format` does not run on markdown, so nothing mechanical could have touched an existing entry either.
- **T-01-96** (a closed entry reopened by editing its status line) — DW-9, DW-26 and DW-44 all still read `status: done 2026-08-14`; DW-33 still reads `done 2026-08-15`. The refutation motion DW-123 established was used again for DW-129: name the earlier text, do not rewrite it.
- **T-01-97** (an executed plan edited to agree with a later finding) — the `01-01-*` … `01-14-*` diff across `52cebe8..HEAD` is empty.
- **T-01-98** (a residual filed with an argued claim in an observed voice) — DW-127 states in its own words that nobody pressed the combination in a second application against a daemon whose worker was dead, and that the injection was a named fault injection quoted verbatim in the record.
- **T-01-99** (a deferral recorded as an oversight) — DW-126 carries a `decision:` line in DW-125's register, naming what ratified it, where that is recorded, and when.

No new network endpoint, auth path, file access pattern or schema change. No package-manager install, so the Package Legitimacy Gate does not apply. No change to `COVERAGE.md`.

## Open items this plan did NOT close, and is not authorized to

Five `.planning/WINDOWS.md` entries stay **open**. They are review items; closing them from here would be the same defect class the phase was raised to fix.

| WINDOWS | Raised by | What it needs |
|---|---|---|
| **32** | 01-16 | a reviewer's blessing of the substituted `--plain-name 'workerGone'` criterion — reported, not engineered away. Not a code change. |
| **33** | 01-17 | the undiagnosed warm-up halt (one run in four). `49c5f9f` fixed the log retention so a recurrence is diagnosable; the cause itself is still unknown. |
| **34** | 01-17 | the probe asserts the daemon's own written config instead of hand-seeding one. |
| **35** | 01-18 | `kind: unrun-verify` — WR-04's acceptance is a source assertion, not a behavioural one; the SIGSEGV was not reproduced. |

Also owed to a reviewer and untouched here: **01-18 coverage D6** and **01-19 coverage D3**, both `human_judgment: true`. And **D6 of this SUMMARY** joins them — whether these five entries say the right things is editorial.

No new WINDOWS entries were filed by this plan: no stub, no skipped test, no unrun `<verify>` and no deviation arose.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **Phase 1 is fully recorded.** Everything this gap-closure set decided is in the ledger and nothing it decided is only in a commit message. G-01-15 (the `workerGone` false report) and G-01-16 (WR-03, WR-04, WR-07, WR-08) are both closed on the record; WR-05 is filed by decision; the residuals are named with owners.
- **Phase 5 inherits a ready dossier**, not a search: DW-127 carries the mechanism, the observed shutdown symptom, the explicit boundary of what was observed, the CR-01/WR-01/CR-03/WR-02 linkage, and a re-runnable oracle (`DISPLAY=:99 ./tool/uat/worker_gone_probe.sh --at <sha> --label <name>`) pointed at the exact arm it is about to change.
- **Phase 2 inherits DW-128** beside the WR-06 it already owned: same method, same requirement (SETTINGS-09 / FLAT-16), different sentence — and a note that a pass reshaping `_unavailableLines` should settle both rather than one.
- **The later WR-05 cluster inherits DW-126**: three anchors re-derived at HEAD, a fourth the review does not carry, the proposed replacement arm quoted, and an explicit statement that a human already decided not to fix this here.
- **This is the last plan of the phase.** The tree is clean and committed; both suites and the analyzer are exactly where 01-19 left them (982 dart / 2 skipped, 165 flutter / 7 skipped, clean). Phase verification can re-run `/gsd-verify-work 01` against a record that now states what was not fixed as plainly as what was.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-11*

## Self-Check: PASSED

- `.planning/phases/01-hotkey-truth/01-20-SUMMARY.md` — FOUND on disk
- `_bmad-output/implementation-artifacts/deferred-work.md` — FOUND on disk, 130 `### DW-` entries (was 125)
- `test/platform/worker-gone-observation.md` — FOUND on disk (DW-127's cited evidence exists, which its precondition required)
- Commit `e531253` (Task 1) — FOUND in `git log --oneline --all`
- Commit `693b5af` (Task 2) — FOUND in `git log --oneline --all`
- Commit `b0288aa` (this SUMMARY) — FOUND in `git log --oneline --all`
- DW-126, DW-127, DW-128 — `status: open`; DW-129, DW-130 — `status: done 2026-09-11` each with a `resolution:` beneath it
