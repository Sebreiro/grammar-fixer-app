import 'dart:async';

import '../domain/hotkey/global_hotkey.dart';
import '../domain/logger.dart';
import '../domain/panel/panel_visibility.dart';

/// The hotkey toggle (AD-8) and Settings view coordination.
///
/// CAP-1 budgets 100 ms from key press to a focused panel, so the decision
/// reads the port's synchronous visibility mirror and the show/hide call is
/// fired rather than awaited — nothing on this path waits on the window
/// manager. The panel window itself is constructed once at startup, so
/// [PanelVisibility.show] only changes visibility.
final class PanelController {
  PanelController({
    required this._visibility,
    required GlobalHotkey hotkey,
    required this._logger,
  }) {
    _activations = hotkey.activations.listen(
      (_) => onHotkeyActivated(),
      // AD-15 backstop: the port promises a plain event stream. An adapter
      // that errors instead must not take the subscription — and with it
      // every later press — down with it.
      onError: (Object error) => _log(
        () => _logger.error(
          'the hotkey activation stream errored',
          context: _errorContext(error),
        ),
      ),
    );
    _visibilityChanges = _visibility.changes.listen(
      _onVisibilityChanged,
      onError: (Object error) => _log(
        () => _logger.error(
          'the panel visibility stream errored',
          context: _errorContext(error),
        ),
      ),
    );
  }

  final PanelVisibility _visibility;
  final Logger _logger;
  late final StreamSubscription<void> _activations;
  late final StreamSubscription<PanelVisibilityState> _visibilityChanges;
  bool _settingsVisible = false;

  /// The home view reports its current surface synchronously so a hotkey can
  /// swap Settings for the panel without first hiding the warm window.
  void setSettingsVisible(bool visible) => _settingsVisible = visible;

  /// Broadcast: the home view watches this, and it is not promised to be the
  /// only consumer.
  final StreamController<void> _showRequests =
      StreamController<void>.broadcast();
  final StreamController<void> _focusLosses =
      StreamController<void>.broadcast();

  void _onVisibilityChanged(PanelVisibilityState state) {
    // A GTK hide callback carries no session reason. Only the adapter's
    // attributed focus loss may discard a Settings capture draft. Its stream
    // delivery may lag behind a later show, so check the current mirror too.
    // CorrectionController owns the editor and active run; hiding does not
    // cancel either one under AD-4.
    if (state != PanelVisibilityState.focusLost ||
        !_settingsVisible ||
        _focusLosses.isClosed ||
        _visibleNow()) {
      return;
    }
    _focusLosses.add(null);
  }

  /// A native focus-loss departure while Settings is showing. Settings uses
  /// this to abandon only its capture draft, leaving the panel session intact.
  Stream<void> get focusLosses => _focusLosses.stream;

  /// Emits once per show this controller requests — the hotkey summoning a hidden
  /// panel (CAP-1), a later launch asking the holder to raise it (AD-14), and the
  /// tray's open-panel entry (AD-12).
  ///
  /// It exists because [PanelVisibility.changes] cannot answer the question a
  /// surface actually has. That stream emits on a *transition*, so a show of a
  /// window that is already visible produces nothing at all: no event, no fresh
  /// session (AD-18 keys off the same transition), and so no way for the window's
  /// content to react. The consequence was concrete — with the settings screen
  /// showing, the tray's "open the panel" raised a window still showing settings,
  /// on a screen printing "the tray menu still opens the panel".
  ///
  /// A *request*, not a confirmation. It is emitted where the show is fired, so
  /// nothing here awaits the window manager and CAP-1's budget is untouched; a
  /// show the port then rejects has still been asked for, and the surface that
  /// keys off it wants the intent rather than the outcome.
  Stream<void> get showRequests => _showRequests.stream;

  /// Mirrors the port so widgets read visibility through the application
  /// ring instead of reaching for the port themselves.
  ///
  /// [PanelVisibility.changes] is deliberately not re-exposed — it is
  /// broadcast, so re-exposing it would cost nothing mechanically. The reason
  /// is layering: this controller owns the toggle, not the visibility stream,
  /// and a consumer that needs the stream takes it from the port through its
  /// own seam rather than through a controller that has nothing to add to it.
  bool get isVisible => _visibleNow();

  /// One press of the bound combination: shows the hidden panel (CAP-1),
  /// returns visible Settings to the panel, or hides a visible panel (CAP-14).
  void onHotkeyActivated() {
    if (_visibleNow()) {
      if (_settingsVisible) {
        _requestShow();
        return;
      }
      _fire(_visibility.hide, 'hide');
      return;
    }
    _requestShow();
  }

  /// Shows the panel without toggling it.
  ///
  /// AD-14's second launch asks the resident holder to *show* its panel, and
  /// hiding it because it happened to be up already would turn a deliberate
  /// launch into a dismissal. The tray menu's "open the panel" path (AD-12)
  /// wants the same call. Fired rather than awaited, for the same CAP-1 reason
  /// as [onHotkeyActivated].
  void showPanel() {
    _requestShow();
  }

  /// Asks the window to come up and says so on [showRequests].
  ///
  /// The port call goes first: it is the one with a 100 ms budget behind it, and
  /// the announcement is a synchronous add to a broadcast controller whose
  /// listeners are woken a microtask later. Guarded, because a throw out of a
  /// closed controller here would escape onto the activations stream and into the
  /// daemon's zone — the one thing every guard in this file exists to prevent.
  void _requestShow() {
    _fire(_visibility.show, 'show');
    if (_showRequests.isClosed) {
      return;
    }
    try {
      _showRequests.add(null);
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'announcing a panel show request failed',
          context: _errorContext(error),
        ),
      );
    }
  }

  /// Reads the port's visibility mirror, reducing a throwing adapter to a
  /// log line and an assumption.
  ///
  /// AD-15 backstop, and the same reasoning as [_fire]'s: the port declares a
  /// synchronous in-process mirror, so a throw is a broken adapter. It runs on
  /// the decision path of every press, outside the fired future, so without
  /// this it is the one port call that escapes to the caller — or, from the
  /// activations stream, to the zone. Hidden is the safe assumption: the user
  /// pressed the hotkey because they want the panel, and CAP-14's second press
  /// re-hides it once the mirror answers again.
  bool _visibleNow() {
    try {
      return _visibility.isVisible;
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'reading the panel visibility mirror failed; assuming hidden',
          context: _errorContext(error),
        ),
      );
      return false;
    }
  }

  Future<void> dispose() async {
    try {
      await _visibilityChanges.cancel();
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'cancelling the panel visibility subscription failed',
          context: _errorContext(error),
        ),
      );
    }
    try {
      await _activations.cancel();
    } on Object catch (error) {
      // AD-15 backstop: shutdown completes even against a broken adapter.
      _log(
        () => _logger.error(
          'cancelling the hotkey activation subscription failed',
          context: _errorContext(error),
        ),
      );
    }
    // After the cancel, so no activation can arrive looking for a stream that is
    // already gone. Idempotent: closing a closed controller is a no-op.
    await _showRequests.close();
    await _focusLosses.close();
  }

  /// Fires a visibility call and attaches failure handling to the returned
  /// future.
  ///
  /// Registering a handler is not awaiting it: the handler is installed
  /// synchronously and this method returns before the window manager
  /// answers, so AD-8's decision path — and CAP-1's 100 ms budget — is
  /// unchanged. The toggle therefore stays usable on the next press even
  /// when this call never lands.
  void _fire(Future<void> Function() call, String action) {
    try {
      unawaited(
        call().catchError((Object error) => _logFailure(action, error)),
      );
    } on Object catch (error) {
      // AD-15 backstop: the port declares a Future, so a synchronous throw
      // is a broken adapter — it must still not escape the hotkey path.
      _logFailure(action, error);
    }
  }

  void _logFailure(String action, Object error) {
    _log(
      () => _logger.error(
        'the panel visibility port rejected $action',
        context: _errorContext(error),
      ),
    );
  }
}

/// Emits a log line without letting the logger's own failure escape — see the
/// canonical note in `correction_controller.dart`.
void _log(void Function() emit) {
  try {
    emit();
  } on Object {
    // Nowhere left to report this: the reporting channel is what broke.
  }
}

/// The only part of a caught error that is safe to put in a log line — see
/// the [Logger] port's doc, and the canonical note in
/// `correction_controller.dart`.
Map<String, Object?> _errorContext(Object error) {
  return {'error_type': error.runtimeType.toString()};
}
