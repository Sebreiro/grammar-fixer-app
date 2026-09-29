import '../../domain/config/app_config.dart';
import '../../domain/correction/correction_provider.dart';
import '../../domain/correction/preset.dart';
import '../../domain/logger.dart';
import '../config/default_app_config.dart';
import 'provider_registry.dart';
import 'unconfigured_correction_provider.dart';

/// AD-5's single active pair: the one `(CorrectionProvider, Preset)` the
/// composition root injects, and the only place selection happens.
///
/// It lives here rather than inside `main.dart` so the resolution rules — the
/// registry lookup (AD-15), the unknown-provider degradation (AD-19) and the
/// dangling-preset backstop — are reachable by a test, while the code stays
/// composition-root code. Nothing below this point selects a provider or sees
/// a model id without its prompt.
final class ActiveCorrection {
  const ActiveCorrection({required this.provider, required this.preset});

  final CorrectionProvider provider;

  /// Prompt and model together, always (AD-5).
  final Preset preset;

  /// Resolves the pair [config] describes, degrading rather than failing.
  ///
  /// Startup never depends on the answer being good: a preset id that names
  /// nothing falls back to the shipped preset, and a provider this build does
  /// not ship — or that the config never described — yields a provider that
  /// reports `providerUnavailable` on the first correction (AD-19). Both are
  /// logged, because both mean the user's config says something the daemon
  /// could not honour.
  static ActiveCorrection resolve({
    required AppConfig config,
    required ProviderRegistry registry,
    required Logger logger,
  }) {
    final preset = _activePreset(config, logger);
    return ActiveCorrection(
      provider: _providerFor(preset, config, registry, logger),
      preset: preset,
    );
  }

  /// The preset `activePresetId` names. `ConfigStore` validates that cross
  /// reference (AD-13), so a miss here is a breach of its contract — but a
  /// daemon with no preset could not correct at all, so it is reported and the
  /// shipped preset stands in.
  static Preset _activePreset(AppConfig config, Logger logger) {
    for (final preset in config.presets) {
      if (preset.id == config.activePresetId) {
        return preset;
      }
    }
    logger.error(
      'the active preset id names no preset; using the shipped preset',
      context: {
        'active_preset_id': config.activePresetId,
        'preset_id': DefaultAppConfig.shippedPresetId,
      },
    );
    return DefaultAppConfig.shippedPreset;
  }

  static CorrectionProvider _providerFor(
    Preset preset,
    AppConfig config,
    ProviderRegistry registry,
    Logger logger,
  ) {
    final providerConfig = config.providers[preset.providerId];
    if (providerConfig == null) {
      return _unavailable(
        logger,
        preset,
        'is not described in the config file',
        'the active preset names a provider the config does not describe',
      );
    }
    // AD-15: a map lookup, never a `switch (providerId)`.
    final provider = registry.create(preset.providerId, providerConfig);
    if (provider == null) {
      return _unavailable(
        logger,
        preset,
        'is not a provider this build ships',
        'the active preset names a provider this build does not ship',
      );
    }
    return provider;
  }

  static UnconfiguredCorrectionProvider _unavailable(
    Logger logger,
    Preset preset,
    String problem,
    String logMessage,
  ) {
    logger.warning(
      logMessage,
      context: {'preset_id': preset.id, 'provider_id': preset.providerId},
    );
    return UnconfiguredCorrectionProvider(
      // CAP-13 renders this inline in the panel, so it is a sentence naming
      // the setting the user has to fix. Ids are config values the user wrote
      // themselves, never clipboard-derived content.
      message:
          'the configured provider "${preset.providerId}" $problem, so no '
          'correction can run. Fix the active preset in the config file.',
    );
  }
}
