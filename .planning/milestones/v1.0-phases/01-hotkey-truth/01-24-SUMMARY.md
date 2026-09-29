---
phase: 01-hotkey-truth
plan: 24
subsystem: testing
tags: [deferred-work, ledger, flakiness, merge-gate, gap-closure, append-only]
gap_closure: true
gap_ids: [G-01-19]
requires:
  - phase: "01-23"
    provides: "The diagnosis, the ordered D-Bus barrier, and the measured pass ratio in test/platform/merge-gate-flakiness-observation.md that this entry cites instead of asserting"
provides:
  - "DW-131 — the filed record of the intra-file half of the merge gate's nondeterminism: diagnosis, measured ratio (cited, not restated), the relationship to DW-15, and both AD-14 socket suites as open residuals with their observed frequency"
  - "A re-measured PRE-EXISTING check at this HEAD whose answer CHANGED from the verification's, with the single benign commit that changed it named"
  - "A correction of 01-VERIFICATION.md's path slip for single_instance_lock_test.dart, filed in the new entry rather than written over the report"
affects:
  - "Any later reader of deferred-work.md deciding whether the merge gate is trustworthy"
  - "Phase-1 re-verification, which now has the third missing: bullet of gaps[3] discharged"
actuals:
  tokens: 2903
  tasks: 1
  commits: 1
tech-stack:
  added: []
  patterns:
    - "A record plan cites the measurement record by path and quotes its ratio, rather than restating the numbers in its own voice — the motion DW-122 and DW-127 set for the two earlier probe records"
    - "A residual that did not reproduce in N runs is filed with the arithmetic for why N cannot distinguish 'fixed' from 'not sampled', not absorbed into the clean ratio"
key-files:
  created: []
  modified:
    - _bmad-output/implementation-artifacts/deferred-work.md
key-decisions:
  - "Severity high, not medium: the defect falsifies no product behaviour, but 'the suite is green' is the sole proof offered for several of this phase's verified truths, so a gate failing about two runs in three makes the phase's evidence layer unsound rather than merely inconveniencing a developer. The counter-argument is recorded inside the entry so a later reader can re-weigh it without reconstructing it."
  - "status: open, despite 01-23's clean 10/10 and 3/3. The diagnosis is established and the ratio is clean, but two residuals remain whose mechanism 01-23 did not touch, so the entry is not closed on an improvement."
  - "The PRE-EXISTING claim was re-run at this HEAD rather than inherited, and the answer changed: the portal suite and the fake now DO appear in git diff --name-only 52cebe8..HEAD, from exactly one commit (9eb8a47, 01-23's own fix). Recorded as a changed answer with its cause named, not glossed to preserve the original sentence."
  - "01-VERIFICATION.md gives the lock suite's path as test/architecture/single_instance_lock_test.dart; the file is at test/infrastructure/system/. Corrected in the new entry's location: and stated as a disagreement there; the report is left as written."
requirements-completed: []
coverage:
  - id: D1
    description: "DW-131 exists as one appended entry carrying origin/location/severity/reason/status in the register's field order"
    verification:
      - kind: other
        ref: "grep -c '^### DW-131:' _bmad-output/implementation-artifacts/deferred-work.md = 1; field grep over the entry = 5"
        status: pass
    human_judgment: false
  - id: D2
    description: "The entry cites the measurement record rather than asserting the ratio, and states the DW-15 relationship"
    verification:
      - kind: other
        ref: "grep -c 'merge-gate-flakiness-observation' over the entry = 2; grep -c 'DW-15' over the entry = 4"
        status: pass
    human_judgment: false
  - id: D3
    description: "Both AD-14 socket suites are named as residuals with their observed frequency and the entry is not closed on an improvement"
    verification:
      - kind: other
        ref: "grep -ciE 'single_instance_lock_test|daemon_startup_test' over the entry = 5; status: open"
        status: pass
    human_judgment: false
  - id: D4
    description: "Append-only held mechanically, measured before the commit and swept per-commit after it"
    verification:
      - kind: other
        ref: "git diff --numstat on the ledger before commit = 15 additions / 0 deletions; per-commit sweep of 52cebe8..HEAD found zero ledger deletions in every commit; range total 58 0"
        status: pass
    human_judgment: false
  - id: D5
    description: "No code, no executed plan, no SUMMARY and no verification report was edited"
    verification:
      - kind: other
        ref: "git diff --numstat -- lib/ test/ tool/ dart_test.yaml | wc -l = 0; same over 01-VERIFICATION.md and every 01-0*/01-1*/01-20-* file = 0; over the four frozen port declarations = 0"
        status: pass
    human_judgment: false
  - id: D6
    description: "The entry keeps measured evidence in a different voice from reasoned inference, in DW-124's register"
    verification: []
    human_judgment: true
    rationale: "Whether the four kinds of evidence actually read as distinct to a later reader is a judgment about prose, not a predicate a command can evaluate. The mechanical gates prove the entry names the right things; they cannot prove it distinguishes them well."
duration: 5 min
completed: 2026-09-14
status: complete
---

# Phase 01 Plan 24: DW-131 — The Intra-File Half of the Merge Gate's Nondeterminism, Filed Summary

**The half of the suite's flakiness that `dart_test.yaml`'s DW-15 citation does not cover now has a ledger entry that cites 01-23's measured ratio instead of asserting a condition, names both AD-14 socket suites as residuals with the arithmetic showing ten clean runs cannot prove them fixed, and stays `open` rather than closing on an improvement.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-09-14T18:22:20Z
- **Completed:** 2026-09-14T18:27:03Z
- **Tasks:** 1 of 1
- **Files modified:** 1

## Accomplishments

### Task 1 — DW-131 appended (`26eebcd`)

One entry, 15 added lines, zero deletions, at the end of
`_bmad-output/implementation-artifacts/deferred-work.md`, in the field order
DW-126 … DW-130 use (`origin:`, `location:`, `severity:`, `reason:`, `status:`).

**Severity: high.** The justifying sentence, as written in the entry: the defect
falsifies no product behaviour — it is a test-harness defect that 01-23 has now
measured and, on the half it reached, apparently closed — but *"the suite is
green" is the sole proof offered for several of this phase's verified truths, so
a gate that fails about two runs in three does not merely inconvenience a
developer, it makes the phase's evidence layer unsound*. A defect in the
instrument that measures everything else outranks a defect in any one thing it
measured. The medium reading is recorded inside the entry rather than suppressed,
so a later reader can disagree with the weighting without reconstructing it.

**Status: `open`.** This is the part of the plan that mattered most and it is
worth being exact about, because the tempting answer was the wrong one.
**01-23's ratio WAS clean** — 10 PASS / 0 FAIL over ten serial runs of the
binding-free half (982 passed / 2 skipped each time) and 3 PASS / 0 FAIL over
three of the Flutter-bound half (165 / 7). The diagnosis is established, by
instrumentation rather than argument (2–3 event-loop turns to delivery idle
versus **255** under full contention, against `_settle()`'s budget of 50). Two of
the plan's three closing conditions are therefore met. The third is not, and that
is why the entry stays open:

1. `test/infrastructure/system/single_instance_lock_test.dart:60` — "AD-14:
   release frees the address for the very lock that held it" — observed failing
   **once in the verification's seven full-suite runs (≈1/7)**.
2. `test/infrastructure/system/daemon_startup_test.dart:304` — "AD-14, CAP-1: the
   holder receives exactly one show request" — likewise **once in seven (≈1/7)**.

Neither failed in any of 01-23's ten runs, and that is not evidence either is
fixed. Their mechanism is DW-15's one-abstract-socket-bind-per-process hazard,
which 01-23's change does not touch at all — that change is entirely inside the
portal fake's emit path, and `git log --oneline 52cebe8..HEAD` over both AD-14
files is empty. And the arithmetic forbids the comfortable reading: at p = 1/7
per run, the chance of seeing zero failures in ten runs is about **0.21**, so a
clean ten is an unremarkable outcome for a defect that is exactly as present as
it was. Ten runs cannot distinguish "fixed" from "not sampled" at that rate.
Closing DW-131 on the 10/10 would have been the same reasoning error — a sample
read as a measurement — that the entry exists to record.

**Append-only, measured before the commit rather than asserted after it.**
`git diff --numstat` on the ledger with the entry written and nothing staged:

```
15	0	_bmad-output/implementation-artifacts/deferred-work.md
```

Non-zero additions, zero deletions. **Per-commit sweep** (the stricter form
01-VERIFICATION.md's `gaps_closed` records for the previous set, rather than
checking only the range endpoints): every commit in `52cebe8..HEAD` was walked
individually and **none has a non-zero deletions column for the ledger file**.
Range total `58 0` — 43 from the earlier closure set plus this plan's 15.

**Two things the entry records that the plan could not have known to ask for.**

- **The PRE-EXISTING claim's answer changed, and the entry says so.** The plan
  asked for the check to be re-run at this HEAD "so the claim is measured in this
  run rather than inherited". It was, and it no longer returns what
  01-VERIFICATION.md recorded. Re-run against the verification's own range
  (`52cebe8..307f7f2`) it still returns nothing, as that report said. Re-run at
  this HEAD, `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart`
  and `test/support/fake_global_shortcuts_portal.dart` now **do** appear — from
  exactly one commit, `9eb8a47`, which is 01-23's own barrier change, the fix for
  this very entry. Both AD-14 socket suites and `dart_test.yaml` remain untouched
  in range. So the defect still was not introduced by the gap-closure set, but
  the sentence that proved it no longer proves it unaided, and the entry carries
  the longer form rather than the stale short one.
- **A path slip in 01-VERIFICATION.md, corrected in the new entry and not in the
  report.** `gaps[3].artifacts` gives the lock suite as
  `test/architecture/single_instance_lock_test.dart`; the file is at
  `test/infrastructure/system/single_instance_lock_test.dart` and no file exists
  at the former path. The verification's row is otherwise exact (file, row title,
  frequency), so it is a path slip and not a different file. Corrected in
  DW-131's `location:`, stated there as a disagreement, and the report left
  standing — the motion DW-129 made for plan 01-03's truth and DW-123 made for
  DW-9/26/44.

## Task Commits

1. **Task 1: DW-131 — the intra-file half, filed with its diagnosis and its measured ratio** — `26eebcd` (docs)

**Plan metadata:** see the `docs(01-24): complete …` commit following this summary.

## Files Created/Modified

- `_bmad-output/implementation-artifacts/deferred-work.md` — one appended entry,
  DW-131, at the end of the file. Nothing else in the file was touched.

## Decisions Made

- **Severity high over medium**, on reach rather than on blast radius, with the
  rejected reading written into the entry.
- **`status: open` despite a clean ratio**, because a residual remains whose
  mechanism the fix does not touch and whose rate ten runs cannot resolve.
- **The changed PRE-EXISTING answer recorded as changed**, with the single benign
  commit named, rather than quietly restated in the form that used to be true.
- **The verification's path slip corrected in the new entry only.** Both texts
  survive.
- **Line anchors re-derived at this HEAD with `/usr/bin/grep`**, not with the
  shell's ugrep shadow, and the entry says which grep produced its numbers so a
  later re-derivation lands on the same figures.

## Deviations from Plan

None — plan executed exactly as written. Two findings surfaced during the write
(the changed PRE-EXISTING answer and the path slip) and both were handled the way
the plan's own prohibition directs: *"If writing the entry surfaces something that
looks like it needs a code change, that is a finding for the entry to carry, not
an edit for this plan to make."* Neither produced an edit outside the ledger.

**Total deviations:** 0.
**Impact on plan:** none.

## Issues Encountered

None. Every gate passed on the first run:

| Gate | Result |
|---|---|
| `grep -c '^### DW-131:'` | `1` |
| Five required fields present | `5` |
| Cites `merge-gate-flakiness-observation` | `2` |
| Names `DW-15` | `4` |
| Names both AD-14 socket suites | `5` |
| Ledger `git diff --numstat` | `15  0` |
| `git diff --numstat -- lib/ test/ tool/ dart_test.yaml \| wc -l` | `0` |
| Same over `01-VERIFICATION.md` and every `01-0*`/`01-1*`/`01-20-*` | `0` |
| Same over the four frozen port declarations | `0` |
| Per-commit ledger deletion sweep, `52cebe8..HEAD` | zero deletions in every commit |

No test suite was run by this plan and none is claimed. The merge gate's ratio is
01-23's deliverable and lives in
`test/platform/merge-gate-flakiness-observation.md`; repeating a single run here
and calling it green would be the exact error this entry is written about.

## User Setup Required

None.

## Next Phase Readiness

`01-VERIFICATION.md` `gaps[3]`'s third `missing:` bullet is discharged: the
residual intra-file half is filed where before it was unfiled. With this plan all
four `status: failed` gaps in that report have closure plans — `gaps[0]` and
`gaps[1]` → 01-21, `gaps[2]` → 01-22, `gaps[3]` → 01-23 (diagnosis and ratio) and
01-24 (the ledger entry). Phase 1 is ready for re-verification.

**Carried open, deliberately:** DW-131 itself. The two AD-14 abstract-socket
suites at ≈1/7 are unresolved and unsampled, not fixed, and the entry stays
`open` until somebody runs enough of the gate to tell the difference — the
observation record's §5 notes that anything failing at under roughly one run in
ten is invisible to a ten-run sample by construction, and that none of these
numbers say anything about GitHub Actions, where `ci.yml` has still never
executed.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-14*

## Self-Check: PASSED

- `_bmad-output/implementation-artifacts/deferred-work.md` present on disk, DW-131 heading count `1`.
- `.planning/phases/01-hotkey-truth/01-24-SUMMARY.md` present on disk.
- Commits `26eebcd` (ledger entry) and `48a7d71` (plan metadata) both present in `git log --oneline --all`.
- `git diff --numstat 50ea0ed..HEAD -- lib/ test/ tool/ dart_test.yaml` — 0 lines.
- `git diff --numstat 50ea0ed..HEAD` over `01-VERIFICATION.md` and every `01-0*`/`01-1*`/`01-20-*` file — 0 lines.
