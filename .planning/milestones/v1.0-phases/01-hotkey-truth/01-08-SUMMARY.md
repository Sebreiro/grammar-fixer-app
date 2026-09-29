---
phase: 01-hotkey-truth
plan: 08
subsystem: api
tags: [hotkey, wayland, x11, settings, precedence, port-contract, riverpod]

requires:
  - phase: 01-hotkey-truth (plan 04)
    provides: "`HotkeyUnavailableCause`, which is what makes a superseding `HotkeyUnavailable` on `bindingChanges` distinguishable from the one a refused bind returns"
  - phase: 01-hotkey-truth (plan 06)
    provides: "`GlobalHotkey.current`, the `hotkeyBackendDescription` field on `SettingsState`, and the adapter-side half of the same 'whichever is newer' rule this plan states in the port"
  - phase: 01-hotkey-truth (plan 07)
    provides: "the controller as the capture-control work left it — `captureValidator` as a field, `_beginMutation`/`_endMutation` untouched"
provides:
  - "the precedence between the port's two writers, written in `GlobalHotkey`'s own documentation: an event observed after a `bind()` was issued supersedes that bind's return value, with the same-turn tie broken toward the backend"
  - "'observed' defined as the moment the consumer's listener runs, not the moment the backend emitted"
  - "the honest reachability boundary — the protocol-level inversion at startup is unreachable on the shipped Wayland adapter, and the doc says so instead of claiming a live defect"
  - "`SettingsController._backendChangeGeneration`: a rebind stamps it when it issues its bind and discards its own outcome if a backend-originated change bumped it while the bind was in flight"
  - "an info-level log line for the discard, in `applyStartupOutcome`'s decline shape, carrying no key and no combination"
affects: [01-09, 01-10, phase-2 SETTINGS-02, phase-2 SETTINGS-09, phase-7 ARCH-06]

actuals:
  tokens: 3067
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A monotonic generation counter beside the state (not on it) as the mechanism a consumer implements a port-stated precedence rule with — the same slot, and the same synchronous-answer reason, as `_mutating`"
    - "A precedence rule between two writers of one state field stated in the port where both members are declared, so a second adapter cannot implement the opposite order and still satisfy every written invariant"

key-files:
  created: []
  modified:
    - lib/src/domain/hotkey/global_hotkey.dart
    - lib/src/application/settings_controller.dart
    - test/application/settings_controller_test.dart

key-decisions:
  - "The counter's final name is `_backendChangeGeneration` (the plan's working name was `_bindGeneration`; it counts backend-originated changes observed, not binds issued, and the name says which)."
  - "The tie-break comparison is `!=` against a monotonic counter, so any move at all supersedes — a same-turn arrival is after the bind was issued, which is what the port's rule says."
  - "When the bind's outcome is discarded, `hotkeyBackendDescription` keeps the value that arrived *with* the surviving change rather than re-reading `GlobalHotkey.current`. Re-reading would risk pairing a compositor outcome with the description of the bind's own answer on any adapter that lacks 01-06's adapter-side record guard."
  - "A discarded outcome does NOT suppress the mutation's own `SettingsFailure`. The outcome field says what is in effect; the failure field says the user's rebind did not land. Both are true at once and both are still rendered."
  - "The rule is stated in full on `bindingChanges` (the winning writer) with the short form and a pointer on `bind` (the losing one), so a reader of either member finds it."

patterns-established:
  - "Precedence between two writers of one state field belongs in the port, not in the consumer: an application-ring comment leaves a second adapter free to implement the opposite order."
  - "State the reachability boundary of a rule in the same doc as the rule. This doc says the startup inversion is protocol-legal and unreachable on the shipped adapter, so nobody later reads the rule as a bug report."

requirements-completed: [HOTKEY-07]

coverage:
  - id: D1
    description: "`GlobalHotkey` documents which of its two writers wins when they disagree, with the rationale, the definition of 'observed', the same-turn tie-break, and the honest reachability boundary"
    requirement: "HOTKEY-07"
    verification:
      - kind: other
        ref: "grep -c 'supersede\\|precedence' lib/src/domain/hotkey/global_hotkey.dart -> 2 (non-zero); dart analyze --fatal-infos -> No issues found!"
        status: pass
    human_judgment: true
    rationale: "Whether prose states a rule unambiguously enough that a second adapter author implements the same order is a judgement a grep cannot make. The grep proves only that words are present."
  - id: D2
    description: "`changeHotkey` discards its own bind outcome when a backend-originated change landed after that bind was issued, keeps the newer one, and logs the discard"
    requirement: "HOTKEY-07"
    verification:
      - kind: unit
        ref: "test/application/settings_controller_test.dart#C6 HOTKEY-07: a compositor change landing while a rebind is in flight survives, and the rebind's own answer is discarded"
        status: pass
      - kind: unit
        ref: "test/application/settings_controller_test.dart#CAP-12: on X11 the settings surface is authoritative for the binding it requested (the no-intervening-change half)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The guard behaves correctly against a real compositor that emits `ShortcutsChanged` while a portal `BindShortcuts` dialog is open"
    verification: []
    human_judgment: true
    rationale: "OWED, not observed. This container has no GlobalShortcuts portal, so no real mid-rebind `ShortcutsChanged` can be produced here. The fake reproduces the ordering; it does not prove a real compositor emits in that window."

duration: 15min
completed: 2026-09-02
status: complete
---

# Phase 01 Plan 08: Hotkey Precedence Summary

**`GlobalHotkey` now states that a `bindingChanges` event observed after a `bind()` was issued supersedes that bind's return value — same-turn arrivals included — and `SettingsController.changeHotkey` obeys it via a `_backendChangeGeneration` stamp, so a compositor rebind landing during a seconds-wide portal dialog is no longer overwritten by the bind's own stale answer.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-09-02T22:14Z *(approximate — the orchestrator handoff was not stamped at spawn; the first task commit is 22:23:10Z)*
- **Completed:** 2026-09-02T22:29Z
- **Tasks:** 2 of 2
- **Files modified:** 3 (all three were declared in `files_modified` — see "Files outside the plan's list")

## Accomplishments

- **The rule is written where both writers are declared.** `GlobalHotkey.bindingChanges` carries the full statement: an event that reaches it supersedes the return value of any `bind()` issued before it; the tie in a same-turn arrival goes to the backend; "observed" means the moment the consumer's listener runs, never the moment the backend emitted. `bind`'s own doc carries the short form and points at it, so a reader of either member finds the rule.
- **The rationale rides with it**, because a rule with no reason gets re-litigated: on Wayland the compositor is the authority (AD-10), D-01 requires the surface to show what is *currently* in effect, and a bind's answer is by construction older than any change the backend originated after that call was issued.
- **The reachability boundary is stated, not glossed.** The doc says the GlobalShortcuts documentation specifies no ordering, so a change arriving *before* a bind's answer is protocol-legal — and that it is nevertheless unreachable on the shipped Wayland adapter, which subscribes to `ShortcutsChanged` only after `_bindShortcut` has returned. Verified against the adapter this session: the two `_listenForShortcutSignals(client)` call sites are at `wayland_portal_global_hotkey.dart:488` (the abandoned-refusal branch) and `:519`, both *after* the `await _bindShortcut(...)` at `:467`. No live startup defect is claimed.
- **The reachable window is closed.** `changeHotkey` stamps `_backendChangeGeneration` at the instant it issues the bind, `_onBindingChanged` bumps it, and the rebind discards its own outcome if the number moved — leaving the state holding the compositor's newer fact, and its description.
- **The discard is audible.** An info line in `applyStartupOutcome`'s decline shape: *"the rebind outcome was not applied because the surface already holds a newer backend-originated one"*. No key, no combination, no config value (T-01-45).
- **The three things the plan told this plan not to touch are untouched:** `applyStartupOutcome`, `_onBindingChanged`'s last-writer-wins semantics between two backend changes (its only addition is the bump), and `_writeChange`'s position inside `changeHotkey` — Phase 2's SETTINGS-02 territory.

## Task Commits

1. **Task 1: Write the precedence rule where both writers are declared** — `b67efdf` (docs)
2. **Task 2: Give the rebind path the guard the startup path already has** — `eed99e1` (fix)

## Files Created/Modified

- `lib/src/domain/hotkey/global_hotkey.dart` — the precedence rule, its rationale, the definition of "observed", the same-turn tie-break and the reachability boundary, on `bindingChanges` (full) and `bind` (short form + pointer). Documentation only; no declaration changed, so no AD-9 gate is spent by this plan.
- `lib/src/application/settings_controller.dart` — the `_backendChangeGeneration` field, the stamp-and-compare in `changeHotkey`, the discard log, and the bump in `_onBindingChanged`.
- `test/application/settings_controller_test.dart` — one new row for the mid-flight discard; one `reason:` added to an existing row to tie the no-intervening-change half of the rule to HOTKEY-07.

## For Phase 2's SETTINGS-02 (DW-68) — the exact boundary to rebase on

`changeHotkey` now spans **lines 175–238** of `lib/src/application/settings_controller.dart` (it was 158–190 before this plan; the plan's own quoted `:142-172` was already stale).

**Lines this plan touched, in post-change numbering:**

| Lines | What |
|---|---|
| 180–184 | the generation stamp and its comment |
| 189–207 | the tie-break comment, `final superseded = ...`, and the `if (superseded)` discard log |
| 211–219 | the two `superseded ? … : …` ternaries for `hotkeyBindOutcome` / `hotkeyBackendDescription`, and their comment (these replaced the two former plain lines) |

**Lines this plan did NOT touch, and which are SETTINGS-02's subject:**

| Lines | What |
|---|---|
| 162–174 | the method's doc comment |
| 176–178 | the `_beginMutation()` guard |
| **185–188** | **`await _bind(binding)` and `await _writeChange(...)` — the bind-before-write ordering SETTINGS-02 closes. Deliberately left exactly as found.** |
| 220–226 | `_resolveFailure(writeFailure ?? bindFailure, _Mutation.hotkey)` |
| 227–237 | `mutationInFlight: false` and the `finally { _endMutation(); }` |

SETTINGS-02 changes the *ordering* at 185–188 and will have to decide what a generation stamped before a reordered bind means. The stamp at 184 must stay **before** whichever call issues the bind, wherever that call ends up; that is the whole content of the invariant.

Also owed to Phase 2 / plan 01-10: the plan's `<artifacts_this_phase_produces>` names the counter's working name `_bindGeneration`. **The shipped name is `_backendChangeGeneration`** — it counts backend-originated changes observed, not binds issued.

## Decisions Made

Recorded here because this was an unattended run and no human was available to consult. Each is the best-supported reading of the plan and the port's own contract; each is reviewable.

1. **Counter name: `_backendChangeGeneration`.** The plan offered `_bindGeneration` as a working name and asked for the final one to be recorded. What the counter counts is backend-originated changes *observed*, and `_bindGeneration` would read as "how many binds have been issued" — the opposite subject.
2. **`!=` rather than `>` for the comparison.** Equivalent on a monotonically incrementing counter; `!=` states "any move at all counts", which is exactly the tie-break the plan asked to be explicit rather than incidental. A comment says so at 189–195.
3. **The description is carried, not re-read, on the discard path.** `_backendDescription()` reads `GlobalHotkey.current`. On the shipped Wayland adapter 01-06's record guard means `current` keeps the newer change, so re-reading would be harmless there — but the port does not promise that guard, and the test fake demonstrably does not implement it. Keeping `_state.hotkeyBackendDescription` pairs the surviving outcome with the wording that arrived in the same turn as it, which is the property 01-06's `_backendDescription` doc says must hold ("keeps the pair from describing two different moments").
4. **A discarded outcome does not suppress the mutation's failure.** If the bind threw and a compositor change landed meanwhile, the state shows the compositor's outcome *and* still shows "the shortcut could not be registered". These are two different facts — what is in effect, and whether the user's own change landed — and `_resolveFailure`'s doc already establishes that the surface must keep saying the second one until the mutation that earned it is fixed. Left unchanged.
5. **The rule's full text went on `bindingChanges`, not on `bind`.** The plan allowed either or both. `bindingChanges` is the winning writer and already contains the "never an answer to a call this app made, which `bind` already gives" sentence the rule extends; `bind` carries the short form plus a pointer, so neither member is a dead end.
6. **The no-intervening-change case got no new test row** — it is already covered by three pre-existing rows (`CAP-12: on X11 the settings surface is authoritative…`, `…on Wayland the surface reports the compositor's binding…`, `…a backend that cannot report the effective binding leaves it absent`), all of which run a rebind with nothing intervening and assert the bind's own answer lands. One `reason:` was added to the first of them naming HOTKEY-07, so the coverage is legible rather than accidental.

## Verification Criteria NOT literally passed

Both are declared here rather than reported as passes. Neither was worked around by reshaping the code to satisfy a literal command.

### 1. `grep -c 'generation' lib/src/application/settings_state.dart` prints `0` — **FAILS at baseline, unrelated to this plan**

It prints **1**, and did before this plan ran. The single match is a pre-existing doc sentence at `settings_state.dart:104`:

> `/// has no mutation-generation guard, so a second mutation issued inside that`

That sentence is about `_beginMutation`'s refusal semantics and predates this plan. Making the literal command print `0` would require deleting a correct pre-existing doc line for a cosmetic pass — the fourth instance this phase of the single-line-grep problem the executor brief warned about.

**Substituted check, which proves the criterion's actual intent (the counter is bookkeeping beside the state, not something a consumer renders):**

```
$ git diff --stat lib/src/application/settings_state.dart
(empty — the file is untouched by this plan)
$ grep -n 'generation' lib/src/application/settings_state.dart
104:  /// has no mutation-generation guard, so a second mutation issued inside that
```

`SettingsState` gained no field, no constructor parameter and no diff at all. The counter is a private `int` on `SettingsController` beside `_mutating`.

### 2. "The total `test(` declaration count across `test/` is unchanged" — **NOT met: 982 → 983 (+1)**

This criterion and the plan's own instruction in the same `<action>` block ("update the existing controller tests to cover … a rebind with a change arriving mid-flight") cannot both be satisfied: the mid-flight discard is a new behaviour with no existing row, and no existing row became redundant.

**What was done instead of gaming the count:** exactly one row was added, in the existing group `a change the backend originated (C5, C6, AD-10, AD-11)`, as a sibling of the startup-seed row it is the rebind analog of. **No new test file. No row deleted. No row's subject changed.** The alternatives were both worse — folding two subjects into one row, or deleting an unrelated row to hold the number.

The row is not vacuous. It was mutation-checked this session: with `superseded` forced to `false`, the scoped controller file reported `+51 -1` and the single failure was this row (`/tmp/.../scratchpad` held the backup; the file was restored from it and re-analyzed clean before the commit).

## Deviations from Plan

**None under Rules 1–4.** No bug, missing critical functionality, blocker or architectural change was found. The plan's two tasks were executed as written.

Two smaller notes that are not deviations but are worth recording:

- **The plan's quoted line numbers were stale, again** (`:142-172` for `changeHotkey`, `:294-312` for `applyStartupOutcome`, `:324-333` for `_onBindingChanged`; the real pre-change positions were 158–190, 313–332 and 344–354). Located by name, per the executor brief. The `applyStartupOutcome` no-hunk criterion holds under both numberings: the diff's hunk headers are `-140,0`, `-162,0`, `-166,0`, `-170,2` and `-344,0`, and none falls inside 294–312 or 313–332.
- **One `reason:` string was added to an existing test row** (`CAP-12: on X11 the settings surface is authoritative for the binding it requested`). Inside a declared file; no assertion changed, no subject changed.

**Total deviations:** 0.
**Impact on plan:** none — no scope creep, no undeclared file, no pre-empted territory.

## Files outside the plan's list

**None.** All three files changed were in `files_modified`. This is the first plan this phase whose declared file list was complete — the four preceding plans each needed undeclared files (01-05: six `DaemonStartup.begin` call sites plus `composition_wiring_test.dart`; 01-06: three settings files; 01-07: six files). Recorded because the executor brief asked for it either way.

## Known Stubs

None. Nothing in this plan is unreachable, placeholder, or wired to an absent data source. The guard is on the shipped rebind path and is exercised by a passing test.

## Threat register

All four mitigations the plan assigned to this work are implemented:

| Threat | Disposition | Where |
|---|---|---|
| T-01-42 — a stale bind answer overwriting a newer compositor change | mitigated | `settings_controller.dart:184,196,216-219`, plus the info log at 201–206 so the case is observable |
| T-01-43 — an unwritten ordering rule | mitigated | `global_hotkey.dart` — the rule is in the port, where both writers are declared |
| T-01-44 — a change lost during a seconds-wide portal dialog | mitigated | the stamp is taken before the bind is issued, so the guard covers the whole `await`, not just the moment of assignment |
| T-01-45 — the discard log line | mitigated | the line names the situation only: no key label, no combination, no config value, and no context map at all |
| T-01-SC — package-manager installs | accepted (n/a) | no dependency changed; `pubspec.yaml` and `pubspec.lock` were not touched |

**Threat flags:** none. No new network endpoint, auth path, file access pattern or schema change. The one new piece of state is a private in-process integer.

## Verification Results

Every command below was run this session, after the final code state.

| Command | Result |
|---|---|
| `dart analyze --fatal-infos` | **No issues found!** |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **All tests passed!** — `+960 ~2` (baseline was 959/2; the +1 is this plan's row) |
| `dart test --exclude-tags=live test/application/settings_controller_test.dart` | **All tests passed!** — `+52` (was 51) |
| `flutter test --exclude-tags=live test/ui test/platform test/composition` | **All tests passed!** — `+165 ~7`, exactly the baseline |
| `awk '/changeHotkey\(HotkeyBinding/,/^  }$/' … \| grep -Ec 'generation\|newer'` | **4** (non-zero) |
| `grep -c 'supersede\|precedence\|newer' lib/src/domain/hotkey/global_hotkey.dart` | **4** (non-zero) |
| `grep -c 'supersede\|precedence' lib/src/domain/hotkey/global_hotkey.dart` | **2** (the port file matches, not only an application-ring comment) |
| `dart format --output=none --set-exit-if-changed` on all three files | clean |
| `git diff` hunks vs `applyStartupOutcome` | no hunk inside it under either numbering |

No baseline was regressed: 960/2 scoped (was 959/2, +1 by this plan's own row) and 165/7 flutter (unchanged).

## Human verification OWED — not observed

Recorded as owed, never as passed.

1. **A real compositor emitting `ShortcutsChanged` while a `BindShortcuts` dialog is open.** This is the exact scenario the guard exists for, and it cannot be produced in this container: there is no GlobalShortcuts portal here. The unit row reproduces the *ordering* against `FakeGlobalHotkey`'s `bindGate`; it does not prove a real compositor emits in that window, nor that a real portal's dialog is open long enough for a user to trigger one. Needs a GNOME/KDE Wayland session: open the settings screen, start a rebind, and rebind the same shortcut from the desktop's own keyboard settings while the portal dialog is up. Expect the desktop's combination to survive and the info line to appear on stderr.
2. **No live X11 observation was attempted or needed.** On X11 `bind()` resolves synchronously inside the seam and `bindingChanges` is an empty stream that closes, so the guard is structurally inert there — `_backendChangeGeneration` can never move. Stated rather than tested, because there is no branch to reach.

Both belong in `WINDOWS.md` alongside 01-07's rows 13 and 14.

## Issues Encountered

- **The `bindGate` fake records the bind's own answer into `current`.** `FakeGlobalHotkey._record` is called on the bind's resolution path regardless of what arrived meanwhile, so after a discarded bind the fake's `current` holds the bind's answer rather than the compositor's — the opposite of the real Wayland adapter, which has 01-06's record guard. This is what made decision 3 (carry the description, do not re-read it) load-bearing rather than stylistic. The fake was left alone: it is a faithful stand-in for an adapter that has *not* implemented the port's new rule, which is exactly the consumer-side robustness the guard should have.
- **Nothing else.** No auth gate, no package install, no analyzer fight.

## User Setup Required

None — no external service configuration, no new dependency, no config migration.

## Next Phase Readiness

**Ready for plan 01-09 and 01-10.**

- **Owed to plan 01-10 (the ledger closures):** FLAT-03 is now closable as *resolved* — the rule is stated in the port and the reachable half is enforced with a passing test. The closure text should quote the code: `GlobalHotkey.bindingChanges`'s "Precedence over [bind]'s answer" paragraph and `SettingsController._backendChangeGeneration`. Note in the closure that no AD-9 declaration was edited by this plan (documentation only), so it adds nothing to the Phase-7 ARCH-06 reconciliation hand-off.
- **Owed to Phase 2's SETTINGS-02 (DW-68):** the line table above. The one invariant to preserve across the reorder is that the stamp is taken before the bind is issued.
- **Bearing on the open 01-07 blocker (the two narrowed widget assertions):** none. This plan changed no rendering and no read-out. `hotkeyBindOutcome` is written by one fewer path than before, never by more, so what `HotkeyStatusView` can display is unchanged and the question of whether the requested combination may appear on screen at all is untouched. That blocker still needs a product answer, not a test edit.
- **Concern to carry:** the guard's live behaviour is unobserved (see "Human verification OWED"). Everything below the port is proven by a passing, mutation-checked unit row; the compositor half of the interaction is not.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-02*

## Self-Check: PASSED

- All three modified files exist on disk.
- Both task commits resolve in `git log --all`: `b67efdf`, `eed99e1`.
- Every acceptance criterion was re-run against the final code. Two did not pass literally and are declared above with their substitutes and reasoning ("Verification Criteria NOT literally passed"); none is reported as a pass.
- Plan-level `<verification>` 1–5 all re-run: analyze clean, scoped `dart test` 960/2, `flutter test` 165/7, the rule present in the port and the guard present in `changeHotkey`, and no `git diff` hunk inside `applyStartupOutcome`.
