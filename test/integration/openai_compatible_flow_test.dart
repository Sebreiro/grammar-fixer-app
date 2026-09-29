import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/openai_compatible/openai_compatible_correction_provider.dart';
import 'package:test/test.dart';

const _preset = Preset(
  id: 'compatible',
  providerId: OpenAiCompatibleCorrectionProvider.providerId,
  model: 'example-model',
  systemPrompt: 'Return FORMAL, CASUAL, SHORTER and END.',
);

void main() {
  test('CAP-5 CAP-8: the configured endpoint receives the preset and returns '
      'structured streaming suggestions in fresh sessions', () async {
    final requests = <Map<String, Object?>>[];
    final endpoint = await _serve((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/chat/completions');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer secret',
      );
      requests.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, Object?>,
      );
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(_frame('FORMAL: Fixed.\nCASUAL: Better.\n'));
      await request.response.flush();
      request.response.write(_frame('SHORTER: Good.\nEND'));
      request.response.write(_frame('', finish: 'stop'));
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final provider = OpenAiCompatibleCorrectionProvider(
      baseUrl: endpoint.toString(),
      apiKey: 'secret',
    );

    for (final input in ['first draft', 'second draft']) {
      final events = await _events(provider, input);
      expect(events.whereType<SuggestionDelta>(), isNotEmpty);
      final completed = events.last as CorrectionCompleted;
      expect([
        for (final suggestion in completed.suggestions) suggestion.register,
      ], SuggestionRegister.values);
      expect(
        [for (final suggestion in completed.suggestions) suggestion.text],
        ['Fixed.', 'Better.', 'Good.'],
      );
    }

    expect(requests, hasLength(2));
    for (var index = 0; index < requests.length; index++) {
      final body = requests[index];
      expect(body['model'], _preset.model);
      expect(body['stream'], isTrue);
      final messages = body['messages'] as List<Object?>;
      expect(
        (messages.first as Map<String, Object?>)['content'],
        _preset.systemPrompt,
      );
      expect(
        (messages.last as Map<String, Object?>)['content'],
        ['first draft', 'second draft'][index],
      );
    }
  });

  test('CAP-13: HTTP authentication, missing endpoint, and server failures '
      'become distinct terminal events', () async {
    final statuses = [
      HttpStatus.unauthorized,
      HttpStatus.notFound,
      HttpStatus.serviceUnavailable,
    ];
    var nextStatus = 0;
    final endpoint = await _serve((request) async {
      request.response.statusCode = statuses[nextStatus++];
      await request.response.close();
    });
    final provider = OpenAiCompatibleCorrectionProvider(
      baseUrl: endpoint.toString(),
    );

    for (final kind in [
      CorrectionFailureKind.providerUnavailable,
      CorrectionFailureKind.providerUnavailable,
      CorrectionFailureKind.providerError,
    ]) {
      final events = await _events(provider);
      expect(events, hasLength(1));
      expect((events.single as CorrectionFailed).kind, kind);
    }
    expect(nextStatus, statuses.length);
  });

  test('CAP-13: a complete transport with no END sentinel is a malformed '
      'correction', () async {
    final endpoint = await _serve((request) async {
      request.response.write(
        _frame('FORMAL: One\nCASUAL: Two\nSHORTER: Three'),
      );
      request.response.write(_frame('', finish: 'stop'));
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final events = await _events(
      OpenAiCompatibleCorrectionProvider(baseUrl: endpoint.toString()),
    );

    expect(
      (events.last as CorrectionFailed).kind,
      CorrectionFailureKind.malformedResponse,
    );
  });

  test(
    'CAP-13: invalid and truncated SSE streams report provider errors',
    () async {
      final bodies = [
        'data: {not json}\n\n',
        '${_frame('FORMAL: One')}data: [DONE]\n\n',
        _frame('FORMAL: One'),
      ];
      var nextBody = 0;
      final endpoint = await _serve((request) async {
        request.response.write(bodies[nextBody++]);
        await request.response.close();
      });
      final provider = OpenAiCompatibleCorrectionProvider(
        baseUrl: endpoint.toString(),
      );

      for (final _ in bodies) {
        final events = await _events(provider);
        expect(
          (events.last as CorrectionFailed).kind,
          CorrectionFailureKind.providerError,
        );
      }
    },
  );

  test(
    'CAP-13: invalid settings fail before any request is attempted',
    () async {
      for (final baseUrl in [
        '',
        'http://example.com/v1',
        'http://[invalid/v1',
        'https://user@example.com/v1',
        'https://example.com/v1?mode=unsafe',
        'https://example.com/v1#fragment',
      ]) {
        final events = await _events(
          OpenAiCompatibleCorrectionProvider(baseUrl: baseUrl),
        );
        expect(
          (events.single as CorrectionFailed).kind,
          CorrectionFailureKind.providerUnavailable,
        );
      }

      final noModel =
          await OpenAiCompatibleCorrectionProvider(
                baseUrl: 'http://127.0.0.1:1/v1',
              )
              .correct(
                text: 'draft',
                preset: const Preset(
                  id: 'empty',
                  providerId: OpenAiCompatibleCorrectionProvider.providerId,
                  model: ' ',
                  systemPrompt: 'correct',
                ),
              )
              .toList();
      expect(
        (noModel.single as CorrectionFailed).kind,
        CorrectionFailureKind.providerUnavailable,
      );

      final noKeySource = await _events(
        OpenAiCompatibleCorrectionProvider(
          baseUrl: 'http://127.0.0.1:1/v1',
          resolveApiKey: () => throw StateError('keyring unavailable'),
        ),
      );
      expect(
        (noKeySource.single as CorrectionFailed).kind,
        CorrectionFailureKind.providerUnavailable,
      );

      final tooLarge = await _events(
        const OpenAiCompatibleCorrectionProvider(
          baseUrl: 'http://127.0.0.1:1/v1',
        ),
        'x' * (256 * 1024),
      );
      expect(
        (tooLarge.single as CorrectionFailed).kind,
        CorrectionFailureKind.providerUnavailable,
      );

      final noOpenAiKey = await _events(
        const OpenAiCompatibleCorrectionProvider(
          baseUrl: 'https://api.openai.com/v1',
        ),
      );
      expect(
        (noOpenAiKey.single as CorrectionFailed).kind,
        CorrectionFailureKind.providerUnavailable,
      );
    },
  );

  test('CAP-5: an already-complete endpoint and a loopback hostname are '
      'accepted without a credential', () async {
    final paths = <String>[];
    final endpoint = await _serve((request) async {
      paths.add(request.uri.path);
      request.response.write(_frame('FORMAL: A\nCASUAL: B\nSHORTER: C\nEND'));
      request.response.write(_frame('', finish: 'stop'));
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final base = endpoint.toString().replaceFirst('127.0.0.1', 'localhost');
    final provider = OpenAiCompatibleCorrectionProvider(
      baseUrl: '$base/chat/completions',
    );

    final events = await _events(provider);

    expect(events.last, isA<CorrectionCompleted>());
    expect(paths.single, '/v1/chat/completions');
  });

  test('CAP-13: cancelling while a credential lookup is pending prevents '
      'the HTTP request', () async {
    final lookup = Completer<String?>();
    final provider = OpenAiCompatibleCorrectionProvider(
      baseUrl: 'http://127.0.0.1:1/v1',
      resolveApiKey: () => lookup.future,
    );
    final events = <CorrectionEvent>[];
    final subscription = provider
        .correct(text: 'draft', preset: _preset)
        .listen(events.add);

    await subscription.cancel();
    lookup.complete('late-key');
    await pumpEventQueue();

    expect(events, isEmpty);
  });

  test('CAP-13: cancelling an in-flight provider request terminates without '
      'an event', () async {
    final arrived = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final endpoint = await _serve((request) async {
      arrived.complete();
      await release.future;
      await request.response.close();
    });
    final events = <CorrectionEvent>[];
    final subscription = OpenAiCompatibleCorrectionProvider(
      baseUrl: endpoint.toString(),
    ).correct(text: 'draft', preset: _preset).listen(events.add);

    await arrived.future;
    await subscription.cancel();
    release.complete();
    await pumpEventQueue();

    expect(events, isEmpty);
  });

  test('CAP-5: pausing before the HTTP stream arrives holds its events '
      'until the consumer resumes', () async {
    final endpoint = await _serve((request) async {
      request.response.write(
        _frame('FORMAL: One\nCASUAL: Two\nSHORTER: Three\nEND'),
      );
      request.response.write(_frame('', finish: 'stop'));
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final events = <CorrectionEvent>[];
    final done = Completer<void>();
    final subscription =
        OpenAiCompatibleCorrectionProvider(baseUrl: endpoint.toString())
            .correct(text: 'draft', preset: _preset)
            .listen(events.add, onDone: done.complete);
    subscription.pause();
    await pumpEventQueue();

    expect(events, isEmpty);
    subscription.resume();
    await done.future.timeout(const Duration(seconds: 3));
    expect(events.last, isA<CorrectionCompleted>());
  });

  test(
    'CAP-13: a provider that never answers terminates at its deadline',
    () async {
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final endpoint = await _serve((request) async {
        await release.future;
        await request.response.close();
      });
      final provider = OpenAiCompatibleCorrectionProvider(
        baseUrl: endpoint.toString(),
        timeout: const Duration(milliseconds: 50),
      );

      final events = await _events(provider);

      expect(
        (events.single as CorrectionFailed).kind,
        CorrectionFailureKind.timeout,
      );
      release.complete();
    },
  );
}

Future<Uri> _serve(Future<void> Function(HttpRequest) respond) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) => unawaited(respond(request)));
  addTearDown(() => server.close(force: true));
  return Uri.parse('http://127.0.0.1:${server.port}/v1');
}

String _frame(String content, {String? finish}) =>
    'data: ${jsonEncode({
      'choices': [
        {
          'delta': {'content': content},
          'finish_reason': finish,
        },
      ],
    })}\n\n';

Future<List<CorrectionEvent>> _events(
  OpenAiCompatibleCorrectionProvider provider, [
  String text = 'draft',
]) => provider
    .correct(text: text, preset: _preset)
    .toList()
    .timeout(const Duration(seconds: 5));
