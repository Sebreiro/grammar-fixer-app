import 'dart:io';

import '../../domain/clock.dart';
import '../../domain/logger.dart';
import 'log_line_encoder.dart';

/// Structured logging: one JSON line per call, timestamped from the [Clock]
/// port rather than the wall clock, so log output is assertable.
///
/// The default sink is stderr. [LogLineEncoder] shares the same wire format
/// with the cyclic file logger; tests can inject a sink.
/// What must never reach it — `input_text`, suggestion bodies — is the
/// caller's contract, documented on the [Logger] port.
final class StderrLogger implements Logger {
  StderrLogger({required Clock clock, IOSink? sink})
    : _encoder = LogLineEncoder(clock: clock),
      _sink = sink ?? stderr;

  final LogLineEncoder _encoder;
  final IOSink _sink;

  @override
  void info(String message, {Map<String, Object?>? context}) =>
      _write('info', message, context);

  @override
  void warning(String message, {Map<String, Object?>? context}) =>
      _write('warning', message, context);

  @override
  void error(String message, {Map<String, Object?>? context}) =>
      _write('error', message, context);

  void _write(String level, String message, Map<String, Object?>? context) {
    _sink.writeln(_encoder.encode(level, message, context));
  }
}
