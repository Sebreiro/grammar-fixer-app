/// The outcome of one read-only lookup in the desktop's secret store.
///
/// An unavailable service includes a locked matching item. Callers may use
/// another configured source without prompting to unlock the desktop keyring.
sealed class SecretLookup {
  const SecretLookup();
}

final class SecretFound extends SecretLookup {
  const SecretFound(this.value);

  final String value;
}

final class SecretAbsent extends SecretLookup {
  const SecretAbsent();
}

final class SecretUnavailable extends SecretLookup {
  const SecretUnavailable();
}

/// Reads a provider credential without creating, changing, or unlocking it.
abstract interface class SecretStore {
  Future<SecretLookup> readProviderKey(String providerId);
}
