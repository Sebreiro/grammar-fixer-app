import 'dart:convert';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/file_logger.dart';
import 'package:test/test.dart';

import '../../fakes/fake_clock.dart';

void main() {
  late Directory directory;
  late File output;
  late IOSink stderrSink;
  late File diagnostics;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('file_logger_');
    output = File('${directory.path}/config/logs/grammmar-corrector.log');
    diagnostics = File('${directory.path}/stderr');
    stderrSink = diagnostics.openWrite();
  });
  tearDown(() async {
    await stderrSink.close();
    await directory.delete(recursive: true);
  });

  FileLogger logger() =>
      FileLogger(clock: FakeClock(millis: 42), stderrSink: stderrSink);
  Future<List<Map<String, Object?>>> entries() async => [
    for (final line in await output.readAsLines())
      jsonDecode(line) as Map<String, Object?>,
  ];

  test(
    'CAP-13: queued startup errors reach the file once path and config are ready',
    () async {
      final log = logger();
      log.error('startup error');
      await log.open(output.path);
      log.configureMaxBytes(2048);
      await log.close();
      expect((await entries()).single['message'], 'startup error');
    },
  );

  test(
    'AD-14: a launch that never opens the file only drains stderr',
    () async {
      final log = logger();
      log.info('the resident daemon was notified');
      await log.close();
      expect(await output.exists(), isFalse);
      await stderrSink.flush();
      expect(
        await diagnostics.readAsString(),
        contains('resident daemon was notified'),
      );
    },
  );

  test(
    'CAP-13: disk write failures are reported once and do not escape',
    () async {
      final log = logger();
      await log.open('/dev/full');
      log.error('first failure');
      log.error('second failure');
      await log.close();
      await stderrSink.flush();
      final lines = await diagnostics.readAsLines();
      expect(
        lines.where((line) => line.contains('log file is unavailable')),
        hasLength(1),
      );
      expect(lines.any((line) => line.contains('second failure')), isTrue);
    },
    skip: !File('/dev/full').existsSync(),
  );

  test(
    'CAP-13: every log level reaches disk and stderr and close drains pending writes',
    () async {
      final log = logger();
      await log.open(output.path);
      log.info('started');
      log.warning('warning');
      log.error('failed', context: {'kind': 'providerError'});
      await log.close();
      await log.close();
      expect((await entries()).map((entry) => entry['level']), [
        'info',
        'warning',
        'error',
      ]);
      expect((await entries()).last['context'], {'kind': 'providerError'});
      await stderrSink.flush();
      expect(await diagnostics.readAsLines(), await output.readAsLines());
    },
  );

  test(
    'CAP-13: a restart appends without losing earlier logs below the configured limit',
    () async {
      final first = logger();
      await first.open(output.path);
      first.error('first failure');
      await first.close();
      final second = logger();
      await second.open(output.path);
      second.error('second failure');
      await second.close();
      expect((await entries()).map((entry) => entry['message']), [
        'first failure',
        'second failure',
      ]);
    },
  );

  test(
    'CAP-13: cycling rewrites one file at the byte limit and keeps complete JSON lines',
    () async {
      final log = logger();
      await log.open(output.path);
      log.configureMaxBytes(1024);
      for (var index = 0; index < 20; index++) {
        log.error('failure $index', context: {'detail': 'é' * 150});
      }
      await log.close();
      expect(await output.length(), lessThanOrEqualTo(1024));
      expect((await entries()).last['message'], 'failure 19');
      expect((await output.parent.list().toList()), hasLength(1));
      expect((await entries()).length, lessThan(20));
    },
  );

  test(
    'CAP-13: an entry larger than the limit retains a marked error summary',
    () async {
      final log = logger();
      await log.open(output.path);
      log.configureMaxBytes(1024);
      log.error('huge failure', context: {'detail': 'x' * 3000});
      await log.close();
      expect(await output.length(), lessThanOrEqualTo(1024));
      final entry = (await entries()).single;
      expect(entry['message'], 'huge failure');
      expect(entry['context'], containsPair('entry_truncated', true));
    },
  );

  test(
    'CAP-8: a live limit reduction resets an oversized file even without a new entry',
    () async {
      final log = logger();
      await log.open(output.path);
      log.configureMaxBytes(5000);
      log.error('failure', context: {'detail': 'x' * 2000});
      log.configureMaxBytes(1024);
      await log.close();
      expect(await output.length(), lessThanOrEqualTo(1024));
    },
  );

  test(
    'CAP-8: startup waits for the saved larger limit before writing or cycling',
    () async {
      await output.parent.create(recursive: true);
      await output.writeAsString(
        '${' ' * (AppConfig.defaultLogMaxBytes + 100)}\n',
      );
      final log = logger();
      await log.open(output.path);
      log.info('startup');
      log.configureMaxBytes(2 * AppConfig.defaultLogMaxBytes);
      await log.close();
      expect(await output.length(), greaterThan(AppConfig.defaultLogMaxBytes));
      expect((await output.readAsLines()).last, contains('startup'));
    },
  );

  test(
    'CAP-13: an unavailable log path reports once on stderr without breaking error handling',
    () async {
      final blocker = File('${directory.path}/blocked');
      await blocker.writeAsString('not a directory');
      final log = logger();
      await log.open('${blocker.path}/logs/grammmar-corrector.log');
      log.error('provider failed');
      await log.close();
      await stderrSink.flush();
      final lines = await diagnostics.readAsLines();
      expect(lines, hasLength(2));
      expect(lines.first, contains('log file is unavailable'));
      expect(lines.last, contains('provider failed'));
    },
  );
}
