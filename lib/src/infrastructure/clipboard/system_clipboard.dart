import 'package:flutter/services.dart';

import '../../domain/clipboard/clipboard_port.dart';

/// [ClipboardPort] over Flutter's own `Clipboard` service.
///
/// No new dependency: `package:flutter/services.dart` is already in the graph,
/// and the engine's platform channel is what talks to the display server. Only
/// plain text crosses it — nothing above this port may assume X11 primary
/// selection exists (AGENTS.md §4.2).
///
/// Deliberately holds no [Logger]. Every value that passes through here is
/// whatever the user last copied, and the Consistency Conventions forbid it
/// reaching a log line; having no logger to reach for makes that structural
/// rather than a rule someone has to remember. A rejected read or write
/// propagates as a failed future, and `CorrectionController` already logs the
/// failure without its payload (CAP-2).
final class SystemClipboard implements ClipboardPort {
  const SystemClipboard();

  /// Null when the clipboard is empty or holds no plain text — absence is a
  /// modelled value, never a failed read.
  @override
  Future<String?> readText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  Future<void> writeText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
