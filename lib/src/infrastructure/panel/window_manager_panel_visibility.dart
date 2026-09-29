import 'dart:async';

import '../../domain/logger.dart';
import '../../domain/panel/panel_visibility.dart';
import 'keyboard_focus_witness.dart';
import 'panel_window.dart';

/// AD-8's [PanelVisibility], over a [PanelWindow].
///
/// Four mechanisms have to hold together, and only the first is obvious.
///
/// *One — the mirror leads.* [isVisible] is assigned, and [changes] emits,
/// **before the first await** of [show] and [hide]. AD-8 forbids the toggle
/// from awaiting anything, so a mirror that only moved when the window manager
/// answered would read stale for the whole round trip and a second press inside
/// it would show the panel again instead of hiding it.
///
/// *Two — requests are serialised.* `windowManager.show()` is not one channel
/// call: it awaits an `isMinimized()` hop and only then invokes `show`, while
/// `hide()` invokes immediately. Two unserialised requests therefore reach the
/// platform out of order — a `hide()` issued during a `show()` arrives *first*,
/// and the show maps the window behind it. This is a reordering point, not a
/// latency point, so a queue rather than a timeout is what answers it.
///
/// *Three — a superseded request is abandoned, not completed.* [show] must also
/// focus: `window_manager`'s Linux `show` is `gtk_widget_show` alone, which
/// neither raises the window nor takes the keyboard, while CAP-1 asks for
/// "visible **and** focused". But `focus()` is `gtk_window_present`, and that
/// **maps a hidden toplevel** — so a trailing focus belonging to a request a
/// later press already superseded puts the panel back on screen with the mirror
/// reading false. A request whose intent the mirror no longer holds therefore
/// issues *nothing at all*, and so produces no echo either.
///
/// *Four — a window call is bounded without forgetting it.* [_requestTimeout]
/// releases the caller and advances the intent queue. The native call can still
/// be running: [_nativeInFlight] retains its ownership until settlement, so its
/// echo is not treated as an external visibility change and a deferred blur
/// cannot start a racing hide. If a timed-out call settles after a newer intent
/// has completed, [_nativeSettled] queues a repair in the current direction.
/// A native call that never settles cannot be cancelled by this Dart seam.
///
/// Window events divide on **two independent axes**, and that they are
/// independent is the whole argument of this arrangement. Stating them as one
/// taxonomy is what hid a defect from a reader once already.
///
/// *Axis one — echo-capable, or structurally external.* Can one of our own
/// three calls cause this event? This adapter calls `show`, `hide` and `focus`
/// and nothing else. `focus()` is `gtk_window_present`, which maps a hidden
/// toplevel; `windowManager.show()` deiconifies a minimised one as part of its
/// own implementation; and unmapping a focused window takes its keyboard away.
/// So `show`, `hide`, `restore`, `focus` and `blur` can all be the window
/// reporting one of our own requests back at us — they are **echo-capable**.
/// `minimize` and `close` cannot: nothing we call iconifies, and nothing we
/// call produces a GTK `delete-event`. They are **structurally external**, and
/// are therefore obeyed whatever is outstanding — a `minimize` moves the mirror
/// straight (DW-31), a `close` puts the window away for real (DW-12).
/// `minimize` and `restore` reach Dart from the same GTK `window-state-event`
/// handler and still land on opposite sides of this axis, which is why it cannot
/// be read off the signal.
///
/// *Axis two — a claim about the mirror, or not.* Does believing the event mean
/// writing [isVisible]? `show`, `restore` and `minimize` can each report
/// whether the panel is up. The GTK `hide` signal only echoes our own request,
/// whose departure was already reported with its reason. `focus` reports the
/// keyboard, which is a different fact about the same window. `close` and `blur`
/// do not either — they are *intents*, and this adapter answers them the only
/// honest way, with a real `hide` through [_dismiss].
///
/// `_reconcile` — the active-request guard — takes the echo-capable mirror
/// claims that can add information: `show` and `restore`. Inside that set
/// the guard is what keeps an echo arriving *during* one of our requests from
/// being read as the window manager acting on its own, which is the one case an
/// event knows something the intent does not.
///
/// **The intersection would break a pair, so one `restore` steps out of it.**
/// `minimize` and `restore` cancel each other out, and putting them on opposite
/// sides of the guard makes them stop doing that during one of our requests: the
/// `minimize` is believed, the `restore` that undoes it is swallowed, and the
/// mirror is left reading false over a window that is mapped with nothing able
/// to correct it. `main.dart` sets `setSkipTaskbar(true)`, so the hotkey is the
/// only route back to that panel, and against a false mirror that press resolves
/// to [show] rather than [hide] — so the panel stays on screen with nothing left
/// that can put it away, while the `_focused` clear on the way down has already
/// taken CAP-14's dismissal with it. So a believed `minimize` arms a
/// one-shot latch ([_believedMinimize]) and the next `restore` consumes it,
/// moving the mirror back whatever `_outstanding` reads. Every other `restore`
/// keeps the guard, unchanged, and that is what keeps the load-bearing case
/// intact: a `show()` parked with a `hide()` queued behind it cleared the latch
/// when those intents were expressed, so the show's own deiconify echo is still
/// swallowed and the queued hide still runs.
///
/// `focus` shows why the axes have to be kept apart. It is echo-capable, and it
/// is still believed whoever caused it — an echo of our own `focus()` reports
/// truthfully that the window holds the keyboard, so the `_outstanding` guard
/// would have nothing to swallow. What the arm needs instead is a `_visible`
/// guard, for a reason on neither axis: the plugin emits the event
/// asynchronously, so our own `focus()`'s event lands after that call's reply
/// and can arrive at a panel the same round trip has just put away. The arm says
/// how. `blur` is the other half of that pair and is answered by [_onBlur].
///
/// A timed-out call retains its native ownership. Its late `show` or `focus`
/// echo cannot report a new panel state; a `hide` echo is always ignored because
/// it carries no departure reason. A stale settlement queues
/// repair only after the latest intent has completed. The caller still receives
/// a bounded answer even when the native operation never settles.
///
/// [changes] emits **exactly on a transition of the state**, whatever caused it
/// — and every departure is *attributed*: a requested hide is `dismissed`, and
/// so is the `close` control because this adapter answers it with one; an
/// iconify is `iconified`; and CAP-14's focus-loss hide is `focusLost`. There is
/// no fourth source. In particular there is no external unmap to attribute: the
/// `hide` event is the GTK *widget* `hide` signal, so it can only ever be an
/// echo of a `hide` call of ours (see the `hide` arm). Attribution is made at
/// the request that moves the mirror, which
/// is why [_setMirror] takes a [PanelVisibilityState] rather than a bool:
/// nothing here can infer from a false mirror how the window came to be away,
/// and every caller can.
///
/// "A transition of the state" is wider than a transition of [isVisible], and
/// deliberately so. There is one way to be up, so a `shown` over a true mirror
/// is nothing; there are three ways to be away, so a *different* departure over
/// a false mirror is news — the reason the panel is away has been replaced, and
/// under the three-way session rule the last reason is the one that decides the
/// next summon. [_reportDeparture] is where that is done and bounded.
///
/// What the attribution buys is stated in `CorrectionController`, not here — the
/// port is descriptive and AD-18's rule belongs to the ring above it. The
/// consequence worth knowing at this end is that a duplicate emission is no
/// longer uniformly expensive: a spurious `shown` after a `dismissed` is still a
/// duplicate clipboard read and a discarded editor, while one after an
/// `iconified` or a `focusLost` costs nothing at all.
///
/// **A fourth question was added to `blur`, and none of the four mechanisms
/// above moves because of it (G-01-13).** The `blur` this adapter answers is
/// not only "the user turned away": a passive key grab activating makes X send
/// the focused window a `FocusOut(mode=NotifyGrab)` — the keyboard was
/// intercepted, not transferred — and `window_manager 0.5.2` forwards it as a
/// bare `blur` with the mode discarded
/// (`window_manager_plugin.cc:979-982`, `:1108`). So the daemon's *own*
/// shortcut produced a dismissal, and that dismissal beat the toggle's own
/// activation by 4-12 ms, leaving `PanelController` reading a mirror that
/// already truthfully said hidden and re-showing the panel it had just
/// dismissed. [_onBlur] therefore also asks a [KeyboardFocusWitness] whether
/// the keyboard actually went anywhere, and a focus-out that demonstrably moved
/// no keyboard is not a dismissal. The question is a *fact* read from the
/// display server, not a timing guess — which is what makes it a fix rather
/// than a wider race.
///
/// Mechanism by mechanism, because "it does not disturb them" is the claim that
/// has to be checkable rather than asserted:
///
/// 1. *The mirror leads* — untouched. The witness writes no mirror and is read
///    only on a path that has already read one, so nothing about when
///    [isVisible] moves relative to an await changes.
/// 2. *Requests are serialised* — untouched. The witness never enters [_apply]'s
///    chain and issues no window call, so it cannot reorder anything against
///    anything.
/// 3. *A superseded request is abandoned* — untouched. The witness creates no
///    request, so there is none to supersede and none whose trailing half could
///    land late.
/// 4. *A window call is bounded* — the witness is **not** a window call, and it
///    is deliberately not bounded by [_requestTimeout]. It is one synchronous X
///    round trip on the platform thread. The residual, stated honestly: an X
///    server that stops answering blocks it. That adds no new class of hang —
///    GDK already makes synchronous round trips to that same server on that
///    same thread for its own per-frame work, so such a server has stopped the
///    daemon before this read is reached — and that sentence is *reasoning*,
///    not a measurement.
///
/// **DW-33 is preserved and strengthened, not contradicted.** Its question —
/// *did this window ever hold the keyboard?* — stays, and stays first. The new
/// question is orthogonal: *has the keyboard actually gone anywhere?* A
/// focus-out at a window that never took the keyboard and a focus-out that moved
/// no keyboard are two different non-dismissals, and the first is still answered
/// without consulting the server at all.
///
/// One behaviour change is recorded deliberately: a *foreign* client's global
/// shortcut firing while our panel is up no longer dismisses it. It used to, and
/// that was the diagnosis's smoking-gun control. Not dismissing is the more
/// correct answer — a foreign grab moves no focus and the panel gets the
/// keyboard back — but it is a change, and it is a consequence of keying on the
/// focus rather than on whose grab it was.
///
/// This type owns the [PanelWindow] it is given and the [KeyboardFocusWitness]
/// it is given: [dispose] disposes both, and disposing the window is what
/// deregisters the window listener.
final class WindowManagerPanelVisibility implements PanelVisibility {
  WindowManagerPanelVisibility({
    required this._window,
    required KeyboardFocusWitness focusWitness,
    required this._requestTimeout,
    required this._logger,
  }) : _witness = focusWitness {
    _events = _window.events.listen(
      _onWindowEvent,
      // AD-15 backstop: the seam promises a plain stream of event names. One
      // that errors instead must not end this subscription — every later
      // reconciliation depends on it.
      //
      // The `onDone` arm is explicitly defensive: the shipped seam closes
      // `events` only from its own `dispose()`, which this adapter calls after
      // cancelling, so completion cannot arrive here. Kept because
      // `PanelWindow.dispose()` advertises closing `events`, so any other
      // implementation can produce it — and a completion under a live adapter
      // is the worse half: reconciliation stops for good while the adapter
      // still reports healthy, taking CAP-14's focus-loss hide, the
      // external-hide correction and `minimize` with it. Log-only by decision
      // — no resubscription, retry or dead-stream flag — so the line states
      // that consequence rather than the bare event.
      onError: (Object error) => _log(
        () => _logger.error(
          'the panel window event stream errored',
          context: _errorContext(error),
        ),
      ),
      onDone: () => _log(
        () => _logger.error(
          'the panel window event stream closed; window events can no longer '
          'reconcile the panel visibility mirror',
        ),
      ),
    );
  }

  final PanelWindow _window;

  /// Answers whether a focus-out actually moved the keyboard (G-01-13).
  ///
  /// Written to only from the `focus` arm and read only from [_keyboardStillHere],
  /// so the whole of its influence on this file is one recording site and one
  /// question. Named `focusWitness` at the constructor rather than defaulted:
  /// a default would put a private policy at a construction site — the thing
  /// `composition_wiring_test.dart` pins [_requestTimeout] against — and would
  /// additionally make a site that forgot to pass one silently get the null
  /// object, so a wiring mistake would present as CAP-14 quietly never
  /// suppressing rather than as a compile error.
  final KeyboardFocusWitness _witness;

  /// How long one window call may hold the request chain before it is
  /// abandoned (mechanism four).
  ///
  /// Required, and stated at the composition root rather than defaulted here:
  /// this is one half of a single policy — how long a single platform call may
  /// hold the daemon — shared with `DaemonLifecycle`'s teardown steps, and a
  /// default would let the two drift apart without anyone deciding to.
  final Duration _requestTimeout;
  final Logger _logger;
  late final StreamSubscription<String> _events;

  /// Broadcast, which is what the port declares — and what makes the suite's
  /// second listener a decision rather than a runtime throw. In production
  /// `CorrectionController` is the only subscriber.
  final StreamController<PanelVisibilityState> _changes =
      StreamController<PanelVisibilityState>.broadcast();

  bool _visible = false;
  bool _disposed = false;
  int _intentGeneration = 0;
  int _nativeInFlight = 0;
  int _settledIntentGeneration = -1;

  /// How many callers are currently traversing the serialized request queue.
  ///
  /// While this or [_nativeInFlight] is non-zero,
  /// a window event that is echo-capable *and* may add a mirror claim —
  /// `show` or an unlatched `restore` — is our own intent coming back,
  /// already reported by the mirror. A GTK `hide` echo is ignored regardless
  /// of this count because its request already reported the departure reason.
  /// (`focus` is echo-capable too and claims nothing about the mirror.)
  /// A blur is held while either count is non-zero. Release waits for both
  /// counts to reach zero, including calls abandoned by the timeout.
  int _outstanding = 0;

  /// Whether the window holds the keyboard, as the window itself last said.
  ///
  /// Written from user and self focus events and cleared on a real blur or a
  /// hidden mirror. [_onBlur] needs this fact to distinguish a click-away from
  /// a focus-out at a window that never received keyboard focus (DW-33).
  bool _focused = false;

  /// A self-caused focus-in must not cancel a blur deferred under our present.
  bool _userFocusedSinceBlur = false;

  /// A `minimize` this adapter believed and no `restore` has undone yet.
  ///
  /// Four write sites, and naming all of them here is the point of this doc:
  /// **armed** by a `minimize` that actually took the panel down, **consumed**
  /// by the next `restore` — the arm a reader hunting for this flag is looking
  /// for — and **cleared** by [show] and [_hide], which is [hide]'s whole body,
  /// and two sites, not one.
  /// The suite's negative-control record measures those two separately (controls
  /// 18 and 19), and the measurement is **not** the symmetric one earlier prose
  /// here claimed: [show]'s clear alone fails nothing, [hide]'s alone fails one
  /// row, and deleting both fails two. So [hide]'s clear is individually
  /// load-bearing and [show]'s is not — do not read the pair as two
  /// interchangeably redundant lines. Nothing else arms it, so it is one-shot by
  /// construction rather than by convention.
  ///
  /// `minimize` is structurally external and moves the mirror whatever is
  /// outstanding,
  /// while `restore` is echo-capable and normally does not — and that asymmetry
  /// applied to a *pair* of events that cancel each other out leaves the mirror
  /// reading false over a mapped window with nothing able to correct it. This
  /// latch is what keeps the pair symmetric during one of our requests exactly
  /// as it is outside one: the arm that consumes it moves the mirror back
  /// without consulting the guard, and every `restore` that finds it clear takes
  /// the guard unchanged.
  ///
  /// Cleared by [show] and [_hide], where an intent is *expressed* rather than
  /// where the mirror happens to move — the same rule [_deferredBlur] follows,
  /// and for a sharper reason: after one of our requests a `restore` may be that
  /// request's own echo, which is the case the guard exists for, and
  /// `windowManager.show()` deiconifying a minimised window is exactly how that
  /// echo is produced.
  ///
  /// Deliberately **not** cleared by [_setMirror] or [_reportDeparture], unlike
  /// [_deferredBlur] — and the reason is stronger than earlier prose here
  /// claimed. That prose said a clear there "would be a fourth writer pinning
  /// nothing" — miscounted (the four sites are above, so it would be a fifth)
  /// and, more importantly, wrong: it fails three rows. The `minimize` arm arms
  /// this flag and *then* calls `_setMirror(iconified)` on the very next line,
  /// so a clear on that path disarms every believed minimize as it is armed and
  /// the pair stops cancelling out: the symmetric-pair row, the
  /// blur-after-a-pair row and the spent-latch row all fail, the same three as
  /// control 17. Measured, not reasoned.
  ///
  /// What the earlier reasoning was actually about is the mirror going back to
  /// *true*: the only routes there that bypass [show] and [hide] are an external
  /// `show` event and a guarded `restore`, and both run with nothing of ours
  /// outstanding — so a latch left standing across one of them can afterwards
  /// only write a value the mirror already holds. True, and not a reason to add
  /// a clear; it was simply the wrong half of the method to reason about.
  bool _believedMinimize = false;

  /// A blur that arrived while a request of ours was outstanding and has not
  /// been reconsidered yet (DW-32).
  ///
  /// A latch rather than a queue, deliberately: repeated blurs inside one round
  /// trip are one user turning away, not several. Released by
  /// [_releaseDeferredBlur] when [_outstanding] reaches zero.
  ///
  /// Dropped by three writers besides that release, all saying the same thing —
  /// a blur belongs to the intent it was raised under, and any newer intent
  /// voids it. [show] and [_hide] drop it because that is where an intent is
  /// *expressed*, including the requests that move no mirror at all (a `show()`
  /// at a visible panel, a `hide()` at a hidden one — the latter still reports
  /// a departure when it re-attributes one, see [_reportDeparture]);
  /// [_setMirror] and [_reportDeparture] drop it on any transition, which is the
  /// backstop for the intents the window states rather than the caller — a
  /// `close` or a `minimize`. A late `hide` echo is ignored.
  bool _deferredBlur = false;

  /// The departure [changes] last reported, and therefore the reason the panel
  /// is currently away.
  ///
  /// Read by [_reportDeparture] to answer the only question the four-valued
  /// stream needs and the two-valued mirror cannot: *have I already reported
  /// this?* Starts at [PanelVisibilityState.dismissed], because a panel that has
  /// never been shown is away for the reason a dismissal leaves it away — which
  /// is also what makes a `hide()` before the first `show()` report nothing.
  ///
  /// Meaningless while the mirror reads true, and not maintained there: nothing
  /// reads it in that state.
  PanelVisibilityState _lastDeparture = PanelVisibilityState.dismissed;

  /// The tail of the serialised request chain (mechanism two).
  Future<void> _queue = Future<void>.value();

  @override
  bool get isVisible => _visible;

  @override
  Stream<PanelVisibilityState> get changes => _changes.stream;

  @override
  Future<void> show() {
    if (_disposed) {
      // A press can land in the teardown gap between this adapter closing and
      // the hotkey adapter closing. Moving a real window whose mirror is
      // frozen is worse than doing nothing.
      return Future<void>.value();
    }
    // Before the mirror, because the mirror may not move. A `show()` against an
    // already-visible panel — AD-14's second launch, AD-12's tray entry — is
    // the request DW-32 exists for, and it is also the one `_setMirror`
    // early-returns on: the panel is already up, nothing written, no latch
    // cleared. A
    // blur latched under an earlier round trip would then release against this
    // summon and dismiss the panel the user just asked for, and because
    // `_dismiss` moves the mirror synchronously the request queued here would
    // read as superseded and issue nothing — the panel would simply never
    // appear. The latch belongs to the intent it was raised under, so it is
    // dropped wherever a new intent is *expressed*, not only where the mirror
    // happens to move.
    //
    // `_believedMinimize` is dropped here for the same reason and one of its
    // own: from this point on a `restore` may be *this request's* echo, because
    // `windowManager.show()` deiconifies a minimised window as part of its own
    // implementation. A latch left standing would hand that echo the
    // unconditional arm, and with a `hide()` queued behind this show that is the
    // stranded dismissal the guard exists to prevent.
    _deferredBlur = false;
    _believedMinimize = false;
    _setMirror(PanelVisibilityState.shown);
    return _enqueue(true, ++_intentGeneration);
  }

  @override
  Future<void> hide() => _hide(PanelVisibilityState.dismissed);

  /// The whole of [hide], with the departure [changes] will report as a
  /// parameter.
  ///
  /// Split out because the two routes to a real unmap mean different things to a
  /// session and the identical thing to the window. A requested hide — the
  /// hotkey toggle at a visible panel, the `close` arm — is the user saying they
  /// are done, so it is [PanelVisibilityState.dismissed]; the focus-loss hide
  /// CAP-14 performs on the user's behalf is [PanelVisibilityState.focusLost],
  /// and a session survives it. Nothing else differs, so this is a parameter
  /// rather than a second copy of the body.
  ///
  /// A parameter and not a boolean flag (AGENTS.md §2): it selects the label on
  /// an emission, not a behaviour, and the enum is the label's own type. What
  /// the type cannot say is that the label must be a *departure*, which is what
  /// the assert says instead.
  Future<void> _hide(PanelVisibilityState departure) {
    // The one place this is asserted. [PanelVisibilityState] is a single enum
    // on a single stream by decision, so no type can say "a departure" — and
    // every departure that arrives here arrives in a *variable*: `hide()`'s
    // literal and both of [_dismiss]'s. The window-driven routes pass literals
    // straight to [_setMirror] and are not covered; see its doc for why that is
    // the boundary rather than an omission.
    assert(
      !departure.isVisible,
      'a hide reports where the panel went, and shown is not a departure',
    );
    if (_disposed) {
      return Future<void>.value();
    }
    // Same reason as [show], and for the same shape of gap: a `hide()` against
    // a panel the mirror already reads as hidden writes nothing either. The
    // minimize latch goes with it — a hide is an intent about this window too,
    // and a `restore` after it is no longer undoing anything this adapter is
    // still waiting to see undone.
    _deferredBlur = false;
    _believedMinimize = false;
    _setMirror(departure);
    return _enqueue(false, ++_intentGeneration);
  }

  /// Deregisters from the window, closes [changes], and disposes both seams
  /// this type owns. Idempotent, and never throws: it runs on the shutdown
  /// path.
  ///
  /// The witness is disposed here because this type owns it, exactly as it owns
  /// the window — one disposer, so `DaemonLifecycle` closing this adapter
  /// releases the X connection the witness opened without needing a second
  /// teardown step that could run in the wrong order.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _guard('cancelling the panel window event subscription', () async {
      await _events.cancel();
    });
    await _guard('closing the panel visibility change stream', _changes.close);
    await _guard('disposing the panel window', _window.dispose);
    await _guard('disposing the keyboard focus witness', _witness.dispose);
  }

  /// Queues [intended] behind every request already issued, and returns the
  /// caller's own future — a rejection reaches the caller, and the chain
  /// survives it.
  Future<void> _enqueue(bool intended, int generation) {
    final result = _queue.then((_) => _apply(intended, generation));
    _queue = result.catchError((Object _) {});
    return result;
  }

  /// Issues one request's platform calls.
  ///
  /// **Invariant:** every await of the window in here goes through [_answered].
  /// The bound is a property of the *chain*, not of a call — this method is one
  /// link in `_queue`, so a single bare `await _window.…()` re-parks every
  /// request behind it forever and mechanism four is silently gone, with no
  /// analyzer complaint and nothing but a hung panel to say so.
  Future<void> _apply(bool intended, int generation) async {
    if (_disposed) {
      return;
    }
    if (_visible != intended || generation != _intentGeneration) {
      // A later press already superseded this request. Issuing its calls now
      // would move a window the user has since dismissed — and `focus()` maps
      // a hidden toplevel, so even the trailing half of a show is enough.
      return;
    }
    _outstanding += 1;
    try {
      if (!intended) {
        // Branched on rather than discarded even though nothing follows a
        // hide. The invariant above is enforced by nothing except this method
        // reading as though every call's answer matters, and the arm that
        // throws its answer away is the arm a later call gets appended to
        // without anyone noticing it was never checked.
        if (!await _answered('hide', _window.hide, generation)) {
          return;
        }
        return;
      }
      if (!await _answered('show', _window.show, generation)) {
        // The window never answered the map, so the request is over: issuing
        // `focus()` now would be a second call against an unresponsive window,
        // and `focus()` is `gtk_window_present` — it would map a toplevel whose
        // own `show` was abandoned.
        return;
      }
      if (_disposed ||
          _visible != intended ||
          generation != _intentGeneration ||
          _deferredBlur) {
        // The two halves of a show are two round trips, and a press can land
        // between them. `focus()` is `gtk_window_present`, which maps *and*
        // raises — so focusing now would steal the keyboard for a panel the
        // user has already dismissed, and re-map it if the queued hide had
        // somehow got in first. The same re-check covers a `dispose()` that
        // landed mid-flight: a torn-down adapter must not present the window.
        return;
      }
      // Branched on for the same reason the hide arm is, and more so: this is
      // the last call in the method, so it is the one a fifth round trip would
      // be appended after.
      if (!await _answered('focus', _window.focus, generation)) {
        return;
      }
    } finally {
      _outstanding -= 1;
      if (_outstanding == 0 && _nativeInFlight == 0) {
        // A timeout ends this queue link, but native ownership remains until
        // _nativeSettled observes the underlying operation finish.
        _releaseDeferredBlur();
      }
    }
  }

  /// Issues one window call under [_requestTimeout], and says whether the
  /// window answered.
  ///
  /// A refusal is not this method's business: the rejection propagates, reaches
  /// the caller through [_enqueue], and is reported wherever that caller
  /// reports it. What this bounds is the call that never settles at all, which
  /// no `catch` can reach.
  ///
  /// Reported through `onTimeout` and a local flag rather than by catching a
  /// [TimeoutException]: a seam is free to have deadlines of its own, and one
  /// of those expiring is the window *refusing* the call, not this policy
  /// firing.
  Future<bool> _answered(
    String call,
    Future<void> Function() issue,
    int generation,
  ) async {
    // This is the actual call boundary. Nothing may await between the check
    // and issue(): focus() can present a window that a newer intent hid.
    if (call == 'focus' &&
        (_disposed ||
            !_visible ||
            generation != _intentGeneration ||
            _deferredBlur)) {
      return false;
    }
    _nativeInFlight += 1;
    var abandoned = false;
    final operation = Future<void>.sync(issue);
    unawaited(
      operation.then(
        (_) => _nativeSettled(
          call,
          generation,
          abandoned: abandoned,
          succeeded: true,
        ),
        onError: (Object _, StackTrace _) => _nativeSettled(
          call,
          generation,
          abandoned: abandoned,
          succeeded: false,
        ),
      ),
    );
    var answered = true;
    await operation.timeout(
      _requestTimeout,
      onTimeout: () {
        answered = false;
        abandoned = true;
      },
    );
    if (!answered) {
      _log(
        () => _logger.error(
          'the window did not answer $call within '
          '${_requestTimeout.inMilliseconds} ms; the request was abandoned so '
          'the next press is still served',
          context: {'call': call, 'timeout_ms': _requestTimeout.inMilliseconds},
        ),
      );
    }
    return answered;
  }

  void _nativeSettled(
    String call,
    int generation, {
    required bool abandoned,
    required bool succeeded,
  }) {
    _nativeInFlight -= 1;
    if (_disposed) {
      return;
    }
    // A timed-out call can still change the real window after the replacement
    // has completed. Queue a repair in the direction of the latest intent.
    final stalePresent = (call == 'show' || call == 'focus') && !_visible;
    final staleHide = call == 'hide' && _visible;
    if (succeeded &&
        abandoned &&
        generation != _intentGeneration &&
        _outstanding == 0 &&
        _settledIntentGeneration == _intentGeneration &&
        (stalePresent || staleHide)) {
      unawaited(
        _enqueue(_visible, _intentGeneration).catchError(
          (Object error) => _log(
            () => _logger.error(
              'the window rejected a repair after a late $call',
              context: _errorContext(error),
            ),
          ),
        ),
      );
    }
    if (succeeded && generation == _intentGeneration) {
      _settledIntentGeneration = generation;
    }
    if (_outstanding == 0 && _nativeInFlight == 0) {
      _releaseDeferredBlur();
    }
  }

  void _onWindowEvent(String event) {
    if (_disposed) {
      return;
    }
    switch (event) {
      case 'show':
        // An echo of our own map, or the window manager mapping the panel on
        // its own — `_reconcile` is what tells those apart. Like `restore`
        // below, this arm does not re-arm `_focused`: a mirror moving to true
        // is not the window saying it holds the keyboard, and only a `focus`
        // says that. `gtk_widget_show` does not even raise the window, let
        // alone focus it, so an external `show` is the *less* likely of the two
        // to be followed by a real focus-in — and where none arrives, CAP-14
        // cannot answer a click-away at that panel until the user clicks into
        // it, and a focus-in re-arms it there and then. Same owed runtime claim
        // as the `restore` arm's, and the same accepted trade — stated in full
        // at `_setMirror`'s `_focused` clear.
        _reconcile(PanelVisibilityState.shown);
      case 'restore':
        // `gtk_window_deiconify` + `gtk_window_present`: the window is back.
        //
        // Two arms, because a `restore` means two different things depending on
        // whether this adapter is still holding a `minimize` it believed.
        //
        // *Undoing a believed minimize.* Then it is the other half of a pair,
        // and the pair has to cancel out during one of our requests exactly as
        // it does outside one — see [_believedMinimize]. The guard is skipped,
        // and skipping it is safe for the reason the split rests on: nothing
        // this adapter calls iconifies, so the latch can only have been armed by
        // a genuinely external minimize, and nothing of ours is waiting for this
        // event. One-shot, so a second `restore` finds the latch spent and takes
        // the guard like any other.
        //
        // *Every other restore.* Guarded, unchanged, and that is the
        // load-bearing half: `windowManager.show()` restores a minimised window
        // as part of its own implementation, so this really can be our own
        // echo — and believing it while a `hide()` is queued behind that show
        // strands the hide and leaves the panel on screen.
        //
        // The keyboard is deliberately *not* restored on either arm.
        // `_setMirror` cleared `_focused` on the way down (see there), and this
        // arm does not put it back, because a mirror moving to true is not the
        // window saying it holds the keyboard — only a `focus` says that. On
        // Linux `gtk_window_present` normally does take it, so a real focus-in
        // follows and re-arms the flag a turn later; where it does not, the
        // restored panel cannot answer a focus-out until the user clicks into
        // it. That is the trade `_setMirror`'s clear accepts, stated in full
        // there, and it is a claim only a session can settle — `## Not covered
        // here` in `test/platform/runtime-observation-checklist.md` carries it.
        if (_believedMinimize) {
          _believedMinimize = false;
          _setMirror(PanelVisibilityState.shown);
        } else {
          _reconcile(PanelVisibilityState.shown);
        }
      case 'hide':
        // The Linux plugin emits this only from its own gtk_widget_hide call.
        // The request that issued that call already reported its departure in
        // [_hide], with the reason that request owned. The event carries no
        // request identity, and can arrive after its Future settles or after a
        // newer show finishes. Reading the current mirror to infer its reason
        // would turn a late focus-loss echo into a new dismissal (PANEL-19).
        // A native unmap by another client does not emit this GTK widget signal.
        // Repair of an abandoned native hide belongs to [_nativeSettled], where
        // the call's generation is still available.
        break;
      case 'close':
        // DW-12: a close is a dismissal, not an exit — the same intent CAP-14
        // gives a focus loss, so it gets the same answer.
        //
        // Not `_reconcile(false)`, and that is the whole change.
        //
        // What keeps the toplevel alive is `main.dart`'s
        // `setPreventClose(true)`, and nothing else: `on_window_close` returns
        // `_is_prevent_close`, and returning TRUE is what suppresses GTK's
        // default `delete-event` handler — the one that destroys the widget
        // (`window_manager-0.5.2/linux/window_manager_plugin.cc:967-971`).
        // The emit-before-return ordering in that function guarantees nothing
        // on its own, because `_emit_event` is
        // `fl_method_channel_invoke_method` (`:959-965`) — an asynchronous
        // channel invoke, so this arm runs a main-loop turn later. With the
        // flag false the toplevel would already be destroyed by then.
        //
        // So: the event arrives with the toplevel still mapped *because the
        // flag is set*, and a mirror written to `false` here would be a lie
        // about a window that is still on screen. The arm has to actually put
        // the window away — and it is correct only while `main.dart` sets that
        // flag, which `test/architecture/hidden_window_test.dart`'s presence
        // row and `composition_wiring_test.dart`'s DW-12 row are what hold.
        //
        // No `_outstanding` guard, deliberately: `close` is a GTK
        // `delete-event`, and this adapter's only platform calls are `show`,
        // `hide` and `focus`, so a close can never be an echo of ours. It is
        // structurally external, and `minimize` below now sits on that same
        // side for the same reason (DW-31).
        _dismiss('close', PanelVisibilityState.dismissed);
      case 'minimize':
        // Structurally external, exactly as `close` is: `minimize` comes from a
        // GTK `window-state-event` and nothing this adapter calls iconifies, so
        // it can never be an echo of ours. It goes straight to the mirror
        // rather than through `_reconcile`, because the guard there would
        // discard the one signal an iconify produces at all whenever it landed
        // during a request of ours (DW-31).
        //
        // Nothing else would report it: `gtk_window_iconify` emits no GTK
        // `hide` signal. And an iconified panel is not merely mislabelled —
        // `main.dart` calls `setSkipTaskbar(true)` on this toplevel, so there
        // is no task-bar entry to click it back from and the hotkey is the only
        // way to reach it. With the mirror still reading `true`, that press is
        // spent issuing a `hide` against a window nobody can see, and the user
        // has to press twice to get the panel back.
        //
        // **An unconditional `minimize` on its own is not a partial fix — it is
        // a worse defect.** It was tried and reverted (the escalation of
        // 2026-08-15): with `restore` left wholly behind the guard, a
        // `minimize`/`restore` pair arriving during one of our requests believed
        // the first half and swallowed the second, leaving the mirror reading
        // `false` over a window that is mapped — *permanently*, because
        // the departure path also clears `_focused` and the `focus` arm's own
        // `_visible` guard can never re-arm it over a false mirror, so CAP-14's
        // dismissal was dead for that panel's life. With `setSkipTaskbar(true)`
        // the hotkey is the only route back, and against a false mirror that
        // press resolves to `show()` rather than `hide()`: the panel is already
        // on screen, so the press changes nothing the user can see and leaves
        // them with a window nothing can put away. Hence the latch armed below
        // and consumed by the `restore` arm above — the two halves of that
        // change are one design, not one plus a follow-up.
        //
        // The cost of leaving `_reconcile` is now one thing rather than two. The
        // `changes` transition a minimize landing during one of our requests
        // emits — the one the guard used to swallow — is attributed `iconified`,
        // so the `shown` after it begins no session and the panel comes back
        // with whatever was typed into it. That was DW-30, and it is answered in
        // `CorrectionController` rather than by suppressing an emission here,
        // which would have redefined AD-18 instead. What remains is the other
        // half: a mirror written
        // here can supersede a request that is *queued but not yet started*:
        // `_apply` returns early when `_visible` no longer matches the intent
        // it was enqueued with, so a second press already waiting behind an
        // in-flight one evaporates without reaching the window. That is the
        // same shape the guarded `restore` exists to prevent, and it is allowed
        // here because the two events mean opposite things — a `restore` claims
        // the panel is back, while a `minimize` says the user cannot see it, and
        // a queued summon that dies against a genuinely iconified window costs
        // one press rather than stranding a dismissal.
        //
        // Taken deliberately: the alternative is a mirror that lies about a
        // window the user cannot see or reach. And the departure named here is
        // what makes it affordable — a window manager that iconifies on a
        // workspace switch or a show-desktop gesture hands back the same window
        // with the same text in it, and `iconified` is how the ring above is
        // told to keep it.
        //
        // **A minimize is believed only when it actually took the panel down,
        // and that now decides the attribution as well as the latch.** Over a
        // false mirror the panel is already away for a reason somebody
        // *expressed* — our own `hide()`, a close, CAP-14's focus-loss hide —
        // and
        // `_reportDeparture` would otherwise replace that reason with this one.
        // Replacing a `dismissed` with an `iconified` is the mirror image of
        // DW-30: the summon after the user's own dismissal would hand back the
        // session they asked to be rid of, off an incidental
        // `GDK_WINDOW_STATE_ICONIFIED` flag raised while the window was
        // unmapping. So the reason a panel is away only ever moves *toward* a
        // dismissal and never away from one.
        //
        // This is not the only arm that needs that choice made for it, and
        // earlier prose here claimed it was ("every other route to a
        // re-attribution is a real dismissal"). The `hide` arm is the
        // counterexample and is now gated the same way: it is the echo of one of
        // our own calls, so it can arrive long after the departure that actually
        // put the panel away. What is left unguarded is `_hide` itself, and
        // there the departure really is the caller's own live intent.
        if (_visible) {
          // Armed only by a minimize that actually took the panel down, because
          // that is what "believed" means here and what the `restore` arm is
          // entitled to undo. It is also what keeps the load-bearing case
          // intact: a `show()` parked with a `hide()` queued behind it has the
          // mirror already reading false, so a `minimize` landing in that window
          // arms nothing for the show's own deiconify echo to consume.
          _believedMinimize = true;
          _setMirror(PanelVisibilityState.iconified);
        }
      case 'focus':
        // Believed whoever caused it, *while the mirror says a panel is up*.
        // Our own `focus()` and the user clicking the panel both mean the
        // window really does hold the keyboard, so an echo needs no guard here
        // — the fact it reports is true either way, and it is the fact
        // `_onBlur` cannot decide a dismissal without (DW-33).
        //
        // The `_visible` guard is about *when* it arrives, not who caused it.
        // Our own `focus()`'s event lands *after* that call's channel reply —
        // and therefore after anything the request's completion set in motion,
        // including a deferred blur releasing into a `hide`. Recorded unguarded,
        // that trailing event would write `true` over a mirror already reading
        // false, and the next departure could not be relied on to clear it:
        // `_reportDeparture` returns before the clear whenever the departure
        // merely repeats the one already standing, which the hide that put the
        // mirror there is. The next summon would then open with a stale
        // keyboard and the first spurious focus-out would dismiss the panel the
        // user just asked for, which is DW-33 reinstated by its own fix.
        //
        // **What that ordering rests on is not what earlier prose here cited.**
        // It cited `_emit_event` being an asynchronous
        // `fl_method_channel_invoke_method`
        // (`window_manager-0.5.2/linux/window_manager_plugin.cc:959-965`).
        // That argues nothing here, and read literally it argues the opposite:
        // `on_window_focus` (`:973-977`) is the `focus-in-event` handler and
        // calls `_emit_event` straight away, on the *same* channel the method
        // reply goes back over — so an event emitted before
        // `fl_method_call_respond` reaches Dart before the reply, not after it.
        // The asynchrony of the invoke is about the C side not blocking, not
        // about ordering against a reply.
        //
        // What actually holds the ordering is that the focus *grant* is
        // asynchronous: `gtk_window_present` asks the compositor to activate
        // the toplevel, and `focus-in-event` arrives on a later main-loop turn,
        // after the method call has already responded. That is a compositor
        // claim, not one this file's source citations can settle, and it is a
        // claim in the register `## Not covered here` in
        // `test/platform/runtime-observation-checklist.md` carries. Where a
        // compositor delivers the focus-in inside the round trip instead, the
        // consequence is the one `_releaseDeferredBlur` states in full.
        //
        // The guard cannot tell "too late" from "too early", and the second is
        // the price of it: while the mirror wrongly reads false over a window
        // that really is mapped — the state `_onBlur`'s doc names as reachable,
        // and the one a `minimize` landing inside `_apply` produces — a genuine
        // focus-in is discarded here, and nothing re-arms the flag when a later
        // `restore` or `show` echo corrects the mirror. CAP-14 then misses that
        // panel's click-aways until a focus-in re-arms the flag. Same trade as
        // `_setMirror`'s clear, stated in full there.
        //
        // The witness is recorded here and nowhere else, under the same guard
        // and for the same reason: what [_keyboardStillHere] compares against
        // has to be the focus as it stood when *this window* said it held the
        // keyboard. A recording taken at a moment the adapter does not count as
        // holding it would answer a later blur against a focus owner that was
        // never ours.
        if (_visible) {
          _focused = true;
          _userFocusedSinceBlur = true;
          _recordFocusWitness();
        }
      case 'self-focus':
        if (_visible) {
          _focused = true;
          _recordFocusWitness();
        }
      case 'blur':
        _onBlur();
    }
  }

  /// Believes a window event, but only when it can be telling us something we
  /// did not already know.
  ///
  /// Reached from `show` and a `restore` with no believed `minimize` standing
  /// behind it. A `hide` event is an owned echo whose request already reported
  /// its departure. `minimize` and `close` bypass this guard because nothing this
  /// adapter calls can produce either (DW-31, DW-12), so for those two there is
  /// no echo to swallow and the guard could only discard the event outright.
  ///
  /// An arm count is the wrong way to state the scope of this method, and a
  /// stale one was here: every arm's reach into the mirror is conditional now.
  /// A `blur` moves it only when the window held the keyboard, the panel is up
  /// and nothing of ours is outstanding; a `restore` moves it through here or
  /// past here depending on the latch. What is invariant is the *route*. An arm
  /// writes the mirror for one of exactly two reasons: it reports a state the
  /// window has already reached (`show`, `restore`, `minimize`), or it
  /// answers an intent with a real `hide` through [_dismiss] (`close`, and a
  /// `blur` that gets past [_onBlur]'s three questions). This method is the
  /// guard on the first route, minus the arms that cannot be echoes of ours. It
  /// is not a judgement about which arms deserve tidying.
  ///
  /// `focus` is echo-capable as well and is still not reached from here, for a
  /// third reason again: it is not a claim about the mirror at all. See the
  /// class doc's taxonomy, which is by *what our own calls can cause* and so
  /// puts `focus` on this side of the line while this method does not.
  ///
  /// `restore` being on this side is the load-bearing half of the split:
  /// `windowManager.show()` restores a minimised window as part of its own
  /// implementation, so a `restore` echo can arrive *during* one of our
  /// requests. Believing it while a hide is queued behind that show would flip
  /// the mirror back to true and make the queued hide look superseded — the
  /// panel would stay on screen, which is the exact defect this adapter exists
  /// to close.
  ///
  /// The one `restore` that is **not** reached from here is the one undoing a
  /// `minimize` this adapter believed ([_believedMinimize]). That exception
  /// exists because the guard cannot be applied to half of a self-cancelling
  /// pair, and it does not weaken the paragraph above: [show] and [hide] clear
  /// the latch where those intents are expressed, so an echo produced by one of
  /// our own requests always finds it clear and is swallowed here as before.
  void _reconcile(PanelVisibilityState state) {
    if (_outstanding > 0 || _nativeInFlight > 0) {
      return;
    }
    _setMirror(state);
  }

  /// CAP-14's focus-loss hide, performed by the adapter because the
  /// alternative — the application ring deciding it — needs a focus signal on
  /// [PanelVisibility], and the port is AD-8 verbatim.
  ///
  /// Four questions, in this order.
  ///
  /// *Is the panel up?* A hidden panel has no focus to lose.
  ///
  /// *Did the window ever hold the keyboard?* A focus-out at a window that
  /// never took it is not a dismissal — it is a window manager with
  /// focus-stealing prevention declining to hand the keyboard over when the
  /// panel was mapped, and hiding on it takes the panel down at the very moment
  /// the user summoned it (DW-33).
  ///
  /// *Did the keyboard actually go anywhere?* A `blur` is not only the user
  /// turning away: a passive key grab activating produces
  /// `FocusOut(mode=NotifyGrab)`, and the plugin discards the mode, so the
  /// daemon's own shortcut arrived here as a dismissal (G-01-13). The witness
  /// reads the display server's current focus owner and compares it with the
  /// one recorded when the `focus` arm last ran; a match means no focus
  /// transfer happened and there is no dismissal to perform.
  ///
  /// **[_focused] stays `true` on that suppressed path, and that is not
  /// incidental.** The clear moved below the third question for it. Presses 1
  /// and 3 of UAT test 13 ended on `FocusIn(NotifyUngrab)` and 2 and 4 on
  /// `FocusIn(NotifyNormal)`, so the pre-fix arm depended on a focus-in coming
  /// back to re-arm the flag — and if GDK ever stopped delivering the
  /// `NotifyUngrab` form, [_focused] would be left false and the next *genuine*
  /// blur would be discarded by DW-33's question, resurrecting the withdrawn
  /// G-01-14 symptom for real. Keeping the flag where the keyboard demonstrably
  /// never left removes that dependency outright: the adapter no longer needs a
  /// focus-in it cannot guarantee. On every *other* path the flag is still
  /// cleared as it was — whatever else is true there, the window does not hold
  /// the keyboard now.
  ///
  /// *Is a request of ours outstanding?* Then the blur is **latched**, not
  /// acted on and not dropped. It cannot simply be believed, because the
  /// mapping half of our own `show` produces one. It must not be discarded
  /// either: a `show()` against an **already-visible** panel — AD-14's second
  /// launch, AD-12's tray entry — is a full round trip during which the user
  /// really can click away, and nothing would ever re-ask (DW-32).
  /// [_releaseDeferredBlur] reconsiders it when the chain lets go.
  ///
  /// The first two questions are not independent, and the order above is the
  /// readable one rather than the minimal one: [_focused] is written `true`
  /// only under a `_visible` mirror and cleared on every transition away from
  /// one, so `_focused` implies `_visible` and `!_visible` can never be the
  /// sole reason this returns. It is kept because the alternative is a
  /// dismissal that depends on an invariant held elsewhere, and because the
  /// two questions are about different things — one about the panel, one about
  /// the keyboard. A reader should not have to derive the first from the
  /// second. The suite's negative-control record says which of them each row
  /// actually fails for.
  ///
  /// A timeout releases the caller, but a pending native call still counts as
  /// outstanding here. Its blur remains latched until native settlement, so
  /// focus loss cannot start a hide that races that call.
  void _onBlur() {
    if (!_visible) {
      _focused = false;
      _userFocusedSinceBlur = false;
      return;
    }
    if (!_focused) {
      // DW-33, unchanged: it never held the keyboard, so there is nothing to
      // clear and no reason to spend an X round trip on a path that returns
      // anyway.
      return;
    }
    if (_keyboardStillHere()) {
      // The focus did not move. `_focused` stays true — see the doc above.
      return;
    }
    _focused = false;
    _userFocusedSinceBlur = false;
    if (_outstanding > 0 || _nativeInFlight > 0) {
      _deferredBlur = true;
      return;
    }
    _dismiss('focus-loss', PanelVisibilityState.focusLost);
  }

  /// The witness's recording, with the AD-15 backstop around it — the write
  /// half of [_keyboardStillHere]'s.
  ///
  /// The seam promises a recording; only its `dispose()` promises never to
  /// throw, and the X11 implementation reaches `DynamicLibrary.open`, `calloc`
  /// and an FFI call behind this call. A throw here would leave the
  /// `_window.events` **listener callback**, and a listener throw is not a
  /// stream error — the subscription's `onError` never sees it — so what is
  /// left is the root zone, `PlatformDispatcher.onError` in `main.dart`. That
  /// is the escape route this guard closes, and it is the fact a reader cannot
  /// recover from the code.
  ///
  /// Nothing is returned and the caller's behaviour is identical either way:
  /// a recording that failed leaves nothing witnessed, so [_keyboardStillHere]
  /// answers `false` and the next focus-out is a real focus loss — the
  /// pre-seam behaviour, and the fail-safe direction `focusUnmoved`'s contract
  /// states. The line carries `error_type` and nothing else, per the [Logger]
  /// port — this adapter sits on the panel the user types into.
  void _recordFocusWitness() {
    try {
      _witness.recordFocusGained();
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'the keyboard focus witness could not record the focus; a later '
          'focus-out is treated as a real focus loss',
          context: _errorContext(error),
        ),
      );
    }
  }

  /// The witness's answer, with the AD-15 backstop around it.
  ///
  /// A seam that throws where it promised a value must not take the daemon with
  /// it, and it must not suppress a dismissal either: a throw is an uncertainty,
  /// and every uncertainty answers `false` so the adapter behaves exactly as it
  /// did before the seam existed. The line carries `error_type` and nothing
  /// else, per the [Logger] port — this adapter sits on the panel the user types
  /// into.
  bool _keyboardStillHere() {
    try {
      return _witness.focusUnmoved;
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'the keyboard focus witness failed; the focus-out is treated as a '
          'real focus loss',
          context: _errorContext(error),
        ),
      );
      return false;
    }
  }

  /// Reconsiders a blur that [_onBlur] latched, now that the request chain has
  /// let go of the window.
  ///
  /// State is re-read here rather than trusted from when the blur arrived,
  /// because the request that suppressed it has been running in between: the
  /// adapter may have been torn down, and the user may have clicked back onto
  /// the panel.
  ///
  /// Which of the three re-reads carries which case needs saying, because two
  /// of them are backstops and only one decides anything on its own.
  ///
  /// `!_visible` is the backstop. It reads as the guard for "the panel was
  /// already dismissed by a press while this request was in flight", and that
  /// case is real — but it is answered before the release ever runs, by the
  /// latch drops in [show], [_hide] and [_setMirror]: a press that put the panel
  /// away dropped the latch on its way through, so this method returns at
  /// `!_deferredBlur` above and never reaches here. With the latch set,
  /// `_visible` is true by construction. The re-read stays because the
  /// alternative is a dismissal whose correctness rests on an invariant three
  /// other methods have to keep. Deleting it alone fails nothing; deleting it
  /// together with [_setMirror]'s latch drop does fail a row, because those two
  /// are redundant only with respect to each other. The suite's
  /// negative-control record measures that pair as a control of its own.
  ///
  /// `_disposed` is the same shape: [_hide] returns without touching the window
  /// once the adapter is closed, so the [_dismiss] below is already inert by
  /// the time it would matter. It is stated here so a later `_dismiss` that
  /// reached the seam directly would not silently move a real window on the
  /// teardown path.
  ///
  /// Only a user focus-in after the blur cancels dismissal. A focus-in caused
  /// by our own show or present updates keyboard truth for later blurs, but
  /// cannot satisfy this re-check. The native adapter labels that event as
  /// `self-focus`; the keyboard witness still checks current ownership when
  /// the event ordering is uncertain.
  ///
  /// The question is asked here as well as in [_onBlur] because this method
  /// reaches [_dismiss] past [_onBlur]'s questions, not through them. Without
  /// it the suppression would be half wired: a grab firing during one of our
  /// round trips — AD-14's second launch and AD-12's tray entry are both full
  /// round trips against a mapped, focused window — would latch a blur that
  /// moved no keyboard and dismiss the panel when the chain let go.
  ///
  /// The latch is dropped whether or not the dismissal happens: one round trip
  /// answers it once, and a blur that no longer applies is not owed to any
  /// later request. [show], [_hide] and [_setMirror] drop it too — see
  /// [_deferredBlur] for the rule the four of them share.
  void _releaseDeferredBlur() {
    if (!_deferredBlur) {
      return;
    }
    _deferredBlur = false;
    if (_disposed || !_visible || _userFocusedSinceBlur) {
      return;
    }
    if (_keyboardStillHere()) {
      return;
    }
    _dismiss('focus-loss', PanelVisibilityState.focusLost);
  }

  /// Puts the panel away on the window's own initiative, and reduces a refusal
  /// to a log line.
  ///
  /// Three call sites, two causes. Both causes mean "the user is done with this
  /// window" — a focus loss (CAP-14) and a close (DW-12) — and the focus loss
  /// reaches here by two routes: [_onBlur] when nothing of ours is outstanding,
  /// and [_releaseDeferredBlur] when a blur latched during a request is
  /// reconsidered afterwards (DW-32). The deferred route is the same cause and
  /// carries the same [cause] string deliberately: to whoever reads the log, a
  /// dismissal delayed by one round trip is still a focus loss, and splitting
  /// it would put a third vocabulary in front of them for no difference they
  /// can act on.
  ///
  /// All three want the identical thing: a real `hide`, issued without awaiting
  /// it, whose rejection must not
  /// escape into the zone as an uncaught error in a daemon whose job is to stay
  /// up. The mirror has already led inside [_hide], so a refusal costs the line
  /// and nothing else.
  ///
  /// [cause] is a parameter rather than a flattened single message because the
  /// two are different events to whoever reads the line: a window manager that
  /// refuses the focus-loss hide is a compositor quirk, and one that refuses the
  /// close hide leaves a toplevel on screen that the user explicitly dismissed.
  ///
  /// [departure] travels beside it and is **not** the same fact. [cause] is the
  /// operator's vocabulary — which of two log lines to read — while [departure]
  /// is the session's, and the two do not partition the call sites the same way:
  /// both focus-loss routes carry one cause and one departure, while the `close`
  /// arm's cause is its own and its departure is the one an ordinary [hide]
  /// carries. Collapsing them into one parameter would tie the log wording to
  /// AD-18's rule.
  void _dismiss(String cause, PanelVisibilityState departure) {
    unawaited(
      _hide(departure).catchError(
        (Object error) => _log(
          () => _logger.error(
            'the window rejected the $cause hide',
            context: _errorContext(error),
          ),
        ),
      ),
    );
  }

  /// Moves the mirror to [state] and reports it, or does neither.
  ///
  /// The single write point, and it takes a [PanelVisibilityState] rather than a
  /// bool so that every route to a false mirror names its departure where the
  /// move is made. Nothing about the departure is inferred here: this method
  /// cannot tell an iconify from a dismissal, and every call site can.
  ///
  /// What the type does not do is make that naming safe, and earlier prose here
  /// claimed it did — "the compiler forces every route to be named". The
  /// compiler forces a *value*, not a valid one, and the mirror direction is
  /// then read off that value with [PanelVisibilityState.isVisible]: a caller
  /// that passes `shown` where it meant a departure raises the mirror instead of
  /// failing to compile. [_hide]'s assert is what says so, and it is the only
  /// one — but it does **not** see every departure, and earlier prose here
  /// claimed it did. It covers the routes that carry a departure in a
  /// *variable*, which is every caller-side request: [hide]'s literal and both
  /// of [_dismiss]'s. The two window-driven routes never cross it — the
  /// `minimize` arm calls this method directly with
  /// [PanelVisibilityState.iconified]. The GTK `hide` event does not create a
  /// departure; [_hide] already reported the reason owned by its request. A
  /// third window-driven site that computed its departure would want its own
  /// boundary check.
  /// [PanelVisibilityState.iconified]'s own doc names the geometry bundle as the
  /// change most likely to add one.
  void _setMirror(PanelVisibilityState state) {
    if (_disposed) {
      return;
    }
    if (!state.isVisible) {
      _reportDeparture(state);
      return;
    }
    if (_visible) {
      // There is exactly one way to be up, so a `shown` over a true mirror
      // knows nothing the mirror does not: a `show()` at a visible panel, or
      // our own map's echo. Unlike a departure it can never be a
      // re-attribution, which is why this half kept the plain
      // did-the-mirror-move guard.
      return;
    }
    _visible = true;
    // Dropped on the way up as well as the way down, for the reason
    // [_reportDeparture] states in full: a blur belongs to the intent it was
    // raised under, and a transition is a newer intent.
    _deferredBlur = false;
    _changes.add(state);
  }

  /// Reports that the panel is away, and which of the three ways it went.
  ///
  /// **The guard here is "have I already reported this?", not "did the mirror
  /// move?"** The mirror is what that question used to be asked through, and the
  /// stand-in stopped fitting the moment the stream grew a third and fourth
  /// value: a window that is already away can still have the *reason* it is away
  /// replaced — the user iconifies the panel and then closes it — and under the
  /// three-way session rule the last reason is the one the next summon obeys. So
  /// a re-attribution is a real change of state and is emitted.
  ///
  /// Three boundaries keep that from making the stream chatty, and they are the
  /// whole of it. A departure that merely repeats the standing one reports
  /// nothing. The `shown` side is untouched, so a `show()` at a visible panel
  /// still emits nothing at all. And no departure is invented where none was
  /// expressed: a `minimize` is accepted only while the mirror is visible, and
  /// a GTK `hide` echo never reports a departure. The echo has no request id or
  /// reason; only the originating [_hide] call has that information.
  void _reportDeparture(PanelVisibilityState departure) {
    if (!_visible && departure == _lastDeparture) {
      return;
    }
    _visible = false;
    _lastDeparture = departure;
    // A transition is an intent, and a blur raised before it belonged to the
    // panel that intent replaced. `_releaseDeferredBlur` re-reads `_visible`,
    // and `_visible` alone cannot tell "still the panel the blur belonged to"
    // from "a different panel that happens to be up" — both read true.
    //
    // This is the **backstop** half of that rule, not the whole of it. It
    // covers the transitions the *window* causes, which is all it can cover:
    // the caller-side requests that move no mirror are dropped in [show] and
    // [_hide] instead, where the intent is expressed rather than where the
    // mirror moves, and the `show()` at a visible panel is precisely the
    // request DW-32 is about.
    //
    // Only one of those two requests is actually kept out of this method,
    // though, and the distinction matters because the `close` arm depends on
    // it. A `show()` at a visible panel never enters here at all. A `hide()` at
    // a *hidden* one does enter, and returns at the repeat guard above only
    // when the standing departure is already `dismissed`; over a `focusLost` or
    // an `iconified` it passes the guard and re-attributes the absence, which
    // is the whole point of the guard being "have I already reported this?".
    //
    // With those two in place, deleting this line *alone* fails nothing —
    // every window-driven route to a false mirror also leaves `_visible` false
    // at the release point, where [_releaseDeferredBlur] answers it. The two
    // are redundant only with respect to each other, though, and deleting both
    // does fail a row: a `minimize` inside a latched round trip is the one
    // transition to a false mirror that neither [show] nor [_hide] is involved
    // in. The suite's negative-control record measures the pair as a control of
    // its own for exactly that reason, so neither line is read as dead and
    // neither is mistaken for the mechanism carrying the case by itself.
    _deferredBlur = false;
    // An unmapped window holds no keyboard. Without this, a hidden-then-shown
    // panel would carry a stale "we hold the keyboard" from its previous life
    // and the first spurious blur after a summon would dismiss it — exactly
    // what DW-33 exists to stop. `_onBlur` clears the flag on its own path,
    // so what this line is actually for is every *other* route the mirror
    // takes to false: a `close`, a `minimize`, a late `hide` echo of our own, a
    // hide the window refused.
    //
    // **The accepted trade, stated once — the other three sites point here.**
    // Clearing the flag costs a dismissal in the mirror-image case: where the
    // mirror goes false while the window really is mapped and focused, or
    // where the window brings the panel back with no focus-in behind it,
    // `_onBlur` has nothing to act on. The cost is *not* "one press", which
    // earlier prose here claimed, and it is not permanent either: that panel
    // cannot dismiss itself on a click-away until a focus-in re-arms the
    // flag.
    //
    // **What re-arms it is narrower than "a focus-in", and earlier prose here
    // said "a focus-in" flatly.** The `focus` arm only records one *while the
    // mirror reads true*, so a focus-in that arrives inside the false-mirror
    // window is discarded and re-arms nothing. Two measured consequences, both
    // reproduced against this file rather than argued:
    //
    // - An external `minimize`/`restore` pair where the compositor hands the
    //   keyboard back *before* the `window-state-event` carrying `restore` —
    //   GTK delivers `focus-in-event` and `window-state-event` from
    //   independent compositor events with no ordering guarantee, so this is
    //   a coin flip rather than an exotic interleaving. `show, focus,
    //   minimize, focus, restore, blur` issues no `hide` at all; the same
    //   sequence with the focus-in *after* the `restore` issues one. The
    //   ordering of that focus-in is the whole of the difference.
    // - A hide the window refused, which leaves the mirror false over a
    //   window that is mapped *and still focused*. `gtk_widget_show` at an
    //   already-mapped window and `gtk_window_present` at an already-focused
    //   one raise no focus *transition*, so the press that repairs the mirror
    //   brings no focus-in with it and the next click-away is swallowed.
    //
    // So the bound is the next focus **transition** — the user clicking away
    // (unanswered) and back — not the next focus-in, and certainly not one
    // press. Still bounded, and still not the panel's life.
    //
    // **And the hotkey is not an escape hatch in the state this paragraph is
    // about.** Earlier prose here said "every other way of putting the panel
    // away (the hotkey, the tray entry, the close control) keeps working
    // throughout", and it was wrong twice over. Where the mirror reads false
    // over a mapped window a press resolves to [show], not [_hide], so it
    // re-summons instead of dismissing. And the tray entry was never a way of
    // putting the panel away at all: that menu offers "open the panel" and
    // Quit, and `PanelController.showPanel()` never hides. The close control is
    // what still works.
    //
    // **What that re-summon costs depends on the departure that put the mirror
    // there, and only one of the two cases above still pays it (DW-30).** The
    // refused hide recorded `PanelVisibilityState.dismissed` — the user *did*
    // ask for the panel to go away — so the repairing press begins a fresh
    // AD-18 session over text that never left the screen. That residual is this
    // rule applied correctly rather than a leftover of the one before it, and it
    // is no longer "the DW-30 cost". The `minimize`/`restore` case recorded
    // `PanelVisibilityState.iconified`, and a `shown` after one of those begins
    // nothing, so a press against that mirror brings the panel back with its
    // text.
    //
    // "Dead for that panel's life" describes the **reverted** asymmetric
    // split and must not be reused for this design. There the mirror was
    // stuck false over a mapped window, so the `focus` arm's own `_visible`
    // guard discarded every focus-in and nothing could ever re-arm. Here the
    // mirror reads true and a focus-in is believed normally.
    //
    // Taken in this direction deliberately: a panel that dismisses itself
    // costs the user the panel and whatever was typed into it, which is
    // DW-33's defect exactly, and no number of recovered click-aways is worth
    // one of those.
    _focused = false;
    _userFocusedSinceBlur = false;
    _changes.add(departure);
  }

  /// Runs one teardown step, reducing its failure to a log line: a daemon that
  /// cannot exit is the worse failure.
  Future<void> _guard(String what, Future<void> Function() run) async {
    try {
      await run();
    } on Object catch (error) {
      _log(() => _logger.error('$what failed', context: _errorContext(error)));
    }
  }

  /// Emits a log line without letting the logger's own failure escape — see
  /// the canonical note in `correction_controller.dart`.
  void _log(void Function() emit) {
    try {
      emit();
    } on Object {
      // Nowhere left to report this: the reporting channel is what broke.
    }
  }
}

/// The only part of a caught error that is safe to put in a log line — see the
/// [Logger] port's doc, and the canonical note in `correction_controller.dart`.
Map<String, Object?> _errorContext(Object error) {
  return {'error_type': error.runtimeType.toString()};
}
