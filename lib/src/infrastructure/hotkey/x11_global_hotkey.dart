import 'dart:async';

import '../../domain/hotkey/global_hotkey.dart';
import '../../domain/hotkey/hotkey_bind_outcome.dart';
import '../../domain/hotkey/hotkey_binding.dart';
import '../../domain/hotkey/hotkey_status.dart';
import '../../domain/logger.dart';
import 'hotkey_grab.dart';
import 'hotkey_key_catalogue.dart';
import 'hotkey_registrar.dart';

/// The X11 half of AD-9's two adapters, over a real X11 passive key grab.
///
/// AD-9 requires the *selection* to be real from the composition root onward:
/// exactly one adapter is constructed at startup and there is no runtime
/// switch. The grab itself now sits behind [HotkeyRegistrar], which is what
/// keeps this file free of a Flutter import — not a style preference:
/// `daemon_startup_test.dart` imports it and runs under `dart test`, which
/// cannot resolve `dart:ui`, so an import reaching here stops the whole
/// binding-free suite resolving rather than failing one test.
///
/// Everything the backend can refuse is a value (AD-12): an unrepresentable
/// key, a refused grab, a refused release, a channel that is gone and a
/// disposed adapter all resolve to [HotkeyUnavailable] or to the binding that
/// is genuinely still in effect. [bind] never throws and never rejects.
///
/// **And the value says *which* refusal it was.** [HotkeyUnavailableCause] is
/// read from [HotkeyRegistrarRefusal.code] through [_causeOf], and the seam's
/// own sentence is what a surface renders. This adapter used to hard-code
/// `keyRefused` with one sentence for every refusal the seam could produce, so
/// a host where no X display can be opened — where no combination can ever
/// work — told the user to choose a different one and apply it again. That is
/// the confusion HOTKEY-08 exists to remove, and it was reachable without
/// anyone parsing a string, which is what made it a failure of the field
/// rather than of the prose.
///
/// **What a `HotkeyBound` here does and does not claim.** AD-10 says
/// [HotkeyRegistration.effective] is "what is actually in effect", and that is
/// what is reported: the requested combination when the grab was accepted, and
/// the *previous* combination when a rebind was abandoned. Both readings are now
/// backed by the server's own answer — [HotkeyRegistrar] makes a refused grab
/// readable and named, and a rejected grab releases nothing, so the previous
/// combination reported on an abandoned rebind is genuinely still held rather
/// than assumed to be. The seam this replaced could do neither: it discarded
/// `keybinder_bind`'s result and answered success regardless, so a combination
/// another client already owned arrived here as a successful bind.
final class X11GlobalHotkey implements GlobalHotkey {
  X11GlobalHotkey({required this._registrar, required this._logger}) {
    _presses = _registrar.presses.listen(
      _onPress,
      // AD-15 backstop, and explicitly defensive: the shipped seam adds to a
      // controller it owns and cannot error it. Kept because what arrives here
      // is whatever an implementation of the interface emits — and this is the
      // only route from a key press to the panel, so an error that ended the
      // subscription would silently retire CAP-1 for the rest of the session.
      onError: (Object error) => _log(
        () => _logger.error(
          'the hotkey press stream errored',
          context: _errorContext(error),
        ),
      ),
    );
  }

  final HotkeyRegistrar _registrar;
  final Logger _logger;
  late final StreamSubscription<void> _presses;

  final StreamController<void> _activations =
      StreamController<void>.broadcast();

  /// The combination genuinely held right now, or null when none is. Read by
  /// the abandoned-rebind path, which has to report it rather than the request.
  HotkeyBinding? _effective;

  /// What [current] answers: the last outcome [bind] produced, recorded so a
  /// settings screen that mounts later can read it without having been
  /// listening. Null until [bind] has answered once.
  HotkeyStatus? _status;

  bool _disposed = false;

  /// The tail of the serialized bind chain — the same idiom, for the same
  /// reason, as `WindowManagerPanelVisibility._queue`.
  ///
  /// [bind] is release-then-grab across two awaits, so two overlapping calls
  /// would interleave as release, release, grab, grab. Both grabs then reach
  /// the backend under the seam's one stable identifier with no `unregister`
  /// between them, and the native side inserts into a `std::map` that does not
  /// overwrite — so keybinder ends up holding **two** combinations while this
  /// adapter can only ever release one. One press toggles the panel twice
  /// until shutdown, and after it the second combination stays grabbed for the
  /// whole X session with a dead handler behind it. The window is real:
  /// `SettingsController.changeHotkey` has no in-flight guard of its own.
  Future<void> _queue = Future<void>.value();

  /// Broadcast: `PanelController` is not promised to be the only consumer.
  @override
  Stream<void> get activations => _activations.stream;

  /// Empty, and closed the moment it is listened to — nothing outside this app
  /// can change a keybinder grab.
  ///
  /// The port's member exists for the Wayland portal, where the compositor owns
  /// the binding and can rebind or drop it behind the app's back. An X11 passive
  /// grab is only ever changed by [bind], and [bind]'s return value is already
  /// the whole report; there is no third party to hear from. So this is a
  /// measured absence rather than an unimplemented member, and a closed stream
  /// says so to a consumer that subscribes.
  @override
  Stream<HotkeyBindOutcome> get bindingChanges =>
      const Stream<HotkeyBindOutcome>.empty();

  /// The last answer [bind] gave, and nothing else can change it here: an X11
  /// passive grab is only ever changed by this app, so [bindingChanges] is
  /// empty and there is no third party whose change could land between two
  /// reads of this.
  ///
  /// Reads a field. No round trip, and on this backend not even the
  /// possibility of one — the seam holds no cached answer to re-ask for.
  @override
  HotkeyStatus? get current => _status;

  /// Serialized against every other in-flight [bind]; see [_queue].
  @override
  Future<HotkeyBindOutcome> bind(HotkeyBinding binding) {
    // Recorded on the way out rather than at each `return` inside [_bind]:
    // every one of that method's answers passes through here, so one funnel is
    // what makes "every outcome updates [current]" a property of the shape
    // rather than of eight remembered assignments — including the refusals
    // answered before the backend, which are exactly the ones an assignment
    // beside `_effective` would miss, since they assign it nothing.
    final result = _queue.then((_) => _bind(binding)).then(_recordStatus);
    // The chain must outlive a link that failed, or one rejection would park
    // every later bind forever. `_bind` never rejects, so this is the same
    // belt-and-braces the panel adapter's queue carries.
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<HotkeyBindOutcome> _bind(HotkeyBinding binding) async {
    if (_disposed) {
      return _shutDownDuringBind();
    }

    // Answered without the backend: the catalogue is the whole of what this
    // build can register, so a key outside it is a settled "no" rather than a
    // request worth making.
    final usbHidUsage = HotkeyKeyCatalogue.usbHidUsageFor(binding.key);
    if (usbHidUsage == null) {
      return _refusedBeforeBackend(
        key: binding.key,
        message:
            'the key "${binding.key}" is not one this build can register as an '
            'X11 shortcut, so the hotkey is inactive — '
            'the tray menu still opens the panel',
      );
    }

    // There used to be a second refusal here, for the seven labels the removed
    // vendor plugin bound to a keypad, ISO or 3270 variant of the key the user
    // asked for. It is gone with the defect: the keyval table it could not see
    // left the tree with the plugin, and `X11KeyGrabRegistrar` now resolves the
    // key by keysym name itself. See `HotkeyKeyCatalogue` for the measurement.

    // No release on the way in, and no short-circuit on an unchanged request.
    // Both facts used to live on the pre-release helper this replaced, and both
    // still govern:
    //
    // * *Nothing is short-circuited on the request.* Asking again for the
    //   combination already configured must reach the seam, because a
    //   short-circuit keyed off the *request* closes every recovery path — a
    //   binding that was refused, or lost, could then never be asked for again.
    //   The seam holds an already-satisfied check of its own, and it compares
    //   against what it actually *holds*, which is only ever set after a grab
    //   the server confirmed.
    // * *Holding two registrations at once is still the failure to prevent.*
    //   Under the backend this replaced it made one press run two handlers, so
    //   AD-8's toggle showed and immediately hid and the panel appeared never to
    //   open; the old ordering prevented that by releasing before it grabbed,
    //   which is exactly how a refused grab cost the user a working shortcut.
    //   Measured against a live X server, re-issuing the *same* grab is not a
    //   second grab, so the shape the double-hold takes here is different and no
    //   less wrong: a rebind that never released would leave the *previous*
    //   combination still opening the panel behind the user's back.
    //   [HotkeyRegistrar.grab] now owns the swap: it acquires, confirms, and
    //   only then lets the previous combination go, so at most one is ever held
    //   *and* a refusal releases nothing.
    try {
      await _registrar.grab(
        HotkeyGrab(modifiers: binding.modifiers, usbHidUsage: usbHidUsage),
      );
    } on Object catch (error) {
      // A teardown that overlapped this grab is not the session refusing it,
      // and must not be reported as one. `dispose()` is deliberately not queued
      // behind [bind] — a daemon that must exit cannot wait on a channel — so a
      // stop signal during a settings rebind runs the whole teardown while this
      // call is parked above. The shipped seam notices that and rejects (it
      // undoes its own registration first), which means *this* is the branch
      // that race actually takes, not the `_disposed` check below. Without the
      // distinction the user is told "this session refused the global
      // shortcut" — a message that sends them to inspect their compositor for
      // something the daemon itself did — and it is logged at error level.
      if (_disposed) {
        return _shutDownDuringBind();
      }
      // A rejected grab has released nothing ([HotkeyRegistrar.grab]), so
      // whatever was in effect before this call still is — still grabbed, and
      // still opening the panel. AD-12 allows "the hotkey is inactive" only when
      // that is true of the machine and not merely of the request, which is what
      // [_refusedBeforeBackend] says at length for the refusals answered before
      // the backend; this is the same rule for the one the backend answers.
      final refusal = _refusalOf(error);
      final cause = _causeOf(refusal);
      final stillInEffect = _effective;
      // The code decides, not merely whether something was held. A
      // `keyRefused` or a `badRequest` leaves the previous grab standing,
      // because the seam acquires before it releases and a rejected grab has
      // released nothing. A `noBackend` or a `workerGone` says the connection
      // that held it is gone — and killing the worker isolate does not close
      // the X socket it opened, since the `Display` is a raw pointer with no
      // finalizer, so the server keeps the passive grab and keeps swallowing
      // the combination for every other application while nothing reads that
      // connection's event queue. Reporting the old combination as effective
      // there claims a shortcut that cannot fire and is still taken from the
      // whole desktop.
      if (stillInEffect == null || cause == HotkeyUnavailableCause.noBackend) {
        // Already null in the first disjunct; in the second it is what makes
        // the adapter's own record true, so a later rebind is not
        // short-circuited against a combination this adapter no longer holds
        // and [current] cannot answer with a stale registration.
        _effective = null;
        _log(
          () => _logger.error(
            'the X11 key grab was refused',
            context: _refusalContext(error, refusal),
          ),
        );
        return HotkeyUnavailable(
          cause: cause,
          message: refusal?.message ?? _unclassifiedRefusal,
        );
      }
      _log(
        () => _logger.error(
          'the X11 key grab was refused, so the rebind was abandoned and the '
          'previous combination is still in effect',
          context: _refusalContext(error, refusal),
        ),
      );
      return _abandonedRebind(stillInEffect);
    }

    // The same race, for a seam that *resolves* a grab it received after its
    // own teardown instead of rejecting it. Explicitly defensive: the shipped
    // seam rejects, so the branch above is what runs in production. It is kept
    // because what runs here is whatever an implementation of the interface
    // does, and reporting `HotkeyBound` for a grab this adapter has already
    // stopped tracking would be a false claim about what is in effect whoever
    // ends up releasing it. Note what the risk is *not*: every path that sets
    // `_disposed` is followed by process exit — `DaemonLifecycle.shutdown()`
    // then `exit(0)`, or `_abort` then `exit(1)` — and the X server drops a
    // client's passive grabs when it disconnects, so a grab stranded here does
    // not outlive the daemon.
    if (_disposed) {
      // Only on this branch: the seam resolved the grab, so something is
      // registered and letting go of it is the point. The rejecting branch
      // above must *not* come here — the shipped seam has already undone the
      // registration and refuses a release once disposed, so the attempt would
      // log a teardown failure that did not happen.
      await _guard(
        'releasing an X11 key grab that landed during teardown',
        _registrar.release,
      );
      return _shutDownDuringBind();
    }

    _effective = binding;
    return HotkeyBound(
      HotkeyRegistration(
        effective: binding,
        authority: BindingAuthority.application,
      ),
    );
  }

  /// Records [outcome] as what [current] answers, and passes it through.
  ///
  /// **`backendDescription` is null here, and that is X11's whole answer to
  /// HOTKEY-03**: this app owns the grab, so what is in effect is the
  /// structured combination in [HotkeyRegistration.effective] and a surface
  /// renders it from the binding itself with `hotkeyBindingLabel`. There is no
  /// backend-authored spelling to carry — the portal's `trigger_description`
  /// has no X11 counterpart, and inventing one here would put this app's own
  /// notation behind a field whose contract is "the backend's own words".
  HotkeyBindOutcome _recordStatus(HotkeyBindOutcome outcome) {
    _status = HotkeyStatus(outcome: outcome, backendDescription: null);
    return outcome;
  }

  /// The outcome for a request this adapter refused before the backend was
  /// touched at all — an unrepresentable key, or one the backend would bind to
  /// a variant nobody can press.
  ///
  /// Nothing was released and nothing was grabbed on the way here, deliberately:
  /// a request that can be answered without the backend must not drop a working
  /// shortcut on its way to failing. So whatever was held before this call is
  /// still held, and AD-10 settles what to report — `effective` is "what is
  /// actually in effect", not what was asked for. A rebind refused here is
  /// therefore abandoned exactly as a rebind whose *grab* the seam refuses is:
  /// the user's previous combination keeps working and is what comes back. Both
  /// paths end at [_abandonedRebind], which is the one home of that answer.
  ///
  /// Answering [HotkeyUnavailable] regardless would say "the hotkey is
  /// inactive" while the old combination was still grabbed and still opening the
  /// panel — `SettingsController.changeHotkey` stores the new preference either
  /// way, so the settings screen and the tray would both show no shortcut while
  /// the previous one kept firing for the rest of the session. Only when nothing
  /// is held is that message true, and then [message] is what says so, naming
  /// the key and the tray (AD-12).
  ///
  /// The refusal is never silent: on the abandoned path it is logged, because the
  /// caller is being handed a `HotkeyBound` for a combination it did not ask for.
  HotkeyBindOutcome _refusedBeforeBackend({
    required String key,
    required String message,
  }) {
    final stillInEffect = _effective;
    if (stillInEffect == null) {
      // Both callers are one bad key on a backend that is present and working —
      // a label outside the catalogue, or one this build cannot register — so
      // choosing another combination is exactly the user's move.
      return HotkeyUnavailable(
        cause: HotkeyUnavailableCause.keyRefused,
        message: message,
      );
    }
    _log(
      () => _logger.error(
        'the requested hotkey cannot be registered by this build, so the '
        'rebind was abandoned and the previous combination is still in effect',
        context: {'refused_key': key},
      ),
    );
    return _abandonedRebind(stillInEffect);
  }

  /// AD-10's answer for a refusal that cost the user nothing: the combination
  /// genuinely still in effect, owned by this application.
  ///
  /// The one home of that answer, reached from both refusal paths — the ones
  /// answered before the backend ([_refusedBeforeBackend]) and a grab the seam
  /// rejected. They share the rule and not merely the shape: `HotkeyUnavailable`
  /// says "the hotkey is inactive", and that is only true when nothing is held
  /// *by a backend that is still there*. Two conditions therefore gate every
  /// caller: a previous combination recorded in [_effective], **and** a backend
  /// still present to be holding it. [_refusedBeforeBackend] satisfies the
  /// second structurally — nothing was sent to the backend on that path, so it
  /// is as present as it was before the call — while the seam-refused caller
  /// must establish it from the refusal's cause, because a `noBackend` or a
  /// `workerGone` says the connection that held the grab is gone and the
  /// combination it still occupies on the server can no longer fire. Nothing is
  /// released on either path, which is what makes the previous combination
  /// genuinely still in effect rather than a guess.
  HotkeyBindOutcome _abandonedRebind(HotkeyBinding stillInEffect) {
    return HotkeyBound(
      HotkeyRegistration(
        effective: stillInEffect,
        authority: BindingAuthority.application,
      ),
    );
  }

  /// What a [bind] interrupted by teardown reports. Not a refusal by the
  /// session, and worded so nobody goes looking for one.
  HotkeyBindOutcome _shutDownDuringBind() {
    return const HotkeyUnavailable(
      // There is no backend left to refuse anything, so retrying with another
      // key is pointless — which is what [HotkeyUnavailableCause.noBackend]
      // says, and what this sentence already said in words.
      cause: HotkeyUnavailableCause.noBackend,
      message:
          'the hotkey backend has already been shut down, so no global '
          'shortcut is registered — the tray menu still opens the panel',
    );
  }

  void _onPress(void _) {
    if (_disposed || _activations.isClosed) {
      return;
    }
    _activations.add(null);
  }

  /// Releases the grab, disposes the seam and closes [activations]. Idempotent,
  /// and never throws: it runs on the shutdown path (AD-4).
  ///
  /// Every step is independent, because the point is to leave nothing behind: a
  /// release the backend refuses must not stop the stream being closed.
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _guard('cancelling the hotkey press subscription', _presses.cancel);
    await _guard('releasing the X11 key grab', _registrar.release);
    await _guard('disposing the hotkey registrar', _registrar.dispose);
    await _guard('closing the hotkey activation stream', _activations.close);
  }

  /// Runs one teardown step, reducing its failure to a log line: a daemon that
  /// cannot exit is the worse failure.
  Future<void> _guard(String what, Future<void> Function() run) async {
    try {
      await run();
    } on Object catch (error) {
      _log(
        () => _logger.error(
          '$what failed',
          context: _refusalContext(error, _refusalOf(error)),
        ),
      );
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

/// [_errorContext] plus the seam's own refusal code when there is one.
///
/// The code is what an operator reading the log actually needs and what used to
/// be missing: a no-display host produced `{error_type: StateError}` and
/// nothing else, so the four distinct refusals were indistinguishable in the
/// journal as well as on the screen. Still no `toString()` — the code is a
/// project-authored enum name, which is exactly the "application-authored
/// context" the `Logger` port asks for.
Map<String, Object?> _refusalContext(
  Object error,
  HotkeyRegistrarRefusal? refusal,
) {
  return {
    ..._errorContext(error),
    if (refusal != null) 'refusal_code': refusal.code.name,
  };
}

/// The seam's refusal, or null when the rejection was something else.
HotkeyRegistrarRefusal? _refusalOf(Object error) {
  return error is HotkeyRegistrarRefusal ? error : null;
}

/// What the user is told, from what the backend answered (HOTKEY-08, D-06).
///
/// The one place the translation happens, and it is a translation rather than a
/// rename: [HotkeyRefusalCode] has four values named for what the backend said
/// and [HotkeyUnavailableCause] has three named for what it means to the person
/// whose hotkey stopped working. AD-12's dividing question is the only one that
/// matters here — *is there any point in the user trying another combination?*
///
/// * `noBackend` and `workerGone` say no. There is nothing to ask: no client
///   library, no display this process can open, or no worker left alive to
///   carry the request. Every other combination reaches the same absence, so
///   inviting the user to pick one is the confusion HOTKEY-08 exists to remove.
/// * `keyRefused` and `badRequest` say yes. A backend answered, so the
///   mechanism is there; this particular request was not granted. `badRequest`
///   is a defect rather than a property of the host, and it lands here for the
///   same reason `HotkeyUnavailableCause.keyRefused`'s own doc gives: telling
///   someone to give up is the answer that cannot be walked back, so it is not
///   the one to guess with.
/// * A rejection that is not a [HotkeyRegistrarRefusal] at all is a
///   `StateError` from the seam's lifecycle guards, and it takes the same
///   non-defeatist reading — the disposed-during-bind race is already answered
///   above by [_shutDownDuringBind], which does report `noBackend`.
HotkeyUnavailableCause _causeOf(HotkeyRegistrarRefusal? refusal) {
  return switch (refusal?.code) {
    HotkeyRefusalCode.noBackend => HotkeyUnavailableCause.noBackend,
    HotkeyRefusalCode.workerGone => HotkeyUnavailableCause.noBackend,
    HotkeyRefusalCode.keyRefused => HotkeyUnavailableCause.keyRefused,
    HotkeyRefusalCode.badRequest => HotkeyUnavailableCause.keyRefused,
    null => HotkeyUnavailableCause.keyRefused,
  };
}

/// The sentence for a rejection that carried none of its own.
///
/// Every [HotkeyRegistrarRefusal] carries a project-authored sentence, so this
/// is reached only when the seam rejected with something else — a lifecycle
/// `StateError`, or an implementation of the interface this adapter does not
/// ship. It says "this session refused" rather than naming a cause, because at
/// that point the cause is genuinely unknown, and it names the tray as AD-12
/// requires of every sentence a surface renders.
const String _unclassifiedRefusal =
    'this session refused the global shortcut, so the hotkey is inactive — '
    'the tray menu still opens the panel';
