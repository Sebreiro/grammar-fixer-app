---
phase: 01-hotkey-truth
plan: 09
subsystem: api
tags: [hotkey, domain, value-type, immutability, defensive-copy, const, ad-9]

requires:
  - phase: 01-hotkey-truth (plan 07)
    provides: "the capture control that builds `HotkeyBinding(modifiers: {...capture.modifiers}, ...)` — a fresh set literal, which is why HOTKEY-09 is hardening and not a bug fix"
  - phase: pre-existing (`hotkey_grab.dart`)
    provides: "the in-tree defensive-copy precedent, including the doc sentence that names the price: *\"The constructor is therefore not `const`, which is the price.\"*"
provides:
  - "`HotkeyBinding.modifiers` is copied on construction as `Set<HotkeyModifier>.unmodifiable(modifiers)`, so a caller that still owns the set it passed in cannot change what an already-recorded binding compares equal to"
  - "the set the binding exposes is unmodifiable, so a consumer reaching into it cannot mutate the value either"
  - "a doc on the field that states the type-specific consequence (an equal-comparing `SettingsState` suppresses the rebuild that would have shown the change) AND records that this closed no live defect, so a later reader does not go hunting for one"
  - "an amended equality row that proves the copy actually defends — the caller's set is mutated after construction and the two bindings still compare and hash equal"
  - "a measured correction to the plan's cost model: the literal-grep count was right but its file list was short, and 34 further sites sat in implicit const contexts the grep cannot see"
affects: [01-10, phase-7 ARCH-06]

actuals:
  tokens: 6365
  tasks: 1
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A domain value type that owns a collection copies it in the constructor's initializer list as `Set<X>.unmodifiable(...)` and pays for it by dropping `const` — the shape `HotkeyGrab` established, now used by both hotkey value types so a reader does not have to remember which of two near-identical types is safe to hand a mutable set."
    - "A doc that states the honest scope of a hardening change (\"this closed no live defect\") beside the guarantee, so the next reader does not reconstruct a bug that never existed."
    - "Verifying a `const`-removal by compiler, not by grep: `dart analyze` sees implicit const contexts, a literal-string grep cannot."

key-files:
  created: []
  modified:
    - lib/src/domain/hotkey/hotkey_binding.dart
    - lib/src/infrastructure/config/default_app_config.dart
    - test/domain/value_equality_test.dart
    - test/application/controller_resilience_test.dart
    - test/application/settings_controller_test.dart
    - test/composition/composition_root_test.dart
    - test/composition/daemon_graph_test.dart
    - test/fakes_smoke_test.dart
    - test/infrastructure/config/json_config_store_test.dart
    - test/infrastructure/correction/active_correction_test.dart
    - test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart
    - test/infrastructure/hotkey/x11_global_hotkey_test.dart
    - test/infrastructure/hotkey/xdg_shortcut_trigger_test.dart
    - test/infrastructure/system/daemon_startup_test.dart
    - test/ui/settings/settings_screen_config_test.dart
    - test/ui/settings/settings_screen_hotkey_test.dart
    - test/ui/settings_harness.dart

key-decisions:
  - "Task 1 answered `defensive-copy` — selected by the orchestrator under the user's instruction to complete the phase unattended, NOT ratified by a human. Phase 7's ARCH-06 reconciliation must re-confirm it with a human before the spine is edited to match."
  - "The mutation guarantee is proven by AMENDING the existing order-independence equality row rather than adding a new one: the row already claimed `{control, shift}` and `{shift, control}` are one combination, and 'and still are after the caller mutates its set' is the same claim extended one step. This keeps the plan's `test(`-count-unchanged criterion honest (983 -> 983) while still producing evidence, instead of choosing between the two."
  - "The row also asserts `first.modifiers.add(...)` throws `UnsupportedError`. The constructor copying and the field being unmodifiable are two different guarantees, and only the second stops a consumer that reaches into `binding.modifiers` directly."
  - "The plan's verify #4 (`grep -rc 'const HotkeyBinding(' lib/ test/`) was treated as necessary but NOT sufficient. It printed clean at a point where `dart analyze` reported 40 errors. `dart analyze --fatal-infos` is what actually proves the criterion; the grep is kept as a cheap first pass."
  - "`ARCHITECTURE-SPINE.md` was not touched. `git status --porcelain _bmad-output/planning-artifacts/` is empty and stayed empty."

patterns-established:
  - "When a plan's cost model is a grep count, verify the count AND the file list separately — this phase has now had the count right and the file list wrong (01-09), the count wrong (01-04), and the build location wrong (01-05)."
  - "A `const` removal on a widely-constructed type has two cost classes: explicit `const T(` sites, and sites where `T(...)` sits inside somebody else's const expression. Only the compiler enumerates the second, and clearing them cascades (a `const` variable turned `final` invalidates every const expression that referenced it)."

requirements-completed: [HOTKEY-09]

coverage:
  - id: D1
    description: "`HotkeyBinding` copies its modifier set on construction, so a caller that mutates the set it passed in cannot change what an already-recorded binding compares equal to"
    requirement: "HOTKEY-09"
    verification:
      - kind: unit
        ref: "test/domain/value_equality_test.dart#CAP-12: two bindings whose modifier sets differ only in order are the same combination, and HOTKEY-09: they stay so after the caller mutates the set it passed in"
        status: pass
      - kind: other
        ref: "grep -c 'unmodifiable' lib/src/domain/hotkey/hotkey_binding.dart -> 2"
        status: pass
    human_judgment: false
  - id: D2
    description: "The set the binding exposes is itself unmodifiable, so a consumer reaching into `binding.modifiers` cannot mutate the value either"
    requirement: "HOTKEY-09"
    verification:
      - kind: unit
        ref: "test/domain/value_equality_test.dart#CAP-12: two bindings whose modifier sets differ only in order are the same combination, and HOTKEY-09: they stay so after the caller mutates the set it passed in (throwsUnsupportedError assertion)"
        status: pass
    human_judgment: false
  - id: D3
    description: "No call site anywhere constructs a `HotkeyBinding` as a compile-time constant — including the implicit const contexts a literal grep cannot see"
    requirement: "HOTKEY-09"
    verification:
      - kind: other
        ref: "dart analyze --fatal-infos -> No issues found! (the authoritative check; grep -rn 'const HotkeyBinding(' lib/ test/ -> no matches, kept as the cheap first pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Value equality, hashing and the rendered shortcut label are unchanged in behaviour; the whole scoped suite is unmoved"
    requirement: "HOTKEY-09"
    verification:
      - kind: unit
        ref: "dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart -> All tests passed! 960 passing / 2 skipped (identical to the 01-08 baseline)"
        status: pass
      - kind: automated_ui
        ref: "flutter test --exclude-tags=live test/ui test/platform test/composition -> All tests passed! 165 passing / 7 skipped (identical to the 01-08 baseline)"
        status: pass
      - kind: other
        ref: "git diff --stat lib/src/ui/settings/hotkey_binding_label.dart -> empty (label formatter untouched, still iterates HotkeyModifier.values)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The AD-9 declaration edit is recorded as orchestrator-selected rather than human-ratified, and the spine reconciliation is left to Phase 7 via plan 01-10's ledger entry"
    requirement: "HOTKEY-09"
    verification: []
    human_judgment: true
    rationale: "Whether an orchestrator-selected answer to a `blocking-human` gate is acceptable in place of a human ratification is precisely the judgment a human must make. Automation cannot self-certify its own substitution for a human gate. The decision is recorded verbatim below with its framing intact; a human must read it and either ratify or reverse."

duration: 11 min
completed: 2026-09-02
status: complete
---

# Phase 01 Plan 09: HotkeyBinding Defensive Copy Summary

**`HotkeyBinding` now copies its modifier set into an unmodifiable `Set` in the constructor's initializer list, dropping `const` exactly as `HotkeyGrab` already did — 50 `const` keywords removed across 17 files, and the doc says plainly that this closed no live defect.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-09-02T22:30:00Z (approximate — captured after the fact; the 01-08 metadata commit landed at 22:30:23Z)
- **Completed:** 2026-09-02T22:41:00Z
- **Tasks:** 1 executed (Task 2); Task 1 was a pre-answered checkpoint
- **Files modified:** 17

## Task 1's answer, reproduced verbatim with its framing intact

Task 1 was a `gate="blocking-human"` `checkpoint:decision`. It was answered on disk in
`.planning/phases/01-hotkey-truth/01-GATE-ANSWERS.md` before this executor ran, and was **not**
re-asked. The answer, and — as the gate answer itself requires — the framing that goes with it:

> **Decided by: the orchestrator, 2026-09-02, under the user's explicit instruction to complete the
> phase unattended. Option id: `defensive-copy`.**
>
> **This is NOT a human ratification of a frozen-spine edit.** The user declined the interactive gate
> and delegated completion. Phase 7's ARCH-06 reconciliation must treat this entry as
> orchestrator-selected and re-confirm it with a human before the spine is edited to match.
>
> **The basis is requirement text, not orchestrator preference.** HOTKEY-09 reads:
>
> > Defensively copy or wrap `HotkeyBinding.modifiers` so a caller mutating its own set cannot change
> > a supposedly immutable domain value behind a `const` constructor
>
> That mandates a mechanism, which admits only one of the plan's three options:
>
> | Option | Verdict |
> |---|---|
> | `defensive-copy` | The only option that satisfies the requirement text. **Chosen.** |
> | `document-the-rule` | Prose only — does not "defensively copy or wrap", so HOTKEY-09 stays unmet. Same shape as 01-04's rejected `message-only`. |
> | `unmodifiable-view-const` | The plan documents that it does not work: a `const` constructor cannot call `Set.unmodifiable`. |
>
> Consequences that bind the implementation:
>
> - Drop `const` from the declared constructor and copy the set on construction, following
>   `hotkey_grab.dart:17-35`, whose doc already states *"The constructor is therefore not `const`,
>   which is the price."*
> - Expected cost, per the plan's re-count: one `const` removal in `lib/`
>   (`default_app_config.dart:142`, whose enclosing `AppConfig` is not itself `const`, so no cascade)
>   and fifteen across seven `test/` files. Verify the count rather than trusting it — plan counts
>   have drifted twice this phase.
> - `ARCHITECTURE-SPINE.md` is **not** edited by this phase. The reconciliation for this and every
>   other AD-9 declaration edit is a Phase-7 (ARCH-06) hand-off entry in the ledger.
> - On record and unchanged by this decision: **there is no live defect today.** Every `lib/`
>   construction site passes a fresh set literal and a `const` set literal is immutable at runtime.
>   This is hardening against a future caller. Say so in the SUMMARY; do not overstate it as a fix.

**Every one of those consequences was honoured.** In particular: the spine was not edited, and the
"no live defect" framing is stated below, in the code doc, and in the commit message.

## The honest scope of this change: no bug was fixed

Stated plainly, because the plan, the research and the gate answer all insist on it and because a
future reader who assumes otherwise will waste time looking for a defect that was never there:

- **Nothing in `lib/` mutated a set it had handed to a binding.** The capture control builds a fresh
  `{...capture.modifiers}` (`hotkey_capture.dart:166`); the JSON config store builds a local set it
  drops on return (`json_config_store.dart:321-332`); the shipped default is a `const` set literal,
  which is immutable at runtime.
- **So this is API hardening against a future caller, not a fix.** What it buys is that the
  guarantee is now mechanical rather than documentary, and that the two near-identical hotkey value
  types (`HotkeyBinding`, `HotkeyGrab`) no longer have different safety properties with no signpost.
- **What made it worth doing anyway** is the shape of the failure it forecloses. The value equality
  AD-9 mandates on this type is exactly what would turn a mutated set into silence rather than an
  error: `SettingsState` holds a binding transitively and compares by value, so a mutated set makes
  a `copyWith` produce a state that compares *equal* to the one before it, and an equal state
  suppresses the rebuild that would have shown the change. No exception, no log line, nothing to
  trace. That reasoning is now in the field's own doc.

## Accomplishments

- **The declaration.** `HotkeyBinding` takes `Set<HotkeyModifier> modifiers` as a plain parameter and
  assigns `modifiers = Set<HotkeyModifier>.unmodifiable(modifiers)` in its initializer list. The
  constructor is no longer `const`, and the field doc names that price in the same words its
  precedent does, then adds the consequence specific to this type and the honest note above.
- **Both halves of the guarantee are asserted, not just one.** The constructor copying stops the
  *caller* mutating the value; the field being unmodifiable stops a *consumer* who reaches into
  `binding.modifiers` doing the same. The amended row proves both.
- **50 non-declaration `const` keywords removed across 17 files** (see the count section — this is
  where the plan's model was short).
- **Equality, hashing and the rendered label are provably unchanged.** `setEquals`/`setHash` are
  order-independent, so an unmodifiable copy of the same elements compares and hashes identically;
  `hotkey_binding_label.dart` is byte-identical and still iterates `HotkeyModifier.values`, so
  insertion order still never reaches the user. Both suites are at exactly the 01-08 baseline.

## Task Commits

1. **Task 1: Ratify dropping `const` from AD-9's declared constructor** — no commit; pre-answered
   checkpoint, answer on disk in `01-GATE-ANSWERS.md`, reproduced above.
2. **Task 2: Copy the set on construction, and remove the `const` uses that follow** — `ad6a3e1`
   (`fix`)

**Plan metadata:** see the `docs(01-09)` commit that carries this file.

## The actual count of affected sites, versus the plan's prediction

The plan predicted **16** non-declaration sites (1 in `lib/`, 15 across **seven** `test/` files) and
asked that the count be verified rather than trusted. Verified. There are **two** classes of site,
and the plan's model only had one of them.

### Class 1 — literal `const HotkeyBinding(` (what the plan's grep sees): 16 sites, 9 files

The **count** was exactly right. The **file list** was short by one file.

| File | Sites | Declared by the plan? |
|---|---|---|
| `lib/src/infrastructure/config/default_app_config.dart` | 1 | yes |
| `test/infrastructure/hotkey/x11_global_hotkey_test.dart` | 4 | yes |
| `test/infrastructure/hotkey/xdg_shortcut_trigger_test.dart` | 3 | yes |
| `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart` | 2 | yes |
| `test/ui/settings/settings_screen_config_test.dart` | 2 | yes |
| `test/infrastructure/config/json_config_store_test.dart` | 1 | yes |
| `test/infrastructure/correction/active_correction_test.dart` | 1 | yes |
| `test/infrastructure/system/daemon_startup_test.dart` | 1 | yes |
| **`test/ui/settings/settings_screen_hotkey_test.dart`** | **1** | **NO — undeclared** |

### Class 2 — `HotkeyBinding(...)` inside somebody else's `const` expression: 34 keywords, 10 files

These carry no literal `const HotkeyBinding(` substring, so **the plan's grep is structurally blind
to them** and its `files_modified` list could not have contained them. Three shapes:

- `const AppConfig _config = AppConfig(... hotkeyBinding: HotkeyBinding(...))`
- `const HotkeyBound(HotkeyRegistration(effective: HotkeyBinding(...)))`
- `const HotkeyBinding _ctrlShiftG = HotkeyBinding(...)` / `static const HotkeyBinding ctrlShiftG = ...`
  / `const altSpace = HotkeyBinding(...)`

| File | `const` keywords removed / turned `final` | Declared by the plan? |
|---|---|---|
| `test/application/settings_controller_test.dart` | 14 | NO |
| `test/ui/settings/settings_screen_hotkey_test.dart` | 6 | NO |
| `test/infrastructure/hotkey/x11_global_hotkey_test.dart` | 4 | yes |
| `test/application/controller_resilience_test.dart` | 2 | NO |
| `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart` | 2 | yes |
| `test/ui/settings_harness.dart` | 2 | NO |
| `test/composition/composition_root_test.dart` | 1 | NO |
| `test/composition/daemon_graph_test.dart` | 1 | NO |
| `test/fakes_smoke_test.dart` | 1 | NO |
| `test/infrastructure/config/json_config_store_test.dart` | 1 | yes |

**Totals: 50 non-declaration `const` keywords, 17 files.** Eight files were undeclared by
`files_modified` (the seven marked NO above, plus `test/domain/value_equality_test.dart`, whose
equality row was amended). Confirmed mechanically:
`git show ad6a3e1 --unified=0 -- '*.dart' | grep -c '^-.*\bconst\b'` → **51** (50 plus the
declaration itself).

**Class 2 also cascades**, which is why it took three analyzer passes rather than one: turning
`const HotkeyBinding _altSpace` into `final` invalidated every `const HotkeyBound(...)` that
*referenced* it, and turning `static const HotkeyBinding ctrlShiftG` into `final` invalidated the
`static const AppConfig defaultConfig` that referenced *that*. Passes: 40 issues → 16 → 7 → 0.

## Files Created/Modified

- `lib/src/domain/hotkey/hotkey_binding.dart` — the declaration: `const` dropped, the set copied via
  `Set<HotkeyModifier>.unmodifiable(...)` in the initializer list, and the doc that names the price,
  the type-specific silent-failure consequence, and the honest "no live defect" scope.
- `lib/src/infrastructure/config/default_app_config.dart` — the one `lib/` construction site
  (`Ctrl+Shift+G`, the shipped default); its enclosing `AppConfig` was not `const`, so no cascade,
  exactly as the plan predicted.
- `test/domain/value_equality_test.dart` — the order-independence row amended (not added) to mutate
  the caller's set after construction and assert the binding is unmoved, plus a
  `throwsUnsupportedError` assertion on the exposed set.
- 15 further `test/` files — mechanical `const` removals and `const`→`final` conversions only. No row
  was deleted, no row was restructured, no assertion was weakened.

## Decisions Made

1. **`defensive-copy`, as answered — orchestrator-selected, not human-ratified.** Recorded above in
   full, including the requirement text it rests on and the fact that Phase 7's ARCH-06 must
   re-confirm it with a human.
2. **The mutation proof amends an existing row rather than adding one.** The plan says twice that the
   `test(` count must not change and that this is "mechanical edits to existing tests, not new test
   work" — while the plan's own `must_haves` truth requires that two bindings "remain [equal] after
   the caller mutates the set it passed in", which no existing row asserted. Extending the row that
   already owned the order-independence claim satisfies both: the count is unchanged at **983** and
   the guarantee has evidence. Nothing was proven by prose alone.
3. **Both guarantees asserted separately.** Constructor-copies and field-is-unmodifiable are
   different properties; `Set.unmodifiable` happens to give both, but only one of them is what
   HOTKEY-09's text asks for, so the row asserts each.
4. **`dart analyze` is the authoritative check for "no compile-time-constant construction", not the
   plan's grep.** The grep is kept as a cheap first pass, and this is declared as a substitution
   below rather than reported as a clean pass of the literal criterion.
5. **The mutated sets in the amended row are named locals, not inline literals.** A set literal
   handed straight to the constructor is a reference nobody kept, so the mutation the row exists to
   perform would be impossible to write. The row comments say so, in the spirit of
   `test/support/value_equality.dart`'s own "build each side separately, without const" rule.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] 34 `const` keywords in implicit const contexts, across 10 files, seven of them undeclared**

- **Found during:** Task 2, immediately after the literal-grep removals
- **Issue:** With all 16 literal `const HotkeyBinding(` sites removed and the plan's verify grep
  already printing nothing, `dart analyze --fatal-infos` reported **40 errors**. `HotkeyBinding(...)`
  appears inside other `const` expressions (`const AppConfig _config = ...`,
  `const HotkeyBound(HotkeyRegistration(effective: ...))`, `static const HotkeyBinding ctrlShiftG =
  ...`, `const altSpace = ...`) where the literal string never occurs. Six files carrying these were
  absent from `files_modified` entirely, and a seventh (`settings_screen_hotkey_test.dart`) carried a
  literal site too and was also absent. The suite could not compile.
- **Fix:** Removed the `const` keyword from each such expression, or converted the declaration to
  `final` where the site was a `const` variable. Three analyzer passes were needed because the
  conversions cascade: a `const` variable turned `final` invalidates every const expression that
  referenced it (40 → 16 → 7 → 0).
- **Files modified:** `test/application/settings_controller_test.dart`,
  `test/application/controller_resilience_test.dart`, `test/composition/composition_root_test.dart`,
  `test/composition/daemon_graph_test.dart`, `test/fakes_smoke_test.dart`,
  `test/ui/settings_harness.dart`, `test/ui/settings/settings_screen_hotkey_test.dart`,
  `test/infrastructure/hotkey/x11_global_hotkey_test.dart`,
  `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart`,
  `test/infrastructure/config/json_config_store_test.dart`
- **Verification:** `dart analyze --fatal-infos` → `No issues found!`; both suites at the exact 01-08
  baseline (960/2 and 165/7).
- **Committed in:** `ad6a3e1` (part of the task commit)

**2. [Rule 2 - Missing critical] The plan's own `must_haves` mutation truth had no test to prove it**

- **Found during:** Task 2, before implementing
- **Issue:** The plan's acceptance criteria say to *confirm* the existing order-independence row
  rather than add one, and that the `test(` count must not change. But its `must_haves` truths
  require that two set-equal bindings "remain so **after the caller mutates the set it passed in**",
  and no row asserted anything about mutation. Shipping the copy with no evidence would have made
  HOTKEY-09's mechanism unverified — the exact "closes on inspection rather than on a gate that ran"
  failure mode STATE.md flags as this milestone's standing risk.
- **Fix:** Amended the existing row (`test/domain/value_equality_test.dart`) instead of adding one:
  the two sets are now named locals, they are mutated (`add`, `clear`) after construction, and the
  row re-asserts `expectSameValue`, the single-element `Set` hash agreement, the surviving
  combination, and `throwsUnsupportedError` on the exposed set.
- **Files modified:** `test/domain/value_equality_test.dart`
- **Verification:** row passes; `grep -rho 'test(' test/ --include='*.dart' | wc -l` → **983**,
  unchanged from the 01-08 baseline.
- **Committed in:** `ad6a3e1` (part of the task commit)

---

**Total deviations:** 2 auto-fixed (1× Rule 3 blocking, 1× Rule 2 missing critical).
**Impact on plan:** No scope creep. Deviation 1 was mandatory — the tree did not compile without it,
and it is a correction to the plan's cost model rather than new work. Deviation 2 added evidence for a
truth the plan already required, at zero net `test(` cost. No production behaviour beyond the
declaration itself was changed.

## Substituted / augmented verification — declared, not reported as passes

**Plan verify #4 — `grep -rc 'const HotkeyBinding(' lib/ test/ | grep -v ':0$'`.**
The literal command **did** pass (prints nothing). It is reported here as **passed but insufficient**,
not as sufficient proof of the criterion it is attached to ("a compile-time-constant construction
survives somewhere"). Evidence that it is insufficient: at the moment it first printed nothing,
`dart analyze --fatal-infos` reported **40 errors** from exactly that failure. The substitute that
proves the real property is `dart analyze --fatal-infos` → `No issues found!`, which is the only
check that enumerates implicit const contexts. Both were run; both pass now. This is the fifth time
this phase a single-line grep over formatted Dart has been structurally unable to prove the property
it was attached to (01-04, 01-06 ×2, 01-07, 01-08) and it is recorded in `.planning/WINDOWS.md`
(entry 18) so a later plan editing a `const`-constructible domain type does not trust the same grep.

**Everything else passed literally.** For the record, with output:

| Check | Result |
|---|---|
| `dart analyze --fatal-infos` | `No issues found!` |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | `All tests passed!` — **960 passing / 2 skipped**, ≥900 as required, identical to the 01-08 baseline |
| `flutter test --exclude-tags=live test/ui test/platform test/composition` | `All tests passed!` — **165 passing / 7 skipped**, identical to the 01-08 baseline |
| `grep -c 'unmodifiable' lib/src/domain/hotkey/hotkey_binding.dart` | `2` (≥1 required; the copy is in the initializer list) |
| `grep -rn 'const HotkeyBinding(' lib/ test/` | no matches |
| `git status --porcelain _bmad-output/planning-artifacts/` | empty — `ARCHITECTURE-SPINE.md` untouched |
| `git diff --stat lib/src/ui/settings/hotkey_binding_label.dart` | empty — label formatter unchanged |
| `grep -rho 'test(' test/ --include='*.dart' \| wc -l` | `983` — unchanged |
| `grep -n 'HotkeyBinding(' lib/src/domain/hotkey/hotkey_binding.dart` | one line — exactly one constructor declaration remains |

**No human-only verification is owed by this plan.** Unlike 01-07 and 01-08, nothing here is
display-server-dependent, needs a real compositor, or is observable only at runtime: the change is a
domain-ring value type and its guarantee is fully expressible in-process. The one item requiring a
human is a judgment, not an observation — see D5 and "Issues Encountered".

## The plan's remaining `must_haves` truths, checked

| Truth | Status |
|---|---|
| A caller mutating the set it passed cannot change what the binding compares equal to | **Proven** — amended row in `value_equality_test.dart` |
| Differently-ordered sets compare and hash equal, and remain so after mutation | **Proven** — same row (order half pre-existing, mutation half added) |
| The rendered label is order-independent because it iterates enum-declaration order | **Confirmed, unchanged** — `hotkey_binding_label.dart` byte-identical; its own doc states the reason |
| A binding with an empty modifier set stays constructible in the domain, is refused before any backend call, and is never produced by the capture control | **Confirmed by existing rows, not newly proven** — `HotkeyBinding(modifiers: {}, key: 'F12')` still constructs (`x11_global_hotkey_test.dart`, `xdg_shortcut_trigger_test.dart`), and the refusal lives in plan 01-07's application-ring validator and the adapter, both untouched here |
| Exactly one constructor declaration in the domain binding file; no call site constructs one as a compile-time constant | **Proven** — one declaration; `dart analyze` clean |

## Earlier plans' work, checked intact

Verified by `git diff` against the files each plan owns, all empty in this commit:

- **01-04** — `hotkey_status_view.dart` untouched; still selects its unavailable rendering from
  `HotkeyUnavailable.cause` via `_causeLine`, never from message content.
- **01-06** — the compositor's `trigger_description` still rendered verbatim;
  `_unavailableLines`' closing ownership sentence (Phase 2 / SETTINGS-09) untouched.
- **01-07** — capture control untouched: standing hint only under `BindingAuthority.application`,
  bare `Escape` releases focus, AltGr still refused on `LogicalKeyboardKey.altGraph`.
- **01-08** — `settings_controller.dart` untouched, so `_backendChangeGeneration` is still stamped
  before the bind is issued. `changeHotkey` was not modified in any way.
- Count-asserting tests: `composition_wiring_test.dart` (shared unresponsive-call budget, 3) and
  `ad1_import_rule_test.dart` (`_knownPortSeamCount`, 11) untouched and passing.

## Issues Encountered

**One, and it is a judgment for the morning, not a code problem.** Task 1 was a `blocking-human`
gate. It was answered by the orchestrator, not by a human, and the answer says so. That substitution
is legitimate for an unattended run only if a human later agrees it was — which is why it is filed as
coverage entry **D5** with `human_judgment: true` rather than auto-passed. The decision rests on
requirement text (HOTKEY-09 mandates a *mechanism*, which eliminates `document-the-rule`) and on a
documented impossibility (a `const` constructor cannot call `Set.unmodifiable`, which eliminates
`unmodifiable-view-const`), so the reasoning is checkable rather than a matter of taste. But it edits
a verbatim-frozen AD-9 declaration, and **the spine is now out of date until Phase 7 reconciles it.**

**One ledger-hygiene note, disclosed rather than hidden.** `.planning/WINDOWS.md` entry 18 was first
appended in this session as `kind: unrun-verify` with a description claiming the mutation guarantee
was only proven in-process. That was wrong — the guarantee *is* proven by a passing unit row, and no
runtime observation was ever required — and a false "owed" entry would block `/gsd-ship` for nothing.
It was rewritten in the same session, before being committed, to the accurate defect: the plan's
verify grep being structurally insufficient (`kind: deviation`). Recorded here because the correction
is the kind of thing a reviewer should be told about rather than discover.

## Next Phase Readiness

**Ready for plan 01-10**, which is the last plan in Phase 01 and owns the ledger work. It now has
four things from this plan to file:

1. **`FLAT-05` closes as resolved** — `HotkeyBinding.modifiers` is copied on construction and exposed
   unmodifiable, with the alternative FLAT-05 itself named (`document-the-rule`) considered and
   rejected on requirement text. Flip `status:` and add `resolution:`; do not delete the entry.
2. **The Phase-7 (ARCH-06) hand-off entry gains this AD-9 declaration edit** — the fourth, alongside
   01-01's `HotkeyStatus? get current`, 01-04's `HotkeyUnavailableCause`, and AD-11 step 1. Spine
   lines **239–243** now disagree with `hotkey_binding.dart:6`, which is intentional and unhidden.
3. **The reconciliation entry must carry the ratification status** — this edit was
   **orchestrator-selected under an unattended run, not human-ratified**, and Phase 7 must re-confirm
   it with a human before editing the spine. That distinction is the whole point of the record.
4. **`.planning/WINDOWS.md` entry 18** — the grep-insufficiency deviation, if 01-10 is filing window
   entries into the BMAD ledger.

**One concern to carry forward, unresolved by design:** the spine's AD-9 block and the shipped
`hotkey_binding.dart` are now textually different. Anyone reading the spine as the contract will read
a `const` constructor that no longer exists. That is the accepted cost of the "do not hand-edit the
spine" precedent, and it is the third such divergence Phase 01 has opened.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-02*

## Self-Check: PASSED

- All 3 files claimed in `key-files.modified` spot-checked on disk: present.
- Both commits present in `git log --oneline --all`: `ad6a3e1` (task) and `062740e` (metadata).
- Every `<acceptance_criteria>` re-run at final state; all pass, with plan verify #4 declared passed-but-insufficient and substituted by `dart analyze --fatal-infos` (see "Substituted / augmented verification").
- `dart analyze --fatal-infos` clean at final state; both suites at the 01-08 baseline (960/2 and 165/7); `test(` count 983.
- `.planning/config.json` and the untracked `.claude/` tree excluded from both commits.
