---
phase: 01-hotkey-truth
plan: 18
subsystem: infra
tags: [x11, ffi, panel-visibility, keyboard-focus-witness, ad-15, cap-14]

# Dependency graph
requires:
  - phase: 01-hotkey-truth
    provides: "01-12's keyboard-focus witness seam (G-01-13), which is the code both warnings are about"
  - phase: 01-hotkey-truth
    provides: "01-16's green x11_global_hotkey_test.dart row — the broad merge-gate suite this plan runs globs it"
  - phase: 01-hotkey-truth
    provides: "01-17's finished live probe — its clean-tree assertion forbids concurrent edits under lib/ and test/"
provides:
  - "Guard symmetry across both halves of the KeyboardFocusWitness seam: `_recordFocusWitness()` is the write-side AD-15 backstop, mirroring `_keyboardStillHere()`"
  - "A stated contract on the port: `recordFocusGained()` may throw and the caller backstops it, so the asymmetry with `dispose()`'s never-throws promise is written down rather than accidental"
  - "`FakeKeyboardFocusWitness.recordError` — the injection point the write half had none of, and the reason the new guard is pinned by a row rather than by a reading"
  - "Mutation-audit item 40 in window_manager_panel_visibility_test.dart, verified at 1 failure"
  - "`X11KeyboardFocusWitness._open` allocates both out-parameters before publishing `_bindings`/`_display`, and `_readFocus` refuses to read while either pointer is `nullptr`"
affects: [panel-visibility, cap-14, phase-07-documentation]

actuals:
  tokens: 65280
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A seam's guard discipline is symmetric or it is not a discipline: where one half of a port is backstopped, the other half is backstopped the same way and for a stated reason"
    - "A guard with no injection point is unpinned; the fake grows the hook before the row is written"
    - "Allocate-before-publish on any lazily-opened FFI handle whose health check is field-shaped"

key-files:
  created: []
  modified:
    - lib/src/infrastructure/panel/window_manager_panel_visibility.dart
    - lib/src/infrastructure/panel/keyboard_focus_witness.dart
    - lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart
    - test/fakes/fake_keyboard_focus_witness.dart
    - test/infrastructure/panel/window_manager_panel_visibility_test.dart

key-decisions:
  - "The write-side guard returns nothing and changes no caller behaviour: a failed recording leaves nothing witnessed, so `focusUnmoved` answers `false` and the next focus-out is a real focus loss — the pre-seam behaviour, which is the fail-safe direction the port's own contract states"
  - "Neither `_unavailable` latch in `_open` was widened to cover the allocations: `_unavailable` means the connection could not be established and will not be retried, and an allocation failure is a transient — latching it would turn one failed `calloc` into a witness that never answers again for the life of the daemon"
  - "WR-04's acceptance is a SOURCE assertion, not a behavioural one, and is declared as such rather than dressed as a measurement. No row was manufactured to make the branch 'covered'"

patterns-established:
  - "Mutation-audit item 40: the write-side guard's removal fails exactly 1 row, verified by applying the mutation and restoring from a scratchpad backup"

requirements-completed: []

coverage:
  - id: D1
    description: "A throw from `recordFocusGained()` at a visible, focusing panel does not escape the `_window.events` listener callback into the root zone"
    verification:
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#AD-15: a witness that throws while recording does not escape the window-event listener, and the next focus-out still dismisses"
        status: pass
    human_judgment: false
  - id: D2
    description: "A failed recording emits exactly one error line whose context is exactly `{'error_type': <runtime type>}` — no user text, no vendor exception `toString()`"
    verification:
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#AD-15: a witness that throws while recording does not escape the window-event listener, and the next focus-out still dismisses (map equality on `errors.single.context`)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A failed recording suppresses nothing: the next genuine focus-out still dismisses the panel"
    verification:
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#AD-15: a witness that throws while recording does not escape the window-event listener, and the next focus-out still dismisses (isVisible isFalse, calls == [show, focus, hide])"
        status: pass
    human_judgment: false
  - id: D4
    description: "The new guard is pinned, not merely present: removing the `on Object` guard fails exactly 1 row (mutation-audit item 40)"
    verification:
      - kind: other
        ref: "mutation applied and reverted 2026-09-11: `_recordFocusWitness` body reduced to the bare call; `dart test --exclude-tags=live test/infrastructure/panel test/fakes_smoke_test.dart` reported 1 failing test, the new row"
        status: pass
    human_judgment: false
  - id: D5
    description: "The port states that `recordFocusGained()` may throw and that the caller backstops it; no signature changed"
    verification:
      - kind: other
        ref: "git diff 0c8c126..HEAD -- lib/src/infrastructure/panel/keyboard_focus_witness.dart shows 11 additions, 0 deletions — doc-only"
        status: pass
    human_judgment: false
  - id: D6
    description: "`X11KeyboardFocusWitness._open` cannot publish a display without the buffers that make it readable, and `_readFocus` answers 'cannot tell' rather than writing through a null pointer"
    verification:
      - kind: other
        ref: "source assertion: both `calloc` line numbers (206, 207) strictly below both publish line numbers (210, 211); `_readFocus`'s body carries a `nullptr` comparison returning null; `dart analyze --fatal-infos` clean; both suites unchanged"
        status: pass
    human_judgment: true
    rationale: "SOURCE assertion, not behavioural. A `calloc` failure has no injection point through this seam — the class IS the seam, it owns its own allocator with no hook, and it needs a live X server to reach `_open` at all. The SIGSEGV was NOT reproduced; nobody starved this process's allocator. A human must accept the ordering argument on its own terms, because no row can be written that would fail if the ordering were wrong."

duration: 11 min
completed: 2026-09-11
status: complete
---

# Phase 01 Plan 18: Witness seam guard symmetry and allocate-before-publish Summary

**Both halves of the `KeyboardFocusWitness` seam now carry the same AD-15 backstop — `_recordFocusWitness()` beside `_keyboardStillHere()`, a stated may-throw contract on the port, and a `FakeKeyboardFocusWitness.recordError` hook that pins the new guard with one row — and `X11KeyboardFocusWitness._open` allocates its out-parameters before it publishes the display it cannot serve without them.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-09-11T13:36:30Z
- **Completed:** 2026-09-11T13:47:01Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- **WR-03 closed.** The bare `_witness.recordFocusGained()` in the `focus` arm is now the single call inside `_recordFocusWitness()`, an `on Object catch` guard declared beside `_keyboardStillHere()` so the two halves of the seam's backstop sit together. Its doc names the escape route the code cannot show: the recording runs inside the `_window.events` **listener callback**, and a listener throw is not a stream error, so the subscription's `onError` never sees it and the root zone (`main.dart`'s `PlatformDispatcher.onError`) is what receives it.
- **The asymmetry is now a contract.** `keyboard_focus_witness.dart` states on `recordFocusGained()` that it may throw and that the caller backstops it — doc-only, no signature touched, so `dispose()`'s never-throws promise reads as a deliberate difference rather than as an accident of which member happened to get a guard.
- **The guard is pinned by a row, not a reading.** `FakeKeyboardFocusWitness` gained `Object? recordError`, thrown *after* `recordedGains` is incremented so a row can assert both that the call was made and that it failed. One new row drives it end to end: injected throw → real listener path → real guard → real logger → a panel that still dismisses on the next genuine focus-out.
- **WR-04 closed.** `_open` now allocates both out-parameters into locals and assigns them before `_bindings` and `_display`, so a `calloc` that throws leaves the seam unopened rather than half-opened. `_readFocus` gained a belt that refuses to read while either pointer is `nullptr`, answering the honest "cannot tell".
- **Mutation-audit item 40 added and verified at its claimed count.** Removing the `on Object` guard fails exactly 1 row — measured, not asserted.

## Task Commits

1. **Task 1 (RED): failing row for the witness write-side backstop** — `3cff7dc` (test)
2. **Task 1 (GREEN): guard the witness write side with the AD-15 backstop** — `df58066` (feat)
3. **Task 2: allocate the witness out-parameters before publishing the display** — `33f7952` (fix)

Task 1 carried `tdd="true"`, so it produced a RED commit and a GREEN commit. No REFACTOR commit: there was nothing to clean up, and an empty refactor commit would be noise.

## Files Created/Modified

- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` — `_recordFocusWitness()` added beside `_keyboardStillHere()`; the `focus` arm calls it instead of the witness directly (+33/−1)
- `lib/src/infrastructure/panel/keyboard_focus_witness.dart` — `recordFocusGained()`'s doc states that it may throw and that the caller backstops it (+11/−0, doc only)
- `lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart` — `_open` allocates before publishing; `_readFocus` gained the `nullptr` belt (+29/−2)
- `test/fakes/fake_keyboard_focus_witness.dart` — `Object? recordError`, thrown after `recordedGains` is incremented; `recordedGains`' doc corrected to say it counts the runs that threw (+21/−3)
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` — one new row beside the existing throwing-witness row, plus mutation-audit item 40 (+64/−0)

## Which acceptance criteria were behavioural and which were source assertions

This is the distinction the plan's third prohibition requires be stated rather than blurred.

**Behavioural (a row runs, and would go red if the claim were false):**

| Claim | Evidence |
|---|---|
| A throw from `recordFocusGained()` does not escape the window-event listener | the new row, `escaped` isEmpty under `runZonedGuarded` |
| Exactly one error line, context equal by **map equality** to a single `error_type` key | the new row; equality rather than `containsPair`, so a later key carrying the caught object's own text turns it red |
| The call was made and then failed | `witness.recordedGains == 1` with `recordError` armed |
| A failed recording suppresses nothing — the next genuine focus-out dismisses | `visibility.isVisible` isFalse, `window.calls == ['show', 'focus', 'hide']` |
| The guard is load-bearing, not decorative | mutation applied and reverted: **1 failing row**, the new one |
| No existing behaviour moved | full dart suite 982 passed / 2 skipped (981 before this plan — exactly one row higher), flutter suite 165 passed / 7 skipped, unchanged |

**Source assertions (no row runs; the claim is checked against the text):**

| Claim | Evidence |
|---|---|
| Exactly one direct `_witness.recordFocusGained` call site, and it is inside the guard | `grep -c` = 1; `_recordFocusWitness` appears twice (declaration + call site) |
| The port doc changed and no signature did | doc-only diff, 11 additions / 0 deletions |
| `_open` allocates before it publishes | `calloc<UnsignedLong>` at :206 and `calloc<Int32>` at :207, both strictly below `_bindings = bindings` at :210 and `_display = display` at :211 |
| `_readFocus` refuses to read without its buffers | a `nullptr` comparison inside `_readFocus`'s body, returning null |
| No frozen port declaration moved | `git diff --numstat 0c8c126..HEAD -- lib/src/domain/` is empty |

## WR-04: the SIGSEGV was not reproduced, and it cannot be from this seam

Stated plainly, because an argued claim must never be recorded as an observed one.

**Nobody starved this process's allocator.** The fault WR-04 describes — `_readFocus` executing `_focusOut.value = _none` through a null pointer after `_open` published a display without its buffers — was never made to happen, here or anywhere. What was established is that the ordering which makes it *possible* is gone.

It cannot be observed from this seam, for three compounding reasons:

1. **There is no hook.** `X11KeyboardFocusWitness` calls `calloc` directly. The class *is* the seam; it has no injected allocator and nothing above it can make an allocation fail.
2. **`_open` is unreachable in the suite.** Reaching it needs `DynamicLibrary.open('libX11.so.6')` to succeed *and* `XOpenDisplay(nullptr)` to return a live display — a real X server. Every row that exercises this code path drives `FakeKeyboardFocusWitness` from the adapter's side instead, which is the whole reason the seam exists (AGENTS.md §4.2).
3. **A row that faked it would pin the wrong thing.** Constructing the class with hand-set private state to make the branch "covered" would assert an arrangement production cannot produce. The plan prohibits it and no such row was written.

So WR-04's acceptance is: the ordering, read from the source; `dart analyze --fatal-infos` clean; and both suites unchanged, which is the honest negative — nothing in either can reach this file's `_open` at all, so "unchanged" is what a correct change looks like here, not evidence that the change works.

This is recorded as `.planning/WINDOWS.md` entry **35** (`kind: unrun-verify`, status `open`) so the absence of a runnable proof is visible at ship time rather than inferred from the diff.

## Decisions Made

- **The write-side guard returns nothing.** The read side answers `false` on a throw because it owes the caller a value; the write side owes nothing, and the caller's behaviour is identical whether the recording landed or not. A failed recording leaves nothing witnessed, so `focusUnmoved` answers `false` — the pre-seam behaviour.
- **Neither `_unavailable` latch was widened to cover the allocations.** `_unavailable` means "the connection could not be established and will not be retried". An allocation failure is not that: it is a transient the next call may not hit, and latching it would turn one failed `calloc` into a witness that never answers again for the life of the daemon. The `DynamicLibrary.open` try/catch and the `XOpenDisplay` null check are both byte-identical to before.
- **The `_readFocus` belt is named as a belt in its own comment.** On today's paths `_open` cannot return non-null with either pointer still `nullptr`, so the branch is not reachable. It exists for the `dispose`-then-read ordering the class currently guards by the `_disposed` flag alone, so a future edit moving that flag check does not reintroduce a null-pointer write. Stating that is the difference between a guard against a future edit and a branch presented as reachable.
- **No REFACTOR commit for Task 1.** Nothing needed cleaning up after GREEN.

## Prohibition compliance

The plan carried three `status: unresolved`, `verification: judgment` prohibitions. All three held:

1. **"Cannot tell" was never upgraded to "unmoved".** Neither change makes `focusUnmoved` answer `true` anywhere it previously answered `false`. A failed recording leaves nothing witnessed → `false`. A missing out-parameter returns null → `false`. No fallback reusing a last known focus id was added, and `_readFocus` returns nothing it did not read from the server on that call. The existing suppression rows (mutation-audit items 36 and 37) plus the new row all go red if that ever changes.
2. **No log line carries user text or a vendor exception's `toString()`.** The one new line is produced by the file's existing `_errorContext`, which emits exactly `{'error_type': …}` and no second key. The new row asserts that map by **equality**, so a later addition of a key carrying the caught object's own text fails the row rather than shipping.
3. **The argued claim is recorded as argued.** See the WR-04 section above and coverage entry D6 (`human_judgment: true`).

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 01-19 (the wave-4 sibling, WR-07 and WR-08) shares no file with this plan and is unblocked. The working tree is clean and every change is committed.
- Plan 01-20 files WR-05 as a ledger-only entry per the user's ratified decision.
- `.planning/WINDOWS.md` entries 32, 33 and 34 (from plans 01-16 and 01-17) were left `open` — none of them is this plan's to close. Entry 35 is new and belongs to WR-04's missing behavioural proof.
- No new ledger entries in `_bmad-output/implementation-artifacts/deferred-work.md`, no change to `COVERAGE.md`, no new files, no new public API — exactly as `<artifacts_this_phase_produces>` specified.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-11*

## Self-Check: PASSED

All five modified source files exist on disk. All three task commits (`3cff7dc`, `df58066`, `33f7952`) are present in `git log --all`. Plan-level `<verification>` re-run at HEAD: `dart analyze --fatal-infos` clean, dart suite 982 passed / 2 skipped (one row higher than the 981 before this plan), flutter suite 165 passed / 7 skipped (unchanged), `grep -c '_witness.recordFocusGained'` = 1, both `calloc` line numbers below both publish line numbers, `_readFocus` carries a `nullptr` guard, `git diff --numstat 0c8c126..HEAD -- lib/src/domain/` empty, `test/architecture` green (228 passed / 1 skipped — includes `ad1_import_rule_test.dart` and `composition_wiring_test.dart`).
