import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/clipboard/clipboard_port.dart';

final class FakeClipboardPort implements ClipboardPort {
  FakeClipboardPort({this.text});

  /// The clipboard content; null models an empty or non-text clipboard.
  String? text;

  /// Holds [readText] open until the test completes it. A real read is
  /// display-server IPC, so scenarios that turn on what happens *while* the
  /// panel is seeding — the user typing, a shutdown — need that window.
  Completer<void>? readGate;

  /// When set, [readText] throws it after [readGate] resolves. A real
  /// clipboard read is display-server IPC and can fail outright.
  Object? readError;

  /// Holds [writeText] open until the test completes it — [readGate]'s mirror
  /// for CAP-11's write. A write is display-server IPC too, so a panel session
  /// can end while one is still in flight.
  ///
  /// Read at *call* time, like [writeError]: two writes can then be in flight
  /// with different gates and different outcomes, which is the only way to
  /// express two overlapping copies resolving out of order.
  Completer<void>? writeGate;

  /// When set, [writeText] throws it and nothing is recorded. Captured when the
  /// call is made, not when it completes.
  Object? writeError;

  /// Every written value, in order, for assertions.
  final List<String> writes = [];

  /// How many times [readText] was called. Whether a read happened at all is
  /// the only observable for a session that should never have begun — a
  /// controller torn down mid-seed reports nothing either way.
  int readCalls = 0;

  @override
  Future<String?> readText() async {
    readCalls++;
    // Captured before the await, exactly as [writeText] does, and for the same
    // reason: a real read's answer is the clipboard it was handed to, not
    // whatever the test set while it waited. Without this, two overlapping
    // reads could not be given different content, which is the only way to
    // express a stale read landing after a newer session re-seeded — so the
    // guard against it was pinned by nothing.
    final gate = readGate;
    final error = readError;
    final value = text;
    await gate?.future;
    if (error != null) {
      throw error;
    }
    return value;
  }

  @override
  Future<void> writeText(String text) async {
    // Both captured before the await: a real write's outcome is decided by the
    // clipboard it was handed to, not by whatever the test set while it waited.
    final error = writeError;
    final gate = writeGate;
    await gate?.future;
    if (error != null) {
      throw error;
    }
    this.text = text;
    writes.add(text);
  }
}
