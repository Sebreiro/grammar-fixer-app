import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../domain/correction/correction_event.dart';
import '../../../domain/correction/correction_provider.dart';
import '../../../domain/correction/preset.dart';
import '../../../domain/correction/suggestion_register.dart';
import '../shared/register_tagged_stream_parser.dart';
import 'chat_completion_sse_decoder.dart';

/// One explicitly configured Chat Completions endpoint, with no fallback.
final class OpenAiCompatibleCorrectionProvider implements CorrectionProvider {
  const OpenAiCompatibleCorrectionProvider({
    required this.baseUrl,
    this.apiKey,
    this.resolveApiKey,
    this.timeout = const Duration(seconds: 60),
  });

  static const providerId = 'openai-compatible';
  static const baseUrlSettingsKey = 'baseUrl';

  final String baseUrl;
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
  static const _decoder = ChatCompletionSseDecoder();

  final String baseUrl;
  final String? apiKey;
  final Future<String?> Function()? resolveApiKey;
  final Duration timeout;
  final String text;
  final Preset preset;

  late final StreamController<CorrectionEvent> _output;
  late final StreamController<String> _content;
  StreamSubscription<String>? _decodedContent;
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
    } on Object {
      _emit(
        _failure(
          CorrectionFailureKind.providerUnavailable,
          'Could not read the API key source. Check Settings and retry.',
        ),
      );
      return;
    }
    if (_terminated) return;
    if (endpoint.host == 'api.openai.com' && (resolvedKey?.isEmpty ?? true)) {
      _emit(
        _failure(
          CorrectionFailureKind.providerUnavailable,
          'Configure an OpenAI API key, then retry.',
        ),
      );
      return;
    }
    final body = _requestBody();
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
      if (response.statusCode != HttpStatus.ok) {
        _emit(_statusFailure(response.statusCode));
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
    } on Object {
      _emit(
        _failure(
          CorrectionFailureKind.providerError,
          'Could not reach the configured provider. Check its address and connection, then retry.',
        ),
      );
    }
  }

  String _requestBody() => jsonEncode({
    'model': preset.model,
    'messages': [
      {'role': 'system', 'content': preset.systemPrompt},
      {'role': 'user', 'content': text},
    ],
    'stream': true,
    'temperature': 0.2,
    'n': 1,
    'max_tokens': 512,
  });

  void _attachParser() {
    _parsedEvents = const RegisterTaggedStreamParser()
        .parse(_content.stream)
        .listen(
          _emit,
          onError: (Object _) => _emit(
            _failure(
              CorrectionFailureKind.providerError,
              'The provider stream failed. Retry the correction.',
            ),
          ),
        );
    if (_consumerPaused) _parsedEvents?.pause();
  }

  void _attachDecoder(HttpClientResponse response) {
    _decodedContent = _decoder
        .decode(response)
        .listen(
          (content) => _content.add(content),
          onError: (Object _) => _emit(
            _failure(
              CorrectionFailureKind.providerError,
              'The provider returned an invalid or interrupted stream. Retry.',
            ),
          ),
          onDone: () {
            if (!_terminated) unawaited(_content.close());
          },
        );
    if (_content.isPaused) _decodedContent?.pause();
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
