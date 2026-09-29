import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dbus/dbus.dart';

import '../../domain/hotkey/global_hotkey.dart';
import '../../domain/hotkey/hotkey_bind_outcome.dart';
import '../../domain/hotkey/hotkey_binding.dart';
import '../../domain/hotkey/hotkey_status.dart';
import '../../domain/logger.dart';
import 'portal_app_id_regime.dart';
import 'xdg_shortcut_trigger.dart';

/// The Wayland half of AD-9's two adapters, over a real
/// `org.freedesktop.portal.GlobalShortcuts` session.
///
/// AD-9 requires the *selection* to be real from the composition root onward:
/// exactly one adapter is constructed at startup and there is no runtime
/// switch. What this file adds is the handshake behind it — AD-11's four steps,
/// in AD-11's order, on the session bus.
///
/// **It must never report a successful bind it did not make**, which under this
/// portal takes a specific and easily-missed form. The `shortcuts` list the
/// `BindShortcuts` response carries back is documented as "a subset of the
/// shortcuts which were passed in … (this includes the set of all shortcuts and
/// the empty set)", so a portal that discards the request answers *successfully*
/// with our shortcut missing. That is how GNOME reports a bind it dropped
/// because the application id has no installed `.desktop` entry. So the
/// read-back is checked, and an id asked for and not returned is
/// [HotkeyUnavailable] naming the app id — not a bind.
///
/// **`effective` is always null here, by measurement rather than omission —
/// and the read-back that AD-10 asks for happens anyway.** AD-10 says the
/// settings surface displays the effective binding read back from the portal;
/// what the portal actually returns per shortcut is `description` and
/// `trigger_description`, the latter documented as "user-readable text
/// describing how to trigger the shortcut for the client to render". It is
/// localized, backend-specific, and not a trigger — there is no
/// machine-readable combination anywhere in the reply, in the `BindShortcuts`
/// Response, the `ListShortcuts` reply or the `ShortcutsChanged` signal alike.
/// So `effective` stays null, which is AD-10's own vocabulary for a backend
/// that cannot report it, and **the localized description is carried instead**:
/// out of this adapter on [current], verbatim, to be rendered as the desktop's
/// own wording rather than this app's.
///
/// **It is never parsed back into a combination.** Reconstructing a
/// [HotkeyBinding] from that phrase would be a prediction of vendor and locale
/// behaviour that fails silently on a translated string (AGENTS.md §1). That is
/// not this file's opinion but a ratified decision: DW-66's `decision:` line of
/// 2026-08-14 reads "Render the localized description — the portal's
/// trigger_description is displayed on the settings screen, clearly labelled as
/// the desktop's own wording rather than this app's. Parsing the phrase back
/// was rejected as silently wrong on a translated string." What the surface
/// must never do instead is print the *requested* combination where the
/// effective one goes, which is the defect HOTKEY-03 exists to close.
///
/// **A compositor-side change now reaches the surface**, which it did not before
/// the port grew `bindingChanges`. AD-11's `ShortcutsChanged` subscription used
/// to end in a log line because there was no member to push a changed
/// registration upward; [_onShortcutsChanged] emits on it now — a rebind as
/// [HotkeyBound] (with `effective` still null, for the reason above) and a drop
/// as [HotkeyUnavailable], while a payload this build cannot read emits nothing.
///
/// Everything the portal can refuse is a value (AD-12): an unparsable bus
/// address, an absent session bus, an absent portal, a compositor with no
/// GlobalShortcuts backend (every wlroots one), a dismissed dialog, a malformed
/// reply, a discarded bind and a disposed adapter all resolve to
/// [HotkeyUnavailable]. [bind] never throws and never rejects, and that is
/// structural rather than by inspection: its body's one `catch` takes `Object`.
///
/// **No Flutter import, and that is a command rather than a style rule.**
/// `test/infrastructure/system/daemon_startup_test.dart` imports this file and
/// runs under `dart test`, which cannot resolve `dart:ui`. An import reaching
/// here stops the whole binding-free suite resolving rather than failing one
/// test. `package:dbus` is pure `dart:io`, so this costs nothing —
/// `test/architecture/hotkey_confinement_test.dart` holds both halves.
final class WaylandPortalGlobalHotkey implements GlobalHotkey {
  /// [client] is a test seam, and the only one this adapter has.
  ///
  /// Nothing but this sentence and the composition root's single call site stops
  /// production code passing its own client — the same shape the ledger already
  /// flags on `AppDatabase`. It is here because the whole of AD-11 is a claim
  /// about what reaches the bus and in what order, and the only way to assert
  /// that is to point the adapter at a bus a test owns. `DBusClient.session()`
  /// is what the daemon gets, and it is inert until the first call
  /// (`callMethod` awaits a lazy `_connect()`), so constructing this adapter on
  /// a session with no bus at all costs nothing and connects to nothing.
  ///
  /// It is a factory because `DBusClient.session()` **can throw**, and a throw
  /// out of here would not degrade anything — it would stop the daemon. That
  /// constructor parses `DBUS_SESSION_BUS_ADDRESS` eagerly and raises
  /// `FormatException` for any value with no `transport:` prefix, which includes
  /// an empty string and the bare socket path people write by hand. The throw
  /// would escape `DaemonStartup._hotkeyFor` inside `begin`'s try, which
  /// releases the AD-14 address and rethrows: no daemon, no tray, no panel,
  /// where AD-12 and the spine's operational envelope both require a degraded
  /// start. So an address this build cannot read becomes [HotkeyUnavailable]
  /// from [bind], like every other way the bus can be out of reach.
  ///
  /// [appIdRegime] is resolved at the composition root, not here, and that is
  /// AD-9's rule rather than a preference: it is the same class of question as
  /// the display server — asked once, from the process environment, with no
  /// runtime switch — so the adapter is handed the answer instead of asking it.
  /// Asking it here would also put the sandbox probe on this file's import
  /// graph, where every test that constructs the adapter would inherit it.
  ///
  /// [requestTimeout] is the composition root's one budget for a platform call
  /// that never settles, handed here rather than restated — see
  /// [_requestBudget].
  factory WaylandPortalGlobalHotkey({
    DBusClient? client,
    required PortalAppIdRegime appIdRegime,
    required Duration requestTimeout,
    required Logger logger,
  }) {
    if (client != null) {
      return WaylandPortalGlobalHotkey._(
        client,
        appIdRegime,
        requestTimeout,
        logger,
      );
    }
    try {
      return WaylandPortalGlobalHotkey._(
        DBusClient.session(),
        appIdRegime,
        requestTimeout,
        logger,
      );
    } on Object catch (error) {
      // Logged here rather than at bind time, because this is the one failure
      // that is already decided before anything is asked of the adapter, and the
      // user's own configuration is what decided it.
      try {
        logger.error(
          'DBUS_SESSION_BUS_ADDRESS could not be read as a D-Bus address, so '
          'no global shortcut can be requested',
          context: _errorContext(error),
        );
      } on Object {
        // Nowhere left to report this: the reporting channel is what broke.
      }
      return WaylandPortalGlobalHotkey._(
        null,
        appIdRegime,
        requestTimeout,
        logger,
      );
    }
  }

  WaylandPortalGlobalHotkey._(
    this._client,
    this._appIdRegime,
    this._requestBudget,
    this._logger,
  );

  /// The reverse-DNS application id AD-11 fixes.
  ///
  /// Public because it is half of a two-part requirement: AD-11 says the id must
  /// also have an installed `.desktop` file of the *same basename*, and the file
  /// that ships it belongs to the packaging story. A test that pins the two
  /// together needs to be able to name this one — and one test asserts this
  /// constant against the literal spelling, because every other assertion
  /// compares the wire value against this same constant and would stay green
  /// through a rename.
  static const String applicationId =
      'com.divertedriver.HotkeyGrammarCorrector';

  /// The one shortcut this app declares. AD-11 names it, and the `Activated`
  /// filter and the read-back check both key off it.
  static const String shortcutId = 'toggle-panel';

  /// The session bus client, or null when `DBUS_SESSION_BUS_ADDRESS` could not
  /// be parsed at all — see the factory constructor.
  ///
  /// Nullable rather than substituted, because there is no honest substitute: an
  /// address this build cannot read is not the same thing as a default one. It
  /// is threaded into every step that needs it rather than read through a
  /// null-assertion, so the one branch that handles its absence is in [_bind],
  /// where it is an AD-12 value like any other.
  final DBusClient? _client;

  /// Which mechanism owns this process's application id, and so whether step 1
  /// of the handshake runs at all — see [_registerApplicationIdOnce].
  final PortalAppIdRegime _appIdRegime;

  /// How long one **dialogless** portal round trip may hold the settings screen
  /// before the wait is abandoned (D-17).
  ///
  /// Injected, not declared: this is the composition root's single policy for a
  /// platform call that never settles, the same constant the panel adapter and
  /// the teardown sequence take. A number authored here would be a second
  /// policy nobody decided on, and the two would be free to drift.
  ///
  /// It is a bound on *waiting*, not a cancellation: Dart cannot recall a call
  /// that is already out, and this adapter deliberately does not try — see
  /// [_dialogBudget] and [_answeredWithin].
  final Duration _requestBudget;

  /// The bound for the **one** step with a human behind it: `BindShortcuts`,
  /// where the portal shows its own dialog and waits for an answer.
  ///
  /// Derived from [_requestBudget] rather than authored, so there is still one
  /// number argued with in one place and the relationship to it is visible
  /// instead of coincidental. At the shipped five seconds this is a minute.
  ///
  /// **Why it is bounded at all, and why not at the dialogless bound.** D-17
  /// says a portal that never answers must fail after a few seconds so the
  /// settings screen never hangs with no way out, and leaving this one step
  /// unbounded would leave the widest hang open — the dialog step is exactly
  /// where a portal stops answering. But a few seconds is nowhere near long
  /// enough for a person to notice a dialog, read it and click Allow, and a
  /// bound that fires while they are reading would report the shortcut dead and
  /// then have it come alive underneath them. A minute is long enough that
  /// expiry means something is wrong rather than that someone is slow.
  ///
  /// Expiry abandons the wait and sends nothing: see [_answeredWithin] and the
  /// arm in [_bind] that deliberately does **not** close the session.
  Duration get _dialogBudget => _requestBudget * _dialogBudgetFactor;

  final Logger _logger;

  final StreamController<void> _activations =
      StreamController<void>.broadcast();

  /// Where a compositor-initiated change goes, which until this member existed
  /// was nowhere — see [_onShortcutsChanged].
  final StreamController<HotkeyBindOutcome> _bindingChanges =
      StreamController<HotkeyBindOutcome>.broadcast();

  /// The live session's object path, or null when none is open.
  ///
  /// Read by three paths: a rebind closes it first, the `Activated` filter
  /// compares against it, and teardown closes it. Every writer clears it
  /// *before* awaiting a Close and restores it only if that Close was refused,
  /// so at most one Close is ever in flight for one session: a `dispose()`
  /// landing while a rebind's Close is outstanding would otherwise send a second
  /// one, which the portal answers with `UnknownObject` and which teardown would
  /// then log as a failure that did not happen.
  DBusObjectPath? _session;

  StreamSubscription<DBusSignal>? _activated;
  StreamSubscription<DBusSignal>? _shortcutsChanged;

  /// AD-11's "once, before any other portal call", latched to the connection it
  /// was issued on.
  ///
  /// Per-instance rather than `static`, and that is the correct reading rather
  /// than a convenience: `Registry.Register` associates an app id with the
  /// *caller's bus connection*, and this adapter owns its connection. AD-9
  /// permits exactly one adapter per process, so once per client is once per
  /// process — while a static latch would be a claim about a connection this
  /// class does not own, and would be wrong the moment a second one existed.
  bool _registered = false;

  /// Set once a call failed *before it reached the bus*, carrying the refusal
  /// that said why — both the sentence and the cause a consumer branches on.
  ///
  /// This is a workaround for a measured `package:dbus` 0.7.14 defect, and
  /// without it the second `bind()` of a session never resolves at all.
  /// `_connect()` assigns its completer before `await _openSocket()` and never
  /// completes it when that throws, so every later call on the client waits on a
  /// completer nobody will complete. `SettingsController._bind` has no timeout,
  /// so a user who opens the settings screen on a session with no bus and
  /// changes the hotkey would get a screen that never resolves. Latching the
  /// dead connection turns the second and every later attempt into the same
  /// answer the first one gave.
  _Refusal? _deadConnection;

  /// What [current] answers: the newest outcome this adapter produced, from a
  /// [bind] or from a `ShortcutsChanged`, whichever came last. Null until one
  /// of the two has happened.
  ///
  /// The reason the port has a synchronous member at all lives on that member;
  /// what this field adds is that the settings screen is almost never mounted
  /// when a `ShortcutsChanged` arrives, so [bindingChanges] alone would drop
  /// the compositor-side rebind this whole adapter exists to notice.
  HotkeyStatus? _status;

  /// How many backend-originated changes have been recorded, read only to
  /// decide whether a [bind] answer is still the newest thing known.
  ///
  /// [_status]'s contract is "whichever is newer", and a bind can be in flight
  /// for a minute behind a portal dialog — so a `ShortcutsChanged` that lands
  /// while it waits is newer than the answer that arrives afterwards.
  /// Comparing this against the value captured when the bind was issued is
  /// what stops that answer overwriting it. It counts backend changes only:
  /// counting bind answers too would let one queued bind discard the next
  /// one's answer.
  int _backendChanges = 0;

  /// The compositor's own wording for the shortcut it currently holds, kept
  /// verbatim and never parsed — the portal's `trigger_description`.
  ///
  /// Written from the `BindShortcuts` read-back, from every `ShortcutsChanged`
  /// that still holds our id, and from an explicit `ListShortcuts` re-read.
  /// Cleared when the compositor says it no longer holds the shortcut, because
  /// wording for a shortcut nobody holds describes nothing.
  ///
  /// **Not cleared at the start of a rebind**, and that is load-bearing: a
  /// rebind whose `Session.Close` is refused is abandoned and answers
  /// `HotkeyRetained` for the shortcut that is *still* in effect, so what the
  /// user must be shown there is the **previous** description. Clearing on the
  /// way in would show them nothing about a shortcut that is still firing.
  String? _backendDescription;

  bool _disposed = false;

  /// The tail of the serialized bind chain — the same idiom, for the same
  /// reason, as `X11GlobalHotkey._queue`.
  ///
  /// A rebind here is close-then-create-then-bind across three awaits, so two
  /// overlapping calls would interleave. The portal's own rule makes the
  /// consequence worse than a wasted round trip: "an application can only
  /// attempt bind shortcuts of a session once", so the two calls cannot share a
  /// session, and an interleaving leaves the compositor holding **two** sessions
  /// with two shortcuts while this adapter tracks one. One press would then
  /// toggle the panel twice, and the untracked session would outlive every
  /// rebind. The window is real: `SettingsController.changeHotkey` has no
  /// in-flight guard of its own, and a portal dialog makes it seconds wide by
  /// design.
  Future<void> _queue = Future<void>.value();

  /// Distinct per call, and both halves matter.
  ///
  /// The counter is what makes a token unique within the process: a reused
  /// `handle_token` collides with a live Request object path, and a reused
  /// `session_handle_token` with a live session. The random suffix is what keeps
  /// two processes of this app on one bus from colliding with each other. Both
  /// stay inside `[A-Za-z0-9_]`, because the portal builds an object *path*
  /// segment out of the token and anything else is not a valid one.
  ///
  /// [Random.secure] rather than `Random()`: the Request object path is built
  /// from these tokens, and [_callThroughRequest] treats the path as the reason
  /// it can match a `Response` without filtering on sender. A time-seeded
  /// non-cryptographic generator would make that path guessable by any other
  /// peer on the session bus, which is the whole of what the argument rests on.
  int _tokenSequence = 0;
  final Random _random = Random.secure();

  /// Broadcast: `PanelController` is not promised to be the only consumer.
  @override
  Stream<void> get activations => _activations.stream;

  /// AD-11's `ShortcutsChanged`, as the value AD-10's surface renders.
  @override
  Stream<HotkeyBindOutcome> get bindingChanges => _bindingChanges.stream;

  /// The newest of what [bind] answered and what the compositor last said,
  /// with the compositor's own wording beside it.
  ///
  /// **Reads two fields and touches the bus for neither.** `ListShortcuts` is
  /// this adapter's re-read of what the compositor holds and it is deliberately
  /// not on this path: the caller of this member is a surface being built, and
  /// a portal round trip here would hang it for as long as the portal took —
  /// which is the failure HOTKEY-06 exists to prevent, on the one backend where
  /// a call can sit behind a dialog for a minute.
  @override
  HotkeyStatus? get current => _status;

  /// Serialized against every other in-flight [bind]; see [_queue].
  @override
  Future<HotkeyBindOutcome> bind(HotkeyBinding binding) {
    // Answered *ahead* of the queue, not inside it, and the ordering is the
    // point. [_queue] chains each bind onto the previous one, so one call that
    // never resolves — the filed never-answering portal — parks every later bind
    // behind it, including the two that need no portal at all. Row A22 requires
    // a disposed adapter to answer with zero portal calls, and it has to hold
    // whatever is still in flight; measured, with a call hung these two answers
    // waited on it forever. `_bind` re-checks both, because a teardown can still
    // land while this one is queued.
    if (_disposed) {
      return Future<HotkeyBindOutcome>.value(
        _recordStatus(_shutDownDuringBind()),
      );
    }
    final dead = _deadConnection;
    if (dead != null) {
      return Future<HotkeyBindOutcome>.value(
        _recordStatus(
          HotkeyUnavailable(cause: dead.cause, message: dead.message),
        ),
      );
    }
    // Recorded on the way out rather than at each `return` inside [_bind]:
    // every one of that method's answers passes through here, which is what
    // makes "every outcome updates [current]" a property of the shape rather
    // than of a dozen remembered assignments four steps deep in a handshake.
    final issuedAt = _backendChanges;
    final result = _queue
        .then((_) => _bind(binding))
        .then((outcome) => _recordBindAnswer(outcome, issuedAt));
    // The chain must outlive a link that failed, or one rejection would park
    // every later bind forever. `_bind` never rejects, so this is the same
    // belt-and-braces the X11 adapter's queue carries.
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<HotkeyBindOutcome> _bind(HotkeyBinding binding) async {
    if (_disposed) {
      return _shutDownDuringBind();
    }
    final dead = _deadConnection;
    if (dead != null) {
      return HotkeyUnavailable(cause: dead.cause, message: dead.message);
    }
    final client = _client;
    if (client == null) {
      // The AD-12 answer for a DBUS_SESSION_BUS_ADDRESS this build cannot read;
      // see the factory constructor, which is where that was decided. No bus
      // means no portal to reach, so no combination the user picks can help.
      return const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: _unusableBusAddress,
      );
    }

    try {
      // Step 1, which a sandboxed build skips entirely — see the method. Its
      // *refusal* is never fatal — AD-12 names only CreateSession and
      // BindShortcuts as the steps whose failure means no hotkey — but a
      // failure to reach the bus at all is, and cannot be otherwise.
      await _registerApplicationIdOnce(client);
      // The first of the post-await guards, and they are all explicitly
      // defensive: `dispose()` is not queued behind [bind] — a daemon that must
      // exit cannot wait on a portal dialog — so a stop signal can land while
      // this is parked. **The guards that follow a call to the bus are not
      // reachable by a test in this container**, and the reason is the same
      // `package:dbus` defect [_deadConnection] works around:
      // `DBusClient.close()` leaves every in-flight call's completer
      // un-completed, so those awaits never resume once teardown has run. They
      // are kept because they are correct, cheap, and the natural upstream fix —
      // erroring pending calls on close — makes every one of them live. Filed.
      // The one exception, and the reason this claim is qualified rather than
      // blanket: the re-check in [_closeSessionBeforeRebinding]'s refusal arm
      // follows a *log* call rather than a bus call, and this adapter's suite
      // drives it with a logger that tears the adapter down from inside
      // `error()`.
      if (_disposed) {
        return _shutDownDuringBind();
      }

      // Step 2's precondition on a rebind, and its own outcome when it fails.
      final abandoned = await _closeSessionBeforeRebinding(client);
      if (abandoned != null) {
        return abandoned;
      }
      if (_disposed) {
        return _shutDownDuringBind();
      }

      final session = await _createSession(client);
      if (_disposed) {
        // The one place a session is knowingly left open, and the only place it
        // can be: teardown has closed the client, so there is nothing left to
        // send a Close on. The portal ties a session to the caller's bus
        // connection, so closing the client is itself what ends it, and every
        // path that sets `_disposed` is followed by process exit.
        return _shutDownDuringBind();
      }
      try {
        await _bindShortcut(client: client, session: session, binding: binding);
      } on _PortalRefusal catch (refusal) {
        if (refusal.abandoned) {
          // **The one refusal that must not close the session** (D-17). This
          // adapter stopped waiting on `BindShortcuts`, and the portal shows
          // its dialog on exactly that call — so the request may be on the
          // user's screen right now, and a Close here would withdraw what they
          // are being asked to approve. Abandoning a wait is permitted;
          // cancelling a live dialog is not.
          //
          // The session is *tracked* instead, which is the alternative to both
          // closing it and leaking it. Tracked, a later rebind closes it before
          // creating another, so two overlapping attempts cannot leave the
          // compositor holding two live sessions — and the `Activated` filter
          // reads `_session` at delivery time, so if the user does click Allow
          // a minute late, the press works and `ShortcutsChanged` tells the
          // settings surface it is live. What this bind reports is still
          // unavailable, because nothing has been granted yet: the answer is
          // corrected by the compositor, never predicted here.
          if (!_disposed) {
            _session = session;
            _listenForShortcutSignals(client);
          }
          rethrow;
        }
        await _guard(
          'closing a global shortcuts session whose bind did not complete',
          // Bounded for the reason `dispose()`'s Close is bounded — see there
          // for the measurement. `_guard` reduces a *throw* and can do nothing
          // about a Close that never settles, and an unbounded one here does
          // not fail the bind, it parks `changeHotkey` short of its terminal
          // state: `mutationInFlight` stays true, `_beginMutation` refuses every
          // later mutation, and the settings surface is disabled for the life of
          // the daemon. That is the hang D-17 exists to prevent, reached through
          // the arm added to satisfy it — and this arm carries the whole
          // non-abandoned refusal set, including the documented GNOME
          // empty-subset discard, which is every bind on a real session until
          // the packaging story ships the `.desktop` file.
          //
          // Only the *wait* is abandoned, so this does not breach the rule the
          // arm above states: the portal has already answered here, so there is
          // no dialog on screen to withdraw. What is given up is knowing the
          // session closed, and the worst case is one orphaned session on a
          // portal that is not answering anyway.
          () => _closeSession(client, session).timeout(_teardownBudget),
        );
        rethrow;
      } on Object {
        // The session exists on the compositor and this adapter is one line away
        // from stopping tracking it. Without this, every refusal after step 2 —
        // a non-zero Response, the documented empty-subset discard, a malformed
        // reply — orphans one session per attempt: `_closeSessionBeforeRebinding`
        // returns early because `_session` was never assigned, and `dispose()`
        // closes nothing. That is not a corner case but the path a real GNOME
        // session takes on every bind until the packaging story ships the
        // `.desktop` file, so a settings screen retried a few times would leave
        // the compositor holding a handful of live sessions.
        await _guard(
          'closing a global shortcuts session whose bind did not complete',
          // Bounded on the same reasoning as the refusal arm above, and here
          // the dead socket is not hypothetical but the likeliest way in: a
          // transport failure inside `_bindShortcut` latches [_deadConnection]
          // and throws, so this Close is issued on the connection that was just
          // classified as dead — and `package:dbus` never completes a call
          // whose socket died under it. Unbounded, this is the same permanent
          // `mutationInFlight` lockout.
          () => _closeSession(client, session).timeout(_teardownBudget),
        );
        rethrow;
      }
      if (_disposed) {
        return _shutDownDuringBind();
      }
      _session = session;
      // Step 4, and last: subscribing before this point would deliver an
      // `Activated` for a shortcut that is not bound yet.
      _listenForShortcutSignals(client);
      if (_backendDescription == null) {
        // The grant carried no wording, so the one thing this backend can
        // report about the shortcut in force is missing and the settings screen
        // has nothing to show for a shortcut that works. Asking is the
        // interface's own remedy — see [_readBackDescription], including why it
        // is not asked unconditionally.
        await _readBackDescription(client, session);
      }
      return const HotkeyBound(
        HotkeyRegistration(
          effective: null,
          authority: BindingAuthority.compositor,
        ),
      );
    } on _PortalRefusal catch (refusal) {
      // Both halves come out of the handshake already decided — the cause was
      // chosen where the condition was detected, four steps down, not inferred
      // from the sentence here.
      return HotkeyUnavailable(cause: refusal.cause, message: refusal.message);
    } on Object catch (error) {
      // The class doc promises unconditionally that `bind()` never throws, and
      // `DaemonStartup.requestBinding` and `SettingsController._bind` both exist
      // to absorb the breach if it ever did. This arm is what makes the promise
      // structural instead of a claim about the paths a reader happened to
      // check: a defect in this file becomes a visible degradation plus one
      // error line (see [_messageFor]) rather than an unhandled rejection during
      // startup.
      final refusal = _refusalFor(error);
      return HotkeyUnavailable(cause: refusal.cause, message: refusal.message);
    }
  }

  /// AD-11 step 1, now conditional. Advisory app-id association, and tolerant
  /// by design on the one branch that makes it.
  ///
  /// **A sandboxed (Flatpak) build must not call this at all**, and the
  /// specification is what makes that a rule rather than an optimisation: the
  /// interface "will not work with applications xdg-desktop-portal identifies
  /// as sandboxed". Inside a sandbox the portal derives the app id from the
  /// sandbox metadata, so a Register from there is a claim this process is not
  /// entitled to make — noise at best, an error line on every launch at worst.
  ///
  /// This method shipped the non-sandboxed path unconditionally for one
  /// recorded reason, and that reason is now answered rather than overruled: no
  /// sandbox detector existed here because the signals one would key off
  /// include `/.dockerenv`, which is true in this project's own container, so a
  /// detector would take the sandboxed branch in every test run and leave the
  /// first invariant of AD-11 executed by nothing. [PortalAppIdRegime] keys on
  /// `/.flatpak-info` and `FLATPAK_ID` instead — written by the Flatpak runtime
  /// and by nothing else, both absent in that container — and the container
  /// markers are rejected there by name, with the measurement. Packaging is no
  /// longer undecided either: the committed set includes Flatpak, which is what
  /// turns this step into a variable in the sequence. Filed in
  /// `_bmad-output/implementation-artifacts/deferred-work.md` as DW-89, closed
  /// 2026-09-01 with that packaging decision recorded.
  ///
  /// The regime check sits **ahead** of the once-per-connection latch rather
  /// than replacing it: the latch is AD-11's "once, before any other portal
  /// call" and it still has to hold on the branch that registers, while a
  /// sandboxed build's second bind must be as silent as its first.
  Future<void> _registerApplicationIdOnce(DBusClient client) async {
    if (_appIdRegime == PortalAppIdRegime.sandboxSupplied) {
      // Before the latch, before the bus, and before any log line: nothing
      // happened here, so nothing may be reported as having happened.
      return;
    }
    if (_registered) {
      return;
    }
    try {
      // Bounded, and abandoned rather than escalated when it expires. There is
      // no dialog behind Register, so nothing is taken away from the user by
      // stopping the wait — and AD-11 makes the whole step advisory, so a
      // registry that goes quiet costs one error line and the sequence carries
      // on, exactly as a refusal does. The alternative would be to fail the
      // bind over an advisory step, which is the one thing AD-11 says not to do.
      final answered = await _answeredWithin(
        _requestBudget,
        _registerCall,
        () async {
          // The reply is discarded on purpose — `Register` declares no
          // out-arguments, and the one Registry that sends some is handled by
          // the signature arm below. Written as a block rather than a
          // one-expression closure so what reaches the bound is a real
          // `Future<void>`; see [_answeredWithin].
          await client.callMethod(
            destination: _registryService,
            path: _registryPath,
            interface: _registryInterface,
            name: 'Register',
            values: [
              DBusString(applicationId),
              DBusDict.stringVariant(const {}),
            ],
            replySignature: DBusSignature(''),
          );
        },
      );
      if (!answered) {
        // The latch is deliberately not set, for the reason the connection arm
        // below gives: AD-11 says Register happens once, and a call this
        // process stopped waiting on has not happened yet. A later rebind may
        // find a registry that answers.
        return;
      }
    } on DBusUnknownMethodException {
      // Tolerated, and not an error: xdg-desktop-portal before 1.20 has no
      // Registry interface at all.
    } on DBusUnknownInterfaceException {
      // The same absence, one level up, and tolerated for the same reason.
      // Which of these four names a portal without the Registry answers with is
      // not something this project can settle — [_messageFor] already treats
      // UnknownMethod and UnknownInterface as one class on exactly that ground,
      // and this path must not settle it the other way. Getting it wrong here
      // would put an error line on the happy path of every launch, on the one
      // signal this code itself calls the likeliest cause of a later discard.
    } on DBusUnknownObjectException {
      // Nobody exports `/org/freedesktop/host/portal/registry`.
    } on DBusServiceUnknownException {
      // Nobody owns the host portal name.
    } on DBusMethodResponseException catch (error) {
      // A live bus refused the association. The sequence continues, because
      // AD-11 makes this step advisory, but the refusal is the likeliest cause
      // of a bind GNOME later discards, so it must not be silent.
      _log(
        () => _logger.error(
          'the portal registry refused the application id association; the '
          'global shortcuts handshake continues without it',
          context: _errorContext(error),
        ),
      );
    } on Object catch (error) {
      if (_isConnectionFailure(error)) {
        // The connection itself failing — no session bus, or a client already
        // closed. AD-11's tolerance does not extend to it, and **cannot**:
        // carrying on would leave `bind()` pending for the life of the daemon
        // (see [_deadConnection]) and the tray would never be told hotkeys are
        // unavailable. So the handshake stops with the diagnosis that fits the
        // real cause, which is also the one AD-12 wants in front of the user.
        //
        // Note what is *not* done: the latch below is not set. AD-11 says
        // Register happens once, and a call that never reached the bus did not
        // happen — latching it here would consume step 1 for the life of the
        // process, so a later retry from the settings screen would bind an app
        // id the portal was never told about and be discarded, telling the user
        // to install a `.desktop` file they may already have.
        //
        // That reasoning is currently **masked rather than exercised**, and
        // saying so is the honest form of it: `_recordDeadConnection` latches on
        // this same statement, and [_bind] answers out of that latch before it
        // could ever reach this method a second time, so no retry can get back
        // to step 1 today. Measured as failing zero tests in both directions —
        // recorded here rather than left looking pinned. It becomes live the
        // moment the upstream `package:dbus` fix the ledger names lands and
        // [_deadConnection] can go.
        throw _PortalRefusal.of(_recordDeadConnection(error));
      }
      // Everything else: a live bus, and a Registry that answered in a way this
      // build did not expect. The measured one is `DBusReplySignatureException`
      // — a Registry that returns an out-argument where `Register` declares none
      // — and it is **not** a `DBusMethodResponseException` (`package:dbus` has
      // it implement `Exception` directly), so before this branch existed it
      // fell to the connection arm above and latched the whole client dead: one
      // non-conformant reply from an *advisory* step answered every later
      // `bind()` for the life of the process without touching the bus. AD-11
      // says any other Register failure is one error line and the sequence
      // continues, so that is what this is.
      _log(
        () => _logger.error(
          'the portal registry answered the application id association in a '
          'shape this build cannot read; the global shortcuts handshake '
          'continues without it',
          context: _errorContext(error),
        ),
      );
    }
    // Latched only once the bus answered — with a reply or with a refusal.
    _registered = true;
  }

  /// AD-11 step 2, over a Request object.
  Future<DBusObjectPath> _createSession(DBusClient client) async {
    final response = await _callThroughRequest(
      client: client,
      name: 'CreateSession',
      // The short bound: the GlobalShortcuts portal shows no dialog here, and
      // the comment on the refusal below says so for the same reason.
      budget: _requestBudget,
      values: [
        DBusDict.stringVariant({
          'handle_token': DBusString(_newToken()),
          'session_handle_token': DBusString(_newToken()),
        }),
      ],
    );
    if (response.code != _granted) {
      // No mention of a dialog: the GlobalShortcuts portal shows its dialog on
      // `BindShortcuts`, not here, so a user sent looking for one they were
      // never shown would be hunting for something that does not exist.
      throw const _PortalRefusal(
        // A portal answered and said no, so a backend is present. Not
        // `noBackend`: this session has global shortcuts, it declined to open a
        // request for them.
        cause: HotkeyUnavailableCause.keyRefused,
        message:
            'this session refused to open a global shortcuts request, so the '
            'hotkey is inactive — the tray menu still opens the panel',
      );
    }
    final handle = response.results['session_handle'];
    // Documented as `s` rather than `o`, and some backends send `o`. Both are a
    // `DBusString` here, so the path is parsed from the text either way.
    if (handle is! DBusString) {
      throw const _PortalRefusal(
        cause: _malformedReplyCause,
        message: _malformedReply,
      );
    }
    try {
      return DBusObjectPath(handle.value);
    } on Object {
      // An object path this app then could not call Close on.
      throw const _PortalRefusal(
        cause: _malformedReplyCause,
        message: _malformedReply,
      );
    }
  }

  /// AD-11 step 3, over a Request object, including the read-back the whole
  /// story turns on.
  Future<void> _bindShortcut({
    required DBusClient client,
    required DBusObjectPath session,
    required HotkeyBinding binding,
  }) async {
    final response = await _callThroughRequest(
      client: client,
      name: 'BindShortcuts',
      // The long bound, and the only step that gets it: this is the one a
      // person is being asked to answer — see [_dialogBudget].
      budget: _dialogBudget,
      values: [
        session,
        DBusArray(DBusSignature('(sa{sv})'), [
          DBusStruct([
            DBusString(shortcutId),
            DBusDict.stringVariant(_shortcutRequest(binding)),
          ]),
        ]),
        // No window of ours is involved: the portal parents its dialog itself.
        const DBusString(''),
        // Its own `handle_token`, distinct from the session's: this call gets a
        // Request object of its own, and reusing the token would put its
        // `Response` on a path that is already in use.
        DBusDict.stringVariant({'handle_token': DBusString(_newToken())}),
      ],
    );
    if (response.code != _granted) {
      // This is the step with a dialog behind it, so this is the message that
      // may name one.
      throw const _PortalRefusal(
        // The canonical `keyRefused`: a working compositor was asked for this
        // combination and did not grant it. Another one may be granted, and on
        // the dismissed-dialog path simply asking again may be.
        cause: HotkeyUnavailableCause.keyRefused,
        message:
            'the compositor did not grant the global shortcut — the portal '
            'dialog was dismissed or the request was refused — so the hotkey '
            'is inactive; the tray menu still opens the panel',
      );
    }

    final bound = _shortcutsIn(response.results['shortcuts']);
    if (bound == null) {
      throw const _PortalRefusal(
        cause: _malformedReplyCause,
        message: _malformedReply,
      );
    }
    if (!bound.containsKey(shortcutId)) {
      // The documented discard, not an error: the reply is a *successful*
      // response whose subset does not include what was asked for.
      throw const _PortalRefusal(
        // The documented discard: a *successful* response whose read-back
        // subset omits what was asked for. A working portal that declined this
        // request — `keyRefused`, exactly as AD-12 names it, even though the
        // remedy the sentence gives is a `.desktop` entry rather than a
        // different combination.
        cause: HotkeyUnavailableCause.keyRefused,
        message:
            'the compositor discarded the global shortcut for application id '
            '$applicationId, which needs a matching '
            '$applicationId.desktop entry installed for the compositor to '
            'keep it — so the hotkey is inactive and '
            // Re-wrapped, not reworded: the deeper nesting the `cause:`
            // argument adds pushed this clause across two lines, and the
            // guardrail that checks every message ends by naming the tray
            // counts per line. Same fix, same reason, as plan 01-03's.
            'the tray menu still opens the panel',
      );
    }
    // After the read-back check, never before it: a portal that discarded the
    // bind answers *successfully* with our id missing, and seeding a
    // description for a shortcut it is not holding is exactly the false claim
    // the check above exists to catch.
    //
    // Assigned unconditionally, including when the portal sent no description
    // at all. Leaving the field alone in that case would show the user the
    // *previous* shortcut's wording beside a newly bound one — and the previous
    // session was closed before this call was made.
    _backendDescription = _logTriggerDescription(bound[shortcutId]);
  }

  /// Asks the compositor what this session holds now, and takes the wording
  /// from its answer — AD-10's read-back, on demand.
  ///
  /// `ListShortcuts` is on the same interface, answers with the same
  /// `shortcuts a(sa{sv})` on its Response, and this adapter had never called
  /// it. It goes through [_callThroughRequest] rather than the bus directly, so
  /// it inherits every property that method argues for: the resolved unique
  /// sender, the [Random.secure] handle token, the subscribe-before-call
  /// ordering, and the bound. The short bound: there is no dialog behind a
  /// list, so nothing here is being answered by a person.
  ///
  /// **Not reachable from [current], deliberately.** That member is read by a
  /// settings surface being built, and a round trip there would hang it for as
  /// long as the portal took — the failure HOTKEY-06 exists to prevent. This is
  /// the explicit re-read; the getter reads the cache.
  ///
  /// **Not called on every bind, either.** AD-11 fixes the handshake at four
  /// steps and a fifth call on the happy path would add one to an invariant the
  /// spine states. It is called on one condition: a bind the compositor granted
  /// whose read-back carried no `trigger_description` at all, where the
  /// alternative to asking is a settings screen with nothing to say about a
  /// shortcut that works.
  ///
  /// Failure costs nothing but a log line — the bind has already succeeded, so
  /// a portal that refuses this or answers it unreadably leaves the wording
  /// absent, exactly as it was.
  Future<void> _readBackDescription(
    DBusClient client,
    DBusObjectPath session,
  ) async {
    try {
      final response = await _callThroughRequest(
        client: client,
        name: 'ListShortcuts',
        budget: _requestBudget,
        values: [
          session,
          DBusDict.stringVariant({'handle_token': DBusString(_newToken())}),
        ],
      );
      if (_disposed) {
        return;
      }
      final held = response.code == _granted
          ? _shortcutsIn(response.results['shortcuts'])
          : null;
      final description = _descriptionIn(held?[shortcutId]);
      if (description == null) {
        _log(
          () => _logger.info(
            'the compositor listed this session without describing how the '
            'global shortcut is triggered, so the settings screen has no '
            'wording of its own to show',
          ),
        );
        return;
      }
      _backendDescription = description;
    } on Object catch (error) {
      // Reduced to a log line rather than a refusal: the shortcut is bound,
      // and failing the bind over the wording for it would take a working
      // hotkey away from the user over a sentence.
      _log(
        () => _logger.error(
          'the compositor did not answer a re-read of the global shortcuts it '
          'holds, so the settings screen shows no wording for one that is '
          'nonetheless in effect',
          context: _errorContext(error),
        ),
      );
    }
  }

  /// The `description` and `preferred_trigger` AD-11 names.
  ///
  /// An unrepresentable key omits `preferred_trigger` rather than refusing the
  /// bind, which is deliberately the opposite of what the X11 adapter does with
  /// the same request. On X11 the app owns the grab, so a key it cannot express
  /// is a shortcut that cannot exist. Under the portal the app owns nothing: the
  /// trigger is a documented hint, the compositor and the user choose the
  /// combination, and the portal shows its own dialog. Refusing would deny the
  /// user a working shortcut over a preference we merely could not phrase. The
  /// two adapters differ because the authority differs, which is what AD-10
  /// exists to say.
  Map<String, DBusValue> _shortcutRequest(HotkeyBinding binding) {
    final description = DBusString('Show the grammar correction panel');
    final trigger = XdgShortcutTrigger.forBinding(binding);
    if (trigger == null) {
      _log(
        () => _logger.info(
          'the configured key cannot be expressed as an XDG shortcut trigger, '
          'so the compositor is asked for the shortcut without a preferred '
          'combination',
          context: {'key': binding.key},
        ),
      );
      return {'description': description};
    }
    return {
      'description': description,
      'preferred_trigger': DBusString(trigger),
    };
  }

  /// Issues one portal call and awaits its `Response` signal.
  ///
  /// The subscription is established **before** the call, and that ordering is
  /// load-bearing rather than tidy. The portal's Request convention exists
  /// because of a documented race: a caller that subscribes only after the
  /// method reply can miss a `Response` that was already emitted. Subscribing
  /// first closes it — `package:dbus` registers the stream in the client
  /// synchronously on listen and its `AddMatch` reaches the bus ahead of the
  /// call, so the rule is installed before the bus forwards it. This does not
  /// bend AD-11's order: AD-11's steps are the portal *operations*, and awaiting
  /// a `Response` is part of steps 2 and 3.
  ///
  /// The signal is matched on sender, interface, member and the path the call
  /// answered with — all four, and the sender is the one that took work.
  /// Passing the portal's *well-known* name here would not do: `package:dbus`
  /// resolves a well-known sender through a name-owner cache populated by an
  /// asynchronous `GetNameOwner`, and this stream is created with a call already
  /// about to go out, so a `Response` arriving before that lookup resolved would
  /// be dropped — the exact race this method exists to close. So the unique name
  /// is resolved *first*, by [_portalSender], and matched directly; the
  /// subscription still precedes the call, which is all row A15 asks.
  ///
  /// Why it is worth a round trip: without it this stream accepted any
  /// `Response` on the right object path from any peer on the session bus
  /// (measured — a client owning no name forged one and the adapter reported
  /// `HotkeyBound`). Path secrecy was the stated substitute, and it is not one:
  /// the path is a fixed prefix plus a token, and a token is a guessing budget
  /// rather than an authenticator. It still carries [Random.secure] entropy,
  /// which is now defence in depth instead of the whole argument.
  Future<({int code, Map<String, DBusValue> results})> _callThroughRequest({
    required DBusClient client,
    required String name,
    required List<DBusValue> values,
    required Duration budget,
  }) async {
    final sender = await _portalSender(client);
    final buffered = <DBusSignal>[];
    final answered = Completer<DBusSignal>();
    DBusObjectPath? requestPath;

    void consider(DBusSignal signal) {
      if (answered.isCompleted) {
        return;
      }
      // Buffered rather than filtered: the path to match against is what the
      // call has not returned yet.
      if (requestPath == null) {
        buffered.add(signal);
        return;
      }
      if (signal.path == requestPath) {
        answered.complete(signal);
      }
    }

    // No `signature:` is supplied on purpose. With one, `package:dbus` pushes a
    // `DBusSignalSignatureException` onto the stream for any Response that does
    // not match — including one for somebody else's request — and an error on a
    // stream whose only consumer is this closure becomes an unhandled zone
    // error. The shape is checked in [_readResponse] instead, where a malformed
    // reply is the value AD-12 requires.
    final responses = DBusSignalStream(
      client,
      sender: sender,
      interface: _requestInterface,
      name: 'Response',
    ).listen(consider);

    try {
      ({int code, Map<String, DBusValue> results})? response;
      // One budget over the whole round trip — the method call *and* the
      // `Response` it promises — because either half going quiet is the same
      // thing to the person waiting on the settings screen. Per call rather
      // than one wrapper around the whole handshake: the caller passes
      // [budget], so the step with a dialog behind it gets the bound a person
      // can answer inside and the dialogless steps get the short one.
      final inTime = await _answeredWithin(budget, name, () async {
        final reply = await client.callMethod(
          destination: _portalService,
          path: _desktopPath,
          interface: _globalShortcutsInterface,
          name: name,
          values: values,
          replySignature: DBusSignature('o'),
        );
        requestPath = reply.returnValues.single.asObjectPath();
        for (final signal in buffered) {
          consider(signal);
        }
        response = _readResponse(await answered.future);
      });
      final answer = response;
      // Two conditions, one arm: `inTime` is the fact, and the null check is
      // what narrows the local the closure assigned. A null with `inTime` true
      // cannot happen — the closure either assigns or throws — and writing it
      // this way is how that stays true without a `!`.
      if (!inTime || answer == null) {
        throw const _PortalRefusal.abandoned();
      }
      return answer;
    } on _PortalRefusal {
      rethrow;
    } on DBusMethodResponseException catch (error) {
      throw _PortalRefusal.of(_refusalFor(error));
    } on DBusReplySignatureException catch (error) {
      throw _PortalRefusal.of(_refusalFor(error));
    } on Object catch (error) {
      // Latched only when the transport is what failed: that is the case
      // [_deadConnection] exists for, and the only one where carrying on would
      // hang rather than degrade. An unclassified error on a connection that is
      // demonstrably alive costs this attempt and no other — a permanent latch
      // is a claim about the client, and one failed call is not evidence of it.
      throw _PortalRefusal.of(
        _isConnectionFailure(error)
            ? _recordDeadConnection(error)
            : _refusalFor(error),
      );
    } finally {
      // Guarded even though it cannot currently fail *into* this frame, and the
      // distinction is worth writing down because the shape looks like a hole in
      // the promise above and is not one. Cancelling sends `RemoveMatch`, which a
      // dying socket can refuse — but `DBusSignalStream` is a broadcast
      // `StreamController`, and a broadcast controller discards the future its
      // `onCancel` returns, so the refusal is reported to the enclosing zone and
      // no `try` here could ever see it (measured directly against
      // `package:dbus` 0.7.14; the suite's `RemoveMatch`-failing row observes
      // the zone error, but not that it came from *this* frame rather than from
      // `dispose()`'s two cancels, so it is not what pins this). The guard is
      // what makes this frame correct if that ever changes: `finally` sits
      // outside every catch above, so an unguarded rejection here would leave
      // `bind()` by the one route the class doc says nothing leaves by.
      //
      // That the cancel *happens at all* is a separate property, and a leak
      // rather than a throw: without it every portal call leaves a live
      // `DBusSignalStream` and its bus match rule behind, invisibly, because the
      // bind's answer is identical either way. It is pinned by counting the
      // rules the client added and removed.
      await _guard(
        'cancelling the portal request subscription',
        responses.cancel,
      );
    }
  }

  /// The portal's unique bus name, resolved immediately before each call that
  /// awaits a `Response`.
  ///
  /// A unique name (`:1.7`) rather than `org.freedesktop.portal.Desktop`,
  /// because a match rule on a well-known name is only as good as the
  /// asynchronous lookup behind it — see [_callThroughRequest].
  ///
  /// **Resolved per call rather than cached, and the round trip is what that
  /// correctness costs.** A cached unique name outlives the process that owns
  /// it: `xdg-desktop-portal` restarting — routine on a session update, and the
  /// case the rebind path a few methods down exists for — brings the well-known
  /// name back on a *new* unique name, and a match rule still naming the old one
  /// matches nothing that will ever be remapped, because `package:dbus` keys its
  /// name-owner cache by well-known names and a rule holding a dead unique name
  /// is tracked by nobody. Measured, with the portal restarted between two
  /// binds: the second `CreateSession` reached the new portal, its `Response`
  /// was dropped, and `bind()` never resolved — and since [bind] chains on
  /// [_queue], every later bind was parked behind it too.
  ///
  /// Resolving here closes that without the timeout the intent rules out. The
  /// lookup is one round trip ahead of the call, so either the portal that
  /// answered it is the one that answers the call, or the call itself fails and
  /// becomes AD-12's value; a portal that dies in the gap emits no `Response`
  /// for anybody, which is the separately filed never-answering case and not
  /// this one. The subscription is still created after this returns and before
  /// the call goes out, which is all row A15 asks.
  Future<String> _portalSender(DBusClient client) async {
    String? owner;
    final bool answered;
    try {
      // Bounded: there is no dialog behind a name-owner lookup, and it is the
      // first call a rebind makes, so a bus that stops answering here would
      // hang the settings screen before the portal was even asked anything.
      answered = await _answeredWithin(
        _requestBudget,
        _nameOwnerCall,
        () async {
          owner = await client.getNameOwner(_portalService);
        },
      );
    } on Object catch (error) {
      // The same reduction every other call gets, because this one is a call
      // too — and it is now the first one a rebind makes, so leaving it
      // untranslated would put a raw vendor error where AD-12 requires a value.
      throw _PortalRefusal.of(
        _isConnectionFailure(error)
            ? _recordDeadConnection(error)
            : _refusalFor(error),
      );
    }
    if (!answered) {
      // Nothing is in flight that a user is answering, and nothing was closed:
      // the lookup is simply left to land wherever it lands.
      throw const _PortalRefusal.abandoned();
    }
    // Read into a local before it is narrowed: the assignment happens inside
    // the closure above, so the field-like promotion the old direct `await`
    // allowed no longer applies — and this codebase does not silence that with
    // `!`.
    final resolved = owner;
    if (resolved == null) {
      // Nobody owns the portal name. The same absence a `CreateSession` to an
      // unowned destination reports, learned one step earlier, so it gets the
      // same sentence rather than a second vocabulary for one condition.
      // Nobody owns the portal name, so there is nothing on this desktop to
      // ask — the same absence, and the same cause, that [_refusalFor] gives
      // the `ServiceUnknown` arm one step later.
      throw const _PortalRefusal(
        cause: HotkeyUnavailableCause.noBackend,
        message: _noDesktopPortal,
      );
    }
    return resolved;
  }

  /// AD-11 step 4. One subscription each, established after the first
  /// successful `BindShortcuts` and never rebuilt.
  ///
  /// Both filter on the *current* session handle, read at delivery time, so a
  /// rebind that replaces the session needs no new subscription — and an
  /// abandoned rebind keeps delivering for the session that is genuinely still
  /// live.
  ///
  /// Both also filter on **sender**, unlike the Request stream, and here that
  /// is a security property rather than tidiness. `Activated` is the whole path
  /// from a key press to a panel that reads the clipboard, so without a sender
  /// rule any peer on the session bus could raise it by emitting one forged
  /// signal. The race that forced the Request stream to go without does not
  /// exist on this path: these streams are created after `BindShortcuts` has
  /// already returned, with nothing of ours in flight, so `package:dbus` has all
  /// the time it needs to resolve the portal's name to its unique one before the
  /// first real signal arrives.
  void _listenForShortcutSignals(DBusClient client) {
    _activated ??= DBusSignalStream(
      client,
      sender: _portalService,
      path: _desktopPath,
      interface: _globalShortcutsInterface,
      name: 'Activated',
    ).listen(_onActivated);
    _shortcutsChanged ??= DBusSignalStream(
      client,
      sender: _portalService,
      path: _desktopPath,
      interface: _globalShortcutsInterface,
      name: 'ShortcutsChanged',
    ).listen(_onShortcutsChanged);
  }

  /// CAP-1's whole path from a key press to the panel, and AD-8's budget is why
  /// it allocates nothing, loads nothing and awaits nothing.
  void _onActivated(DBusSignal signal) {
    // Kept, correct, and **unreachable** — recorded rather than left looking
    // pinned. Measured: deleting this line fails zero tests, and it cannot be
    // made to fail one. `dispose()` sets `_disposed` and clears `_session` in
    // the same synchronous run, before its first await, so a press landing
    // anywhere in the teardown window is already rejected by the session filter
    // below; and by the time `_activations` is closed the bus client is closed
    // too, so no signal is delivered at all. A row drives the window and holds
    // either way. This stays as the cheap structural belt on CAP-1's path to a
    // clipboard-reading panel, and it becomes live if either of those two
    // orderings ever changes.
    if (_disposed || _activations.isClosed) {
      return;
    }
    if (signal.values.length < 2) {
      return;
    }
    final session = signal.values[0];
    if (session is! DBusObjectPath || session != _session) {
      return;
    }
    final id = signal.values[1];
    if (id is! DBusString || id.value != shortcutId) {
      return;
    }
    _activations.add(null);
  }

  /// AD-11's subscription, and — since the port gained `bindingChanges` — the
  /// path from a rebind the user made in the compositor's own settings to the
  /// surface that renders it (AD-10).
  ///
  /// Three branches, three different things known, three different answers. The
  /// id is still held: the compositor rebound it, so [HotkeyBound] goes up with
  /// `effective: null` — the portal sends only a localized
  /// `trigger_description` and nothing here parses it back into a combination,
  /// for the reason the class doc gives. The id is gone: [HotkeyUnavailable],
  /// because AD-12's degradation is exactly what has happened. The payload could
  /// not be read: **nothing is emitted at all**, because the one thing this
  /// branch knows is that it knows nothing, and either value would be a claim
  /// about compositor state that was never established (AGENTS.md §1).
  void _onShortcutsChanged(DBusSignal signal) {
    if (_disposed || signal.values.length < 2) {
      return;
    }
    final session = signal.values[0];
    if (session is! DBusObjectPath || session != _session) {
      return;
    }
    final shortcuts = _shortcutsIn(signal.values[1]);
    if (shortcuts == null) {
      // Deliberately not reported as a shortcut that was dropped. This branch
      // knows one thing — that the payload could not be read — and saying
      // anything about what the compositor now holds would be stating a fact
      // about its state that was never established (AGENTS.md §1).
      _log(
        () => _logger.error(
          'a ShortcutsChanged signal arrived in a shape this build cannot '
          'read, so what the compositor now holds is unknown',
        ),
      );
      return;
    }
    if (!shortcuts.containsKey(shortcutId)) {
      if (_status?.outcome is! HotkeyBound &&
          _status?.outcome is! HotkeyRetained) {
        // **A revocation needs something to have been in effect.** The session
        // is tracked from the moment a `BindShortcuts` is abandoned (D-17),
        // where nothing was granted at all — so a compositor announcing this
        // session's shortcuts before granting ours would otherwise be reported
        // as "your desktop took this shortcut away" for a shortcut the user
        // never had. This branch knows only what it already knew, so it says
        // nothing upward, on the same reasoning as the unreadable payload
        // above: the loss it would report was never established.
        _log(
          () => _logger.info(
            'the compositor reports this session holds no global shortcut, '
            'which is what this app already had, so nothing is reported as '
            'lost',
          ),
        );
        return;
      }
      // Nothing is in effect, so there is no shortcut for a description to be
      // about. Cleared here rather than left for [_recordStatus] to ignore:
      // an abandoned rebind later on reports the shortcut still in effect and
      // reads this field for its wording, and by then this one is long gone.
      _backendDescription = null;
      _log(
        () => _logger.info(
          'the compositor reports this session no longer holds the global '
          'shortcut',
        ),
      );
      _pushBindingChange(
        const HotkeyUnavailable(
          // **The case HOTKEY-08's enum exists to distinguish**, and the only
          // site in this codebase that produces it. A shortcut that was
          // genuinely in effect has been taken away: the user had one and no
          // longer does, which is a different thing from a bind that never
          // took. D-08 forbids re-claiming it — the user re-applies when they
          // want it back — and D-09 forbids interrupting them to say so.
          //
          // Reachable only from this method, whose subscription is
          // sender-filtered on the portal's resolved unique name. That filter
          // is what stops any session-bus peer forging a revocation, and it is
          // load-bearing precisely because this value is now machine-readable.
          cause: HotkeyUnavailableCause.revoked,
          message:
              'your desktop no longer holds this shortcut, so the hotkey is '
              'inactive — the tray menu still opens the panel',
        ),
      );
      return;
    }
    // The wording from the signal that just arrived, which is the compositor
    // telling us what it now holds — the second of the three places the read-back
    // reaches this adapter. D-08 governs what is *not* done here: the loss case
    // above reflects the loss and this case reflects the change, and neither
    // attempts a re-claim.
    _backendDescription = _logTriggerDescription(
      shortcuts[shortcutId],
      changed: true,
    );
    _pushBindingChange(
      const HotkeyBound(
        HotkeyRegistration(
          effective: null,
          authority: BindingAuthority.compositor,
        ),
      ),
    );
  }

  /// Publishes a backend-initiated change, unless teardown has already closed
  /// the stream.
  ///
  /// The `isClosed` check is the same cheap structural belt [_onActivated]
  /// carries and is unreachable for the same reason — `dispose()` sets
  /// `_disposed` before its first await and [_onShortcutsChanged] returns on it —
  /// but adding to a closed controller throws, and this one runs inside a stream
  /// callback where a throw becomes an unhandled zone error.
  void _pushBindingChange(HotkeyBindOutcome outcome) {
    // Recorded before the stream is consulted, and unconditionally: a consumer
    // that arrives later reads [current] rather than this stream, so a change
    // must land in the field even on the turn where nobody is listening — which
    // is the ordinary case for a tray daemon.
    _backendChanges += 1;
    _recordStatus(outcome);
    if (_bindingChanges.isClosed) {
      return;
    }
    _bindingChanges.add(outcome);
  }

  /// Records [outcome] as what [current] answers, pairing it with the
  /// compositor's own wording, and passes it through.
  ///
  /// **Only a held registration carries a description**, which is what keeps the
  /// pair honest without a second rule at every call site: a `HotkeyUnavailable`
  /// says nothing is in effect, and wording for a shortcut nobody holds
  /// describes nothing. The corollary is the one that matters — the abandoned
  /// rebind, which answers `HotkeyRetained` for the *previous* shortcut, picks up
  /// the previous description here, because that is what [_backendDescription]
  /// still holds and what is still in effect.
  HotkeyBindOutcome _recordStatus(HotkeyBindOutcome outcome) {
    _status = HotkeyStatus(
      outcome: outcome,
      backendDescription: switch (outcome) {
        HotkeyBound() || HotkeyRetained() => _backendDescription,
        HotkeyUnavailable() => null,
      },
    );
    return outcome;
  }

  /// Records a [bind] answer, unless the compositor has said something newer
  /// while that bind was in flight.
  ///
  /// [issuedAt] is [_backendChanges] as it stood when the bind was issued. A
  /// higher value now means a `ShortcutsChanged` landed in between — a rebind
  /// the user made in their desktop's own settings, or a revocation — and that
  /// is the newer fact. Overwriting it with this call's answer would put the
  /// shortcut the app asked for in front of the one the compositor last
  /// reported, on the one member a late-mounting settings screen reads.
  ///
  /// The answer still goes back to the caller either way: what a bind resolved
  /// to is that caller's business, and only [current] is a claim about *now*.
  HotkeyBindOutcome _recordBindAnswer(HotkeyBindOutcome outcome, int issuedAt) {
    if (_backendChanges != issuedAt) {
      _log(
        () => _logger.info(
          'the compositor reported a change while this bind was in flight, so '
          'the change is what the surface keeps rather than this answer',
        ),
      );
      return outcome;
    }
    return _recordStatus(outcome);
  }

  /// Lets go of the live session before a new one is created, and returns the
  /// outcome to report instead when that could not be done — null when the
  /// caller should go on and create.
  ///
  /// A whole new session is the only way to rebind: the portal documents that
  /// "an application can only attempt bind shortcuts of a session once", so
  /// CAP-12's rebind cannot re-issue `BindShortcuts`. This is the Wayland
  /// analogue of X11's release-then-grab, and it fails the same way — a refused
  /// Close **abandons** the rebind rather than creating a second session,
  /// because two live sessions would leave the compositor holding two shortcuts
  /// with only one of them filtered in, and the user's existing shortcut still
  /// works.
  Future<HotkeyBindOutcome?> _closeSessionBeforeRebinding(
    DBusClient client,
  ) async {
    final session = _session;
    if (session == null) {
      return null;
    }
    // Cleared before the await, and put back only if the Close was refused: see
    // [_session] for why two Closes for one session must not be possible.
    _session = null;
    try {
      await _closeSession(client, session);
    } on DBusUnknownObjectException catch (error) {
      // Not a refusal, and the opposite of one: the portal is telling us this
      // session no longer exists. `xdg-desktop-portal` restarting — routine on
      // a session update — takes every session with it, and the shortcut goes
      // too. Treating it as "the previous shortcut is still in effect" would
      // restore a dead handle, answer `HotkeyBound` for a shortcut bound to
      // nothing, and keep answering it on every later rebind, since the arm is
      // reached identically each time. That is the misreport the class doc
      // opens against. So the rebind goes ahead: there is nothing left to close.
      _logSessionAlreadyGone(error);
    } on DBusServiceUnknownException catch (error) {
      // The portal itself is gone, and its sessions with it. Same answer — and
      // the `CreateSession` that follows is what turns a portal that is really
      // absent into AD-12's visible value rather than a silent claim of success.
      _logSessionAlreadyGone(error);
    } on Object catch (error) {
      if (_isConnectionFailure(error)) {
        // The transport failing, not the portal refusing — and the difference is
        // the whole answer. "The previous shortcut is still in effect" is a
        // claim about a live session behind a live connection, and there is
        // neither: measured, with the bus gone this arm answered `HotkeyBound`
        // having put **zero** calls on the wire, and because the arm is reached
        // identically each time it would go on answering it for the life of the
        // daemon, while `SettingsController` persisted a binding nothing holds
        // and the tray kept reporting hotkeys available. That is precisely the
        // misreport this class's doc opens against. So it gets the same
        // reduction `_registerApplicationIdOnce` and [_callThroughRequest]
        // already make, and `_session` stays cleared, because nothing is live.
        // Not `revoked`, though it is reached while letting go of a live
        // session: the compositor did not take anything away, the transport
        // under the request died. `_recordDeadConnection` classifies it as the
        // absent backend it is.
        final refusal = _recordDeadConnection(error);
        return HotkeyUnavailable(
          cause: refusal.cause,
          message: refusal.message,
        );
      }
      _log(
        () => _logger.error(
          'the previous global shortcuts session could not be closed, so the '
          'rebind was abandoned and the previous shortcut is still in effect',
          context: _errorContext(error),
        ),
      );
      if (_disposed) {
        // The sibling awaits all re-check, and this one has to as well: without
        // it a teardown landing here answers "the previous shortcut is still in
        // effect" about a session whose bus client teardown has already closed.
        return _shutDownDuringBind();
      }
      // The Close was refused, so that session is still live and still this
      // adapter's — including for the `Activated` filter.
      _session = session;
      // AD-10: what is reported is what is actually in effect, and the old
      // session still is. `effective` stays null for the reason the class doc
      // gives — the portal never told us the combination.
      //
      // **The wording that goes with it is the previous one**, which is why
      // nothing on the way into a rebind clears [_backendDescription]: the
      // shortcut still in effect is the previous shortcut, and describing it
      // with wording for the combination this rebind was reaching for would
      // name a shortcut the compositor never granted.
      return const HotkeyRetained(
        HotkeyRegistration(
          effective: null,
          authority: BindingAuthority.compositor,
        ),
      );
    }
    return null;
  }

  /// One info line for a session the portal says is already gone — a fact about
  /// the portal, not a failure of ours, so it is not an error.
  void _logSessionAlreadyGone(Object error) {
    _log(
      () => _logger.info(
        'the previous global shortcuts session no longer exists, so the rebind '
        'creates a new one rather than reporting the old shortcut as live',
        context: _errorContext(error),
      ),
    );
  }

  Future<void> _closeSession(DBusClient client, DBusObjectPath session) async {
    await client.callMethod(
      destination: _portalService,
      path: session,
      interface: _sessionInterface,
      name: 'Close',
      replySignature: DBusSignature(''),
    );
  }

  /// Closes the portal session, cancels both subscriptions, closes the bus
  /// client and closes [activations]. Idempotent, and never throws: it runs on
  /// the shutdown path (AD-4).
  ///
  /// Every step is independent, because the point is to leave nothing behind: a
  /// Close the portal refuses must not stop the client being closed.
  ///
  /// Closing the client is the load-bearing step rather than hygiene.
  /// `package:dbus` documents that an unclosed client can stop the Dart process
  /// terminating — which on this branch would be a daemon that never exits — and
  /// it is also what ends the portal session on the compositor's side.
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final client = _client;
    // Read and cleared before anything is awaited, so a rebind's Close that is
    // still in flight is the only one there ever is; see [_session].
    final session = _session;
    _session = null;
    if (client != null && session != null) {
      await _guard(
        'closing the global shortcuts portal session',
        // Bounded, and that is the difference between a daemon that exits and
        // one that does not. `_guard` reduces a teardown *throw* to a log line
        // but can do nothing about a teardown that never returns, and
        // `package:dbus` never completes a call whose socket died under it
        // (measured: with the bus killed while this Close was in flight,
        // `dispose()` never resolved). `DaemonLifecycle` awaits this step in
        // sequence, so everything after it — the history database, the config
        // store, the AD-14 lock — would never run and the process would never
        // reach `exit`.
        () => _closeSession(client, session).timeout(_teardownBudget),
      );
    }
    // Before the client: cancelling a signal stream sends `RemoveMatch`, which
    // needs a socket that is still open.
    await _guard(
      'cancelling the portal shortcut activation subscription',
      () async => _activated?.cancel(),
    );
    await _guard(
      'cancelling the portal shortcuts-changed subscription',
      () async => _shortcutsChanged?.cancel(),
    );
    if (client != null) {
      await _guard('closing the session bus client', client.close);
    }
    await _guard('closing the hotkey activation stream', _activations.close);
    await _guard(
      'closing the hotkey binding-change stream',
      _bindingChanges.close,
    );
  }

  /// What a [bind] interrupted by teardown reports. Not a refusal by the
  /// portal, and worded so nobody goes looking for one.
  HotkeyBindOutcome _shutDownDuringBind() {
    return const HotkeyUnavailable(
      // Nothing is left to ask, so nothing the user picks can be granted —
      // which is what this sentence already said and what `noBackend` means.
      cause: HotkeyUnavailableCause.noBackend,
      message:
          'the hotkey backend has already been shut down, so no global '
          'shortcut is registered — the tray menu still opens the panel',
    );
  }

  /// The `(u response, a{sv} results)` a Request's `Response` carries.
  ({int code, Map<String, DBusValue> results}) _readResponse(
    DBusSignal signal,
  ) {
    if (signal.values.length < 2) {
      throw const _PortalRefusal(
        cause: _malformedReplyCause,
        message: _malformedReply,
      );
    }
    final code = signal.values[0];
    final results = signal.values[1];
    // The signature is checked as well as the type: `mapStringVariant` throws on
    // a dict whose values are not variants, and a portal that sent `a{ss}` would
    // otherwise turn a malformed reply into a cast error crossing the port.
    if (code is! DBusUint32 ||
        results is! DBusDict ||
        results.signature.value != _vardict) {
      throw const _PortalRefusal(
        cause: _malformedReplyCause,
        message: _malformedReply,
      );
    }
    return (code: code.value, results: results.mapStringVariant());
  }

  /// The `a(sa{sv})` shortcut list a Response or a `ShortcutsChanged` carries,
  /// as id to its own vardict — or **null when there is no readable list at
  /// all**.
  ///
  /// The distinction is the point. An empty map means the portal told us which
  /// shortcuts it holds and ours was not among them, which is the documented
  /// discard; null means it told us nothing this build could read. Collapsing
  /// the two would make a malformed signal report a fact about compositor state
  /// that was never established.
  Map<String, Map<String, DBusValue>>? _shortcutsIn(DBusValue? value) {
    if (value is! DBusArray || value.childSignature.value != _shortcutEntry) {
      return null;
    }
    final shortcuts = <String, Map<String, DBusValue>>{};
    for (final entry in value.children) {
      if (entry is! DBusStruct || entry.children.length < 2) {
        continue;
      }
      final id = entry.children[0];
      final properties = entry.children[1];
      if (id is! DBusString ||
          properties is! DBusDict ||
          properties.signature.value != _vardict) {
        continue;
      }
      shortcuts[id.value] = properties.mapStringVariant();
    }
    return shortcuts;
  }

  /// Records what the compositor says the shortcut is — user-readable text,
  /// never parsed — and **returns it**, because it is also what the settings
  /// screen shows.
  ///
  /// It used to only log. That left AD-10's read-back happening and its result
  /// reaching nobody: the one field the portal sends about the shortcut in
  /// force went to stderr while the screen said the combination could not be
  /// reported. Returning it is the whole of what changed; the extraction is
  /// unmoved, and the log line stays because it is still the only record of a
  /// rebind in a daemon that shows the user nothing (D-09).
  String? _logTriggerDescription(
    Map<String, DBusValue>? properties, {
    bool changed = false,
  }) {
    final description = _descriptionIn(properties);
    _log(
      () => _logger.info(
        changed
            ? 'the compositor changed the global shortcut for this session'
            : 'the compositor bound the global shortcut',
        context: {
          // Not parsed into a binding on purpose: it is localized,
          // backend-specific, user-readable text, and turning it back into a
          // combination would be a prediction of vendor behaviour that
          // misreports silently.
          'trigger_description': description,
        },
      ),
    );
    return description;
  }

  /// The `trigger_description` in one shortcut's vardict, or null when the
  /// portal sent none or sent something that is not a string.
  ///
  /// Absence is not a failure: the property is documented but a backend is free
  /// to omit it, and a shortcut that fires without a description is still a
  /// working shortcut. What must never happen is a description standing in for
  /// a combination, or a combination standing in for one.
  String? _descriptionIn(Map<String, DBusValue>? properties) {
    final description = properties?['trigger_description'];
    return description is DBusString ? description.value : null;
  }

  /// Latches [error] as a connection that will never work again and returns the
  /// refusal to report — see [_deadConnection].
  _Refusal _recordDeadConnection(Object error) {
    final refusal = _refusalFor(error);
    _deadConnection = refusal;
    return refusal;
  }

  /// Translates a `package:dbus` failure into the sentence AD-12 requires — one
  /// a user can act on, naming the way in that still works — and the cause
  /// HOTKEY-08 requires beside it.
  ///
  /// The classified cases are the ones that tell the user something specific;
  /// they are not logged, because the message *is* the diagnosis and the
  /// composition root already logs it. Only the unclassified case logs, where
  /// the error type is the only clue there is.
  ///
  /// **Every classified arm is [HotkeyUnavailableCause.noBackend], and that is
  /// a property of which errors are classified rather than a blanket
  /// assignment**: each one detects an absent bus, a dead transport, or a
  /// portal that is not there — conditions under which no combination the user
  /// picks can reach anything. The single arm where a portal demonstrably
  /// answered is [_unclassified], and it is the only one that is not.
  _Refusal _refusalFor(Object error) {
    return switch (error) {
      // No bus socket at all — measured as what `DBusClient.session()` does on a
      // session with neither DBUS_SESSION_BUS_ADDRESS nor /run/user/<uid>/bus.
      SocketException() => (
        cause: HotkeyUnavailableCause.noBackend,
        message:
            'no session bus could be reached, so no global shortcut is '
            'registered — the tray menu still opens the panel',
      ),
      // The transport failing after it had once worked: a bus that went away
      // under a live client, or a client already closed. [_isConnectionFailure]
      // groups these with the socket case, and [_recordDeadConnection] latches
      // whatever refusal comes back here — so without their own arm the user
      // reads [_unclassified]'s "the desktop portal refused the global shortcut
      // request" for the life of the daemon, and goes hunting for a permission
      // they were never asked for.
      //
      // Not [HotkeyUnavailableCause.revoked], which is the near-miss worth
      // naming: nothing was taken away here, the connection carrying the request
      // died. `revoked` is reserved for a compositor saying it no longer holds a
      // shortcut it did hold, which arrives on [_onShortcutsChanged] alone.
      OSError() || DBusClosedException() => (
        cause: HotkeyUnavailableCause.noBackend,
        message:
            'the session bus connection was lost, so no global shortcut is '
            'registered — the tray menu still opens the panel',
      ),
      DBusServiceUnknownException() || DBusUnknownObjectException() => (
        cause: HotkeyUnavailableCause.noBackend,
        message: _noDesktopPortal,
      ),
      // The wlroots case: Sway, Hyprland and Niri ship no GlobalShortcuts
      // implementation. Both error names reach here because which one a
      // backend-less portal answers with is not settled. AD-12's headline case,
      // and the one `noBackend` was named for.
      DBusUnknownMethodException() || DBusUnknownInterfaceException() => (
        cause: HotkeyUnavailableCause.noBackend,
        message:
            'this compositor provides no global shortcuts portal, so the '
            'hotkey is inactive — the tray menu still opens the panel',
      ),
      _ => _unclassified(error),
    };
  }

  /// A portal that **answered**, in a way this build did not classify.
  ///
  /// [HotkeyUnavailableCause.keyRefused] rather than `noBackend`, and the
  /// difference matters to the user: something on the other end replied, so
  /// telling them this desktop has no global shortcuts would be false and would
  /// talk them out of a retry that may well work. What is true is that a live
  /// backend did not grant the request; the sentence carries the rest.
  _Refusal _unclassified(Object error) {
    _log(
      () => _logger.error(
        'the global shortcuts portal handshake failed',
        context: _errorContext(error),
      ),
    );
    return (
      cause: HotkeyUnavailableCause.keyRefused,
      message:
          'the desktop portal refused the global shortcut request, so the '
          'hotkey is inactive — the tray menu still opens the panel',
    );
  }

  /// True when [error] is the transport failing rather than a peer answering.
  ///
  /// The distinction decides whether a failure costs one attempt or all of them:
  /// only these leave the `package:dbus` client in the state [_deadConnection]
  /// exists for, where every later call waits on a completer nobody completes.
  static bool _isConnectionFailure(Object error) =>
      error is SocketException ||
      error is OSError ||
      error is DBusClosedException;

  String _newToken() {
    _tokenSequence += 1;
    return 'hgc_${_tokenSequence}_'
        '${_random.nextInt(_tokenRange).toRadixString(36)}';
  }

  /// Issues one portal round trip under [budget], and says whether the portal
  /// answered (D-17).
  ///
  /// The same shape, and the same distinction, as the panel adapter's
  /// `_answered`: reported through `onTimeout` and a local flag rather than by
  /// catching the error `timeout` raises when no `onTimeout` is supplied,
  /// because a seam is free to have deadlines of its own, and one of *those*
  /// expiring is the portal refusing the call, not this policy firing — a
  /// `catch` cannot tell the two apart, and a flag set only by this bound can.
  /// A refusal is not this method's business either — the
  /// rejection propagates to the caller, which already turns it into AD-12's
  /// value. What this bounds is the call that never settles at all, which no
  /// `catch` can reach.
  ///
  /// **It abandons and never cancels, and that is the rule the whole feature
  /// turns on.** The portal shows the user a dialog on `BindShortcuts`, and
  /// sending a `Close` on expiry would take that dialog off the screen — or
  /// worse, leave it up over a request that no longer exists, so the Allow they
  /// click lands nowhere. So nothing is sent: the wait stops, the caller
  /// reports what is actually in effect, and a late answer is still the
  /// compositor's to grant.
  Future<bool> _answeredWithin(
    Duration budget,
    String call,
    Future<void> Function() issue,
  ) async {
    var answered = true;
    // Re-wrapped rather than bounded directly, and this is a trap rather than a
    // ceremony: `timeout` reads its type argument from the *instance*, not from
    // the static type here. A caller handing over a `Future<DBusMethodResponse>`
    // widened to `Future<void>` — which the subtype rule allows — gets a
    // `Future<DBusMethodResponse>.timeout`, whose `onTimeout` must return one of
    // those, and the callback below returning nothing then throws a `TypeError`
    // *inside the call*. Measured: it surfaced as the advisory Register step
    // logging an unreadable-reply line on a perfectly healthy portal. An async
    // wrapper makes the receiver genuinely `Future<void>`, so the bound cannot
    // depend on what a call site happens to return.
    Future<void> awaited() async => issue();
    await awaited().timeout(
      budget,
      onTimeout: () {
        answered = false;
      },
    );
    if (!answered) {
      _log(
        () => _logger.error(
          'the desktop portal did not answer $call within '
          '${budget.inMilliseconds} ms; the wait was abandoned so the settings '
          'screen is not left hanging, and nothing was cancelled in case a '
          'dialog is still on screen',
          context: {'call': call, 'timeout_ms': budget.inMilliseconds},
        ),
      );
    }
    return answered;
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

/// A portal step that could not produce a binding, on its way to becoming a
/// [HotkeyUnavailable].
///
/// Internal control flow that never leaves the file: [WaylandPortalGlobalHotkey]
/// catches it in exactly one place and returns the value AD-12 requires, so no
/// vendor error and no exception of any kind crosses the port boundary. It is a
/// throw rather than a nullable return because the handshake is four steps deep
/// with two awaits each, and threading an optional outcome back out of every one
/// of them would bury the sequence AD-11 makes an invariant under error
/// plumbing.
final class _PortalRefusal implements Exception {
  /// The ordinary case: the portal answered and said no.
  ///
  /// [abandoned] is not a parameter here, and deliberately not: a refusal is
  /// what a portal *said*, and abandoning is what this adapter *did*, so the
  /// one named constructor below is the only way to build the second — nobody
  /// can pass `abandoned: true` beside a sentence about a refusal.
  const _PortalRefusal({required this.cause, required this.message})
    : abandoned = false;

  /// Rebuilds a refusal from a classified [_Refusal], for the arms that get
  /// both halves from [WaylandPortalGlobalHotkey._refusalFor] at once.
  _PortalRefusal.of(_Refusal reason)
    : cause = reason.cause,
      message = reason.message,
      abandoned = false;

  /// A step this adapter stopped waiting on (D-17), as distinct from one the
  /// portal refused.
  ///
  /// [HotkeyUnavailableCause.keyRefused] rather than `noBackend`, on the same
  /// reasoning [WaylandPortalGlobalHotkey._unclassified] gives: something is
  /// there — the name resolved, or the session opened — so telling the user
  /// this desktop has no global shortcuts would be false and would talk them
  /// out of a retry that may well work. What is true is that nothing has been
  /// granted *yet*.
  const _PortalRefusal.abandoned()
    : cause = HotkeyUnavailableCause.keyRefused,
      message = _portalDidNotAnswer,
      abandoned = true;

  /// Which of D-06's three things this is, carried out of the four-deep
  /// handshake rather than left to be inferred from [message] at the top.
  ///
  /// Without it the cause would have to be recovered by matching on the
  /// sentence in [WaylandPortalGlobalHotkey._bind]'s single catch — which is
  /// the prose-parsing HOTKEY-08 exists to remove, one layer lower down.
  final HotkeyUnavailableCause cause;

  /// Already in AD-12's terms — a sentence for a user, naming the tray.
  final String message;

  /// True when the wait was abandoned rather than answered, which decides one
  /// thing and only one: whether [WaylandPortalGlobalHotkey._bind] may close
  /// the session it has just created.
  ///
  /// It may not. A `BindShortcuts` this adapter stopped waiting on is a dialog
  /// that may still be on the user's screen, and closing its session would
  /// withdraw the request they are being asked to approve. Every other refusal
  /// arrives *after* the portal has answered, where there is no dialog left to
  /// withdraw and an unclosed session is an orphan on the compositor.
  final bool abandoned;
}

/// A refusal reduced to what AD-12's value needs: the cause a consumer branches
/// on, and the sentence the user reads.
///
/// A record rather than a class because it is a two-field tuple with no
/// behaviour, which is what this codebase reaches for records for. It exists so
/// the cause and the message are chosen **in the same place** — a separate
/// `_causeFor` switch beside [WaylandPortalGlobalHotkey._refusalFor] would be
/// two switches over one set of error types, free to disagree the day either
/// gains an arm.
typedef _Refusal = ({HotkeyUnavailableCause cause, String message});

/// The only part of a caught error that is safe to put in a log line — see the
/// [Logger] port's doc, and the canonical note in `correction_controller.dart`.
Map<String, Object?> _errorContext(Object error) {
  return {'error_type': error.runtimeType.toString()};
}

/// `XDG_DESKTOP_PORTAL_RESPONSE_SUCCESS`. 1 is the user cancelling, 2 is any
/// other failure the backend reports.
const int _granted = 0;

/// The signature every `a{sv}` the portal sends must carry.
const String _vardict = 'a{sv}';

/// The element signature of the portal's shortcut lists.
const String _shortcutEntry = '(sa{sv})';

const String _noDesktopPortal =
    'no desktop portal is running on this session, so the hotkey is inactive — '
    'the tray menu still opens the panel';

/// What a step this adapter stopped waiting on tells the user (D-17).
///
/// It says plainly that nothing was cancelled, because on the `BindShortcuts`
/// path that is the difference between a dialog they can still answer and one
/// they are about to click Allow on for a request that no longer exists. And it
/// does not claim the shortcut is dead: the compositor may still grant it, in
/// which case the press starts working and `ShortcutsChanged` says so.
const String _portalDidNotAnswer =
    'the desktop portal did not answer in time, so this app stopped waiting '
    'rather than leaving the settings screen hanging — nothing was cancelled, '
    'so a dialog still on screen can still be granted; until it is, the hotkey '
    'is inactive and the tray menu still opens the panel';

const String _malformedReply =
    'the desktop portal answered in a shape this build cannot read, so no '
    'global shortcut is registered — the tray menu still opens the panel';

/// The cause every [_malformedReply] refusal carries, kept beside the sentence
/// so the five sites that throw it cannot drift apart.
///
/// **A portal answered**, which is the whole of what decides this: it replied in
/// a shape this build could not read, so the mechanism demonstrably exists and
/// [HotkeyUnavailableCause.noBackend] would be false. `keyRefused` is the
/// honest remainder — it does not tell the user to give up, and the sentence
/// says plainly that the reply, not the combination, was the problem.
const HotkeyUnavailableCause _malformedReplyCause =
    HotkeyUnavailableCause.keyRefused;

const String _unusableBusAddress =
    'the session bus address this session advertises is not one this build can '
    'read, so no global shortcut is registered — the tray menu still opens the '
    'panel';

const String _portalService = 'org.freedesktop.portal.Desktop';
final DBusObjectPath _desktopPath = DBusObjectPath(
  '/org/freedesktop/portal/desktop',
);
const String _globalShortcutsInterface =
    'org.freedesktop.portal.GlobalShortcuts';
const String _requestInterface = 'org.freedesktop.portal.Request';
const String _sessionInterface = 'org.freedesktop.portal.Session';

const String _registryService = 'org.freedesktop.host.portal';
final DBusObjectPath _registryPath = DBusObjectPath(
  '/org/freedesktop/host/portal/registry',
);
const String _registryInterface = 'org.freedesktop.host.portal.Registry';

/// Wide enough that two processes are very unlikely to pick the same suffix,
/// and inside `Random.nextInt`'s domain.
const int _tokenRange = 1 << 30;

/// How much longer the one step with a dialog behind it may take than a
/// dialogless one — see [WaylandPortalGlobalHotkey._dialogBudget].
///
/// A factor rather than a second duration, so the injected budget stays the
/// only number this file's waits are measured in and the relationship between
/// the two is stated instead of implied. Twelve is chosen for what it buys at
/// the shipped budget: a minute is comfortably longer than anyone needs to read
/// one dialog and click a button, and short enough that a settings screen still
/// answers rather than hanging.
const int _dialogBudgetFactor = 12;

/// The two bounded calls that are not routed through a Request object, named so
/// the log line and the [Logger] context agree with what is on the bus.
const String _nameOwnerCall = 'GetNameOwner';
const String _registerCall = 'Registry.Register';

/// How long a `Session.Close` nobody is waiting on gets before it is given up
/// on.
///
/// **Spent on the three hygiene Closes, and for a narrower reason than the
/// bind steps' own budget.** It began as teardown's alone; the two `_bind`
/// failure arms that tidy up a session whose bind did not complete take it too,
/// because they are the same call with the same question behind it — nobody is
/// waiting on the answer, the portal has already answered or has already gone,
/// and a Close that never settles there parks `changeHotkey` short of its
/// terminal state and disables the settings surface permanently. The fourth
/// Close, `_closeSessionBeforeRebinding`'s, is deliberately **not** bounded:
/// [_session] requires at most one Close in flight per session, and restoring
/// `_session` after abandoning one that may still land would let `dispose()`
/// send a second.
///
/// **Nothing is cancelled by spending it, and that rule is unchanged.** This
/// paragraph used to say the bind path had no timeout by intent — that AD-11
/// makes a portal dialog the user must answer normal, and cancelling one out
/// from under them would be worse than waiting. D-17 overrides the conclusion: a
/// settings screen that hangs with no way out is worse still, so the bind path
/// is bounded too. But the old reason was right about what it was protecting,
/// and it is carried into the new rule rather than dropped: every bound wait
/// here abandons and sends **nothing**, so a dialog the user is reading is never
/// withdrawn, and the one step with a dialog behind it waits twelve times longer
/// than the dialogless ones. See `_answeredWithin`, `_dialogBudget`, and the arm
/// in `_bind` that declines to close an abandoned session at all.
///
/// This budget stays separate from the bind steps' because it answers a
/// different question. There the wait is for something a person may be doing;
/// here nobody is waiting for the answer at all — on teardown the worse failure
/// is a daemon that cannot exit, and closing the client is itself what ends the
/// session, while on the two `_bind` arms the session is already unusable
/// whatever the portal says. So it is deliberately shorter, and it is authored
/// here rather than injected because none of the three spends it on a person's
/// behalf: teardown's is inside a step count the composition root already argues
/// about against its supervisor's stop grace, and the other two are hygiene on a
/// bind that has already failed.
const Duration _teardownBudget = Duration(seconds: 2);
