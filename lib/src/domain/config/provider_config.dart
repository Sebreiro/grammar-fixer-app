import '../collection_equality.dart';

/// Configuration for one described provider, keyed by provider id in
/// the AppConfig providers map.
///
/// The settings are opaque to the domain: AD-15 keeps every transport detail
/// (executable path, endpoint, key name) inside the provider's own adapter,
/// so only that adapter interprets its entry.
///
/// Collection ownership: the const constructor cannot defensively copy, so
/// callers hand over an unowned (ideally const) map and never mutate it
/// after construction.
final class ProviderConfig {
  const ProviderConfig({required this.settings});
  final Map<String, String> settings;

  static const compatibleProviderId = 'openai-compatible';
  static const baseUrlSetting = 'baseUrl';

  /// The in-app editor permits only a destination the HTTP adapter can use
  /// without sending drafts or credentials over a remote plaintext connection.
  static String? baseUrlProblem(String value) {
    final base = Uri.tryParse(value.trim());
    if (base == null ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      return 'Enter a valid Base URL without credentials, query, or fragment.';
    }
    final loopback =
        base.host == 'localhost' ||
        base.host == '127.0.0.1' ||
        base.host == '::1';
    if (base.scheme != 'https' && !(base.scheme == 'http' && loopback)) {
      return 'Use HTTPS, or HTTP for an explicit loopback address.';
    }
    return null;
  }

  /// Value equality, with [settings] compared as a map — `AppConfig` holds
  /// these in a map of its own and cannot compare by value while its values
  /// compare by identity.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ProviderConfig && mapEquals(settings, other.settings);
  }

  @override
  int get hashCode => mapHash(settings);
}
