import 'dart:async';
import 'dart:convert';

/// Decodes complete Chat Completions SSE frames into ordered text deltas.
///
/// A successful close requires both a stop finish reason and `[DONE]`. The
/// bounded input stream cannot turn a truncated response into a completion.
final class ChatCompletionSseDecoder {
  const ChatCompletionSseDecoder();

  static const int maxBodyBytes = 2 * 1024 * 1024;
  static const int maxFrameBytes = 64 * 1024;

  Stream<String> decode(Stream<List<int>> bytes) {
    late final StreamController<String> output;
    StreamSubscription<String>? lines;
    final frameData = <String>[];
    var bodyBytes = 0;
    var frameBytes = 0;
    var sawStop = false;
    var ended = false;

    void fail() {
      if (ended) return;
      ended = true;
      output.addError(const FormatException('Invalid provider stream'));
      unawaited(lines?.cancel());
      unawaited(output.close());
    }

    void acceptFrame() {
      frameBytes = 0;
      if (frameData.isEmpty || ended) return;
      final data = frameData.join('\n');
      frameData.clear();
      if (data == '[DONE]') {
        if (!sawStop) {
          fail();
          return;
        }
        ended = true;
        unawaited(lines?.cancel());
        unawaited(output.close());
        return;
      }
      try {
        final Object? decoded = jsonDecode(data);
        if (decoded is! Map<String, Object?>) throw const FormatException();
        final choices = decoded['choices'];
        if (choices is! List<Object?>) throw const FormatException();
        if (choices.isEmpty) return; // Optional final usage frame.
        if (choices.length != 1 || choices.first is! Map<String, Object?>) {
          throw const FormatException();
        }
        final choice = choices.first as Map<String, Object?>;
        final finish = choice['finish_reason'];
        if (finish != null) {
          if (finish != 'stop' || sawStop) throw const FormatException();
          sawStop = true;
        }
        final delta = choice['delta'];
        if (delta is! Map<String, Object?>) throw const FormatException();
        final content = delta['content'];
        if (content != null && content is! String) {
          throw const FormatException();
        }
        if (content is String && content.isNotEmpty) {
          if (sawStop) throw const FormatException();
          output.add(content);
        }
      } on FormatException {
        fail();
      }
    }

    void acceptLine(String line) {
      if (ended) return;
      if (line.isEmpty) {
        acceptFrame();
        return;
      }
      frameBytes += utf8.encode(line).length;
      if (frameBytes > maxFrameBytes) {
        fail();
        return;
      }
      if (line.startsWith('data:')) {
        final value = line.substring(5);
        frameData.add(value.startsWith(' ') ? value.substring(1) : value);
      }
    }

    output = StreamController<String>(
      onListen: () {
        lines = bytes
            .map((chunk) {
              bodyBytes += chunk.length;
              if (bodyBytes > maxBodyBytes) {
                throw const FormatException('Provider stream too large');
              }
              return chunk;
            })
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              acceptLine,
              onError: (Object _) => fail(),
              onDone: () {
                if (!ended) fail();
              },
            );
      },
      onPause: () => lines?.pause(),
      onResume: () => lines?.resume(),
      onCancel: () => lines?.cancel(),
    );
    return output.stream;
  }
}
