import 'dart:convert';
import 'dart:io';

import '../../domain/clock.dart';
import '../../domain/logger.dart';

/// Structured logging: one JSON line per call, timestamped from the [Clock]
/// port rather than the wall clock, so log output is assertable.
///
/// The sink is injectable purely so tests can read what was written; in the
/// daemon it is always `stderr`, as the Consistency Conventions require.
/// What must never reach it — `input_text`, suggestion bodies — is the
/// caller's contract, documented on the [Logger] port.
final class StderrLogger implements Logger {
  StderrLogger({required this._clock, IOSink? sink}) : _sink = sink ?? stderr;

  final Clock _clock;
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
    _sink.writeln(_line(level, message, context));
  }

  /// This method is called from `catch` handlers — sidecar stderr
  /// forwarding, config warnings — so it must never be the thing that fails.
  /// [_asText] rescues an unknown *type*, but a cyclic structure throws
  /// [JsonCyclicError] straight past it, so the encode itself is guarded and
  /// the line degrades rather than the caller dying inside its own error
  /// path.
  String _line(String level, String message, Map<String, Object?>? context) {
    final entry = <String, Object?>{
      'timestamp': _clock.nowMillis(),
      'level': level,
      'message': message,
      'context': context ?? const <String, Object?>{},
    };
    try {
      return jsonEncode(entry, toEncodable: _asText);
    } on JsonUnsupportedObjectError {
      return jsonEncode({
        ...entry,
        'context': const <String, Object?>{},
        'contextError': 'the context could not be encoded and was dropped',
      });
    }
  }

  /// A context value the JSON codec does not know must not take the daemon
  /// down over a diagnostic; render it and carry on.
  static String _asText(Object? value) => '$value';
}
