import 'dart:async';

import 'package:hotkey_grammar_corrector/src/infrastructure/tray/tray_icon.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/tray/tray_menu_entry.dart';

import 'cancel_failing_stream.dart';

/// A [TrayIcon] that records the **sequence** of calls made against it, not the
/// set.
///
/// Order is the whole assertion here. The native `set_context_menu`
/// dereferences the `AppIndicator*` that `set_icon` creates, with no null check
/// — so "the icon was set and the menu was pushed" is satisfied by the one
/// ordering that crashes, and a set-shaped fake could not tell the difference.
/// Hence [calls], a list of rendered call descriptions, alongside [menus] for
/// the rows that need to read a label rather than only a key.
final class FakeTrayIcon implements TrayIcon {
  /// Every call in the order it was made, rendered with its argument:
  /// `setIcon(assets/tray/…png)`, `setMenu(open-panel:enabled)`, `dispose()`.
  final List<String> calls = <String>[];

  /// Every menu pushed, structurally, so a row can assert the words a user
  /// reads and not only the key behind them.
  final List<List<TrayMenuEntry>> menus = <List<TrayMenuEntry>>[];

  /// When set, the matching call records itself and then rejects — a seam
  /// refusing the request, which the port under test must propagate rather
  /// than swallow.
  Object? setIconError;
  Object? setMenuError;
  Object? disposeError;

  /// Holds one native menu update so a newer status can arrive before it lands.
  Completer<void>? setMenuGate;

  /// When set, cancelling a subscription to [selections] rejects.
  ///
  /// A `StreamController` cannot express this on its own — see
  /// [CancelFailingStream] — and it is the only way to reach the first of
  /// `TrayManagerTray.dispose()`'s three guarded steps on its failure path.
  Object? cancelError;

  bool disposed = false;

  final StreamController<String> _selections =
      StreamController<String>.broadcast();

  @override
  Stream<String> get selections =>
      CancelFailingStream<String>(_selections.stream, () => cancelError);

  /// The user picking a menu entry, by its [TrayMenuEntry.key].
  void emitSelection(String key) {
    if (_selections.isClosed) {
      return;
    }
    _selections.add(key);
  }

  /// The seam breaking its promise of a plain stream of keys.
  void emitSelectionError(Object error) {
    if (_selections.isClosed) {
      return;
    }
    _selections.addError(error);
  }

  @override
  Future<void> setIcon(String assetPath) async {
    calls.add('setIcon($assetPath)');
    _rejectIfArmed(setIconError);
  }

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) async {
    calls.add('setMenu(${entries.map(_describe).join(', ')})');
    final gate = setMenuGate;
    if (gate != null) {
      await gate.future;
    }
    menus.add(List<TrayMenuEntry>.unmodifiable(entries));
    _rejectIfArmed(setMenuError);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose()');
    disposed = true;
    await _selections.close();
    _rejectIfArmed(disposeError);
  }

  static String _describe(TrayMenuEntry entry) =>
      '${entry.key}:${entry.enabled ? 'enabled' : 'disabled'}';

  void _rejectIfArmed(Object? error) {
    if (error != null) {
      throw error;
    }
  }
}
