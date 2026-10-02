import 'dart:convert';

import 'package:hotkey_grammar_corrector/src/infrastructure/correction/openai_compatible/chat_completion_sse_decoder.dart';
import 'package:test/test.dart';

void main() {
  const decoder = ChatCompletionSseDecoder();

  test('CAP-5: separate reasoning never becomes correction text', () async {
    final bytes = [
      ..._frame(
        jsonEncode({
          'choices': [
            {
              'delta': {
                'reasoning': 'We need to correct the sentence.',
                'reasoning_content': 'We should use three registers.',
                'reasoning_details': [
                  {'type': 'reasoning.text', 'text': 'We need a correction.'},
                ],
                'content': null,
              },
            },
          ],
        }),
      ),
      ..._frame('{"choices":[{"delta":{"content":"FORMAL: Fixed."}}]}'),
      ..._frame('{"choices":[{"delta":{},"finish_reason":"stop"}]}'),
      ..._frame('[DONE]'),
    ];

    expect(await decoder.decode(Stream.value(bytes)).toList(), [
      'FORMAL: Fixed.',
    ]);
  });

  test(
    'CAP-13: structured SSE errors reach the diagnostics callback before failure',
    () async {
      final frames = <Map<String, Object?>>[];
      final body = {
        'error': {'code': 429, 'message': 'Quota exhausted'},
      };
      await expectLater(
        decoder
            .decode(
              Stream.value(_frame(jsonEncode(body))),
              onProviderError: frames.add,
            )
            .toList(),
        throwsFormatException,
      );
      expect(frames.single, body);
    },
  );

  test(
    'CAP-5: usage frames and SSE comments do not interrupt ordered text',
    () async {
      final bytes = utf8.encode(
        ': keepalive\n\n'
        'data:{"choices":[]}\n\n'
        'data: {"choices":[{"delta":{"content":"A"},"finish_reason":null}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n',
      );

      expect(await decoder.decode(Stream.value(bytes)).toList(), ['A']);
    },
  );

  test('CAP-13: malformed Chat Completions frames fail the stream', () async {
    final malformed = [
      '[]',
      '{"choices":{}}',
      '{"choices":[{},{}]}',
      '{"choices":["wrong type"]}',
      '{"choices":[{"delta":null}]}',
      '{"choices":[{"delta":{"content":12}}]}',
      '{"choices":[{"delta":{},"finish_reason":"length"}]}',
      '{"choices":[{"delta":{"content":"late"},"finish_reason":"stop"}]}',
    ];

    for (final data in malformed) {
      await expectLater(
        decoder.decode(Stream.value(_frame(data))).toList(),
        throwsFormatException,
        reason: data,
      );
    }
  });

  test('CAP-13: duplicate stops and text after a stop are rejected', () async {
    const stop = '{"choices":[{"delta":{},"finish_reason":"stop"}]}';
    const content =
        '{"choices":[{"delta":{"content":"late"},"finish_reason":null}]}';

    for (final second in [stop, content]) {
      final bytes = [..._frame(stop), ..._frame(second), ..._frame('[DONE]')];
      await expectLater(
        decoder.decode(Stream.value(bytes)).toList(),
        throwsFormatException,
      );
    }
  });

  test(
    'CAP-5: the final OpenRouter usage frame can repeat a content-free stop',
    () async {
      for (final content in ['', null]) {
        final bytes = [
          ..._frame('{"choices":[{"delta":{"content":"Fixed."}}]}'),
          ..._frame('{"choices":[{"delta":{},"finish_reason":"stop"}]}'),
          ..._frame(
            jsonEncode({
              'choices': [
                {
                  'index': 0,
                  'delta': {'content': content, 'role': 'assistant'},
                  'finish_reason': 'stop',
                  'native_finish_reason': 'stop',
                },
              ],
              'usage': {'prompt_tokens': 229, 'completion_tokens': 30},
            }),
          ),
          ..._frame('[DONE]'),
        ];

        expect(await decoder.decode(Stream.value(bytes)).toList(), ['Fixed.']);
      }
    },
  );

  test(
    'CAP-13: usage cannot hide late text, a changed finish, or invalid metadata',
    () async {
      const stop = '{"choices":[{"delta":{},"finish_reason":"stop"}]}';
      final malformedUsageFrames = [
        '{"choices":[{"delta":{"content":"late"},"finish_reason":"stop"}],"usage":{}}',
        '{"choices":[{"delta":{},"finish_reason":"length"}],"usage":{}}',
        for (final usage in [null, 'invalid', <Object?>[]])
          jsonEncode({
            'choices': [
              {'delta': <String, Object?>{}, 'finish_reason': 'stop'},
            ],
            'usage': usage,
          }),
      ];

      for (final frame in malformedUsageFrames) {
        final bytes = [..._frame(stop), ..._frame(frame), ..._frame('[DONE]')];
        await expectLater(
          decoder.decode(Stream.value(bytes)).toList(),
          throwsFormatException,
          reason: frame,
        );
      }
    },
  );

  test('CAP-13: repeated usage stops still require DONE', () async {
    final bytes = [
      ..._frame('{"choices":[{"delta":{},"finish_reason":"stop"}]}'),
      ..._frame('{"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{}}'),
    ];

    await expectLater(
      decoder.decode(Stream.value(bytes)).toList(),
      throwsFormatException,
    );
  });

  test(
    'CAP-13: oversized frames and bodies fail before they are parsed',
    () async {
      final hugeFrame = utf8.encode(
        'data: ${'x' * ChatCompletionSseDecoder.maxFrameBytes}\n\n',
      );
      final hugeBody = List<int>.filled(
        ChatCompletionSseDecoder.maxBodyBytes + 1,
        32,
      );

      await expectLater(
        decoder.decode(Stream.value(hugeFrame)).toList(),
        throwsFormatException,
      );
      await expectLater(
        decoder.decode(Stream.value(hugeBody)).toList(),
        throwsFormatException,
      );
    },
  );

  test(
    'CAP-13: an upstream transport error becomes an invalid stream',
    () async {
      await expectLater(
        decoder
            .decode(Stream<List<int>>.error(StateError('transport closed')))
            .toList(),
        throwsFormatException,
      );
    },
  );
}

List<int> _frame(String data) => utf8.encode('data: $data\n\n');
