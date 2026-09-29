import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/correction/correction_record.dart';
import 'package:hotkey_grammar_corrector/src/domain/history/correction_repository.dart';

final class FakeCorrectionRepository implements CorrectionRepository {
  /// Every successfully saved record, in save order, for assertions.
  final List<CorrectionRecord> saved = [];

  /// Every record [save] was *called* with, including the ones [saveError]
  /// rejected. AD-7 allows exactly one attempt per terminal event, so a test
  /// that asserts "never retried" reads this rather than [saved].
  final List<CorrectionRecord> saveAttempts = [];

  /// When set, [save] returns a rejected future and records nothing.
  ///
  /// Rejected rather than thrown synchronously, matching
  /// `DriftCorrectionRepository.save`: the two shapes strand the controller
  /// differently, and only the rejecting one is the real contract.
  Object? saveError;

  /// When set, [save] parks on this before recording anything.
  ///
  /// A real history write is SQLite on disk and does not land instantly, so a
  /// terminal event arriving as the daemon exits leaves a write in flight.
  /// This is what lets a test hold one open across `dispose()` and prove
  /// shutdown waits for it (CAP-7 retains every correction).
  Completer<void>? saveGate;

  @override
  Future<void> save(CorrectionRecord record) async {
    saveAttempts.add(record);
    await saveGate?.future;
    final error = saveError;
    if (error != null) {
      throw error;
    }
    saved.add(record);
  }

  @override
  Future<List<CorrectionRecord>> recent({required int limit}) async {
    RangeError.checkNotNegative(limit, 'limit');
    return saved.reversed.take(limit).toList();
  }
}
