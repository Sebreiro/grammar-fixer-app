---
phase: 01-hotkey-truth
plan: 03
subsystem: infra
tags: [x11, xlib, dart-ffi, hotkey, grab, ad-10, ad-12, d-10]

# Dependency graph
requires:
  - phase: 01-02
    provides: "X11KeyGrabRegistrar — the dart:ffi/isolate seam whose grab choreography this plan inverts, and the HotkeyRegistrar contract it rewrote"
provides:
  - "A non-destructive X11 bind path: a grab another application owns is refused with the previously working shortcut still grabbed and still firing (D-10, HOTKEY-01)"
  - "HotkeyRegistrar.grab's inverted guarantee: a rejected grab has released nothing"
  - "Acquire-then-confirm-then-release grab semantics in X11KeyGrabRegistrar, with a refused acquisition putting back exactly what it took"
  - "An already-held short-circuit compared against what is HELD, never against what was REQUESTED, so a refused or lost binding can always be re-requested"
  - "Three newly measured X facts that correct standing doc claims (see Deviation 2)"
affects: [01-04, 01-06, 01-07, 01-10, phase-02-settings]

# Actuals (#2632) — estimateTokens scale (chars/4) over the files actually changed.
actuals:
  tokens: 34661
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Atomic swap at a platform seam: resolve, acquire, confirm, then release — so the failure path costs the caller nothing"
    - "An idempotence short-circuit compared against confirmed state rather than against the request, so no recovery path is closed"
    - "A refusal helper that reads what is actually in effect before choosing between 'unavailable' and 'the previous binding' — one home for the answer (_abandonedRebind), one guard per call site with its own sentence"
    - "Re-pointing a test row whose exercised path became unreachable at the claim it was making, rather than deleting it"

key-files:
  created: []
  modified:
    - "lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart"
    - "lib/src/infrastructure/hotkey/x11_global_hotkey.dart"
    - "lib/src/infrastructure/hotkey/hotkey_registrar.dart"
    - "lib/src/ui/settings/hotkey_status_view.dart"
    - "test/infrastructure/hotkey/x11_global_hotkey_test.dart"
    - "test/infrastructure/system/daemon_startup_test.dart"
    - "test/fakes/fake_hotkey_registrar.dart"

key-decisions:
  - "The swap lives in the seam, not in the adapter: only the implementation can acquire, confirm and release without ever being in either bad state, so `HotkeyRegistrar.grab` owns it and the adapter issues no bare release on the bind path."
  - "The already-held short-circuit was kept — but for a different reason than the plan gave. Measured: X does NOT refuse a self re-grab; it accepts it, produces no second grab, and one XUngrabKey removes it. So an identical rebind without the short-circuit would acquire nothing and then ungrab the grab it just re-took, leaving the user with no shortcut at all."
  - "The conservative any-BadAccess-is-refusal reading in _acquire is unchanged. The plan's lock-variant degradation branch rests on a false premise about plan 01-02's code and is not implementable in this file without four extra XSync round trips and a Logger the seam deliberately does not have (Deviation 3)."
  - "The abandoned path gets an error log, not a user-facing message — exactly as _refusedBeforeBackend does. The user sees HotkeyBound naming their old combination, and the settings surface renders 'In effect: <old>' plus 'That differs from your preference, <requested>'."
  - "Doc claims this plan's own measurements falsified were corrected in place rather than left standing, including one carried over from plan 01-02."

patterns-established:
  - "A flagged assumption cheap enough to settle is settled: five minutes of Xvfb replaced 'X reports BadAccess for a self re-grab' with a measurement that inverted it and changed the reason the code is shaped as it is"
  - "A test row whose exercised path becomes unreachable is re-pointed at the reachable form of the same claim, and the re-point says so in the row's own comment"

requirements-completed: [HOTKEY-01]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "On X11, applying a combination another application already owns leaves the previously working shortcut still grabbed and still opening the panel"
    requirement: "HOTKEY-01"
    verification:
      - kind: manual_procedural
        ref: "live Xvfb :77 — independent ctypes client holds Ctrl+Shift+G on all four ignored-modifier states; X11GlobalHotkey over the real X11KeyGrabRegistrar binds Alt+Q (1 activation via xdotool), then binds Ctrl+Shift+G => 'BOUND effective=[alt]+Q authority=application' + error log 'the X11 key grab was refused, so the rebind was abandoned...'; pressing Alt+Q again => 1 activation; pressing Ctrl+Shift+G => 0 activations"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#D-10, AD-10: a grab the seam refuses mid-rebind abandons the rebind and reports the combination that is still live"
        status: pass
    human_judgment: false
  - id: D2
    description: "HotkeyUnavailable is reached from the X11 bind path only when nothing is held; when something is held a refused rebind returns HotkeyBound naming it and logs the abandonment"
    requirement: "HOTKEY-01"
    verification:
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#AD-12: a refused grab with nothing held is a value, and logs the error type only"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#D-10, AD-10: ... reports the combination that is still live (asserts errors().single.message contains 'abandoned')"
        status: pass
      - kind: other
        ref: "awk '/await _registrar.grab/,/^  }$/' x11_global_hotkey.dart | grep -c HotkeyBound => 2; grep -c _releaseBeforeRebinding => 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "At most one combination is grabbed at a time — a successful rebind releases the previous grab, and a refused one releases nothing"
    verification:
      - kind: manual_procedural
        ref: "live Xvfb :77 — after rebinding Ctrl+Shift+G -> Alt+Q, pressing Ctrl+Shift+G produces 0 activations and pressing Alt+Q produces 1; the acquisition precedes the ungrab in source order (_acquire at :703, _ungrabHeld at :711)"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#CAP-12: a rebind is one atomic swap inside the seam (expects the grab alone, no bare release)"
        status: pass
    human_judgment: false
  - id: D4
    description: "A rebind to the combination already held succeeds rather than being short-circuited away, so a binding that was refused or lost can always be asked for again"
    verification:
      - kind: manual_procedural
        ref: "live Xvfb :77 — binding Alt+Q twice in a row leaves it still firing (1 activation after the second bind); and after the conflicting client exited, Ctrl+Shift+G bound and fired, proving the earlier refusal was never recorded as held"
        status: pass
      - kind: unit
        ref: "test/infrastructure/hotkey/x11_global_hotkey_test.dart#CAP-12: rebinding to the same combination still reaches the seam + #AD-12: a refused grab is never recorded as effective"
        status: pass
    human_judgment: false
  - id: D5
    description: "The settings surface states what is actually in effect and that it differs from the preference, rather than that the hotkey is inactive"
    verification:
      - kind: automated_ui
        ref: "test/ui/settings/settings_screen_hotkey_test.dart#A4 AD-10: when the backend chose something else, both the preference and what is in effect are shown and distinguished ('In effect: …' + 'differs from your preference, Ctrl+Shift+G')"
        status: pass
    human_judgment: true
    rationale: "The rendering path is pinned by an existing widget test and the outcome feeding it is now proved live, but the surface still does not say *why* the request did not take (\"that combination is taken\") — it says what is in effect and that it differs. Carrying a refusal reason alongside a HotkeyBound needs the port-surface additions plans 01-04 and 01-06 own. A human looking at a real GUI session is also still owed (see Owed observations)."
  - id: D6
    description: "No test row was deleted and none added; the suite pins the new choreography with the same number of claims"
    verification:
      - kind: other
        ref: "grep -c '    test(' x11_global_hotkey_test.dart => 25 before and after; git diff --stat => 122 insertions / 59 deletions; file grew 741 -> 804 lines; grep -c \"'release()', 'grab(\" => 0; grep -c \"'release()', 'dispose()'\" => 2"
        status: pass
    human_judgment: false
  - id: D7
    description: "The baseline suites are unregressed at exactly the numbers measured on HEAD 9c91fe8"
    verification:
      - kind: integration
        ref: "dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart => 946 passed / 2 skipped / 0 failed"
        status: pass
      - kind: integration
        ref: "flutter test --exclude-tags=live test/ui test/platform test/composition => 165 passed / 7 skipped / 0 failed"
        status: pass
      - kind: other
        ref: "dart analyze --fatal-infos => No issues found!"
        status: pass
    human_judgment: false

# Metrics
duration: 20 min
completed: 2026-09-01
status: complete
---

# Phase 1 Plan 03: A Refused Rebind That Costs the User Nothing Summary

**`X11KeyGrabRegistrar` now acquires the new grab, confirms it against the server, and only then ungrabs the old one — so a combination another application owns is refused with the previous shortcut still held and still opening the panel, proved live under `Xvfb :77` with an independent client holding the conflict; `_releaseBeforeRebinding`, which dropped the working grab on its way to failing, is gone.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-09-01T17:05:13Z
- **Completed:** 2026-09-01T17:25:12Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- **D-10 is proved, not argued.** With an independent `ctypes` client holding `Ctrl+Shift+G` on all four ignored-modifier states, the daemon bound to `Alt+Q`, then applied `Ctrl+Shift+G`: the adapter returned `BOUND effective=[alt]+Q authority=application`, logged the abandonment, and `Alt+Q` still delivered an activation on the very next press. On the shipped code that same sequence returned `HotkeyUnavailable` **and** had already released `Alt+Q` — the user lost a shortcut they never asked to give up.
- **`HotkeyUnavailable` is now reachable from the X11 bind path only when nothing is held.** The grab-refusal arm reads `_effective` first and routes through the same "only when nothing is held" rule `_refusedBeforeBackend` had already documented at length (T-01-12). Both paths end at one helper, `_abandonedRebind`.
- **The recovery path is open and measured.** After the conflicting client exited, the same `Ctrl+Shift+G` request bound and fired — because a refusal is never recorded as held, and the seam's idempotence check compares against what is *held*, never against what was *requested* (T-01-15).
- **A flagged assumption was settled in five minutes and came back false**, which changed the reason the code is shaped as it is rather than the shape. X does not refuse a client re-grabbing its own combination; it accepts it, creates no second grab, and one `XUngrabKey` removes it. So the short-circuit is not cosmetic protection against a spurious conflict — it is what stops an idempotent rebind from acquiring nothing and then ungrabbing the grab it just re-took, silently leaving the user with no shortcut.
- **Every test row was re-pointed, none deleted, none added.** `test(` count 25 before and after; the file grew 741 → 804 lines. Two rows whose exercised path became unreachable were re-pointed at the reachable form of the same claim, and each says so in its own comment.
- **Both baselines are exactly unregressed:** 946/2/0 on the dart side, 165/7/0 on the flutter side, `dart analyze --fatal-infos` clean.

## Task Commits

1. **Task 1: Acquire before releasing, so a refused grab keeps the shortcut that was working** — `4e745a9` (fix)
2. **Task 2: Re-point the ordering rows that pin the old release-first choreography** — `591d311` (test)

## Files Created/Modified

- `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart` — the worker's `_grab` resolves the keycode, short-circuits an already-held combination, calls the new `_acquire` (which takes all four states, `XSync`s, reads the trap, and on refusal puts back exactly what it took **without touching what is held**), and only then `_ungrabHeld`s the previous combination and records the new one. `_takeGrab` became `_acquire` returning `({String? refusal, List<int> states})`; `_ungrabStates` was extracted so a partial acquisition can be undone precisely. `_onMappingChanged` follows the same order. The main-isolate `grab()` no longer calls `_releaseHeld()`.
- `lib/src/infrastructure/hotkey/hotkey_registrar.dart` — `grab()`'s doc inverted: it no longer says the backend releases what was held *first*, and states that a rejected grab has released nothing and why the swap must live in the implementation.
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` — the pre-release call, its guard, and `_releaseBeforeRebinding` (48 lines) are gone; the helper's two load-bearing facts are re-homed as a comment at the new call site; the `on Object catch` arm chooses between `HotkeyUnavailable` and `_abandonedRebind(stillInEffect)`; the class doc's falsified keybinder paragraph is refreshed.
- `lib/src/ui/settings/hotkey_status_view.dart` — one doc phrase citing the now-unreachable refused-release path (Deviation 4).
- `test/infrastructure/hotkey/x11_global_hotkey_test.dart` — nine rows re-pointed (see Task 2's commit message for the row-by-row map).
- `test/infrastructure/system/daemon_startup_test.dart` — the AD-9 registrar-identity row's expected call list (Deviation 4).
- `test/fakes/fake_hotkey_registrar.dart` — the contract paragraph explaining what call *order* pins, inverted (Deviation 4).

## The measurements, since the seam has no automated test

Run against a live `Xvfb :77` in this container on 2026-09-01. The first three are new; they correct standing doc claims.

| Measurement | Result |
|---|---|
| conn 1 grabs `Ctrl+Shift+G` | `errors=[]` → HELD |
| **conn 1 grabs the same combination again** | `errors=[]` → **accepted, no `BadAccess`** |
| conn 2 (another client) grabs it | `errors=[(10, 33)]` → REFUSED (`BadAccess`/`X_GrabKey`) |
| conn 1 grabs it twice, then **one** `XUngrabKey`; conn 2 retries | conn 2 → HELD, so **one ungrab removed the grab entirely despite two `XGrabKey` calls** |
| conn 1 releases; conn 2 retries | HELD (refusal is not sticky) |

And the seam end to end, through `X11GlobalHotkey` over the real `X11KeyGrabRegistrar`, with the conflict held by an independent client (presses synthesised with `xdotool`, which uses XTEST):

```text
1. bind Alt+Q                    -> BOUND effective=[alt]+Q authority=application
   press alt+q                   -> 1 activation
2. bind Ctrl+Shift+G (taken)     -> [error] the X11 key grab was refused, so the rebind was
                                     abandoned and the previous combination is still in effect
                                     {error_type: StateError}
                                  -> BOUND effective=[alt]+Q authority=application
   press alt+q AGAIN             -> 1 activation      <-- the shortcut was not spent on the refusal
   press ctrl+shift+g            -> 0 activations     <-- it is not ours, correctly
3. bind Alt+Q again (idempotent) -> BOUND effective=[alt]+Q
   press alt+q                   -> 1 activation      <-- the short-circuit's whole payoff
--- conflicting client exits ---
4. bind Ctrl+Shift+G             -> BOUND effective=[control, shift]+G
   press ctrl+shift+g            -> 1 activation      <-- recovery path open
5. rebind to Alt+Q               -> BOUND effective=[alt]+Q
   press alt+q                   -> 1 activation
   press ctrl+shift+g            -> 0 activations     <-- exactly one combination held
```

The probe was a throwaway (`tool/_x11_d10_probe.dart`) and was deleted before the commit; the two Python clients live in the session scratchpad, not the repo.

## Decisions Made

All five are in the frontmatter. Two deserve the argument in full:

**Why the short-circuit stayed after its premise failed.** The plan justified comparing against the held combination with "X answers `BadAccess` when a client grabs a combination it already holds itself". That is false on this server. But removing the short-circuit would have been worse than leaving it: acquire-then-release on an identical rebind acquires nothing new (X accepts the duplicate silently and keeps one grab) and then ungrabs "the previous" combination — which is the same grab. The user's shortcut would disappear on the most ordinary rebind there is, silently, with `HotkeyBound` reported. The short-circuit is load-bearing for a reason the plan did not anticipate, and the code and its comment now say the measured reason rather than the assumed one.

**Why the abandoned path carries no message.** `HotkeyBound` has no message field, and adding one is plan 01-04's and 01-06's territory (`HotkeyUnavailable`'s cause, and `HotkeyStatus? get current`). So the abandonment is an error log, and the user's evidence is the surface: `In effect: Alt+Q` plus `That differs from your preference, Ctrl+Shift+G.` That is true, and it is no longer the false "the hotkey is inactive". It is not yet "that combination is taken" — see the honest gap under Owed observations.

## Deviations from Plan

### 1. [Rule 1 — Bug] An acceptance criterion the plan's own deletion would have broken

- **Found during:** Task 1, before editing.
- **Issue:** Criterion 3 required `grep -c 'tray menu still opens the panel'` to be **at least 4**. The baseline was exactly 4 — and one of those four occurrences lived inside `_releaseBeforeRebinding`, which the same task orders deleted. A correct implementation would have printed 3. The criterion's intent ("every `HotkeyUnavailable` message literal still ends with a clause naming the tray menu") was satisfiable; its measurement was not, because a fifth message literal (line 121's) carries the phrase split across two source lines, so the grep never counted it.
- **Fix:** Re-wrapped that existing literal's line break so the clause sits on one line — the message text is byte-identical, no behaviour changes, and the guardrail now genuinely counts what it intends. Count is 4, and there are exactly 4 `HotkeyUnavailable` message literals in the file, each ending by naming the tray. No padding was added and the criterion was not substituted.
- **Verification:** `grep -c` → 4; every `HotkeyUnavailable(` site enumerated and checked by hand.
- **Committed in:** `4e745a9`.

### 2. [Rule 1 — Bug] Two doc claims falsified by this plan's own measurements

- **Found during:** Task 1, settling the plan's flagged assumption under `Xvfb`.
- **Issue:** `x11_key_grab_registrar.dart`'s class-doc fact 1 asserted "two `XGrabKey` calls on one combination are two grabs, and X delivers to both" as the current-route reason for releasing before grabbing. Measured false: a duplicate self-grab is accepted, produces one grab, and one `XUngrabKey` removes it. The plan's own action text, `must_haves` prohibition and threat T-01-13 all restate that premise, and the adapter's new call-site comment was going to inherit it.
- **Fix:** Fact 1 rewritten with the three measurements and their dates; the plugin-level origin of the double-fire (two handlers from a `std::map::insert` that does not overwrite, which really did make AD-8's toggle show and immediately hide) is preserved as history rather than asserted as the X-level mechanism. The adapter's call-site comment carries the AD-8-toggle fact the plan's criterion requires **and** the correction. **The required behaviour did not change** — at most one combination held at a time, which is what the prohibition demands, and which the live probe confirms (step 5 above).
- **Committed in:** `4e745a9`.

### 3. [Recorded, not implemented] The lock-variant degradation branch rests on a false premise

- **Found during:** Task 1, reading `_takeGrab` as plan 01-02 left it.
- **Issue:** The plan's action names an edge case to handle: "A lock-mask variant refused while the base state succeeded. Keep the grab, log the degradation naming which state failed, and resolve … it is the documented behaviour plan 01-02 already carries." Plan 01-02 carries the **opposite**, explicitly and with its reasoning in the code: one `XSync` covers all four grabs, X reports the failing *request* and not which state it was, so "a `BadAccess` anywhere in the batch is read as the base state being taken … the conservative reading and the right one". The premise comes from `01-RESEARCH.md`'s skeleton (step 5), which was not implemented as written.
- **Why not implemented:** attributing the failure to one state needs four separate `XSync` round trips instead of one, and "log the degradation" is impossible in that file — `X11KeyGrabRegistrar` deliberately takes no `Logger` (plan 01-02, coverage item D8), and surfacing it upward would mean `grab()` resolving with a value instead of `void`, i.e. a port-shape change plans 01-04/01-06 own. No `must_haves` truth and no acceptance criterion touches lock-variant degradation.
- **Where it stands:** the conservative refusal is unchanged, and its cost fell sharply — refusing on a lock-variant `BadAccess` now leaves the user's existing shortcut working, where before it destroyed it. Recorded here rather than worked around silently.

### 4. [Rule 3 — Blocking] Three files outside the plan's declared set had to move with the change

- **Found during:** Task 2, at its own gates.
- **Issue and fix:**
  - `test/infrastructure/system/daemon_startup_test.dart:260` asserted `['release()', 'grab(...)']` for the AD-9 registrar-identity row and failed for the same one reason. Leading `release()` dropped; the row's claim (the registrar `main.dart` built is the one the adapter grabs through) is untouched.
  - `test/fakes/fake_hotkey_registrar.dart`'s class doc stated the contract this plan inverts — "A rebind must release *before* it grabs" — as the reason the fake records order rather than a set. Rewritten to state the new invariant, so the fake still explains why it is sequence-shaped.
  - `lib/src/ui/settings/hotkey_status_view.dart` cited "a rebind whose release the backend refused" as its example of an outcome carrying the previous combination. That path is now unreachable; one phrase re-pointed at the refused *grab*. The claim, and the rendering, are unchanged.
- **Verification:** full scoped runs green (946/2/0 and 165/7/0).
- **Committed in:** `591d311`.

### 5. [Rule 1 — Bug] The plan misclassified the two teardown-race rows as untouchable

- **Found during:** Task 2 row walk.
- **Issue:** Task 2 says the teardown-race rows "around `:415-487`" are about `dispose()`, must be left unchanged, and that a failure there "is a bug in Task 1". Both failed — but on their **first** list element, the bind's leading `release()`, not on any disposal entry. They are mixed rows: they assert a bind's calls and a teardown's calls in one list.
- **Fix:** dropped only the leading `release()` from each. Their three and two trailing teardown entries are byte-identical, which is itself the evidence Task 1 did not change disposal behaviour — and the two pure disposal rows (`['release()', 'dispose()']` at what are now `:716` and `:738`) passed untouched throughout.
- **Committed in:** `591d311`.

### 6. [Re-pointed, recorded as the plan asks] One row had no successor in its original form

- `AD-12: a grab refused after a successful release leaves nothing reported as effective` built its state through a *successful* release mid-rebind. That sequence is now unreachable by construction — the release only happens after a confirmed acquisition, so a refusal can never empty `_effective`. Per the plan's instruction the row was **not** deleted: it is re-pointed at the reachable form of the same claim (a refusal is never recorded as held, so the identical request can be re-made and succeed) and renamed `AD-12: a refused grab is never recorded as effective, so the same combination can always be asked for again`. Its comment states what it used to drive and why that is gone.
- The `AD-15` ThrowingLogger row had the same problem in a sub-case the plan's "walk every `expect(registrar.calls, …)`" pass does not reach (it asserts no call list). Its refused-release sub-case became the abandoned rebind — which is strictly better coverage, because that is the one path that logs *while returning a success value*.

---

**Total deviations:** 4 auto-fixed (2 bugs, 1 blocking, 1 broken criterion) + 1 recorded-not-implemented + 1 row with no direct successor.
**Impact on plan:** No scope creep in behaviour — the production change is exactly the choreography the plan specifies, in the three files it names. Two deviations are corrections to the plan's own factual premises, both surfaced rather than absorbed; one is a criterion the plan's own deletion would have failed, fixed by making the guardrail measurable instead of by substituting it.

## Issues Encountered

- **The plan's `stillInEffect` verify check and its "sibling helper" suggestion pull in opposite directions.** The check requires `stillInEffect` to appear *inside* the region between the `_registrar.grab` call and the end of `_bind`; a sibling helper (which the action offers as one of two clean shapes) would put it in the sibling instead. Resolved by keeping the two-line guard at each call site with its own log sentence and factoring the shared *answer* into `_abandonedRebind` — one home for the AD-10 outcome, no divergent copies of the rule, and the check measures the arm it was written for rather than a helper. Both readings of the plan's intent are satisfied.
- **Stale `keybinder` wording survives inside the protected region.** `x11_global_hotkey.dart`'s `_queue` doc (pre-change lines 65-105) still explains the serialization hazard in terms of keybinder's `std::map`, and the `bindingChanges` doc still says "a keybinder grab". Acceptance criterion 4 forbids any hunk in that range, so both were left exactly as they are; one test row name inherits the same wording. Handed off below rather than fixed.
- **`pkill -f "Xvfb :77"` kills the shell that started it** (01-02 recorded this; confirmed again). `pkill -x Xvfb` is the working form.

## Owed observations — recorded as owed, never as passed

1. **D-10 seen by a human on a real GUI session.** The `<human-check>` asks for Settings opened, `Ctrl+Shift+G` applied against a live conflict, and the original shortcut pressed to confirm. Everything except the human's eyes is done and recorded above: the outcome, the log line and the surviving grab are all measured live, and the rendering that outcome produces is pinned by `settings_screen_hotkey_test.dart#A4 AD-10`. What is **not** observed is the assembled GUI — this container has no session with a StatusNotifier host, which is the same limit plan 01-02 recorded for its owed item 1. Appended to `.planning/WINDOWS.md` as entry 3 (`unrun-verify`, phase 01).
2. **The surface says what is in effect, not that the request was taken.** `must_haves` truth 1 asks the settings screen to state "the new combination is taken". It states `In effect: <old>` and `That differs from your preference, <requested>` — true, informative, and no longer the false "inactive", but not the reason. `HotkeyBound` has no message field; carrying a refusal reason on a successful outcome is what plans **01-04** (`HotkeyUnavailable`'s cause) and **01-06** (`HotkeyStatus? get current`) exist for. Half of truth 1 is delivered and proved; this half is theirs.

## Hand-offs

- **Plan 01-04** owns the `HotkeyUnavailable` construction sites, which this plan deliberately left structurally alone (the plan says so explicitly). There are now **three** construction sites in `x11_global_hotkey.dart`, not two: the grab-refusal arm's nothing-held branch is new. Also see Owed observation 2 — the abandoned path is where a "your request was refused because X" cause would actually help.
- **Plan 01-06** (`HotkeyStatus? get current`): `_effective` is the adapter's record of what is held, and it is now assigned **only** after a confirmed grab and never cleared by a refusal. `dispose()` does not clear it, which is safe because every reader is behind the `_disposed` check — worth knowing if `current` becomes a reader that is not.
- **Plan 01-07** (press-to-capture, `hotkey_key_catalogue.dart`): the keypad-variant rows at what are now `:262-286` and `:349-381` were left untouched, as instructed. The virtual-modifier table in 01-02's summary is unchanged by this plan.
- **Plan 01-10** (ledger): DW-39's supersession note is still owed by 01-10 and was not touched here. Nothing in this plan closes or opens a ledger entry.
- **Stale keybinder wording in the protected region** of `x11_global_hotkey.dart` (`_queue` doc, `bindingChanges` doc) and in one test row name. Whoever next owns that file's head should re-point them; this plan was forbidden from touching lines 65-105.
- **The FFI seam still has no automated test** and now has more logic in it (the swap, the short-circuit, the precise partial undo). The measurements above are the evidence; CI will not catch a regression here. That risk is unchanged in kind from 01-02 and larger in surface.

## Known Stubs

None. No placeholder, no hardcoded empty value, no deferred wiring — every path this plan touches is implemented and exercised.

## Threat Flags

None new. The plan's register was honoured: **T-01-12** (repudiation) mitigated and pinned by a source assertion on the refusal arm plus two suite rows; **T-01-13** (double-hold) mitigated by the swap and confirmed live — pressing the old combination after a rebind produces zero activations; **T-01-14** (orphaned partial acquisition) mitigated by `_ungrabStates` putting back exactly the states taken, on the measured idempotence of `XUngrabKey`; **T-01-15** (a rebind that can never be re-requested) mitigated by comparing against what is held, and measured (step 4 of the probe); **T-01-16** (log context) held — the abandonment log carries `{'error_type': 'StateError'}` only, and the abandoned-before-backend log carries `{'refused_key': key}`, a key label. No new network endpoint, auth path, file access or schema change.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Ready for the rest of wave 3+.** The bind path is now non-destructive on both halves of the tracer's promise, both gate suites sit exactly on the 2026-09-01 baseline, and the seam contract states the guarantee later plans will be written against.
- **One residual risk, named rather than assumed away:** the atomic swap's correctness rests on facts about one X server (`Xvfb` in this container). The three measurements are recorded above with their commands so a real-session run can contradict them cheaply. If `Mod2Mask` is not NumLock on some host (assumption A2, carried from 01-02), the lock-variant branch this plan touched degrades exactly as 01-02 documented.

## Self-Check: PASSED

- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` — FOUND, `_releaseBeforeRebinding` count 0
- `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart` — FOUND, `_acquire` precedes `_ungrabHeld` in source order
- `lib/src/infrastructure/hotkey/hotkey_registrar.dart` — FOUND, `grab()` doc states "a rejected [grab] has released nothing"
- `test/infrastructure/hotkey/x11_global_hotkey_test.dart` — FOUND, 25 `test(` declarations, 0 release-then-grab rows, 2 disposal rows
- Commits `4e745a9`, `591d311` — both FOUND in `git log --oneline --all`
- `git diff --diff-filter=D HEAD~2 HEAD` — empty; no file deleted
- Throwaway probe `tool/_x11_d10_probe.dart` — GONE (intended); `git status` clean across every path this plan touched

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-01*
