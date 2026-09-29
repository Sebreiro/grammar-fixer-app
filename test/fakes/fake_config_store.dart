import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_load_result.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_store.dart';

import 'cancel_failing_stream.dart';

final class FakeConfigStore implements ConfigStore {
  /// Redirects to a private positional constructor, because the field behind
  /// [current] has to be private — the getter is what throws on demand — and a
  /// named parameter cannot be spelled `this._current`.
  factory FakeConfigStore({required AppConfig current, String? loadWarning}) =>
      FakeConfigStore._(current, loadWarning);

  FakeConfigStore._(this._current, this.loadWarning);

  /// When set, reading [current] throws instead of answering.
  ///
  /// The port declares `current` as the most recently loaded or written value and
  /// documents a read before `load()` as programmer error, so an adapter that
  /// throws afterwards is breaking its own contract (AD-13). It is the one port
  /// call a mutation makes *outside* an `await`, so without a guard it escapes
  /// the mutation entirely — which is what leaves a surface's controls disabled
  /// for good and an error in the zone.
  Object? currentError;

  AppConfig _current;

  @override
  AppConfig get current {
    final error = currentError;
    if (error != null) {
      throw error;
    }
    return _current;
  }

  /// Settable per test, and by [write].
  set current(AppConfig config) => _current = config;

  /// Scripted malformed-file warning surfaced by [load]; null for a
  /// well-formed file (AD-13).
  String? loadWarning;

  /// When set, [write] rejects: [current] is unchanged, nothing is recorded
  /// in [writes], and no echo reaches [changes] — an unwritable config file
  /// (AD-13) as the settings surface sees it.
  Object? writeError;

  /// When set, [write] throws `ArgumentError.value` for any config this
  /// predicate accepts, the way `JsonConfigStore.write` refuses a
  /// cross-field-invalid value — before any I/O, so nothing is written and
  /// nothing is echoed.
  bool Function(AppConfig config)? rejects;

  /// The error [rejects] throws, when the default shape is not enough. The
  /// real store's `ArgumentError.value(config, …)` stringifies to `Instance
  /// of 'AppConfig'`, so a test proving the refusal path logs a *type* rather
  /// than the error itself needs to supply one that carries a payload.
  /// Must be an `ArgumentError` to reach the same arm.
  ArgumentError? rejectError;

  /// When set, cancelling a subscription to [changes] rejects — the teardown
  /// a controller's `dispose()` has to survive.
  Object? cancelError;

  /// When set, [write] waits on it before doing anything — a slow disk, and the
  /// only way to observe a mutation while it is still *in flight*.
  Completer<void>? writeGate;

  /// Run after a successful [write], before it returns — the seam for a store
  /// that breaks *between* the write and the read that renders it, which is the
  /// one ordering a guard on the write path cannot see.
  void Function()? onWriteComplete;

  /// Every written config, in order, for assertions.
  final List<AppConfig> writes = [];

  final StreamController<AppConfig> _changes =
      StreamController<AppConfig>.broadcast();

  @override
  Future<ConfigLoadResult> load() async {
    return ConfigLoadResult(config: current, warning: loadWarning);
  }

  @override
  Stream<AppConfig> get changes =>
      CancelFailingStream<AppConfig>(_changes.stream, () => cancelError);

  @override
  Future<void> write(AppConfig config) async {
    final gate = writeGate;
    if (gate != null) {
      await gate.future;
    }
    if (rejects?.call(config) ?? false) {
      throw rejectError ??
          ArgumentError.value(
            config,
            'config',
            'activePresetId names no preset in presets',
          );
    }
    final error = writeError;
    if (error != null) {
      throw error;
    }
    current = config;
    writes.add(config);
    _changes.add(config);
    onWriteComplete?.call();
  }

  /// Pushes an error onto [changes] — a store whose file watcher failed.
  /// The port promises a plain value stream, so this is contract-breaking
  /// behaviour a resident daemon must nevertheless survive.
  void emitChangesError(Object error) => _changes.addError(error);

  /// Closes the changes stream. Test teardown only — not part of the port.
  void dispose() {
    unawaited(_changes.close());
  }
}
