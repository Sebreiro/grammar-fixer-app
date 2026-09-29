import '../correction/correction_record.dart';

/// Persists correction history (CAP-7, AD-7 shape).
///
/// The correction controller is the sole caller of [save], exactly once per
/// correction, at the terminal event. Provider adapters never persist.
abstract interface class CorrectionRepository {
  Future<void> save(CorrectionRecord record);

  /// The most recent records, newest first. [limit] must be non-negative;
  /// a negative limit is programmer error ([RangeError]).
  Future<List<CorrectionRecord>> recent({required int limit});
}
