import 'dart:async';

import 'package:window_manager/window_manager.dart';

import 'panel_activation.dart';
import 'panel_activation_presenter.dart';
import 'panel_window.dart';

/// [PanelWindow] over `window_manager` — the one file in `lib/` that names the
/// package, apart from the composition root's own window setup (AD-1).
///
/// **Why `onWindowEvent` and not the typed callbacks.** `window_manager 0.5.2`
/// emits `show` and `hide` from its Linux plugin (`on_window_show` /
/// `on_window_hide` in `linux/window_manager_plugin.cc`), but `WindowListener`
/// declares no `onWindowShow`/`onWindowHide` and its dispatch map in
/// `lib/src/window_manager.dart` has no entry for either name. The untyped
/// `onWindowEvent(String)` hook, which fires for *every* event before that map
/// is consulted, is therefore the only route to the two events the visibility
/// mirror is reconciled from. The typed hooks are deliberately not mixed in
/// alongside it: they would deliver `blur`, `minimize` and `restore` twice.
///
/// The listener is registered in the constructor, so the adapter must be
/// constructed before the window can produce an event — not because
/// `ensureInitialized()` has run (on Linux that answers a bare `true` and
/// connects nothing), but because an event delivered before `addListener`
/// simply reaches no one.
final class WindowManagerPanelWindow
    with WindowListener
    implements PanelWindow {
  WindowManagerPanelWindow({this._activationPresenter}) {
    windowManager.addListener(this);
  }

  /// Broadcast so the seam does not impose a one-listener rule of its own on
  /// top of the port's.
  final StreamController<String> _events = StreamController<String>.broadcast();

  final PanelActivationPresenter? _activationPresenter;

  bool _disposed = false;
  bool _focused = false;
  bool _selfFocusPending = false;

  @override
  Stream<String> get events => _events.stream;

  @override
  void onWindowEvent(String eventName) {
    if (_disposed) {
      return;
    }
    if (eventName == 'focus') {
      _focused = true;
      final reported = _selfFocusPending ? 'self-focus' : 'focus';
      _selfFocusPending = false;
      _events.add(reported);
      return;
    }
    if (eventName == 'blur') {
      _focused = false;
      // A present already in flight can still deliver its focus-in after this
      // blur. Keep its provenance until a focus-in or an explicit hide.
    }
    _events.add(eventName);
  }

  /// The three requests carry the same post-disposal guard [onWindowEvent]
  /// does, and for the same reason: once [dispose] has run the listener is
  /// deregistered and [events] is closed, so a call that still moved the real
  /// window could never be echoed back and no mirror above it could ever
  /// correct itself. Written out rather than routed through a shared helper
  /// taking a tear-off, so `test/architecture/hidden_window_test.dart` can
  /// still see which `window_manager` methods this file reaches.
  @override
  Future<void> show() async {
    if (_disposed) {
      return;
    }
    if (!_focused) {
      _selfFocusPending = true;
    }
    await windowManager.show();
  }

  @override
  Future<void> hide() async {
    if (_disposed) {
      return;
    }
    _selfFocusPending = false;
    await windowManager.hide();
  }

  @override
  Future<void> focus({PanelActivation? activation}) async {
    if (_disposed) {
      return;
    }
    if (!_focused) {
      _selfFocusPending = true;
    }
    final presenter = _activationPresenter;
    if (presenter == null) {
      await windowManager.focus();
      return;
    }
    await presenter.present(activation);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    windowManager.removeListener(this);
    await _events.close();
  }
}
