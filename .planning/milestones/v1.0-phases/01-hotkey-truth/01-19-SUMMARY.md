---
phase: 01-hotkey-truth
plan: 19
subsystem: hotkey
tags: [dart, flutter, x11, wayland, xdg-portal, dead-code-removal, altgr]

requires:
  - phase: 01-16
    provides: the X11 seam-refused arm that turns 01-15's fail-first row green, so this plan's broad-suite gate is not red for a reason that is not its own
  - phase: 01-17
    provides: a clean `git status --porcelain -uno -- lib/ test/ tool/` at the probe's before/after boundary, which this plan's six-file diff would otherwise have broken
provides:
  - A capture validator whose four refusal subjects are each reachable by input a user can produce — the always-false portal-trigger predicate, the fifth enum value and its user-facing sentence are gone
  - The vocabulary-divergence invariant re-homed to a build-time assertion over `HotkeyKeyCatalogue.registrableKeys()`, carrying in its `reason:` the record of what the deletion traded away
  - Two AltGr comments that state a measured fact at the fidelity it was measured at, replacing a flag that told the next reader to treat settled work as open
affects: [hotkey capture, settings screen, XDG portal serialization, Phase 7 ARCH-06 reconciliation]

actuals:
  tokens: 3185
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A guard strictly dominated by existing build-time assertions is deleted, not retained behind a new one — and the deleted guard's rationale moves into the surviving assertion's `reason:` string rather than being lost"
    - "An unused-import question is settled by running the analyzer with the doc link stripped, not by reading the source and guessing"

key-files:
  created: []
  modified:
    - lib/src/domain/hotkey/registrable_keys.dart
    - lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart
    - lib/src/application/hotkey_capture.dart
    - lib/src/ui/settings/hotkey_capture_field.dart
    - test/infrastructure/hotkey/hotkey_key_catalogue_test.dart
    - test/architecture/hotkey_confinement_test.dart

key-decisions:
  - "WR-08 closed by reviewer option (a) — delete the field, the enum value and the branch — not option (b), keep the branch behind a new assertion. Decided on a measurement: `registrableKeys()` prints `total=63 withoutPortalTrigger=0 missing=[]`, and the divergence the guard existed to catch is already asserted three times in both directions at build time."
  - "The deleted guard's reasoning is preserved in two places rather than dropped: the replacement assertion's `reason:` string in `hotkey_key_catalogue_test.dart`, and a doc paragraph on `registrableKeys()` re-pointing the one-vocabulary invariant at the tests that now carry it."
  - "The `xdg_shortcut_trigger.dart` import in `hotkey_key_catalogue.dart` STAYS. Measured, not assumed: the `[XdgShortcutTrigger]` doc link at `:186` is the sole remaining reference, and stripping it to backticks makes `dart analyze` report `unused_import` (exit 2)."
  - "The AltGr comments cite XTEST observation and explicitly do NOT claim a physical keyboard, matching UAT test 9's own `fidelity:` retraction of the physical-keyboard framing."

patterns-established:
  - "Pre-deletion gate: before removing a guard, run the assertions that are claimed to dominate it and show them green — the deletion's safety is a measurement taken before the fact, not a claim made after"
  - "A `reason:` string is where a removed branch's rationale goes, so the trade-off is read by whoever next sees the assertion fail"

requirements-completed: [HOTKEY-04]

coverage:
  - id: D1
    description: "The capture validator has exactly four refusal subjects, each reachable — the always-false portal-trigger branch, its enum value and its user-facing sentence are deleted with no orphaned switch arm or dead string"
    requirement: "HOTKEY-04"
    verification:
      - kind: other
        ref: "grep -rn 'hasPortalTrigger\\|noPortalTrigger' lib/ test/ | wc -l => 0"
        status: pass
      - kind: unit
        ref: "dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart => 982 passed / 2 skipped"
        status: pass
      - kind: other
        ref: "dart analyze --fatal-infos => No issues found!"
        status: pass
    human_judgment: false
  - id: D2
    description: "The divergence the deleted guard stood for is asserted at build time over the real injected vocabulary, with a reason naming what the deletion cost and where the reverse direction lives"
    requirement: "HOTKEY-04"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/hotkey_key_catalogue_test.dart#the injected vocabulary (registrableKeys) — withoutKeysymName isEmpty"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/xdg_shortcut_trigger_test.dart#parity with the X11 catalogue (AD-9) => 13 passed"
        status: pass
    human_judgment: false
  - id: D3
    description: "Both AltGr comments state what UAT test 9 and the 01-07 run measured, at the fidelity measured, without re-importing the physical-keyboard overstatement — and nothing executable changed in either file"
    verification:
      - kind: other
        ref: "grep -rn 'not verified in this session' lib/ | wc -l => 0"
        status: pass
      - kind: other
        ref: "git diff -U0 over the two AltGr files at Task 2's commit => 0 non-comment lines"
        status: pass
      - kind: integration
        ref: "flutter test test/ui test/platform test/composition => 165 passed / 7 skipped (settings_screen_hotkey_test.dart AltGr row green)"
        status: pass
    human_judgment: true
    rationale: "Whether the replacement prose over-claims or under-claims is an editorial judgment no grep settles. The greps prove the stale flag is gone, the citation is present and nothing executable moved; they cannot prove the new sentences are the right sentences. A reviewer should read both blocks against UAT test 9's `fidelity:` note."
  - id: D4
    description: "No frozen port declaration moved"
    verification:
      - kind: other
        ref: "git diff --numstat 594e126 HEAD -- global_hotkey.dart hotkey_binding.dart hotkey_bind_outcome.dart panel_visibility.dart => 0 lines"
        status: pass
    human_judgment: false

duration: 20 min
completed: 2026-09-11
status: complete
---

# Phase 01 Plan 19: Capture-path record defects (WR-07, WR-08) Summary

**Deleted an always-false portal-trigger refusal — a field, an enum value, a branch and a user-facing sentence no input could reach — and re-homed the invariant it stood for into a build-time assertion over the real injected vocabulary; then replaced both AltGr "not verified" flags with what was actually measured.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-09-11T13:51:00Z
- **Completed:** 2026-09-11T14:11:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- **WR-08 closed by deletion.** `RegistrableKey.hasPortalTrigger`, `HotkeyCaptureRefusal.noPortalTrigger`, the `if (!key.hasPortalTrigger)` branch and its refusal sentence are gone. `HotkeyCaptureRefusal` now has exactly four values and the validator's refusal chain keeps its previous order minus the one removed link.
- **The guard moved to where it has teeth.** The per-key flag loop in `hotkey_key_catalogue_test.dart` was **replaced**, not deleted, by a collected-list assertion over `HotkeyKeyCatalogue.registrableKeys().all` — a failure now names *which* labels diverged, not only the first.
- **WR-07 closed.** Both AltGr comments state the predicate, why it is the logical `altGraph` rather than the physical `altRight`, what was observed and where, and what pins it — without claiming a physical keyboard.
- **Suites unchanged and green:** 982 dart passed / 2 skipped, 165 flutter passed / 7 skipped, `dart analyze --fatal-infos` clean. No net change to test-row count (a row was rewritten, not added).

## Task Commits

1. **Task 1 (tracer): WR-08 — delete the unreachable refusal, move its guard** — `de50896` (refactor)
2. **Task 2: WR-07 — the AltGr comments say what was measured** — `5ed401c` (docs)

## The pre-deletion gate (run BEFORE anything was removed)

The plan's whole case for deletion is that three existing assertions already dominate the guard. That was verified first, as a measurement rather than a reading:

| Assertion | Where | Result |
|---|---|---|
| every `HotkeyKeyCatalogue.labels` entry resolves to a keysym name | `xdg_shortcut_trigger_test.dart`, `parity with the X11 catalogue (AD-9)` | **green** (4 rows in group) |
| the reverse direction, plus `XdgShortcutTrigger.labels == HotkeyKeyCatalogue.labels` (same order) | same group | **green** |
| the flag asserted true on every key of `registrableKeys()` | `hotkey_key_catalogue_test.dart` | **green** (13 rows in file) |

And the predicate itself was measured always-false by running the real catalogue:

```
total=63 withoutPortalTrigger=0 missing=[]
```

This reproduces 01-VERIFICATION.md's number independently. Had any of the three been absent or red, the deletion would have been halted and reported — the guard was only safe to remove because the guarding was already being done elsewhere.

## WR-08: which option was taken, and why

**Option (a) — delete the field, the enum value and the branch.** Not option (b), keep the branch behind a new assertion.

The reason is a measurement, not a preference. The flag was `XdgShortcutTrigger.keysymNameFor(label) != null`, and the two vocabularies are identical by construction (26 letters, 10 digits, F1–F12, and the same 15 named keys in `HotkeyKeyCatalogue._namedKeys` and `XdgShortcutTrigger._namedKeysymNames`), so the flag was true for all 63 keys and the branch was unreachable. A guard strictly dominated by three existing build-time assertions is not a safety net — it is dead code with extra steps.

The two failure modes are also not equivalent, which is what settles the fork: a divergence caught by a test stops the build in front of the developer who caused it, while a divergence caught by the deleted branch reached a *user* as a sentence about a key they had just pressed. Deleting lost nothing, because the guarding was never being done by the field.

This is the same motion plan 01-07's own `resolution:` recorded for `labelsThatBindTheWrongKey` — *"an always-false predicate leaves branches that can never run, which AGENTS.md §1 rules out"* — so the phase now applies its own standard to its own code instead of contradicting it.

## Every site the deletion touched, and the grep that proves none was missed

| Site | What was done |
|---|---|
| `registrable_keys.dart` ctor | `required this.hasPortalTrigger` parameter removed |
| `registrable_keys.dart` field + doc | field and its 12-line doc removed |
| `registrable_keys.dart:36` | "one of the **five** subjects" → "one of the **four** subjects" |
| `registrable_keys.dart` class doc | third clause (whether the portal can be told about the key) removed; replaced by a note recording that the clause existed, why it went, and where the invariant is asserted now |
| `hotkey_key_catalogue.dart:193` | `hasPortalTrigger:` argument removed |
| `hotkey_key_catalogue.dart:185` doc | portal-half clause re-pointed, **not** dropped — it now names `hotkey_key_catalogue_test.dart` and `xdg_shortcut_trigger_test.dart`'s parity group as what carries the one-vocabulary invariant |
| `hotkey_capture.dart:66-68` | `noPortalTrigger` enum value and doc removed |
| `hotkey_capture.dart:154-162` | branch, `HotkeyCaptureRefused` and user-facing sentence removed |
| `hotkey_key_catalogue_test.dart:192-201` | loop **replaced** by the collected-list assertion (see below) |
| `hotkey_confinement_test.dart:354` | "which of the **five** things went wrong" → "**four**" |

Proof that the sweep was complete:

```
grep -rn 'hasPortalTrigger\|noPortalTrigger' lib/ test/ | wc -l      => 0
grep -rniE 'five (subjects|things)|the fifth thing' lib/ test/ | wc -l => 0
```

The plan's `<interfaces>` table listed exactly these ten sites and the greps confirm it was complete at HEAD — no eleventh site was found.

## The replacement row's `reason:` string, quoted

Recorded here so the trade-off survives where a later reader will find it:

> this assertion IS the guard that used to be a capture-time refusal. Plan 01-19 deleted the portal-trigger flag on RegistrableKey and the fifth HotkeyCaptureRefusal value that read it, because the flag was true for every key the catalogue can produce, so that refusal could never fire. The invariant it stood for is real, and it is checked here instead — against registrableKeys(), the vocabulary the composition root actually injects — so a divergence fails the build in front of the developer who caused it rather than reaching a user as a sentence about a key they just pressed. The reverse direction (a label this table lacks) and the same-order claim are asserted by xdg_shortcut_trigger_test.dart's 'parity with the X11 catalogue (AD-9)' group

Note the wording deliberately avoids spelling the removed identifiers, because the plan's own acceptance criterion requires `grep -rn 'hasPortalTrigger\|noPortalTrigger' lib/ test/` to return **0** — a first draft named them verbatim and tripped that gate. It says "the portal-trigger flag on RegistrableKey" and "the fifth HotkeyCaptureRefusal value" instead, which names the deletion without reintroducing the token.

The assertion collects a list and expects it empty, rather than looping with a per-key `expect`, so a failure names *which* labels diverged instead of only the first. It runs against `HotkeyKeyCatalogue.registrableKeys()` — the vocabulary the composition root actually injects — never a hand-built `RegistrableKey`, which is this plan's second prohibition.

## What the analyzer decided about the `xdg_shortcut_trigger.dart` import

**It stays.** And this was measured rather than inferred, because the plan explicitly said not to guess.

After removing the one executable use, `dart analyze --fatal-infos` was clean — but a clean analyzer does not by itself prove the import is *needed*; it could mean the project does not flag unused imports at all. So the question was settled by experiment: the `[XdgShortcutTrigger]` doc link at `:186` was temporarily rewritten to plain backticks and the analyzer re-run on that file alone.

```
warning - hotkey_key_catalogue.dart:3:8 - Unused import: 'xdg_shortcut_trigger.dart'.
          Try removing the import directive. - unused_import
1 issue found.  exit=2
```

The file was then restored from a scratchpad backup (never `git checkout --`). This proves both halves: the analyzer *does* catch an unused import here, and the `///` doc link at `:186` is the sole thing keeping this one alive — exactly the case `<interfaces>` predicted. The two backtick mentions at `:58` and `:193` do **not** hold it; only the square-bracket link does.

## WR-07: what the comments now say

Both sites previously ended with a bracketed note saying the GTK-embedder mapping of AltGr was "not verified in this session". That half was false. Each replacement now states three things and no more:

1. **The predicate and why it is the logical key** — `altGraph`, not `altRight`: on a layout mapping Level 3 to the right Alt key the embedder reports `altGraph`, and on one that does not the same physical key reports an ordinary `altRight`, so keying on the physical key would refuse a legitimate `Alt` combination on a US layout. This reasoning survives whole.
2. **What was observed, and where** — the 01-07 run (2026-09-02) that settled assumption A3, and UAT test 9 (2026-09-04) on an `altgr-intl` layout where AltGr and AltGr+E each rendered the Level 3 refusal and the stored shortcut was not folded into Alt.
3. **What pins it now** — `settings_screen_hotkey_test.dart`'s AltGr row.

Two things deliberately avoided, both about not over-claiming in the other direction:

- **No physical-keyboard claim.** Every press in both observations was XTEST. Both comments say so and say why it is sufficient rather than a caveat — the predicate reads a GTK/Flutter keymap translation that cannot distinguish an injected event from a switch closing. This matches UAT test 9's own `fidelity:` note, which retracts the physical-keyboard framing as an overstatement of what the claim needs.
- **The consequence clause survives** in both: `HotkeyModifier` has four values and none is Level 3, which is why a refusal is right rather than a fold.

The two blocks were adapted to their sites' voices rather than pasted twice — the application-ring doc documents a *field on a value type*, the ui-ring doc documents the *predicate that computes it* and keeps its longer folding-is-worse argument untouched.

## Tracer feedback gate

Task 1 was `type="tracer"`. Gate evaluated per the precedence chain: the task carries no `gate="blocking-human"` (row 1 no), auto mode is off — `auto_advance: false`, `_auto_chain_active: false` (row 2 no), the run is interactive with `human_verify_mode: end-of-phase` and the tracer's `<verify>` carries only `<automated>` blocks with no `<human-check>` (row 3 **yes**). All six verify commands were therefore re-run end-to-end after the Task 1 commit; all passed, so execution continued to the expansion task with no checkpoint. Had any failed, expansion would have been halted rather than layered onto a broken slice.

## Verification Results

| # | Check | Result |
|---|---|---|
| 1 | `dart analyze --fatal-infos` | **No issues found!** |
| 2 | `grep -rn 'hasPortalTrigger\|noPortalTrigger' lib/ test/` | **0** |
| 3 | `grep -rn 'not verified in this session' lib/` | **0** |
| 4 | `grep -rniE 'five (subjects\|things)\|the fifth thing' lib/ test/` | **0** |
| 5 | `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **982 passed / 2 skipped** |
| 6 | `flutter test test/ui test/platform test/composition` | **165 passed / 7 skipped** |
| 7 | `git diff --numstat` over the four frozen port declarations | **0 lines** |
| 8 | `git diff -U0` over the two AltGr files (Task 2's diff) | **0 non-comment lines** |

On check 8, stated precisely rather than smoothed: measured against the plan base `594e126`, the two-file span shows **10** non-comment lines. All ten are pure deletions in `hotkey_capture.dart` from **Task 1** (the enum value and the branch) — zero additions, and nothing from Task 2. The gate belongs to Task 2 and was **0** when measured at Task 2's commit, and `hotkey_capture_field.dart` alone is **0** even against the plan base. The full deletion list is printed in the execution log.

Suite counts match the pre-existing baseline exactly (982/2 and 165/7), so nothing regressed and no test row was added or lost — the catalogue row was rewritten in place.

## Decisions Made

- **WR-08 → option (a), deletion.** Reasoned from the `total=63 withoutPortalTrigger=0 missing=[]` measurement and the three dominating assertions, not from preference. Recorded in the plan objective, the commit message and here, so a future reversal knows what it is reversing.
- **The deleted guard's rationale is preserved in two places**, not dropped: the replacement assertion's `reason:` string, and a re-pointed doc paragraph on `registrableKeys()`. The one-vocabulary claim is still true and still load-bearing; it is simply no longer asserted by a field nothing could falsify.
- **The import stays**, decided by running the analyzer with the doc link stripped rather than by reading the source.
- **The replacement `reason:` avoids the removed identifiers verbatim**, because the plan's own zero-match gate forbids them. Named descriptively instead.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The first draft of the replacement `reason:` string tripped the plan's own zero-match gate**

- **Found during:** Task 1
- **Issue:** The reason string named `RegistrableKey.hasPortalTrigger` and `HotkeyCaptureRefusal.noPortalTrigger` verbatim to explain what had been deleted. That made `grep -rn 'hasPortalTrigger\|noPortalTrigger' lib/ test/` return **2**, failing both the task's `<verify>` and its acceptance criterion, which require **0**.
- **Fix:** Reworded to "the portal-trigger flag on RegistrableKey" and "the fifth HotkeyCaptureRefusal value that read it" — the deletion is still named precisely and the reason still carries the whole trade-off, without reintroducing the tokens the gate scans for.
- **Files modified:** `test/infrastructure/hotkey/hotkey_key_catalogue_test.dart`
- **Verification:** gate re-run, **0** matches; row green in the full suite.
- **Committed in:** `de50896` (part of the Task 1 commit — the fix landed before the commit, so no intermediate red state was committed)

**2. [Rule 2 - Missing Critical] The import question was settled by experiment rather than by a clean analyzer run**

- **Found during:** Task 1
- **Issue:** `dart analyze --fatal-infos` was clean after the argument was removed, which the plan would accept as "a `///` reference still needs it". But a clean run is consistent with two different worlds — the import is genuinely needed, or the project does not flag unused imports at all — and the plan explicitly said **do not guess**. Reporting "the analyzer decided" without knowing the analyzer *can* decide would have been exactly the class of unearned claim this phase exists to remove.
- **Fix:** Temporarily rewrote the `[XdgShortcutTrigger]` doc link to backticks, re-ran the analyzer on that file, observed `unused_import` / exit 2, then restored from a scratchpad backup (not `git checkout --`).
- **Files modified:** none permanently — `hotkey_key_catalogue.dart` restored byte-identical
- **Verification:** post-restore `grep -n 'XdgShortcutTrigger'` shows the `[...]` link back at `:186`; full analyze clean; full suite green.
- **Committed in:** n/a (measurement only, no lasting change)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing-critical-evidence)
**Impact on plan:** Neither changed scope. The first was a gate conflict inside my own new text, caught by the plan's own verify and fixed before commit. The second strengthened an evidence claim the plan asked not to guess at. No scope creep.

## Issues Encountered

None. Both tasks executed as written; the two items above were handled under the deviation rules rather than as problems.

## Prohibitions — self-assessment

- **P6 (append-only, nothing outside the ratified scope).** Held. The diff is exactly the six files the plan lists. `x11_key_grab_registrar.dart`, `hotkey_status_view.dart` and `json_config_store.dart` are untouched; no plan 01-01 … 01-14 was rewritten, superseded or renumbered; `_bmad-output/implementation-artifacts/deferred-work.md` was **read only** and not edited (its 01-07 `resolution:` passage still reads "a five-subject validator", which is an accurate record of what was true on 2026-09-02 and is not mine to rewrite — the append-only rule is precisely why the sweep for stale counts was scoped to `lib/` and `test/`). `.planning/WINDOWS.md` entries 32–35 left open.
- **P2 (closure evidence not retrofitted or vacuous).** Held. No `RegistrableKey` was constructed by hand with the flag forced false to make the branch reachable before deleting it. The replacement assertion runs against `HotkeyKeyCatalogue.registrableKeys()`, the real injected vocabulary, and the three dominating assertions were run green *before* the deletion rather than asserted after it.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- WR-07 and WR-08 are closed; together with plan 01-18's WR-03 and WR-04 this completes G-01-16, the four warnings 01-VERIFICATION.md raised on this phase's own new code and did not defer.
- Plan 01-20 is the last of the phase (WR-05 ledger entry, at the user's ratified decision).
- **Owed to a reviewer, not to code:** D3's prose is human-judgment coverage — whether the two new AltGr blocks say the right thing is editorial and no grep settles it. Read them against UAT test 9's `fidelity:` note.
- **One record note for Phase 7 (ARCH-06):** `registrable_keys.dart` appears in no verbatim-fixed ARCHITECTURE-SPINE.md block (it was created by 01-07 in this phase), so removing a field from it needed no human gate. The four frozen declarations were confirmed byte-identical mechanically, held to the standard 01-12 proved for its own two files.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-11*

## Self-Check: PASSED

All six modified files present on disk; both task commits (`de50896`, `5ed401c`) present in `git log`. All eight plan `<verification>` items re-run and passing at HEAD.
