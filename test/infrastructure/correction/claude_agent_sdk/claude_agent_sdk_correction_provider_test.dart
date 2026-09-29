import 'dart:async';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/provider_registry.dart';
import 'package:test/test.dart';

import '../../../fakes/fake_logger.dart';

/// Behaviour tests for `ClaudeAgentSdkCorrectionProvider` (AD-19), covering
/// every row of the spec's I/O & Edge-Case Matrix except the live smoke.
/// Each row runs against a bash stub standing in for the Python sidecar:
/// interpreter `/bin/bash`, sidecar = a generated script in a temp dir.
void main() {
  const preset = Preset(
    id: 'test-preset',
    providerId: 'claude-agent-sdk',
    model: 'test-model',
    systemPrompt: 'unused by stubs',
  );

  late Directory tempDir;
  late FakeLogger logger;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sidecar_stub_');
    logger = FakeLogger();
  });

  tearDown(() => tempDir.delete(recursive: true));

  /// Every stub reads the request line first so the adapter's stdin write
  /// never hits a broken pipe on the happy rows.
  File stubScript(String scriptBody, {bool readsRequest = true}) {
    final prelude = readsRequest ? 'read -r _request || true\n' : '';
    return File('${tempDir.path}/stub_sidecar.sh')
      ..writeAsStringSync('#!/bin/bash\n$prelude$scriptBody');
  }

  ClaudeAgentSdkCorrectionProvider providerForStub(
    String scriptBody, {
    String interpreterPath = '/bin/bash',
    bool readsRequest = true,
    Duration timeout = ClaudeAgentSdkCorrectionProvider.defaultTimeout,
  }) {
    return ClaudeAgentSdkCorrectionProvider(
      interpreterPath: interpreterPath,
      sidecarPath: stubScript(scriptBody, readsRequest: readsRequest).path,
      logger: logger,
      timeout: timeout,
    );
  }

  Future<List<CorrectionEvent>> correctWith(
    ClaudeAgentSdkCorrectionProvider provider,
  ) => provider.correct(text: 'input under test', preset: preset).toList();

  group('happy path', () {
    test('CAP-5: tagged text plus done streams deltas then '
        'CorrectionCompleted with all three registers', () async {
      final provider = providerForStub('''
echo '{"type":"text","text":"FORMAL: a\\nCASUAL: b\\n"}'
echo '{"type":"text","text":"SHORTER: c\\nEND\\n"}'
echo '{"type":"done"}'
''');

      final events = await correctWith(provider);

      expect(events.whereType<SuggestionDelta>(), isNotEmpty);
      expect(events.last, isA<CorrectionCompleted>());
      final completed = events.whereType<CorrectionCompleted>().single;
      expect(completed.suggestions.map((s) => s.text), ['a', 'b', 'c']);
    });
  });

  group('failure translation', () {
    test('CAP-13: a malformed NDJSON line yields exactly one '
        'CorrectionFailed(providerError)', () async {
      final provider = providerForStub('''
echo 'this is not json'
echo '{"type":"done"}'
''');

      final events = await correctWith(provider);

      _expectSingleFailure(events, CorrectionFailureKind.providerError);
    });

    test('CAP-13: a sidecar error line maps its kind by name to '
        'CorrectionFailed(providerUnavailable)', () async {
      final provider = providerForStub('''
echo '{"type":"error","kind":"providerUnavailable","message":"cannot import claude_agent_sdk"}'
exit 1
''');

      final events = await correctWith(provider);

      final failure = _expectSingleFailure(
        events,
        CorrectionFailureKind.providerUnavailable,
      );
      expect(failure.message, contains('claude_agent_sdk'));
    });

    test('CAP-13: a non-zero exit without a terminal line yields '
        'providerError naming the exit code', () async {
      final provider = providerForStub('exit 3\n');

      final events = await correctWith(provider);

      final failure = _expectSingleFailure(
        events,
        CorrectionFailureKind.providerError,
      );
      expect(failure.message, contains('3'));
    });

    test('CAP-13: a clean exit without a done or error line yields '
        'providerError', () async {
      final provider = providerForStub('''
echo '{"type":"text","text":"FORMAL: a\\n"}'
exit 0
''');

      final events = await correctWith(provider);

      expect(events.last, isA<CorrectionFailed>());
      final failure = events.whereType<CorrectionFailed>().single;
      expect(failure.kind, CorrectionFailureKind.providerError);
    });

    test('CAP-13: a sidecar that closes its output but never exits still '
        'terminates instead of hanging the correction', () async {
      final provider = providerForStub('''
exec 1>&-
sleep 30
''');

      final events = await correctWith(provider);

      _expectSingleFailure(events, CorrectionFailureKind.providerError);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('CAP-13: a nonexistent interpreter yields '
        'CorrectionFailed(providerUnavailable) without throwing', () async {
      final provider = providerForStub(
        'echo unreachable\n',
        interpreterPath: '/nonexistent/python3',
      );

      final events = await correctWith(provider);

      final failure = _expectSingleFailure(
        events,
        CorrectionFailureKind.providerUnavailable,
      );
      expect(failure.message, contains('/nonexistent/python3'));
    });

    test('CAP-13: an interpreter that exists but cannot be executed yields '
        'providerUnavailable', () async {
      // Passes the path preflight, so the classification has to come from
      // setsid's 126 exit code — the "host problem, not provider fault" rule.
      final unexecutable = File('${tempDir.path}/not_executable.py')
        ..writeAsStringSync('print("never runs")\n');
      await Process.run('chmod', ['-x', unexecutable.path]);
      final provider = providerForStub(
        'echo unreachable\n',
        interpreterPath: unexecutable.path,
      );

      final events = await correctWith(provider);

      _expectSingleFailure(events, CorrectionFailureKind.providerUnavailable);
    });

    test('CAP-13: a sidecar that dies before reading its request still '
        'terminates exactly once', () async {
      // The real ImportError path exits at module import, before main() reads
      // stdin — so the adapter's request write hits a broken pipe.
      final provider = providerForStub('''
echo '{"type":"error","kind":"providerUnavailable","message":"cannot import claude_agent_sdk"}'
exit 1
''', readsRequest: false);

      final events = await correctWith(provider);

      _expectSingleFailure(events, CorrectionFailureKind.providerUnavailable);
    });

    test('CAP-13: untagged model text plus done fails as malformedResponse '
        'via the parser', () async {
      final provider = providerForStub('''
echo '{"type":"text","text":"no tags here at all"}'
echo '{"type":"done"}'
''');

      final events = await correctWith(provider);

      _expectSingleFailure(events, CorrectionFailureKind.malformedResponse);
    });
  });

  group('protocol discipline (AD-3, AD-19)', () {
    test('AD-19: text lines arriving after done are dead protocol and are '
        'ignored', () async {
      final provider = providerForStub('''
echo '{"type":"text","text":"FORMAL: a\\nCASUAL: b\\nSHORTER: c\\nEND\\n"}'
echo '{"type":"done"}'
echo '{"type":"text","text":"LATE: ignored\\n"}'
echo '{"type":"error","kind":"providerError","message":"too late"}'
''');

      final events = await correctWith(provider);

      final completed = events.whereType<CorrectionCompleted>().single;
      expect(completed.suggestions.map((s) => s.text), ['a', 'b', 'c']);
      expect(events.whereType<CorrectionFailed>(), isEmpty);
    });

    test('AD-19: one process per correction — a second correct() on the same '
        'provider succeeds', () async {
      final provider = providerForStub('''
echo '{"type":"text","text":"FORMAL: a\\nCASUAL: b\\nSHORTER: c\\nEND\\n"}'
echo '{"type":"done"}'
''');

      final first = await correctWith(provider);
      final second = await correctWith(provider);

      for (final events in [first, second]) {
        expect(events.whereType<CorrectionCompleted>().single.suggestions, [
          isA<Object>(),
          isA<Object>(),
          isA<Object>(),
        ]);
      }
    });
  });

  group('cancellation (AD-4, AD-19)', () {
    test('AD-4: cancelling after the first delta emits nothing afterwards, '
        'ever', () async {
      final provider = providerForStub('''
echo '{"type":"text","text":"FORMAL: par"}'
sleep 30
echo '{"type":"text","text":"tial\\nCASUAL: x\\nSHORTER: y\\n"}'
echo '{"type":"done"}'
''');
      final events = <CorrectionEvent>[];
      final firstDelta = Completer<void>();
      final subscription = provider
          .correct(text: 'input under test', preset: preset)
          .listen((event) {
            events.add(event);
            if (!firstDelta.isCompleted) {
              firstDelta.complete();
            }
          });

      await firstDelta.future;
      final eventCountAtCancel = events.length;
      // cancel() completes only once teardown has run — the process group is
      // dead and every subscription is cancelled — so the assertion below is
      // ordered against the run's own shutdown, not against a wall clock.
      await subscription.cancel();
      await pumpEventQueue();

      expect(events.length, eventCountAtCancel);
      expect(events.whereType<CorrectionCompleted>(), isEmpty);
      expect(events.whereType<CorrectionFailed>(), isEmpty);
    });

    test('AD-19: cancellation kills the whole process group — the sleep '
        'grandchild dies, not just the leader', () async {
      final pidFile = '${tempDir.path}/grandchild.pid';
      final provider = providerForStub('''
sleep 300 &
echo \$! > '$pidFile'
echo '{"type":"text","text":"FORMAL: x"}'
wait
''');
      final firstDelta = Completer<void>();
      final subscription = provider
          .correct(text: 'input under test', preset: preset)
          .listen((_) {
            if (!firstDelta.isCompleted) {
              firstDelta.complete();
            }
          });

      // The stub writes the pid before the delta, so the file exists here.
      await firstDelta.future;
      final grandchildPid = File(pidFile).readAsStringSync().trim();
      await subscription.cancel();

      expect(
        await _processDied(grandchildPid),
        isTrue,
        reason: 'a leader-only kill would orphan the sleep grandchild',
      );
    });

    test('AD-19: a sidecar that ignores SIGTERM is escalated to SIGKILL and '
        'its group still dies', () async {
      final pidFile = '${tempDir.path}/trapping_grandchild.pid';
      final provider = providerForStub('''
trap '' TERM
sleep 300 &
echo \$! > '$pidFile'
echo '{"type":"text","text":"FORMAL: x"}'
wait
''');
      final firstDelta = Completer<void>();
      final subscription = provider
          .correct(text: 'input under test', preset: preset)
          .listen((_) {
            if (!firstDelta.isCompleted) {
              firstDelta.complete();
            }
          });

      await firstDelta.future;
      final grandchildPid = File(pidFile).readAsStringSync().trim();
      await subscription.cancel();

      expect(
        await _processDied(grandchildPid),
        isTrue,
        reason: 'SIGTERM is trapped, so only the SIGKILL escalation can win',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('AD-4: cancelling before the sidecar has spawned still tears the '
        'group down and emits nothing', () async {
      final pidFile = '${tempDir.path}/early_cancel_grandchild.pid';
      final provider = providerForStub('''
sleep 300 &
echo \$! > '$pidFile'
echo '{"type":"text","text":"FORMAL: x"}'
wait
''');
      final events = <CorrectionEvent>[];
      // Cancel in the same turn as listen(), inside the async spawn gap: the
      // post-spawn _terminated re-check is the only thing that can kill a
      // process nobody has a handle to yet.
      final subscription = provider
          .correct(text: 'input under test', preset: preset)
          .listen(events.add);
      await subscription.cancel();

      expect(events, isEmpty);
      expect(
        await _grandchildFromFile(pidFile).then(_processDiedOrNeverStarted),
        isTrue,
        reason: 'a cancel during spawn must not leak an orphaned group',
      );
    });
  });

  group('timeout (AD-19, CAP-13)', () {
    test('CAP-13: a registry-built provider with a few-hundred-millisecond '
        'timeoutMillis fails as timeout and takes its grandchild with '
        'it', () async {
      // Reads its request, then never speaks again — the stalled network
      // call the ledger's hang report describes, with no output, no EOF and
      // no exit to end the run any other way.
      final pidFile = '${tempDir.path}/stalled_grandchild.pid';
      final script = stubScript('''
sleep 300 &
echo \$! > '$pidFile'
wait
''');
      final provider = ProviderRegistry(logger: logger).create(
        ClaudeAgentSdkCorrectionProvider.providerId,
        ProviderConfig(
          settings: {
            ClaudeAgentSdkCorrectionProvider.interpreterSettingsKey:
                '/bin/bash',
            ClaudeAgentSdkCorrectionProvider.sidecarSettingsKey: script.path,
            ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey: '300',
          },
        ),
      );
      if (provider == null) {
        fail('the registry must know its shipped provider id');
      }

      final elapsed = Stopwatch()..start();
      final events = await provider
          .correct(text: 'input under test', preset: preset)
          .toList();
      elapsed.stop();

      _expectSingleFailure(events, CorrectionFailureKind.timeout);
      expect(
        elapsed.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason:
            'bounded near the configured 300 ms, not merely under the 60 s '
            'default — the slack is what would let a regression hide',
      );
      expect(
        await _processDiedOrNeverStarted(await _grandchildFromFile(pidFile)),
        isTrue,
        reason: 'the timeout terminal kills the group, like every other one',
      );
    }, timeout: const Timeout(Duration(seconds: 90)));

    test(
      'CAP-13: the timeout message names the deadline it enforced',
      () async {
        final provider = providerForStub(
          'sleep 300\n',
          timeout: const Duration(milliseconds: 250),
        );

        final events = await correctWith(provider);

        final failure = _expectSingleFailure(
          events,
          CorrectionFailureKind.timeout,
        );
        expect(failure.message, contains('250'));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('AD-3: a run that completes inside its deadline yields one terminal, '
        'and the deadline passing afterwards adds nothing', () async {
      const deadline = Duration(milliseconds: 300);
      final provider = providerForStub('''
echo '{"type":"text","text":"FORMAL: a\\nCASUAL: b\\nSHORTER: c\\nEND\\n"}'
echo '{"type":"done"}'
''', timeout: deadline);
      final events = <CorrectionEvent>[];

      final subscription = provider
          .correct(text: 'input under test', preset: preset)
          .listen(events.add);
      await subscription.asFuture<void>();
      final countAtClose = events.length;
      await Future<void>.delayed(deadline * 2);

      expect(events.last, isA<CorrectionCompleted>());
      expect(
        events,
        hasLength(countAtClose),
        // Deliberately not claiming this proves the timer was cancelled: the
        // _emit terminal guard would suppress a late timeout either way, and
        // an uncancelled Timer is not observable from here. What it does pin
        // is AD-3 — one terminal, nothing after it.
        reason: 'AD-3 allows exactly one terminal event per correction',
      );
    });

    test('AD-19: the deadline is total wall clock, not idle time — a sidecar '
        'streaming deltas past it still times out', () async {
      // Every other timeout row uses a silent stub, so an implementation
      // that rearmed the timer on each delta would pass them all while
      // reinstating the unbounded run AD-19 exists to prevent.
      const deadline = Duration(milliseconds: 400);
      final provider = providerForStub('''
while true; do
  echo '{"type":"text","text":"FORMAL: x"}'
  sleep 0.05
done
''', timeout: deadline);

      final events = await correctWith(provider);

      expect(
        events.whereType<SuggestionDelta>(),
        isNotEmpty,
        reason:
            'the stub has to actually be streaming for this to mean '
            'anything',
      );
      final terminals = events.whereType<CorrectionFailed>();
      expect(terminals, hasLength(1));
      expect(terminals.single.kind, CorrectionFailureKind.timeout);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('AD-19: an absent timeoutMillis leaves a real deadline in force, not '
        'a degenerate one', () async {
      // The registry test only asserts that nothing was logged, so replacing
      // the fallback with Duration(milliseconds: 1) passes it — while making
      // every correction fail instantly as timeout.
      final events = await _stalledRunEventsWithin(
        _registryProvider(
          logger,
          stubScript('sleep 300\n'),
          timeoutMillis: null,
        ),
        preset,
        const Duration(seconds: 1),
      );

      expect(
        events.whereType<CorrectionFailed>(),
        isEmpty,
        reason:
            'the adapter default is 60 s; a millisecond default would '
            'have terminated long ago',
      );
    });

    test('AD-19: a rejected timeoutMillis falls back to a real deadline, not '
        'a degenerate one', () async {
      final events = await _stalledRunEventsWithin(
        _registryProvider(
          logger,
          stubScript('sleep 300\n'),
          timeoutMillis: 'soon',
        ),
        preset,
        const Duration(seconds: 1),
      );

      expect(events.whereType<CorrectionFailed>(), isEmpty);
    });
  });

  group('logging', () {
    test(
      'AD-19: sidecar stderr is reported without its potentially private text',
      () async {
        final provider = providerForStub('''
echo 'sidecar diagnostic line' >&2
echo '{"type":"text","text":"FORMAL: a\\nCASUAL: b\\nSHORTER: c\\nEND\\n"}'
echo '{"type":"done"}'
''');

        await correctWith(provider);

        expect(
          await _loggedMessageArrives(logger, 'sidecar reported an error'),
          isTrue,
          reason: 'a Python-side failure remains identifiable without its body',
        );
        expect(
          logger.lines.every(
            (entry) => !entry.toString().contains('sidecar diagnostic line'),
          ),
          isTrue,
        );
      },
    );
  });
}

CorrectionFailed _expectSingleFailure(
  List<CorrectionEvent> events,
  CorrectionFailureKind kind,
) {
  expect(events, hasLength(1), reason: 'exactly one terminal, nothing else');
  final failure = events.single;
  expect(failure, isA<CorrectionFailed>());
  expect((failure as CorrectionFailed).kind, kind);
  return failure;
}

/// The grandchild pid if the stub got far enough to record one; null when
/// the cancel beat the spawn, which is itself a pass.
Future<String?> _grandchildFromFile(String pidFile) async {
  for (var attempt = 0; attempt < 10; attempt += 1) {
    final file = File(pidFile);
    if (file.existsSync() && file.readAsStringSync().trim().isNotEmpty) {
      return file.readAsStringSync().trim();
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return null;
}

Future<bool> _processDiedOrNeverStarted(String? pid) async =>
    pid == null || await _processDied(pid);

/// Polls `kill -0` until the signal fails — the process is gone — or a
/// deadline passes. Polling absorbs the instant between SIGTERM delivery
/// and the grandchild actually terminating.
Future<bool> _processDied(String pid) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    final probe = await Process.run('kill', ['-0', pid]);
    if (probe.exitCode != 0) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// Stderr reporting races the terminal event, so the assertion polls briefly.
Future<bool> _loggedMessageArrives(FakeLogger logger, String message) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    final found = logger.lines.any((entry) => entry.message == message);
    if (found) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

/// A provider built the way the composition root will build it, so the
/// registry's own settings parsing is part of what these rows exercise.
CorrectionProvider _registryProvider(
  FakeLogger logger,
  File script, {
  required String? timeoutMillis,
}) {
  final provider = ProviderRegistry(logger: logger).create(
    ClaudeAgentSdkCorrectionProvider.providerId,
    ProviderConfig(
      settings: {
        ClaudeAgentSdkCorrectionProvider.interpreterSettingsKey: '/bin/bash',
        ClaudeAgentSdkCorrectionProvider.sidecarSettingsKey: script.path,
        ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey: ?timeoutMillis,
      },
    ),
  );
  if (provider == null) {
    fail('the registry must know its shipped provider id');
  }
  return provider;
}

/// Everything a stalled run emitted inside [window], then teardown. Used to
/// observe that a fallback deadline is a real one — the run must still be
/// alive when the window closes.
Future<List<CorrectionEvent>> _stalledRunEventsWithin(
  CorrectionProvider provider,
  Preset preset,
  Duration window,
) async {
  final events = <CorrectionEvent>[];
  final subscription = provider
      .correct(text: 'input under test', preset: preset)
      .listen(events.add);
  await Future<void>.delayed(window);
  await subscription.cancel();
  return events;
}
