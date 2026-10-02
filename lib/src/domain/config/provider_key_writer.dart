import 'secret_write_result.dart';

/// Stores an explicitly entered provider credential.
abstract interface class ProviderKeyWriter {
  /// Replaces the matching key and reports whether persistence succeeded.
  Future<SecretWriteResult> writeProviderKey(String providerId, String apiKey);
}
