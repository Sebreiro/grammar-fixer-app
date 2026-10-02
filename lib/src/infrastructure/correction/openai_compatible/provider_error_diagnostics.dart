import 'dart:convert';

/// Preserves provider diagnostics while removing credentials and echoed text.
final class ProviderErrorDiagnostics {
  ProviderErrorDiagnostics({required Iterable<String> sensitiveValues})
    : _sensitiveValues =
          sensitiveValues.where((value) => value.isNotEmpty).toList()
            ..sort((left, right) => right.length.compareTo(left.length));

  final List<String> _sensitiveValues;
  static final _bearer = RegExp(r'Bearer\s+[^\s"<>]+', caseSensitive: false);
  static final _apiKey = RegExp(r'sk-[a-zA-Z0-9_-]{8,}');
  static final _keySeparators = RegExp(r'[_\s-]');
  static const _sensitiveFields = {
    'input',
    'inputtext',
    'flaggedinput',
    'messages',
    'prompt',
    'systemprompt',
    'content',
    'completion',
    'suggestions',
    'choices',
    'apikey',
    'authorization',
    'accesstoken',
    'cookie',
    'setcookie',
  };

  String sanitize(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      return jsonEncode(_sanitizeValue(decoded, 0));
    } on FormatException {
      if (_looksLikeJson(body)) return '[malformed JSON diagnostics omitted]';
      return _redactText(body);
    } on Object {
      // An untrusted diagnostic must never suppress the failure's log entry.
      return '[provider diagnostics could not be sanitized]';
    }
  }

  Object? _sanitizeValue(Object? value, int depth) {
    if (depth > 24) return '[redacted nested value]';
    return switch (value) {
      Map<String, Object?>() => {
        for (final MapEntry(:key, :value) in value.entries)
          _redactText(key):
              _sensitiveFields.contains(
                key.toLowerCase().replaceAll(_keySeparators, ''),
              )
              ? '[redacted]'
              : _sanitizeValue(value, depth + 1),
      },
      List<Object?>() => [
        for (final item in value) _sanitizeValue(item, depth + 1),
      ],
      String() => _sanitizeString(value, depth),
      _ => value,
    };
  }

  String _sanitizeString(String value, int depth) {
    // OpenRouter metadata.raw can itself contain a JSON error envelope.
    if (_looksLikeJson(value)) {
      try {
        final Object? decoded = jsonDecode(value);
        return jsonEncode(_sanitizeValue(decoded, depth + 1));
      } on FormatException {
        return '[malformed nested JSON diagnostics omitted]';
      }
    }
    return _redactText(value);
  }

  bool _looksLikeJson(String value) {
    final trimmed = value.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  String _redactText(String value) {
    var safe = value;
    for (final sensitive in _sensitiveValues) {
      safe = safe.replaceAll(sensitive, '[redacted]');
      final escaped = jsonEncode(sensitive);
      safe = safe.replaceAll(
        escaped.substring(1, escaped.length - 1),
        '[redacted]',
      );
    }
    return safe
        .replaceAll(_bearer, 'Bearer [redacted]')
        .replaceAll(_apiKey, '[redacted]');
  }
}
