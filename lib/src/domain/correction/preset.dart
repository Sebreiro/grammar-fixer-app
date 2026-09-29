/// Prompt and model, bound as one unit. Never separated.
final class Preset {
  const Preset({
    required this.id,
    required this.providerId,
    required this.model,
    required this.systemPrompt,
  });
  final String id;
  final String providerId;
  final String model;
  final String systemPrompt;

  /// Value equality, added to AD-2's declaration without touching its fields:
  /// `AppConfig` holds a `List<Preset>` and cannot compare by value while its
  /// elements compare by identity.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Preset &&
        id == other.id &&
        providerId == other.providerId &&
        model == other.model &&
        systemPrompt == other.systemPrompt;
  }

  @override
  int get hashCode => Object.hash(id, providerId, model, systemPrompt);
}
