import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

/// The CAP-7 history database: AD-7's two tables and its index, declared in
/// `history.drift` so the spine's SQL is the schema rather than a Dart
/// transcription of it.
///
/// Nothing here resolves a path — `AppPaths` owns that, and the composition
/// root decides which database this daemon opens.
@DriftDatabase(include: {'history.drift'})
class AppDatabase extends _$AppDatabase {
  /// Opens the database over an already-built executor, which is how tests
  /// reach an in-memory database with no Flutter binding.
  AppDatabase(super.executor);

  /// Opens (and creates, if absent) the history database stored in [file],
  /// running every statement on a background isolate.
  ///
  /// AGENTS.md §6 keeps expensive work off the UI isolate, and this is the
  /// constructor the resident daemon uses: a synchronous `NativeDatabase`
  /// would fsync each `save` and scan each `recent` on the isolate that has to
  /// answer AD-8's hotkey toggle inside CAP-1's 100 ms.
  AppDatabase.file(File file) : super(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // sqlite defaults foreign_keys to off per connection, which would make
      // AD-7's ON DELETE CASCADE silently inert.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
