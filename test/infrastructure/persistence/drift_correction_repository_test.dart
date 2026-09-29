import 'dart:io';

// `show`n narrowly: drift's query builder exports an `isNull` that would
// shadow the matcher of the same name.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_record.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
// Prefixed: the generated library exposes a `Suggestion` row class that would
// otherwise collide with the domain type under test.
import 'package:hotkey_grammar_corrector/src/infrastructure/persistence/app_database.dart'
    as history;
import 'package:hotkey_grammar_corrector/src/infrastructure/persistence/drift_correction_repository.dart';
import 'package:test/test.dart';

/// CAP-7 history persistence over drift. Everything here runs headless on
/// NativeDatabase — in memory, except the restart test, which needs a real
/// file to be able to reopen it (AGENTS.md §7: no Flutter binding).
void main() {
  late history.AppDatabase database;
  late DriftCorrectionRepository repository;

  setUp(() {
    database = history.AppDatabase(NativeDatabase.memory());
    repository = DriftCorrectionRepository(database);
  });
  tearDown(() => database.close());

  group('save', () {
    test(
      'CAP-7: a completed correction writes one row and three suggestions',
      () async {
        await repository.save(_completed());

        final corrections = await _rows(database, 'corrections');
        expect(corrections, hasLength(1));
        expect(corrections.single['outcome'], 'completed');
        expect(corrections.single['failure_kind'], isNull);
        expect(corrections.single['created_at'], 1700000000000);
        expect(corrections.single['input_text'], 'i has bad grammar');
        expect(
          corrections.single['preset_id'],
          'default-formal-casual-shorter',
        );
        expect(corrections.single['provider_id'], 'claude-agent-sdk');
        expect(corrections.single['model'], 'claude-sonnet-5');
        expect(corrections.single['latency_ms'], 812);

        final suggestions = await _rows(database, 'suggestions');
        expect(
          suggestions.map((row) => row['register']),
          containsAll(<String>['formal', 'casual', 'shorter']),
        );
        expect(suggestions, hasLength(3));
        expect(
          suggestions.every(
            (row) => row['correction_id'] == corrections.single['id'],
          ),
          isTrue,
        );
      },
    );

    test(
      'CAP-7: a failed correction writes its kind and no suggestions',
      () async {
        await repository.save(_failed());

        final corrections = await _rows(database, 'corrections');
        expect(corrections, hasLength(1));
        expect(corrections.single['outcome'], 'failed');
        expect(corrections.single['failure_kind'], 'timeout');

        expect(await _rows(database, 'suggestions'), isEmpty);
      },
    );

    test('CAP-7: enums are stored by name, never by index', () async {
      await repository.save(_completed());
      await repository.save(_failed());

      // Asserting the literal names, not just `isA<String>()`: an
      // index-storing implementation writing '0'/'1' into these TEXT columns
      // would satisfy a type check and still break AD-6 the moment someone
      // reorders an enum.
      expect(
        (await _rows(database, 'suggestions')).map((row) => row['register']),
        containsAll(<String>['formal', 'casual', 'shorter']),
      );
      final corrections = await _rows(database, 'corrections');
      expect(
        corrections.map((row) => row['outcome']),
        containsAll(<String>['completed', 'failed']),
      );
      expect(
        corrections.map((row) => row['failure_kind']),
        contains('timeout'),
      );
      expect(
        SuggestionRegister.formal.index,
        0,
        reason:
            'formal is index 0, so a stored "0" would prove index storage; '
            'the assertions above prove it is the name that is stored',
      );
    });

    test(
      'CAP-7: saving the same content twice keeps two separate records',
      () async {
        await repository.save(_completed());
        await repository.save(_completed());

        expect(await _rows(database, 'corrections'), hasLength(2));
        expect(await _rows(database, 'suggestions'), hasLength(6));
        expect(await repository.recent(limit: 10), hasLength(2));
      },
    );

    test(
      'CAP-7: a failing suggestion insert rolls the whole write back',
      () async {
        // Two suggestions in the same register violate AD-7's composite primary
        // key, so the second insert fails after the correction row is in.
        final duplicated = CorrectionRecord(
          createdAtMillis: 1700000000000,
          inputText: 'i has bad grammar',
          presetId: 'default-formal-casual-shorter',
          providerId: 'claude-agent-sdk',
          model: 'claude-sonnet-5',
          latencyMs: 812,
          outcome: CorrectionOutcome.completed,
          suggestions: const [
            Suggestion(register: SuggestionRegister.formal, text: 'One.'),
            Suggestion(register: SuggestionRegister.formal, text: 'Two.'),
          ],
        );

        // Named precisely: `isA<Exception>()` would also pass if `save` blew
        // up before the first insert, which is the very failure this test
        // exists to distinguish from a correct rollback.
        await expectLater(
          repository.save(duplicated),
          throwsA(
            isA<SqliteException>().having(
              (error) => error.message,
              'message',
              contains('UNIQUE constraint failed'),
            ),
          ),
        );

        expect(await _rows(database, 'corrections'), isEmpty);
        expect(await _rows(database, 'suggestions'), isEmpty);
      },
    );

    test(
      'CAP-7: a record contradicting its own invariants is refused, not stored',
      () async {
        // CorrectionRecord carries these invariants as asserts, which a release
        // build strips — which is exactly why the read path re-checks them. The
        // write path has to refuse them too: the port has no delete, so a row
        // that only `recent` rejects would make history unreadable for good.
        //
        // Reaching the guard from a test needs the record to become
        // contradictory after construction, since this VM runs with asserts on.
        // Its suggestion list is growable, so that is the available route.
        final suggestions = <Suggestion>[];
        final record = CorrectionRecord(
          createdAtMillis: 1700000000000,
          inputText: 'i has bad grammar',
          presetId: 'default-formal-casual-shorter',
          providerId: 'claude-agent-sdk',
          model: 'claude-sonnet-5',
          latencyMs: 30000,
          outcome: CorrectionOutcome.failed,
          failureKind: CorrectionFailureKind.timeout,
          suggestions: suggestions,
        );
        suggestions.add(
          const Suggestion(
            register: SuggestionRegister.formal,
            text: 'Should not exist.',
          ),
        );

        await expectLater(
          repository.save(record),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              allOf(contains('failed'), contains('suggestion')),
            ),
          ),
        );

        expect(await _rows(database, 'corrections'), isEmpty);
        expect(await _rows(database, 'suggestions'), isEmpty);
      },
    );
  });

  group('recent', () {
    test('CAP-7: returns newest first, capped at limit', () async {
      await repository.save(_completed(createdAtMillis: 1000, inputText: 'a'));
      await repository.save(_completed(createdAtMillis: 2000, inputText: 'b'));
      await repository.save(_completed(createdAtMillis: 3000, inputText: 'c'));

      final recent = await repository.recent(limit: 2);

      expect(recent.map((record) => record.inputText), ['c', 'b']);
    });

    test('CAP-7: suggestions come back in SuggestionRegister order', () async {
      await repository.save(
        _completed(
          suggestions: const [
            Suggestion(register: SuggestionRegister.shorter, text: 'Short.'),
            Suggestion(register: SuggestionRegister.formal, text: 'Formal.'),
            Suggestion(register: SuggestionRegister.casual, text: 'Casual.'),
          ],
        ),
      );

      final recent = await repository.recent(limit: 1);

      expect(recent.single.suggestions.map((s) => s.register), [
        SuggestionRegister.formal,
        SuggestionRegister.casual,
        SuggestionRegister.shorter,
      ]);
      expect(recent.single.suggestions.map((s) => s.text), [
        'Formal.',
        'Casual.',
        'Short.',
      ]);
    });

    test(
      'CAP-7: a failed record round-trips its kind and empty suggestions',
      () async {
        await repository.save(_failed());

        final recent = await repository.recent(limit: 1);

        expect(recent.single.outcome, CorrectionOutcome.failed);
        expect(recent.single.failureKind, CorrectionFailureKind.timeout);
        expect(recent.single.suggestions, isEmpty);
      },
    );

    test('CAP-7: limit 0 returns nothing from a populated database', () async {
      await repository.save(_completed());

      expect(await repository.recent(limit: 0), isEmpty);
    });

    test('CAP-7: a negative limit is programmer error', () {
      expect(() => repository.recent(limit: -1), throwsRangeError);
    });

    test(
      'CAP-7: an unknown stored register is a corrupt-history StateError',
      () async {
        await _insertRawCorrection(database, outcome: 'completed');
        await database.customStatement(
          "INSERT INTO suggestions (correction_id, register, text) "
          "VALUES (1, 'sarcastic', 'Oh, splendid.')",
        );

        await expectLater(
          repository.recent(limit: 1),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(contains('register'), contains('sarcastic')),
            ),
          ),
        );
      },
    );

    test(
      'CAP-7: an unknown stored outcome is a corrupt-history StateError',
      () async {
        await _insertRawCorrection(database, outcome: 'abandoned');

        await expectLater(
          repository.recent(limit: 1),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(contains('outcome'), contains('abandoned')),
            ),
          ),
        );
      },
    );

    test(
      'CAP-7: an unknown stored failure kind is a corrupt-history StateError',
      () async {
        await _insertRawCorrection(
          database,
          outcome: 'failed',
          failureKind: 'meteor-strike',
        );

        await expectLater(
          repository.recent(limit: 1),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(contains('failure_kind'), contains('meteor-strike')),
            ),
          ),
        );
      },
    );

    // The three cases above hold values outside their enum. These hold values
    // that are individually legal and jointly contradict CorrectionRecord's
    // invariants — which are asserts, and therefore absent from a release
    // build, so they must be rejected here rather than left to the domain.
    test(
      'CAP-7: a completed correction carrying a failure kind is corrupt history',
      () async {
        await _insertRawCorrection(
          database,
          outcome: 'completed',
          failureKind: 'timeout',
        );

        await expectLater(
          repository.recent(limit: 1),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(contains('completed'), contains('timeout')),
            ),
          ),
        );
      },
    );

    test(
      'CAP-7: a failed correction missing its failure kind is corrupt history',
      () async {
        await _insertRawCorrection(database, outcome: 'failed');

        await expectLater(
          repository.recent(limit: 1),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('failed'),
            ),
          ),
        );
      },
    );

    test(
      'CAP-7: a failed correction carrying suggestions is corrupt history',
      () async {
        await _insertRawCorrection(
          database,
          outcome: 'failed',
          failureKind: 'timeout',
        );
        await database.customStatement(
          'INSERT INTO suggestions (correction_id, register, text) '
          "VALUES (1, 'formal', 'Should not exist.')",
        );

        await expectLater(
          repository.recent(limit: 1),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(contains('failed'), contains('suggestion')),
            ),
          ),
        );
      },
    );

    test(
      'CAP-7: one unreadable row costs the whole window, not just itself',
      () async {
        // Pins the blast radius of the StateErrors above, which every other
        // corrupt-history test leaves unobserved by seeding a database holding
        // nothing but the bad row. It is deliberately not asserting that this
        // is desirable — recovery from a corrupt history is filed as deferred
        // work — only that the contract today is all-or-nothing, so a change
        // in either direction has to be made knowingly.
        await repository.save(
          _completed(createdAtMillis: 1000, inputText: 'a'),
        );
        await repository.save(
          _completed(createdAtMillis: 2000, inputText: 'b'),
        );
        await _insertRawCorrection(
          database,
          outcome: 'abandoned',
          id: 99,
          createdAtMillis: 10,
        );

        // A window that stops above the bad row is unaffected.
        final readable = await repository.recent(limit: 2);
        expect(readable.map((record) => record.inputText), ['b', 'a']);

        // One that reaches it loses the two healthy records with it.
        await expectLater(
          repository.recent(limit: 3),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('abandoned'),
            ),
          ),
        );
      },
    );

    test(
      'CAP-7: corrections sharing a millisecond still come back newest first',
      () async {
        // Pins the `id` tie-break in recent()'s ORDER BY: with created_at
        // equal, insertion order is the only thing left to order by.
        await repository.save(
          _completed(createdAtMillis: 5000, inputText: 'a'),
        );
        await repository.save(
          _completed(createdAtMillis: 5000, inputText: 'b'),
        );
        await repository.save(
          _completed(createdAtMillis: 5000, inputText: 'c'),
        );

        final recent = await repository.recent(limit: 3);

        expect(recent.map((record) => record.inputText), ['c', 'b', 'a']);
      },
    );

    test(
      'CAP-7: history past the id-chunk boundary still carries its suggestions',
      () async {
        // `isIn` binds one variable per correction id and sqlite caps those at
        // 32766, so the suggestion read is chunked. The row count here has to
        // exceed that chunk size: at 40 records every id fits in one chunk, so
        // deleting the chunking — or dropping every chunk after the first —
        // would still pass, and the second mutation silently returns
        // suggestion-less records rather than failing loudly.
        const savedCount = 501;
        for (var i = 0; i < savedCount; i++) {
          await repository.save(
            _completed(createdAtMillis: 1000 + i, inputText: 'row $i'),
          );
        }

        final recent = await repository.recent(limit: 40000);

        expect(recent, hasLength(savedCount));
        expect(recent.first.inputText, 'row ${savedCount - 1}');
        expect(recent.last.inputText, 'row 0');
        // Asserted for every record, not just the first: the records beyond the
        // first chunk are exactly the ones a chunking regression strands.
        expect(
          recent.where((record) => record.suggestions.length == 3),
          hasLength(savedCount),
          reason:
              'every record must come back with all three registers, '
              'including those whose ids fell outside the first chunk',
        );
      },
    );
  });

  group('restart durability', () {
    late Directory temporaryDirectory;

    late bool previousWarningSetting;

    setUp(() async {
      temporaryDirectory = Directory.systemTemp.createTempSync('hgc_history_');
      // The shared in-memory database from the outer setUp is unused here and
      // would otherwise be a second live database alongside the file ones,
      // making the suppression below load-bearing rather than cosmetic. Close
      // it so the only overlap left is the one this group is actually about.
      await database.close();
      // Restart durability is exactly "two AppDatabase instances over one
      // file", which is what drift's debug warning exists to flag. These two
      // are strictly sequential — the first is closed before the second is
      // built — so the warning is noise.
      previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });
    tearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningSetting;
      temporaryDirectory.deleteSync(recursive: true);
    });

    test(
      'CAP-7: a saved correction survives reopening the database file',
      () async {
        final file = File('${temporaryDirectory.path}/history.sqlite');
        final saved = _completed();

        final firstRun = history.AppDatabase.file(file);
        await DriftCorrectionRepository(firstRun).save(saved);
        await firstRun.close();

        final secondRun = history.AppDatabase.file(file);
        addTearDown(secondRun.close);
        final recent = await DriftCorrectionRepository(
          secondRun,
        ).recent(limit: 1);

        expect(recent, hasLength(1));
        final restored = recent.single;
        expect(restored.createdAtMillis, saved.createdAtMillis);
        expect(restored.inputText, saved.inputText);
        expect(restored.presetId, saved.presetId);
        expect(restored.providerId, saved.providerId);
        expect(restored.model, saved.model);
        expect(restored.latencyMs, saved.latencyMs);
        expect(restored.outcome, saved.outcome);
        expect(restored.failureKind, saved.failureKind);
        expect(
          restored.suggestions.map((s) => (s.register, s.text)),
          saved.suggestions.map((s) => (s.register, s.text)),
        );
      },
    );
  });
}

CorrectionRecord _completed({
  int createdAtMillis = 1700000000000,
  String inputText = 'i has bad grammar',
  List<Suggestion> suggestions = const [
    Suggestion(
      register: SuggestionRegister.formal,
      text: 'My grammar is poor.',
    ),
    Suggestion(register: SuggestionRegister.casual, text: 'My grammar is bad.'),
    Suggestion(register: SuggestionRegister.shorter, text: 'Bad grammar.'),
  ],
}) {
  return CorrectionRecord(
    createdAtMillis: createdAtMillis,
    inputText: inputText,
    presetId: 'default-formal-casual-shorter',
    providerId: 'claude-agent-sdk',
    model: 'claude-sonnet-5',
    latencyMs: 812,
    outcome: CorrectionOutcome.completed,
    suggestions: suggestions,
  );
}

CorrectionRecord _failed() {
  return CorrectionRecord(
    createdAtMillis: 1700000000001,
    inputText: 'i has bad grammar',
    presetId: 'default-formal-casual-shorter',
    providerId: 'claude-agent-sdk',
    model: 'claude-sonnet-5',
    latencyMs: 30000,
    outcome: CorrectionOutcome.failed,
    failureKind: CorrectionFailureKind.timeout,
    suggestions: [],
  );
}

/// A row written past the repository, the way a hand-edited or foreign-written
/// database would look.
Future<void> _insertRawCorrection(
  history.AppDatabase database, {
  required String outcome,
  String? failureKind,
  int id = 1,
  int createdAtMillis = 10,
}) {
  return database.customStatement(
    'INSERT INTO corrections (id, created_at, input_text, preset_id, '
    'provider_id, model, latency_ms, outcome, failure_kind) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    <Object?>[
      id,
      createdAtMillis,
      'in',
      'p',
      'prov',
      'm',
      5,
      outcome,
      failureKind,
    ],
  );
}

Future<List<Map<String, Object?>>> _rows(
  history.AppDatabase database,
  String table,
) async {
  final rows = await database.customSelect('SELECT * FROM $table').get();
  return rows.map((row) => row.data).toList();
}
