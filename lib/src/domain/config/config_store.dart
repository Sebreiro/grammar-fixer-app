import 'app_config.dart';
import 'config_load_result.dart';

/// Sole owner of the config file (AD-13): all reads, validation, and writes
/// happen here, and every settings mutation writes through this port.
///
/// This is also the single validation point for cross-field references:
/// `activePresetId` must name a preset in `presets`, and every
/// `preset.providerId` must name an entry in `providers`. Nothing downstream
/// re-validates.
abstract interface class ConfigStore {
  /// Reads the config file once at startup and makes its value [current].
  /// A malformed file yields defaults plus a surfaced warning (AD-13) —
  /// loading never throws for a bad file.
  Future<ConfigLoadResult> load();

  /// The most recently loaded or written value. Reading before [load]
  /// completes is programmer error — adapters throw [StateError].
  AppConfig get current;

  /// Emits after every successful [write]. Broadcast: a state-change
  /// notification stream with multiple independent listeners (settings UI,
  /// composition root).
  Stream<AppConfig> get changes;

  /// Persists [config] to the file and makes it [current]. Validates the
  /// cross-field references documented on this port before writing.
  Future<void> write(AppConfig config);
}
