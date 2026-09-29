import 'suggestion.dart';
import 'suggestion_register.dart';

sealed class CorrectionEvent {
  const CorrectionEvent();
}

/// Streamed partial text appended to one register's slot (CAP-5).
final class SuggestionDelta extends CorrectionEvent {
  const SuggestionDelta({required this.register, required this.textDelta});
  final SuggestionRegister register;
  final String textDelta;
}

/// Terminal. Carries exactly one Suggestion per SuggestionRegister value.
final class CorrectionCompleted extends CorrectionEvent {
  const CorrectionCompleted({required this.suggestions});
  final List<Suggestion> suggestions;
}

/// Terminal. Rendered inline in the panel with a Retry action (CAP-13).
final class CorrectionFailed extends CorrectionEvent {
  const CorrectionFailed({required this.kind, required this.message});
  final CorrectionFailureKind kind;
  final String message;

  /// Value equality, added to AD-2's declaration without touching its fields:
  /// `CorrectionState` holds this as its rendered failure, so the state cannot
  /// compare by value while this compares by identity.
  ///
  /// [SuggestionDelta] and [CorrectionCompleted] deliberately keep identity
  /// equality: neither is held by anything that needs deduping, and equality
  /// is added where a consumer needs it rather than everywhere it could go.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CorrectionFailed &&
        kind == other.kind &&
        message == other.message;
  }

  @override
  int get hashCode => Object.hash(kind, message);
}

enum CorrectionFailureKind {
  timeout,
  providerUnavailable,
  providerError,
  malformedResponse,
}
