import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/sidecar_host_paths.dart';
import 'package:test/test.dart';

/// Each version this repository depends on gets exactly one writable home, and
/// the architecture spine points at it rather than repeating it.
///
/// `claude_agent_sdk` is pinned in `assets/sidecar/requirements.txt`, which is
/// what `tool/provision_sidecar.sh` installs from. Flutter's version is pinned
/// in `.github/workflows/ci.yml`, which is what a runner installs from. The
/// spine's Stack table used to restate both numbers, and a reader treats that
/// table as the decision — so each version had two homes free to disagree, and
/// the way a disagreement got discovered was a correction failing against a
/// version nobody chose, or CI passing on a toolchain nobody develops against.
///
/// The spine now cites those two files instead. That removes the drift rather
/// than detecting it, so what is left to check is different: the citations have
/// to *resolve*, they have to name the file that actually ships the version,
/// and the numbers must not quietly grow back. Growing back has two shapes and
/// both fail here — the cell replaced by a bare `3.44.8`, and the likelier one
/// where the number is put back *beside* the citation. The second is what a
/// reader who checked only that the citation resolves would wave through, with
/// the second writable home fully restored.
///
/// These readers do not cover every copy of either version. `.devcontainer/`
/// and `pubspec.yaml` pin Flutter by hand as well, ungated, which is deferred
/// work — so a green run here means the spine and its cited home agree, not
/// that the tree has one Flutter version.
///
/// Every reader is a pure function over text, so the "no row to read" case is
/// testable directly. It has to be: a parser that answers null on a table it
/// stopped recognising would turn these gates into rows that pass because they
/// found nothing, which is the failure mode a drift check is most prone to.
void main() {
  group('the pin readers', () {
    test('the requirements reader finds a pinned version', () {
      expect(
        pinnedInRequirements(
          '# a comment\n'
          'claude-agent-sdk==1.2.3\n',
        ),
        '1.2.3',
      );
    });

    test('the requirements reader answers null when nothing pins the '
        'distribution', () {
      expect(
        pinnedInRequirements('# only a comment\nsomething-else==9.9.9\n'),
        isNull,
      );
    });

    test('the requirements reader ignores a different distribution whose name '
        'merely starts the same way', () {
      expect(pinnedInRequirements('claude-agent-sdk-extras==4.5.6\n'), isNull);
    });

    test('the requirements reader stops at a trailing comment', () {
      // The same rule tool/provision_sidecar.sh's read_pin applies. The two
      // must agree, or the script installs correctly and then fails its own
      // verification against a version with a comment glued to it.
      expect(
        pinnedInRequirements('claude-agent-sdk==1.2.3  # keep in sync\n'),
        '1.2.3',
      );
    });

    test('the Stack table reader finds the version cell of a row', () {
      expect(
        pinnedInStackTable(_syntheticSpine, rowName: 'claude_agent_sdk'),
        '1.2.3',
      );
      expect(
        pinnedInStackTable(_syntheticSpine, rowName: 'Flutter (stable)'),
        '9.8.7',
      );
    });

    test('the Stack table reader answers null when the row is gone, so the '
        'checks below fail instead of passing on nothing', () {
      expect(
        pinnedInStackTable(_syntheticSpine, rowName: 'drift_flutter'),
        isNull,
      );
    });

    test('the Stack table reader ignores a matching row outside the Stack '
        'section', () {
      // The spine is a long document with several tables. A row named the same
      // way in the Capability map, or in a quoted example, is *absence* as far
      // as the Stack table is concerned — answering with it would be a wrong
      // answer dressed as a found one.
      expect(
        pinnedInStackTable(
          '## Deferred\n'
          '\n'
          '| Name | Version |\n'
          '| --- | --- |\n'
          '| claude_agent_sdk | 0.0.1 |\n'
          '\n'
          '## Stack\n'
          '\n'
          '| Name | Version |\n'
          '| --- | --- |\n'
          '| dbus | 0.7.14 |\n',
          rowName: 'claude_agent_sdk',
        ),
        isNull,
      );
    });

    test('the Stack table reader answers null on a document with no Stack '
        'section at all', () {
      expect(
        pinnedInStackTable(
          '| claude_agent_sdk | 1.2.3 |\n',
          rowName: 'claude_agent_sdk',
        ),
        isNull,
      );
    });

    test('the workflow reader finds the pinned Flutter version', () {
      expect(
        flutterVersionInWorkflow(
          'jobs:\n'
          '  build:\n'
          '    steps:\n'
          '      - uses: subosito/flutter-action@v2\n'
          '        with:\n'
          '          flutter-version: 9.8.7\n',
        ),
        '9.8.7',
      );
    });

    test('the workflow reader answers null when no version is pinned', () {
      expect(
        flutterVersionInWorkflow('jobs:\n  build:\n    steps: []\n'),
        isNull,
      );
    });

    test('the requirements reader answers null on two pinning lines rather '
        'than guessing the first', () {
      // tool/provision_sidecar.sh refuses this file outright. A reader that
      // guessed would let this gate go green on input the script it gates
      // rejects — the two readers must agree about ambiguity as well as about
      // where a version ends.
      expect(
        pinnedInRequirements(
          'claude-agent-sdk==1.2.3\n'
          'claude-agent-sdk==4.5.6\n',
        ),
        isNull,
      );
    });

    test('the workflow reader strips the quotes YAML authors add to keep a '
        'version a string', () {
      expect(
        flutterVersionInWorkflow('          flutter-version: "9.8.7"\n'),
        '9.8.7',
      );
      expect(
        flutterVersionInWorkflow("          flutter-version: '9.8.7'\n"),
        '9.8.7',
      );
    });

    test('the workflow reader answers null when two jobs pin their own '
        'toolchains, rather than covering only the first', () {
      expect(
        flutterVersionInWorkflow(
          '          flutter-version: 9.8.7\n'
          '          flutter-version: 1.2.3\n',
        ),
        isNull,
      );
    });

    test('the venv reader finds the directory the provisioning script '
        'builds', () {
      expect(
        venvDirectoryInScript("readonly venv_dir=\"\${repo_root}/.venv-x\"\n"),
        '.venv-x',
      );
    });

    test('the venv reader answers null when the assignment is gone', () {
      expect(venvDirectoryInScript('readonly other=1\n'), isNull);
    });
  });

  group('the citation reader', () {
    test('finds the repo-relative path a Stack row cites', () {
      expect(
        citedPathInStackTable(_citingSpine, rowName: 'claude_agent_sdk'),
        'assets/sidecar/requirements.txt',
      );
      expect(
        citedPathInStackTable(_citingSpine, rowName: 'Flutter (stable)'),
        '.github/workflows/ci.yml',
      );
    });

    test('refuses a row whose name merely starts the same way, and still '
        'answers the real row below it', () {
      expect(
        citedPathInStackTable(_citingSpine, rowName: 'claude_agent_sdk'),
        'assets/sidecar/requirements.txt',
      );
      expect(
        citedPathInStackTable(_citingSpine, rowName: 'claude_agent_sdk_extras'),
        'assets/sidecar/extras.txt',
      );
    });

    test('answers null on a cell that restates a bare version, which is the '
        'second home growing back', () {
      // The load-bearing half. Without it the gate would pass a row that had
      // quietly reverted to stating the number, which is the state this whole
      // change exists to end.
      expect(
        citedPathInStackTable(_syntheticSpine, rowName: 'Flutter (stable)'),
        isNull,
      );
      expect(
        citedPathInStackTable(_syntheticSpine, rowName: 'claude_agent_sdk'),
        isNull,
      );
    });

    test('answers null on a cell that cites the file *and* restates the '
        'number, which is the same revert done additively', () {
      // The likelier edit of the two, and the one a citation-only check would
      // wave through: the row parses, the path resolves, and the second
      // writable home is fully back.
      expect(
        citedPathInStackTable(
          _stackSectionAround(
            '| Flutter (stable) | 3.44.8 (pinned in '
            '`.github/workflows/ci.yml`) |',
          ),
          rowName: 'Flutter (stable)',
        ),
        isNull,
      );
      expect(
        citedPathInStackTable(
          _stackSectionAround('| thing | `a/b.txt` pins 1.2.3 |'),
          rowName: 'thing',
        ),
        isNull,
      );
    });

    test('does not read the digits inside a cited path as a restated '
        'version', () {
      // `.github/workflows/ci.yml` carries dots and digits of its own. The
      // version check runs on what is left once the backticked span is gone,
      // or this reader would refuse the very citation the spine ships.
      expect(
        citedPathInStackTable(_citingSpine, rowName: 'Flutter (stable)'),
        '.github/workflows/ci.yml',
      );
      expect(
        citedPathInStackTable(
          _stackSectionAround('| thing | pinned in `tool/v1.2/pins.txt` |'),
          rowName: 'thing',
        ),
        'tool/v1.2/pins.txt',
      );
    });

    test('answers null on a path that escapes the repository or names a '
        'remote', () {
      for (final escape in const [
        '../elsewhere/ci.yml',
        'tool/../../elsewhere/ci.yml',
        'https://example.invalid/ci.yml',
      ]) {
        expect(
          citedPathInStackTable(
            _stackSectionAround('| thing | pinned in `$escape` |'),
            rowName: 'thing',
          ),
          isNull,
          reason:
              '"$escape" is not a file inside this repository, so nothing '
              'here can check what it points at',
        );
      }
    });

    test('answers null on a cell whose backticked token is not a path', () {
      // `on `PATH`` is a legitimate Stack cell — it just cites no file, so
      // there is nothing here for this gate to resolve.
      expect(
        citedPathInStackTable(_citingSpine, rowName: '`claude` CLI'),
        isNull,
      );
    });

    test('answers null on a cell citing two files rather than guessing which '
        'one is the home', () {
      expect(
        citedPathInStackTable(
          _stackSectionAround('| thing | pinned in `a/b.txt` and `c/d.txt` |'),
          rowName: 'thing',
        ),
        isNull,
      );
    });

    test('answers null on an absolute path, which is not a file in this '
        'repository', () {
      expect(
        citedPathInStackTable(
          _stackSectionAround('| thing | pinned in `/etc/thing.conf` |'),
          rowName: 'thing',
        ),
        isNull,
      );
    });

    test('answers null on a version restated inside backticks, which the '
        'strip-every-backtick rule made invisible', () {
      // Reproduced against the committed reader before this fixture existed:
      // both rows cited the right file, restated a wrong number, and passed.
      // Backticks in a Stack name cell are ordinary here — `` `claude` CLI ``
      // is a real row — so this is not an exotic edit.
      expect(
        citedPathInStackTable(
          _stackSectionAround(
            '| Flutter (stable) `3.44.7` | pinned in '
            '`.github/workflows/ci.yml` |',
          ),
          rowName: 'Flutter (stable)',
        ),
        isNull,
      );
      expect(
        citedPathInStackTable(
          _stackSectionAround('| thing | `1.2.3` — pinned in `a/b.txt` |'),
          rowName: 'thing',
        ),
        isNull,
      );
    });

    test('answers null on a version in a column after the version cell', () {
      // The row the version rule runs over reaches the end of the line. While
      // it stopped at the second pipe, a third column was outside every check
      // that reads a row, and the doc saying "the whole row" was false.
      expect(
        citedPathInStackTable(
          _stackSectionAround('| thing | pinned in `a/b.txt` | was 1.2.3 |'),
          rowName: 'thing',
        ),
        isNull,
      );
    });

    test('reads a citation of a file at the repository root', () {
      // `pubspec.yaml` is the next home the ledger plans to gate. The rule this
      // replaces required a slash, so that citation could not be written.
      expect(
        citedPathInStackTable(
          _stackSectionAround('| thing | pinned in `pubspec.yaml` |'),
          rowName: 'thing',
        ),
        'pubspec.yaml',
      );
    });

    test('reads the spellings that name one file as that one file', () {
      // The caller compares this answer to the one home by string, so an
      // unnormalised `./a/b.txt` fails a correct spine on punctuation — the
      // same false red the trim beside it exists to stop.
      for (final spelling in const [
        './a/b.txt',
        'a//b.txt',
        'a/./b.txt',
        ' a/b.txt ',
      ]) {
        expect(
          citedPathInStackTable(
            _stackSectionAround('| thing | pinned in `$spelling` |'),
            rowName: 'thing',
          ),
          'a/b.txt',
          reason: '"$spelling" names the file a/b.txt names',
        );
      }
    });

    test('answers null when the row is gone, so the checks below fail instead '
        'of passing on nothing', () {
      expect(
        citedPathInStackTable(_citingSpine, rowName: 'drift_flutter'),
        isNull,
      );
    });

    test('answers null for a matching row outside the Stack section', () {
      expect(
        citedPathInStackTable(
          '## Deferred\n'
          '\n'
          '| Name | Version |\n'
          '| --- | --- |\n'
          '| thing | pinned in `a/b.txt` |\n'
          '\n'
          '## Stack\n'
          '\n'
          '| Name | Version |\n'
          '| --- | --- |\n'
          '| dbus | 0.7.14 |\n',
          rowName: 'thing',
        ),
        isNull,
      );
    });

    test('answers null on a document with no Stack section at all', () {
      expect(
        citedPathInStackTable(
          '| thing | pinned in `a/b.txt` |\n',
          rowName: 'thing',
        ),
        isNull,
      );
    });

    test('answers null when the version is restated in the row *name* cell, '
        'which is the same revert one column to the left', () {
      // Not hypothetical: until these rows were re-homed the spine's own
      // `claude_agent_sdk` row kept its parenthetical metadata in the name
      // cell, so that is a place a number demonstrably goes. A version check
      // scoped to the version cell would call both of these green.
      expect(
        citedPathInStackTable(
          _stackSectionAround(
            '| Flutter (stable) 3.44.8 | pinned in '
            '`.github/workflows/ci.yml` |',
          ),
          rowName: 'Flutter (stable)',
        ),
        isNull,
      );
      expect(
        citedPathInStackTable(
          _stackSectionAround(
            '| claude_agent_sdk (pip, 0.2.132) | pinned in '
            '`assets/sidecar/requirements.txt` |',
          ),
          rowName: 'claude_agent_sdk',
        ),
        isNull,
      );
    });

    test('answers null on two Stack rows of one name rather than reading the '
        'first, which is the second home one row down', () {
      // The shape a citation-plus-restatement revert takes when it is split
      // across two rows instead of one cell. `firstMatch` would answer the
      // citation and leave the bare number underneath it unread.
      expect(
        citedPathInStackTable(
          _stackSectionAround(
            '| Flutter (stable) | pinned in `.github/workflows/ci.yml` |\n'
            '| Flutter (stable) | 3.44.8 |',
          ),
          rowName: 'Flutter (stable)',
        ),
        isNull,
      );
      expect(
        pinnedInStackTable(
          _stackSectionAround(
            '| Flutter (stable) | pinned in `.github/workflows/ci.yml` |\n'
            '| Flutter (stable) | 3.44.8 |',
          ),
          rowName: 'Flutter (stable)',
        ),
        isNull,
        reason:
            'ambiguity reads as absence in the cell reader too, or the failure '
            'message would quote a row the citation check never used',
      );
    });

    test('trims a padded citation rather than answering whitespace', () {
      // The cell cites the same file; an untrimmed answer would fail the real
      // gate\'s comparison against the home with a diff of invisible spaces.
      expect(
        citedPathInStackTable(
          _stackSectionAround('| thing | pinned in ` a/b.txt ` |'),
          rowName: 'thing',
        ),
        'a/b.txt',
      );
      expect(
        citedPathInStackTable(
          _stackSectionAround('| thing | pinned in `   ` |'),
          rowName: 'thing',
        ),
        isNull,
      );
    });
  });

  group('the subject scope', () {
    test('finds a second row for the same subject however it is named', () {
      // The shape the value-scoped check waved through: a duplicate row whose
      // number has already drifted away from the home. Reproduced green against
      // the committed gate with exactly this row.
      final rows = _tableRowsNaming(
        _stackSectionAround(
          '| Flutter (stable) | pinned in `.github/workflows/ci.yml` |\n'
          '| Flutter toolchain | 3.44.7 |',
        ),
        _flutterSubject,
      );
      expect(rows.length, 2);
    });

    test('does not read a package whose name merely contains the subject', () {
      // `flutter_riverpod`, `drift_flutter` and `flutter_lints` are real Stack
      // rows with versions of their own. A subject rule that claimed them would
      // fail the spine for stating versions it is supposed to state.
      final rows = _tableRowsNaming(
        _stackSectionAround(
          '| flutter_riverpod | 3.4.2 |\n'
          '| drift_flutter | 0.3.1 |\n'
          '| flutter_lints (dev) | 6.0.0 |\n'
          '| claude_agent_sdk_extras (pip) | 9.9.9 |',
        ),
        _flutterSubject,
      );
      expect(rows, isEmpty);
      expect(
        _tableRowsNaming(
          _stackSectionAround('| claude_agent_sdk_extras (pip) | 9.9.9 |'),
          _sdkSubject,
        ),
        isEmpty,
      );
    });

    test('reads only the name cell, so the ring table is not a Stack row', () {
      // `package:flutter/*` and `Flutter widgets` sit in the architecture's own
      // dependency table. A whole-line rule would fail the spine on them.
      expect(
        _tableRowsNaming(
          '| **domain** | `lib/src/domain/` | `dart:*` core only | '
          '`package:flutter/*`, drift, dbus, any plugin |\n',
          _flutterSubject,
        ),
        isEmpty,
      );
    });

    test('matches the sdk subject either side of the pip/import divide', () {
      for (final spelling in const ['claude_agent_sdk', 'claude-agent-sdk']) {
        expect(
          _tableRowsNaming(
            _stackSectionAround('| $spelling (pip) | pinned in `a/b.txt` |'),
            _sdkSubject,
          ),
          hasLength(1),
          reason: '"$spelling" names the same pin',
        );
      }
    });
  });

  group('the failure messages', () {
    test('an empty version cell is named as one, not quoted as "null"', () {
      const row = '| Flutter (stable) ||';
      final source = _stackSectionAround(row);
      expect(pinnedInStackTable(source, rowName: flutterRowName), isNull);
      final message = _uncitedFailure(
        rowName: flutterRowName,
        row: _stackRow(source, rowName: flutterRowName),
        cell: pinnedInStackTable(source, rowName: flutterRowName),
        home: workflowPath,
      );
      expect(message, contains('empty version cell'));
      expect(
        message,
        isNot(contains('"null"')),
        reason:
            'the message interpolates the cell, so an empty one used to read '
            'back `reads "null"` — text that quotes nothing and names no edit',
      );
    });

    test('a restated version is reported as the rule that fired, over the text '
        'the rule was applied to', () {
      const row = '| Flutter (stable) `3.44.7` | pinned in `a/b.yml` |';
      final source = _stackSectionAround(row);
      final message = _uncitedFailure(
        rowName: flutterRowName,
        row: _stackRow(source, rowName: flutterRowName),
        cell: pinnedInStackTable(source, rowName: flutterRowName),
        home: workflowPath,
      );
      expect(message, contains('3.44.7'));
      expect(message, contains('name cell'));
    });
  });

  group('the real files', () {
    test('AD-19: the spine cites the one home of the claude_agent_sdk pin, '
        'and the citation resolves', () {
      final spine = _read(spinePath);
      final cited = citedPathInStackTable(spine, rowName: module);
      if (cited == null) {
        fail(
          _uncitedFailure(
            rowName: module,
            row: _stackRow(spine, rowName: module),
            cell: pinnedInStackTable(spine, rowName: module),
            home: requirementsPath,
          ),
        );
      }
      expect(
        cited,
        requirementsPath,
        reason:
            'the spine\'s "$module" Stack row cites "$cited", but the pin\'s '
            'one home is $requirementsPath — the file tool/provision_sidecar.sh '
            'installs from. Citing anything else points a reader at a version '
            'that is not the one that ships',
      );
      if (!File(cited).existsSync()) {
        fail(
          'the spine\'s "$module" Stack row cites "$cited", which does not '
          'exist. A citation that does not resolve is worse than the '
          'duplicated number it replaced: it reads as a decision with a home '
          'and has neither.',
        );
      }

      expect(
        pinnedInRequirements(_read(cited)),
        isNotNull,
        reason:
            'the spine\'s "$module" Stack row cites "$cited", but that file '
            'pins no single $distribution version — so the row points a reader '
            'at a file that cannot answer the question it was asked',
      );
    });

    test('the spine cites the one home of the Flutter version, and the '
        'citation resolves', () {
      final spine = _read(spinePath);
      final cited = citedPathInStackTable(spine, rowName: flutterRowName);
      if (cited == null) {
        fail(
          _uncitedFailure(
            rowName: flutterRowName,
            row: _stackRow(spine, rowName: flutterRowName),
            cell: pinnedInStackTable(spine, rowName: flutterRowName),
            home: workflowPath,
          ),
        );
      }
      expect(
        cited,
        workflowPath,
        reason:
            'the spine\'s "$flutterRowName" Stack row cites "$cited", but the '
            'toolchain\'s one home is $workflowPath — the file a runner '
            'installs from. Citing anything else points a reader at a version '
            'CI does not build with',
      );
      if (!File(cited).existsSync()) {
        fail(
          'the spine\'s "$flutterRowName" Stack row cites "$cited", which does '
          'not exist. A citation that does not resolve is worse than the '
          'duplicated number it replaced: it reads as a decision with a home '
          'and has neither.',
        );
      }

      expect(
        flutterVersionInWorkflow(_read(cited)),
        isNotNull,
        reason:
            'the spine\'s "$flutterRowName" Stack row cites "$cited", but that '
            'file pins no single flutter-version — so CI and the spine would '
            'again be two answers to one question',
      );
    });

    test('neither cited version has a second home anywhere in the spine', () {
      // The per-row check above reads one row. This reads the table and the
      // document, and it is deliberately **subject-scoped** rather than
      // value-scoped.
      //
      // Asking "does the string 3.44.8 appear anywhere", which is what this
      // did, was wrong in both directions and both were reproduced against the
      // committed reader:
      //
      // - it stayed green on `| Flutter toolchain | 3.44.7 |` added to the
      //   Stack table, because a duplicate that has already drifted no longer
      //   equals the home — so the check saw the second writable home only
      //   while the second home was still harmless;
      // - it went red when a legitimate new pin happened to equal an unrelated
      //   row's version: bumping `claude-agent-sdk` to 0.7.14 collided with
      //   `| dbus | 0.7.14 |` and failed the spec's own criterion that editing
      //   the pin and nothing else keeps the suite green.
      //
      // What is checked instead: one row per subject, no row anywhere stating
      // a number for these subjects, and no prose line naming a subject beside
      // its cited number. The numbers are still read from the homes the spine
      // cites, so this assertion cannot itself become a third copy.
      final spine = _read(spinePath);
      final section = _stackSection(spine);
      if (section == null) {
        fail(
          'the spine has no `## Stack` section, so this gate cannot tell '
          'whether either version has grown a second home',
        );
      }

      final subjects = [
        (
          label: flutterRowName,
          name: _flutterSubject,
          home: workflowPath,
          version: flutterVersionInWorkflow(_read(workflowPath)),
        ),
        (
          label: module,
          name: _sdkSubject,
          home: requirementsPath,
          version: pinnedInRequirements(_read(requirementsPath)),
        ),
      ];

      for (final subject in subjects) {
        expect(
          subject.version,
          isNotNull,
          reason:
              '${subject.home} pins no single version, so this gate cannot '
              'tell whether the spine has grown a second copy of it',
        );

        // One row, whatever it says. A second row naming the same subject is
        // the second writable home back, and it does its damage precisely when
        // the two disagree — which is the state a value check cannot see.
        final stackRows = _tableRowsNaming(section, subject.name);
        expect(
          stackRows.length,
          1,
          reason:
              'the `## Stack` section holds ${stackRows.length} rows naming '
              '${subject.label} — '
              '${stackRows.map((row) => '"${row.trim()}"').join(', ')}. '
              'Exactly one row may speak for a version whose home is '
              '${subject.home}.',
        );

        // No row anywhere in the document — this table or another — may state
        // a number for these subjects, in any column.
        for (final row in _tableRowsNaming(spine, subject.name)) {
          expect(
            _restatesAVersion(row),
            isFalse,
            reason:
                'the spine row "${row.trim()}" states a version for '
                '${subject.label}, whose one home is ${subject.home}. Cite the '
                'file and only the file — in the version cell, in the name '
                'cell, or in any column after them.',
          );
        }

        // Prose. Scoped to lines that name the subject *and* carry the cited
        // number, so an unrelated package sitting at the same version is not
        // read as a revert. Residual, stated rather than hidden: prose that
        // states the number without naming the subject anywhere on the line is
        // not caught here.
        for (final line in spine.split('\n')) {
          if (line.trimLeft().startsWith('|')) {
            continue;
          }
          if (!RegExp(subject.name).hasMatch(line) ||
              !line.contains(subject.version!)) {
            continue;
          }
          fail(
            'the spine states "${subject.version}" beside ${subject.label} in '
            'prose — "${line.trim()}" — while citing ${subject.home} as that '
            'version\'s one home. Prose is as writable as a table cell, and a '
            'reader believes it the same way.',
          );
        }
      }
    });

    test('AD-19: the provisioning script builds the environment the shipped '
        'default points at', () {
      // The one duplicated fact still left, and the one whose drift is silent.
      // Every Dart-side copy of `.venv-sidecar` now reads SidecarHostPaths, but
      // tool/provision_sidecar.sh cannot import Dart, so it keeps its own
      // spelling. Rename one side and nothing goes red: the harness's
      // availability probe finds no interpreter, so five rows *skip*, the live
      // rows skip, and the suite is green having stopped covering the sidecar.
      final declared = venvDirectoryInScript(_read(provisionScriptPath));
      if (declared == null) {
        fail(
          '$provisionScriptPath has no parseable venv_dir assignment — not '
          'found, so this gate cannot compare anything',
        );
      }

      expect(
        SidecarHostPaths.repoRelativeInterpreterPath,
        startsWith('$declared/'),
        reason:
            'the script builds "$declared" while the shipped default derives '
            'from "${SidecarHostPaths.repoRelativeInterpreterPath}", so a '
            'provisioned host would still be seeded with the bare `python3` '
            'fallback and every sidecar row would skip',
      );
    });
  });
}

/// The repo-relative directory `tool/provision_sidecar.sh` creates, or null.
String? venvDirectoryInScript(String source) {
  final matches = RegExp(
    r'''^readonly venv_dir="\$\{repo_root\}/([^"]+)"''',
    multiLine: true,
  ).allMatches(source);
  return matches.length == 1 ? matches.single.group(1) : null;
}

const String distribution = 'claude-agent-sdk';
const String module = 'claude_agent_sdk';
const String flutterRowName = 'Flutter (stable)';
const String requirementsPath = 'assets/sidecar/requirements.txt';
const String workflowPath = '.github/workflows/ci.yml';
const String provisionScriptPath = 'tool/provision_sidecar.sh';
const String spinePath =
    '_bmad-output/planning-artifacts/architecture/'
    'architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md';

/// A Stack table whose version cells still restate numbers — what the spine
/// looked like before the pins were given one home, and what a reverted row
/// would look like again.
const String _syntheticSpine =
    '## Stack\n'
    '\n'
    '| Name | Version |\n'
    '| --- | --- |\n'
    '| Flutter (stable) | 9.8.7 |\n'
    '| dbus | 0.7.14 |\n'
    '| claude_agent_sdk (pip, pinned in `x/requirements.txt`) | 1.2.3 |\n'
    '| `claude` CLI (spawned by the Python SDK) | on `PATH` |\n'
    '\n'
    '## Structural Seed\n';

/// The shape the Stack table has now: the two versions with an executable home
/// cite it, and the rows that pin nothing still say so in prose.
///
/// The two cited rows are the **real** row strings, verbatim, so this group
/// exercises the row-name shapes `the real files` group depends on. A
/// paraphrase would let a future reword of a Stack row break the real gate with
/// every unit test still green — which is the same "passes because it found
/// nothing" failure these readers are built to refuse.
///
/// The `claude_agent_sdk_extras` row sits *above* the real one on purpose: the
/// name-boundary guard has to refuse it in the citing shape too, and a reader
/// that scans in document order would otherwise answer the extras path.
const String _citingSpine =
    '## Stack\n'
    '\n'
    '| Name | Version |\n'
    '| --- | --- |\n'
    '| Flutter (stable) | pinned in `.github/workflows/ci.yml` |\n'
    '| dbus | 0.7.14 |\n'
    '| claude_agent_sdk_extras (pip) | pinned in `assets/sidecar/extras.txt` |\n'
    '| claude_agent_sdk (pip, imported by the Python sidecar) | pinned in '
    '`assets/sidecar/requirements.txt` |\n'
    '| `claude` CLI (spawned by the Python SDK) | on `PATH` |\n'
    '\n'
    '## Structural Seed\n';

/// A minimal `## Stack` section carrying just [row], for the cell shapes that
/// are easier to state than to find a real example of.
String _stackSectionAround(String row) =>
    '## Stack\n'
    '\n'
    '| Name | Version |\n'
    '| --- | --- |\n'
    '$row\n'
    '\n'
    '## Structural Seed\n';

/// The version [source] pins for [distribution], or null when no line does.
///
/// Deliberately strict about the `==` that must follow the name and about where
/// the version ends: a requirements file may carry ranges, near-namesakes and
/// trailing comments, and a loose match would report a neighbouring package's
/// version, or a version with a comment glued to it.
/// Exactly one match, or null. `firstMatch` would answer a file carrying two
/// conflicting `claude-agent-sdk==` lines with whichever came first, which is a
/// guess — and `tool/provision_sidecar.sh` refuses that same file outright, so
/// this gate would go green on input the tooling it gates rejects. Ambiguity has
/// to read as absence for the caller's "row not found" failure to mean anything.
String? pinnedInRequirements(String source) {
  final matches = RegExp(
    '^${RegExp.escape(distribution)}==([^\\s#]+)',
    multiLine: true,
  ).allMatches(source);
  return matches.length == 1 ? matches.single.group(1) : null;
}

/// The whole `## Stack` row for [rowName] — name cell and version cell both —
/// or null when the section has no such row, or more than one.
///
/// The section is sliced off first, so a same-named row in any other table — a
/// deferred item, a capability map, a quoted example — is not answered as if it
/// were the Stack table's. Absence has to read as absence for the caller's
/// "row not found" failure to mean anything.
///
/// Two rows of one name inside the Stack table read as absence for the same
/// reason [pinnedInRequirements] refuses two pinning lines: answering the first
/// would let `| Flutter (stable) | pinned in `…` |` and a second
/// `| Flutter (stable) | 3.44.8 |` coexist with this gate green, which is the
/// second writable home growing back one row down from the citation.
///
/// The name cell is kept because [citedPathInStackTable] has to look for a
/// restated version in the *whole* row: this table already uses the name cell
/// for parenthetical metadata, so it is somewhere a number can come back.
///
/// "Whole row" means to the end of the line. It used to mean the first two
/// cells, which made the doc above false for any column after them and left a
/// third-column version outside every rule that reads this.
String? _stackRow(String source, {required String rowName}) {
  final section = _stackSection(source);
  if (section == null) {
    return null;
  }
  final matches = RegExp(
    // `(?![\w-])` rather than `\b`: the row names include parentheses, after
    // which `\b` does not match, while a longer name like
    // `claude_agent_sdk_extras` must still not satisfy `claude_agent_sdk`.
    '^\\|\\s*${RegExp.escape(rowName)}(?![\\w-])[^|]*\\|[^\\n]*',
    multiLine: true,
  ).allMatches(section);
  return matches.length == 1 ? matches.single.group(0) : null;
}

/// True when [text] still states a version once every backticked **path** is
/// gone.
///
/// Shared by [citedPathInStackTable] and [_uncitedFailure] rather than written
/// twice: a copy would let the rule and the message that explains it drift, so
/// the gate would fail for one reason and name another.
///
/// Only the spans [_looksLikePath] accepts are removed. Removing *every*
/// backticked span — which this did until the number was put back inside one —
/// left the exact revert this gate exists to refuse invisible to it: a row
/// reading ``| Flutter (stable) `3.44.7` | pinned in `…/ci.yml` |`` cited the
/// right file, restated a wrong number, and passed. A path has to be stripped
/// because `.github/workflows/ci.yml` carries digits of its own; a version is
/// not a path, so backticks no longer hide one.
bool _restatesAVersion(String text) => RegExp(r'\d+\.\d+').hasMatch(
  text.replaceAllMapped(
    RegExp('`([^`]*)`'),
    (match) => _looksLikePath(_normalizedCitation(match.group(1)!.trim()))
        ? ' '
        : match.group(0)!,
  ),
);

/// A repo-relative path this gate could resolve: no scheme, no leading `/`, no
/// `..` segment, and a file extension.
///
/// The extension is what separates a citation from a version — `3.44.8` is a
/// run of digits and dots exactly as `tool/v1.2/pins.txt` is, and only one of
/// them ends in something a file can be named after. Requiring it also lets a
/// row cite a file at the repository root: `pubspec.yaml` is the next home the
/// ledger plans to gate, and the "must contain a slash" rule this replaces made
/// that citation unrepresentable.
bool _looksLikePath(String token) =>
    token.isNotEmpty &&
    !token.startsWith('/') &&
    !token.contains('://') &&
    !token.split('/').contains('..') &&
    RegExp(r'^[\w.@+-]+(/[\w.@+-]+)*$').hasMatch(token) &&
    RegExp(r'\.[A-Za-z][\w-]*$').hasMatch(token);

/// [token] with the spellings that name one file collapsed into one.
///
/// `./a/b.txt`, `a//b.txt` and `a/./b.txt` all name the file `a/b.txt` names,
/// and the caller compares this answer to the one home by string. Without it a
/// substantively correct citation fails on a diff of punctuation — the same
/// false red the trim beside it was added to stop.
String _normalizedCitation(String token) {
  var normalized = token.replaceAll(RegExp('/{2,}'), '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  while (normalized.contains('/./')) {
    normalized = normalized.replaceAll('/./', '/');
  }
  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

/// Every markdown table row in [source] whose **name cell** matches [subject].
///
/// The name cell only. `package:flutter/*` sits in the ring table's "never
/// imports" column and `Flutter widgets` in its neighbour, and neither is a row
/// speaking for the Flutter toolchain's version — a rule that read whole rows
/// here would go red on the architecture's own dependency table.
List<String> _tableRowsNaming(String source, String subject) {
  final pattern = RegExp(subject);
  return source
      .split('\n')
      .where((line) => line.trimLeft().startsWith('|'))
      .where((line) {
        final cells = line.split('|');
        return cells.length > 1 && pattern.hasMatch(cells[1]);
      })
      .toList();
}

/// The Flutter **toolchain**, as a Stack name cell spells it.
///
/// The word has to stand alone: `flutter_riverpod`, `drift_flutter` and
/// `flutter_lints` are different packages with their own rows and their own
/// versions, and none of them speaks for the toolchain.
const String _flutterSubject = r'(?<![\w-])[Ff]lutter(?![\w-])';

/// The `claude_agent_sdk` pin, spelled either way round the pip/import divide,
/// and not `claude_agent_sdk_extras`.
const String _sdkSubject = r'(?<![\w-])claude[_-]?agent[_-]?sdk(?![\w-])';

/// The version cell of the `## Stack` section's row for [rowName], or null when
/// that section has no such row (or more than one — see [_stackRow]).
///
/// This returns the cell *verbatim*, whatever it holds. It is what a failure
/// message quotes back so a row that reverted to a bare number says so in its
/// own words.
String? pinnedInStackTable(String source, {required String rowName}) {
  final row = _stackRow(source, rowName: rowName);
  if (row == null) {
    return null;
  }
  final cell = RegExp(r'\|[^|]*\|\s*([^|]+?)\s*\|').firstMatch(row);
  return cell?.group(1);
}

/// The repo-relative path the `## Stack` row for [rowName] cites, or null when
/// the cell cites nothing — including when it restates a bare version, which is
/// the second home growing back.
///
/// A citation is exactly one backticked token in the version cell that reads as
/// a path inside this repository, and **nothing that looks like a version
/// beside it**. Everything else is absence:
///
/// - a bare version (`3.44.8`) has no backticked token at all — the cell has
///   stopped pointing at the home and started being a second one;
/// - a version *and* a citation (``3.44.8 (pinned in `…/ci.yml`)``) is the same
///   revert done additively, and is the likelier one: the row still parses and
///   the path still resolves, so a reader who checked only that the citation
///   works would call the second writable home green. Both halves have to be
///   refused or this gate only catches the careless version of the mistake;
/// - the same revert in the row's **name** cell (`| Flutter (stable) 3.44.8 |
///   pinned in `…` |`) is refused too. The version check runs over the whole
///   row, not just the version cell, because this table already uses the name
///   cell for parenthetical metadata — until these rows were re-homed, the
///   `claude_agent_sdk` row read ``| claude_agent_sdk (pip, pinned in
///   `…/requirements.txt`) | 0.2.132 |``, so the name cell is a place a number
///   demonstrably goes;
/// - a backticked token that names no file (`on `PATH``) cites nothing;
/// - two backticked tokens are ambiguous, and ambiguity reads as absence for
///   the same reason [pinnedInRequirements] refuses two pinning lines — a gate
///   that guesses can be green about the wrong file;
/// - an absolute path, a `..` segment, or a URL is not a file inside this
///   repository, so nothing here can check what it points at.
///
/// The version check does not care whether the number wears backticks. It used
/// to: every backticked span was stripped before the test, so `` `3.44.7` `` in
/// the name cell was the one revert shape that survived the rule written to
/// refuse it.
///
/// This is a per-row check, and a row is not the whole table: the section-wide
/// assertion in `the real files` is what refuses a second row for the same
/// subject, a row elsewhere in the document, and the number restated in prose
/// beside the subject's name.
String? citedPathInStackTable(String source, {required String rowName}) {
  final row = _stackRow(source, rowName: rowName);
  if (row == null) {
    return null;
  }
  final cell = pinnedInStackTable(source, rowName: rowName);
  if (cell == null) {
    return null;
  }
  final quoted = RegExp('`([^`]+)`').allMatches(cell);
  if (quoted.length != 1) {
    return null;
  }
  if (_restatesAVersion(row)) {
    return null;
  }
  // Trimmed and normalised: a cell written `pinned in ` ./a//b.txt ` ` cites the
  // same file `a/b.txt` does, and an unnormalised answer would fail the caller's
  // comparison against the real home with a diff of punctuation — a red gate on
  // a correct spine.
  final cited = _normalizedCitation(quoted.single.group(1)!.trim());
  if (!_looksLikePath(cited)) {
    return null;
  }
  return cited;
}

/// Why a Stack row cited nothing, in the terms that tell a reader what to do:
/// the row is gone or doubled, or the number has grown a second home again.
///
/// [row] is the whole row [_stackRow] answered, so the version branch reports
/// the same text the rule was applied to. Both use [_restatesAVersion] rather
/// than each testing for a version their own way — a message that explains a
/// different rule than the one that fired is worse than no message.
String _uncitedFailure({
  required String rowName,
  required String? row,
  required String? cell,
  required String home,
}) {
  if (row == null) {
    return 'the spine has no single parseable "$rowName" row in its `## Stack` '
        'section — either the row is gone or the table holds two of that name, '
        'and a gate that guessed between them could be green about the wrong '
        'one. $home is the home the row should cite.';
  }
  if (_restatesAVersion(row)) {
    return 'the spine\'s "$rowName" Stack row reads "${row.trim()}". $home is '
        'the one home of this version; stating the number in this row — '
        'instead of the citation, beside it, or over in the name cell — '
        'reintroduces the second, writable copy that used to drift. Cite the '
        'file and only the file.';
  }
  if (cell == null || cell.trim().isEmpty) {
    // Its own branch, because the message below interpolates the cell: an empty
    // one produced `Stack row reads "null"`, which quotes nothing and names no
    // edit. A blank cell is also the one shape `lint_spine.py`'s `version_pin`
    // rule catches, so saying so points at the faster check.
    return 'the spine\'s "$rowName" Stack row has an empty version cell, so it '
        'states nothing and cites nothing — the row is there and says no more '
        'than its absence would. $home is the home it should cite. '
        '(`lint_spine.py`\'s `version_pin` rule reports this one too.)';
  }
  return 'the spine\'s "$rowName" Stack row reads "$cell", which cites no file '
      'this gate can resolve. A citation has to be exactly one backticked '
      'repo-relative path — not a bare name, not two paths, not one that '
      'escapes the repository or names a remote. $home is what it should '
      'point at.';
}

/// The `flutter-version:` value in a GitHub workflow, or null.
///
/// Quotes are stripped, because `flutter-version: "3.44.8"` is the ordinary way
/// to stop YAML reading a two-dot version as something other than a string, and
/// an unstripped read reports a version that does not exist.
///
/// More than one pin reads as null for the same reason [pinnedInRequirements]
/// does: the moment a second job pins its own toolchain, reading only the first
/// silently stops covering the other.
String? flutterVersionInWorkflow(String source) {
  final matches = RegExp(
    r'''^\s*flutter-version:\s*([^\s#]+)''',
    multiLine: true,
  ).allMatches(source);
  if (matches.length != 1) {
    return null;
  }
  return _unquoted(matches.single.group(1)!);
}

String _unquoted(String value) {
  for (final quote in const ['"', "'"]) {
    if (value.length >= 2 && value.startsWith(quote) && value.endsWith(quote)) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

/// The text between the `## Stack` heading and the next heading of the same
/// level, or null when there is no such heading.
String? _stackSection(String source) {
  final heading = RegExp(r'^## Stack\s*$', multiLine: true).firstMatch(source);
  if (heading == null) {
    return null;
  }
  final rest = source.substring(heading.end);
  final next = RegExp(r'^## ', multiLine: true).firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path does not exist; this gate reads it and cannot pass without it');
  }
  return file.readAsStringSync();
}
