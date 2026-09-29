import '../../domain/config/provider_config.dart';
import '../../domain/correction/correction_provider.dart';
import '../../domain/logger.dart';
import 'claude_agent_sdk/claude_agent_sdk_correction_provider.dart';
import 'api_key_resolver.dart';
import 'openai_compatible/openai_compatible_correction_provider.dart';

/// The id → factory table the composition root looks providers up in
/// (AD-15): adding a provider is adding one map entry here, never a
/// `switch` in the correction pipeline.
final class ProviderRegistry {
  // Named once here rather than inline, so the settings contract reads as
  // one line each and stays tied to the adapter that owns the keys.
  static const _interpreterKey =
      ClaudeAgentSdkCorrectionProvider.interpreterSettingsKey;
  static const _sidecarKey =
      ClaudeAgentSdkCorrectionProvider.sidecarSettingsKey;
  static const _timeoutKey =
      ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey;

  ProviderRegistry({required Logger logger, ApiKeyResolver? apiKeyResolver})
    : _factories = {
        ClaudeAgentSdkCorrectionProvider
            .providerId: (config) => ClaudeAgentSdkCorrectionProvider(
          // Missing settings still construct a provider: it reports
          // providerUnavailable on the first correct() instead, because a
          // half-configured provider must never block daemon startup (AD-19).
          interpreterPath: config.settings[_interpreterKey] ?? '',
          sidecarPath: config.settings[_sidecarKey] ?? '',
          logger: logger,
          timeout: _timeoutFrom(config, logger),
        ),
        OpenAiCompatibleCorrectionProvider.providerId: (config) =>
            OpenAiCompatibleCorrectionProvider(
              baseUrl:
                  config.settings[OpenAiCompatibleCorrectionProvider
                      .baseUrlSettingsKey] ??
                  '',
              resolveApiKey: apiKeyResolver == null
                  ? null
                  : () async => (await apiKeyResolver.resolve(config)).apiKey,
            ),
      };

  final Map<String, CorrectionProvider Function(ProviderConfig)> _factories;

  /// null means "no such provider id" — the caller decides how to surface
  /// a config that names a provider this build does not ship.
  CorrectionProvider? create(String id, ProviderConfig config) =>
      _factories[id]?.call(config);

  /// Above this a value has stopped being a bound. `int.tryParse` accepts
  /// numbers that overflow [Duration]: `9223372036854775807` yields a
  /// negative `inMilliseconds`, so the deadline fires instantly and every
  /// correction fails as timeout, and `999999999999999999` wraps to roughly
  /// geological time — silently reinstating the exact hang AD-19 exists to
  /// prevent. A day is far past any correction anyone would wait for.
  static const int _maxTimeoutMillis = 24 * 60 * 60 * 1000;

  /// The AD-19 timeout, which lives in the settings map and nowhere else so
  /// the value has exactly one home. An absent key takes the adapter's own
  /// default silently; a key the user got wrong takes it loudly, because a
  /// typo that silently reinstates the default is the kind of thing nobody
  /// notices until a correction hangs for a minute.
  static Duration _timeoutFrom(ProviderConfig config, Logger logger) {
    final raw = config.settings[_timeoutKey];
    if (raw == null) {
      return ClaudeAgentSdkCorrectionProvider.defaultTimeout;
    }
    final millis = int.tryParse(raw);
    // The three rejections read differently on purpose: telling an operator
    // that "0" is unparseable sends them hunting for a typo instead of
    // looking at what they meant.
    if (millis == null) {
      return _rejected(logger, raw, 'is not a whole number of milliseconds');
    }
    if (millis <= 0) {
      return _rejected(logger, raw, 'must be greater than zero');
    }
    if (millis > _maxTimeoutMillis) {
      return _rejected(
        logger,
        raw,
        'must be at most $_maxTimeoutMillis ms (one day)',
      );
    }
    return Duration(milliseconds: millis);
  }

  static Duration _rejected(Logger logger, String raw, String problem) {
    const fallback = ClaudeAgentSdkCorrectionProvider.defaultTimeout;
    logger.warning(
      'the provider setting "$_timeoutKey" $problem; using the default',
      context: {
        'key': _timeoutKey,
        'value': raw,
        'usingDefaultMillis': fallback.inMilliseconds,
      },
    );
    return fallback;
  }
}
