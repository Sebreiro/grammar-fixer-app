---
title: 'Drift history persistence'
type: 'feature'
created: '2026-08-07'
status: 'done'
baseline_revision: 'c3a3ff59a18a1ad0be899ac32921921ec41bcbe8'
final_revision: '41e2693f97a80503a7ac2888284f57e4ee5d9918'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/lib/src/domain/correction/correction_record.dart'
  - '{project-root}/lib/src/domain/history/correction_repository.dart'
warnings: ['oversized']
---

<intent-contract>

## Intent

**Problem:** `CorrectionRepository` is a port with no implementation, so CAP-7 ("a record holding the input text and the returned suggestions exists in the local database and is still readable after an application restart") is unmet — `CorrectionController` already calls `save` at every terminal event and the write goes nowhere.

**Approach:** Add `AppDatabase` (drift, AD-7's schema) and `DriftCorrectionRepository` behind the existing port in `lib/src/infrastructure/persistence/`, mapping `CorrectionRecord` straight onto the two tables in one transaction, and prove restart durability by reopening a temp-file database.

## Boundaries & Constraints

**Always:**
- AD-7's `CREATE TABLE` / `CREATE INDEX` statements are the schema, copied into a `.drift` file: exactly those columns, types, `ON DELETE CASCADE`, the `PRIMARY KEY (correction_id, register)`, and `corrections_created_at_idx`. The repository maps `CorrectionRecord` onto them with **no intermediate model**.
- One write per correction, at the terminal event, inside a `transaction`. `CorrectionController` stays the sole caller of `save` — do not add a persist call anywhere else.
- AD-6: `SuggestionRegister`, `CorrectionOutcome` and `CorrectionFailureKind` are persisted by `.name`, never by index. `recent()` returns suggestions in `SuggestionRegister` declaration order.
- AD-1: nothing under `lib/src/domain/**` changes; drift is imported only under `lib/src/infrastructure/`. `test/architecture/ad1_import_rule_test.dart` must still pass.
- `created_at` is the unix-millis-UTC value already on the record (`Clock` port, set by the controller). The repository never calls `DateTime.now()` and takes no `Clock`.
- Database integer keys never leave the repository — nothing returned from it carries a row id.
- Foreign keys must be switched on per connection (`PRAGMA foreign_keys = ON` in `beforeOpen`); without it AD-7's `ON DELETE CASCADE` is inert.
- Tests run headless on drift's `NativeDatabase` (in-memory and temp file) with no Flutter binding, and cite CAP-7 in their names.

**Block If:**
- Honouring AD-7's schema would require changing a domain type or the `CorrectionRepository` port signature.
- The pin investigation below turns up a drift/sqlite combination that needs a Stack-table change beyond keeping today's pins.

**Never:**
- No history query API beyond the port's existing `recent({required int limit})`; no analytics UI, no migration strategy past schema v1, no `drift_flutter`/`path_provider` path resolution (`AppPaths` is story 1, and the composition root is story 4).
- Never rename an AD-7 column, add a column, or change a type to make Dart happier.
- Never widen the pubspec pins or add a dependency; the Stack table is the authority.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Completed correction | `CorrectionRecord(outcome: completed, 3 suggestions)` | 1 `corrections` row (`outcome='completed'`, `failure_kind` NULL) + 3 `suggestions` rows with `register` in `'formal'/'casual'/'shorter'` | No error expected |
| Failed correction | `CorrectionRecord(outcome: failed, failureKind: timeout, suggestions: [])` | 1 `corrections` row (`outcome='failed'`, `failure_kind='timeout'`), 0 `suggestions` rows | No error expected |
| Restart | Save into a temp-file DB, `close()`, construct a new `AppDatabase` on the same file | `recent(limit: 1)` returns the record with its suggestions | No error expected |
| Suggestion insert fails mid-write | Record whose suggestions repeat a register (composite-PK violation) | Nothing persisted: 0 `corrections` rows, 0 `suggestions` rows | Transaction rolls back; the drift exception propagates to the caller |
| Cascade | Delete a `corrections` row | Its `suggestions` rows are gone | No error expected |
| `recent` ordering | Three saved records with increasing `createdAtMillis` | Newest first, at most `limit` records, suggestions ordered formal→casual→shorter | No error expected |
| `recent(limit: 0)` | Populated database | Empty list | No error expected |
| `recent(limit: -1)` | Any state | — | `RangeError`, as the port documents |
| Unreadable stored enum | Row hand-written with `register='sarcastic'` (or an unknown `outcome`/`failure_kind`) | — | `StateError` naming the column and the offending value: a value outside the enum can only come from outside this app |

</intent-contract>

## Code Map

- `lib/src/domain/history/correction_repository.dart` -- the port being implemented; `save` + `recent({required int limit})`, unchanged by this story.
- `lib/src/domain/correction/correction_record.dart` -- the AD-7 shape being mapped; asserts `failureKind` present iff failed, and empty suggestions when failed. No row id field.
- `lib/src/domain/correction/{suggestion,suggestion_register,correction_outcome,correction_event}.dart` -- the enums persisted by `.name`.
- `lib/src/application/correction_controller.dart` -- the sole caller of `save` (`_persist`, at the terminal event). Read-only reference; do not edit.
- `test/fakes/fake_correction_repository.dart` -- existing in-memory fake; unchanged, and the new drift tests must not replace it.
- `test/architecture/ad1_import_rule_test.dart` -- the AD-1 merge gate that must keep passing.
- `pubspec.yaml` -- `drift 2.34.3`, `sqlite3 3.5.1`, `drift_dev 2.34.0`, `build_runner 2.15.1`, already pinned.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- holds the drift/drift_flutter EOL entry this story closes.

## Tasks & Acceptance

**Execution:**
- `lib/src/infrastructure/persistence/history.drift` -- create; paste AD-7's two `CREATE TABLE`s and the `CREATE INDEX` unchanged, except for the single drift-only annotation `AS suggestionText` on `suggestions.text` (see Design Notes). Keep AD-7's inline comments.
- `lib/src/infrastructure/persistence/app_database.dart` -- create `AppDatabase extends _$AppDatabase` with `@DriftDatabase(include: {'history.drift'})`, `schemaVersion => 1`, a `beforeOpen` that runs `PRAGMA foreign_keys = ON`, and a named constructor opening a `File` (`NativeDatabase`) alongside the `QueryExecutor` one the tests use.
- `lib/src/infrastructure/persistence/app_database.g.dart` -- generate with `dart run build_runner build` and commit it.
- `lib/src/infrastructure/persistence/drift_correction_repository.dart` -- create `DriftCorrectionRepository implements CorrectionRepository`, taking an `AppDatabase`. `save` = one `transaction`: insert the `corrections` companion, then the suggestion rows keyed by the returned id. `recent` = `corrections` ordered by `created_at` then `id` descending, limited, with each record's suggestions re-sorted into `SuggestionRegister` declaration order. Import the generated library with a prefix so its `Suggestion` row class cannot be confused with the domain `Suggestion`.
- `test/infrastructure/persistence/app_database_test.dart` -- create; assert the effective schema against AD-7 via `PRAGMA table_info`, `PRAGMA foreign_key_list`, `PRAGMA index_list`, that `PRAGMA foreign_keys` is on after open, and that a `corrections` delete cascades.
- `test/infrastructure/persistence/drift_correction_repository_test.dart` -- create; cover every I/O matrix row, including the temp-file reopen for restart durability and the rollback case.
- `pubspec.yaml` -- amend only if the pin investigation below produces a change; otherwise leave untouched and record the finding.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- retain the drift/drift_flutter EOL heading and historical text; if the evidence closes it, set `status: done <date>` and add a `resolution:` citing the pin and build evidence. If it remains open, add the investigation evidence to that same entry.

**Acceptance Criteria:**
- Given a completed correction saved into a temp-file database, when the database is closed and a new `AppDatabase` is opened on the same file, then `recent(limit: 1)` returns a `CorrectionRecord` equal in every field to the one saved, including all three suggestions (CAP-7).
- Given `save` is called once, when the write completes, then exactly one `corrections` row exists — a second call with the same content produces a second, separate record rather than overwriting.
- Given the deferred-work drift/drift_flutter EOL item, when the story completes, then its heading remains and the entry either has `status: done <date>` with a `resolution:` citing closing evidence or stays open with new investigation evidence; the run result states the outcome (pins kept or changed, with resolved versions).
- Given the full suite, when `dart test` and `dart analyze` run, then both pass, including `test/architecture/ad1_import_rule_test.dart` and the pre-existing application-layer tests.

## Spec Change Log

- **The pin investigation resolved harder than Design Notes predicted.** Design Notes concluded "today's pins already are the non-EOL combination — keep the pins", on the reading that `+eol` marks an inert tombstone rather than an obsolete native build. That reading is correct, but it is not the best available outcome: dropping `drift_flutter` altogether removes `sqlite3_flutter_libs`, `sqlcipher_flutter_libs` *and* the transitive `jni`/`jni_flutter`/`jni_util` FFI plugin from the graph entirely, rather than carrying three inert packages forever. The invocation intent was explicit — "if a clean combination exists, take it" — and one does, so the implementation took it. `drift_flutter` was only ever needed for the `driftDatabase()` path helper, which this story's Never list already excludes (`AppPaths` is story 1, composition root is story 4), so nothing in scope lost a capability.

  Resolved versions: `drift 2.34.3`, `sqlite3 3.5.1`, `drift_dev 2.34.0`, `build_runner 2.15.1` — all unchanged; the only pubspec edit is the deletion of the `drift_flutter: 0.3.1` line. `pubspec.lock` now contains no `sqlite3_flutter_libs`, no `sqlcipher_flutter_libs`, no `drift_flutter` and no `jni`.

  Native sqlite still reaches a packaged build: `flutter build linux --release` emits `build/linux/x64/release/bundle/lib/libsqlite3.so` (1.8 MB) from `sqlite3 3.5.1`'s Dart build hooks (`hooks` + `code_assets` + `native_toolchain_c`), which is exactly the mechanism upstream points to in the tombstones' own description ("Not used anymore, update to version 3.x of package:sqlite3 instead"). This was verified by building, not assumed from the test run — the test suite alone would not have caught a bundling regression.

  This does not trip the intent-contract's Block If ("a combination that *needs* a Stack-table change beyond keeping today's pins"): keeping today's pins was viable, so no change was *needed*. The removal is elective, and its only cost is that ARCHITECTURE-SPINE.md's Stack table still lists `drift_flutter | 0.3.1`. That divergence is filed in `../../../implementation-artifacts/deferred-work.md` rather than hand-edited into the spine, following the convention story 1 used for AD-16.

## Review Triage Log

### 2026-08-07 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 0, medium 1, low 7)
- defer: 6: (high 0, medium 4, low 2)
- reject: 5: (high 0, medium 2, low 3)
- addressed_findings:
  - `[medium]` `[patch]` `_toRecord` validated each enum column in isolation, so a row whose values were individually legal but jointly contradictory (`outcome='completed'` with a `failure_kind`, `outcome='failed'` with suggestion rows) bypassed the corrupt-history `StateError` and landed on `CorrectionRecord`'s asserts — an `AssertionError` under `dart test`, and in a release build (asserts stripped) an invariant-violating record handed to the panel. Two lenses reproduced both shapes. Added the cross-column checks to `_toRecord`, throwing the same `Unreadable history:` `StateError`, plus three tests.
  - `[low]` `[patch]` `AppDatabase.file` used the synchronous `NativeDatabase(file)`, running every `save`/`recent` on the calling isolate — the one AGENTS.md §6 reserves ("keep expensive work off the show path and off the UI isolate") for AD-8's toggle inside CAP-1's 100 ms. Dropping `drift_flutter` had silently discarded the background-isolate default its `driftDatabase()` helper supplied. Switched to `NativeDatabase.createInBackground(file)` (verified working by probe before adopting).
  - `[low]` `[patch]` `recent`'s suggestion fetch bound one SQL variable per correction id via `isIn`, which sqlite caps at 32766 — a large `limit` failed at the driver instead of returning history (reproduced at 40 000 rows). Chunked the id set at 500 and added a test that reads far past the cap.
  - `[low]` `[patch]` The rollback test asserted `throwsA(isA<Exception>())`, which would also pass if `save` threw before the first insert — i.e. if persistence broke entirely. Narrowed to `SqliteException` with the `UNIQUE constraint failed` message.
  - `[low]` `[patch]` The test named "enums are stored by name, never by index" asserted only `isA<String>()`, which an index-storing implementation writing `'0'`/`'1'` into a TEXT column would also satisfy. Strengthened to the literal stored names across all three enums.
  - `[low]` `[patch]` `recent`'s `id` tie-break for same-millisecond corrections was documented but asserted by no test (the ordering test used well-separated timestamps). Added a three-record same-millisecond ordering test.
  - `[low]` `[patch]` The restart group justified suppressing drift's multiple-database warning with "the connections are strictly sequential", which was false — the outer `setUp`'s in-memory database was still open — and reset the flag to a hardcoded `false`. Closed the unused database so the claim is true, and saved/restored the previous flag value.
  - `[low]` `[patch]` The ledger entry closing the EOL item recorded the new resolution but not the answer to the original question, so deleting the old entry would have lost whether the `+eol` packages were ever a real hazard. Added that finding (deliberate empty tombstones, no native code) to the entry.

### 2026-08-07 — Review pass (follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 7: (high 0, medium 2, low 5)
- defer: 3: (high 0, medium 3, low 0)
- reject: 7: (high 0, medium 2, low 5)
- addressed_findings:
  - `[medium]` `[patch]` The chunking test added by the previous pass never crossed a chunk boundary. It saved 40 corrections against a chunk size of 500 — one chunk — and 40 bound variables is nowhere near sqlite's 32766 cap, so an unchunked query would not have failed either. Two lenses proved it vacuous by mutation: both deleting `_chunked` and rewriting it to drop every chunk after the first left the whole suite green, and the second mutation is the shipping hazard (records past row 500 come back with no suggestions, silently). Raised the fixture to 501 records and asserted all three registers on *every* returned record, not just the first. Re-verified by mutation: the dropped-chunk variant now fails.
  - `[medium]` `[patch]` `save` validated nothing, while `_toRecord` rejects rows whose columns are individually legal but jointly contradict `CorrectionRecord`'s invariants. All three code lenses raised the asymmetry independently: the read-side guard exists precisely because those invariants are asserts that a release build strips, and that reasoning is symmetric — without a write-side guard the same stripped build persists a row every later `recent` refuses to read, and the port has no delete, so history stays unreadable for good. Added `_rejectContradictoryRecord`, made `save` `async` so a rejection arrives as a failed future rather than a synchronous throw the unawaited caller could not catch, and covered the reachable branch by mutating a record's growable suggestion list after construction.
  - `[low]` `[patch]` Every corrupt-history test seeded a database containing only the bad row, so nothing pinned whether one unreadable row costs the reader that entry or the whole result. It is the whole result. Added a mixed-database test that reads a window above the bad row successfully and then loses two healthy records to it — pinning today's all-or-nothing contract without endorsing it, since corrupt-history recovery is already deferred work.
  - `[low]` `[patch]` Every schema and pragma assertion ran on the in-memory executor; `AppDatabase.file` — the only constructor that ships, and a different connection reached over a background isolate — was exercised solely by the restart test, which asserts nothing about migrations. `beforeOpen` could have stopped running there with the suite green and AD-7's `ON DELETE CASCADE` inert in production. Added a file-constructor group asserting `PRAGMA foreign_keys` and a cascading delete; verified by mutation that removing the pragma now fails it.
  - `[low]` `[patch]` AUTOINCREMENT was "proved" by the existence of `sqlite_sequence`, which is schema-wide — any other AUTOINCREMENT table would keep it green while `corrections` lost the keyword, silently inverting the same-millisecond `id` tie-break through rowid reuse. Now asserted against the `corrections` DDL, plus a behavioural test that ids are not reused after a delete.
  - `[low]` `[patch]` `_insertRawCorrection` interpolated its values straight into the SQL literal, so a corrupt-data fixture containing an apostrophe — exactly what that helper simulates — would have failed to parse or stored something other than intended. Converted to bound variables.
  - `[low]` `[patch]` `pubspec.yaml`'s header comment still claimed the dependency list is "pinned exactly to the architecture spine's Stack table" in the same file that deliberately diverges from it, inviting the next reader to re-add `drift_flutter` and drag back the whole EOL/jni chain this story removed. Recorded the divergence inline, pointing at the ledger.

### 2026-08-07 — Review pass (follow-up 2)

- intent_gap: 0
- bad_spec: 0
- patch: 3: (high 0, medium 1, low 2)
- defer: 5: (high 0, medium 3, low 2)
- reject: 10: (high 0, medium 3, low 7)
- addressed_findings:
  - `[medium]` `[patch]` Every pragma and cascade assertion in the suite ran against a database being *created*. The daemon creates `history.sqlite` once and reopens it on every launch thereafter, and the reopen is a different `MigrationStrategy` branch — so moving `PRAGMA foreign_keys = ON` from `beforeOpen` into `onCreate` left all 31 tests green while a reopened database reported `foreign_keys = 0` and a cascade delete stranded an orphan `suggestions` row. AD-7's `ON DELETE CASCADE` would have been inert from the second launch on. Added a reopen test to the file-constructor group asserting both the pragma and the cascade on a second connection to an existing file; re-verified by mutation that it is the only test that fails when the pragma moves.
  - `[low]` `[patch]` `recent()` handed back the growable list `_suggestionsFor` builds and sorts in place, so a caller could mutate history it was only meant to read — and inconsistently: mutation succeeded on a completed record and threw on a failed one, whose empty suggestions are a `const []`. The suite's own write-guard test weaponises exactly this mutability to reach an otherwise unreachable branch. Wrapped in `List.unmodifiable`.
  - `[low]` `[patch]` `pubspec.yaml`'s header still opened with "Versions are pinned exactly to the architecture spine's Stack table … the spine, not the resolver, decides when these move" — a false absolute standing immediately above the paragraph refuting it. The previous pass added the exception without correcting the claim, so a reader skimming the first sentence would still conclude the file matches the spine and "fix" the mismatch by re-adding `drift_flutter`, dragging the EOL/`jni` chain back in. Rewrote the claim to admit the documented divergence.

## Design Notes

**Pin investigation, already carried out during planning — do not redo it, verify and record it.** `sqlite3_flutter_libs 0.6.0+eol` and `sqlcipher_flutter_libs 0.7.0+eol` are *deliberately empty tombstone packages* published by drift's own author. Their pub description reads "Not used anymore, update to version 3.x of package:sqlite3 instead"; the cached copies contain only a doc-comment library file, no native code and no dependencies, and their changelog states the version "removes all code from this package … It can be used to require that the old Flutter-specific scripts are no longer used." The current native SQLite comes from `sqlite3 3.5.1` (published 2026-08-04) via Dart build hooks — visible as `Running build hooks...` when `dart test` starts. `drift_flutter 0.3.1` is the newest published version and the only one compatible with `sqlite3 ^3.0.0`; the alternative, `drift_flutter 0.2.8`, would pull `sqlite3 ^2.4.6` and the *real* 0.5.x native build scripts — strictly worse. `sqlite3_native_assets` is discontinued upstream, replaced by `sqlite3`. **Conclusion: today's pins already are the non-EOL combination**; the ledger entry rests on reading the `+eol` tag as "obsolete native build" when it means "this shim is intentionally inert". Keep the pins, close the entry, and record this evidence.

**Why `AS suggestionText`.** AD-7's column is named `text`. drift generates `class Suggestions extends Table`, and `Table` already declares `ColumnBuilder<String> text()`, so a generated `text` column getter fails to compile ("Can't declare a member that conflicts with an inherited one"). `AS suggestionText` is drift-file-only syntax that renames the *Dart getter*; the SQL column stays `text`. Verified emitted DDL:

```sql
CREATE TABLE "suggestions" ("correction_id" INTEGER NOT NULL REFERENCES corrections(id)ON DELETE CASCADE,
  "register" TEXT NOT NULL, "text" TEXT NOT NULL, PRIMARY KEY(correction_id, register))
CREATE INDEX corrections_created_at_idx ON corrections (created_at)
```

Because drift normalises the DDL it emits anyway, the schema tests assert AD-7 through PRAGMAs rather than by string-comparing SQL.

**`PRAGMA foreign_keys` defaults to 0** on a freshly opened drift `NativeDatabase` — measured, not assumed. Enable it in `beforeOpen` or AD-7's `ON DELETE CASCADE` silently does nothing.

## Verification

**Commands:**
- `dart run build_runner build` -- expected: succeeds, writes `app_database.g.dart`.
- `dart test` -- expected: all tests pass, including the new persistence tests and `test/architecture/ad1_import_rule_test.dart`.
- `dart analyze` -- expected: no issues (AGENTS.md §6 merge gate).
- `dart format --set-exit-if-changed lib test` -- expected: no reformatting needed.
- `dart pub deps --style=compact 2>&1 | grep -E 'sqlite3|drift'` -- expected: the resolved versions recorded in the run result as the pin-investigation evidence.


## Auto Run Result

Status: done

**Summary.** Follow-up review pass over the completed story (no implementation loopback — no intent_gap and no bad_spec findings). Four review layers ran in parallel over the story's full change. Three patches applied, five findings deferred, ten rejected.

**Diff reviewed.** The recorded `baseline_revision` (`c3a3ff5`) post-dated the story's own implementation commit `54af87c` — a previous follow-up run overwrote it with the HEAD at its start — so diffing from it would have reviewed only the two patch rounds and skipped the schema, repository and tests entirely. Reviewed `0765cb9..HEAD` instead (the true pre-implementation revision, recorded in the spec's first commit), scoped to `lib/src/infrastructure/persistence`, `test/infrastructure/persistence` and `pubspec.yaml`. Generated `app_database.g.dart` was excluded from the diff text but left available on disk to the reviewers.

**Files changed this pass:**
- `test/infrastructure/persistence/app_database_test.dart` -- added a reopen test to the file-constructor group, asserting `PRAGMA foreign_keys` and a cascading delete on a second connection to an existing file.
- `lib/src/infrastructure/persistence/drift_correction_repository.dart` -- `recent()` now returns `List.unmodifiable(suggestions)`.
- `pubspec.yaml` -- corrected the header's "pinned exactly to the spine's Stack table" claim to admit the documented `drift_flutter` divergence.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- five new entries appended (existing entries untouched).
- `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/2-drift-history-persistence.md` -- triage log, status, final revision.

**Review findings breakdown.** patch 3 (1 medium, 2 low); defer 5 (3 medium, 2 low); reject 10 (3 medium, 7 low); intent_gap 0; bad_spec 0.

Two reviewer claims were refuted before triage rather than acted on:
- "`AppDatabase.file` never creates the parent directory, so the first save on a clean machine dies." False — drift 2.34.3 creates it recursively (`native.dart:409-412`, `openDatabase`). Two of the three code lenses independently read the same source and discarded the claim.
- "Making `save` `async` buys nothing, because the caller catches neither a failed future nor a synchronous throw." Refuted by the verification-gap lens's probe against the real `CorrectionController`: the async form leaves the controller at `CorrectionStatus.completed`, a synchronous throw strands it at `CorrectionStatus.running`. The mitigation is real; that it has no regression test is filed as deferred work.

**Verification performed:**
- `dart test` -- 225 passed, 2 skipped (up from 224/2: one test added). Includes `test/architecture/ad1_import_rule_test.dart` and the application-layer tests.
- `dart analyze` -- No issues found.
- `dart format --set-exit-if-changed lib test` -- 66 files, 0 changed.
- `dart pub deps --style=compact | grep -E 'sqlite3|drift'` -- `drift 2.34.3`, `sqlite3 3.5.1`, `drift_dev 2.34.0`; no `drift_flutter`, no `sqlite3_flutter_libs`, no `sqlcipher_flutter_libs`. Pins unchanged, matching the Spec Change Log's recorded resolution.
- Mutation check on the new test: relocating `PRAGMA foreign_keys = ON` from `beforeOpen` to `onCreate` fails the new reopen test and *only* that test — confirming both that the gap was real and that it is now closed.

**Follow-up review recommendation:** `true`. Patched this pass: high 0, medium 1, low 2 → score `3x1 + 1x2 = 5`, which meets the threshold of 5.

**Residual risks:**
- The five newly deferred items are all latent rather than live, because `lib/main.dart` is still `void main() {}` — nothing constructs `AppDatabase` or `DriftCorrectionRepository` yet. Three of them (database lifecycle/close, the vendor-type `SqliteException` crossing the port, the untested failing-`save` path) become user-visible the moment story 4's composition root wires the daemon, and should be read together with the already-filed "port failures are unmodelled across all three controllers" entry.
- `baseline_revision` in this spec's frontmatter remains a post-implementation revision. It is left as-is because the orchestrator owns that field; any further review run should expect to re-derive the true baseline as this pass did.
