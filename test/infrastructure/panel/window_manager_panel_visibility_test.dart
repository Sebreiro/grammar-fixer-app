import 'dart:async';

import 'package:hotkey_grammar_corrector/src/application/panel_controller.dart';
import 'package:hotkey_grammar_corrector/src/domain/panel/panel_visibility.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/absent_keyboard_focus_witness.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/window_manager_panel_visibility.dart';
import 'package:test/test.dart';

import '../../fakes/fake_global_hotkey.dart';
import '../../fakes/fake_keyboard_focus_witness.dart';
import '../../fakes/fake_logger.dart';
import '../../fakes/fake_panel_window.dart';
import '../../fakes/throwing_logger.dart';

/// The bound for every row where the bound is **not** what is under test.
///
/// Deliberately unreachable rather than merely generous. Most rows here park a
/// call on purpose and settle it several statements later, so a bound they
/// could reach under load would quietly turn them into abandonment rows that
/// still pass — the mirror ends in the same place, and the row would be
/// certifying behaviour it never exercised. Nothing in this suite waits on a
/// timer, so no honest row comes within minutes of this.
const Duration _ampleBound = Duration(minutes: 5);

/// The bound for the rows where reaching it *is* the behaviour under test.
///
/// Short, because those rows wait it out in real time — and no shorter, because
/// two of them also require a follow-up call to land inside it while a dozen
/// other suites share the machine.
const Duration _stallBound = Duration(seconds: 1);

/// AD-8's visibility mirror, over a window that lags.
///
/// Every row that ends in a settled window asserts
/// `window.visible == visibility.isVisible`. That single pairing is what makes
/// this suite able to fail for the real defect: the reverted attempt kept a
/// correct mirror over a panel that was still on screen, and a suite that
/// asserted only the mirror certified it green.
///
/// **Negative controls.** Thirty-nine mutations of
/// `window_manager_panel_visibility.dart` were applied to this tree, this file
/// re-run against each, and each reverted **from a copy** rather than with
/// `git checkout --`, which would have discarded the work under review along
/// with the mutation. Each is stated as the exact edit, and every count is
/// failures *in this file* over a baseline confirmed green first — 90 rows, all
/// passing — because a count no one can reproduce is not evidence, and a run
/// whose baseline was never checked reports the same number for every gate.
///
/// Both numbers in that sentence are counted, not carried: it read
/// "Thirty-one mutations" and "80 rows" while the list below already reached
/// 32, which is the drift a prose count acquires the moment an entry is
/// appended without re-reading the header. The row count is the harness's own
/// `testDone` total for this file, and the mutation count is the number of
/// entries below.
///
/// **The counts in 33-39 were taken with a JSON-reporter counter, and that is
/// not a detail.** A `grep -c '\[E\]'` over the compact reporter's output
/// reports **0 failures for every mutation**, because the compact reporter
/// rewrites one line with carriage returns and the failure markers never reach
/// a line end. The first measurement of control 33 came back 0 that way and was
/// only caught because a 0 there contradicted the row that had just been
/// watched to fail. Count from `testDone` events, or the gate reports success
/// for a mutation that broke three rows.
///
/// Two reading notes, because DW-30 moved two bodies without moving their
/// behaviour. `hide()` is now a one-line delegation to
/// `_hide(PanelVisibilityState.dismissed)`, so every entry below that names
/// `hide()` — a line "in `hide()`", or the method itself — means `_hide`; the
/// departure is the only thing the two routes into it disagree about, and
/// `hide()` no longer has a body for a line to be deleted from. And
/// `_setMirror`'s departure half is now `_reportDeparture`, so every entry that
/// names `_setMirror` below the `_visible` write — again, a line or the method —
/// means `_reportDeparture`. The one exception is control 32, which names
/// `_setMirror`'s `shown` path explicitly because that is the copy of the line
/// that stayed behind; where an entry could mean either, it says which.
///
/// **How the zero counts were taken, and why that needed saying.** A "0" from
/// this harness and a stale build are indistinguishable from the outside, and
/// one entry here was previously wrong in its *reasoning* as well as its count
/// — control 20 claimed unpinnability from a premise that did not hold. So
/// every control recorded as 0 below was re-measured immediately after a
/// **canary** run (control 2, the `_reconcile` guard) over the same tree and
/// toolchain: the canary moved the count to 8 each time, which is what makes
/// the 0 beside it a measurement rather than an artefact. Each remaining 0
/// carries a **falsifiable** reason it cannot be pinned — a concrete state
/// whose existence would disprove it — rather than a note that no row happens
/// to cover it.
///
/// 1. `show()`/`hide()` rewritten to
///    `return _enqueue(v).whenComplete(() => _setMirror(v));`, so the mirror
///    is assigned *after* the first await rather than before it — 46 failures
/// 2. the `if (_outstanding > 0) return;` guard deleted from `_reconcile`
///    — 8 failures. Also this block's canary: it is the cheapest edit that
///    reaches many rows, so a run where it fails nothing is a stale build and
///    not a result.
/// 3. both superseded-request checks deleted (`if (_visible != intended)
///    return;` on entry to `_apply`, and the `_visible != intended` half of
///    the re-check between `show()` and `focus()`) — 6 failures
/// 4. serialisation removed (`_enqueue` reduced to `return _apply(intended);`)
///    — 4 failures
/// 5. the guarded `restore` arm changed from `_reconcile(true)` to
///    `_setMirror(true)`, so it walks past the guard — 4 failures: the restore
///    row itself and the three rows where the latch is at stake around it.
///    That coverage is what the adapter's doc calls load-bearing, and before
///    the restore row existed this mutation failed **zero**.
/// 6. the DW-33 focus requirement deleted from `_onBlur` — `heldFocus` dropped,
///    so the arm opens `if (!_visible) return;` again and answers a blur
///    whether or not the window ever took the keyboard — 4 failures. Five rows
///    here are titled DW-33; these are the four that turn on the *requirement*
///    — the bare-blur row, the trailing-focus row, the minimize/restore clear
///    and the blur-during-a-show row. The fifth, focus-regained-before-release,
///    is carried by the latch rather than by this guard and survives. Without
///    them the whole suite stays green while the panel dismisses itself on the
///    summon under any compositor with focus-stealing prevention, because every
///    other blur row here delivers a `focus` first or expects nothing to happen
///    anyway.
/// 7. the DW-32 latch deleted — `_deferredBlur = true` replaced by a bare
///    `return`, so a blur suppressed by `_outstanding` is dropped again as it
///    was before — 4 failures: the two latch rows, the deferred-refusal log row
///    and the abandoned-round-trip row in the DW-28 group.
/// 8. `minimize` routed back through `_reconcile(false)`, putting the
///    `_outstanding` guard in front of it — 5 failures: the DW-31 row, the
///    three rows built on the believed pair, and the minimize-voids-a-latched-
///    blur row. The guard has no echo to swallow on that arm, so it can only
///    discard the one signal an iconify produces at all.
/// 9. the `_visible` guard deleted from the `focus` arm, so a focus event is
///    recorded whatever the mirror says — 1 failure, the trailing-focus row.
/// 10. `_deferredBlur = false` deleted from `_setMirror` — **0 failures** alone;
///    pinned jointly, as control 22. Falsifiable reason: while the latch is set
///    the mirror necessarily reads true (that is a precondition of latching), so
///    every mirror transition reachable *after* a latch is true-to-false, and
///    each of those leaves `_visible` false at the release point where control
///    13's re-read answers it. A row failing for this line alone would need a
///    transition to `true` while the latch stands — that is, a mirror both true
///    (to have latched) and false (to transition up) at the same moment. Exhibit
///    one and this reason is wrong.
/// 11. the `_focused` clear in `_setMirror` made unreachable
///    (`if (!visible)` to `if (false)`) — 1 failure, the minimize/restore row.
///    Before that row this mutation failed **zero**: every other path to a
///    false mirror in this file goes through `_onBlur`, which clears the flag
///    itself.
/// 12. `!_visible ||` deleted from `_onBlur`'s first question — **0 failures**.
///    Falsifiable reason: `_focused` is written `true` only inside the `focus`
///    arm's `if (_visible)`, and is cleared by `_setMirror` on every
///    true-to-false transition and by `_onBlur` itself, so the state
///    `_focused && !_visible` is unreachable and the clause can never be the
///    sole cause of that return. Exhibit a path that leaves `_focused` set over
///    a false mirror and this reason is wrong. Kept because the two questions
///    are about different things and a reader should not have to derive one
///    from the other.
/// 13. `!_visible ||` deleted from `_releaseDeferredBlur` — **0 failures**
///    alone; pinned jointly, as control 22. Falsifiable reason: every route to
///    a false mirror drops the latch on its way through — `show()` and `hide()`
///    where the intent is expressed, `_setMirror` for the window-driven ones —
///    so a release that gets past `!_deferredBlur` always finds `_visible`
///    true. Exhibit a false mirror at the release point with the latch still
///    set and this reason is wrong.
/// 14. `_disposed ||` deleted from `_releaseDeferredBlur` — **0 failures**.
///    Falsifiable reason: the dismissal behind this guard is
///    [WindowManagerPanelVisibility._dismiss], which reaches the window only
///    through [WindowManagerPanelVisibility.hide], and that returns before
///    touching the seam once `_disposed` is set — so no window call can survive
///    the deletion. It becomes pinnable the moment a `_dismiss` route reaches
///    the seam directly, which is exactly why it is written down rather than
///    dropped.
/// 15. `_deferredBlur = false` deleted from `show()`, so a latch survives a
///    request that writes no mirror — 1 failure, the re-summon-that-moves-no-
///    mirror row, and nothing else. This is the gate for the defect a review
///    pass found still open after control 10's fix: `_setMirror` early-returns
///    when the value does not change, and `show()` on an already-visible panel
///    is both the request that does that and the request DW-32 exists for.
/// 16. the same deletion from `hide()` — **0 failures**. Falsifiable reason: a
///    latch requires a true mirror, and any intervening transition to false
///    drops it, so a `hide()` that reaches this line always finds the mirror
///    true and therefore always transitions — where control 10's clear covers
///    it. Exhibit a `hide()` with the latch set and the mirror already false
///    and this reason is wrong. (It follows that 10 and 16 are redundant with
///    each other too; the minimal set that fails a row is 10 with 13, which is
///    control 22.)
/// 17. the `minimize`/`restore` latch deleted — the `restore` arm reduced to
///    `_reconcile(true)` and the `_believedMinimize` arming removed, which is
///    the asymmetric split of the reverted 2026-08-15 attempt exactly — 3
///    failures: the symmetric-pair row, the blur-after-a-pair row and the
///    spent-latch row. Those three are what say the pair still cancels out
///    during one of our requests, and that CAP-14 outlives it.
/// 18. `_believedMinimize = false` deleted from `show()` — **0 failures** alone;
///    pinned jointly, as control 23. Falsifiable reason: `show()` leaves the
///    mirror reading true, so a latch consumed inside that request writes a
///    value the mirror already holds; the only ways back to false during it are
///    a `hide()`, which clears the latch itself (control 19), and a `minimize`,
///    which re-arms it. Exhibit a `restore` reaching the latch arm with the
///    mirror false, a latch armed before the `show()` and no `hide()` in
///    between, and this reason is wrong.
/// 19. the same deletion from `hide()` — 1 failure, the close-with-a-believed-
///    minimize row. That is the one route where the mirror is already false when
///    the intent is expressed, so `_setMirror` writes nothing and this clear is
///    the only thing standing between the deiconify echo and a mirror that
///    reads true over a window the user just closed.
/// 20. the latch armed by a `minimize` that moved no mirror (`if (_visible)`
///    to `if (true)`) — 1 failure, the minimize-that-moved-no-mirror row. **This
///    entry previously read 0 with the reason that the guarded arm "produces the
///    same value anyway", and that was wrong**: the guarded arm routes the
///    `restore` through `_reconcile`, which swallows it while `_outstanding` is
///    up, whereas the latch arm writes the mirror unconditionally — so the two
///    do not agree in the very state the condition is about. Armed
///    unconditionally, a `minimize` landing while our own queued `hide` has
///    already put the mirror down lets the show's deiconify echo consume the
///    latch, the queued hide then reads as superseded and issues nothing, and
///    the panel stays on screen: the stranded dismissal the whole latch design
///    exists to prevent. The condition does a second job in the same line, which
///    that reason also omitted — `hide()` writes the mirror false before calling
///    the window, so a compositor reporting `GDK_WINDOW_STATE_ICONIFIED` as part
///    of `gtk_widget_hide` cannot arm the latch off our own unmap either.
/// 21. the latch made sticky rather than one-shot (`_believedMinimize = false`
///    deleted from the `restore` arm) — **0 failures**. Falsifiable reason: a
///    stale latch can only be consumed by a later `restore`, and reaching one
///    with a false mirror requires a transition to false after the consumption
///    that neither re-arms the latch (a `minimize` does) nor clears it (`show()`,
///    `hide()` and every `_dismiss` route do) — and no such transition exists.
///    Exhibit one and this reason is wrong. The one-shot form is kept because
///    "there is a believed minimize still to undo" is the only thing the flag is
///    allowed to mean.
/// 22. controls 10 and 13 deleted **together** — 1 failure, the
///    minimize-voids-a-latched-blur row. Each cites the other as the mechanism
///    that makes it redundant, so before that row the pair was jointly unpinned:
///    a maintainer reading this record could have removed both and shipped a
///    behaviour change green. A `minimize` is the route that reaches both, being
///    the one transition to a false mirror that neither `show()` nor `hide()` is
///    involved in.
/// 23. controls 18 and 19 deleted **together** — 2 failures, the
///    stranded-queued-hide row and the close-with-a-believed-minimize row.
///    **Not the same shape as 22, and this entry previously said it was.** In 22
///    each line really is individually redundant given the other (0 and 0, 1
///    together). Here the counts are 0, 1 and 2: control 19 is individually
///    pinned — its own entry above states the row — so only `show()`'s clear is
///    redundant on its own, and what the pair adds beyond deleting 19 alone is
///    the stranded-queued-hide row. Re-measured on this tree against a baseline
///    confirmed green: 18 alone 0, 19 alone 1, both 2.
/// 24. `_releaseDeferredBlur` skipped on the abandoned path — a local flag set
///    when `_answered` returns false, and the release in `_apply`'s `finally`
///    made conditional on it — 1 failure, the abandoned-round-trip row in the
///    DW-28 group. That row is the only one here that latches a blur under a
///    call the window never answers, and it is what makes the `finally`
///    placement a decision: a release hung off the completion path leaves the
///    latch standing with nothing left to reconsider it.
/// 25. `_deferredBlur = false` deleted from `_releaseDeferredBlur` itself,
///    leaving the `_disposed || !_visible || _focused` guard intact — **0
///    failures**. Recorded because it is the one latch write this record
///    otherwise omitted while the field doc names it a writer, and an omitted
///    line is the one a maintainer can delete as dead with the file green.
///    Falsifiable reason: the only early return that can leave the latch set is
///    `_focused` (control 13 rules out `!_visible`, and `_disposed` admits no
///    further requests), and every later release is reached only through
///    `show()` or `hide()`, both of which drop the latch before enqueueing — so
///    a stale latch cannot survive to a later release and act there. Exhibit a
///    `_releaseDeferredBlur` call whose latch was set before the request that
///    reached it and this reason is wrong.
/// 26. `if (_outstanding == 0)` in `_apply`'s `finally` widened to `if (true)`,
///    so the release runs on every request's exit rather than on the chain
///    letting go — **0 failures**. Recorded for the same reason as 25: it is the
///    one conditional this change adds that the record otherwise omitted, and an
///    omitted line is the one a maintainer deletes as dead with the file green.
///    Falsifiable reason: mechanism two makes every request a link of `_queue`,
///    so exactly one `_apply` is ever in flight and this counter only ever holds
///    0 or 1 — the condition is vacuous on this tree and becomes load-bearing
///    only if concurrent `_apply` runs are ever allowed, which is what the
///    comment at the site says. Exhibit two `_apply` runs overlapping and this
///    reason is wrong.
/// 27. both focus-loss `_dismiss` calls changed to pass
///    `PanelVisibilityState.dismissed` instead of
///    `PanelVisibilityState.focusLost`, so CAP-14's own hide reports the
///    departure a *requested* hide reports (DW-30) — 6 failures: the two
///    attribution rows for the immediate and the latched route, the three
///    older CAP-14/DW-32 rows whose emission lists now name the departure, and
///    the DW-28 row control 31 also cites, because an abandoned hide carries
///    the departure it was issued under into its late echo. Recorded as 5 until
///    the follow-up pass re-measured it; the DW-28 row was the one missed. The
///    mutation moves no mirror and no window call, so before the emissions were
///    typed it failed **zero** while the summon after every click-away
///    discarded whatever the user had typed.
/// 28. `_reportDeparture`'s guard widened back to "did the mirror move?"
///    (`if (!_visible) { return; }`), which is what `_setMirror` did before this
///    change — 2 failures: the DW-30 group's close-after-an-iconify row and the
///    DW-31 latch row that pins the same sequence from the mirror's end. This is
///    the defect the first pass of DW-30 shipped: a dismissal landing over a
///    panel that was already away is swallowed, so the summon after an explicit
///    close hands back the session the user just closed, with the mirror and the
///    window both perfectly correct throughout.
/// 29. the same guard deleted outright, so a departure is re-announced even when
///    it repeats the standing one — 2 failures: the transition-only row in "the
///    mirror leads" and the DW-30 group's repeated-departure row. Measured
///    separately from 28 on purpose: one direction swallows news and the other
///    invents it, and one row cannot fail for both.
/// 30. the `minimize` arm's `_setMirror(PanelVisibilityState.iconified)` lifted
///    out of its `if (_visible)` block, so an iconify is attributed over a panel
///    that was already away — 1 failure: the DW-31 row for a minimize that moved
///    no mirror. That is the mirror image of DW-30 — a survivable departure
///    replacing a standing dismissal, so a hotkey dismissal followed by a stray
///    `GDK_WINDOW_STATE_ICONIFIED` would hand back the session the user closed —
///    and it is one of two arms that need the direction chosen for them; the
///    other is 31.
/// 31. the `if (_visible)` gate removed from the `hide` arm, so a `hide` event
///    reaches `_reconcile` over a panel that is already away — 1 failure: the
///    abandoned focus-loss row in the DW-28 group. This one was a live defect
///    rather than a hypothesis. The `hide` event is the GTK *widget* `hide`
///    signal (`window_manager_plugin.cc:1112` -> `on_window_hide`), so it can
///    only be an echo of one of our own calls — and a focus-loss hide abandoned
///    at the bound lets go of `_outstanding` while its call is in flight, so the
///    echo lands with nothing to swallow it and renames the standing `focusLost`
///    to `dismissed`. The next summon then discarded what the user had typed, on
///    the commonest departure there is.
/// 32. `_deferredBlur = false` deleted from `_setMirror`'s **`shown`** path —
///    **0 failures**. The second copy of that line, recorded on its own because
///    the split that created it left two lines a control could mean; 10 is the
///    other one. Falsifiable reason: `_deferredBlur` is only ever set while the
///    mirror reads true, and every route back to a false mirror clears it on the
///    way — `show()`, `_hide`, and `_reportDeparture` — so it cannot still be
///    standing when a false-to-true transition runs this line. Exhibit a latched
///    blur surviving a departure and this reason is wrong. Kept rather than
///    deleted because the rule it states is the same one `_reportDeparture`
///    states, and a reader should find it on both halves of the transition.
/// 33. the fourth question deleted from `_onBlur` — the
///    `if (_keyboardStillHere()) return;` block removed outright, which is
///    G-01-13's defect restored — **3 failures**: the unmoved-keyboard row, the
///    `_focused`-survives row, and the throwing-witness row. The third is worth
///    naming: with the question gone the witness is never read at all, so a row
///    asserting one read and one log line fails for the *absence* of the
///    question rather than for the dismissal — which is what makes it evidence
///    about the question and not only about the hide.
/// 34. the `_focused = false` clear moved back **above** the fourth question,
///    so a suppressed focus-out clears the flag the way the pre-fix arm did —
///    **1 failure**, the `_focused`-survives row. The one control that pins an
///    *ordering* rather than a line, and the reason the clear sits where it
///    does: UAT test 13 recorded presses 1 and 3 ending on
///    `FocusIn(NotifyUngrab)` and 2 and 4 on `FocusIn(NotifyNormal)`, so an arm
///    that cleared here would need a focus-in to come back to re-arm it, and
///    where GDK delivers no `NotifyUngrab` form the next *genuine* blur is
///    discarded by DW-33's question instead.
/// 35. the question deleted from `_releaseDeferredBlur` — **1 failure**, the
///    latched-blur-released-after-the-keyboard-came-back row. The half of the
///    fix that is easy to leave out, because `_onBlur` alone makes the `hide`
///    route work and the harness route pass: the latch reaches `_dismiss` past
///    `_onBlur`'s questions, not through them, so a grab firing during one of
///    our own round trips — AD-14's second launch, AD-12's tray entry — still
///    dismissed the panel.
/// 36. `_keyboardStillHere()` hardcoded to `true`, the witness still read but
///    its answer discarded — CAP-14 suppressed wherever it should fire, which
///    is threat T-01-62 — **15 failures**, spread across four groups. The
///    largest count in this record, and deliberately so: it is the mutation the
///    fail-safe direction of `focusUnmoved` exists to make impossible, and the
///    count is the measure of how much of CAP-14 rides on the answer being
///    `true` only where a focus transfer is positively ruled out. It is also
///    what pins the two rows no other control reaches — the moved-keyboard row
///    and the `AbsentKeyboardFocusWitness` (Wayland arm) row.
/// 37. the AD-15 backstop in `_keyboardStillHere` answering `true` on a throw
///    instead of `false` — **1 failure**, the throwing-witness row. Recorded
///    separately from 36 because a throw is the one uncertainty that arrives as
///    control flow rather than as a value, and answering it in the suppressing
///    direction would make a broken X connection read as "the keyboard never
///    moved" for the life of the daemon.
/// 38. the fourth question asked **before** DW-33's `!_focused` question —
///    **1 failure**, the zero-reads row. Not a correctness mutation: the panel
///    still behaves identically, because a window that never held the keyboard
///    has nothing witnessed to compare against and `focusUnmoved` answers
///    `false` either way. What it costs is a synchronous X round trip on every
///    blur at a panel the window manager never focused, in a daemon that is
///    resident all day — which is why the row asserts a read *count* rather
///    than an outcome, and why this control has to exist for that row to be
///    evidence of anything.
/// 39. `_witness.recordFocusGained()` deleted from the `focus` arm — **1
///    failure**, the focus-is-witnessed row. The recording is the other half of
///    the comparison, and deleting it does not fail the suppression rows:
///    nothing witnessed means `focusUnmoved` answers `false`, so every row
///    above degrades to the pre-seam behaviour it was already asserting. Only a
///    row that counts the recordings can see it, and that asymmetry is the
///    point — a wiring mistake in this direction presents as CAP-14 quietly
///    never suppressing, never as a failure.
/// 40. the `on Object` guard removed from `_recordFocusWitness`, the recording
///    left bare in the `focus` arm the way it stood before WR-03 — **1
///    failure**, the throwing-recording row. The write-side twin of 37, and
///    recorded separately for the reason that makes it worth pinning at all:
///    what a throw costs here is not a wrong answer but an escape. The
///    recording runs inside the `_window.events` listener callback, and a
///    listener throw is not a stream error, so the subscription's `onError`
///    cannot see it and the root zone is what receives it. Every behavioural
///    row in this file stays green without the guard — a failed recording
///    leaves nothing witnessed, so the dismissal fires exactly as it already
///    did — which is precisely why the guard needed a row and an injection
///    point (`FakeKeyboardFocusWitness.recordError`) rather than a reading.
///
/// 33 and 34 are pinned by rows that overlap on one and diverge on the other:
/// the `_focused`-survives row fails for both, and it is the only row that
/// does, so the unmoved-keyboard row and the zero-reads row are what keep the
/// two controls from being one claim measured twice.
///
/// The wiring half of G-01-13 is measured in `composition_wiring_test.dart`
/// rather than here, because it is a claim about `daemon_startup.dart`'s text
/// and this suite cannot see it: swapping the two `_focusWitnessFor` arms fails
/// 1 row there, and giving the witness its own second
/// `DisplayServer.fromEnvironment` call fails 1 other. Both leave this suite
/// entirely green, which is why they needed pinning somewhere at all.
///
/// 9 and 11 are deliberately pinned by rows that fail for one of them and not
/// the other — the trailing-focus row never delivers a `focus` while the panel
/// is up, and the minimize/restore row never delivers one while it is down. A
/// single row failing for both would have proved neither.
///
/// Recorded here rather than as extra tests: a mutation is evidence about this
/// suite, not behaviour the daemon has. This is the single record — the
/// ledger's resolution line cites it rather than restating the numbers.
///
/// Pure Dart, no Flutter binding: that is the whole reason the `PanelWindow`
/// seam exists (AGENTS.md §7).
void main() {
  late FakePanelWindow window;
  late FakeLogger logger;
  late FakeKeyboardFocusWitness witness;
  late WindowManagerPanelVisibility visibility;

  setUp(() {
    window = FakePanelWindow();
    logger = FakeLogger();
    // Held in a local so a row can state the answer it needs. The default is
    // `false` — the seam's fail-safe direction — so every row written before
    // this seam existed keeps the behaviour it was written against, and a row
    // that suppresses a dismissal has to say so out loud.
    witness = FakeKeyboardFocusWitness();
    visibility = WindowManagerPanelVisibility(
      window: window,
      focusWitness: witness,
      requestTimeout: _ampleBound,
      logger: logger,
    );
  });

  tearDown(() => visibility.dispose());

  group('the mirror leads (CAP-1, AD-8)', () {
    test('CAP-1: isVisible is true before show() completes — the toggle never '
        'waits on the window manager', () async {
      final showing = visibility.show();

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'AD-8 forbids the toggle awaiting anything, so a mirror that only '
            'moved when the window answered would read stale for the whole '
            'round trip',
      );
      expect(
        window.visible,
        isFalse,
        reason: 'the window has not answered yet',
      );

      await window.settle();
      await showing;

      expect(visibility.isVisible, isTrue);
      expect(window.visible, visibility.isVisible);
    });

    test(
      'CAP-1: show() maps the window and then focuses it — '
      'gtk_widget_show alone neither raises it nor takes the keyboard',
      () async {
        final showing = visibility.show();
        await window.settle();
        await showing;

        expect(window.calls, ['show', 'focus']);
        expect(window.visible, isTrue);
      },
    );

    test('CAP-14: isVisible is false before hide() completes', () async {
      await _settled(visibility.show(), window);

      final hiding = visibility.hide();

      expect(visibility.isVisible, isFalse);
      expect(window.visible, isTrue, reason: 'the window has not answered yet');

      await window.settle();
      await hiding;

      expect(window.visible, visibility.isVisible);
      expect(window.calls, ['show', 'focus', 'hide']);
    });

    test('AD-18: changes emits once per transition, naming the departure, and '
        'nothing for a hide that changes nothing', () async {
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      await _settled(visibility.hide(), window);
      await _settled(visibility.show(), window);
      await _settled(visibility.show(), window);
      await _settled(visibility.hide(), window);
      await pumpEventQueue();

      expect(
        emitted,
        [PanelVisibilityState.shown, PanelVisibilityState.dismissed],
        reason:
            'a requested hide is the user saying they are done, so it reports '
            'dismissed — and CorrectionController begins a session on the '
            'shown after one (AD-18), which makes a duplicate emission here a '
            'duplicate clipboard read and a discarded editor',
      );
    });

    test('AD-14: a show on an already-visible panel still raises it — the '
        'mirror not moving is not a reason to skip the window', () async {
      await _settled(visibility.show(), window);

      // AD-14's second launch and AD-12's tray "open the panel" both call
      // show() on a panel that may already be up. `changes` correctly emits
      // nothing, so the only observable is that the window is asked again —
      // an early return whenever the mirror does not move would silently kill
      // the raise, and on Linux `show` alone does not raise anyway.
      await _settled(visibility.show(), window);

      expect(window.calls, ['show', 'focus', 'show', 'focus']);
      expect(window.visible, visibility.isVisible);
    });

    test('AD-8: the window never holds two of our requests at once', () async {
      final showing = visibility.show();
      final hiding = visibility.hide();
      await pumpEventQueue();

      expect(
        window.inFlight,
        lessThanOrEqualTo(1),
        reason:
            'windowManager.show() awaits an isMinimized() hop before it '
            'invokes show, while hide() invokes immediately — two unserialised '
            'requests reach the platform out of order, and the show maps the '
            'window behind the hide',
      );

      await window.settle();
      await showing;
      await hiding;
    });

    test('AD-15: a rejected show leaves the mirror true and rejects the '
        'returned future', () async {
      window.showError = StateError('the window manager refused to map');

      final showing = visibility.show();
      final failed = expectLater(showing, throwsA(isA<StateError>()));
      await window.settle();
      await failed;

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'the intent stands; the next press must still read the panel as '
            'shown and hide it',
      );
      expect(window.calls, ['show'], reason: 'a failed show is not focused');
    });

    test(
      'AD-15: a rejected request does not break the queue behind it',
      () async {
        await _settled(visibility.show(), window);
        window.hideError = StateError('the window manager refused to unmap');

        final failed = expectLater(
          visibility.hide(),
          throwsA(isA<StateError>()),
        );
        // Let the hide reach the window before the refusal is lifted, so the
        // call that rejects is the queued one and the press behind it is not.
        await pumpEventQueue();
        window.hideError = null;
        final showing = visibility.show();

        await window.settle();
        await failed;
        await showing;

        expect(
          window.visible,
          isTrue,
          reason:
              'a rejected request must not strand the queue — the next press '
              'still has to reach the window',
        );
        expect(window.visible, visibility.isVisible);
      },
    );
  });

  group('the fast double press (AD-8, CAP-14)', () {
    // The pre-hop variant is a **mutation-only discriminator on this row**,
    // and saying so is the honest reading of it. In the shipped tree the
    // superseded first press returns before touching the window at all, so
    // `FakePanelWindow.show()` — and therefore its `isMinimized` pre-hop — is
    // never entered, and the two runs issue the identical `['hide']`. The
    // variants diverge only under mutation 4 (serialisation removed), where
    // the pre-hop is what lets the later `hide` overtake the earlier `show`
    // and reorder the platform calls rather than merely delaying them. The
    // row below (`a press landing between show and focus`) is where the
    // pre-hop path is exercised against the shipped adapter.
    for (final preHop in [false, true]) {
      test(
        'CAP-14: two presses inside the window round trip leave the panel '
        'hidden${preHop ? ' (with show() isMinimized pre-hop)' : ''}',
        () async {
          await visibility.dispose();
          window = FakePanelWindow(showHasMinimizedPreHop: preHop);
          visibility = WindowManagerPanelVisibility(
            window: window,
            focusWitness: FakeKeyboardFocusWitness(),
            requestTimeout: _ampleBound,
            logger: logger,
          );
          final hotkey = FakeGlobalHotkey();
          final controller = PanelController(
            visibility: visibility,
            hotkey: hotkey,
            logger: logger,
          );

          // Two presses with nothing released in between: the window has not
          // answered the first when the second arrives.
          controller.onHotkeyActivated();
          controller.onHotkeyActivated();
          await window.settle();
          await pumpEventQueue();

          expect(visibility.isVisible, isFalse);
          expect(window.visible, visibility.isVisible);
          expect(
            window.wasEverVisible,
            isFalse,
            reason:
                'the second press dismissed the panel before the first reached '
                'the window; a request the user superseded must issue nothing '
                'at all, because focus() is gtk_window_present and maps a '
                'hidden toplevel',
          );
          expect(window.calls, isNot(contains('show')));
          expect(window.calls, isNot(contains('focus')));

          await controller.dispose();
          await hotkey.dispose();
        },
      );
    }

    test('CAP-14: a press landing between show and focus stops the focus — no '
        'keyboard steal for a panel already dismissed', () async {
      final showing = visibility.show();
      await pumpEventQueue();

      // The window maps and answers, but the press arrives before the focus
      // call the same request was about to make.
      window.releaseNext();
      final hiding = visibility.hide();

      await window.settle();
      await showing;
      await hiding;

      expect(
        window.calls,
        ['show', 'hide'],
        reason:
            'focus() is gtk_window_present: it takes the keyboard and maps a '
            'hidden toplevel, so a request the user has superseded must stop '
            'between its two halves as well as before its first',
      );
      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
    });

    test('AD-8: disposing between show and focus stops the focus — a '
        'torn-down adapter must not present the window', () async {
      final showing = visibility.show();
      await pumpEventQueue();

      // Disposal drains the parked show, so the request resumes with the
      // adapter already closed and its window listener deregistered.
      await visibility.dispose();
      await pumpEventQueue();
      await showing;

      expect(window.calls, isNot(contains('focus')));
    });

    test('AD-8: the show echo of a superseded request does not resurrect the '
        'panel', () async {
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      // Press one gets as far as issuing `show`.
      final showing = visibility.show();
      await pumpEventQueue();
      // Press two lands while that request is still outstanding.
      final hiding = visibility.hide();
      // Only now does the window map and report its own `show` back.
      window.releaseNext();
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason:
            'the echo belongs to a request the user has already superseded; '
            'believing it emits a spurious shown behind the dismissal, which '
            'under AD-18 clears the editor and re-reads the clipboard against '
            'a panel on its way out',
      );

      await window.settle();
      await showing;
      await hiding;
      await pumpEventQueue();

      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.dismissed,
      ]);
    });
  });

  group('window events move the mirror only on their own (AD-8)', () {
    test('AD-8: our own show echo reports no second transition', () async {
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      await _settled(visibility.show(), window);
      await pumpEventQueue();

      expect(emitted, [PanelVisibilityState.shown]);
      expect(window.visible, visibility.isVisible);
    });

    test(
      'AD-8/PANEL-19: an unlabelled GTK hide echo cannot dismiss a later show',
      () async {
        final emitted = <PanelVisibilityState>[];
        visibility.changes.listen(emitted.add);
        await _settled(visibility.show(), window);

        // The plugin emits this only for our own gtk_widget_hide call. Its
        // event has no request identity and cannot override this shown state.
        window.emitEvent('hide');
        await pumpEventQueue();

        expect(visibility.isVisible, isTrue);
        expect(emitted, [PanelVisibilityState.shown]);
      },
    );

    test('AD-8: minimize moves the mirror — gtk_window_iconify emits no hide '
        'signal, so nothing else would', () async {
      await _settled(visibility.show(), window);

      window.emitEvent('minimize');
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason:
            'an iconified panel that still reads as visible wastes the next '
            'press on a hide nobody can see',
      );

      // With nothing outstanding both `restore` arms produce the same value, so
      // this row says nothing about which one ran — the rows below are where
      // that distinction lives. What it pins is the pair cancelling out at all.
      window.emitEvent('restore');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
    });

    test('DW-31: a minimize arriving during one of our requests still moves '
        'the mirror — nothing this adapter calls iconifies, so it can never '
        'be an echo', () async {
      // The half of the split that is easy to get wrong, because `minimize`
      // and `restore` arrive from the same GTK `window-state-event` handler
      // and the row above pins `restore` on the other side of it. The
      // asymmetry is one-directional and real: `windowManager.show()`
      // deiconifies as part of its own implementation, so a `restore` can be
      // our own doing, while nothing this adapter calls iconifies anything.
      //
      // Routed through `_reconcile`, this event was discarded outright — the
      // guard has no echo to swallow here, only the one signal an iconify
      // produces at all. `gtk_window_iconify` emits no GTK `hide` either, and
      // `main.dart` calls `setSkipTaskbar(true)`, so there is no task-bar entry
      // to click the panel back from: the hotkey is the only way to reach it,
      // and with the mirror still reading `true` that press was spent hiding a
      // window nobody could see.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      // AD-14's second launch against an already-visible panel, parked at the
      // window: `_outstanding` is up, which is the state under test.
      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('minimize');
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason: 'an iconified panel is not up, whoever asked for the iconify',
      );
      expect(window.iconified, isTrue);
      expect(
        window.visible,
        isTrue,
        reason: 'iconified is still mapped, unlike hidden',
      );
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.iconified,
      ]);

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason:
            'and the request that was in flight does not put it back: the '
            'mirror no longer holds that intent, so the show stops before its '
            'trailing focus',
      );
      // The window surface, not the mirror alone. This suite exists because a
      // correct mirror over a wrong window is the defect class it missed once
      // already, and a `minimize` arm that answered with `_dismiss` instead of
      // `_setMirror` would satisfy every assertion above while issuing a
      // platform `hide` the window manager never asked for.
      expect(
        window.calls,
        ['show', 'focus', 'show'],
        reason:
            'an iconify is the window manager reporting a state it has already '
            'reached — the mirror follows it, and nothing is issued back',
      );
      expect(
        window.iconified,
        isTrue,
        reason:
            'the native minimize survives the parked show; the adapter did not '
            'turn an iconify into a hide',
      );
      expect(window.visible, isTrue);
    });

    test('DW-31: a minimize and the restore that undoes it, both inside one of '
        'our requests, leave the mirror agreeing with the mapped window — the '
        'pair is symmetric whatever is outstanding', () async {
      // The two halves of this change are one design. Believing the `minimize`
      // while leaving `restore` wholly behind the guard makes a self-cancelling
      // pair stop cancelling: the correcting event is swallowed and the mirror
      // is left reading false over a window that is mapped, permanently. That
      // was the reverted attempt of 2026-08-15, and it is worse than the stale
      // flag DW-31 was opened for — `_setMirror(false)` also clears the
      // keyboard flag, so CAP-14 died for that panel's life, and with
      // `setSkipTaskbar(true)` the hotkey is the only route back, which against
      // a false mirror resolves to `show()`: the panel is already up, so the
      // press changes nothing the user can see and nothing can put the window
      // away again.
      //
      // A believed `minimize` therefore arms a one-shot latch and the next
      // `restore` consumes it, moving the mirror back without consulting the
      // guard.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      // AD-14's second launch against an already-visible panel, parked at the
      // window: `_outstanding` is up for the whole pair.
      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('minimize');
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason: 'an iconified panel is not up, whoever asked for the iconify',
      );
      expect(window.iconified, isTrue);
      expect(
        window.visible,
        isTrue,
        reason: 'iconified is still mapped, unlike hidden',
      );

      window.emitEvent('restore');
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'and a restore that undoes a minimize this adapter believed is '
            'believed in turn — nothing we call iconifies, so the latch can '
            'only have been armed by a genuinely external minimize',
      );
      expect(window.iconified, isFalse);
      expect(window.visible, isTrue);

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(
        window.visible,
        isTrue,
        reason: 'restore leaves the mapped window ready to show again',
      );
      expect(window.iconified, isFalse);
      expect(window.visible, visibility.isVisible);
      expect(
        window.calls,
        ['show', 'focus', 'show', 'focus'],
        reason:
            'the pair is reported state, not a request: nothing is issued back '
            'at the window, and the parked show still finishes its own focus '
            'because the mirror holds its intent again',
      );
      expect(
        emitted,
        [
          PanelVisibilityState.shown,
          PanelVisibilityState.iconified,
          PanelVisibilityState.shown,
        ],
        reason:
            'the summon, then the pair — one value each way and no third, and '
            'the pair is named iconified so no session is discarded across it. '
            'A guarded restore would have stopped at the iconified, leaving a '
            'mirror reading false over a mapped window that no later press '
            'could put away',
      );
    });

    test('CAP-14: a genuine blur after a believed minimize/restore pair still '
        'dismisses the panel — the pair does not take the focus-loss hide with '
        'it', () async {
      // The row the reverted attempt could not pass, and the reason the pair
      // had to be made symmetric rather than left half-fixed. There, after such
      // a pair, a real click-away issued **nothing at all**: `_setMirror(false)`
      // had cleared the keyboard flag and the `focus` arm's own `_visible` guard
      // could never re-arm it over a mirror stuck at false. With the mirror back
      // up, the deiconify's real focus-in is recorded and CAP-14 outlives the
      // pair.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('minimize');
      await pumpEventQueue();
      window.emitEvent('restore');
      await pumpEventQueue();

      await window.settle();
      await showing;
      await pumpEventQueue();

      // `gtk_window_deiconify` + `gtk_window_present` normally takes the
      // keyboard back, and only the focus-in says so — the restore arm
      // deliberately does not re-arm the flag itself.
      window.emitEvent('focus');
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      expect(
        window.calls.where((call) => call == 'hide'),
        hasLength(1),
        reason: 'a real hide against the window, as CAP-14 asks for',
      );
      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.iconified,
        PanelVisibilityState.shown,
        PanelVisibilityState.focusLost,
      ]);
    });

    test('DW-31: a second restore on a spent latch is swallowed by the guard — '
        'the latch is one-shot, and one restore undoes one minimize', () async {
      // What this row pins is the outcome, not the mechanism, and saying so is
      // the honest reading of it. Making the latch sticky rather than one-shot
      // fails nothing here, and no row can be written that it does fail:
      // consuming it a second time writes `true` over a mirror that already
      // reads `true`, and every route to a false mirror while a request of ours
      // is outstanding either re-arms the latch (a further `minimize`) or clears
      // it (a press, or a `close`'s own hide). The one-shot form is kept because
      // "there is a believed minimize still to undo" is the only thing the flag
      // is allowed to mean; recorded here rather than left to be discovered,
      // like the other guards this suite's negative-control block says fail
      // nothing.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('minimize');
      window.emitEvent('restore');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue, reason: 'the pair cancelled out');

      window.emitEvent('restore');
      await pumpEventQueue();

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
      expect(window.visible, visibility.isVisible);
      expect(
        emitted,
        [
          PanelVisibilityState.shown,
          PanelVisibilityState.iconified,
          PanelVisibilityState.shown,
        ],
        reason: 'the second restore undoes nothing, so it reports nothing',
      );
    });

    test('DW-31: our own show produces the restore echo, and the echo takes the '
        'guard rather than the latch — changes reports the summon once', () async {
      // The sequence the latch has to survive without being consumed by it:
      // an external `minimize` believed with nothing outstanding, then a press.
      // `windowManager.show()` deiconifies a minimised window as part of its own
      // implementation, so the `restore` that follows is *our own echo* — and it
      // arrives after `show()` has already written the mirror. Taking the guard
      // is what makes that a silent echo rather than a second transition.
      //
      // As with the row above, both arms produce the same mirror value here, so
      // this row pins the outcome. The row below is the one that fails when the
      // latch is not cleared where the intent is expressed.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      window.emitEvent('minimize');
      await pumpEventQueue();
      expect(visibility.isVisible, isFalse);

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('restore');
      await pumpEventQueue();

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
      expect(window.visible, visibility.isVisible);
      expect(
        emitted,
        [
          PanelVisibilityState.shown,
          PanelVisibilityState.iconified,
          PanelVisibilityState.shown,
        ],
        reason:
            'the press is one transition and its own echo is not a second one. '
            'Both read shown, so a duplicate would cost nothing here under '
            'AD-18 — what it would cost is the transition-only contract the '
            'port states, which everything above reads',
      );
    });

    test(
      'AD-8: a restore arriving during one of our requests is not believed '
      '— the guard covers it, and that is what keeps a queued hide alive',
      () async {
        // The adapter's doc calls the guard's coverage of `restore`
        // load-bearing rather than tidiness, because `windowManager.show()`
        // restores a minimised window as part of its own implementation, so a
        // `restore` echo can arrive *during* one of our requests. Believing it
        // while a hide is queued behind that show flips the mirror back to true,
        // makes the queued hide look superseded, and leaves the panel on screen
        // with the mirror reading false — the exact defect this adapter exists
        // to close, re-entered through the minimised path.
        //
        // Without this row that claim was pinned by nothing: mutating the
        // `restore` arm to `_setMirror(true)`, straight past the guard, failed
        // no test in the suite. The wholesale guard-deletion mutation does fail
        // two, but both are `show`-echo rows.
        //
        // No believed `minimize` stands here, and that is a precondition rather
        // than an accident: the row below is the same sequence with one in
        // front of it.
        final showing = visibility.show();
        await pumpEventQueue();
        final hiding = visibility.hide();

        window.emitEvent('restore');
        await pumpEventQueue();
        await window.settle();
        await Future.wait([showing, hiding]);
        await pumpEventQueue();

        expect(visibility.isVisible, isFalse);
        expect(
          window.visible,
          visibility.isVisible,
          reason: 'a believed restore would have stranded the queued hide',
        );
      },
    );

    test('DW-31: a believed minimize does not let our own show echo strand a '
        'queued hide — show() and hide() clear the latch where the intent is '
        'expressed', () async {
      // The load-bearing row above, re-run with a believed `minimize` standing
      // in front of it, and the only row here that fails when the latch is not
      // cleared in `show()`/`hide()`. Left standing, the show's own deiconify
      // echo consumes it, the mirror goes back to true, the queued hide reads as
      // superseded and issues nothing — the panel stays on screen and the
      // mirror agrees with it, which is precisely what the guard's `restore`
      // coverage exists to prevent. `_setMirror` cannot carry this on its own:
      // it early-returns when the value does not change, and a `show()` at an
      // already-visible panel writes nothing at all.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      // An external iconify with nothing outstanding, so the latch is armed
      // when the press arrives.
      window.emitEvent('minimize');
      await pumpEventQueue();
      expect(visibility.isVisible, isFalse);

      final showing = visibility.show();
      await pumpEventQueue();
      final hiding = visibility.hide();

      // The deiconify `windowManager.show()` performs on its way to mapping.
      window.emitEvent('restore');
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason: 'the queued hide holds the mirror, and the echo is not news',
      );

      await window.settle();
      await Future.wait([showing, hiding]);
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      expect(
        window.calls,
        contains('hide'),
        reason:
            'the queued hide has to reach the window: a consumed latch would '
            'have made it read as superseded, so it would have issued nothing '
            'and the panel would still be on screen',
      );
      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.iconified,
        PanelVisibilityState.shown,
        PanelVisibilityState.dismissed,
      ]);
    });

    test('DW-31: a close while a believed minimize stands still leaves the '
        'mirror down — hide() spent the latch, so the deiconify echo takes the '
        'guard', () async {
      // The same rule as the row above, reached through the other clear, and
      // the row that pins `hide()`'s on its own. A `close` dismisses through
      // `hide()`, so that is where this intent is expressed — and nothing on the
      // mirror path can carry it, because `_reportDeparture` never touches the
      // latch (see its doc, and control 17). Left standing, the latch is
      // consumed by the deiconify the unmap performs on its way through, the
      // mirror goes back to true over a window that is on its way down, and the
      // panel the user explicitly closed reads as up: the next press is spent
      // hiding a window that has already gone.
      //
      // It is also DW-30's re-attribution on the close side, which is why the
      // emission list below has a third value the mirror did not move for: the
      // panel was already away as an `iconified`, and the close replaced the
      // *reason* it is away. Under the three-way session rule the last reason is
      // the one the next summon obeys, so a swallowed `dismissed` here would
      // hand the user back the session they just closed.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      window.emitEvent('minimize');
      await pumpEventQueue();
      expect(visibility.isVisible, isFalse);

      // The user closes the iconified panel. `setPreventClose(true)` means the
      // toplevel is still there, so the adapter's own hide is what puts it away.
      window.emitEvent('close');
      await pumpEventQueue();

      window.emitEvent('restore');
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason:
            'the close is the standing intent, and a restore arriving inside '
            'its round trip undoes no minimize this adapter is still holding',
      );

      await window.settle();
      await pumpEventQueue();

      expect(window.calls, ['show', 'focus', 'hide']);
      expect(window.visible, isFalse);
      expect(window.iconified, isFalse, reason: 'hidden is not iconified');
      expect(window.visible, visibility.isVisible);
      expect(
        emitted,
        [
          PanelVisibilityState.shown,
          PanelVisibilityState.iconified,
          PanelVisibilityState.dismissed,
        ],
        reason:
            'the mirror moved twice and the stream reported three times: the '
            'close is a real change of state even over a panel that was already '
            'away, because it changed why it is away (DW-30)',
      );
    });

    test('DW-31: a minimize that moved no mirror arms nothing — our own hide '
        'had already put the panel down, so the deiconify echo behind it is '
        'still just an echo', () async {
      // The arming condition, and the row that pins it. `_believedMinimize` is
      // armed only by a `minimize` that actually took the panel down, and the
      // reason is this sequence: a `show()` parked with a `hide()` queued behind
      // it has the mirror already reading false, so an iconify arriving there
      // moves nothing and has nothing for a `restore` to undo. Arm it anyway and
      // the deiconify `windowManager.show()` performs on its way to mapping
      // consumes the latch, the mirror goes back to true, the queued hide reads
      // as superseded and issues nothing — the panel stays on screen. That is
      // the stranded dismissal the guard's `restore` coverage exists to prevent,
      // reached through the latch that was added to preserve it.
      //
      // The condition does a second job in the same line. `hide()` writes the
      // mirror false *before* it calls the window, so a compositor that reports
      // `GDK_WINDOW_STATE_ICONIFIED` as part of `gtk_widget_hide` cannot arm the
      // latch off our own unmap either.
      //
      // Assertions run in both directions on purpose: under the mutation the
      // mirror and the window both read true, so they agree with each other and
      // this suite's usual `window.visible == visibility.isVisible` pairing
      // cannot see it. What separates the two trees is the mirror's *value* and
      // the absence of the queued `hide` from the platform calls.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();
      final hiding = visibility.hide();

      // The compositor reports the iconify while our own hide has already put
      // the mirror down, and then the deiconify that belongs to the parked show.
      window.emitEvent('minimize');
      await pumpEventQueue();
      window.emitEvent('restore');
      await pumpEventQueue();

      await window.settle();
      await Future.wait([showing, hiding]);
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason:
            'the last thing the user asked for was the panel gone, and neither '
            'of those two events undoes a minimize this adapter believed',
      );
      expect(
        window.calls,
        ['show', 'focus', 'show', 'hide'],
        reason:
            'the queued hide reached the window: a latch armed by the iconify '
            'would have let the deiconify echo revive the mirror, and the hide '
            'would then have read as superseded and issued nothing at all',
      );
      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
      expect(
        emitted,
        [PanelVisibilityState.shown, PanelVisibilityState.dismissed],
        reason:
            'and no third transition — a believed pair here would report the '
            'panel back up over a hide the user is still waiting for',
      );
    });

    test('DW-12: a close puts the window away for real — with '
        'setPreventClose(true) the toplevel is still mapped when the event '
        'arrives, so a mirror alone would be a lie', () async {
      // `on_window_close` returns `_is_prevent_close`, and `main.dart` sets
      // that flag true at startup — returning TRUE is what suppresses GTK's
      // default `delete-event` handler, so the toplevel survives. (The
      // emit-before-return ordering inside that function proves nothing by
      // itself: `_emit_event` is an asynchronous channel invoke, so with the
      // flag false the window would be gone before Dart ran.) So the event no
      // longer means "the toplevel is gone": it means the user asked for it to
      // go, and something has to make that true. `_reconcile(false)` would
      // leave a window on screen that `isVisible` reports as hidden.
      //
      // This row drives the fake window directly, so it *assumes* that premise
      // rather than establishing it; the flag itself is pinned in
      // `test/architecture/`, and the real close control is owed on a session
      // (see `test/platform/panel_visibility_live_test.dart`).
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      window.emitEvent('close');
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason: 'the mirror leads the hide, as it does for every other request',
      );

      await window.settle();
      await pumpEventQueue();

      expect(
        window.calls,
        ['show', 'focus', 'hide'],
        reason:
            'a real hide against the window, not a mirror write — this is the '
            'whole of DW-12 on this side',
      );
      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.dismissed,
      ]);
    });

    test('DW-12: a close arriving while a request of ours is outstanding is '
        'still obeyed — a close can never be an echo of ours', () async {
      // The deliberate asymmetry with the blur twin below (a blur arriving
      // while a show is outstanding is never dismissed on the spot — it is
      // dropped or latched), and the one decision in this arm that nothing
      // else here can see. `close` is a GTK `delete-event`,
      // and this adapter's only platform calls are `show`, `hide` and `focus`,
      // so it is the one window event that cannot be an echo of a request of
      // ours — which is why the arm skips the `_outstanding` guard every other
      // arm goes through. Without this row, adding
      // `if (_outstanding > 0) { return; }` in front of `_dismiss('close')`
      // leaves the whole suite green while a close landing during the map it
      // interrupts is silently dropped: the panel stays on screen and the user
      // has to ask twice.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      // The show is parked at the window, so `_outstanding` is up — the state
      // in which the blur arm deliberately does nothing.
      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('close');
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason:
            'the close is the user dismissing a window that is mapping, not '
            'the window reporting back what we asked it for',
      );

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(
        window.calls,
        ['show', 'hide'],
        reason:
            'the map answered and the close had already superseded it, so the '
            'trailing focus is not issued — gtk_window_present would re-map '
            'the very window the close asked to put away',
      );
      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.dismissed,
      ]);
    });

    test('DW-12: a close is obeyed even when the mirror already reads hidden — '
        'a close always means a mapped window', () async {
      // The arm's other unguarded property, and the twin of the row above. The
      // blur arm asks `!_visible` and `_outstanding > 0` before it dismisses
      // anything, and both of those look like they belong in the `_dismiss`
      // helper the two arms now share. `_outstanding` is pinned above; without
      // this row, adding `if (!_visible) { return; }` to `_dismiss` leaves the
      // whole suite green — every other close row shows the panel first, so
      // `_visible` is true at each of them.
      //
      // The state this builds is the one `_onBlur`'s own doc names as reachable:
      // "the mirror reads `false` over a mapped window until some later window
      // event moves it". A close is exactly such an event, and it is the one
      // that must repair rather than believe the mirror — `setPreventClose(true)`
      // means GTK will not take the toplevel down either, so an arm that
      // returned early here would leave the panel on screen with the user's
      // close control now inert.
      await _settled(visibility.show(), window);

      // A believed iconify moves the mirror while this fake's native window
      // remains mapped, reproducing the stale mirror the close must repair.
      window.emitEvent('minimize');
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      expect(
        window.visible,
        isTrue,
        reason: 'the premise of this row — a stale mirror over a live window',
      );

      window.emitEvent('close');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        window.calls,
        ['show', 'focus', 'hide'],
        reason:
            'a real hide, issued against a window the mirror had already given '
            'up on — the close is what repairs the disagreement',
      );
      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
    });

    test('AD-15: a close whose hide the window refuses is logged, and the '
        'daemon stays up', () async {
      await _settled(visibility.show(), window);
      window.hideError = StateError('the window manager refused to unmap');

      window.emitEvent('close');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason: 'the mirror led, and a refusal does not put the intent back',
      );
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(
        errors.single.message,
        contains('close hide'),
        reason:
            'a refused close hide leaves a window on screen the user just '
            'dismissed; a refused focus-loss hide is a compositor quirk — the '
            'two are different events and must not share one line',
      );
      expect(errors.single.context, {'error_type': 'StateError'});
    });

    test('CAP-1: a closed panel is still warm — the toplevel was never '
        'destroyed, so the next press shows it again', () async {
      await _settled(visibility.show(), window);

      window.emitEvent('close');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(window.visible, isFalse);

      await _settled(visibility.show(), window);

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'a close that destroyed the toplevel would leave the adapter '
            'issuing show and focus at a window that no longer exists',
      );
      expect(window.visible, isTrue);
      expect(
        logger.lines,
        isEmpty,
        reason: 'nothing here failed, so nothing here is worth a line',
      );
    });

    test('AD-8: an unrecognised event moves nothing', () async {
      await _settled(visibility.show(), window);

      window.emitEvent('resized');
      window.emitEvent('move');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
    });

    test('AD-15: an event stream that errors is logged and the subscription '
        'survives', () async {
      window.emitEventError(StateError('the channel broke'));
      await pumpEventQueue();

      window.emitEvent('show');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
      expect(logger.lines.single.level, 'error');
      expect(logger.lines.single.context, {'error_type': 'StateError'});
    });

    test('AD-15: an event stream that closes under a live adapter is logged — '
        'an errored stream leaves a line, a completed one would leave '
        'nothing', () async {
      await window.closeEvents();
      await pumpEventQueue();

      expect(
        logger.lines,
        hasLength(1),
        reason:
            'reconciliation has stopped for good and the adapter still reads '
            'healthy, so this line is the only thing that can say so',
      );
      expect(logger.lines.single.level, 'error');
      expect(logger.lines.single.message, contains('closed'));
      expect(logger.lines.single.message, contains('reconcile'));
      expect(
        logger.lines.single.context,
        isNull,
        reason: 'there is no error here to describe',
      );
    });

    test('AD-15: the ordinary teardown logs no stream-closed line — dispose '
        'cancels the subscription before the window closes events', () async {
      await visibility.dispose();
      await pumpEventQueue();

      expect(
        logger.lines,
        isEmpty,
        reason:
            'a cancelled subscription receives no done event, so the backstop '
            'must stay silent on every ordinary shutdown',
      );
      expect(window.disposed, isTrue, reason: 'the window really did close');
    });

    test('AD-15: a logger that throws while reporting the close does not let '
        'the failure escape — the reporting channel is what broke', () async {
      final escaped = <Object>[];
      final throwing = ThrowingLogger();

      await runZonedGuarded(() async {
        final closing = FakePanelWindow();
        final adapter = WindowManagerPanelVisibility(
          window: closing,
          focusWitness: FakeKeyboardFocusWitness(),
          requestTimeout: _ampleBound,
          logger: throwing,
        );

        await closing.closeEvents();
        await pumpEventQueue();
        await adapter.dispose();
      }, (Object error, StackTrace stack) => escaped.add(error));

      expect(
        throwing.attempts,
        ['error'],
        reason:
            'ThrowingLogger records every call attempted so a test can prove '
            'the guards still tried — without this, a row asserting only that '
            'nothing escaped stays green when the arm never fires at all',
      );
      expect(
        escaped,
        isEmpty,
        reason:
            'an unguarded emit would surface as an uncaught async error from '
            'the stream callback, taking down a daemon because its log sink '
            'broke',
      );
    });
  });

  group('the focus-loss hide (CAP-14)', () {
    test('CAP-14: a blur after the window took the keyboard hides the panel, '
        'mirror and window together', () async {
      // The row that must not regress, and the reason the `focus` event is
      // delivered here rather than assumed: since DW-33 the adapter answers a
      // focus-out only when a focus-in said the window ever held the keyboard.
      // Deleting that requirement is a mutation the DW-33 row below catches;
      // deleting the *dismissal* is what this row catches.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      window.emitEvent('focus');
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);

      await window.settle();
      await pumpEventQueue();

      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.focusLost,
      ]);
    });

    test('DW-33: a blur at a panel the window manager never gave the keyboard '
        'to does nothing — the panel must not dismiss itself at the moment it '
        'is summoned', () async {
      // A compositor with focus-stealing prevention maps the panel and leaves
      // the keyboard where it was, then sends a focus-out as the pointer or the
      // previous window settles. Answered as a dismissal, that is CAP-14 firing
      // on the summon itself: the user presses the hotkey and the panel appears
      // and vanishes.
      //
      // This row is the first of the two questions the arm now asks, and the
      // one the CAP-14 row above deliberately does not exercise — that row
      // delivers a `focus` first.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isTrue,
        reason: 'no focus-in ever said the window held the keyboard',
      );
      expect(window.calls, ['show', 'focus']);
      expect(
        window.visible,
        isTrue,
        reason: 'and the panel the user just asked for is still on screen',
      );
      expect(emitted, [PanelVisibilityState.shown]);
    });

    test('DW-33: a focus arriving at a panel that is already gone is not '
        'recorded — the trailing event of our own focus() must not arm the '
        'next summon', () async {
      // Reachable in the *ordinary* flow, not a contrived one, and that is the
      // point. The plugin emits every event through `_emit_event`, an
      // asynchronous `fl_method_channel_invoke_method`
      // (`window_manager-0.5.2/linux/window_manager_plugin.cc:959-977`), so the
      // `focus` our own `gtk_window_present` causes always lands *after* that
      // call's channel reply — and therefore after anything the request's
      // completion set in motion, a deferred blur releasing into a `hide`
      // included. Recorded unguarded it writes `true` over a mirror already
      // reading false, and `_setMirror` cannot take it back: that clear is a
      // no-op once `_visible` is false. The next summon then opens holding a
      // keyboard it never took, and the first spurious focus-out dismisses the
      // panel the user just asked for — DW-33 reinstated through its own fix.
      //
      // No `focus` is delivered while the panel is up, deliberately: that would
      // make the row depend on `_setMirror`'s own clear as well and it would
      // then fail for two different deletions, which proves neither. The clear
      // has its own row below, and the realistic sequence — a real focus, a
      // hide, then the trailing focus — is the two of them together.
      await _settled(visibility.show(), window);
      await _settled(visibility.hide(), window);

      // The trailing event, arriving at a panel that has already gone.
      window.emitEvent('focus');
      await pumpEventQueue();

      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'the summon the user just made must not be dismissed by a keyboard '
            'flag left behind by the one before it',
      );
      expect(window.visible, isTrue);
      expect(emitted, [PanelVisibilityState.shown]);
    });

    test('DW-33: the mirror going false on a route with no blur still clears '
        'the keyboard — an unmapped window holds none', () async {
      // `_onBlur` clears the flag on its own path, so the whole value of the
      // clear in `_setMirror` lives in the routes the mirror takes to false
      // *without* a blur: a `close`, a `minimize`, an external `hide` event, a
      // hide the window refused. None of them was exercised, and before this
      // row deleting the clear left the whole file green against a baseline
      // confirmed green first. (The row count has moved twice since that was
      // measured, which is why the negative-control block states failure counts
      // and its own baseline rather than totals in prose.)
      //
      // A minimize is used because it is the shortest of those routes that can
      // be reversed in the same row: the panel comes back, and the question is
      // whether it comes back believing it still has the keyboard it held
      // before it was iconified. It must not — the row above covers the other
      // half, a focus arriving while the mirror is false, and neither row
      // fails for the other's deletion.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      window.emitEvent('focus');
      await pumpEventQueue();

      window.emitEvent('minimize');
      await pumpEventQueue();
      window.emitEvent('restore');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue, reason: 'the panel is back');

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'the keyboard the panel held in its previous life is not a '
            'keyboard it holds now, and a restored window has to earn a focus '
            'of its own before a focus-out means anything',
      );
      expect(window.calls, isNot(contains('hide')));
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.iconified,
        PanelVisibilityState.shown,
      ]);
    });

    test('CAP-14: a blur while the panel is hidden does nothing — the other '
        'question the arm asks before it dismisses anything', () async {
      // A hidden panel has no focus to lose, and `close`'s twin row
      // deliberately has no such guard — that asymmetry is what this row is
      // beside.
      //
      // Which of the arm's two questions stops it is worth stating, because it
      // is not the one the row is named for. The `focus` below arrives at a
      // false mirror and the arm's own `_visible` guard discards it, so
      // `_focused` is false and `!heldFocus` is what returns. `!_visible` can
      // never decide this on its own — `_focused` is written only under a
      // visible mirror and cleared on every transition away from one, so it
      // implies `_visible`. Deleting `!_visible ||` from `_onBlur` leaves this
      // file green; it is recorded as control 12 rather than fixed, since the
      // clause states a real precondition and costs nothing.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      window.emitEvent('focus');
      window.emitEvent('blur');
      await pumpEventQueue();

      expect(emitted, isEmpty);
      expect(window.calls, isEmpty);
    });

    test('DW-33: a blur arriving while a show is outstanding, at a panel that '
        'never held the keyboard, is dropped rather than latched', () async {
      // The state story 5 wrote as "ignored — a user cannot have dismissed a
      // panel that is still being mapped". That reading is right *here*,
      // because this panel was not up and focused before the show: the blur is
      // the map itself, not a dismissal. It is stopped by the DW-33 question,
      // not by the latch — which is the discriminator this row carries, since
      // a latch armed here would fire a hide the moment the round trip ended.
      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(
        window.calls,
        ['show', 'focus'],
        reason:
            'nothing was deferred, so nothing is dismissed when the request '
            'chain lets go',
      );
      expect(window.visible, visibility.isVisible);
    });

    test('DW-32: a blur during a second show of an already-visible focused '
        'panel is latched, and dismissed when the round trip ends', () async {
      // The widening of story 5's row, and the case that row got wrong: a
      // `show()` on a panel that is *already up* — AD-14's second launch,
      // AD-12's tray entry — is a full round trip against a mapped, focused
      // window, and the user really can click away during it. Returning early
      // on `_outstanding` discarded that dismissal and nothing ever re-asked,
      // so the panel stayed on screen until the next press.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'nothing happens while the request is in flight — the blur is '
            'held, not obeyed, because our own map can produce one',
      );

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason: 'and the held blur is answered once the chain lets go',
      );
      expect(
        window.calls,
        ['show', 'focus', 'show', 'hide'],
        reason:
            'a real hide against the window, not a mirror write: the second '
            'summon completed and the dismissal followed it',
      );
      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.focusLost,
      ]);
    });

    test('DW-32: two blurs inside one round trip are one dismissal — the '
        'latch is a flag, not a queue', () async {
      // The `focus` between the two blurs is what makes this row able to fail
      // for the claim in its name. `_onBlur` clears `_focused` before it tests
      // it, so a bare `blur, blur` has its second blur return at the DW-33
      // question and never reach `_deferredBlur = true` at all — the row would
      // then pass identically against a latch that counted, and the flag-vs-
      // queue property would be pinned by nothing. Delivering a focus-in
      // between them is also the realistic sequence: a user cannot lose focus
      // twice without regaining it in between.
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();
      window.emitEvent('focus');
      await pumpEventQueue();
      window.emitEvent('blur');
      await pumpEventQueue();

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(
        window.calls.where((call) => call == 'hide'),
        hasLength(1),
        reason:
            'the user turned away once; a queue of deferred blurs would issue '
            'a second hide against a panel that is already gone',
      );
      expect(visibility.isVisible, isFalse);
      expect(window.visible, visibility.isVisible);
    });

    test('DW-33: a focus regained before the latch releases drops the deferred '
        'blur — the window manager has just handed the keyboard back', () async {
      // DW-32's door into DW-33's defect. The round trip that suppressed the
      // blur ends in `focus()`, which is `gtk_window_present`: it takes the
      // keyboard back and the window says so. Dismissing on the blur that
      // preceded that would take down a panel the compositor has just focused.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();
      window.emitEvent('focus');
      await pumpEventQueue();

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
      expect(
        window.calls,
        isNot(contains('hide')),
        reason: 'there is no dismissal left to perform',
      );
      expect(window.visible, isTrue);
      expect(emitted, [PanelVisibilityState.shown]);
    });

    test('DW-32: a latched blur whose panel is dismissed first adds no second '
        'hide — the press that dismissed it took the latch with it', () async {
      // Named for the mechanism that actually carries it. The obvious reading —
      // that `_releaseDeferredBlur` re-reads `_visible` and finds it false — is
      // not what happens: `hide()` drops the latch before it touches the
      // mirror, so the release returns at `!_deferredBlur` and never reaches
      // that check. Deleting the `!_visible` re-read leaves this row and the
      // whole file green, which is recorded as control 13 rather than fixed;
      // with the latch set, `_visible` is true by construction.
      //
      // What the row pins is the outcome from the user's side, which is the
      // part that must hold however the guards are arranged: one press, one
      // hide.
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();

      // A press lands while the second summon is still parked at the window.
      final hiding = visibility.hide();
      await pumpEventQueue();

      await window.settle();
      await Future.wait([showing, hiding]);
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      expect(
        window.calls.where((call) => call == 'hide'),
        hasLength(1),
        reason:
            'the press already put the panel away, so the deferred blur has '
            'nothing to dismiss — acting on what was true when it arrived '
            'would issue a hide at a window somebody else is already moving',
      );
      expect(window.visible, visibility.isVisible);
    });

    test('DW-32: a latched blur does not survive a re-summon that moves no '
        'mirror — the tray entry and the second launch are exactly that '
        'request', () async {
      // The row below covers the same rule through a `hide()` + `show()` pair,
      // which transitions the mirror twice. This one covers the request that
      // transitions it *not at all*, and that request is not an edge: a
      // `show()` against an already-visible panel is AD-14's second launch and
      // AD-12's tray entry — the very shape DW-32 exists for. `_setMirror`
      // early-returns when the value does not change, so a latch dropped only
      // there is not dropped here, and the release fires against the summon
      // the user just made.
      //
      // The outcome is worse than a stray hide, which is why it gets its own
      // row: `_dismiss` moves the mirror synchronously, so the `show` queued
      // behind it reads as superseded and issues nothing. The panel does not
      // flicker — it never appears, and no further event is coming to explain
      // it. Both presses are spent and the user is looking at nothing.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      // AD-14's second launch, parked at the window.
      final showing = visibility.show();
      await pumpEventQueue();

      // The user clicks away during that round trip.
      window.emitEvent('blur');
      await pumpEventQueue();

      // And then asks for the panel again — the tray entry, or a third press.
      // The mirror already reads true, so nothing about it moves.
      final again = visibility.show();
      await pumpEventQueue();

      await window.settle();
      await Future.wait([showing, again]);
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'the last thing the user asked for was the panel, and a blur '
            'raised before that request cannot answer it',
      );
      expect(
        window.visible,
        isTrue,
        reason:
            'and the window is really up: the failure this pins is not a '
            'mislabelled mirror but a summon that produced no panel at all',
      );
      expect(
        window.calls,
        isNot(contains('hide')),
        reason: 'nothing was dismissed, so nothing was hidden',
      );
      expect(window.visible, visibility.isVisible);
      expect(
        emitted,
        [PanelVisibilityState.shown],
        reason:
            'and the panel never left, so no AD-18 session was discarded on '
            'the way',
      );
    });

    test('DW-32: a latched blur does not survive a fresh summon — a mirror '
        'transition is a new intent, and the blur belonged to the one before '
        'it', () async {
      // `_releaseDeferredBlur` re-reads `_visible`, and `_visible` alone cannot
      // tell "still the panel the blur belonged to" from "a panel the user has
      // since re-summoned". Both read `true`. Inside one slow round trip the
      // user can dismiss the panel and summon it again, and the release then
      // fires against the *new* panel — worse than a stray hide, because
      // `_dismiss` moves the mirror synchronously, so the queued show reads as
      // superseded and issues nothing: the panel the user asked for never
      // appears at all, and no further event is coming to explain it.
      //
      // Clearing the latch on every transition is what answers that, and it
      // subsumes the mechanism of the dismissed-first row above; that row is
      // kept because it pins the outcome from the other direction.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();

      // Two presses inside the round trip the blur was latched under: the user
      // put the panel away and then asked for it back.
      final hiding = visibility.hide();
      final again = visibility.show();
      await pumpEventQueue();

      await window.settle();
      await Future.wait([showing, hiding, again]);
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'the last thing the user asked for was the panel, and a blur '
            'raised before that request cannot answer it',
      );
      expect(
        window.visible,
        isTrue,
        reason:
            'and the window really is up — a mirror reading true over a panel '
            'the release quietly suppressed is the same defect wearing the '
            'other face',
      );
      expect(window.visible, visibility.isVisible);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.dismissed,
        PanelVisibilityState.shown,
      ]);
    });

    test('DW-32: a minimize during a latched round trip voids the blur — the '
        'panel was iconified, not dismissed, and a hide at it would be a '
        'second unmap of a window nobody can see', () async {
      // The window-driven half of the rule the two press-driven rows above
      // cover, and the row that closes a gap the two guards behind it had left
      // jointly unpinned: `_setMirror`'s clear of the latch and
      // `_releaseDeferredBlur`'s `!_visible` re-read each cited the other as the
      // mechanism making it redundant, so deleting them *together* failed
      // nothing and a maintainer reading the record could remove both and ship
      // a behaviour change green. A `minimize` is the route that reaches both:
      // it is the one transition to a false mirror that neither `show()` nor
      // `hide()` is involved in, so the latch survives into the release point
      // if that clear is gone, and issues a hide from there if the re-read is
      // gone too.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      // The user clicks away, and then the window manager iconifies the panel
      // before the round trip ends.
      window.emitEvent('blur');
      await pumpEventQueue();
      window.emitEvent('minimize');
      await pumpEventQueue();

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason: 'the iconify is what the mirror ends on',
      );
      expect(
        window.calls,
        isNot(contains('hide')),
        reason:
            'the panel is already off the screen: the blur belonged to the '
            'panel the minimize took away, and a hide issued for it now would '
            'unmap a window the user cannot see anyway',
      );
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.iconified,
      ]);
    });

    test('AD-8: a latched blur outliving dispose() moves no window — a '
        'torn-down adapter must not dismiss anything', () async {
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();

      // Disposal drains the parked show, so the request resumes — and reaches
      // its release point — with the adapter already closed.
      //
      // The outcome is what this pins, not a particular guard: two of them
      // stand between the release and the window, and deleting either one alone
      // leaves this row green. `_releaseDeferredBlur`'s own `_disposed` check
      // returns first; behind it, `hide()` returns without touching the seam
      // once `_disposed` is set, so the dismissal is inert even if the check is
      // removed (control 14). Both are stated as deliberate, because a
      // `_dismiss` refactored to reach the seam directly would need the first
      // one and nothing here would notice its absence until then.
      await visibility.dispose();
      await pumpEventQueue();
      await showing;

      expect(
        window.calls,
        isNot(contains('hide')),
        reason:
            'the release point runs on the way out of a request, which is '
            'exactly where a disposal lands; a hide issued from there would '
            'move a real window whose mirror is frozen',
      );
    });

    test('AD-15: a rejected focus-loss hide is logged and the mirror stays '
        'false', () async {
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();
      window.hideError = StateError('the window manager refused to unmap');

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('focus-loss hide'));
      expect(errors.single.context, {'error_type': 'StateError'});
    });

    test('AD-15: a rejected hide from a *deferred* focus-loss is logged the '
        'same way — one cause, one line', () async {
      // The latch reaches `_dismiss` by a second route, and a refusal there
      // must still name the focus loss rather than the close: an operator
      // reading the line has to be able to tell a compositor quirk from a
      // window the user explicitly dismissed.
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();
      window.emitEvent('blur');
      await pumpEventQueue();
      window.hideError = StateError('the window manager refused to unmap');

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('focus-loss hide'));
      expect(errors.single.context, {'error_type': 'StateError'});
    });

    test('CAP-14: a focus-out at a panel whose keyboard never went anywhere '
        'is not a dismissal', () async {
      // G-01-13. The daemon's own passive grab activating makes X send the
      // focused window a `FocusOut(mode=NotifyGrab)` — intercepted, not
      // transferred — and the plugin forwards it as a bare `blur` with the
      // mode discarded, so the panel dismissed itself on its own shortcut and
      // the toggle then re-showed it off a mirror that already truthfully read
      // hidden.
      witness.answer = true;
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
      expect(
        window.calls,
        ['show', 'focus'],
        reason:
            'no `hide` reached the window at all — the mirror staying true is '
            'the weaker half of this claim, because a mirror can be right '
            'about a window that moved anyway',
      );
      expect(window.visible, isTrue);
      expect(
        emitted,
        [PanelVisibilityState.shown],
        reason:
            'and no `focusLost` was announced, so `CorrectionController` never '
            'saw a departure it would have to reason about (AD-18)',
      );
    });

    test('CAP-14: a focus-out that really moved the keyboard is still a '
        'dismissal', () async {
      // Today's behaviour, stated as a row of its own so the fix above cannot
      // be widened into a suppression of CAP-14 itself. The witness answering
      // `false` is the whole of the seam's contract: `true` only where the
      // absence of a focus transfer is positively established.
      witness.answer = false;
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      expect(window.calls, ['show', 'focus', 'hide']);
      expect(window.visible, isFalse);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.focusLost,
      ]);
    });

    test('CAP-14: the window still holds the keyboard after a suppressed '
        'focus-out, so the next genuine one still dismisses', () async {
      // The row that pins `_focused` *surviving* the suppressed path, and it
      // is not a tidiness claim. UAT test 13 recorded presses 1 and 3 ending
      // on `FocusIn(NotifyUngrab)` and 2 and 4 on `FocusIn(NotifyNormal)`, so
      // an arm that cleared the flag on the suppressed path would depend on a
      // focus-in coming back to re-arm it — and where GDK delivers no
      // `NotifyUngrab` form, the next genuine blur is discarded by DW-33's
      // question instead. Keeping the flag where the keyboard demonstrably
      // never left removes that dependency outright.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      witness.answer = true;
      window.emitEvent('blur');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue, reason: 'the grab, suppressed');

      // No second `focus` in between: that is the point. Nothing re-arms the
      // flag, and the dismissal below has to work without it.
      witness.answer = false;
      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      expect(window.calls, ['show', 'focus', 'hide']);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.focusLost,
      ]);
    });

    test('CAP-14: the shipped witness for a host that cannot answer never '
        'suppresses — the Wayland arm', () async {
      // Driven through `AbsentKeyboardFocusWitness` rather than the fake,
      // because this is the production collaborator every non-X11 session
      // gets, Wayland included: the portal takes no key grab, so nothing the
      // daemon does can produce the spurious focus-out, and no portal call
      // reports the keyboard owner either. A null object that answered `true`
      // would silently disable CAP-14 on every such host, and no wiring grep
      // would see it.
      await visibility.dispose();
      window = FakePanelWindow();
      visibility = WindowManagerPanelVisibility(
        window: window,
        focusWitness: const AbsentKeyboardFocusWitness(),
        requestTimeout: _ampleBound,
        logger: logger,
      );

      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      expect(window.calls, ['show', 'focus', 'hide']);
      expect(window.visible, isFalse);
    });

    test('AD-15: a witness that throws is taken as a real focus loss and says '
        'so once', () async {
      // The seam promises a value. One that throws instead must not take the
      // daemon with it, must not suppress the dismissal either — a throw is an
      // uncertainty, and every uncertainty answers `false` — and must reduce to
      // a line carrying `error_type` and nothing more, because this adapter
      // sits on the panel the user types into.
      final escaped = <Object>[];

      await runZonedGuarded(() async {
        await _settled(visibility.show(), window);
        window.emitEvent('focus');
        await pumpEventQueue();
        witness.readError = StateError('the X server would not answer');

        window.emitEvent('blur');
        await pumpEventQueue();
        await window.settle();
        await pumpEventQueue();
      }, (Object error, StackTrace stack) => escaped.add(error));

      expect(visibility.isVisible, isFalse);
      expect(window.calls, ['show', 'focus', 'hide']);
      expect(witness.reads, 1, reason: 'asked once, not retried');
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('keyboard focus witness'));
      expect(errors.single.context, {'error_type': 'StateError'});
      expect(
        escaped,
        isEmpty,
        reason: 'the backstop caught it; nothing reached the zone',
      );
    });

    test(
      'AD-15: a witness that throws while recording does not escape the '
      'window-event listener, and the next focus-out still dismisses',
      () async {
        // The write half of the row above, and the reason it needs its own: the
        // recording runs inside the `_window.events` **listener callback**, and
        // a listener throw is not a stream error, so the subscription's
        // `onError` never sees it — the root zone
        // (`main.dart`'s `PlatformDispatcher.onError`) is what is left. That is
        // the escape route this guard closes, and it is why `escaped` being
        // empty is the load-bearing assertion here rather than a formality.
        //
        // The second half is the one worth asserting out loud: a failed
        // recording must not suppress anything. The fake's `answer` is left at
        // its default `false` — the direction the real witness answers when
        // nothing was witnessed — so the next genuine focus-out is a real focus
        // loss, exactly as it was before this seam existed.
        final escaped = <Object>[];

        await runZonedGuarded(() async {
          await _settled(visibility.show(), window);
          witness.recordError = StateError('the X server would not answer');

          window.emitEvent('focus');
          await pumpEventQueue();

          window.emitEvent('blur');
          await pumpEventQueue();
          await window.settle();
          await pumpEventQueue();
        }, (Object error, StackTrace stack) => escaped.add(error));

        expect(
          escaped,
          isEmpty,
          reason: 'the backstop caught it; nothing reached the root zone',
        );
        expect(
          witness.recordedGains,
          1,
          reason: 'the call was made, and then it failed',
        );
        final errors = logger.lines.where((line) => line.level == 'error');
        expect(errors, hasLength(1));
        expect(errors.single.message, contains('could not record'));
        // Map equality, not `containsPair`: a later key carrying the caught
        // object's own text turns this row red instead of shipping the user's
        // editor content to stderr.
        expect(errors.single.context, {'error_type': 'StateError'});
        expect(visibility.isVisible, isFalse);
        expect(window.calls, ['show', 'focus', 'hide']);
      },
    );

    test('DW-33 is answered before the witness is asked — a blur with no '
        'preceding focus spends no round trip', () async {
      // Two claims, and the second is what needs the read count. That a blur
      // at a window which never took the keyboard is no dismissal is DW-33's
      // own row above; what this one adds is that the adapter does not pay a
      // synchronous X round trip to find that out. The witness read is on the
      // blur path of a resident daemon, so a question asked on a path that
      // returns anyway is a cost with no answer attached.
      witness.answer = true;
      await _settled(visibility.show(), window);

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isTrue,
        reason:
            'DW-33: it never held the keyboard, so there is nothing to lose',
      );
      expect(window.calls, ['show', 'focus']);
      expect(witness.reads, isZero);
    });

    test('CAP-14: a focus gained at a visible panel is witnessed, and one at a '
        'false mirror is not', () async {
      // The `focus` arm's existing `_visible` guard governs the recording as
      // well as `_focused`, and it has to: what the witness compares against
      // must be the focus as it stood when *this* window said it held the
      // keyboard. A recording taken while the mirror reads false — our own
      // `focus()`'s event landing after the round trip that put the panel away
      // — would answer a later blur against a focus owner that was never ours.
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      expect(witness.recordedGains, 1);

      await _settled(visibility.hide(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      expect(
        witness.recordedGains,
        1,
        reason:
            'the trailing focus at a hidden panel recorded nothing, exactly as '
            'it set no `_focused`',
      );
    });

    test('DW-32: a latched blur released after the keyboard came back is not a '
        'dismissal', () async {
      // The latch route reaches `_dismiss` past `_onBlur`'s questions, so the
      // fourth question has to be asked again at the release point or the
      // suppression is only half wired: a grab that fires during a round trip
      // — AD-14's second launch, AD-12's tray entry, both full round trips
      // against a mapped focused window — would still dismiss the panel.
      //
      // Read the witness's two answers as the two moments they are: at the
      // blur the focus had moved, so the blur is latched; by the release the
      // keyboard is back, so there is no dismissal left to perform.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      witness.answer = false;
      window.emitEvent('blur');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue, reason: 'held, not obeyed');

      witness.answer = true;
      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
      expect(window.calls, [
        'show',
        'focus',
        'show',
      ], reason: 'no `hide` was ever issued, from either route');
      expect(window.visible, isTrue);
      expect(emitted, [PanelVisibilityState.shown]);
    });

    test('DW-32: a latched blur released with the keyboard still elsewhere is '
        'a dismissal', () async {
      // Unchanged, and stated beside its twin so the question added at the
      // release point cannot be widened into a suppression of the DW-32 case
      // it was added to narrow.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      final showing = visibility.show();
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      expect(window.calls, ['show', 'focus', 'show', 'hide']);
      expect(window.visible, isFalse);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.focusLost,
      ]);
    });
  });

  group('DW-30: every departure is named where the mirror moves', () {
    // The whole attribution table in one place, one row per site that can move
    // the mirror down, plus the return route the pair has.
    //
    // Deliberately separate from the mechanism rows above, which assert the
    // *mirror* and the window agreeing and read the emission as a side claim.
    // These rows assert only the label, because the label is now a contract of
    // its own: `CorrectionController` reads it to decide whether a session ends
    // (AD-18), so a site that names its departure wrongly discards the user's
    // typed text or keeps text they asked to be rid of, with the mirror and the
    // window both perfectly correct throughout.
    //
    // The human's rule is three-way, not two: `dismissed` ends a session,
    // `iconified` and `focusLost` do not.

    test('CAP-2/DW-30: a requested hide reports dismissed — the hotkey toggle '
        'at a visible panel is the gesture that asks for this', () async {
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      await _settled(visibility.hide(), window);

      expect(
        emitted,
        [PanelVisibilityState.shown, PanelVisibilityState.dismissed],
        reason: 'the user asked for the window to go away, so the session ends',
      );
    });

    test(
      'CAP-14/DW-30/PANEL-19: a late hide echo cannot dismiss a visible panel',
      () async {
        // The plugin emits this only from gtk_widget_hide, but carries no
        // request id. A prior focus-loss hide can echo after a later show, so
        // neither the mirror nor this event can supply a dismissal reason.
        final emitted = <PanelVisibilityState>[];
        visibility.changes.listen(emitted.add);
        await _settled(visibility.show(), window);

        window.emitEvent('hide');
        await pumpEventQueue();

        expect(
          emitted,
          [PanelVisibilityState.shown],
          reason: 'an echo cannot replace the request-owned departure reason',
        );
      },
    );

    test('CAP-2/DW-12/DW-30: the close arm reports dismissed, and its log line '
        'stays its own — the cause and the departure are two facts', () async {
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.hideError = StateError('the window manager refused to unmap');

      window.emitEvent('close');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        emitted,
        [PanelVisibilityState.shown, PanelVisibilityState.dismissed],
        reason:
            'a close is the user dismissing the window, so it takes the same '
            'half of the rule a hide() request takes',
      );
      expect(
        logger.lines.single.message,
        contains('close hide'),
        reason:
            "and the operator's vocabulary is untouched by the session's: this "
            'refusal is still the close one, not a focus-loss one',
      );
    });

    test('CAP-14/DW-30: the immediate focus-loss hide reports focusLost — the '
        'click-away dismissed the window, not the work in it', () async {
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        emitted,
        [PanelVisibilityState.shown, PanelVisibilityState.focusLost],
        reason:
            'the user clicked away; they did not ask for what they had typed '
            'to be thrown away, so the session survives the return',
      );
    });

    test('CAP-14/DW-30: a latched focus-loss hide reports focusLost too — one '
        'round trip later is still a focus loss', () async {
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      // AD-14's second launch, parked at the window: the blur is latched rather
      // than obeyed, and reconsidered when the chain lets go (DW-32).
      final showing = visibility.show();
      await pumpEventQueue();
      window.emitEvent('blur');
      await pumpEventQueue();

      await window.settle();
      await showing;
      await pumpEventQueue();

      expect(
        emitted,
        [PanelVisibilityState.shown, PanelVisibilityState.focusLost],
        reason:
            'the deferred route is the same cause reaching the window a round '
            'trip late, so it cannot end a session the immediate one keeps',
      );
    });

    test('CAP-2/DW-30: a minimize reports iconified — the user did not ask to '
        'be done with the window', () async {
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);

      window.emitEvent('minimize');
      await pumpEventQueue();

      expect(
        emitted,
        [PanelVisibilityState.shown, PanelVisibilityState.iconified],
        reason:
            'a workspace switch or a show-desktop gesture hands back the same '
            'window with the same text in it, and the press that brings it '
            'back must not discard that text (DW-30)',
      );
    });

    test(
      'CAP-2/DW-31/DW-30: the latched restore reports shown, so a believed '
      'pair costs no session at all — the pair is where DW-30 bit hardest',
      () async {
        final emitted = <PanelVisibilityState>[];
        visibility.changes.listen(emitted.add);
        await _settled(visibility.show(), window);

        // The pair arrives inside one of our requests, which is the interleaving
        // DW-31's latch exists for: the minimize is believed and the restore
        // undoing it walks past the guard.
        final showing = visibility.show();
        await pumpEventQueue();
        window.emitEvent('minimize');
        await pumpEventQueue();
        window.emitEvent('restore');
        await pumpEventQueue();

        await window.settle();
        await showing;
        await pumpEventQueue();

        expect(
          emitted,
          [
            PanelVisibilityState.shown,
            PanelVisibilityState.iconified,
            PanelVisibilityState.shown,
          ],
          reason:
              'a restored panel and a summoned one are in the same place, so the '
              'return is plain shown — and because the departure before it was '
              'an iconify, no session begins and the editor survives the pair',
        );
      },
    );

    test('CAP-2/DW-12/DW-30: a close arriving at a panel that is already '
        'iconified reports dismissed — the last reason is the one the next '
        'summon obeys', () async {
      // The re-attribution row, and the defect the first pass of this change
      // shipped: `_setMirror` early-returned whenever `isVisible` did not move,
      // so a dismissal landing over a panel that was already away was swallowed
      // and the summon after an explicit close handed back the session the user
      // had just closed — CAP-2's re-seed never running, with the mirror and the
      // window both perfectly correct throughout.
      //
      // The DW-31 row that pins the *latch* for this sequence asserts the same
      // third value from the other end; this one asserts only the label, which
      // is the contract `CorrectionController` reads.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      window.emitEvent('minimize');
      await pumpEventQueue();
      window.emitEvent('close');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        emitted,
        [
          PanelVisibilityState.shown,
          PanelVisibilityState.iconified,
          PanelVisibilityState.dismissed,
        ],
        reason:
            'the mirror was already false when the close arrived, and the close '
            'is still news: it replaced *why* the panel is away, which is the '
            'whole of what the three-way rule reads',
      );
    });

    test('CAP-2/DW-12/DW-30: a close arriving at a panel a focus loss already '
        'took away reports dismissed — the other survivable departure, and the '
        'one a refused hide leaves standing', () async {
      // The sibling of the row above, and the half of the re-attribution rule
      // that the `iconified` row cannot reach. `focusLost` is the commonest
      // departure there is (CAP-14 issues one on every click-away), so it is
      // the standing departure a later dismissal most often has to displace —
      // and it is the one a refused or abandoned hide leaves standing while the
      // window is still mapped, which is the arrangement the `hide` arm's
      // `_visible` gate exists for.
      //
      // Pinned separately from the `iconified` row because a suppression keyed
      // on `focusLost` — the shape a maintainer reaches for when narrowing the
      // guard, since `focusLost` is the departure the gate above is written
      // about — leaves that row and every other row in this file green while
      // the adapter stops reporting a dismissal the user really made. The
      // controller's latch then never ends the session and the summon after an
      // explicit close hands back the session they closed: DW-30's own defect,
      // reached through the survivable departure the other row does not use.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);
      await _settled(visibility.show(), window);
      window.emitEvent('focus');
      await pumpEventQueue();

      // CAP-14's focus-loss hide: the mirror goes false and the departure
      // standing on the stream is `focusLost`.
      window.emitEvent('blur');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      window.emitEvent('close');
      await pumpEventQueue();
      await window.settle();
      await pumpEventQueue();

      expect(
        emitted,
        [
          PanelVisibilityState.shown,
          PanelVisibilityState.focusLost,
          PanelVisibilityState.dismissed,
        ],
        reason:
            'the panel was already away for a survivable reason and the user '
            'then closed it: the close replaced why it is away, and the next '
            'summon obeys the close',
      );
    });

    test(
      'CAP-2/DW-30: a departure that repeats the standing one reports nothing '
      '— the guard is "have I already said this", not "did the mirror move"',
      () async {
        // The boundary on the row above, and the half that keeps the stream from
        // becoming chatty. Without it every refused hide and every queued
        // dismissal behind one would re-announce a departure the controller
        // already has, and the port's transition-only contract — which
        // everything else in this file reads — would be gone.
        final emitted = <PanelVisibilityState>[];
        visibility.changes.listen(emitted.add);
        await _settled(visibility.show(), window);

        await _settled(visibility.hide(), window);
        await _settled(visibility.hide(), window);
        // And the window's own report of the same absence, with nothing of ours
        // outstanding to swallow it.
        window.emitEvent('hide');
        await pumpEventQueue();

        expect(
          emitted,
          [PanelVisibilityState.shown, PanelVisibilityState.dismissed],
          reason:
              'three requests and events saying the panel is dismissed, and one '
              'emission: the second and third know nothing the first did not',
        );
      },
    );
  });

  group('teardown (CAP-7)', () {
    test('AD-8: a disposed adapter closes changes and deregisters from the '
        'window', () async {
      final closed = visibility.changes.isEmpty;

      await visibility.dispose();

      expect(await closed, isTrue);
      expect(window.disposed, isTrue);
    });

    test('AD-8: show() and hide() are no-ops once disposed — a press landing '
        'in the teardown gap must not move a real window', () async {
      await visibility.dispose();

      await visibility.show();
      await visibility.hide();

      expect(
        window.calls,
        isEmpty,
        reason:
            'the hotkey adapter closes after this one, so a press can still '
            'arrive; a window moved by a frozen mirror is worse than nothing',
      );
    });

    test('AD-8: a window event after disposal reaches nothing', () async {
      await visibility.dispose();

      window.emitEvent('show');
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
    });

    test('CAP-7: disposing twice is a no-op', () async {
      await visibility.dispose();

      await expectLater(visibility.dispose(), completes);
    });
  });

  group('a window call that never answers (DW-28)', () {
    // The only rows in this file that may reach the bound, so the only ones
    // given a bound they can. Built over the outer one rather than beside it:
    // every row here would otherwise have to remember to construct its own, and
    // the row that forgot would pass by never timing out at all.
    setUp(() async {
      await visibility.dispose();
      window = FakePanelWindow();
      visibility = WindowManagerPanelVisibility(
        window: window,
        focusWitness: FakeKeyboardFocusWitness(),
        requestTimeout: _stallBound,
        logger: logger,
      );
    });

    test('DW-28: a call that never settles is abandoned at the bound, and the '
        'caller is told nothing worse than that the request is over', () async {
      // Mechanism two chains every request onto the one before it, so before
      // this bound a single unresponsive call parked the whole chain and the
      // panel stopped responding until the daemon was restarted.
      await expectLater(
        visibility.show(),
        completes,
        reason:
            'the port says a resolved future means the request left the queue, '
            'not that the window moved — an abandoned one is not a rejection',
      );

      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('show'));
      expect(errors.single.context, {
        'call': 'show',
        'timeout_ms': _stallBound.inMilliseconds,
      });
    });

    test('AD-8: an abandoned show issues no focus — no second call against an '
        'unresponsive window', () async {
      await visibility.show();

      expect(
        window.calls,
        ['show'],
        reason:
            'focus() is gtk_window_present, which maps a hidden toplevel: '
            'issuing it after a show that was abandoned would put on screen '
            'the very window whose map never answered',
      );
    });

    test('DW-28: the queue advances past an abandoned call — the next press is '
        'served without a restart', () async {
      final stalling = visibility.show();
      await pumpEventQueue();
      // Queued behind a call the window will never answer. Before the bound
      // this future never resolved and neither did any press after it.
      final hiding = visibility.hide();

      await stalling;
      await window.settle();
      await hiding;

      expect(window.calls, [
        'show',
        'hide',
      ], reason: 'the later request reached the window on its own');
      expect(window.visible, isFalse);
      expect(window.visible, visibility.isVisible);
      // The later request has to be *served*, not merely issued and abandoned
      // in its turn. Without this the row passes on a loaded machine where the
      // hide expired too — same window state, none of the behaviour claimed.
      expect(
        logger.lines.where((line) => line.level == 'error'),
        hasLength(1),
        reason: 'exactly one call was abandoned: the one never answered',
      );
    });

    test('DW-28: a hide that never answers is abandoned and named — the bound '
        'is on every call, not only on the map', () async {
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      // The window manager mapped the panel itself, so the mirror is up without
      // a request of ours having to settle first — this row is about the hide.
      window.emitEvent('show');
      await pumpEventQueue();
      expect(visibility.isVisible, isTrue);

      await expectLater(visibility.hide(), completes);

      expect(window.calls, ['hide']);
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(
        errors.single.context,
        {'call': 'hide', 'timeout_ms': _stallBound.inMilliseconds},
        reason:
            'the line says which call went unanswered, or an operator '
            'cannot tell a window that will not map from one that will not unmap',
      );

      // The same claim the abandoned-show row below makes, on the other arm:
      // the user asked for the panel to go away and nothing has said otherwise,
      // so the next press must read it as hidden and show it. Without this,
      // writing the intent back on the hide branch leaves the whole suite
      // green.
      expect(visibility.isVisible, isFalse);
      expect(
        emitted,
        [PanelVisibilityState.shown, PanelVisibilityState.dismissed],
        reason:
            'the map the window manager did, then the hide the mirror led '
            'with — abandoning the call is not a third transition to report',
      );
    });

    test('PANEL-14: a timed-out focus still owns its late echo', () async {
      // The second half of a show is a second round trip, and it is the half a
      // bare `await _window.focus()` would leave unbounded: the map answers, so
      // every row about a stalled *show* stays green while the chain parks on
      // the focus behind it.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      final showing = visibility.show();
      await pumpEventQueue();
      window.releaseNext();

      await expectLater(showing, completes);

      expect(window.calls, ['show', 'focus']);
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(errors.single.context, {
        'call': 'focus',
        'timeout_ms': _stallBound.inMilliseconds,
      });

      // The intent stands on this arm too — and the map did land, so mirror and
      // window agree. Without it, writing the mirror back on the focus branch
      // leaves every other row in this group green.
      expect(visibility.isVisible, isTrue);
      expect(window.visible, isTrue);
      expect(
        emitted,
        [PanelVisibilityState.shown],
        reason:
            'the mirror led at the call, and abandoning the trailing focus is '
            'not a second transition to report',
      );

      // The caller is released, but the native focus call is still owned.
      // Its echo cannot be mistaken for an external hide before it settles.
      window.emitEvent('hide');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
    });

    test(
      'PANEL-14: a late abandoned show is repaired without a new session',
      () async {
        // The late map is native reality, but it cannot become a new session.
        // Its settlement queues a hide after the newer dismissal completed.
        final emitted = <PanelVisibilityState>[];
        visibility.changes.listen(emitted.add);

        await visibility.show();
        final hiding = visibility.hide();
        await pumpEventQueue();

        // The later request answers first: the queue advanced past a call the
        // window has still not settled.
        window.releaseCall('hide');
        await hiding;

        expect(visibility.isVisible, isFalse);
        expect(window.visible, isFalse);

        window.releaseCall('show');
        await pumpEventQueue();

        expect(
          window.visible,
          isTrue,
          reason:
              'the bound stopped the daemon waiting on the map, it did not stop '
              'the map',
        );
        expect(visibility.isVisible, isFalse);
        window.releaseCall('hide');
        await pumpEventQueue();
        expect(window.visible, isFalse);
        expect(emitted, [
          PanelVisibilityState.shown,
          PanelVisibilityState.dismissed,
        ], reason: 'the abandoned show cannot begin another session');
      },
    );

    test('PANEL-15: a late abandoned focus is repaired after dismissal', () async {
      // A late gtk_window_present can still map and raise the toplevel.
      // The adapter retains ownership and restores the newer hide intent.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      final showing = visibility.show();
      await pumpEventQueue();
      // The map answers; the present that follows it is what reaches the bound.
      window.releaseCall('show');
      await showing;

      expect(
        window.calls,
        ['show', 'focus'],
        reason: 'the show answered, so the focus was issued and then abandoned',
      );

      final hiding = visibility.hide();
      await pumpEventQueue();
      window.releaseCall('hide');
      await hiding;

      expect(visibility.isVisible, isFalse);
      expect(window.visible, isFalse);

      window.releaseCall('focus');
      await pumpEventQueue();

      expect(
        window.visible,
        isTrue,
        reason:
            'gtk_window_present maps as well as raises, so the abandoned call '
            'put the dismissed panel back on screen — and unlike the show arm '
            'it also has the keyboard',
      );
      expect(visibility.isVisible, isFalse);
      window.releaseCall('hide');
      await pumpEventQueue();
      expect(window.visible, isFalse);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.dismissed,
      ], reason: 'the abandoned present cannot begin another session');
    });

    test('CAP-14/DW-28/DW-30: an abandoned focus-loss hide landing later does '
        'not turn the click-away into a dismissal', () async {
      // The `hide` arm's re-attribution defect, and the reason that arm is
      // gated on `_visible`. CAP-14's own hide moves the mirror and reports
      // `focusLost`; the platform call behind it is abandoned at the bound, so
      // `_outstanding` is back down while the call is still in flight. When it
      // lands, `gtk_widget_hide` fires the GTK `hide` signal and this adapter
      // hears its own request back with nothing outstanding to swallow it.
      //
      // Ungated, `_reportDeparture` would accept it: the mirror already reads
      // false, but `dismissed` is not `focusLost`, so the repeat guard lets it
      // through and the stream reports a dismissal the user never asked for.
      // The next summon would then clear the panel and re-read the clipboard —
      // DW-30's own defect, reached through DW-30's fix, on the commonest
      // departure there is.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      final showing = visibility.show();
      await window.settle();
      await showing;
      window.emitEvent('focus');
      await pumpEventQueue();

      // The user clicks away. The mirror leads and the hide is issued, but the
      // window never answers it inside the bound, so the request lets go of the
      // chain while its call is still in flight. Waited out rather than pumped:
      // the abandonment *is* the bound expiring, and `_dismiss` issues the hide
      // unawaited, so there is no future here to await instead.
      window.emitEvent('blur');
      await pumpEventQueue();
      await Future<void>.delayed(
        _stallBound + const Duration(milliseconds: 50),
      );
      await pumpEventQueue();

      expect(
        logger.lines.where((line) => line.level == 'error').single.message,
        contains('hide'),
        reason: 'the premise of this row — the call was abandoned at the bound',
      );
      expect(visibility.isVisible, isFalse);
      expect(emitted, [
        PanelVisibilityState.shown,
        PanelVisibilityState.focusLost,
      ], reason: 'the click-away, reported as the departure it is');

      // Only now does the abandoned unmap land, and the GTK widget `hide`
      // signal it raises comes back to us as an event.
      window.releaseCall('hide');
      await pumpEventQueue();

      expect(window.visible, isFalse);
      expect(visibility.isVisible, isFalse);
      expect(
        emitted,
        [PanelVisibilityState.shown, PanelVisibilityState.focusLost],
        reason:
            'and no third value: the echo of our own hide knows nothing about '
            'why the panel went away, so it must not be allowed to rename it',
      );
    });

    test(
      'PANEL-14: a late abandoned hide restores the requested panel',
      () async {
        // A stale unmap can still land physically. It cannot turn the newer
        // shown intent into a dismissal or discard the live editor session.
        final emitted = <PanelVisibilityState>[];
        visibility.changes.listen(emitted.add);

        final showing = visibility.show();
        await window.settle();
        await showing;

        expect(window.visible, isTrue);

        // Abandoned: the window never answers this unmap.
        await visibility.hide();

        expect(
          window.visible,
          isTrue,
          reason:
              'the bound stopped the daemon waiting, not the window unmapping',
        );

        // The user presses again. Every call answers, and none of them is a
        // transition, so this request drives no event at all.
        final again = visibility.show();
        await pumpEventQueue();
        window.releaseCall('show');
        await pumpEventQueue();
        window.releaseCall('focus');
        await again;

        expect(visibility.isVisible, isTrue);
        expect(window.visible, isTrue);

        // Only now does the abandoned unmap land.
        window.releaseCall('hide');
        await pumpEventQueue();

        expect(
          window.visible,
          isFalse,
          reason: 'a call abandoned at the bound is not a call cancelled',
        );
        expect(visibility.isVisible, isTrue);
        window.releaseCall('show');
        await pumpEventQueue();
        window.releaseCall('focus');
        await pumpEventQueue();
        expect(window.visible, isTrue);
        expect(emitted, [
          PanelVisibilityState.shown,
          PanelVisibilityState.dismissed,
          PanelVisibilityState.shown,
        ]);
      },
    );

    test('AD-15: a call that refuses *after* it was abandoned is absorbed — a '
        'late refusal is not an unhandled error on the exit path', () async {
      // Nothing in this adapter states this: it is a property of
      // `Future.timeout`, which keeps its own listener on the source and drops
      // whatever arrives once the bound has already completed the result. The
      // obvious rewrites — `Future.any` with a `Future.delayed`, or a
      // hand-rolled completer — leave the source with no error handler, and a
      // window that refuses late then becomes an uncaught zone error in a
      // daemon whose whole job is to stay up. This is what would fail.
      final escaped = <Object>[];
      window.showError = StateError('the window refused, late');

      await runZonedGuarded(() async {
        await expectLater(visibility.show(), completes);
        window.releaseCall('show');
        await pumpEventQueue();
      }, (Object error, StackTrace stack) => escaped.add(error));

      expect(escaped, isEmpty);
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(
        errors,
        hasLength(1),
        reason:
            'one line, for our own expiry — the refusal arrived after the '
            'request was already over and there is no caller left to tell',
      );
      expect(errors.single.context, {
        'call': 'show',
        'timeout_ms': _stallBound.inMilliseconds,
      });
    });

    test('DW-28: an abandoned show leaves the intent standing — the mirror '
        'stays true and reports one transition, not two', () async {
      // The same claim the rejected-show row above makes for a refusal: the
      // user asked for the panel and nothing has said otherwise, so the next
      // press must read it as shown and hide it. Nothing else here pins the
      // mirror after an abandonment — writing the intent back on this branch
      // leaves every other row in the group green.
      final emitted = <PanelVisibilityState>[];
      visibility.changes.listen(emitted.add);

      await visibility.show();

      expect(visibility.isVisible, isTrue);
      expect(
        emitted,
        [PanelVisibilityState.shown],
        reason:
            'the mirror led at the call, and abandoning the call is not a '
            'second transition to report',
      );
    });

    test('DW-28: bounding a chain link surrenders serialisation — the '
        'abandoned call is still in flight behind the next one', () async {
      // Stated in the class doc as the price of mechanism four, and pinned here
      // so it is a decision rather than a surprise. The queue-advance row above
      // only exercises the benign case, where the abandoned call never lands.
      await visibility.show();
      final hiding = visibility.hide();
      await pumpEventQueue();

      expect(
        window.inFlight,
        2,
        reason:
            'mechanism two exists to keep the window holding at most one of our '
            'calls; a call abandoned is not a call cancelled, and this is the '
            'one thing that can break that promise',
      );

      // The abandoned show lands late, *during* the hide — so its echo is
      // swallowed by the `_outstanding` guard like any other, and the mirror
      // does not follow the window back up.
      window.releaseNext();
      await pumpEventQueue();

      expect(
        visibility.isVisible,
        isFalse,
        reason: 'the mirror holds the later intent, not the older echo',
      );
      expect(
        window.visible,
        isTrue,
        reason:
            'and the window really did map: the bound stopped the daemon '
            'waiting on the call, it did not stop the call',
      );

      await window.settle();
      await hiding;

      expect(window.visible, isFalse);
      expect(
        window.visible,
        visibility.isVisible,
        reason: 'the later request is what puts the two back in step',
      );
    });

    test('PANEL-14: an abandoned native call still owns its echo', () async {
      await visibility.show();

      // The caller has timed out, but native ownership has not ended.
      window.emitEvent('hide');
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
    });

    test(
      'PANEL-14: a latched blur waits for native settlement after timeout',
      () async {
        // Timeout releases the caller but not the native operation. The blur
        // remains held until that operation settles, avoiding a racing hide.
        await _settled(visibility.show(), window);
        window.emitEvent('focus');
        await pumpEventQueue();

        // AD-14's second launch against an already-visible, focused panel — and
        // this time the window never answers the map.
        final stalling = visibility.show();
        await pumpEventQueue();

        window.emitEvent('blur');
        await pumpEventQueue();

        expect(
          visibility.isVisible,
          isTrue,
          reason: 'held, not obeyed: our own map can produce a focus-out too',
        );

        // The bound expires, the request lets go, and the release point runs.
        await stalling;
        await pumpEventQueue();

        expect(visibility.isVisible, isTrue);

        await window.settle();
        await pumpEventQueue();

        expect(
          window.calls,
          contains('hide'),
          reason:
              'a real hide against the window, not a mirror write — the same '
              'dismissal the completed-round-trip row asserts, reached through '
              'the timeout path',
        );
        expect(window.visible, isFalse);
        expect(window.visible, visibility.isVisible);
        final errors = logger.lines.where((line) => line.level == 'error');
        expect(
          errors,
          hasLength(1),
          reason:
              'exactly one call was abandoned — without this the row passes on a '
              'loaded machine where the dismissing hide expired as well, which is '
              'the same window state and none of the behaviour claimed',
        );
        expect(errors.single.context, {
          'call': 'show',
          'timeout_ms': _stallBound.inMilliseconds,
        });
      },
    );

    test(
      'AD-8: a superseded, a disposal-abandoned and a timed-out request all '
      'resolve rather than throw — the uniform outcome the port states',
      () async {
        // The first two abandonments have nothing to do with the bound, so they
        // run over a window bounded well past anything this row can reach —
        // otherwise a slow machine would make all three the *same* case and the
        // row would prove one third of what it claims.
        final ordinary = FakePanelWindow();
        final unbounded = WindowManagerPanelVisibility(
          window: ordinary,
          focusWitness: FakeKeyboardFocusWitness(),
          requestTimeout: _ampleBound,
          logger: logger,
        );

        final superseded = unbounded.show();
        final winning = unbounded.hide();
        await ordinary.settle();

        await expectLater(superseded, completes);
        await expectLater(winning, completes);

        final atDisposal = unbounded.show();
        await pumpEventQueue();
        await unbounded.dispose();

        await expectLater(atDisposal, completes);

        await expectLater(
          visibility.show(),
          completes,
          reason:
              'three different reasons a request never moved the window, one '
              'outcome for the caller: isVisible and changes are where the '
              'intent is observable',
        );
      },
    );

    test(
      'AD-15: a logger that throws while reporting an abandoned call does '
      'not let the failure escape — the reporting channel is what broke',
      () async {
        final escaped = <Object>[];
        final throwing = ThrowingLogger();

        await runZonedGuarded(() async {
          final stalling = FakePanelWindow();
          final adapter = WindowManagerPanelVisibility(
            window: stalling,
            focusWitness: FakeKeyboardFocusWitness(),
            requestTimeout: _stallBound,
            logger: throwing,
          );

          await adapter.show();
          await adapter.dispose();
        }, (Object error, StackTrace stack) => escaped.add(error));

        expect(
          throwing.attempts,
          ['error'],
          reason:
              'the attempt proves the timeout arm fired; a row asserting only '
              'that nothing escaped stays green when the arm never runs',
        );
        expect(escaped, isEmpty);
      },
    );
  });
}

/// Issues [request], lets the window answer everything it triggers, and waits
/// for the caller's own future — the settled state every window-state
/// assertion is read from.
Future<void> _settled(Future<void> request, FakePanelWindow window) async {
  await window.settle();
  await request;
}
