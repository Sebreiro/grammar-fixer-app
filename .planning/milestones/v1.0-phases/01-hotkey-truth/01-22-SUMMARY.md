---
phase: 01-hotkey-truth
plan: 22
subsystem: ui
tags: [hotkey, capture-validator, doc-comment, gap-closure, sweep-completeness]

# Dependency graph
requires:
  - phase: 01-hotkey-truth
    provides: "plan 01-19's deletion of `HotkeyCaptureRefusal.noPortalTrigger`, which took the enum from five values to four and left one prose site behind (DW-130)"
  - phase: 01-hotkey-truth
    provides: "plan 01-07's `HotkeyCaptureValidator` and `RegistrableKey.forUsage`, the mechanism HOTKEY-04 asks for and the sibling doc that already carried the correct count"
provides:
  - "`HotkeyCaptureField.validator`'s doc states the refusal-subject count the enum actually has, so the three sites that carry it (the field doc, `forUsage`'s doc, `HotkeyCaptureRefusal` itself) can no longer be read against each other and disagree"
  - "A recorded, reproducible completeness sweep for the retired count — both patterns, both pre-edit and post-edit outputs, and the reason DW-130's pattern returned a true zero that supported a false conclusion"
affects: [01-23, 01-24, phase-01 re-verification, any future refusal-subject change]

actuals:
  tokens: 5341
  tasks: 1
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A completeness sweep is recorded with the pattern that produced it, and the pattern is shown to match the pre-fix site before the fix lands"

key-files:
  created: []
  modified:
    - lib/src/ui/settings/hotkey_capture_field.dart

key-decisions:
  - "Ran both sweeps under `/usr/bin/grep` (GNU grep 3.11) rather than the harness `grep` shell function (ugrep 7.8.4), and recorded both, so the zero is not an artefact of the matcher — the same defect class DW-130 fell into"
  - "Left `hotkey_capture_field.dart:51` (\"Read for two things\") and `:471-481` (the AltGr paragraph's \"exactly four values\") untouched: the first counts what the `authority` field is read for, the second counts `HotkeyModifier` values — neither counts refusal subjects"
  - "Recorded the retired wording only here and in git, never in `lib/` or `test/`, because a \"was previously five\" note would re-create the exact string the post-edit sweep must not find"

patterns-established:
  - "Sweep proof obligation: quote the pattern, run it before and after, and demonstrate it matches the pre-fix site — a pattern that cannot match the miss is not a proof of completeness"

requirements-completed: [HOTKEY-04]

coverage:
  - id: D1
    description: "`HotkeyCaptureField.validator`'s doc comment names four refusal subjects, matching `HotkeyCaptureRefusal`'s four values and `RegistrableKey.forUsage`'s sibling sentence"
    requirement: "HOTKEY-04"
    verification:
      - kind: other
        ref: "grep -c 'four-subject' lib/src/ui/settings/hotkey_capture_field.dart == 1"
        status: pass
      - kind: other
        ref: "sed -n '/^enum HotkeyCaptureRefusal {/,/^}/p' lib/src/application/hotkey_capture.dart | grep -cE '^  [a-z][A-Za-z]*,$' == 4"
        status: pass
      - kind: other
        ref: "dart analyze --fatal-infos == No issues found!"
        status: pass
    human_judgment: false
  - id: D2
    description: "No prose site in `lib/` or `test/` still counts five refusal subjects, proved by a sweep that matched the surviving site before the edit"
    requirement: "HOTKEY-04"
    verification:
      - kind: other
        ref: "/usr/bin/grep -rn 'five-subject\\|five subject' lib/ test/ — 1 before, 0 after"
        status: pass
      - kind: other
        ref: "/usr/bin/grep -rniE 'five[- ](subject|subjects|thing|things)|the fifth (subject|thing)' lib/ test/ — 1 before, 0 after"
        status: pass
    human_judgment: false
  - id: D3
    description: "Nothing but the one sentence moved — the enum, the validator, the ordered refusal chain, the verdict function, the four frozen port declarations and every test are byte-identical"
    requirement: "HOTKEY-04"
    verification:
      - kind: other
        ref: "git diff --numstat over hotkey_capture.dart, registrable_keys.dart, hotkey_key_catalogue.dart, global_hotkey.dart, hotkey_binding.dart, hotkey_bind_outcome.dart, panel_visibility.dart == empty; git diff --name-only -- lib/ test/ == one file"
        status: pass
      - kind: automated_ui
        ref: "flutter test --exclude-tags=live test/ui/settings — 46 passed"
        status: pass
    human_judgment: false

# Metrics
duration: 5min
completed: 2026-09-14
status: complete
---

# Phase 01 Plan 22: Capture-Validator Refusal Count Summary

**One doc comment in `hotkey_capture_field.dart` stopped claiming a fifth capture-refusal subject that plan 01-19 deleted, and the completeness sweep 01-19 only asserted is now recorded with a pattern proven to match the site it missed.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-09-14T17:45:52Z
- **Completed:** 2026-09-14T17:51:30Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- `lib/src/ui/settings/hotkey_capture_field.dart:61` now reads "The four-subject capture validator", agreeing with `HotkeyCaptureRefusal`'s four values (counted from source in this run: `levelThreeModifier`, `modifierOnly`, `noModifier`, `keyNotRegistrable`) and with `registrable_keys.dart:36`'s "one of the four subjects".
- Both completeness sweeps were run **before** the edit — the narrow one returning exactly the one hit `01-VERIFICATION.md gaps[2]` names, the broad one returning the same hit — and **after** the edit, both returning zero. The claim of completeness now rests on a measurement that would have failed an hour ago.
- The diagnosis of DW-130's false conclusion is recorded below, so the next person to retire a count knows which shape of pattern to use.
- Scope held: exactly one file changed in `lib/`+`test/`; the enum, the vocabulary type, the catalogue, the four verbatim-fixed port declarations and every test are byte-identical.

## The sweeps

### Pattern A — the narrow sweep `01-VERIFICATION.md gaps[2].missing` names verbatim

```
grep -rn 'five-subject\|five subject' lib/ test/
```

**Before the edit (1 hit):**

```
lib/src/ui/settings/hotkey_capture_field.dart:61:  /// The five-subject capture validator, supplied by `SettingsController`
```

**After the edit (0 hits):** `… | wc -l` → `0`

### Pattern B — the broader sweep, the one that would have caught 01-19's miss

```
grep -rniE 'five[- ](subject|subjects|thing|things)|the fifth (subject|thing)' lib/ test/
```

**Before the edit (1 hit):**

```
lib/src/ui/settings/hotkey_capture_field.dart:61:  /// The five-subject capture validator, supplied by `SettingsController`
```

**After the edit (0 hits):** `… | wc -l` → `0`

### Why the pattern DW-130 records could not match the surviving site

DW-130's `resolution:` proves its sweep complete with

```
grep -rniE 'five (subjects|things)|the fifth thing' lib/ test/
```

which requires the count word to be followed by a **space** and a **plural** noun — and the surviving site is the hyphenated, singular compound `five-subject`, so the pattern missed it on both counts at once; the zero it returned was a true measurement of a question that was not the one being asked. Run against the pre-edit tree in this session it still returns `0`, while Pattern B returns the hit — which is the whole demonstration.

### Which `grep` produced these numbers

The harness shell aliases `grep` to a shell function backed by **ugrep 7.8.4**, which differs from GNU grep on regex-metacharacter handling. Every number above was produced by **`/usr/bin/grep` (GNU grep 3.11)** invoked by absolute path. For completeness both sweeps were also run through the harness `grep`: identical results (1 before, 0 after, both patterns). Neither pattern contains a `$` anchor, which is where the two matchers are known to diverge here, so the agreement is expected rather than lucky — but it was measured rather than assumed, because assuming it is the exact move that produced this gap.

## Task Commits

1. **Task 1: the count in the prose is the count in the enum, and the sweep that says so is run** — `0772562` (docs)

**Plan metadata:** see the final `docs(01-22)` commit.

## Files Created/Modified

- `lib/src/ui/settings/hotkey_capture_field.dart` — the `validator` field doc's opening compound changed from `five-subject` to `four-subject`. The `(DW-71)` citation and the two AD-1 sentences explaining why the validator is injected rather than reached for are unchanged; they were correct and are not what this gap was about.

## Verification Results

| Check | Result |
|---|---|
| `dart analyze --fatal-infos` | `No issues found!` |
| Pattern A over `lib/ test/` | `0` |
| Pattern B over `lib/ test/` | `0` |
| `grep -c 'four-subject' hotkey_capture_field.dart` | `1` |
| `HotkeyCaptureRefusal` value count, measured this run | `4` |
| `git diff --numstat` over `hotkey_capture.dart`, `registrable_keys.dart`, `hotkey_key_catalogue.dart` | empty |
| `git diff --numstat` over the four frozen port declarations | empty |
| `git diff --numstat` over `01-0*`, `01-1*`, `01-20-*` plans and SUMMARYs | empty |
| `flutter test --exclude-tags=live test/ui/settings` | `+46: All tests passed!` |

The full binding-free merge gate is deliberately **not** asserted here. This plan changes one doc comment and cannot affect it; `01-VERIFICATION.md gaps[3]` measured that ratio at 2 PASS / 5 FAIL over 7 runs and plan 01-23 owns it.

## Additional scan of the same file

Beyond `:61`, the file was scanned for any other sentence counting refusal subjects. Two count-bearing lines exist and neither is in scope:

- `:51` — "Read for two things: the label above, and whether the standing hint …" counts what the `authority` field is read for, not refusals.
- `:471-481` — the AltGr paragraph's "`HotkeyModifier` has exactly four values and none of them is Level 3" counts modifiers; it is already correct (`hotkey_binding.dart` declares four) and plan 01-19 rewrote it deliberately.

## Decisions Made

1. **Both sweeps run under `/usr/bin/grep`, and the matcher named.** A completeness zero produced by a matcher whose regex semantics were not checked is the same class of evidence DW-130 offered. Naming the binary and its version makes the measurement reproducible.
2. **Pattern B is broader than the defect.** It covers the spaced form, the hyphenated form, singular and plural, and the ordinal — so it also catches the shapes a future retirement is likely to leave behind, not only the one that survived this time.
3. **No trace of the retired wording in source.** The old sentence lives in this SUMMARY and in `0772562`'s diff. A `// was: five-subject` note would re-create the exact string Pattern A must not find and turn the gate into something that fails on its own explanation.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. The one environment fact worth carrying forward (the `grep`/ugrep shadowing, flagged by the executor of sibling plan 01-21) did not bite: neither sweep pattern uses `$` or any other construct where the two matchers diverge, and both were run under GNU grep regardless.

## Gap Closure

`G-01-18` = `01-VERIFICATION.md gaps[2]`, both `missing:` bullets satisfied:

- *"`:61` reads four"* → `grep -c 'four-subject'` on that file returns `1`; `git diff` shows the single-word change.
- *"the sweep the truth claims returns zero"* → Pattern A returns `0` after the edit, having returned exactly `1` before it.

01-REVIEW.md **WR-03** is closed by the same change and is the independent report the verification cites.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

01-19's must-have truth 4 now holds as written. Remaining phase-01 gap-closure work is unaffected: plan 01-23 owns the merge-gate flake ratio (`gaps[3]`) and plan 01-24 owns the edge-probe register. Nothing in this plan touches either.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-14*

## Self-Check: PASSED

- `lib/src/ui/settings/hotkey_capture_field.dart` — FOUND
- `.planning/phases/01-hotkey-truth/01-22-SUMMARY.md` — FOUND
- Commit `0772562` — FOUND in `git log`
- Post-write re-run of Pattern A over `lib/ test/` — `0` (this SUMMARY lives outside both trees, so quoting the retired wording here does not re-arm the gate)
