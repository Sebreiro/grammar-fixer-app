/// Names shared by config persistence and the selected provider's secret edge.
final class ProviderSecretFields {
  const ProviderSecretFields._();

  static const providerId = 'openai-compatible';
  static const configKey = 'apiKey';
  static const environmentKey = 'OPENAI_API_KEY';
}
