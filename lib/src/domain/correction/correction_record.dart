import '../collection_equality.dart';
import 'correction_event.dart';
import 'correction_outcome.dart';
import 'suggestion.dart';

/// One persisted correction — input, suggestions, and provenance (AD-7 shape).
///
/// `providerId`, `model`, and `presetId` are load-bearing, not metadata:
/// history without them cannot be read once the operator switches provider or
/// model. Database ids never leave the repository, so there is no id field.
final class CorrectionRecord {
  const CorrectionRecord({
    required this.createdAtMillis,
    required this.inputText,
    required this.presetId,
    required this.providerId,
    required this.model,
    required this.latencyMs,
    required this.outcome,
    required this.suggestions,
    this.failureKind,
  }) : assert(
         (outcome == CorrectionOutcome.failed) == (failureKind != null),
         'failureKind is present exactly when the outcome is failed',
       ),
       assert(
         outcome == CorrectionOutcome.completed || suggestions.length == 0,
         'suggestions must be empty when the correction failed',
       );

  /// Unix milliseconds UTC, obtained from the Clock port.
  final int createdAtMillis;

  /// The edited text actually sent (CAP-3).
  final String inputText;

  final String presetId;
  final String providerId;
  final String model;
  final int latencyMs;
  final CorrectionOutcome outcome;

  /// Null when the correction completed.
  final CorrectionFailureKind? failureKind;

  /// Empty when the correction failed.
  final List<Suggestion> suggestions;

  /// Value equality, so two records built separately from the same correction
  /// compare as the same record. [suggestions] compares in order: AD-6 makes
  /// register order the panel order and the 1/2/3 key mapping, so two records
  /// whose suggestions are permuted are not the same record.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CorrectionRecord &&
        createdAtMillis == other.createdAtMillis &&
        inputText == other.inputText &&
        presetId == other.presetId &&
        providerId == other.providerId &&
        model == other.model &&
        latencyMs == other.latencyMs &&
        outcome == other.outcome &&
        failureKind == other.failureKind &&
        listEquals(suggestions, other.suggestions);
  }

  @override
  int get hashCode => Object.hash(
    createdAtMillis,
    inputText,
    presetId,
    providerId,
    model,
    latencyMs,
    outcome,
    failureKind,
    listHash(suggestions),
  );
}
