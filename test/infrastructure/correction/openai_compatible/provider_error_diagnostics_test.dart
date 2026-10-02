import 'dart:convert';

import 'package:hotkey_grammar_corrector/src/infrastructure/correction/openai_compatible/provider_error_diagnostics.dart';
import 'package:test/test.dart';

void main() {
  final diagnostics = ProviderErrorDiagnostics(
    sensitiveValues: [
      'private draft\nwith "quotes"',
      'private prompt',
      'private-api-key',
    ],
  );

  test(
    'CAP-13: malformed or truncated JSON cannot expose partial request fields',
    () {
      final safe = diagnostics.sanitize(
        '{"error":{"metadata":{"flagged_input":"unknown private fragment',
      );
      expect(safe, isNot(contains('unknown private fragment')));
      expect(safe, contains('malformed JSON diagnostics omitted'));
    },
  );

  test(
    'CAP-13: provider metadata survives while nested echoed payloads and keys are redacted',
    () {
      final body = jsonEncode({
        'error': {
          'code': 429,
          'message': 'Rate limit exceeded',
          'metadata': {
            'provider_name': 'Upstream',
            'raw': jsonEncode({
              'error': {
                'message': 'Capacity exhausted',
                'code': 'rate_limited',
              },
              'flagged_input': 'a fragment of user text',
              'messages': [
                {'content': 'private prompt'},
              ],
              'api_key': 'another key',
            }),
            'authorization': 'Bearer hidden-key',
          },
        },
      });
      final safe = diagnostics.sanitize(body);
      expect(safe, contains('Capacity exhausted'));
      expect(safe, contains('provider_name'));
      expect(safe, contains('rate_limited'));
      expect(safe, isNot(contains('fragment of user text')));
      expect(safe, isNot(contains('private prompt')));
      expect(safe, isNot(contains('another key')));
      expect(safe, isNot(contains('hidden-key')));
    },
  );

  test(
    'CAP-13: plain-text and JSON-escaped diagnostics cannot echo request secrets',
    () {
      final body =
          'private-api-key private prompt private draft\nwith "quotes" '
          '${jsonEncode('private draft\nwith "quotes"')} Bearer other-secret sk-or-another-secret';
      final safe = diagnostics.sanitize(body);
      expect(safe, isNot(contains('private')));
      expect(safe, isNot(contains('other-secret')));
      expect(safe, isNot(contains('another-secret')));
      expect(safe, contains('[redacted]'));
    },
  );

  test(
    'CAP-13: nested arrays and raw JSON have the same redaction contract',
    () {
      final safe = diagnostics.sanitize(
        jsonEncode([
          {
            'input_text': 'unknown text',
            'content': 'unknown suggestion',
            'message': 'private-api-key',
          },
          'ordinary diagnostic',
        ]),
      );
      expect(safe, isNot(contains('unknown')));
      expect(safe, isNot(contains('private-api-key')));
      expect(safe, contains('ordinary diagnostic'));
    },
  );
}
