import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/openai_compatible/openai_compatible_correction_provider.dart';
import 'package:test/test.dart';

import '../fakes/fake_logger.dart';
import '../fakes/fake_clock.dart';
import '../fakes/throwing_logger.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/file_logger.dart';

const _preset = Preset(
  id: 'compatible',
  providerId: OpenAiCompatibleCorrectionProvider.providerId,
  model: 'example-model',
  systemPrompt: 'Return FORMAL, CASUAL, SHORTER and END.',
);

void main() {
  test('CAP-4 CAP-5: the default prompt explicitly requests tags and streams '
      'suggestions before completion', () async {
    final partialDelivered = Completer<void>();
    addTearDown(() {
      if (!partialDelivered.isCompleted) partialDelivered.complete();
    });
    final endpoint = await _serve((request) async {
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, Object?>;
      final messages = body['messages'] as List<Object?>;
      final prompt =
          (messages.first as Map<String, Object?>)['content'] as String;
      expect(prompt, startsWith('${DefaultAppConfig.shippedSystemPrompt}\n\n'));
      expect(prompt, contains('Begin your response with FORMAL:'));
      expect(prompt, contains('Do not include reasoning'));
      expect(body['model'], 'configured-openrouter-model');
      expect(
        (messages.last as Map<String, Object?>)['content'],
        'i has a draft',
      );
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"reasoning":"We need a correction."}}]}\n\n',
      );
      request.response.write(_frame('FORMAL: I have'));
      await request.response.flush();
      await partialDelivered.future.timeout(const Duration(seconds: 3));
      request.response.write(
        _frame(' a draft.\nCASUAL: I have a draft.\nSHORTER: My draft.\nEND'),
      );
      request.response.write(_frame('', finish: 'stop'));
      request.response.write(
        'data: {"choices":[{"index":0,"delta":{"content":"",'
        '"role":"assistant"},"finish_reason":"stop",'
        '"native_finish_reason":"stop"}],"usage":{"prompt_tokens":229,'
        '"completion_tokens":30}}\n\n',
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final events = <CorrectionEvent>[];
    await for (final event
        in OpenAiCompatibleCorrectionProvider(
          logger: FakeLogger(),
          baseUrl: endpoint.toString(),
        ).correct(
          text: 'i has a draft',
          preset: const Preset(
            id: 'default-prompt',
            providerId: OpenAiCompatibleCorrectionProvider.providerId,
            model: 'configured-openrouter-model',
            systemPrompt: DefaultAppConfig.shippedSystemPrompt,
          ),
        )) {
      events.add(event);
      if (event is SuggestionDelta && !partialDelivered.isCompleted) {
        expect(event.textDelta, 'I have');
        partialDelivered.complete();
      }
    }

    final completed = events.last as CorrectionCompleted;
    expect(completed.suggestions.map((item) => item.text), [
      'I have a draft.',
      'I have a draft.',
      'My draft.',
    ]);
  });

  test('CAP-13: untagged output beginning with W remains a malformed '
      'response without invented suggestions', () async {
    final endpoint = await _serve((request) async {
      request.response.write(_frame('We have a corrected sentence.'));
      await request.response.close();
    });
    final events = await _events(
      OpenAiCompatibleCorrectionProvider(
        logger: FakeLogger(),
        baseUrl: endpoint.toString(),
      ),
    );

    expect(events, hasLength(1));
    final failure = events.single as CorrectionFailed;
    expect(failure.kind, CorrectionFailureKind.malformedResponse);
    expect(
      failure.message,
      'malformed response: expected the "FORMAL:" tag at the start of a line, '
      'found "W"',
    );
  });

  test(
    'CAP-13: OpenRouter HTTP 429 details and Retry-After reach the persistent log',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'http_error_log_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stderrSink = File('${directory.path}/stderr').openWrite();
      addTearDown(stderrSink.close);
      final logFile = File(
        '${directory.path}/config/logs/grammmar-corrector.log',
      );
      final logger = FileLogger(
        clock: FakeClock(millis: 42),
        stderrSink: stderrSink,
      );
      await logger.open(logFile.path);
      logger.configureMaxBytes(1048576);
      addTearDown(logger.close);
      final responseBody = jsonEncode({
        'error': {
          'code': 429,
          'message': 'Rate limit exceeded',
          'metadata': {
            'provider_name': 'Upstream',
            'raw': 'Model is temporarily rate-limited upstream. Retry later.',
          },
        },
      });
      final endpoint = await _serve((request) async {
        request.response.statusCode = 429;
        request.response.headers.set('retry-after', '60');
        request.response.headers.set('x-request-id', 'request-429');
        request.response.write(responseBody);
        await request.response.close();
      });
      final events = await _events(
        OpenAiCompatibleCorrectionProvider(
          logger: logger,
          baseUrl: endpoint.toString(),
        ),
      );
      expect(
        (events.single as CorrectionFailed).kind,
        CorrectionFailureKind.providerError,
      );
      await logger.close();
      final entry =
          jsonDecode((await logFile.readAsLines()).single)
              as Map<String, Object?>;
      final context = entry['context'] as Map<String, Object?>;
      expect(entry['level'], 'error');
      expect(context['http_status'], 429);
      expect(context['retry-after'], '60');
      expect(context['x-request-id'], 'request-429');
      expect(
        jsonDecode(context['response_body'] as String),
        jsonDecode(responseBody),
      );
    },
  );

  test(
    'CAP-13: structured JSON failures with HTTP 200 retain error details',
    () async {
      final logger = FakeLogger();
      final endpoint = await _serve((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'error': {
              'code': 502,
              'message': 'Upstream failed after acceptance',
            },
          }),
        );
        await request.response.close();
      });
      final events = await _events(
        OpenAiCompatibleCorrectionProvider(
          logger: logger,
          baseUrl: endpoint.toString(),
        ),
      );
      expect(events.single, isA<CorrectionFailed>());
      expect(
        logger.lines.single.context?['response_body'],
        contains('Upstream failed after acceptance'),
      );
    },
  );

  test(
    'CAP-13: an interrupted HTTP error body preserves the status and captured response',
    () async {
      final logger = FakeLogger();
      final endpoint = await _serve((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 429 Too Many Requests\r\nContent-Length: 1000\r\n\r\npartial rate limit detail',
        );
        await socket.flush();
        await socket.close();
      });
      final events = await _events(
        OpenAiCompatibleCorrectionProvider(
          logger: logger,
          baseUrl: endpoint.toString(),
        ),
      );
      expect(events.single, isA<CorrectionFailed>());
      expect(logger.lines.single.context, containsPair('http_status', 429));
      expect(
        logger.lines.single.context?['response_body'],
        contains('partial rate limit detail'),
      );
      expect(logger.lines.single.context?['body_read_error_type'], isNotNull);
    },
  );

  test(
    'CAP-13: HTTP errors redact credentials and echoed request text but preserve metadata',
    () async {
      final logger = FakeLogger();
      const input = 'private draft with punctuation';
      final endpoint = await _serve((request) async {
        request.response.statusCode = 403;
        request.response.write(
          jsonEncode({
            'error': {
              'message':
                  'rejected private draft with punctuation key resolved-secret-key',
              'metadata': {
                'flagged_input': 'private draft',
                'raw': jsonEncode({
                  'prompt': _preset.systemPrompt,
                  'message': 'upstream rejected request',
                  'api_key': 'unknown key',
                }),
              },
            },
          }),
        );
        await request.response.close();
      });
      await _events(
        OpenAiCompatibleCorrectionProvider(
          logger: logger,
          baseUrl: endpoint.toString(),
          resolveApiKey: () async => 'resolved-secret-key',
        ),
        input,
      );
      final payload = jsonEncode([
        for (final line in logger.lines)
          {'message': line.message, 'context': line.context},
      ]);
      expect(payload, isNot(contains(input)));
      expect(payload, isNot(contains('private draft')));
      expect(payload, isNot(contains('resolved-secret-key')));
      expect(payload, isNot(contains(_preset.systemPrompt)));
      expect(payload, isNot(contains('unknown key')));
      expect(payload, contains('upstream rejected request'));
    },
  );

  test(
    'CAP-13: errors inside HTTP 200 streams retain their detailed response',
    () async {
      final logger = FakeLogger();
      final partialDelivered = Completer<void>();
      final endpoint = await _serve((request) async {
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          _frame('FORMAL: Partial\nCASUAL: Partial casual\n'),
        );
        await request.response.flush();
        await partialDelivered.future.timeout(const Duration(seconds: 3));
        request.response.write(
          'data: ${jsonEncode({
            'error': {
              'code': 429,
              'message': 'Upstream quota exhausted (output: Partial)',
              'metadata': {'raw': 'per-model limit reached'},
            },
            'choices': [
              {'delta': {}, 'finish_reason': 'error'},
            ],
          })}\n\n',
        );
        await request.response.close();
      });
      final events = <CorrectionEvent>[];
      await OpenAiCompatibleCorrectionProvider(
            logger: logger,
            baseUrl: endpoint.toString(),
          )
          .correct(text: 'draft', preset: _preset)
          .forEach((event) {
            events.add(event);
            if (event is SuggestionDelta && !partialDelivered.isCompleted) {
              partialDelivered.complete();
            }
          })
          .timeout(const Duration(seconds: 5));
      expect(events.whereType<SuggestionDelta>(), isNotEmpty);
      expect(events.last, isA<CorrectionFailed>());
      final context = logger.lines.single.context;
      expect(context, containsPair('http_status', 200));
      expect(context, containsPair('stream_error', true));
      expect(context?['response_body'], contains('Upstream quota exhausted'));
      expect(context?['response_body'], contains('per-model limit reached'));
      expect(
        jsonEncode([
          for (final line in logger.lines)
            {'message': line.message, 'context': line.context},
        ]),
        isNot(contains('Partial')),
      );
    },
  );

  test(
    'CAP-13: oversized non-JSON error bodies are bounded and marked',
    () async {
      final logger = FakeLogger();
      final endpoint = await _serve((request) async {
        request.response.statusCode = 503;
        request.response.write('Service overloaded ${'x' * (70 * 1024)}');
        await request.response.close();
      });
      final events = await _events(
        OpenAiCompatibleCorrectionProvider(
          logger: logger,
          baseUrl: endpoint.toString(),
        ),
      );
      expect(events.single, isA<CorrectionFailed>());
      final context = logger.lines.single.context;
      expect(context, containsPair('response_body_truncated', true));
      final body = context?['response_body'] as String;
      expect(body, startsWith('Service overloaded'));
      expect(utf8.encode(body).length, lessThanOrEqualTo(64 * 1024));
    },
  );

  test(
    'CAP-13: an error body that stalls keeps HTTP status and partial diagnostics at timeout',
    () async {
      final logger = FakeLogger();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final endpoint = await _serve((request) async {
        request.response.statusCode = 429;
        request.response.bufferOutput = false;
        request.response.write(
          'Rate limit details before timeout${' ' * 16384}',
        );
        await request.response.flush();
        await release.future;
        await request.response.close();
      });
      final events = await _events(
        OpenAiCompatibleCorrectionProvider(
          logger: logger,
          baseUrl: endpoint.toString(),
          timeout: const Duration(seconds: 1),
        ),
      );
      expect(
        (events.single as CorrectionFailed).kind,
        CorrectionFailureKind.timeout,
      );
      expect(logger.lines.single.context, containsPair('http_status', 429));
      expect(
        logger.lines.single.context?['response_body'],
        contains('Rate limit details'),
      );
      release.complete();
    },
  );

  test(
    'CAP-13: cancelling an error body closes the connection and produces no failure log',
    () async {
      final logger = FakeLogger();
      final arrived = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final endpoint = await _serve((request) async {
        request.response.statusCode = 429;
        request.response.write('partial body');
        await request.response.flush();
        arrived.complete();
        await release.future;
        await request.response.close();
      });
      final events = <CorrectionEvent>[];
      final subscription = OpenAiCompatibleCorrectionProvider(
        logger: logger,
        baseUrl: endpoint.toString(),
      ).correct(text: 'draft', preset: _preset).listen(events.add);
      await arrived.future;
      await subscription.cancel();
      release.complete();
      await pumpEventQueue();
      expect(events, isEmpty);
      expect(logger.lines, isEmpty);
    },
  );

  test(
    'CAP-13: a broken logger cannot interrupt a modeled provider failure',
    () async {
      final events = await _events(
        OpenAiCompatibleCorrectionProvider(
          logger: ThrowingLogger(),
          baseUrl: 'invalid',
        ),
      );
      expect(events.single, isA<CorrectionFailed>());
    },
  );

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
      logger: FakeLogger(),
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
        startsWith('${_preset.systemPrompt}\n\n'),
      );
      final prompt =
          (messages.first as Map<String, Object?>)['content'] as String;
      expect(prompt, contains('Begin your response with FORMAL:'));
      expect(prompt, contains('\nEND\n'));
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
      logger: FakeLogger(),
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
      OpenAiCompatibleCorrectionProvider(
        logger: FakeLogger(),
        baseUrl: endpoint.toString(),
      ),
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
        logger: FakeLogger(),
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
          OpenAiCompatibleCorrectionProvider(
            logger: FakeLogger(),
            baseUrl: baseUrl,
          ),
        );
        expect(
          (events.single as CorrectionFailed).kind,
          CorrectionFailureKind.providerUnavailable,
        );
      }

      final noModel =
          await OpenAiCompatibleCorrectionProvider(
                logger: FakeLogger(),
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
          logger: FakeLogger(),
          baseUrl: 'http://127.0.0.1:1/v1',
          resolveApiKey: () => throw StateError('keyring unavailable'),
        ),
      );
      expect(
        (noKeySource.single as CorrectionFailed).kind,
        CorrectionFailureKind.providerUnavailable,
      );

      final tooLarge = await _events(
        OpenAiCompatibleCorrectionProvider(
          logger: FakeLogger(),
          baseUrl: 'http://127.0.0.1:1/v1',
        ),
        'x' * (256 * 1024),
      );
      expect(
        (tooLarge.single as CorrectionFailed).kind,
        CorrectionFailureKind.providerUnavailable,
      );

      final noOpenAiKey = await _events(
        OpenAiCompatibleCorrectionProvider(
          logger: FakeLogger(),
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
      logger: FakeLogger(),
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
      logger: FakeLogger(),
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
      logger: FakeLogger(),
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
        OpenAiCompatibleCorrectionProvider(
              logger: FakeLogger(),
              baseUrl: endpoint.toString(),
            )
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
        logger: FakeLogger(),
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
