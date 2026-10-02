import 'dart:async';

import '../domain/config/close_behavior.dart';
import '../domain/config/config_store.dart';
import '../domain/logger.dart';
import '../domain/panel/panel_visibility.dart';

/// Applies the saved native Close preference without owning daemon teardown.
final class PanelCloseController {
  PanelCloseController({
    required this._configStore,
    required this._visibility,
    required this._logger,
  }) {
    _closeSubscription = _visibility.closeRequests.listen(
      (_) => _onCloseRequested(),
      onError: (Object error) =>
          _report('the panel close-request stream errored', error),
    );
  }

  final ConfigStore _configStore;
  final PanelVisibility _visibility;
  final Logger _logger;
  final StreamController<void> _quitRequests =
      StreamController<void>.broadcast();
  StreamSubscription<void>? _closeSubscription;
  bool _disposed = false;
  bool _quitRequested = false;

  Stream<void> get quitRequests => _quitRequests.stream;

  void _onCloseRequested() {
    if (_disposed || _quitRequested) return;
    switch (_closeBehavior()) {
      case CloseBehavior.closeToTray:
        unawaited(_hide());
      case CloseBehavior.quit:
        _quitRequested = true;
        _quitRequests.add(null);
    }
  }

  CloseBehavior _closeBehavior() {
    try {
      // Reading the committed snapshot also observes external file edits.
      return _configStore.current.closeBehavior;
    } on Object catch (error) {
      _report('the close preference could not be read; closing to tray', error);
      return CloseBehavior.closeToTray;
    }
  }

  Future<void> _hide() async {
    try {
      await _visibility.hide();
    } on Object catch (error) {
      _report('the window rejected the close hide', error);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final subscription = _closeSubscription;
    _closeSubscription = null;
    try {
      await subscription?.cancel();
    } on Object catch (error) {
      _report('cancelling the panel close subscription failed', error);
    }
    await _quitRequests.close();
  }

  void _report(String message, Object error) {
    try {
      _logger.error(
        message,
        context: {'error_type': error.runtimeType.toString()},
      );
    } on Object {
      // A failed reporting channel has no further reporting destination.
    }
  }
}
