import 'dart:io';

// `show`n narrowly: drift's query builder exports names that would shadow
// matchers of the same name.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/persistence/app_database.dart';
import 'package:test/test.dart';

/// The effective schema is asserted through PRAGMAs rather than by comparing
/// DDL strings, because drift normalises the SQL it emits. What AD-7 fixes is
/// the shape sqlite ends up with: these columns, these types, the composite
/// primary key, the cascading foreign key, and the created_at index.
///
/// Runs on drift's NativeDatabase with no Flutter binding (AGENTS.md §7).
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test(
    'CAP-7: corrections has exactly AD-7 columns, types and nullability',
    () async {
      final columns = await _tableInfo(database, 'corrections');

      expect(columns.keys, [
        'id',
        'created_at',
        'input_text',
        'preset_id',
        'provider_id',
        'model',
        'latency_ms',
        'outcome',
        'failure_kind',
      ]);
      expect(columns['id']!.type, 'INTEGER');
      expect(columns['created_at']!.type, 'INTEGER');
      expect(columns['input_text']!.type, 'TEXT');
      expect(columns['preset_id']!.type, 'TEXT');
      expect(columns['provider_id']!.type, 'TEXT');
      expect(columns['model']!.type, 'TEXT');
      expect(columns['latency_ms']!.type, 'INTEGER');
      expect(columns['outcome']!.type, 'TEXT');
      expect(columns['failure_kind']!.type, 'TEXT');

      // failure_kind is the one nullable column: NULL when the correction
      // completed.
      expect(
        {
          for (final entry in columns.entries)
            if (entry.value.notNull) entry.key,
        },
        {
          'created_at',
          'input_text',
          'preset_id',
          'provider_id',
          'model',
          'latency_ms',
          'outcome',
        },
      );
      expect(columns['id']!.primaryKeyPosition, 1);
    },
  );

  test('CAP-7: corrections.id is AUTOINCREMENT', () async {
    // Asserted against the corrections DDL itself. sqlite_sequence would be a
    // weaker proxy: it is schema-wide, so any other AUTOINCREMENT table would
    // keep this green while corrections quietly lost the keyword.
    final ddl = await database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' "
          "AND name = 'corrections'",
        )
        .get();

    expect(ddl.single.read<String>('sql'), contains('AUTOINCREMENT'));
  });

  test('CAP-7: correction ids are never reused after a delete', () async {
    // The behaviour AUTOINCREMENT exists for here: recent() breaks
    // same-millisecond ties on `id`, which only orders by recency while ids
    // keep climbing. Plain rowids would be recycled from the high-water mark
    // after a delete and silently invert that ordering.
    await database.customStatement(
      'INSERT INTO corrections (created_at, input_text, preset_id, '
      'provider_id, model, latency_ms, outcome) '
      "VALUES (10, 'first', 'p', 'prov', 'm', 5, 'completed')",
    );
    final firstId =
        (await database.select(database.corrections).getSingle()).id;

    await database.customStatement('DELETE FROM corrections');
    await database.customStatement(
      'INSERT INTO corrections (created_at, input_text, preset_id, '
      'provider_id, model, latency_ms, outcome) '
      "VALUES (10, 'second', 'p', 'prov', 'm', 5, 'completed')",
    );
    final secondId =
        (await database.select(database.corrections).getSingle()).id;

    expect(secondId, greaterThan(firstId));
  });

  test(
    'CAP-7: suggestions has AD-7 columns and the composite primary key',
    () async {
      final columns = await _tableInfo(database, 'suggestions');

      expect(columns.keys, ['correction_id', 'register', 'text']);
      expect(columns['correction_id']!.type, 'INTEGER');
      expect(columns['register']!.type, 'TEXT');
      // The `AS suggestionText` annotation renames only the Dart getter.
      expect(columns['text']!.type, 'TEXT');
      expect(columns.values.every((column) => column.notNull), isTrue);

      expect(columns['correction_id']!.primaryKeyPosition, 1);
      expect(columns['register']!.primaryKeyPosition, 2);
      expect(columns['text']!.primaryKeyPosition, 0);
    },
  );

  test(
    'CAP-7: suggestions.correction_id cascades from corrections.id',
    () async {
      final foreignKeys = await database
          .customSelect('PRAGMA foreign_key_list(suggestions)')
          .get();

      expect(foreignKeys, hasLength(1));
      final foreignKey = foreignKeys.single;
      expect(foreignKey.read<String>('table'), 'corrections');
      expect(foreignKey.read<String>('from'), 'correction_id');
      expect(foreignKey.read<String>('to'), 'id');
      expect(foreignKey.read<String>('on_delete'), 'CASCADE');
    },
  );

  test('CAP-7: corrections_created_at_idx indexes created_at', () async {
    final indexes = await database
        .customSelect('PRAGMA index_list(corrections)')
        .get();
    final names = indexes.map((index) => index.read<String>('name'));

    expect(names, contains('corrections_created_at_idx'));

    final indexedColumns = await database
        .customSelect('PRAGMA index_info(corrections_created_at_idx)')
        .get();

    expect(indexedColumns.map((column) => column.read<String>('name')), [
      'created_at',
    ]);
  });

  test('CAP-7: foreign keys are on for the connection after open', () async {
    // Off by default on a fresh sqlite connection, which would make AD-7's
    // ON DELETE CASCADE inert.
    final pragma = await database.customSelect('PRAGMA foreign_keys').get();

    expect(pragma.single.read<int>('foreign_keys'), 1);
  });

  test('CAP-7: deleting a correction deletes its suggestions', () async {
    await database.customStatement(
      "INSERT INTO corrections (id, created_at, input_text, preset_id, "
      "provider_id, model, latency_ms, outcome) "
      "VALUES (1, 10, 'in', 'p', 'prov', 'm', 5, 'completed')",
    );
    await database.customStatement(
      "INSERT INTO suggestions (correction_id, register, text) "
      "VALUES (1, 'formal', 'Formal.')",
    );

    await database.customStatement('DELETE FROM corrections WHERE id = 1');

    final remaining = await database.select(database.suggestions).get();
    expect(remaining, isEmpty);
  });

  // Everything above runs on the in-memory executor. The daemon will use
  // AppDatabase.file, which reaches sqlite over a background isolate — a
  // different connection, and therefore a different place for beforeOpen to
  // run or fail to run. Without this group, foreign keys could go inert on the
  // only constructor that ships while the whole suite stayed green.
  group('the file constructor', () {
    late Directory temporaryDirectory;
    late bool previousWarningSetting;
    late AppDatabase fileDatabase;

    setUp(() async {
      temporaryDirectory = Directory.systemTemp.createTempSync('hgc_schema_');
      // The outer setUp's in-memory database is unused here; closing it keeps
      // the warning suppression below from covering a real second database.
      await database.close();
      previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      fileDatabase = AppDatabase.file(
        File('${temporaryDirectory.path}/history.sqlite'),
      );
    });
    tearDown(() async {
      await fileDatabase.close();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningSetting;
      temporaryDirectory.deleteSync(recursive: true);
    });

    test('CAP-7: foreign keys are on for the shipped connection too', () async {
      final pragma = await fileDatabase
          .customSelect('PRAGMA foreign_keys')
          .get();

      expect(pragma.single.read<int>('foreign_keys'), 1);
    });

    test(
      'CAP-7: deleting a correction cascades on the shipped connection',
      () async {
        await fileDatabase.customStatement(
          'INSERT INTO corrections (id, created_at, input_text, preset_id, '
          'provider_id, model, latency_ms, outcome) '
          "VALUES (1, 10, 'in', 'p', 'prov', 'm', 5, 'completed')",
        );
        await fileDatabase.customStatement(
          'INSERT INTO suggestions (correction_id, register, text) '
          "VALUES (1, 'formal', 'Formal.')",
        );

        await fileDatabase.customStatement(
          'DELETE FROM corrections WHERE id = 1',
        );

        expect(
          await fileDatabase.select(fileDatabase.suggestions).get(),
          isEmpty,
        );
      },
    );

    test(
      'CAP-7: foreign keys are still on when an existing file is reopened',
      () async {
        // Every other pragma and cascade assertion in this file runs against a
        // database being *created*. The daemon creates history.sqlite once and
        // reopens it on every launch thereafter, so the reopen is the path that
        // actually runs in production — and it is a different branch of
        // MigrationStrategy. Moving `PRAGMA foreign_keys = ON` from beforeOpen
        // into onCreate keeps every other test in this suite green while
        // leaving AD-7's ON DELETE CASCADE inert from the second launch on.
        final file = File('${temporaryDirectory.path}/reopened.sqlite');

        final firstOpen = AppDatabase.file(file);
        await firstOpen.customStatement(
          'INSERT INTO corrections (id, created_at, input_text, preset_id, '
          'provider_id, model, latency_ms, outcome) '
          "VALUES (1, 10, 'in', 'p', 'prov', 'm', 5, 'completed')",
        );
        await firstOpen.customStatement(
          'INSERT INTO suggestions (correction_id, register, text) '
          "VALUES (1, 'formal', 'Formal.')",
        );
        await firstOpen.close();

        final reopened = AppDatabase.file(file);
        addTearDown(reopened.close);

        final pragma = await reopened.customSelect('PRAGMA foreign_keys').get();
        expect(pragma.single.read<int>('foreign_keys'), 1);

        // Asserted behaviourally as well as by pragma: the pragma proves the
        // switch, the cascade proves it is load-bearing on this connection.
        await reopened.customStatement('DELETE FROM corrections WHERE id = 1');
        expect(await reopened.select(reopened.suggestions).get(), isEmpty);
      },
    );
  });
}

/// `PRAGMA table_info` for [table], keyed by column name in declaration order.
Future<Map<String, _ColumnInfo>> _tableInfo(
  AppDatabase database,
  String table,
) async {
  final rows = await database.customSelect('PRAGMA table_info($table)').get();
  return {
    for (final row in rows)
      row.read<String>('name'): _ColumnInfo(
        type: row.read<String>('type'),
        notNull: row.read<int>('notnull') == 1,
        primaryKeyPosition: row.read<int>('pk'),
      ),
  };
}

final class _ColumnInfo {
  const _ColumnInfo({
    required this.type,
    required this.notNull,
    required this.primaryKeyPosition,
  });

  final String type;
  final bool notNull;

  /// 0 when the column is not part of the primary key, otherwise its 1-based
  /// position within it.
  final int primaryKeyPosition;
}
