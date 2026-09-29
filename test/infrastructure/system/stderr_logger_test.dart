import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/system/stderr_logger.dart';
import 'package:test/test.dart';

import '../../fakes/fake_clock.dart';

/// Behaviour tests for `StderrLogger`: one structured line per call, timed by
/// the injected `Clock` rather than the wall clock. The sink is a real
/// [IOSink] over an in-memory stream, so nothing reaches the real stderr and
/// the bytes actually written are what gets asserted.
void main() {
  late FakeClock clock;
  late StreamController<List<int>> written;
  late List<String> lines;
  late IOSink sink;
  late StderrLogger logger;

  setUp(() {
    clock = FakeClock(millis: 1700000000000);
    written = StreamController<List<int>>();
    lines = [];
    utf8.decoder
        .bind(written.stream)
        .transform(const LineSplitter())
        .listen(lines.add);
    sink = IOSink(written.sink);
    logger = StderrLogger(clock: clock, sink: sink);
  });

  tearDown(() => sink.close());

  Future<List<Map<String, Object?>>> loggedEntries() async {
    await sink.flush();
    await pumpEventQueue();
    return [for (final line in lines) jsonDecode(line) as Map<String, Object?>];
  }

  test('AD-7: every level writes exactly one parseable JSON line carrying '
      'level, message, context and the clock timestamp', () async {
    logger.info('daemon started', context: {'pid': 42});
    clock.advance(5);
    logger.warning('sidecar stderr', context: {'line': 'traceback'});
    clock.advance(5);
    logger.error('correction failed', context: {'kind': 'timeout'});

    final entries = await loggedEntries();

    expect(entries, hasLength(3));
    expect(
      [for (final entry in entries) entry['level']],
      ['info', 'warning', 'error'],
    );
    expect(
      [for (final entry in entries) entry['message']],
      ['daemon started', 'sidecar stderr', 'correction failed'],
    );
    expect(
      [for (final entry in entries) entry['timestamp']],
      [1700000000000, 1700000000005, 1700000000010],
      reason: 'the timestamp comes from the Clock port, never DateTime.now()',
    );
    expect(entries.first['context'], {'pid': 42});
  });

  test('AD-7: a call without context still writes one line, with an empty '
      'context object', () async {
    logger.info('no context here');

    final entries = await loggedEntries();

    expect(entries, hasLength(1));
    expect(entries.single['context'], isEmpty);
  });

  test('AD-7: a message containing a newline still occupies one log line, '
      'because the payload is JSON-escaped', () async {
    logger.error('first\nsecond');

    final entries = await loggedEntries();

    expect(entries, hasLength(1));
    expect(entries.single['message'], 'first\nsecond');
  });

  test('AD-7: a context value the JSON codec does not know is rendered rather '
      'than thrown — a diagnostic must never take the daemon down', () async {
    logger.warning('odd context', context: {'duration': Duration.zero});

    final entries = await loggedEntries();

    final context = entries.single['context'];
    expect(context, isA<Map<String, Object?>>());
    expect((context! as Map<String, Object?>)['duration'], isA<String>());
  });

  test('AD-7: a cyclic context degrades to a line without it instead of '
      'throwing out of the catch handler that logged it', () {
    // toEncodable only rescues an unknown type; a cycle throws
    // JsonCyclicError straight past it. This method is called from catch
    // handlers, so a throw here kills the path meant to report a failure.
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;

    expect(
      () => logger.error('cyclic context', context: cyclic),
      returnsNormally,
    );
  });

  test('AD-7: the degraded line still carries the level, message and '
      'timestamp — only the context is dropped', () async {
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;

    logger.error('cyclic context', context: cyclic);
    final entries = await loggedEntries();

    expect(entries, hasLength(1));
    expect(entries.single['level'], 'error');
    expect(entries.single['message'], 'cyclic context');
    expect(entries.single['timestamp'], 1700000000000);
    expect(entries.single['context'], isEmpty);
    expect(entries.single['contextError'], isNotNull);
  });
}
