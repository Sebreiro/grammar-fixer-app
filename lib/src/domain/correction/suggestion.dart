import 'suggestion_register.dart';

/// One register variant of a correction. The same shape the history DB persists.
final class Suggestion {
  const Suggestion({required this.register, required this.text});
  final SuggestionRegister register;
  final String text;

  /// Value equality, added to AD-2's declaration without touching its fields:
  /// `CorrectionRecord` holds a `List<Suggestion>` and cannot compare by value
  /// while its elements compare by identity.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Suggestion &&
        register == other.register &&
        text == other.text;
  }

  @override
  int get hashCode => Object.hash(register, text);
}
