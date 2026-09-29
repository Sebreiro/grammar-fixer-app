import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/panel/panel_visibility.dart';

import 'cancel_failing_stream.dart';

final class FakePanelVisibility implements PanelVisibility {
  bool _visible = false;

  /// Broadcast, as the port declares: a state-change notification stream that
  /// may have several independent listeners.
  final StreamController<PanelVisibilityState> _changes =
      StreamController<PanelVisibilityState>.broadcast();

  /// The departure [changes] last reported, mirroring the adapter's own record
  /// so the two agree on when a departure is news.
  PanelVisibilityState _lastDeparture = PanelVisibilityState.dismissed;

  /// When set, [show] rejects and visibility does not change — the window
  /// manager refusing to map the window.
  Object? showError;

  /// When set, [hide] rejects and visibility does not change.
  Object? hideError;

  /// When set, cancelling a subscription to [changes] rejects — the teardown
  /// a controller's `dispose()` has to survive (AD-4).
  Object? cancelError;

  /// When set, reading [isVisible] throws — the synchronous mirror of an
  /// adapter whose window handle is gone. Synchronous, because the port
  /// declares a plain getter and never a future.
  Object? isVisibleError;

  @override
  bool get isVisible {
    final error = isVisibleError;
    if (error != null) {
      throw error;
    }
    return _visible;
  }

  @override
  Stream<PanelVisibilityState> get changes =>
      CancelFailingStream<PanelVisibilityState>(
        _changes.stream,
        () => cancelError,
      );

  @override
  Future<void> show() async {
    final error = showError;
    if (error != null) {
      throw error;
    }
    _emit(PanelVisibilityState.shown);
  }

  @override
  Future<void> hide() async {
    final error = hideError;
    if (error != null) {
      throw error;
    }
    _emit(PanelVisibilityState.dismissed);
  }

  /// Simulates the adapter's focus-loss hide (CAP-14).
  ///
  /// A departure the session survives, which is the whole reason this is a
  /// separate member from [hide] rather than a second call to it.
  void loseFocus() => _departFromAVisiblePanel(PanelVisibilityState.focusLost);

  /// Simulates the window being iconified — today a workspace switch or a
  /// show-desktop gesture.
  ///
  /// The other departure a session survives. Paired with [restore] because an
  /// iconify is the one departure with a return route of its own: without it a
  /// test can only bring the panel back with [show], which reports the same
  /// state but is a different gesture.
  void minimize() => _departFromAVisiblePanel(PanelVisibilityState.iconified);

  /// Simulates the window being de-iconified by the window manager.
  ///
  /// Reports [PanelVisibilityState.shown], exactly as [show] does: the port
  /// names where the window is, and a restored panel and a summoned one are in
  /// the same place.
  void restore() => _emit(PanelVisibilityState.shown);

  /// Pushes an error onto [changes] — an adapter breaking the port's promise
  /// of a plain stream of [PanelVisibilityState].
  void emitChangesError(Object error) => _changes.addError(error);

  /// The two departures only the window itself can cause, neither of which the
  /// adapter reports at a panel that is already away: `_onBlur` returns on a
  /// false mirror, and a `minimize` is believed only when it actually took the
  /// panel down. Without this guard the fake could emit a sequence the shipped
  /// adapter cannot — a survivable departure over a standing dismissal — and a
  /// row written against it would pin a rule nothing implements (DW-30). Pinned
  /// by a row of its own in `correction_controller_test.dart`, because
  /// `CorrectionController` latches the dismissal and so cannot see the
  /// difference.
  void _departFromAVisiblePanel(PanelVisibilityState departure) {
    if (!_visible) {
      return;
    }
    _emit(departure);
  }

  /// The port's transition rule: there is one way to be up, so a `shown` over a
  /// visible panel reports nothing, and there are three ways to be away, so a
  /// departure reports whenever it is not the one already standing.
  ///
  /// The re-attribution half is what lets the application ring compose two
  /// departures — an iconify and then a dismissal — which is the sequence whose
  /// *order* decides the next session (DW-30).
  ///
  /// **The same rule, not the same shape, and the difference is worth naming.**
  /// In the adapter the mirror *leads* the request, so a `show()` the window
  /// then refuses has already written the mirror and already emitted `shown`;
  /// here [showError] throws before anything is emitted at all, and [isVisible]
  /// never moves. This fake is the port's *emission contract* kept honestly, not
  /// a model of the adapter's ordering — a row that needs the mirror to lead a
  /// refusal belongs at the adapter, over `FakePanelWindow`.
  void _emit(PanelVisibilityState state) {
    if (state.isVisible) {
      if (_visible) {
        return;
      }
      _visible = true;
      _changes.add(state);
      return;
    }
    if (!_visible && state == _lastDeparture) {
      return;
    }
    _visible = false;
    _lastDeparture = state;
    _changes.add(state);
  }

  /// Closes the changes stream. Test teardown only — not part of the port.
  void dispose() {
    unawaited(_changes.close());
  }
}
