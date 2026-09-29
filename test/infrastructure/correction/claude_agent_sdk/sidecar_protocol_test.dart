import 'dart:convert';

import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/sidecar_protocol.dart';
import 'package:test/test.dart';

/// Unit tests for the AD-19 wire shapes: strict parsing of every sidecar
/// line, kind-by-name mapping, and the single request line Dart writes.
void main() {
  group('SidecarRequest', () {
    test('CAP-5: toJsonLine carries text, model, and system_prompt as one '
        'line with the protocol field names', () {
      const request = SidecarRequest(
        text: 'line one\nline two',
        model: 'claude-sonnet-5',
        systemPrompt: 'reply with three lines',
      );

      final line = request.toJsonLine();

      expect(line, isNot(contains('\n')), reason: 'NDJSON: one line each');
      expect(jsonDecode(line), {
        'text': 'line one\nline two',
        'model': 'claude-sonnet-5',
        'system_prompt': 'reply with three lines',
      });
    });
  });

  group('SidecarLine.parse well-formed lines', () {
    test('CAP-5: a text line yields its verbatim text', () {
      final line = SidecarLine.parse('{"type":"text","text":"FORM"}');

      expect(
        line,
        isA<SidecarTextLine>().having((l) => l.text, 'text', 'FORM'),
      );
    });

    test('CAP-5: a done line parses to SidecarDoneLine', () {
      expect(SidecarLine.parse('{"type":"done"}'), isA<SidecarDoneLine>());
    });

    for (final kind in CorrectionFailureKind.values) {
      test('CAP-13: an error line with kind "${kind.name}" maps by name', () {
        final line = SidecarLine.parse(
          '{"type":"error","kind":"${kind.name}","message":"m"}',
        );

        expect(
          line,
          isA<SidecarErrorLine>()
              .having((l) => l.kind, 'kind', kind)
              .having((l) => l.message, 'message', 'm'),
        );
      });
    }

    test('CAP-13: an unknown error kind degrades to providerError', () {
      final line = SidecarLine.parse(
        '{"type":"error","kind":"somethingNewer","message":"m"}',
      );

      expect(
        line,
        isA<SidecarErrorLine>().having(
          (l) => l.kind,
          'kind',
          CorrectionFailureKind.providerError,
        ),
      );
    });
  });

  group('SidecarLine.parse malformed lines', () {
    const malformedLines = {
      'not JSON at all': 'this is not json',
      'a JSON array': '["type","text"]',
      'a JSON string': '"just a string"',
      'an object without a type': '{"text":"x"}',
      'an unknown type': '{"type":"bogus"}',
      'a text line without text': '{"type":"text"}',
      'a text line with non-string text': '{"type":"text","text":5}',
      'an error line without a kind': '{"type":"error","message":"m"}',
      'an error line without a message': '{"type":"error","kind":"timeout"}',
    };

    malformedLines.forEach((description, line) {
      test('CAP-13: $description throws FormatException', () {
        expect(() => SidecarLine.parse(line), throwsFormatException);
      });
    });
  });
}
