import 'dart:async';

import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_grab.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_registrar.dart';

import 'cancel_failing_stream.dart';

/// A [HotkeyRegistrar] that records the **sequence** of calls made against it,
/// not the set.
///
/// Order is the whole assertion on several of the adapter's rows, and what it
/// pins inverted when the seam moved onto a private X11 connection. A rebind
/// must **not** release before it grabs: the seam now acquires the new
/// combination, confirms it against the server, and only then lets the previous
/// one go, so a refused grab leaves the user's working shortcut untouched. A
/// bare `release()` on the bind path is therefore a regression, and it is only
/// observable as an extra entry in [calls] — a set-shaped fake could not tell it
/// from the ordering it replaced.
///
/// **It deliberately does not refuse [grab] and [release] after [dispose]**,
/// although the shipped seam does and its interface says so. A fake that
/// enforced that contract would be doing the adapter's job for it: every one of
/// `X11GlobalHotkey`'s own post-dispose guards would then pass whether it was
/// there or not, which is precisely how an unpinned guard survives a suite.
///
/// **The seam's half of that contract is currently pinned nowhere
/// mechanically,** and this paragraph says so rather than citing something that
/// no longer exists. It used to be pinned against mocked platform channels, in
/// a suite that was deleted along with the `hotkey_manager` seam it drove,
/// because the replacement talks to libX11.so.6 over `dart:ffi` and cannot be
/// driven by a mocked channel at all
/// — exercising it needs a live X server, which neither CI nor this project's
/// devcontainer provides by default. `X11KeyGrabRegistrar._refuseIfDisposed` is
/// the implementation of the contract, and the reasoning above is why that
/// matters: an unpinned guard is exactly the kind that disappears in a later
/// refactor with the whole suite still green.
final class FakeHotkeyRegistrar implements HotkeyRegistrar {
  /// Every call in the order it was made, rendered with its argument:
  /// `grab(control+shift 0x0007000a)`, `release()`, `dispose()`.
  final List<String> calls = <String>[];

  /// Every grab requested, structurally, so a row can assert the usage and the
  /// modifiers rather than only that a grab happened.
  final List<HotkeyGrab> grabs = <HotkeyGrab>[];

  /// When set, the matching call records itself and then rejects — the backend
  /// refusing the request, which the adapter must reduce to a value (AD-12).
  Object? grabError;
  Object? releaseError;
  Object? disposeError;

  /// When set, cancelling a subscription to [presses] rejects.
  ///
  /// A `StreamController` cannot express this on its own — see
  /// [CancelFailingStream] — and it is the only way to reach the first of
  /// `X11GlobalHotkey.dispose()`'s four guarded steps on its failure path.
  Object? cancelError;

  /// Awaited inside [grab], after the call is recorded and before its error is
  /// applied — a grab that can be held open for as long as a row needs.
  ///
  /// One row needs it: a stop signal arriving while a settings rebind is parked
  /// on the backend. `dispose()` is deliberately not queued behind `bind()`, so
  /// the whole teardown can run in that gap, and the adapter has to notice when
  /// its grab finally lands.
  Future<void> Function()? onGrab;

  /// Run at the start of [release], before its error is applied.
  ///
  /// The one hook of its kind here, and it exists for one row. `X11GlobalHotkey`
  /// guards its press handler on `_disposed`, and nothing else can reach that
  /// guard: the adapter cancels its subscription first and closes this fake's
  /// stream last, so a press emitted before teardown is delivered normally and
  /// one emitted after it is dropped by an already-closed controller — by the
  /// *fake*, not by the adapter. A guard whose only evidence is a fake doing
  /// the filtering for it is not pinned at all. Emitting from here, with
  /// [cancelError] armed so the subscription survives, is the one point at
  /// which the adapter's own guard is what has to stop the event.
  void Function()? onRelease;

  bool disposed = false;

  final StreamController<void> _presses = StreamController<void>.broadcast();

  @override
  Stream<void> get presses =>
      CancelFailingStream<void>(_presses.stream, () => cancelError);

  /// The user pressing the combination currently held.
  void emitPress() {
    if (_presses.isClosed) {
      return;
    }
    _presses.add(null);
  }

  /// The seam breaking its promise of a plain stream of presses.
  void emitPressError(Object error) {
    if (_presses.isClosed) {
      return;
    }
    _presses.addError(error);
  }

  @override
  Future<void> grab(HotkeyGrab grab) async {
    calls.add('grab($grab)');
    grabs.add(grab);
    final held = onGrab;
    if (held != null) {
      await held();
    }
    _rejectIfArmed(grabError);
  }

  @override
  Future<void> release() async {
    calls.add('release()');
    onRelease?.call();
    _rejectIfArmed(releaseError);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose()');
    disposed = true;
    await _presses.close();
    _rejectIfArmed(disposeError);
  }

  void _rejectIfArmed(Object? error) {
    if (error != null) {
      throw error;
    }
  }
}
