---
phase: 01-hotkey-truth
plan: 12
subsystem: ui
tags: [x11, xlib, dart-ffi, panel-visibility, focus, cap-14, g-01-13, gtk3]

# Dependency graph
requires:
  - phase: 01-11
    provides: "tool/uat/panel_toggle_probe.sh — the event-stream toggle oracle, and its recorded pre-fix baseline hide=FLICKER"
  - phase: 01-02
    provides: "X11KeyGrabRegistrar and its process-global X-error-handler discipline, which is why this read path is one Xlib call"
provides:
  - "KeyboardFocusWitness — an infrastructure-private seam answering whether a focus-out actually moved the keyboard"
  - "X11KeyboardFocusWitness — the X11 answer, built from XGetInputFocus alone"
  - "AbsentKeyboardFocusWitness — the null object that never suppresses; the Wayland arm"
  - "_onBlur's fourth question, with _focused surviving a suppressed focus-out"
  - "the same question at _releaseDeferredBlur, so the DW-32 latch route is covered too"
  - "DaemonStartup.focusWitness — chosen from the one display-server read AD-9's adapter is chosen from"
  - "CAP-14's toggle working across repeated presses on X11: SHOW,HIDE,SHOW,HIDE"
affects: [01-13, 01-14, wayland-portal, panel-geometry, arch-06]

actuals:
  tokens: 97762
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns:
    - "A display-server question answered synchronously as a fact, in place of a race the events cannot settle"
    - "A one-call FFI read path chosen to make an X-error class structurally unreachable rather than handled"
    - "A null-object port arm as the honest answer for a host that cannot answer, never a guess"

key-files:
  created:
    - lib/src/infrastructure/panel/keyboard_focus_witness.dart
    - lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart
    - lib/src/infrastructure/panel/absent_keyboard_focus_witness.dart
    - test/fakes/fake_keyboard_focus_witness.dart
  modified:
    - lib/src/infrastructure/panel/window_manager_panel_visibility.dart
    - lib/src/infrastructure/system/daemon_startup.dart
    - lib/main.dart
    - test/infrastructure/panel/window_manager_panel_visibility_test.dart
    - test/infrastructure/panel/panel_visibility_broadcast_test.dart
    - test/architecture/composition_wiring_test.dart

key-decisions:
  - "The discriminator asks 'is the keyboard still where it was?', not 'was this a grab?' — a grab moves no focus, so the question is race-free in both directions and needs no timer anywhere on the path"
  - "focusUnmoved may be true ONLY where the absence of a focus transfer is positively established; every uncertainty (no display, unanswerable server, None/PointerRoot, nothing witnessed, a throw) answers false, so an unproven path behaves exactly as it did before the seam"
  - "The read path is XGetInputFocus alone, because it takes no window argument and so cannot raise BadWindow — the one X error that would invoke the grab worker's cross-isolate Pointer.fromFunction, which the VM treats as fatal"
  - "_focused now SURVIVES a suppressed focus-out, removing the arm's dependency on a FocusIn(NotifyUngrab) coming back to re-arm it"
  - "The witness stays out of lib/src/domain/, so this fix touches no verbatim-frozen declaration and needs no spine ratification"
  - "focusWitness is required and defaultless — a default would put a private policy at a construction site and make a wiring mistake present as CAP-14 quietly never suppressing"
  - "A foreign client's global shortcut no longer dismisses the panel. Measured, deliberate, and the price of keying on the focus rather than on whose grab it was"

patterns-established:
  - "Negative controls counted from the JSON reporter's testDone events — the compact reporter's [E] markers never reach a line end, so grep -c reports 0 for every mutation"
  - "A behaviour change discovered by a fix is measured and filed, not absorbed into the fix's own claim"

requirements-completed: []

coverage:
  - id: D1
    description: "The KeyboardFocusWitness seam and its fail-safe contract: true only where a focus transfer is positively ruled out, false on every uncertainty"
    verification:
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#CAP-14: a focus-out at a panel whose keyboard never went anywhere is not a dismissal"
        status: pass
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#CAP-14: a focus-out that really moved the keyboard is still a dismissal"
        status: pass
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#AD-15: a witness that throws is taken as a real focus loss and says so once"
        status: pass
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#CAP-14: the shipped witness for a host that cannot answer never suppresses — the Wayland arm"
        status: pass
      - kind: other
        ref: "negative controls 33, 36, 37 — 3, 15 and 1 failures respectively, measured"
        status: pass
    human_judgment: false
  - id: D2
    description: "X11KeyboardFocusWitness reads the focus with XGetInputFocus alone — no window-taking Xlib call on the read path (T-01-61 mitigation)"
    verification:
      - kind: other
        ref: "sed 's://.*::' lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart | grep -cE 'XQueryTree|XGetWindowProperty' == 0"
        status: pass
      - kind: other
        ref: "grep -q 'XGetInputFocus' lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart"
        status: pass
      - kind: e2e
        ref: "DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh hide -> VERDICT=HIDE against a freshly built release bundle"
        status: pass
    human_judgment: false
  - id: D3
    description: "_onBlur's fourth question, asked after DW-33's and before the outstanding-request latch, with _focused surviving the suppressed path"
    verification:
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#CAP-14: the window still holds the keyboard after a suppressed focus-out, so the next genuine one still dismisses"
        status: pass
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#DW-33 is answered before the witness is asked — a blur with no preceding focus spends no round trip"
        status: pass
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#CAP-14: a focus gained at a visible panel is witnessed, and one at a false mirror is not"
        status: pass
      - kind: other
        ref: "negative controls 34, 38, 39 — 1 failure each, measured"
        status: pass
    human_judgment: false
  - id: D4
    description: "The same question at _releaseDeferredBlur, so a blur latched during one of our own round trips is reconsidered against the server"
    verification:
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#DW-32: a latched blur released after the keyboard came back is not a dismissal"
        status: pass
      - kind: unit
        ref: "test/infrastructure/panel/window_manager_panel_visibility_test.dart#DW-32: a latched blur released with the keyboard still elsewhere is a dismissal"
        status: pass
      - kind: other
        ref: "negative control 35 — 1 failure, measured (this row was the RED gate)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The wiring: the display server is read exactly once, each arm gets its own witness, and main.dart takes startup's rather than building one"
    verification:
      - kind: unit
        ref: "test/architecture/composition_wiring_test.dart#AD-9/G-01-13: the display server is read exactly once, and both the hotkey adapter and the focus witness are chosen from that one read"
        status: pass
      - kind: unit
        ref: "test/architecture/composition_wiring_test.dart#AD-9/G-01-13: each display-server arm gets its own focus witness — the X11 one on X11, the null object on Wayland"
        status: pass
      - kind: unit
        ref: "test/architecture/composition_wiring_test.dart#G-01-13: main.dart hands the panel adapter the witness startup chose, not one of its own"
        status: pass
      - kind: other
        ref: "arms swapped -> 1 failure; a second DisplayServer.fromEnvironment call -> 1 failure, both measured"
        status: pass
    human_judgment: false
  - id: D6
    description: "No verbatim-frozen declaration moved: AD-8's PanelVisibility, AD-9's GlobalHotkey and the key-grab registrar are byte-identical to the pre-fix anchor"
    verification:
      - kind: other
        ref: "git rev-parse 7d42485:<path> == git hash-object <path> for all three files"
        status: pass
      - kind: unit
        ref: "test/architecture/ad1_import_rule_test.dart"
        status: pass
    human_judgment: false
  - id: D7
    description: "CAP-14's toggle works for a user on a real desktop — the panel hides on its own shortcut and stays hidden, on a real GNOME/KDE session rather than Xvfb + openbox"
    verification: []
    human_judgment: true
    rationale: "The probe proves it against Xvfb + openbox 3.6.1, which is an X server with a minimal window manager. A real session's focus-stealing prevention, compositing and grab handling differ, and CAP-14 is ultimately a claim about what a user sees. WINDOWS.md 26 files the Wayland half of the same gap."
  - id: D8
    description: "The foreign-grab behaviour change is acceptable product behaviour — a foreign client's global shortcut no longer dismisses the panel"
    verification:
      - kind: e2e
        ref: "DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh foreign-grab -> VERDICT=NOTHING, FOCUS_BEFORE=FOCUS_AFTER=4194308 (was HIDE)"
        status: pass
    human_judgment: true
    rationale: "The change is measured, not in doubt; whether it is the behaviour the product wants is a decision no test can make. A foreign grab moves no focus, so it is indistinguishable from our own by construction. Plan 01-13 measures it, plan 01-14 files it, WINDOWS.md 24 keeps it visible at ship time."
  - id: D9
    description: "T-01-59 (a co-resident client contriving a matching focus id) and T-01-60 (an unresponsive X server blocking the synchronous read) are accepted rather than mitigated"
    verification: []
    human_judgment: true
    rationale: "Both are accepted on reasoning stated in the witness doc in that register, and neither was measured — nobody wedged an X server or contrived a matching focus id. WINDOWS.md 25 records it; plan 01-14 owes the ledger entries."

# Metrics
duration: 50 min
completed: 2026-09-10
status: complete
---

# Phase 01 Plan 12: The Focus-Owner Discriminator Summary

**A `KeyboardFocusWitness` seam whose X11 arm answers one `XGetInputFocus` call, turning `_onBlur`'s bare `blur` into "did the keyboard actually go anywhere?" — so the daemon stops dismissing its own panel on its own shortcut, and the `hide` route flips from `UNMAP=1 MAP=1 FLICKER` to `UNMAP=1 MAP=0 HIDE`**

## Performance

- **Duration:** 50 min
- **Started:** 2026-09-10T13:36:10Z
- **Completed:** 2026-09-10T14:26:00Z
- **Tasks:** 2 (one tracer, one TDD)
- **Files modified:** 10 (4 created, 6 modified)

## Accomplishments

- **G-01-13 is closed on the live oracle.** The `hide` route reports `UNMAP=1 MAP=0 VERDICT=HIDE` against plan 01-11's recorded `UNMAP=1 MAP=1 VERDICT=FLICKER`, and the reporter's own symptom — "shows once, then never hides" — is gone: `alternate` reads `SHOW,HIDE,SHOW,HIDE` where it read `SHOW,FLICKER,FLICKER,FLICKER`.
- **It is closed with a fact, not with timing.** No timer, delay or deadline exists anywhere on the path, and the 8 ms registrar poll and `ownerEvents` were not touched. The gate greps confirm it: `lib/src/infrastructure/panel/`, comment lines stripped, contains zero `Timer` or `Future.delayed`.
- **The one X-error class that could kill the process is structurally unreachable**, not handled. `XGetInputFocus` takes no window argument, so no `BadWindow` can be raised from the main isolate into the grab worker's cross-isolate `Pointer.fromFunction` (T-01-61).
- **Nine new behaviour rows, each pinned by a measured mutation.** Seven negative controls (33-39) were recorded, four more than the plan named, so no row rests on a claim rather than a count.
- **No frozen declaration moved.** All three of `panel_visibility.dart`, `global_hotkey.dart` and `x11_key_grab_registrar.dart` hash-compare equal to their blobs at the anchor commit `7d42485`. No spine ratification is owed by this plan.
- **CAP-14's real dismissals are intact and measured**: `focus-steal` and `desktop-click` both still classify `HIDE`, and control 36 (the witness's answer discarded) fails 15 rows across four groups — the measure of how much of CAP-14 rides on the answer being `true` only where a transfer is positively ruled out.

## Task Commits

1. **Task 1 (tracer): the seam, the X11 answer, `_onBlur`'s question and the wiring** — `dc6079b` (fix)
2. **Task 2 RED: nine rows and the finished fake** — `961fd61` (test)
3. **Task 2 GREEN: the question at `_releaseDeferredBlur`** — `791ddb9` (feat)
4. **Task 2: seven measured negative controls and three wiring pins** — `d78da63` (test)

**Plan metadata:** see the final `docs(01-12)` commit.

## Files Created/Modified

- `lib/src/infrastructure/panel/keyboard_focus_witness.dart` — the seam: `recordFocusGained()`, `focusUnmoved`, `dispose()`. Two members, one job, and the doc carries the load-bearing sentence: `true` only where the absence of a focus transfer is positively established.
- `lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart` — one `XGetInputFocus` on the read path, display opened lazily on first use, a permanent unavailable flag rather than a retry per blur, `None`/`PointerRoot` stored as nothing, out-parameters allocated once and freed in `dispose()`.
- `lib/src/infrastructure/panel/absent_keyboard_focus_witness.dart` — `focusUnmoved => false` unconditionally. The Wayland arm, and the honest answer for any host that cannot answer.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` — the constructor parameter, `recordFocusGained()` in the `focus` arm, `_onBlur`'s fourth question with `_keyboardStillHere()` as its AD-15-backstopped reader, the same question at `_releaseDeferredBlur`, the witness in `dispose()`, and head-doc prose saying for each of the four mechanisms why the new question does not disturb it.
- `lib/src/infrastructure/system/daemon_startup.dart` — the display-server read lifted into a local, `_focusWitnessFor` beside `_hotkeyFor`, `focusWitness` exposed as a field.
- `lib/main.dart` — `focusWitness: startup.focusWitness`.
- `test/fakes/fake_keyboard_focus_witness.dart` — settable answer, a throw switch, a recorded-gain count and a read count.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` — nine rows, controls 33-39, the witness hoisted into `setUp`, and the header's two stale prose counts corrected.
- `test/infrastructure/panel/panel_visibility_broadcast_test.dart` — one argument.
- `test/architecture/composition_wiring_test.dart` — three wiring rows and a `_startupSource()` helper.

## The measured result

| Route | 01-11 pre-fix baseline | Now | Plan 01-11's prediction |
| --- | --- | --- | --- |
| `show` | `SHOW` | `SHOW` | `SHOW` |
| `hide` | **`FLICKER`** | **`HIDE`** | `HIDE` |
| `alternate` | **`SHOW,FLICKER,FLICKER,FLICKER`** | **`SHOW,HIDE,SHOW,HIDE`** | `SHOW,HIDE,SHOW,HIDE` |
| `focus-steal` | `HIDE` | `HIDE` | `HIDE` |
| `desktop-click` | `HIDE` | `HIDE` | `HIDE` |
| `foreign-grab` | `HIDE` | **`NOTHING`** | *(not predicted — see below)* |

Full post-fix `hide` line:

```
ROUTE hide UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=all VERDICT=HIDE
```

## The behaviour change, stated rather than absorbed

**A foreign client's global shortcut fired while our panel is up no longer dismisses the panel.** Pre-fix it did — that was the diagnosis's smoking-gun control. Post-fix the `foreign-grab` route reads `UNMAP=0 MAP=0 FIRST=none FOCUS_BEFORE=4194308 FOCUS_AFTER=4194308 VERDICT=NOTHING`: the panel stayed up and the focus never left.

This is not a defect in the discriminator and cannot be narrowed by it. A foreign passive grab moves no focus, exactly as ours does not, so the two are indistinguishable to a question about the focus — that indistinguishability *is* the mechanism, taken deliberately. Not dismissing is arguably the more correct answer (the panel gets the keyboard back), but it is a change. Plan 01-13 measures it, plan 01-14 files it in the ledger, and it is recorded in `WINDOWS.md` as entry 24 so the ship gate sees it either way.

## Reconciling plan 01-11's failing acceptance criterion

01-11 reported one criterion as failing rather than smoothing it, and warned this plan directly (STATE.md blocker, `WINDOWS.md` 22):

> a focus-owner discriminator validated on a post-settle sample is CIRCULAR on the foreign-grab route, because the focus is foreign only because the dismissal happened. 01-12 must key its discriminator on something available when the blur is handled.

**The finding and the plan do not conflict, and the finding is now confirmed empirically.**

- The finding's *requirement* is already what the plan specifies. `_keyboardStillHere()` reads `XGetInputFocus` **synchronously at the moment the blur is handled** — not at a 1000 ms settle mark, and not from an event. That is precisely "something available when the blur is handled".
- What the finding actually invalidates is using the harness's `FOCUS_BEFORE`/`FOCUS_AFTER` columns as *validation evidence*, and no acceptance criterion in this plan does. The discriminator is validated by the `UNMAP`/`MAP` verdicts and by nine unit rows over a fake, never by the focus columns.
- **The finding's diagnosis is now proved.** It claimed the pre-fix `foreign-grab` focus reading `4194308 -> 2097439` was an artefact of the dismissal rather than a real transfer. With the dismissal gone, that same route reads `4194308 -> 4194308`. The focus never moved; openbox held it only because the panel had unmapped. 01-11 was right, and the reason it was right is now on the record rather than inferred.

No deviation protocol was needed, because no prohibition was reached.

## Decisions Made

- **The question is "is the keyboard still where it was?", not "was this a grab?"** X labels a grab's focus-out `NotifyGrab` precisely because no focus transferred, so the question is race-free in both directions and needs no ordering guarantee — which is what lets the fix exist with no timer.
- **Every uncertainty answers `false`.** No display, an unanswerable server, a focus reported as `None` or `PointerRoot`, nothing witnessed yet, or a throw: each behaves exactly as the adapter did before the seam existed. Suppressing a dismissal that should have fired costs the user a panel that will not go away; a needless dismissal costs only what CAP-14 already did.
- **`_focused` survives the suppressed path.** This removes the arm's dependency on a `FocusIn(NotifyUngrab)` coming back to re-arm it — the latent mechanism UAT test 14's `retest_after_fix` named, and the one that would have resurrected the withdrawn G-01-14 symptom for real.
- **`recordFocusGained()` stores the focus window, not the toplevel.** X names a *child* (`4194308` under toplevel `4194307`), so the comparison is "is it the same one it was?" rather than "is it ours?" — which is what keeps the read path free of the tree walk that would reintroduce T-01-61.
- **The witness compares against what the window *said* it held.** Recorded only in the `focus` arm, under the existing `_visible` guard, so a trailing focus event at a hidden panel records nothing (control 39, and its own row).

## Deviations from Plan

### Auto-fixed and corrected

**1. [Rule 1 - Stale plan fact] The negative-control record reaches 32, not 23**
- **Found during:** Task 2 (reading the `<read_first>` head doc)
- **Issue:** The plan's `<read_first>` states the record "currently reaches control 23". It reached 32. The record's own prose header separately said "Thirty-one mutations" while listing 32, and "80 rows" against an actual 90 — a prose count that had already drifted twice.
- **Fix:** New controls numbered 33-39. Both header counts re-derived from the artefacts (the mutation count from the entries, the row count from the harness's `testDone` total) with a sentence saying they are counted rather than carried, so the next appender re-reads them.
- **Files modified:** `test/infrastructure/panel/window_manager_panel_visibility_test.dart`
- **Verification:** `grep -cE '^/// [0-9]+\. '` prints 39; the JSON counter prints `ROWS=90`.
- **Committed in:** `d78da63`

**2. [Rule 2 - Missing critical verification] Seven negative controls, not three**
- **Found during:** Task 2
- **Issue:** The plan names three mutations to measure. Its own `<done>` requires that each of the nine new rows fail when its own mechanism is removed, and three controls pin only five of them — the moved-keyboard row, the Wayland-arm row, the throwing-witness backstop direction, the zero-reads row and the recorded-gain row would each have been unpinned.
- **Fix:** Four further controls measured (36 the witness's answer discarded, 37 the backstop answering `true` on a throw, 38 the question asked before DW-33's, 39 `recordFocusGained()` deleted). Every one of the nine rows now fails under at least one control.
- **Files modified:** `test/infrastructure/panel/window_manager_panel_visibility_test.dart`
- **Verification:** counts 3, 1, 1, 15, 1, 1, 1 — each measured by making the mutation, running, and restoring from a copy.
- **Committed in:** `d78da63`

**3. [Rule 1 - Bug in the verification method] The mutation counter was reporting 0 for a mutation that broke three rows**
- **Found during:** Task 2 (measuring control 33)
- **Issue:** `dart test --reporter=compact | grep -cE '\[E\]$'` returned `0` for control 33. The compact reporter rewrites a single line with carriage returns, so `[E]` never reaches a line end. A gate built on it reports success for every mutation — and the baseline reads 0 too, so the sanity check passes.
- **Fix:** Counter rebuilt on `--reporter=json`, counting non-`success` `testDone` events; the true count for control 33 is 3. Every count in 33-39 was taken that way, and the hazard is recorded in the suite's head doc and in `WINDOWS.md` 27 so a later plan does not repeat it.
- **Verification:** the same counter reads `FAILURES=0` at baseline and moves for each mutation.
- **Committed in:** `d78da63`

---

**Total deviations:** 3 (1 stale plan fact, 1 missing critical verification, 1 bug in the verification method).
**Impact on plan:** No production behaviour differs from the plan. All three are verification-side: two strengthen the evidence, one corrects a counting method that would have certified broken code as green. No prohibition was reached, no frozen declaration touched, and no scope added to `lib/`.

## Issues Encountered

- **`AbsentKeyboardFocusWitness` needed a row, not just a wiring grep.** The plan pins the Wayland arm by wiring. A null object that answered `true` would disable CAP-14 on every non-X11 host and no wiring grep would see it, so the "cannot answer" row is driven through the real `AbsentKeyboardFocusWitness` rather than through the fake. That also resolved what would otherwise have been a duplicate: the plan lists "witness reports moved" and "witness cannot answer" as two rows, but the seam collapses both to `false`, so at the fake they are the same configuration.
- **`_bodyOf(source, 'KeyboardFocusWitness')` matched the field declaration, not the method.** First attempt at the wiring pin scanned from `final KeyboardFocusWitness focusWitness;` and captured `bindHotkey`'s body. Keyed on `'static KeyboardFocusWitness _focusWitnessFor'` instead, and proved the pin non-vacuous by swapping the arms (1 failure).

## Verification

| Check | Result |
| --- | --- |
| `dart analyze --fatal-infos` | clean, no issues |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | `+974 ~2` — all passed |
| `flutter test --exclude-tags=live test/ui test/platform test/composition` | `+165 ~7` — all passed |
| `DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh hide` | `VERDICT=HIDE` (baseline `FLICKER`) |
| witness contains no window-taking Xlib call (comments stripped) | 0 matches |
| `lib/src/infrastructure/panel/` contains no timer or delay (comments stripped) | 0 matches |
| `panel_visibility.dart`, `global_hotkey.dart`, `x11_key_grab_registrar.dart` vs `7d42485` | all three hash-equal |
| `test/architecture/ad1_import_rule_test.dart` | passed |

The two skipped rows in the `dart test` set and the seven in the `flutter test` set are the pre-existing `live`/no-session skips; nothing skipped that was not skipped before.

## TDD Gate Compliance

Task 2 carries `tdd="true"`, and the RED/GREEN sequence is present in the log: `test(01-12)` `961fd61` precedes `feat(01-12)` `791ddb9`. No REFACTOR commit — no cleanup was warranted.

**One honest qualification.** Eight of the nine rows passed the moment they were written, because task 1 is a `type="tracer"` task and had already shipped their mechanism one commit earlier by design. Only the deferred-blur row was a true RED, and it failed for exactly its own reason (`Expected: true, Actual: <false>` at the post-release visibility assertion). The fail-first evidence for the other eight is the negative-control record — each fails under a measured mutation — which is this suite's established convention and a stronger guarantee than a RED run, since it names *which* line each row depends on. This is not a gate violation being excused: it is a structural consequence of the plan pairing a tracer with a TDD expansion task, and it is recorded so a reader does not mistake eight immediately-green rows for eight rows that prove nothing.

## Known Stubs

None. Every path added is reachable and exercised: the X11 witness by the probe route against a real X server, the null object by a unit row through the real adapter, and both selection arms by a text pin that fails when swapped.

## Threat Flags

None. The plan's `<threat_model>` covers the surface this plan adds, and the two `mitigate` rows are both implemented and pinned — T-01-61 by the single-Xlib-call grep, T-01-62 by four rows and by control 36's 15 failures. No new network endpoint, auth path, file access pattern or schema change was introduced; the one new external interaction is a read-only `XGetInputFocus` on a display the process already holds a connection to.

## Broken-windows ledger

Five entries appended to `.planning/WINDOWS.md`, all `open`:

| # | Kind | What |
| --- | --- | --- |
| 23 | deviation | Two stale `read_first` facts corrected; three named controls became seven |
| 24 | deviation | The deliberate foreign-grab behaviour change, measured — 01-14 owes the ledger entry |
| 25 | unrun-verify | T-01-60 and T-01-59 accepted on reasoning; neither measured |
| 26 | unrun-verify | The Wayland arm unobserved on a real Wayland session |
| 27 | deviation | The compact-reporter mutation-counting hazard |

## User Setup Required

None — no external service configuration required. The fix adds no dependency to `pubspec.yaml` and no Python requirement; `libX11.so.6` is already an unconditional `DT_NEEDED` of `libgdk-3.so.0`.

## Next Phase Readiness

**Ready for 01-13.** It has what it needs: the fix is in the tree, the release bundle is built, and the six-route table above is the post-fix measurement its two added routes refine. The one thing 01-13 must not assume is that the `foreign-grab` route still classifies `HIDE` — it classifies `NOTHING`, deliberately, and that is the route it was chartered to measure.

**Owed to 01-14** (ledger filing), all five stated above and in `WINDOWS.md`: the foreign-grab behaviour change, T-01-59, T-01-60, the unobserved Wayland arm, and the mutation-counting hazard.

**Nothing owed to Phase 7 / ARCH-06 by this plan.** No verbatim-frozen declaration was edited, so no spine reconciliation and no human ratification gate is added to the pile 01-01, 01-04, 01-06 and 01-09 already left there.

**One concern, not a blocker.** The whole live proof rests on Xvfb + openbox 3.6.1. That is a real X server and a real window manager, and it is what makes the `hide` verdict evidence rather than assertion — but a real GNOME or KDE session differs in focus-stealing prevention, compositing and grab handling. Coverage entry D7 routes that to a human, and `WINDOWS.md` 26 files the Wayland half of the same gap.

## Self-Check: PASSED

- `lib/src/infrastructure/panel/keyboard_focus_witness.dart` — FOUND
- `lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart` — FOUND
- `lib/src/infrastructure/panel/absent_keyboard_focus_witness.dart` — FOUND
- `test/fakes/fake_keyboard_focus_witness.dart` — FOUND
- `dc6079b` — FOUND
- `961fd61` — FOUND
- `791ddb9` — FOUND
- `d78da63` — FOUND

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-10*
