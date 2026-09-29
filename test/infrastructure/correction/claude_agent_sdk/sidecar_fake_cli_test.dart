import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../support/fake_claude_cli.dart';

/// The AD-19 sidecar's two non-happy branches, driven through a stub `claude`
/// CLI instead of a real one.
///
/// Both branches — an error `result` message, and the zero-delta
/// `AssistantMessage` fallback — are decided by what the SDK's child process
/// says, so nothing short of controlling that process reaches them. The stub is
/// what makes them cheap: no network, no model, and no nested real `claude`,
/// which is the process that has been observed terminating a dev session.
///
/// The third row is the control the first two need. "The fallback fires when no
/// deltas arrived" is only meaningful beside "it does not fire when they did",
/// and the double-emission it guards against is the failure a reader of the
/// sidecar would most plausibly reintroduce.
///
/// The rows spawn the sidecar script directly rather than going through
/// `ClaudeAgentSdkCorrectionProvider`, because the environment is exactly what
/// has to be controlled and the adapter deliberately exposes no seam for it.
/// The adapter's own translation of these NDJSON lines is covered by its unit
/// rows; what is under test here is the Python.
void main() {
  final skipReason = FakeClaudeCli.unavailableReason();

  group('the sidecar under a stub claude CLI (AD-19)', () {
    late FakeClaudeCli harness;

    setUp(() {
      final reason = skipReason;
      if (reason != null) {
        // Only reachable under `--run-skipped`, which overrides the group's
        // skip. Failing with the banner is the honest answer there: the rows
        // were forced to run on a host that cannot run them, and a
        // LateInitializationError on `harness` would say none of that.
        fail(reason);
      }
      harness = FakeClaudeCli.create();
      addTearDown(harness.dispose);
    });

    test('AD-19: an error result becomes exactly one error line naming the '
        'subtype, and exits non-zero', () async {
      final result = await harness.runSidecar(fixtureName: 'result_is_error');

      expect(_ndjsonLines(result.stdout as String), [
        {
          'type': 'error',
          'kind': 'providerError',
          'message': 'result error_during_execution: the model refused',
        },
      ]);
      expect(result.exitCode, 1);
    });

    test('AD-19: the error line is the whole failure — nothing is written to '
        'stderr, which the adapter forwards into the daemon log', () async {
      // The defect this pins: `sys.exit(1)` from inside the SDK`s `async
      // for` left a SystemExit traceback and "RuntimeError: aclose():
      // asynchronous generator is already running" on stderr beside the one
      // correct error line, so an all-day daemon wrote a traceback into its
      // log on every provider error.
      final result = await harness.runSidecar(fixtureName: 'result_is_error');

      expect(
        result.stderr,
        isEmpty,
        reason:
            'a failure must leave as one protocol line, not as a Python '
            'traceback the daemon then logs',
      );
    });

    test(
      'AD-19: an assistant message with no stream deltas is forwarded as the '
      'non-streaming fallback, then done',
      () async {
        final result = await harness.runSidecar(fixtureName: 'assistant_only');

        expect(_ndjsonLines(result.stdout as String), [
          {'type': 'text', 'text': _correctedText},
          {'type': 'done'},
        ]);
        expect(result.exitCode, 0);
      },
    );

    test(
      'CAP-5: stream deltas are forwarded in order and the assistant message '
      'carrying the same text is not replayed',
      () async {
        // The control for the row above. Forwarding both would double every
        // character the user sees, and the parser would then fail the
        // correction on duplicated register tags.
        final result = await harness.runSidecar(
          fixtureName: 'streaming_deltas',
        );

        expect(_ndjsonLines(result.stdout as String), [
          {'type': 'text', 'text': 'FORMAL: I went'},
          {'type': 'text', 'text': _correctedTextTail},
          {'type': 'done'},
        ]);
        expect(result.exitCode, 0);
      },
    );

    test('AD-19: the SDK spawned the stub, not a real claude CLI', () async {
      // Every row above is only evidence about the sidecar if the process it
      // talked to was ours. `PATH` order is the mechanism; this is the
      // observation — the stub logs nothing unless it actually ran.
      await harness.runSidecar(fixtureName: 'assistant_only');

      final log = File(harness.logPath);
      expect(log.existsSync(), isTrue);
      final entries = log.readAsStringSync();
      expect(entries, isNotEmpty);
      expect(
        entries,
        contains('test/support/fake_claude_cli/claude.py'),
        reason: 'the process the SDK spawned must be this repository\'s stub',
      );
    });
    // One skip for the whole group rather than one per row: the banner is
    // long, and a reader needs it once with the group named — not five times.
  }, skip: skipReason);

  test('an unrunnable harness says which rows it skipped, why, and the one '
      'command that enables them', () {
    // Runs everywhere, including where the harness itself cannot: a skip whose
    // reason never reaches the run output is indistinguishable from a row that
    // was never written.
    final reason = FakeClaudeCli.unavailableReason();
    if (reason == null) {
      // Provisioned host: the rows above ran, so there is no banner to check.
      // The banner's own content is checked on the path that produces it.
      return;
    }
    expect(reason, contains(FakeClaudeCli.provisionCommand));
    expect(reason, contains(FakeClaudeCli.venvInterpreterPath));
  });

  test('on CI the harness must be available, because a skip there is a green '
      'run that exercised none of the sidecar', () {
    // The banner above makes the skip legible to a human reading the output.
    // Nobody reads CI's output on a green run, and the group's `skip:` means an
    // unprovisioned runner reports success having executed neither branch this
    // story exists to close — revert `raise SidecarFailure` to a `fail()` inside
    // the `async for` and the traceback comes back with a green check beside it.
    //
    // So the story's "the skip count must stay 2" stops being something a person
    // has to notice in a log and becomes an assertion, on the one host where
    // provisioning is mandatory. `CI` is set to `true` by GitHub Actions and by
    // every other runner worth naming; locally the row is a no-op, which is
    // deliberate — an unprovisioned laptop is a legitimate state and the banner
    // is the right answer there.
    if (Platform.environment['CI'] != 'true') {
      return;
    }
    expect(
      FakeClaudeCli.unavailableReason(),
      isNull,
      reason:
          'CI runs tool/provision_sidecar.sh before dart test precisely so '
          'these rows run. If this fails, the provisioning step failed or was '
          'removed, and every row above skipped into a green result',
    );
  });
}

const String _correctedText =
    'FORMAL: I went to the store yesterday.\n'
    'CASUAL: I went to the store yesterday.\n'
    'SHORTER: I went to the store.\n'
    'END';

const String _correctedTextTail =
    ' to the store yesterday.\n'
    'CASUAL: I went to the store yesterday.\n'
    'SHORTER: I went to the store.\n'
    'END';

/// Every non-blank stdout line, decoded. Asserting on decoded objects rather
/// than raw text keeps the rows from failing on key order or spacing, which the
/// protocol does not fix.
List<Object?> _ndjsonLines(String output) => [
  for (final line in const LineSplitter().convert(output))
    if (line.trim().isNotEmpty) jsonDecode(line),
];
