import '../../domain/config/app_config.dart';
import '../../domain/config/config_store.dart';
import '../../domain/config/config_write_conflict.dart';
import '../../domain/config/provider_config.dart';
import '../../domain/config/provider_key_writer.dart';
import '../../domain/config/secret_write_result.dart';
import 'provider_secret_fields.dart';

/// Prefers the desktop keyring and persists inaccessible writes through config.
final class ConfigFallbackProviderKeyWriter implements ProviderKeyWriter {
  const ConfigFallbackProviderKeyWriter({
    required this._keyring,
    required this._configStore,
  });

  final ProviderKeyWriter _keyring;
  final ConfigStore _configStore;

  @override
  Future<SecretWriteResult> writeProviderKey(
    String providerId,
    String apiKey,
  ) async {
    final key = apiKey.trim();
    if (key.isEmpty) return SecretWriteResult.unavailable;
    final result = await _writeToKeyring(providerId, key);
    if (result == SecretWriteResult.saved) return result;
    return _writeToConfig(providerId, key);
  }

  Future<SecretWriteResult> _writeToKeyring(
    String providerId,
    String apiKey,
  ) async {
    try {
      return await _keyring.writeProviderKey(providerId, apiKey);
    } on Object {
      // A broken adapter must still allow the authorized config destination.
      return SecretWriteResult.unavailable;
    }
  }

  Future<SecretWriteResult> _writeToConfig(
    String providerId,
    String apiKey,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final config = _withApiKey(_configStore.current, providerId, apiKey);
        await _configStore.write(config);
        return SecretWriteResult.saved;
      } on ConfigWriteConflict {
        // ConfigStore exposes the hand edit as current; merge into it again.
      } on Object {
        // Return failure without exposing exception payloads containing keys.
        return SecretWriteResult.unavailable;
      }
    }
    return SecretWriteResult.unavailable;
  }

  static AppConfig _withApiKey(
    AppConfig config,
    String providerId,
    String apiKey,
  ) => config.copyWith(
    providers: Map.unmodifiable({
      ...config.providers,
      providerId: ProviderConfig(
        settings: Map.unmodifiable({
          ...?config.providers[providerId]?.settings,
          ProviderSecretFields.configKey: apiKey,
        }),
      ),
    }),
  );
}
