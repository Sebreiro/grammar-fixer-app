import 'dart:io';

import 'package:test/test.dart';

/// The two manual procedures that carry the claims this container cannot
/// observe, and the seven places that point at them.
///
/// **Why a test guards documentation.** Six of those seven places are
/// unconditionally skipped rows with a `fail()` body: they exist so a claim
/// nobody observed is owed rather than forgotten, and their skip prose now ends
/// by naming the procedure that says how to observe it — and, in most cases, the
/// specific step numbers. Prose that points at a file rots the moment the file
/// is renamed, and a skipped row reports nothing when it does: the run stays
/// green and the pointer quietly becomes a lie. Step numbers rot faster still,
/// because inserting one step silently misdirects every citation below it. So
/// the paths, the ledger ids each procedure has to name, each pointer clause and
/// each cited step number are pinned here instead.
///
/// This follows `desktop_entries_test.dart`'s existing convention rather than
/// inventing a second one: print what is unobserved in the same place the green
/// is, and assert that the file pointed at exists.
///
/// **Why this file lives in `test/architecture/`.** That is the mechanism that
/// gets these rows run at all. The CI gate is not a bare `dart test` — the bare
/// form cannot run in this repository, because it globs `test/` and crashes
/// trying to compile the `flutter_test` suites under `test/platform` and
/// `test/ui`. What `.github/workflows/ci.yml` runs is the scoped form,
/// `dart test --exclude-tags=live test/application test/architecture test/domain
/// test/infrastructure test/fakes_smoke_test.dart`. A sibling of the suites it
/// pins, over in `test/platform/`, would be run by nothing in the gate and only
/// under `flutter test` locally. Hence `package:test` and this directory.
void main() {
  group('the manual procedures exist', () {
    for (final procedure in _procedures) {
      test('${procedure.path} is committed', () {
        expect(
          File(procedure.path).existsSync(),
          isTrue,
          reason:
              'the ${procedure.name} procedure is missing from '
              '${procedure.path}. ${_pointersTo(procedure)} skipped '
              'row(s) name it by that exact path; renaming or deleting it '
              'leaves every one of them pointing at nothing, and a skipped '
              'row cannot report that itself',
        );
      });
    }
  });

  group('each procedure still names the claims it carries', () {
    for (final procedure in _procedures) {
      test('${procedure.path} names ${_list(procedure.claims)}', () {
        final steps = _stepsIn(_readOrFail(procedure.path));

        // Scoped to the steps, and deliberately not to the whole file: every
        // procedure opens with a "Ledger entries this procedure settles:"
        // header line naming all of them, so a whole-file scan would stay
        // green with every step deleted underneath it.
        final unattributed = steps.values
            .where(
              (step) =>
                  step.settles.isEmpty &&
                  !procedure.preconditionSteps.contains(step.number),
            )
            .map((step) => step.number)
            .toList();
        expect(
          unattributed,
          isEmpty,
          reason:
              'step(s) ${unattributed.join(", ")} of ${procedure.path} carry '
              'no `- *Settles:*` line naming a DW id. Every step has to say '
              'which ledger entry it settles, or the rows below cannot tell '
              'a dropped claim from a reworded one. If one of them genuinely '
              'settles nothing, it needs an explicit `*Settles:* none` bullet '
              'and its number added to that procedure\'s preconditionSteps',
        );

        // The other half of that allowance: a declared precondition step has to
        // *say* it settles nothing. Without this, listing a number in
        // preconditionSteps would excuse a step that simply lost its bullet.
        final silent = procedure.preconditionSteps
            .where((number) => steps[number]?.declaresNone != true)
            .toList();
        expect(
          silent,
          isEmpty,
          reason:
              'step(s) ${silent.join(", ")} of ${procedure.path} are declared '
              'as precondition steps but no longer open their `*Settles:*` '
              'bullet with `none`. That marker is the difference between a '
              'step that settles nothing on purpose and one whose attribution '
              'was dropped; the allowance only holds while the marker is there',
        );

        final found = {for (final step in steps.values) ...step.settles};
        final missing = procedure.claims.difference(found);
        expect(
          missing,
          isEmpty,
          reason:
              'no step of the ${procedure.name} procedure settles '
              '${_list(missing)} any more. A claim that leaves the steps is a '
              'claim nobody is going to observe, and nothing else would '
              'notice. Expected across its `*Settles:*` lines: '
              '${_list(procedure.claims)}. Found: ${_list(found)}. '
              'If a claim genuinely moved elsewhere, move the id in this row '
              'with it — do not just delete it there',
        );

        // The other direction. The procedures carry only the claims the
        // entries behind them own; anything else belongs under "Not covered
        // here" rather than absorbed into a step.
        final absorbed = found.difference(procedure.claims);
        expect(
          absorbed,
          isEmpty,
          reason:
              'a step of the ${procedure.name} procedure now settles '
              '${_list(absorbed)}, which this procedure does not carry. A '
              'claim the enumeration does not own goes under its "Not covered '
              'here" heading, not into a step — otherwise the procedure grows '
              'scope nobody agreed to and a completed run reads as settling '
              'more than it does. Declared: ${_list(procedure.claims)}',
        );
      });
    }
  });

  group('every step still states an action and an expected result', () {
    for (final procedure in _procedures) {
      test('${procedure.path} keeps every step comparable', () {
        final steps = _stepsIn(_readOrFail(procedure.path));

        final incomplete = <String>[];
        for (final step in steps.values) {
          final missing = _requiredBullets.difference(step.bullets);
          if (missing.isNotEmpty) {
            incomplete.add('${step.number} (missing ${missing.join(", ")})');
          }
        }
        expect(
          incomplete,
          isEmpty,
          reason:
              'step(s) ${incomplete.join("; ")} of ${procedure.path} no longer '
              'carry every bullet a step needs. An `*Action:*` with no '
              '`*Expected:*` leaves the operator nothing to compare against, '
              'which is the exact failure this whole bundle was written to '
              'prevent; a missing `*Applies to:*` strands the prerequisites, '
              'which name that line as the authority on what can be run. '
              'Required: ${_requiredBullets.join(", ")}',
        );
      });
    }
  });

  group('every numbered step is still there', () {
    for (final procedure in _procedures) {
      test('${procedure.path} keeps steps ${_numbers(procedure.steps)}', () {
        final markdown = _readOrFail(procedure.path);
        final duplicates = _duplicateStepNumbersIn(markdown);
        expect(
          duplicates,
          isEmpty,
          reason:
              '${procedure.path} has more than one step numbered '
              '${_numbers(duplicates)}. The parser below keys steps by number, '
              'so a repeat merges two steps into one entry and every citation '
              'to that number resolves to the merger — which is precisely the '
              'drift inserting a step without renumbering causes',
        );

        final found = _stepsIn(markdown).keys.toSet();
        expect(
          found,
          equals(procedure.steps),
          reason:
              '${procedure.path} no longer has exactly the steps this row '
              'declares. Declared: ${_numbers(procedure.steps)}. '
              'Found: ${_numbers(found)}. Missing: '
              '${_numbers(procedure.steps.difference(found))}. Added: '
              '${_numbers(found.difference(procedure.steps))}. The claim rows '
              'above cannot catch a removed step whose ledger id another step '
              'also settles, so the numbers are pinned here as well. If a step '
              'genuinely went away, take its number out of this row and check '
              'nothing still cites it',
        );
      });
    }
  });

  group('the results table still agrees with the steps', () {
    for (final procedure in _procedures) {
      test('${procedure.path} records every step exactly once', () {
        final markdown = _readOrFail(procedure.path);
        final table = _resultsTableRowsIn(markdown);

        expect(
          table.duplicated,
          isEmpty,
          reason:
              "${procedure.path}'s results table has more than one row for "
              'step(s) ${_numbers(table.duplicated)}. The operator fills this '
              'table in and hands it to whoever closes the entries, so a '
              'duplicated row means two observations arriving for one step '
              'with nothing to say which is which',
        );

        expect(
          table.rows.keys.toSet(),
          equals(procedure.steps),
          reason:
              "${procedure.path}'s results table no longer has exactly one row "
              'per step. Steps: ${_numbers(procedure.steps)}. Table rows: '
              '${_numbers(table.rows.keys.toSet())}. This table is the artifact '
              'that leaves the run, and it was pinned by nothing: a row could '
              'point at a step that does not exist, or a step could lose the '
              'row that carries its result, and every row here stayed green',
        );

        if (!procedure.resultsTableCarriesIds) {
          return;
        }

        final steps = _stepsIn(markdown);
        final disagreeing = <String>[];
        table.rows.forEach((number, ids) {
          final settles = steps[number]?.settles ?? const <String>{};
          if (!_sameIds(ids, settles)) {
            disagreeing.add(
              'step $number (table says ${_list(ids)}, '
              'step says ${_list(settles)})',
            );
          }
        });
        expect(
          disagreeing,
          isEmpty,
          reason:
              "${procedure.path}'s results table attributes "
              '${disagreeing.join("; ")}. The table and the step have to name '
              'the same entry, or the operator files a real measurement '
              'against the wrong one — a wrong-but-plausible record is worse '
              'than a missing one, because nothing downstream can tell',
        );
      });
    }
  });

  group('the lettered groups the pointers navigate by still exist', () {
    for (final procedure in _procedures.where((p) => p.groups.isNotEmpty)) {
      test('${procedure.path} keeps groups ${_list(procedure.groups)}', () {
        final markdown = _readOrFail(procedure.path);

        expect(
          _groupLettersIn(markdown),
          equals(procedure.groups),
          reason:
              '${procedure.path} no longer has exactly the lettered groups '
              'this row declares. Declared: ${_list(procedure.groups)}. Found: '
              '${_list(_groupLettersIn(markdown))}. Two skip reasons send a '
              'reader to a group by letter, and the X11-only constraint for '
              "the grab steps lives in group D's preamble — a reader who "
              'cannot find the group can lose the constraint entirely',
        );

        final dangling = _citedGroupsIn(markdown).difference(procedure.groups);
        expect(
          dangling,
          isEmpty,
          reason:
              '${procedure.path} refers to group(s) ${_list(dangling)}, which '
              'it does not have. It has ${_list(procedure.groups)}',
        );
      });
    }
  });

  group('the load-bearing cross-references still point at the right work', () {
    for (final citation in _internalCitations) {
      test('${citation.procedure.path}: "${citation.anchor}" resolves', () {
        final markdown = _readOrFail(citation.procedure.path);
        final sentence = _sentenceContaining(markdown, citation.anchor);

        expect(
          sentence,
          isNotEmpty,
          reason:
              '${citation.procedure.path} no longer contains "'
              '${citation.anchor}". That phrase carries a cross-reference this '
              'row resolves; if it was reworded, reword it here too rather '
              'than deleting the row',
        );

        final steps = _stepsIn(markdown);
        final cited = _citedStepsIn(sentence);
        final settled = {
          for (final number in cited) ...?steps[number]?.settles,
        };
        expect(
          settled,
          equals(citation.settles),
          reason:
              '"${citation.anchor}" in ${citation.procedure.path} cites '
              'step(s) ${_numbers(cited)}, which between them settle '
              '${_list(settled)} — not ${_list(citation.settles)} as this row '
              'declares. Existence is not enough for this reference: it tells '
              'the operator which measurements to redo, so a number that '
              'resolves to a real but different step sends them to repeat the '
              'wrong one and the claim is never observed at all',
        );
      });
    }
  });

  group('every skipped live suite is accounted for', () {
    test('no *_live_test.dart is guarded by nothing', () {
      final found = Directory('test/platform')
          .listSync()
          .map((entry) => entry.path)
          .where((path) => path.endsWith('_live_test.dart'))
          .toSet();

      expect(
        found,
        isNotEmpty,
        reason:
            'no test/platform/*_live_test.dart files were found at all, which '
            'means this row is reading the wrong directory and every '
            'conclusion below it is vacuous',
      );

      final unaccounted =
          found
              .difference(_pointers.keys.toSet())
              .difference(_unpinnedLiveSuites.keys.toSet())
              .toList()
            ..sort();
      expect(
        unaccounted,
        isEmpty,
        reason:
            'live suite(s) ${unaccounted.join(", ")} are neither pinned by '
            'this file nor listed in _unpinnedLiveSuites with a reason. An '
            'unconditionally skipped row that nothing pins can have its body, '
            'its skip or its stated premise changed with no run reporting it — '
            'and the gate never executes these suites. Adding a live suite '
            'should be a decision, not something this file absorbs silently',
      );
    });
  });

  group('the paths the procedures cite still exist', () {
    for (final procedure in _procedures) {
      test('${procedure.path} points only at real files', () {
        final missing =
            _repoPathsIn(_readOrFail(procedure.path))
                .where(
                  (path) =>
                      !File(path).existsSync() && !Directory(path).existsSync(),
                )
                .toList()
              ..sort();
        expect(
          missing,
          isEmpty,
          reason:
              '${procedure.path} cites ${missing.join(", ")}, which does not '
              'exist. The procedures name repository paths an operator is told '
              'to run or read — the installer script, the suites their claims '
              'came from, the sibling procedure — and prose that points at a '
              'renamed file rots exactly the way the skip reasons did before '
              'this file existed',
        );
      });
    }
  });

  group('the "Not covered here" heading still scopes each procedure', () {
    for (final procedure in _procedures) {
      test('${procedure.path} still lists what it does not carry', () {
        final section = _notCoveredHereIn(_readOrFail(procedure.path));

        expect(
          section,
          isNotEmpty,
          reason:
              '${procedure.path} has no "## Not covered here" section. That '
              'heading is how the procedure states its own boundary, and four '
              'skip reasons route claims to it by name — deleting it turns '
              'those clauses into lies with nothing to report it',
        );

        final absent = procedure.notCoveredHere
            .where((phrase) => !section.contains(phrase))
            .toList();
        expect(
          absent,
          isEmpty,
          reason:
              "${procedure.path}'s \"Not covered here\" section no longer "
              'names ${absent.join(", ")}. Each of those is a claim a reader '
              'could otherwise assume a completed run settles, and at least '
              'one skip reason says it is named there',
        );
      });
    }
  });

  group('the skipped rows still cannot pass', () {
    for (final suite in _pointers.keys) {
      test('$suite still has a fail() body', () {
        // Comments are stripped first, and every check below reads the
        // stripped source. Three mutations motivate that, each of which left
        // this file green when the checks were whole-file substring searches:
        // block-commenting the entire skipped row out (the row ceases to
        // exist, and the gate never runs these suites, so nothing else
        // notices); leaving `// fail(` behind in a comment while the body
        // itself becomes a passing assertion; and putting the skip behind an
        // environment variable so the row runs and passes when it is set.
        final source = _withoutComments(_readOrFail(suite));

        expect(
          _skipCountIn(source),
          1,
          reason:
              '$suite no longer has exactly one `skip:` argument in live code. '
              'Every row that reads a skip reason in this file takes the only '
              'one in the file; a second would leave one of them unpinned. '
              'Zero means the skipped row was deleted or commented out — the '
              'same thing to a reader and to CI, and this suite is never '
              'executed by the gate, so nothing else would report it',
        );
        expect(
          _skipIsUnconditionalIn(source),
          isTrue,
          reason:
              "$suite's `skip:` argument is no longer a plain string literal. "
              'A conditional skip — `skip: Platform.environment[...] == null '
              "? '...' : false` — lets the row run and pass whenever the "
              'variable is set, which is a claim nobody observed being '
              'reported as met while still looking like a skip',
        );
        expect(
          _failIsInSkippedBody(source),
          isTrue,
          reason:
              '$suite no longer calls fail() inside the body of its skipped '
              'row. It is meant to be an unconditionally skipped row whose '
              'body could never pass if it ran — that is what stops a claim '
              'nobody observed from being reported as met. The check is '
              'bounded to the enclosing `test(` call on purpose: '
              'hidden_window_test.dart carries thirteen other rows, so a '
              'whole-file search there is one unrelated fail() away from '
              'saying nothing at all',
        );
      });
    }
  });

  group('the procedures do not misdirect their own readers', () {
    for (final procedure in _procedures) {
      test('${procedure.path} cites only steps it has', () {
        final markdown = _readOrFail(procedure.path);
        final referenced = _citedStepsIn(markdown);
        final dangling = referenced.difference(procedure.steps);

        expect(
          dangling,
          isEmpty,
          reason:
              '${procedure.path} refers to step(s) ${_numbers(dangling)}, '
              'which it does not have. Both procedures cross-reference their '
              'own steps heavily — prerequisites, group preambles, cleanup and '
              'the results table all cite numbers — and inserting one step '
              'renumbers every reference below it at once. It has '
              '${_numbers(procedure.steps)}',
        );
      });
    }
  });

  group('each skipped row still points at its procedure', () {
    _pointers.forEach((suite, procedure) {
      test('$suite names $procedure in its skip reason', () {
        // The skip argument alone, not the whole file: a path left behind in a
        // doc comment or a constant would satisfy a whole-file `contains`
        // while the reason a reader actually sees named nothing.
        final reason = _skipReasonIn(_readOrFail(suite));

        expect(
          reason,
          isNotEmpty,
          reason:
              '$suite has no `skip:` argument this row can read. It is meant '
              'to be an unconditionally skipped row with a fail() body; if it '
              'stopped being one, that is the thing to look at first',
        );
        expect(
          reason,
          contains(procedure),
          reason:
              '$suite lost its pointer clause. Its skip reason has to name '
              '$procedure, so a reader who hits the skipped row finds the '
              'steps rather than prose alone. (Adjacent string literals are '
              'joined before this match, so `dart format` splitting the path '
              'across two lines is fine — an actual deletion is not.)',
        );
      });
    });
  });

  group('the step numbers each skipped row cites still resolve', () {
    _citations.forEach((suite, citation) {
      test('$suite cites steps that exist and settle what it says', () {
        final cited = _citedStepOrderIn(_skipReasonIn(_readOrFail(suite)));

        expect(
          cited,
          equals(citation.steps.keys.toList()),
          reason:
              '$suite cites a different sequence of steps than this row '
              'declares. Declared, in order: '
              '${citation.steps.keys.join(", ")}. Found in its skip reason: '
              '${cited.join(", ")}. Either the clause changed and this row has '
              'to change with it, or a citation was added, dropped or '
              'reordered. Order is checked on purpose: a clause that keeps the '
              'same numbers while swapping which claim each one is cited for '
              'reads perfectly and sends the reader to the wrong observation, '
              'which no set comparison can see',
        );

        final steps = _stepsIn(_readOrFail(citation.procedure.path));
        citation.steps.forEach((number, claim) {
          final step = steps[number];
          expect(
            step,
            isNotNull,
            reason:
                '$suite cites step $number of ${citation.procedure.path}, and '
                'that procedure has no step $number. It has '
                '${_numbers(steps.keys.toSet())}. Inserting or removing a step '
                'renumbers everything after it, which is exactly the silent '
                'misdirection this row exists to catch',
          );
          expect(
            step!.settles,
            contains(claim),
            reason:
                '$suite cites step $number of ${citation.procedure.path} for '
                '$claim, but that step now settles ${_list(step.settles)}. '
                'The numbers still line up and the claim behind them moved, '
                'which is worse than a broken link: the clause reads correctly '
                'and sends the reader to the wrong observation',
          );
        });
      });
    });
  });

  test('desktop_entries_test.dart still advertises the desktop procedure', () {
    // The seventh pointer site, and the only one that is not a skip reason:
    // that suite's closing row prints the path from a constant. A constant is
    // no safer than prose — it is just a string in a different place.
    // Joined first, for the same reason the pointer rows join: a longer path
    // would push the initializer past the line limit and `dart format` would
    // split it into two adjacent literals. Matching only the first half would
    // then report a drift that a correct rename did not cause.
    final source = _joinAdjacentLiterals(
      _readOrFail(_desktopEntriesArchitectureSuite),
    );
    final declaration = RegExp(
      r"_desktopSessionChecklist\s*=\s*'([^']*)'",
    ).firstMatch(source);

    expect(
      declaration,
      isNotNull,
      reason:
          '$_desktopEntriesArchitectureSuite no longer declares a '
          '_desktopSessionChecklist constant. Its closing row prints where '
          "DW-87's owed work is written down, and that print is the only "
          'place a green run mentions it',
    );
    expect(
      declaration!.group(1),
      _desktopChecklist.path,
      reason:
          '$_desktopEntriesArchitectureSuite advertises a different path than '
          'the skipped rows name. Both have to be ${_desktopChecklist.path}, '
          'or a reader is sent to one of two files depending on which one they '
          'read first',
    );
    expect(
      source,
      contains(r'$_desktopSessionChecklist'),
      reason:
          'the constant is declared but no longer interpolated into that '
          "suite's print, so the path it pins reaches nobody",
    );
  });

  test('the two procedures are named in the run output', () {
    // The same fix desktop_entries_test.dart's own closing row applies: the
    // procedures are Markdown in a test directory, inert to both runners, so
    // nothing about them appears in a run unless a row prints it. A green run
    // should say where the owed work is written down.
    //
    // ignore: avoid_print
    print(
      'NOT OBSERVED HERE — this container has no session: no compositor, no '
      'xdg-desktop-portal, no session bus and no login. '
      '(Correcting what this line used to say: it also claimed "no window '
      'manager", and that a bare display "would supply none of the above". '
      'Xvfb, xvfb-run, openbox 3.6.1, xwininfo, xdotool, xev and xprop are '
      'all installed, and on 2026-09-04 a display plus that window manager '
      'was stood up and found a major CAP-14 defect no green row had — '
      'test/platform/panel-toggle-observation.md, filed as DW-122 with the '
      'refuted premise as DW-123. What it still supplies none of is the list '
      'above, which is why the claims below stay owed rather than '
      'automated.) The runtime claims '
      'behind ${_list(_allClaims())} are owed on a real Linux desktop, and '
      'what to actually do there is written down, step by step, in:\n'
      '  session claims (${_list(_sessionChecklist.claims)})\n'
      '    : ${_sessionChecklist.path}\n'
      '  desktop-entry claims (${_list(_desktopChecklist.claims)}), which need '
      'a login cycle\n'
      '    : ${_desktopChecklist.path}\n'
      '  both are manual: read them, do not run them\n'
      "  DW-39 is only half reachable: the session procedure's step 9 records "
      'how a refused grab presents on any build, but step 11 (GTK main-thread '
      'marshalling) needs a build carrying the dart:ffi keybinder registrar, '
      'which no build in this tree has. A completed run does not settle it.',
    );

    for (final procedure in _procedures) {
      expect(
        File(procedure.path).existsSync(),
        isTrue,
        reason: 'the file this row points at must exist: ${procedure.path}',
      );
    }
  });
}

/// One committed manual procedure and the ledger entries it settles.
final class _Procedure {
  const _Procedure({
    required this.name,
    required this.path,
    required this.claims,
    required this.steps,
    required this.preconditionSteps,
    required this.groups,
    required this.resultsTableCarriesIds,
    required this.notCoveredHere,
  });

  /// How the failure reasons refer to it in prose.
  final String name;

  final String path;

  /// The deferred-work ids the procedure's steps settle between them.
  ///
  /// Checked in *both* directions. Missing means a claim left the steps and
  /// nobody will observe it. Extra means the procedure quietly grew a claim the
  /// enumeration behind it does not own — the thing the "Not covered here"
  /// heading exists to prevent. Only `*Settles:*` lines are read, so a step that
  /// merely mentions an id in its prose does not count either way.
  final Set<String> claims;

  /// Every step number the procedure has to keep.
  ///
  /// The claim sets above cannot carry this: several ids are settled by more
  /// than one step, so deleting a step whose id another step also names leaves
  /// the claim check green. Steps 14 and 16 of the session procedure and step 1
  /// of the desktop one were each removable that way. Pinning the numbers
  /// themselves is what makes "a dropped claim fails a run" true at step
  /// granularity rather than only at id granularity.
  final Set<int> steps;

  /// Steps that settle nothing on purpose, and say so with an explicit `none`.
  ///
  /// Declared here rather than inferred, because "this step has no ledger id"
  /// and "this step lost its ledger id" look identical from the parser's side.
  /// A step listed here must still carry a `*Settles:*` bullet opening with
  /// `none`: the point is that its emptiness is a statement, not an omission.
  final Set<int> preconditionSteps;

  /// The lettered group headings (`## D. The real grab`) the procedure keeps.
  ///
  /// Two skip reasons navigate by letter rather than by number — "group C step 5
  /// for the visible-and-focused panel", "those are group D of …" — and the
  /// session procedure's own X11 gate lives in group D's preamble. A renamed
  /// heading strands all of it, and letters are invisible to the step-number
  /// rows. Empty for a procedure whose sections are numbered steps throughout.
  final Set<String> groups;

  /// Whether the results table's second column carries the ledger ids, so it can
  /// be checked against each step's `*Settles:*` line.
  ///
  /// The desktop procedure's column holds prose descriptions of DW-87's four
  /// facts instead, so only its step-number column is checkable.
  final bool resultsTableCarriesIds;

  /// Phrases the procedure's "Not covered here" section has to keep naming.
  ///
  /// Four skip reasons route claims *to* that heading by name, so deleting it
  /// turns those clauses into lies with nothing to report it. It is also the
  /// mechanism the scope rule leans on: a claim the enumeration does not own is
  /// listed here rather than folded into a step.
  final Set<String> notCoveredHere;
}

const _Procedure _sessionChecklist = _Procedure(
  name: 'session',
  path: 'test/platform/runtime-observation-checklist.md',
  claims: {'DW-9', 'DW-25', 'DW-26', 'DW-39', 'DW-44', 'DW-50', 'DW-72'},
  steps: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16},
  preconditionSteps: {},
  groups: {'A', 'B', 'C', 'D', 'E'},
  resultsTableCarriesIds: true,
  notCoveredHere: {
    'test/platform/tray_live_test.dart',
    'test/platform/desktop-session-checklist.md',
    'DW-53',
    'Accessibility',
    // The two bullets three skip clauses route claims to by name. Deleting
    // either left every row green while `settings_screen_live_test.dart` went
    // on asserting its claims (3), (4) and (5) are "named there".
    'The Wayland portal',
    'Config-file watching',
    // Distinctive phrases rather than the bare words `clipboard` and `meta`:
    // `meta` matches any word containing it, so it was satisfied by prose that
    // said nothing about the modifier claim.
    'The real system clipboard',
    'The `meta` modifier',
  },
);

const _Procedure _desktopChecklist = _Procedure(
  name: 'desktop-entries',
  path: 'test/platform/desktop-session-checklist.md',
  claims: {'DW-87'},
  steps: {1, 2, 3, 4, 5},
  // Step 1 installs the entries; it is the precondition for 2 to 5 and settles
  // none of DW-87's four facts itself.
  preconditionSteps: {1},
  groups: {},
  resultsTableCarriesIds: false,
  notCoveredHere: {
    'test/platform/tray_live_test.dart',
    'test/platform/runtime-observation-checklist.md',
  },
);

const List<_Procedure> _procedures = [_sessionChecklist, _desktopChecklist];

const String _desktopEntriesArchitectureSuite =
    'test/architecture/desktop_entries_test.dart';

/// Every skipped row that carries a pointer clause, and the procedure path its
/// skip reason has to name.
final Map<String, String> _pointers = {
  'test/architecture/hidden_window_test.dart': _sessionChecklist.path,
  'test/platform/panel_visibility_live_test.dart': _sessionChecklist.path,
  'test/platform/x11_hotkey_live_test.dart': _sessionChecklist.path,
  'test/platform/correction_panel_live_test.dart': _sessionChecklist.path,
  'test/platform/settings_screen_live_test.dart': _sessionChecklist.path,
  'test/platform/desktop_entries_live_test.dart': _desktopChecklist.path,
};

/// What each skip reason's step numbers are cited *for*.
///
/// Declared here rather than parsed out of the prose, because "which claim is
/// this citation about" is not recoverable from the sentence. The declaration
/// is kept honest from both ends: the set of numbers is compared against the
/// numbers the clause actually cites, and each number is resolved against the
/// procedure's own `*Settles:*` line.
final class _Citation {
  const _Citation({required this.procedure, required this.steps});

  final _Procedure procedure;

  /// Step number to the ledger id the citing suite invokes it for.
  final Map<int, String> steps;
}

final Map<String, _Citation> _citations = {
  'test/architecture/hidden_window_test.dart': const _Citation(
    procedure: _sessionChecklist,
    steps: {1: 'DW-9', 2: 'DW-9', 3: 'DW-9', 4: 'DW-9'},
  ),
  'test/platform/panel_visibility_live_test.dart': const _Citation(
    procedure: _sessionChecklist,
    steps: {5: 'DW-26', 6: 'DW-26', 7: 'DW-25'},
  ),
  'test/platform/x11_hotkey_live_test.dart': const _Citation(
    procedure: _sessionChecklist,
    // Step 11 — the FFI registrar's GTK-main-thread marshalling — was dropped
    // from this citation in phase 1, and the omission is deliberate rather than
    // an oversight. Keybinder calls GDK, so a keybinder-based FFI registrar
    // would have had to marshal its bind onto the GTK main thread, and step 11
    // is the observation that would have settled whether that worked. The route
    // that shipped opens its own X `Display` and never touches GTK or GDK, so
    // the marshalling surface does not exist to observe. Step 9 still carries
    // DW-39, which is the entry's actual subject: whether a refused grab is
    // readable. Step 11 itself is left in the procedure, flagged for retirement
    // rather than deleted here, because retiring a documented step is a ledger
    // decision and not this gate's to take.
    steps: {8: 'DW-44', 9: 'DW-39', 10: 'DW-44', 12: 'DW-44'},
  ),
  'test/platform/correction_panel_live_test.dart': const _Citation(
    procedure: _sessionChecklist,
    steps: {5: 'DW-26', 6: 'DW-26', 12: 'DW-44', 13: 'DW-50'},
  ),
  'test/platform/settings_screen_live_test.dart': const _Citation(
    procedure: _sessionChecklist,
    // Declared in the order the clause cites them, which is not ascending.
    steps: {13: 'DW-50', 10: 'DW-44', 15: 'DW-72'},
  ),
  'test/platform/desktop_entries_live_test.dart': const _Citation(
    procedure: _desktopChecklist,
    steps: {2: 'DW-87', 3: 'DW-87', 4: 'DW-87', 5: 'DW-87'},
  ),
};

/// One numbered step of a procedure, and the ids its `*Settles:*` line names.
final class _Step {
  const _Step({
    required this.number,
    required this.settles,
    required this.declaresNone,
    required this.bullets,
  });

  final int number;
  final Set<String> settles;

  /// The labelled bullets the step carries — `Applies to`, `Action`, `Expected`,
  /// `Settles` — plus [_checkboxLabel] for its progress checkbox.
  ///
  /// An action with no expected result is the defect the whole arrangement
  /// exists to prevent: it leaves the operator nothing to compare an
  /// observation against. That was checked only by a human reading the spec's
  /// "Manual checks" bullet, which no run executes.
  final Set<String> bullets;

  /// Whether the step's `*Settles:*` bullet opens with the explicit `none`
  /// marker, as opposed to carrying no such bullet at all.
  ///
  /// The two are very different and an empty [settles] cannot tell them apart:
  /// one is a precondition step saying so on purpose, the other is a step that
  /// lost its attribution. Only the first is allowed, and only where
  /// [_Procedure.preconditionSteps] declares it.
  final bool declaresNone;
}

/// A cross-reference inside a procedure whose *target* matters, not just its
/// existence.
///
/// The dangling-reference row resolves every `step N` in both procedures against
/// the step set, which catches a renumbering that leaves a number behind but not
/// one that lands on a real step doing different work. These are the references
/// where landing on the wrong step silently costs an observation.
final class _InternalCitation {
  const _InternalCitation({
    required this.procedure,
    required this.anchor,
    required this.settles,
  });

  final _Procedure procedure;

  /// A distinctive fragment of the sentence carrying the reference.
  final String anchor;

  /// What the steps that sentence cites have to settle between them.
  final Set<String> settles;
}

final List<_InternalCitation> _internalCitations = [
  // Step 16 redoes the geometry and affordance measurements at 1.5x text scale.
  // If it cites the wrong steps the operator repeats the wrong measurement, and
  // DW-72's scaled number — the only one there is — is never taken.
  _InternalCitation(
    procedure: _sessionChecklist,
    anchor: 'repeat steps',
    settles: {'DW-50', 'DW-72'},
  ),
];

/// The sentence of [markdown] containing [anchor], joined across line wraps.
String _sentenceContaining(String markdown, String anchor) {
  final flattened = markdown.replaceAll(RegExp(r'\s*\n\s*'), ' ');
  final at = flattened.indexOf(anchor);
  if (at < 0) {
    return '';
  }
  var start = flattened.lastIndexOf('. ', at);
  start = start < 0 ? 0 : start + 2;
  var end = flattened.indexOf('. ', at);
  end = end < 0 ? flattened.length : end;
  return flattened.substring(start, end);
}

/// Live suites this file deliberately does not pin, and why.
///
/// Both are unconditionally skipped `fail()` rows that no row here guards. They
/// are recorded rather than fixed because their claims belong to ledger entries
/// outside this bundle — but they are recorded, so the next live suite added
/// cannot slip in unnoticed the way these two did.
const Map<String, String> _unpinnedLiveSuites = {
  'test/platform/tray_live_test.dart':
      'its tray claims belong to an entry outside this bundle, and the intent '
      'forbids adding them to either procedure',
  'test/platform/wayland_hotkey_live_test.dart':
      'it names no ledger id at all, so there is no claim to route to a '
      'procedure; filed as deferred work rather than absorbed here',
};

/// How many pinned places name [procedure] by that exact path.
///
/// Not just the skip reasons: the sibling procedure's "Not covered here" section
/// routes claims to it by path, and `desktop_entries_test.dart` prints it from a
/// constant. All three kinds are pinned in this file, so a rename that fixes
/// only the skip reasons fails again on the next run — which is a bad thing for
/// a failure message to understate.
int _pointersTo(_Procedure procedure) {
  final fromSkipReasons = _pointers.values
      .where((path) => path == procedure.path)
      .length;
  final fromSiblings = _procedures
      .where(
        (other) =>
            other.path != procedure.path &&
            other.notCoveredHere.contains(procedure.path),
      )
      .length;
  final fromArchitectureSuite = procedure.path == _desktopChecklist.path
      ? 1
      : 0;
  return fromSkipReasons + fromSiblings + fromArchitectureSuite;
}

/// The step numbers a procedure's results table has a row for, and any it
/// repeats.
_ResultsTable _resultsTableRowsIn(String markdown) {
  final rows = <int, Set<String>>{};
  final duplicated = <int>{};
  final pattern = RegExp(r'^\|\s*(\d+)\s*\|([^|]*)\|');
  for (final line in markdown.split('\n')) {
    final match = pattern.firstMatch(line);
    if (match == null) {
      continue;
    }
    final number = int.tryParse(match.group(1)!);
    if (number == null) {
      continue;
    }
    if (rows.containsKey(number)) {
      duplicated.add(number);
    }
    rows[number] = _ledgerIdsIn(match.group(2)!);
  }
  return _ResultsTable(rows: rows, duplicated: duplicated);
}

final class _ResultsTable {
  const _ResultsTable({required this.rows, required this.duplicated});

  final Map<int, Set<String>> rows;
  final Set<int> duplicated;
}

bool _sameIds(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

/// The lettered group headings a procedure declares: `## D. The real grab`.
Set<String> _groupLettersIn(String markdown) => {
  for (final match in RegExp(
    r'^## ([A-Z])\.',
    multiLine: true,
  ).allMatches(markdown))
    match.group(1)!,
};

/// The group letters a piece of prose refers to: `group D`, `groups C and D`.
Set<String> _citedGroupsIn(String prose) => {
  for (final match in RegExp(
    r'groups?\s+([A-E])\b',
    caseSensitive: false,
  ).allMatches(prose))
    match.group(1)!.toUpperCase(),
};

/// Every repository path a procedure's prose cites.
///
/// Anchored on the top-level directories that actually exist in this repository,
/// so shell prose like `${XDG_DATA_HOME:-~/.local/share}/applications/` is not
/// mistaken for one. Directories count as existing: both procedures cite
/// `test/platform/` as a location as well as naming files inside it.
Set<String> _repoPathsIn(String markdown) => {
  for (final match in RegExp(
    r'(?<![\w/])(?:test|lib|tool|docs)/[\w./-]*\w',
  ).allMatches(markdown))
    match.group(0)!,
};

Set<String> _allClaims() => {
  for (final procedure in _procedures) ...procedure.claims,
};

/// [path]'s contents, or a failure naming the file rather than a
/// `FileSystemException` from somewhere inside a matcher.
String _readOrFail(String path) {
  final file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason:
        '$path is missing, so the row that reads it cannot run. Restore it '
        'or update this suite — a rename is the likeliest cause',
  );
  return file.readAsStringSync();
}

/// The numbered steps of a procedure, keyed by number.
///
/// Both heading styles the two procedures use are accepted: `**7. …**` inside a
/// lettered group, and `## 3. …` as its own section.
Map<int, _Step> _stepsIn(String markdown) {
  final steps = <int, Set<String>>{};
  final declaresNone = <int>{};
  final labels = <int, Set<String>>{};

  int? current;
  StringBuffer? bullet;

  // A `*Settles:*` bullet is read as one unit, joined across however many lines
  // it occupies. Parsing each line on its own is wrong in both directions: it
  // drops an id that landed on a continuation line, and it defeats the `none`
  // marker, because the continuation of a disclaiming bullet does not itself
  // begin with `none`. The desktop procedure's step 1 is exactly that bullet —
  // it wraps, and reading line two alone registered the very id it disclaims.
  void flush() {
    final text = bullet?.toString();
    final step = current;
    bullet = null;
    if (text == null || step == null) {
      return;
    }
    if (text.trim().toLowerCase().startsWith('none')) {
      declaresNone.add(step);
    }
    steps[step]!.addAll(_settledIdsIn(text));
  }

  for (final line in markdown.split('\n')) {
    final match = _stepHeading.firstMatch(line);
    if (match != null) {
      flush();
      final number = int.tryParse(match.group(1)!);
      current = number;
      if (number != null) {
        steps.putIfAbsent(number, () => <String>{});
        labels.putIfAbsent(number, () => <String>{});
      }
      continue;
    }
    if (current == null) {
      continue;
    }
    final label = _bulletLabel.firstMatch(line);
    if (label != null) {
      labels[current]!.add(label.group(1)!.trim());
    } else if (_checkboxLine.hasMatch(line)) {
      labels[current]!.add(_checkboxLabel);
    }
    if (_settlesLine.hasMatch(line)) {
      flush();
      bullet = StringBuffer(line.replaceFirst(_settlesLine, '').trim());
      continue;
    }
    if (bullet != null && _bulletContinuation.hasMatch(line)) {
      bullet!.write(' ${line.trim()}');
      continue;
    }
    flush();
  }
  flush();

  return {
    for (final entry in steps.entries)
      entry.key: _Step(
        number: entry.key,
        settles: entry.value,
        declaresNone: declaresNone.contains(entry.key),
        bullets: labels[entry.key] ?? const <String>{},
      ),
  };
}

/// Both heading styles the two procedures use: `**7. …**` inside a lettered
/// group, and `## 3. …` as its own section.
final RegExp _stepHeading = RegExp(r'^(?:## |\*\*)(\d+)\.');

final RegExp _settlesLine = RegExp(r'^- \*Settles:\*');

/// A labelled bullet of a step: `- *Expected:* …` yields `Expected`.
final RegExp _bulletLabel = RegExp(r'^- \*([^*:]+):\*');

/// The progress checkbox a step carries so a human can track position through a
/// procedure that spans a whole login session.
final RegExp _checkboxLine = RegExp(r'^- \[[ xX]\]');

/// Stands in for the checkbox in [_Step.bullets]; not a real bullet label.
const String _checkboxLabel = '[ ]';

/// Bullets every step of both procedures has to carry.
///
/// `Action` and `Expected` are the intent's first constraint — a step states a
/// concrete action and a result a reader can compare against. `Applies to` is
/// the session gate: without it an X11 operator runs the portal steps, removing
/// the desktop entry changes nothing, and the step's own text has them record a
/// false "AD-11's premise does not hold". `Settles` carries the ledger id. The
/// checkbox is what makes these prose-and-checkbox procedures rather than prose.
const Set<String> _requiredBullets = {
  'Applies to',
  'Action',
  'Expected',
  'Settles',
  _checkboxLabel,
};

/// An indented line that continues the bullet above rather than opening one.
final RegExp _bulletContinuation = RegExp(r'^ {2,}\S');

/// Step numbers that appear on more than one heading.
Set<int> _duplicateStepNumbersIn(String markdown) {
  final seen = <int>{};
  final repeated = <int>{};
  for (final line in markdown.split('\n')) {
    final match = _stepHeading.firstMatch(line);
    if (match == null) {
      continue;
    }
    final number = int.tryParse(match.group(1)!);
    if (number != null && !seen.add(number)) {
      repeated.add(number);
    }
  }
  return repeated;
}

/// The ids a `*Settles:*` line actually commits to.
///
/// Not every `DW-…` on such a line is a claim the step settles: a precondition
/// step says which entry it is *not* one of, and a bare id scan reads that
/// denial as an assertion — leaving the whole desktop procedure satisfiable by
/// the one step that settles nothing. An explicit `none` opens the disclaiming
/// form, and anything after it is prose.
///
/// Takes the bullet's whole body, already joined across its continuation lines
/// by [_stepsIn]. It must not be handed one line at a time: `none` is a property
/// of the bullet, not of a line, and a wrapped disclaimer would leak its
/// negated id from line two.
Set<String> _settledIdsIn(String body) {
  final trimmed = body.trim();
  if (trimmed.toLowerCase().startsWith('none')) {
    return const {};
  }
  return _ledgerIdsIn(trimmed);
}

/// The body of a procedure's `## Not covered here` section.
String _notCoveredHereIn(String markdown) {
  final lines = markdown.split('\n');
  final start = lines.indexWhere(
    (line) => line.trimRight().toLowerCase() == '## not covered here',
  );
  if (start < 0) {
    return '';
  }
  final rest = lines.skip(start + 1).toList();
  final end = rest.indexWhere((line) => line.startsWith('## '));
  return (end < 0 ? rest : rest.take(end)).join('\n');
}

/// How many `skip:` arguments [source] carries.
int _skipCountIn(String source) => 'skip:'.allMatches(source).length;

/// [source] with Dart comments removed and string literals left intact.
///
/// Every check that asks "is this still live code" reads the stripped form.
/// Comments are invisible to the compiler and to a reader skimming for the
/// skipped row, but not to a substring search: `// fail(` satisfies a whole-file
/// `contains('fail(')`, and a block comment can delete an entire skipped row
/// without changing one live token. Literals are preserved byte for byte,
/// because the pointer rows read their prose.
String _withoutComments(String source) {
  final out = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final char = source[index];
    if (char == "'" || char == '"') {
      out.write(char);
      index += 1;
      while (index < source.length) {
        final inner = source[index];
        if (inner == r'\') {
          // An escape consumes the next character whatever it is, so a `\'`
          // does not end the literal.
          final stop = index + 2 <= source.length ? index + 2 : source.length;
          out.write(source.substring(index, stop));
          index = stop;
          continue;
        }
        out.write(inner);
        index += 1;
        if (inner == char) {
          break;
        }
      }
      continue;
    }
    if (char == '/' && index + 1 < source.length) {
      final next = source[index + 1];
      if (next == '/') {
        // Stop at the newline rather than past it: dropping the line break
        // would join the skip argument to whatever followed, and
        // `_skipReasonIn` bounds itself on `\n  );`.
        final end = source.indexOf('\n', index);
        index = end < 0 ? source.length : end;
        continue;
      }
      if (next == '*') {
        final end = source.indexOf('*/', index + 2);
        index = end < 0 ? source.length : end + 2;
        continue;
      }
    }
    out.write(char);
    index += 1;
  }
  return out.toString();
}

/// Whether the single `skip:` argument is a plain string literal.
///
/// `skip:` accepts a `bool` as well as a reason, so a ternary on an environment
/// variable is a legal row that runs — and passes — whenever the condition is
/// false. That is the one shape an unconditionally skipped row must never take.
bool _skipIsUnconditionalIn(String source) {
  final start = source.indexOf('skip:');
  if (start < 0) {
    return false;
  }
  return RegExp('^\\s*r?[\'"]').hasMatch(source.substring(start + 5));
}

/// Whether `fail(` appears inside the body of the skipped row itself.
///
/// Bounded to the enclosing `test(` call. Five of the six suites hold a single
/// row, so a whole-file check happened to be tight for them; the sixth holds
/// fourteen, and there the whole-file form is vacuous the moment any other row
/// calls `fail()`. The body precedes the `skip:` argument in all six.
bool _failIsInSkippedBody(String source) {
  final skip = source.indexOf('skip:');
  if (skip < 0) {
    return false;
  }
  final open = source.lastIndexOf('test(', skip);
  if (open < 0) {
    return false;
  }
  return source.substring(open, skip).contains('fail(');
}

/// Every `DW-<n>` in [text], as whole ids.
///
/// Whole ids matter: a plain substring search for `DW-9` is satisfied by
/// `DW-95`, so a procedure that had lost DW-9 entirely could still pass while
/// naming an unrelated entry.
Set<String> _ledgerIdsIn(String text) => {
  for (final match in RegExp(r'DW-\d+').allMatches(text)) match.group(0)!,
};

/// The `skip:` argument of a suite's single `test(...)` call, with adjacent
/// string literals joined.
///
/// Bounded at the call's closing `  );` rather than running to end of file,
/// because `hidden_window_test.dart` carries helper functions after its skipped
/// row and a path mentioned in one of those is not a pointer a reader sees.
String _skipReasonIn(String rawSource) {
  // Comments stripped first, so a `skip:` written in a doc comment above the row
  // cannot capture this search and hand every row below the wrong text.
  final source = _withoutComments(rawSource);
  final start = source.indexOf('skip:');
  if (start < 0) {
    return '';
  }
  final end = source.indexOf('\n  );', start);
  // Deliberately not "fall back to the rest of the file". If the terminator
  // moves — a row wrapped in a `group`, a different indent, a reflow — the
  // fallback would silently widen every match below into the whole-file
  // `contains` this helper exists to avoid, and widening a check never turns a
  // row red. Returning nothing does.
  if (end < 0) {
    return '';
  }
  return _joinAdjacentLiterals(source.substring(start, end));
}

/// [source] with adjacent Dart string literals concatenated.
///
/// The skip reasons these rows read are one long literal split across many
/// lines by `dart format`, and where it splits is not stable — a clause added
/// above a pointer can push the path onto two lines and break a naive
/// `contains`. Removing every `'` … `'` seam first makes the match depend on
/// the prose rather than on the formatter.
String _joinAdjacentLiterals(String source) =>
    source.replaceAll(RegExp(r"'\s+'"), '');

/// The step numbers a piece of prose cites: `step 13`, `steps 5 and 6`,
/// `steps 1 to 3`, `steps 2, 3 and 4`.
///
/// Dashes are deliberately **not** separators here, in either the list or the
/// range sense. In running prose an em dash is punctuation far more often than
/// it is a range — `step 12 — the 100 ms budget` would otherwise parse as steps
/// 12 through 100 — and no clause in this repository needs a dash range, since
/// `to` says the same thing unambiguously. A dash simply ends the list.
Set<int> _citedStepsIn(String prose) => _citedStepOrderIn(prose).toSet();

/// The step numbers a piece of prose cites, in the order it cites them.
///
/// Order is what distinguishes "the numbers still line up" from "the claim
/// behind them moved". A clause that swaps which claim it sends the reader to —
/// keeping the same set of numbers — reads correctly and misdirects; the set
/// check cannot see it, and the declared order can.
List<int> _citedStepOrderIn(String prose) {
  final pattern = RegExp(
    r'steps?\s+(\d+(?:\s*(?:,|and|to)\s*\d+)*)',
    caseSensitive: false,
  );
  return [
    for (final match in pattern.allMatches(prose))
      ..._expandStepList(match.group(1)!),
  ];
}

/// `1 to 3` to `[1, 2, 3]`; `5 and 6` to `[5, 6]`, in citation order.
List<int> _expandStepList(String list) {
  final token = RegExp(r'(\d+)|(,|and|to)');
  const rangeSeparators = {'to'};
  final expanded = <int>[];

  int? previous;
  String? separator;
  for (final match in token.allMatches(list)) {
    final digits = match.group(1);
    if (digits == null) {
      separator = match.group(2);
      continue;
    }
    final value = int.tryParse(digits);
    if (value == null) {
      continue;
    }
    final start = previous;
    if (start != null && rangeSeparators.contains(separator)) {
      // A descending range is a typo, not a range. Expanding it to nothing
      // would swallow the second number silently; keeping both endpoints puts
      // whichever one does not exist in front of the row that resolves them.
      final lower = start <= value ? start : value;
      final upper = start <= value ? value : start;
      for (var number = lower; number <= upper; number++) {
        if (!expanded.contains(number)) {
          expanded.add(number);
        }
      }
    } else if (!expanded.contains(value)) {
      expanded.add(value);
    }
    previous = value;
    separator = null;
  }
  return expanded;
}

/// Ledger ids in a stable, readable order for a failure message.
///
/// `tryParse` rather than `parse`, and a fallback rather than a throw: this
/// runs *inside* a `reason:` argument, which Dart evaluates eagerly whether or
/// not the matcher failed. A typo in one of the hand-written id constants would
/// otherwise replace every failure message in this file — including the ones
/// explaining the typo — with a `FormatException`.
String _list(Set<String> ids) {
  if (ids.isEmpty) {
    return '(none)';
  }
  final sorted = ids.toList()
    ..sort((a, b) {
      final left = int.tryParse(a.replaceFirst('DW-', ''));
      final right = int.tryParse(b.replaceFirst('DW-', ''));
      if (left == null || right == null) {
        return a.compareTo(b);
      }
      return left.compareTo(right);
    });
  return sorted.join(', ');
}

/// Step numbers in ascending order for a failure message.
String _numbers(Set<int> steps) {
  if (steps.isEmpty) {
    return '(none)';
  }
  final sorted = steps.toList()..sort();
  return sorted.join(', ');
}
