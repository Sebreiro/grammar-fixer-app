import 'dart:async';

import '../../../domain/correction/correction_event.dart';
import '../../../domain/correction/suggestion.dart';
import '../../../domain/correction/suggestion_register.dart';

/// Turns the shipped preset's `FORMAL:`/`CASUAL:`/`SHORTER:` tagged text
/// stream into [CorrectionEvent]s (AD-16).
///
/// **Only one end-of-stream shape completes:** the three register lines, in
/// declaration order, each terminated, followed by a line holding exactly
/// [endSentinel] and then nothing but whitespace. Every other ending —
/// including a `SHORTER:` line that simply stops, which is what a truncated
/// response looks like — is [CorrectionFailureKind.malformedResponse].
///
/// The sentinel exists because a clean transport close mid-final-line is
/// otherwise indistinguishable from a complete response, so a cut-off
/// correction used to succeed with partial text. A trailing newline would
/// not do: whitespace is routinely dropped by models and transports, and it
/// cannot catch a truncation that lands on a line boundary. [endSentinel] is
/// content the model emits deliberately, mandated by the shipped preset's
/// prompt, which interpolates this very constant so prompt and parser cannot
/// drift apart.
///
/// The object is stateless: every [parse] call owns its own parse state, so
/// one instance is reusable across corrections. The returned stream honours
/// AD-3 — zero or more [SuggestionDelta], then exactly one terminal event,
/// then close, never a thrown error — and AD-4: it is single-subscription,
/// and cancelling it cancels the input subscription.
///
/// The parser terminates only when its input does: bounding a stalled
/// transport (timeouts, [CorrectionFailureKind.timeout]) is the adapter's
/// fault domain, not the parser's.
final class RegisterTaggedStreamParser {
  const RegisterTaggedStreamParser();

  /// The final line every conforming response ends with. Defined here, and
  /// interpolated into the shipped system prompt, so there is one spelling.
  static const String endSentinel = 'END';

  Stream<CorrectionEvent> parse(Stream<String> textChunks) {
    final session = _ParseSession();
    late final StreamController<CorrectionEvent> controller;
    StreamSubscription<String>? input;
    var terminated = false;

    // The single funnel to the listener: it enforces AD-3 ordering so the
    // pure session never has to know about subscriptions.
    void emit(CorrectionEvent event) {
      if (terminated) {
        return;
      }
      switch (event) {
        case SuggestionDelta():
          controller.add(event);
        case CorrectionCompleted() || CorrectionFailed():
          // Terminal: stop consuming input first so nothing can follow it.
          terminated = true;
          input?.cancel().ignore();
          input = null;
          controller.add(event);
          unawaited(controller.close());
      }
    }

    controller = StreamController<CorrectionEvent>(
      onListen: () {
        input = textChunks.listen(
          (chunk) => session.addChunk(chunk).forEach(emit),
          // A broken transport is the adapter's fault domain, not a format
          // problem — the sole non-malformedResponse terminal (AD-15).
          onError: (Object _) => emit(
            CorrectionFailed(
              kind: CorrectionFailureKind.providerError,
              message: 'The provider stream failed. Retry the correction.',
            ),
          ),
          onDone: () {
            // A terminal may already exist if a nonconforming input
            // delivered events synchronously during listen(); finish()
            // must not even be evaluated then.
            if (terminated) {
              return;
            }
            emit(session.finish());
          },
        );
        // Same synchronous-delivery hazard: the emit that terminated ran
        // while `input` was still null, so its cancel was a no-op.
        if (terminated) {
          input?.cancel().ignore();
          input = null;
        }
      },
      // Backpressure: a paused consumer must pause the transport instead
      // of buffering it unboundedly.
      onPause: () => input?.pause(),
      onResume: () => input?.resume(),
      // AD-4: the consumer cancelling the output is the cancellation signal.
      onCancel: () {
        final pending = input?.cancel();
        input = null;
        return pending;
      },
    );
    return controller.stream;
  }
}

/// Where the session stands between structural elements of the response.
enum _Phase {
  /// At the start of the stream or of a line, matching the next expected tag.
  expectingTag,

  /// Past a tag's colon, streaming that register's line as deltas.
  readingRegisterLine,

  /// Past the `SHORTER:` line, matching the terminating `END` sentinel.
  expectingEndSentinel,

  /// Past the sentinel; only whitespace may remain.
  afterEndSentinel,

  /// A malformed-response terminal has been produced; input is dead.
  failed,
}

/// Synchronous parse state for one correction: chunks in, events out.
///
/// All decisions live here in pure code (AGENTS.md §2); the stream plumbing
/// above only relays what this machine decides.
final class _ParseSession {
  final List<StringBuffer> _accumulatedTexts = [
    for (final _ in SuggestionRegister.values) StringBuffer(),
  ];

  _Phase _phase = _Phase.expectingTag;

  /// Register whose tag is expected next, or whose line is being read.
  int _registerIndex = 0;

  /// Text held back after a line start while it is still a prefix of the
  /// expected token — a register tag, or the closing sentinel. It never
  /// leaks into deltas and is never lost: it either completes the token or
  /// condemns the response.
  final StringBuffer _heldTokenPrefix = StringBuffer();

  /// False while whitespace right after a tag's colon is being skipped —
  /// that whitespace is presentation, not register content.
  bool _lineContentStarted = false;

  /// Events produced by feeding [chunk] through the machine. A terminal
  /// failure, if any, is the last event; nothing follows it.
  List<CorrectionEvent> addChunk(String chunk) {
    final events = <CorrectionEvent>[];
    var position = 0;
    while (position < chunk.length && _phase != _Phase.failed) {
      position = switch (_phase) {
        _Phase.expectingTag => _consumeTagPrefix(chunk, position, events),
        _Phase.readingRegisterLine => _consumeRegisterLine(
          chunk,
          position,
          events,
        ),
        _Phase.expectingEndSentinel => _consumeEndSentinel(
          chunk,
          position,
          events,
        ),
        _Phase.afterEndSentinel => _consumeTrailingWhitespace(
          chunk,
          position,
          events,
        ),
        _Phase.failed => chunk.length,
      };
    }
    return events;
  }

  /// The terminal event for the end of the input stream. Only a response
  /// that reached the far side of the sentinel completes; an unterminated
  /// final register line is a truncation, not a tolerable omission.
  CorrectionEvent finish() {
    final lastRegisterIndex = SuggestionRegister.values.length - 1;
    return switch (_phase) {
      _Phase.afterEndSentinel => _completed(),
      _Phase.expectingEndSentinel => _missingSentinelFailure(),
      _Phase.readingRegisterLine when _registerIndex == lastRegisterIndex =>
        _missingSentinelFailure(),
      _Phase.readingRegisterLine => _missingRegisterFailure(_registerIndex + 1),
      _Phase.expectingTag => _missingRegisterFailure(_registerIndex),
      // Unreachable: the failure terminal already ended the parse, and the
      // wrapper cancels input before it could deliver a done event.
      _Phase.failed => throw StateError('finish() after a failure terminal'),
    };
  }

  int _consumeTagPrefix(
    String chunk,
    int position,
    List<CorrectionEvent> events,
  ) {
    final tag = _tagFor(SuggestionRegister.values[_registerIndex]);
    return _consumeToken(
      chunk,
      position,
      events,
      token: tag,
      violation: (held) =>
          'expected the "$tag" tag at the start of a line, found "$held"',
      onMatched: () {
        _phase = _Phase.readingRegisterLine;
        _lineContentStarted = false;
      },
    );
  }

  int _consumeEndSentinel(
    String chunk,
    int position,
    List<CorrectionEvent> events,
  ) {
    const sentinel = RegisterTaggedStreamParser.endSentinel;
    return _consumeToken(
      chunk,
      position,
      events,
      token: sentinel,
      violation: (held) =>
          'expected the "$sentinel" sentinel after the '
          '"${_tagFor(SuggestionRegister.values.last)}" line, found "$held"',
      onMatched: () => _phase = _Phase.afterEndSentinel,
    );
  }

  /// Matches [token] a character at a time, holding back a partial match so
  /// it can never leak into a delta, and failing the moment the held text
  /// can no longer become [token] — no need to wait for the rest of the
  /// line or the stream.
  int _consumeToken(
    String chunk,
    int position,
    List<CorrectionEvent> events, {
    required String token,
    required String Function(String held) violation,
    required void Function() onMatched,
  }) {
    var index = position;
    while (index < chunk.length) {
      final char = chunk[index];
      if (_heldTokenPrefix.isEmpty && _isWhitespace(char)) {
        // Whitespace between lines never condemns a response; only text
        // that cannot become the expected token does.
        index += 1;
        continue;
      }
      _heldTokenPrefix.write(char);
      index += 1;
      final held = _heldTokenPrefix.toString();
      if (held == token) {
        _heldTokenPrefix.clear();
        onMatched();
        return index;
      }
      if (!token.startsWith(held)) {
        _fail(events, violation(held));
        return index;
      }
    }
    return index;
  }

  int _consumeRegisterLine(
    String chunk,
    int position,
    List<CorrectionEvent> events,
  ) {
    final register = SuggestionRegister.values[_registerIndex];
    var index = position;
    if (!_lineContentStarted) {
      while (index < chunk.length &&
          !_isLineTerminator(chunk[index]) &&
          _isWhitespace(chunk[index])) {
        index += 1;
      }
      if (index < chunk.length && !_isLineTerminator(chunk[index])) {
        _lineContentStarted = true;
      }
    }
    final terminatorIndex = _indexOfLineTerminator(chunk, index);
    final content = chunk.substring(index, terminatorIndex ?? chunk.length);
    if (content.isNotEmpty) {
      _accumulatedTexts[register.index].write(content);
      events.add(SuggestionDelta(register: register, textDelta: content));
    }
    if (terminatorIndex == null) {
      return chunk.length;
    }
    _advancePastRegisterLine();
    return terminatorIndex + 1;
  }

  int _consumeTrailingWhitespace(
    String chunk,
    int position,
    List<CorrectionEvent> events,
  ) {
    var index = position;
    while (index < chunk.length) {
      if (!_isWhitespace(chunk[index])) {
        _fail(
          events,
          'only whitespace may follow the '
          '"${RegisterTaggedStreamParser.endSentinel}" sentinel, '
          'found "${chunk[index]}"',
        );
        return index;
      }
      index += 1;
    }
    return index;
  }

  void _advancePastRegisterLine() {
    if (_registerIndex == SuggestionRegister.values.length - 1) {
      _phase = _Phase.expectingEndSentinel;
      return;
    }
    _registerIndex += 1;
    _phase = _Phase.expectingTag;
  }

  void _fail(List<CorrectionEvent> events, String violation) {
    _phase = _Phase.failed;
    events.add(
      CorrectionFailed(
        kind: CorrectionFailureKind.malformedResponse,
        message: 'malformed response: $violation',
      ),
    );
  }

  /// The truncation terminal: every register arrived, but the response
  /// stopped before proving it was finished.
  ///
  /// The message names the preset's prompt because that is the likeliest
  /// cause once the daemon is in a user's hands: CAP-8 invites editing
  /// `systemPrompt`, and an edit that drops the sentinel instruction cannot
  /// be caught by config validation — AD-16 makes the register-tagged format
  /// a per-adapter choice, so the store must not demand the sentinel of
  /// every preset. This message is what makes the panel error diagnosable
  /// instead of mysterious.
  CorrectionFailed _missingSentinelFailure() {
    const sentinel = RegisterTaggedStreamParser.endSentinel;
    return CorrectionFailed(
      kind: CorrectionFailureKind.malformedResponse,
      message:
          'malformed response: the stream ended before the closing '
          '"$sentinel" line, so the response may have been truncated — if '
          'every correction fails this way, check that the active preset\'s '
          'system prompt still asks for a final "$sentinel" line',
    );
  }

  CorrectionFailed _missingRegisterFailure(int missingRegisterIndex) {
    final tag = _tagFor(SuggestionRegister.values[missingRegisterIndex]);
    return CorrectionFailed(
      kind: CorrectionFailureKind.malformedResponse,
      message:
          'malformed response: stream ended before the "$tag" register '
          'was complete',
    );
  }

  // CorrectionCompleted is authoritative over the deltas (AD-3), so this is
  // where whitespace gets normalised: trimmed per register, enum order.
  CorrectionCompleted _completed() {
    return CorrectionCompleted(
      suggestions: [
        for (final register in SuggestionRegister.values)
          Suggestion(
            register: register,
            text: _accumulatedTexts[register.index].toString().trim(),
          ),
      ],
    );
  }
}

String _tagFor(SuggestionRegister register) => switch (register) {
  SuggestionRegister.formal => 'FORMAL:',
  SuggestionRegister.casual => 'CASUAL:',
  SuggestionRegister.shorter => 'SHORTER:',
};

bool _isWhitespace(String char) => char.trim().isEmpty;

bool _isLineTerminator(String char) => char == '\n' || char == '\r';

int? _indexOfLineTerminator(String chunk, int from) {
  for (var index = from; index < chunk.length; index += 1) {
    if (_isLineTerminator(chunk[index])) {
      return index;
    }
  }
  return null;
}
