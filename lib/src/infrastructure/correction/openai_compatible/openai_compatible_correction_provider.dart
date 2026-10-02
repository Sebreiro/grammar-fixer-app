import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../domain/correction/correction_event.dart';
import '../../../domain/correction/correction_provider.dart';
import '../../../domain/correction/preset.dart';
import '../../../domain/correction/suggestion_register.dart';
import '../../../domain/logger.dart';
import '../shared/register_tagged_stream_parser.dart';
import 'chat_completion_request.dart';
import 'chat_completion_sse_decoder.dart';
import 'provider_error_diagnostics.dart';

/// One explicitly configured Chat Completions endpoint, with no fallback.
final class OpenAiCompatibleCorrectionProvider implements CorrectionProvider {
  const OpenAiCompatibleCorrectionProvider({
    required this.baseUrl,
    required this.logger,
    this.apiKey,
    this.resolveApiKey,
    this.timeout = const Duration(seconds: 60),
  });

  static const providerId = 'openai-compatible';
  static const baseUrlSettingsKey = 'baseUrl';

  final String baseUrl;
  final Logger logger;
  final String? apiKey;
  final Future<String?> Function()? resolveApiKey;
  final Duration timeout;

  @override
  Stream<CorrectionEvent> correct({
    required String text,
    required Preset preset,
  }) {
    return _HttpCorrectionRun(
      baseUrl: baseUrl,
      logger: logger,
      apiKey: apiKey,
      resolveApiKey: resolveApiKey,
      timeout: timeout,
      text: text,
      preset: preset,
    ).events;
  }
}

final class _HttpCorrectionRun {
  _HttpCorrectionRun({
    required this.baseUrl,
    required this.logger,
    required this.apiKey,
    required this.resolveApiKey,
    required this.timeout,
    required this.text,
    required this.preset,
  }) {
    _content = StreamController<String>(
      onPause: () => _decodedContent?.pause(),
      onResume: () => _decodedContent?.resume(),
      onCancel: () => _decodedContent?.cancel(),
    );
    _output = StreamController<CorrectionEvent>(
      onListen: () => unawaited(_start()),
      onPause: () {
        _consumerPaused = true;
        _parsedEvents?.pause();
      },
      onResume: () {
        _consumerPaused = false;
        _parsedEvents?.resume();
      },
      onCancel: _onCancel,
    );
  }

  static const _maxRequestBytes = 256 * 1024;
  static const maxErrorBodyBytes = 64 * 1024;
  static const _decoder = ChatCompletionSseDecoder();

  final String baseUrl;
  final Logger logger;
  final String? apiKey;
  final Future<String?> Function()? resolveApiKey;
  final Duration timeout;
  final String text;
  final Preset preset;

  late final StreamController<CorrectionEvent> _output;
  late final StreamController<String> _content;
  StreamSubscription<String>? _decodedContent;
  StreamSubscription<List<int>>? _errorBodySubscription;
  final BytesBuilder _errorBody = BytesBuilder(copy: false);
  Map<String, Object?> _failureContext = const {};
  bool _bodyTruncated = false;
  String? _resolvedApiKey;
  final StringBuffer _receivedText = StringBuffer();
  StreamSubscription<CorrectionEvent>? _parsedEvents;
  HttpClient? _client;
  HttpClientRequest? _request;
  Timer? _deadline;
  bool _terminated = false;
  bool _consumerPaused = false;

  Stream<CorrectionEvent> get events => _output.stream;

  Future<void> _start() async {
    final endpoint = _validatedEndpoint(baseUrl);
    if (endpoint == null) {
      _emit(
        _failure(
          CorrectionFailureKind.providerUnavailable,
          'Set a valid HTTPS Base URL, or a loopback HTTP Base URL, in Settings.',
        ),
      );
      return;
    }
    if (preset.model.trim().isEmpty) {
      _emit(
        _failure(
          CorrectionFailureKind.providerUnavailable,
          'Set a model for the active preset in Settings.',
        ),
      );
      return;
    }
    String? resolvedKey = apiKey;
    try {
      final keyResolver = resolveApiKey;
      if (keyResolver != null) resolvedKey = await keyResolver();
    } on Object catch (error) {
      _failureContext = {'error_type': error.runtimeType.toString()};
      _emit(
        _failure(
          CorrectionFailureKind.providerUnavailable,
          'Could not read the API key source. Check Settings and retry.',
        ),
      );
      return;
    }
    if (_terminated) return;
    _resolvedApiKey = resolvedKey;
    if (endpoint.host == 'api.openai.com' && (resolvedKey?.isEmpty ?? true)) {
      _emit(
        _failure(
          CorrectionFailureKind.providerUnavailable,
          'Configure an OpenAI API key, then retry.',
        ),
      );
      return;
    }
    final body = ChatCompletionRequest.encode(
      endpoint: endpoint,
      text: text,
      preset: preset,
    );
    final encodedBody = utf8.encode(body);
    if (encodedBody.length > _maxRequestBytes) {
      _emit(
        _failure(
          CorrectionFailureKind.providerUnavailable,
          'The draft or preset prompt is too long for one correction. Shorten it and retry.',
        ),
      );
      return;
    }
    _attachParser();
    _deadline = Timer(
      timeout,
      () => _emit(
        _failure(
          CorrectionFailureKind.timeout,
          'The provider took too long. Retry the correction.',
        ),
      ),
    );
    final client = HttpClient()..connectionTimeout = timeout;
    _client = client;
    try {
      final request = await client.postUrl(endpoint);
      if (_terminated) {
        request.abort();
        return;
      }
      _request = request;
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final key = resolvedKey;
      if (key != null && key.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      }
      request.add(encodedBody);
      final response = await request.close();
      if (_terminated) return;
      if (response.statusCode != HttpStatus.ok ||
          response.headers.contentType?.mimeType == 'application/json') {
        _attachErrorBody(response);
        return;
      }
      _attachDecoder(response);
    } on TimeoutException {
      _emit(
        _failure(
          CorrectionFailureKind.timeout,
          'The provider took too long. Retry the correction.',
        ),
      );
    } on Object catch (error) {
      _failureContext = {'error_type': error.runtimeType.toString()};
      _emit(
        _failure(
          CorrectionFailureKind.providerError,
          'Could not reach the configured provider. Check its address and connection, then retry.',
        ),
      );
    }
  }

  void _attachErrorBody(HttpClientResponse response) {
    _failureContext = {
      'http_status': response.statusCode,
      for (final name in [
        'retry-after',
        'x-request-id',
        'x-openrouter-request-id',
      ])
        if (response.headers[name] case final values?)
          name: _safeBody(values.join(', ')),
    };
    _errorBodySubscription = response.listen(
      (chunk) => _acceptErrorBytes(chunk, response.statusCode),
      onDone: () => _emit(_statusFailure(response.statusCode)),
      onError: (Object error) {
        _failureContext = {
          ..._failureContext,
          'body_read_error_type': error.runtimeType.toString(),
        };
        _emit(_statusFailure(response.statusCode));
      },
    );
  }

  void _acceptErrorBytes(List<int> chunk, int status) {
    if (_terminated) return;
    final remaining = maxErrorBodyBytes - _errorBody.length;
    _errorBody.add(
      chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
    );
    if (chunk.length > remaining) {
      _bodyTruncated = true;
      _emit(_statusFailure(status));
    }
  }

  String _safeBody(String body) => ProviderErrorDiagnostics(
    sensitiveValues: [
      text,
      preset.systemPrompt,
      apiKey ?? '',
      _resolvedApiKey ?? '',
      _receivedText.toString(),
      ..._receivedText
          .toString()
          .split(RegExp(r'[\r\n]'))
          .map(
            (line) =>
                line.replaceFirst(RegExp(r'^(FORMAL|CASUAL|SHORTER):\s*'), ''),
          ),
    ],
  ).sanitize(body);

  void _recordStreamError(Map<String, Object?> frame) {
    _failureContext = {
      'http_status': HttpStatus.ok,
      'stream_error': true,
      'response_body': _safeBody(jsonEncode(frame)),
    };
  }

  void _logFailure(CorrectionFailed event) {
    try {
      logger.error(
        'the HTTP correction provider failed',
        context: {
          'provider_id': OpenAiCompatibleCorrectionProvider.providerId,
          'failure_kind': event.kind.name,
          'message': _safeBody(event.message),
          ..._failureContext,
          if (_errorBodySubscription != null)
            'response_body': _safeBody(
              utf8.decode(_errorBody.toBytes(), allowMalformed: true),
            ),
          if (_bodyTruncated) 'response_body_truncated': true,
        },
      );
    } on Object {
      // A failed diagnostic sink cannot replace the provider's failure event.
    }
  }

  void _attachParser() {
    _parsedEvents = const RegisterTaggedStreamParser()
        .parse(_content.stream)
        .listen(
          _emit,
          onError: (Object error) => _onStreamFailure(
            error,
            'The provider stream failed. Retry the correction.',
          ),
        );
    if (_consumerPaused) _parsedEvents?.pause();
  }

  void _attachDecoder(HttpClientResponse response) {
    _decodedContent = _decoder
        .decode(response, onProviderError: _recordStreamError)
        .listen(
          (content) {
            // Diagnostics can arrive before the parser delivers its deltas.
            _receivedText.write(content);
            _content.add(content);
          },
          onError: (Object error) => _onStreamFailure(
            error,
            'The provider returned an invalid or interrupted stream. Retry.',
          ),
          onDone: () {
            if (!_terminated) unawaited(_content.close());
          },
        );
    if (_content.isPaused) _decodedContent?.pause();
  }

  void _onStreamFailure(Object error, String message) {
    _failureContext = {
      ..._failureContext,
      'error_type': error.runtimeType.toString(),
    };
    _emit(_failure(CorrectionFailureKind.providerError, message));
  }

  void _emit(CorrectionEvent event) {
    if (_terminated) return;
    switch (event) {
      case SuggestionDelta():
        _output.add(event);
      case CorrectionCompleted():
        final valid =
            event.suggestions.length == SuggestionRegister.values.length &&
            SuggestionRegister.values.every(
              (register) =>
                  event.suggestions
                          .where((item) => item.register == register)
                          .length ==
                      1 &&
                  event.suggestions.any(
                    (item) =>
                        item.register == register &&
                        item.text.trim().isNotEmpty,
                  ),
            );
        _finish(
          valid
              ? event
              : _failure(
                  CorrectionFailureKind.malformedResponse,
                  'The provider returned an incomplete correction. Retry.',
                ),
        );
      case CorrectionFailed():
        _finish(event);
    }
  }

  void _finish(CorrectionEvent event) {
    _terminated = true;
    if (event case CorrectionFailed()) _logFailure(event);
    _output.add(event);
    unawaited(_output.close());
    unawaited(_shutdown());
  }

  Future<void> _onCancel() {
    _terminated = true;
    return _shutdown();
  }

  Future<void> _shutdown() async {
    _deadline?.cancel();
    _deadline = null;
    _request?.abort();
    _request = null;
    _client?.close(force: true);
    _client = null;
    await _errorBodySubscription?.cancel();
    _errorBodySubscription = null;
    await _decodedContent?.cancel();
    _decodedContent = null;
    await _parsedEvents?.cancel();
    _parsedEvents = null;
    // Cancelling the parser removes the only listener. Closing an unlistened
    // single-subscription controller can leave its done future unresolved.
  }
}

Uri? _validatedEndpoint(String rawBaseUrl) {
  final raw = rawBaseUrl.trim();
  if (raw.isEmpty) return null;
  final base = Uri.tryParse(raw);
  if (base == null ||
      base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment) {
    return null;
  }
  final loopback =
      base.host == 'localhost' ||
      base.host == '127.0.0.1' ||
      base.host == '::1';
  if (base.scheme != 'https' && !(base.scheme == 'http' && loopback)) {
    return null;
  }
  final path = base.path.replaceFirst(RegExp(r'/$'), '');
  if (path.endsWith('/chat/completions')) return base;
  return base.replace(path: '$path/chat/completions');
}

CorrectionFailed _statusFailure(int status) {
  if (status == HttpStatus.ok) {
    return _failure(
      CorrectionFailureKind.providerError,
      'The provider returned JSON instead of a correction stream. Retry.',
    );
  }
  if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
    return _failure(
      CorrectionFailureKind.providerUnavailable,
      'The provider rejected the API key. Check the configured key and retry.',
    );
  }
  if (status == HttpStatus.notFound) {
    return _failure(
      CorrectionFailureKind.providerUnavailable,
      'The Chat Completions endpoint was not found. Check the Base URL.',
    );
  }
  return _failure(
    CorrectionFailureKind.providerError,
    'The provider returned HTTP $status. Check its service and retry.',
  );
}

CorrectionFailed _failure(CorrectionFailureKind kind, String message) =>
    CorrectionFailed(kind: kind, message: message);
