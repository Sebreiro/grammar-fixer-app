import 'dart:async';

import 'package:hotkey_grammar_corrector/src/infrastructure/panel/panel_activation.dart';

import 'package:hotkey_grammar_corrector/src/infrastructure/panel/panel_window.dart';

/// A [PanelWindow] that models a **lagging** window, and models its *state* as
/// well as the calls made against it.
///
/// State is the point. A fake that recorded only call names let a mirror-only
/// assertion pass while the real panel stayed on screen: the platform order was
/// `show, hide, focus`, every name was present, and the window ended mapped
/// because `focus()` is `gtk_window_present` and maps a hidden toplevel. So
/// [visible] is what a settled test row must assert against, and [calls] only
/// says how it got there.
///
/// Every call parks until the test releases it, [inFlight] says how many the
/// window is holding — which is how serialisation is asserted directly — and
/// the event a call produces is emitted **before** its future completes — modelling a window whose own echo arrives while the request is
/// still outstanding, which is the ordering the adapter's `_outstanding` guard
/// rests on (and the one assumption no test here can verify — see
/// `test/platform/panel_visibility_live_test.dart`).
final class FakePanelWindow implements PanelWindow {
  FakePanelWindow({this.showHasMinimizedPreHop = false});

  final List<PanelActivation?> focusActivations = [];

  /// Models `windowManager.show()`'s real shape: `await isMinimized()` first,
  /// and only then `invokeMethod('show')`. That first hop is a second await
  /// point, and an unserialised `hide()` issued during it reaches the platform
  /// *before* the show does — a reordering, not merely a delay.
  final bool showHasMinimizedPreHop;

  /// Whether the toplevel is mapped. An iconified window remains mapped but is
  /// not on screen; [iconified] distinguishes it from a hidden toplevel.
  bool visible = false;

  /// The window manager's iconified state, reported by native window events.
  bool iconified = false;

  /// Whether the window was *ever* mapped. A panel that flashes on screen and
  /// is taken down again is still a defect, and [visible] alone cannot say so.
  bool wasEverVisible = false;

  /// When set, the matching call rejects instead of landing — the window
  /// manager refusing a request. The window's state does not change and no
  /// event is emitted, exactly as a refused platform call behaves.
  ///
  /// Read when the call is **issued**, not when it is released, because that
  /// is when a real channel call is either accepted or refused. Arm it before
  /// the request that should fail; arming it after the call has parked does
  /// nothing.
  Object? showError;
  Object? hideError;
  Object? focusError;

  /// Every platform call, in the order it was issued.
  final List<String> calls = <String>[];

  bool disposed = false;

  final StreamController<String> _events = StreamController<String>.broadcast();
  final List<_ParkedCall> _parked = <_ParkedCall>[];

  @override
  Stream<String> get events => _events.stream;

  /// How many calls are parked, waiting for the test to release them.
  int get inFlight => _parked.length;

  @override
  Future<void> show() async {
    if (showHasMinimizedPreHop) {
      await _park('isMinimized');
    }
    // `gtk_widget_show`: maps the window, and nothing more.
    await _park('show', becomesVisible: true);
  }

  @override
  Future<void> hide() async {
    await _park('hide', becomesVisible: false);
  }

  @override
  Future<void> focus({PanelActivation? activation}) async {
    focusActivations.add(activation);
    // `gtk_window_present`: raises *and maps*. This is the call that made the
    // reverted attempt's panel reappear.
    await _park('focus', becomesVisible: true);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    // A real plugin's already-issued channel calls still resolve as it goes
    // away, and a test that disposes with one parked would otherwise leave a
    // future nothing can ever complete.
    while (_parked.isNotEmpty) {
      _release(_parked.removeAt(0));
    }
    await _events.close();
  }

  /// An event the window produced on its own — a window manager unmapping it,
  /// the user clicking away, an iconify from the task bar.
  void emitEvent(String name) {
    if (_events.isClosed) {
      return;
    }
    if (name == 'minimize') {
      iconified = true;
    } else if (name == 'restore') {
      iconified = false;
    }
    _events.add(name);
  }

  /// Pushes an error onto [events] — a seam breaking its promise of a plain
  /// stream of event names.
  void emitEventError(Object error) {
    if (_events.isClosed) {
      return;
    }
    _events.addError(error);
  }

  /// Closes [events] while the window is otherwise alive — the seam's stream
  /// ending under a *live* adapter, which [dispose] cannot model: the adapter
  /// cancels its subscription before disposing the window, and a cancelled
  /// subscription never receives the done event.
  ///
  /// The window emits nothing further afterwards: calls still park, release
  /// and move [visible], but [emitEvent] no-ops on a closed controller, so a
  /// request driven past this point produces no echo — an absence of the
  /// fake's making, not the adapter's.
  Future<void> closeEvents() async {
    await _events.close();
  }

  /// Completes the oldest parked call.
  void releaseNext() => _release(_parked.removeAt(0));

  /// Completes the oldest parked call named [name], leaving anything parked
  /// *before* it still in flight.
  ///
  /// Out-of-order completion is not a curiosity here. Bounding a link of the
  /// adapter's request chain means the window can be holding two of our calls
  /// at once, and the whole question that opens is what happens when the
  /// older, already-abandoned one lands *after* the newer one has answered.
  /// FIFO [releaseNext] cannot pose it.
  void releaseCall(String name) {
    final index = _parked.indexWhere((call) => call.name == name);
    if (index < 0) {
      throw StateError('no parked $name call to release');
    }
    _release(_parked.removeAt(index));
  }

  /// Releases everything, including calls that only appear once an earlier one
  /// resolves, and drains the event loop between each.
  ///
  /// The zero delays are yields, not a wait on a race: every future here is
  /// resolved by this method itself, so the loop ends when the adapter has
  /// nothing left to issue.
  Future<void> settle() async {
    for (var guard = 0; guard < 100; guard += 1) {
      if (_parked.isEmpty) {
        await Future<void>.delayed(Duration.zero);
        if (_parked.isEmpty) {
          return;
        }
      }
      releaseNext();
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('the window never settled — a request loop?');
  }

  Future<void> _park(String name, {bool? becomesVisible}) {
    calls.add(name);
    final call = _ParkedCall(name, becomesVisible, _errorFor(name));
    _parked.add(call);
    return call.completer.future;
  }

  Object? _errorFor(String name) => switch (name) {
    'show' => showError,
    'hide' => hideError,
    'focus' => focusError,
    _ => null,
  };

  void _release(_ParkedCall call) {
    final error = call.error;
    if (error != null) {
      call.completer.completeError(error);
      return;
    }
    final becomesVisible = call.becomesVisible;
    if (becomesVisible == false) {
      iconified = false;
    }
    if (becomesVisible != null && visible != becomesVisible) {
      visible = becomesVisible;
      wasEverVisible = wasEverVisible || becomesVisible;
      // GTK emits `show`/`hide` on a real transition only, so a `focus` on an
      // already-mapped window is silent — and the event lands before the
      // caller's future resolves.
      emitEvent(becomesVisible ? 'show' : 'hide');
    }
    call.completer.complete();
  }
}

final class _ParkedCall {
  _ParkedCall(this.name, this.becomesVisible, this.error);

  final String name;
  final bool? becomesVisible;
  final Object? error;
  final Completer<void> completer = Completer<void>();
}
