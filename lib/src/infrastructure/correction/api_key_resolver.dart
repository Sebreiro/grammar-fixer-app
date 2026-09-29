import '../../domain/config/provider_config.dart';
import '../../domain/config/secret_store.dart';
import '../config/provider_secret_fields.dart';
import 'api_key_source.dart';

/// Resolves one credential for the selected OpenAI-compatible adapter.
///
/// Call [sourceForSettings] when only the label is needed; it never returns
/// key text to UI code. No lookup writes to Secret Service or configuration.
final class ApiKeyResolver {
  const ApiKeyResolver(this._secretStore, this._environment);

  final SecretStore _secretStore;
  final Map<String, String> _environment;

  Future<({String? apiKey, ApiKeySource source})> resolve(
    ProviderConfig config,
  ) async {
    final keyring = await _secretStore.readProviderKey(
      ProviderSecretFields.providerId,
    );
    if (keyring case SecretFound(value: final value)) {
      final key = _usable(value);
      if (key != null) {
        return (apiKey: key, source: ApiKeySource.systemKeyring);
      }
    }

    final fromEnvironment = _usable(
      _environment[ProviderSecretFields.environmentKey],
    );
    if (fromEnvironment != null) {
      return (apiKey: fromEnvironment, source: ApiKeySource.environment);
    }

    final fromConfig = _usable(config.settings[ProviderSecretFields.configKey]);
    if (fromConfig != null) {
      return (apiKey: fromConfig, source: ApiKeySource.configFile);
    }
    // Local Ollama may accept a request without a bearer header.
    return (apiKey: null, source: ApiKeySource.none);
  }

  Future<ApiKeySource> sourceForSettings(ProviderConfig config) async {
    final result = await resolve(config);
    return result.source;
  }

  static String? _usable(String? value) {
    final candidate = value?.trim();
    return candidate == null || candidate.isEmpty ? null : candidate;
  }
}
