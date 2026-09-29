import 'dart:async';
import 'dart:math';

import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart';
import 'package:test/test.dart';

/// Behaviour tests for `RegisterTaggedStreamParser` (AD-16), covering every
/// row of the spec's I/O & Edge-Case Matrix. Pure Dart, no Flutter binding.
void main() {
  const parser = RegisterTaggedStreamParser();

  Future<List<CorrectionEvent>> parseChunks(List<String> chunks) =>
      parser.parse(Stream.fromIterable(chunks)).toList();

  group('well-formed responses', () {
    test(
      'CAP-4: all three registers in one chunk complete in enum order',
      () async {
        final events = await parseChunks([
          'FORMAL: a\nCASUAL: b\nSHORTER: c\nEND',
        ]);

        expect(_deltaTexts(events, SuggestionRegister.formal), ['a']);
        expect(_deltaTexts(events, SuggestionRegister.casual), ['b']);
        expect(_deltaTexts(events, SuggestionRegister.shorter), ['c']);
        _expectCompleted(events, formal: 'a', casual: 'b', shorter: 'c');
      },
    );

    test('CAP-5: register text interleaved across chunks flushes incremental '
        'deltas, never cumulative', () async {
      final events = await parseChunks([
        'FORMAL: one ',
        'two\nCASUAL: thr',
        'ee\nSHORTER: fo',
        'ur\nEND',
      ]);

      expect(_deltaTexts(events, SuggestionRegister.formal), ['one ', 'two']);
      expect(_deltaTexts(events, SuggestionRegister.casual), ['thr', 'ee']);
      expect(_deltaTexts(events, SuggestionRegister.shorter), ['fo', 'ur']);
      _expectCompleted(
        events,
        formal: 'one two',
        casual: 'three',
        shorter: 'four',
      );
    });

    test('CAP-4: a trailing newline and whitespace after the END sentinel '
        'are tolerated', () async {
      final events = await parseChunks([
        'FORMAL: a\nCASUAL: b\nSHORTER: c\nEND\n',
        '  \n\t\n',
      ]);

      _expectCompleted(events, formal: 'a', casual: 'b', shorter: 'c');
    });

    test('CAP-4: an empty register line yields an empty suggestion text and no '
        'empty delta', () async {
      final events = await parseChunks([
        'FORMAL:\nCASUAL:   \nSHORTER: c\nEND',
      ]);

      final deltas = events.whereType<SuggestionDelta>().toList();
      expect(deltas, hasLength(1));
      expect(deltas.single.register, SuggestionRegister.shorter);
      _expectCompleted(events, formal: '', casual: '', shorter: 'c');
    });

    test('CAP-4: tag words in the middle of a line are ordinary content, not '
        'tags', () async {
      final events = await parseChunks([
        'FORMAL: Use FORMAL: and CASUAL: wisely\nCASUAL: b\nSHORTER: c\nEND',
      ]);

      _expectCompleted(
        events,
        formal: 'Use FORMAL: and CASUAL: wisely',
        casual: 'b',
        shorter: 'c',
      );
    });

    test('CAP-4: CRLF line endings complete with trimmed texts and no '
        'carriage return in deltas', () async {
      final events = await parseChunks([
        'FORMAL: a\r\nCASUAL: b\r\nSHORTER: c\r\nEND\r\n',
      ]);

      for (final delta in events.whereType<SuggestionDelta>()) {
        expect(delta.textDelta, isNot(contains('\r')));
        expect(delta.textDelta, isNot(contains('\n')));
      }
      _expectCompleted(events, formal: 'a', casual: 'b', shorter: 'c');
    });

    test('CAP-4: trailing whitespace on register lines is trimmed from the '
        'completed suggestions', () async {
      final events = await parseChunks([
        'FORMAL: a \nCASUAL:\tb\t\nSHORTER: c  \nEND',
      ]);

      _expectCompleted(events, formal: 'a', casual: 'b', shorter: 'c');
    });

    test('CAP-4: a leading newline and blank lines between register lines '
        'are tolerated', () async {
      final events = await parseChunks([
        '\nFORMAL: a\n\n  CASUAL: b\n\nSHORTER: c\n\n  END',
      ]);

      _expectCompleted(events, formal: 'a', casual: 'b', shorter: 'c');
    });

    test('CAP-9: the recorded output of a real claude-sonnet-5 run under the '
        'shipped prompt parses into three registers', () async {
      // Not a hand-written fixture: this is the verbatim response captured
      // on 2026-08-07 by driving the real Python sidecar, the real
      // claude_agent_sdk and the real `claude` CLI with
      // DefaultAppConfig.shippedSystemPrompt. It is the only evidence in the
      // suite that a real model honours the sentinel at all — and note it
      // carries NO trailing newline after END, which is precisely why the
      // grammar keys on content rather than on whitespace.
      const recorded =
          'FORMAL: I went to the store yesterday and bought some milk.\n'
          'CASUAL: I went to the store yesterday and got some milk.\n'
          'SHORTER: I went to the store and bought milk.\n'
          'END';

      final events = await parseChunks([recorded]);

      _expectCompleted(
        events,
        formal: 'I went to the store yesterday and bought some milk.',
        casual: 'I went to the store yesterday and got some milk.',
        shorter: 'I went to the store and bought milk.',
      );
    });

    test('CAP-4: one parser instance is reusable across corrections', () async {
      final first = await parseChunks([
        'FORMAL: a\nCASUAL: b\nSHORTER: c\nEND',
      ]);
      final second = await parseChunks([
        'FORMAL: x\nCASUAL: y\nSHORTER: z\nEND',
      ]);

      _expectCompleted(first, formal: 'a', casual: 'b', shorter: 'c');
      _expectCompleted(second, formal: 'x', casual: 'y', shorter: 'z');
    });
  });

  group('chunk boundaries (CAP-5)', () {
    test(
      'CAP-5: a tag split mid-word across chunks never leaks into deltas',
      () async {
        final events = await parseChunks([
          'FORM',
          'AL: Hel',
          'lo\nCASU',
          'AL: b\nSHORTER: c\nEN',
          'D',
        ]);

        expect(
          _deltaTexts(events, SuggestionRegister.formal),
          ['Hel', 'lo'],
          reason: 'held-back "CASU" must never appear as a formal delta',
        );
        for (final delta in events.whereType<SuggestionDelta>()) {
          expect(delta.textDelta, isNot(contains('CASU')));
          expect(delta.textDelta, isNot(contains('\n')));
        }
        _expectCompleted(events, formal: 'Hello', casual: 'b', shorter: 'c');
      },
    );

    test('CAP-5: any chunking of the same response yields the same terminal '
        'and the same per-register delta text', () async {
      const text =
          'FORMAL: We have issues.\nCASUAL: got issues\nSHORTER: issues\n'
          'END\n';

      final baseline = await parseChunks([text]);
      for (final chunks in _splittingsOf(text)) {
        final events = await parseChunks(chunks);
        _expectCompleted(
          events,
          formal: 'We have issues.',
          casual: 'got issues',
          shorter: 'issues',
        );
        for (final register in SuggestionRegister.values) {
          expect(
            _deltaTexts(events, register).join(),
            _deltaTexts(baseline, register).join(),
            reason: 'chunking must not change $register delta text',
          );
        }
      }
    });

    test('CAP-5: leading whitespace after a tag colon is skipped and empty '
        'deltas are never emitted', () async {
      final events = await parseChunks([
        'FORMAL:',
        '  ',
        ' a\nCASUAL: b\nSHORTER: c\nEND',
      ]);

      for (final delta in events.whereType<SuggestionDelta>()) {
        expect(delta.textDelta, isNotEmpty);
      }
      expect(_deltaTexts(events, SuggestionRegister.formal), ['a']);
      _expectCompleted(events, formal: 'a', casual: 'b', shorter: 'c');
    });

    test('CAP-5: a CRLF pair split across two chunks still delimits the '
        'line and leaks no carriage return', () async {
      final events = await parseChunks([
        'FORMAL: a\r',
        '\nCASUAL: b\r',
        '\nSHORTER: c\r',
        '\nEND\r',
        '\n',
      ]);

      for (final delta in events.whereType<SuggestionDelta>()) {
        expect(delta.textDelta, isNot(contains('\r')));
        expect(delta.textDelta, isNot(contains('\n')));
      }
      _expectCompleted(events, formal: 'a', casual: 'b', shorter: 'c');
    });

    test('CAP-4: any chunking of a malformed response yields the identical '
        'single malformedResponse terminal', () async {
      const fixtures = {
        // Out-of-order first tag.
        'CASUAL: b\nFORMAL: a\nSHORTER: c\nEND': 'FORMAL:',
        // Repeated tag.
        'FORMAL: a\nFORMAL: again\nCASUAL: b\nSHORTER: c\nEND': 'CASUAL:',
        // Text before the first tag.
        'Sure! FORMAL: a\nCASUAL: b\nSHORTER: c\nEND': 'FORMAL:',
        // A fourth tag where the sentinel belongs.
        'FORMAL: a\nCASUAL: b\nSHORTER: c\nFORMAL: d': 'END',
        // Junk after an otherwise complete response.
        'FORMAL: a\nCASUAL: b\nSHORTER: c\nEND\nanything': 'END',
      };

      for (final MapEntry(key: text, value: namedTag) in fixtures.entries) {
        final baseline = await parseChunks([text]);
        _expectMalformed(baseline, naming: namedTag);
        final baselineTerminal = baseline.last as CorrectionFailed;

        for (final chunks in _splittingsOf(text)) {
          final events = await parseChunks(chunks);
          _expectMalformed(events, naming: namedTag);
          final terminal = events.last as CorrectionFailed;
          expect(
            terminal.message,
            baselineTerminal.message,
            reason: 'chunking must not change the failure naming "$namedTag"',
          );
        }
      }
    });
  });

  group('malformed responses (CAP-4)', () {
    test('CAP-4: an empty stream fails with malformedResponse', () async {
      final events = await parser.parse(const Stream<String>.empty()).toList();

      _expectMalformed(events, naming: 'FORMAL:');
      expect(events, hasLength(1), reason: 'no deltas for an empty stream');
    });

    test(
      'CAP-4: a whitespace-only stream fails with malformedResponse',
      () async {
        final events = await parseChunks(['  \n', '\t\n ']);

        _expectMalformed(events, naming: 'FORMAL:');
        expect(events, hasLength(1));
      },
    );

    test('CAP-4: a response ending before SHORTER fails naming the missing '
        'register', () async {
      final events = await parseChunks(['FORMAL: a\nCASUAL: b\n']);

      _expectMalformed(events, naming: 'SHORTER:');
    });

    test('CAP-4: a stream ending inside a held tag prefix fails naming that '
        'register', () async {
      final events = await parseChunks(['FORMAL: a\nCASUAL: b\nSHORT']);

      _expectMalformed(events, naming: 'SHORTER:');
      expect(
        _deltaTexts(events, SuggestionRegister.shorter),
        isEmpty,
        reason: 'the held "SHORT" must be neither leaked nor completed',
      );
    });

    test(
      'CAP-4: a response whose final line is complete but unterminated by '
      'the sentinel fails rather than completing with partial text',
      () async {
        final events = await parseChunks(['FORMAL: a\nCASUAL: b\nSHORTER: c']);

        _expectMalformed(events, naming: 'END');
      },
    );

    test('CAP-4: a response cut off inside its SHORTER line fails as '
        'malformedResponse', () async {
      final events = await parseChunks([
        'FORMAL: a\nCASUAL: b\nSHORTER: the shortest re',
      ]);

      _expectMalformed(events, naming: 'END');
    });

    test(
      'CAP-4: a stream that ends inside the sentinel itself fails',
      () async {
        final events = await parseChunks([
          'FORMAL: a\nCASUAL: b\nSHORTER: c\nEN',
        ]);

        _expectMalformed(events, naming: 'END');
      },
    );

    test('CAP-4: content after the sentinel fails', () async {
      final events = await parseChunks([
        'FORMAL: a\nCASUAL: b\nSHORTER: c\nEND\nanything',
      ]);

      _expectMalformed(events, naming: 'END');
    });

    test('CAP-4: the sentinel is the parser own constant, so the prompt and '
        'the grammar cannot drift apart', () async {
      final events = await parseChunks([
        'FORMAL: a\nCASUAL: b\nSHORTER: c\n'
            '${RegisterTaggedStreamParser.endSentinel}',
      ]);

      _expectCompleted(events, formal: 'a', casual: 'b', shorter: 'c');
    });

    test('CAP-4: an out-of-order first tag fails immediately', () async {
      final events = await parseChunks([
        'CASUAL: b\nFORMAL: a\nSHORTER: c\nEND',
      ]);

      _expectMalformed(events, naming: 'FORMAL:');
      expect(events, hasLength(1));
    });

    test(
      'CAP-4: a repeated tag fails as soon as it cannot be the expected tag',
      () async {
        final events = await parseChunks([
          'FORMAL: a\nFORMAL: again\nCASUAL: b\nSHORTER: c\nEND',
        ]);

        _expectMalformed(events, naming: 'CASUAL:');
      },
    );

    test('CAP-4: a fourth tag where the END sentinel belongs fails', () async {
      final events = await parseChunks([
        'FORMAL: a\nCASUAL: b\nSHORTER: c\nFORMAL: d',
      ]);

      _expectMalformed(events, naming: 'END');
    });

    test('CAP-4: text before the first tag fails as soon as it can no longer '
        'be a tag prefix, without waiting for the stream to end', () async {
      final input = StreamController<String>();
      final events = <CorrectionEvent>[];
      parser.parse(input.stream).listen(events.add);

      // "FORMALI" diverges at the seventh character; the stream stays open.
      input.add('FORMALIty aside, here you go');
      await pumpEventQueue();

      _expectMalformed(events, naming: 'FORMAL:');
      await input.close();
    });
  });

  group('stream discipline (AD-3, AD-4)', () {
    test('CAP-5: an input stream error becomes a providerError terminal, never '
        'a thrown error', () async {
      final input = StreamController<String>();
      final eventsFuture = parser.parse(input.stream).toList();
      input
        ..add('FORMAL: a\n')
        ..addError(StateError('transport broke'));

      final events = await eventsFuture;

      expect(_deltaTexts(events, SuggestionRegister.formal), ['a']);
      final terminal = events.last;
      expect(terminal, isA<CorrectionFailed>());
      terminal as CorrectionFailed;
      expect(terminal.kind, CorrectionFailureKind.providerError);
      expect(terminal.message, contains('Retry the correction'));
      expect(terminal.message, isNot(contains('transport broke')));
      await input.close();
    });

    test('CAP-4: nothing is emitted after the terminal and input is no longer '
        'consumed', () async {
      final input = StreamController<String>();
      var inputCancelled = false;
      input.onCancel = () => inputCancelled = true;
      final events = <CorrectionEvent>[];
      parser.parse(input.stream).listen(events.add);

      input.add('FORMAL: a\nWRONG');
      await pumpEventQueue();

      _expectMalformed(events, naming: 'CASUAL:');
      expect(inputCancelled, isTrue);
      final lengthAtTerminal = events.length;

      input.add('CASUAL: b\nSHORTER: c\nEND');
      await pumpEventQueue();
      expect(events, hasLength(lengthAtTerminal));
    });

    test('CAP-5: cancelling the output subscription cancels the input and '
        'nothing further is emitted', () async {
      final input = StreamController<String>();
      var inputCancelled = false;
      input.onCancel = () => inputCancelled = true;
      final events = <CorrectionEvent>[];
      final subscription = parser.parse(input.stream).listen(events.add);

      input.add('FORMAL: Hel');
      await pumpEventQueue();
      expect(_deltaTexts(events, SuggestionRegister.formal), ['Hel']);

      await subscription.cancel();
      expect(inputCancelled, isTrue);

      input.add('lo\nCASUAL: b\nSHORTER: c\nEND');
      await pumpEventQueue();
      expect(events, hasLength(1), reason: 'no events after cancellation');
    });

    test('CAP-5: the parsed stream is single-subscription; a second listen '
        'throws a StateError', () async {
      final stream = parser.parse(
        Stream.fromIterable(const ['FORMAL: a\nCASUAL: b\nSHORTER: c\nEND']),
      );
      final events = <CorrectionEvent>[];
      stream.listen(events.add);

      expect(() => stream.listen(events.add), throwsStateError);

      await pumpEventQueue();
      _expectCompleted(events, formal: 'a', casual: 'b', shorter: 'c');
    });

    test('CAP-5: pausing the output subscription pauses the input, and '
        'resuming resumes it', () async {
      final input = StreamController<String>();
      var inputPaused = false;
      var inputResumed = false;
      input.onPause = () => inputPaused = true;
      input.onResume = () => inputResumed = true;
      final events = <CorrectionEvent>[];
      final subscription = parser.parse(input.stream).listen(events.add);
      input.add('FORMAL: a');
      await pumpEventQueue();
      expect(_deltaTexts(events, SuggestionRegister.formal), ['a']);

      subscription.pause();
      await pumpEventQueue();
      expect(inputPaused, isTrue, reason: 'backpressure must reach the input');
      expect(inputResumed, isFalse);

      subscription.resume();
      await pumpEventQueue();
      expect(inputResumed, isTrue);

      await subscription.cancel();
      await input.close();
    });
  });
}

/// The text of every delta for [register], in emission order.
List<String> _deltaTexts(
  List<CorrectionEvent> events,
  SuggestionRegister register,
) {
  return [
    for (final event in events.whereType<SuggestionDelta>())
      if (event.register == register) event.textDelta,
  ];
}

/// Asserts the AD-3 shape of a successful parse: the terminal is a single
/// closing [CorrectionCompleted] carrying one trimmed suggestion per
/// register, in enum declaration order.
void _expectCompleted(
  List<CorrectionEvent> events, {
  required String formal,
  required String casual,
  required String shorter,
}) {
  final terminal = events.last;
  expect(terminal, isA<CorrectionCompleted>());
  terminal as CorrectionCompleted;
  expect(
    events.whereType<CorrectionCompleted>().length +
        events.whereType<CorrectionFailed>().length,
    1,
    reason: 'exactly one terminal event',
  );
  expect(
    [for (final suggestion in terminal.suggestions) suggestion.register],
    SuggestionRegister.values,
    reason: 'one suggestion per register, in enum declaration order',
  );
  expect(
    [for (final suggestion in terminal.suggestions) suggestion.text],
    [formal, casual, shorter],
  );
}

/// Asserts the AD-3 shape of a failed parse: the terminal is a single
/// closing [CorrectionFailed] of kind `malformedResponse` whose message
/// names the violated element.
void _expectMalformed(List<CorrectionEvent> events, {required String naming}) {
  final terminal = events.last;
  expect(terminal, isA<CorrectionFailed>());
  terminal as CorrectionFailed;
  expect(terminal.kind, CorrectionFailureKind.malformedResponse);
  expect(terminal.message, contains(naming));
  expect(
    events.whereType<CorrectionCompleted>(),
    isEmpty,
    reason: 'a failed parse never completes',
  );
  expect(
    events.whereType<CorrectionFailed>(),
    hasLength(1),
    reason: 'exactly one terminal event',
  );
}

List<String> _chunksOf(String text, int size) => [
  for (var start = 0; start < text.length; start += size)
    text.substring(start, min(start + size, text.length)),
];

/// Every chunking of [text] the boundary-invariance tests exercise,
/// including the pathological one-character-per-chunk split.
List<List<String>> _splittingsOf(String text) => [
  [text],
  [for (var i = 0; i < text.length; i += 1) text[i]],
  _chunksOf(text, 2),
  _chunksOf(text, 5),
  _chunksOf(text, 7),
  _chunksOf(text, 13),
];
