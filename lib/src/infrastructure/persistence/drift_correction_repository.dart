import 'dart:math';

import 'package:drift/drift.dart';

import '../../domain/correction/correction_event.dart';
import '../../domain/correction/correction_outcome.dart';
import '../../domain/correction/correction_record.dart';
import '../../domain/correction/suggestion.dart';
import '../../domain/correction/suggestion_register.dart';
import '../../domain/history/correction_repository.dart';
// Prefixed: drift generates a `Suggestion` row class from AD-7's `suggestions`
// table, and the domain already owns that name.
import 'app_database.dart' as history;

/// CAP-7 history on drift, mapping [CorrectionRecord] straight onto AD-7's two
/// tables with no intermediate model.
///
/// Row ids stay inside this class, and `created_at` is whatever the record
/// already carries — the timestamp comes from the `Clock` port via the
/// controller, never from here.
final class DriftCorrectionRepository implements CorrectionRepository {
  DriftCorrectionRepository(this._database);

  final history.AppDatabase _database;

  @override
  Future<void> save(CorrectionRecord record) async {
    // `async`, so a rejected record arrives as a failed future like every other
    // save failure rather than as a synchronous throw the sole caller —
    // which fires `save` unawaited — would not be positioned to catch.
    _rejectContradictoryRecord(record);

    // One write per correction: a suggestion insert that fails must not leave
    // a parentless corrections row behind.
    return _database.transaction(() async {
      final correctionId = await _database
          .into(_database.corrections)
          .insert(_correctionRow(record));

      for (final suggestion in record.suggestions) {
        await _database
            .into(_database.suggestions)
            .insert(_suggestionRow(correctionId, suggestion));
      }
    });
  }

  @override
  Future<List<CorrectionRecord>> recent({required int limit}) async {
    RangeError.checkNotNegative(limit, 'limit');

    final corrections =
        await (_database.select(_database.corrections)
              // `id` breaks ties so two corrections sharing a millisecond
              // still come back newest-first deterministically.
              ..orderBy([
                (row) => OrderingTerm.desc(row.createdAt),
                (row) => OrderingTerm.desc(row.id),
              ])
              ..limit(limit))
            .get();

    final suggestionsByCorrectionId = await _suggestionsFor(
      corrections.map((correction) => correction.id),
    );

    return [
      for (final correction in corrections)
        _toRecord(
          correction,
          suggestionsByCorrectionId[correction.id] ?? const [],
        ),
    ];
  }

  /// Refuses a record whose columns would each be legal while the row as a
  /// whole contradicts [CorrectionRecord]'s invariants.
  ///
  /// [_toRecord] already rejects such a row on the way out, for the reason
  /// that it is an assert on the domain type and a release build strips
  /// asserts. That reasoning is symmetric: without this check, the same
  /// stripped build lets `save` write a row that every later `recent` refuses
  /// to read — and the port has no delete, so the history stays unreadable.
  /// Better to reject the write than to persist the poison.
  ///
  /// This deliberately does not check for repeated registers: AD-7's composite
  /// primary key owns that, and the intent requires the rejection to arrive as
  /// a rolled-back transaction from the database.
  void _rejectContradictoryRecord(CorrectionRecord record) {
    final failed = record.outcome == CorrectionOutcome.failed;

    if (failed != (record.failureKind != null)) {
      throw ArgumentError.value(
        record,
        'record',
        "outcome '${record.outcome.name}' with failure kind "
            "'${record.failureKind?.name ?? 'none'}' — failureKind is set if "
            'and only if the correction failed',
      );
    }
    if (failed && record.suggestions.isNotEmpty) {
      throw ArgumentError.value(
        record,
        'record',
        "outcome 'failed' with ${record.suggestions.length} suggestion(s) — "
            'a failed correction produced none',
      );
    }
  }

  history.CorrectionsCompanion _correctionRow(CorrectionRecord record) {
    return history.CorrectionsCompanion.insert(
      createdAt: record.createdAtMillis,
      inputText: record.inputText,
      presetId: record.presetId,
      providerId: record.providerId,
      model: record.model,
      latencyMs: record.latencyMs,
      outcome: record.outcome.name,
      failureKind: Value(record.failureKind?.name),
    );
  }

  history.SuggestionsCompanion _suggestionRow(
    int correctionId,
    Suggestion suggestion,
  ) {
    return history.SuggestionsCompanion.insert(
      correctionId: correctionId,
      register: suggestion.register.name,
      suggestionText: suggestion.text,
    );
  }

  /// Every suggestion belonging to [correctionIds], grouped by correction and
  /// already in `SuggestionRegister` declaration order (AD-6).
  Future<Map<int, List<Suggestion>>> _suggestionsFor(
    Iterable<int> correctionIds,
  ) async {
    if (correctionIds.isEmpty) {
      return const {};
    }

    final grouped = <int, List<Suggestion>>{};
    // `isIn` binds one SQL variable per id and sqlite caps those at 32766, so
    // a large `limit` would fail at the driver rather than return history.
    for (final chunk in _chunked(correctionIds.toList(), 500)) {
      final rows = await (_database.select(
        _database.suggestions,
      )..where((row) => row.correctionId.isIn(chunk))).get();

      for (final row in rows) {
        grouped
            .putIfAbsent(row.correctionId, () => [])
            .add(
              Suggestion(
                register: _decodeEnum(
                  SuggestionRegister.values,
                  row.register,
                  'register',
                ),
                text: row.suggestionText,
              ),
            );
      }
    }
    for (final suggestions in grouped.values) {
      suggestions.sort((a, b) => a.register.index.compareTo(b.register.index));
    }
    return grouped;
  }

  static Iterable<List<int>> _chunked(List<int> ids, int size) sync* {
    for (var start = 0; start < ids.length; start += size) {
      yield ids.sublist(start, min(start + size, ids.length));
    }
  }

  CorrectionRecord _toRecord(
    history.Correction correction,
    List<Suggestion> suggestions,
  ) {
    final storedFailureKind = correction.failureKind;
    final outcome = _decodeEnum(
      CorrectionOutcome.values,
      correction.outcome,
      'outcome',
    );
    final failureKind = storedFailureKind == null
        ? null
        : _decodeEnum(
            CorrectionFailureKind.values,
            storedFailureKind,
            'failure_kind',
          );

    // Each column can hold a legal enum name while the row as a whole
    // contradicts CorrectionRecord's invariants. Those invariants are asserts,
    // which a release build strips, so without this check `recent` would hand
    // the panel a record violating its own contract instead of reporting the
    // corrupt history the StateError path already exists to report.
    if ((outcome == CorrectionOutcome.failed) != (failureKind != null)) {
      throw StateError(
        "Unreadable history: outcome '${correction.outcome}' with "
        "failure_kind '${storedFailureKind ?? 'NULL'}' — failure_kind is set "
        'if and only if the correction failed',
      );
    }
    if (outcome == CorrectionOutcome.failed && suggestions.isNotEmpty) {
      throw StateError(
        "Unreadable history: outcome 'failed' with ${suggestions.length} "
        'suggestion row(s) — a failed correction produced none',
      );
    }

    return CorrectionRecord(
      createdAtMillis: correction.createdAt,
      inputText: correction.inputText,
      presetId: correction.presetId,
      providerId: correction.providerId,
      model: correction.model,
      latencyMs: correction.latencyMs,
      outcome: outcome,
      failureKind: failureKind,
      // Unmodifiable: the list handed over here is the growable one built by
      // `_suggestionsFor` (and sorted in place), so without this a caller
      // could mutate history it was only meant to read — and it would succeed
      // on a completed record while throwing on a failed one, whose empty
      // suggestions are a `const []`.
      suggestions: List.unmodifiable(suggestions),
    );
  }

  /// AD-6: enums are stored by `.name`. A stored value outside the enum cannot
  /// have been written by this app, so it is a corrupt database rather than an
  /// expected failure the panel could render.
  T _decodeEnum<T extends Enum>(List<T> values, String stored, String column) {
    for (final value in values) {
      if (value.name == stored) {
        return value;
      }
    }
    throw StateError(
      "Unreadable history: column '$column' holds '$stored', which is not a "
      '$T value',
    );
  }
}
