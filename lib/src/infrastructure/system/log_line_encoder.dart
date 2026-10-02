import 'dart:convert';

import '../../domain/clock.dart';

final class LogLineEncoder {
  const LogLineEncoder({required this._clock});

  final Clock _clock;

  /// This method is called from `catch` handlers — sidecar stderr
  /// forwarding, config warnings — so it must never be the thing that fails.
  /// [_asText] rescues an unknown *type*, but a cyclic structure throws
  /// [JsonCyclicError] straight past it, so the encode itself is guarded and
  /// the line degrades rather than the caller dying inside its own error
  /// path.
  String encode(String level, String message, Map<String, Object?>? context) {
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
