import 'dart:convert';

import '../../../domain/correction/correction_event.dart';

// One public type per file (AGENTS.md §3) is deliberately relaxed here: the
// spine's structural seed names exactly `sidecar_protocol.dart` for the AD-19
// line shapes, so this file holds the whole wire vocabulary the way
// correction_event.dart holds its sealed family. Splitting it would scatter
// one protocol over four files.

/// The single JSON line Dart writes to the sidecar's stdin (AD-19).
final class SidecarRequest {
  const SidecarRequest({
    required this.text,
    required this.model,
    required this.systemPrompt,
  });

  final String text;
  final String model;
  final String systemPrompt;

  /// One line, no trailing newline — the writer owns line termination.
  String toJsonLine() =>
      jsonEncode({'text': text, 'model': model, 'system_prompt': systemPrompt});
}

/// One NDJSON line the sidecar writes on stdout (AD-19).
sealed class SidecarLine {
  const SidecarLine();

  /// Strict parse: anything that is not exactly one of the three protocol
  /// shapes throws [FormatException], because a sidecar speaking a different
  /// dialect is a transport fault the adapter must surface as
  /// [CorrectionFailureKind.providerError] — never guess-repair.
  factory SidecarLine.parse(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('sidecar line is not a JSON object', line);
    }
    return switch (decoded['type']) {
      'text' => SidecarTextLine._parse(decoded),
      'done' => const SidecarDoneLine(),
      'error' => SidecarErrorLine._parse(decoded),
      _ => throw FormatException('unknown or missing sidecar line type', line),
    };
  }
}

/// A verbatim chunk of raw model text; register tags are the parser's job.
final class SidecarTextLine extends SidecarLine {
  const SidecarTextLine({required this.text});

  factory SidecarTextLine._parse(Map<String, Object?> line) {
    final text = line['text'];
    if (text is! String) {
      throw FormatException('text line without a string "text" field', '$line');
    }
    return SidecarTextLine(text: text);
  }

  final String text;
}

/// The text stream ended. Not success — the parser decides that (AD-19).
final class SidecarDoneLine extends SidecarLine {
  const SidecarDoneLine();
}

/// The sidecar's failure terminal, already translated to a domain kind.
final class SidecarErrorLine extends SidecarLine {
  const SidecarErrorLine({required this.kind, required this.message});

  factory SidecarErrorLine._parse(Map<String, Object?> line) {
    final kind = line['kind'];
    final message = line['message'];
    if (kind is! String || message is! String) {
      throw FormatException(
        'error line without string "kind" and "message" fields',
        '$line',
      );
    }
    // Mapped by name; an unknown kind degrades to providerError instead of
    // failing the parse, so a newer sidecar cannot brick an older daemon.
    return SidecarErrorLine(
      kind:
          CorrectionFailureKind.values.asNameMap()[kind] ??
          CorrectionFailureKind.providerError,
      message: message,
    );
  }

  final CorrectionFailureKind kind;
  final String message;
}
