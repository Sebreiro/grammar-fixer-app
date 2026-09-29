import 'package:hotkey_grammar_corrector/src/infrastructure/panel/keyboard_focus_witness.dart';

/// A [KeyboardFocusWitness] whose answer the test states.
///
/// The real witness is one `XGetInputFocus` round trip against a live server,
/// which the adapter's binding-free `package:test` rows cannot reach — that
/// test need is the whole justification for the seam existing (AGENTS.md §4.2).
///
/// [answer] defaults to `false`, which is the seam's fail-safe direction: a row
/// that does not care about the witness gets the pre-seam behaviour.
///
/// [reads] is here so a row can assert the witness was **not** consulted, which
/// is a different claim from asserting the panel was not dismissed: a focus-out
/// the adapter answers on its own (DW-33's question) must not spend an X round
/// trip on a path that returns anyway, and only a read count can say so.
final class FakeKeyboardFocusWitness implements KeyboardFocusWitness {
  FakeKeyboardFocusWitness({this.answer = false});

  /// What [focusUnmoved] reports. Settable mid-row: a suppressed focus-out
  /// followed by a genuine one is one adapter and two different answers.
  bool answer;

  /// When set, [focusUnmoved] throws it instead of answering — a seam breaking
  /// its promise of a value, which the adapter's AD-15 backstop has to reduce
  /// to a log line and a `false`.
  ///
  /// A throw rather than a rejection because the read is synchronous: there is
  /// no future here for an error to travel on.
  Object? readError;

  /// When set, [recordFocusGained] throws it after counting the call — the
  /// write half of [readError], and the injection point the write half of the
  /// seam had none of.
  ///
  /// A throw rather than a rejection for [readError]'s reason: the call is
  /// synchronous and returns nothing, so there is no future here for an error
  /// to travel on.
  ///
  /// Thrown *after* [recordedGains] is incremented so a row can assert both
  /// that the call was made and that it failed — the same distinction [reads]
  /// makes on the read side. It exists because the write half had no injection
  /// point at all, which is exactly how an unpinned guard survives a suite.
  Object? recordError;

  /// How many times [recordFocusGained] ran, including the runs that threw.
  /// The `focus` arm's `_visible` guard governs the recording as well as
  /// `_focused`, and this is what says so.
  int recordedGains = 0;

  /// How many times [focusUnmoved] was read, including the reads that threw.
  int reads = 0;

  bool disposed = false;

  @override
  void recordFocusGained() {
    recordedGains += 1;
    final error = recordError;
    if (error != null) {
      throw error;
    }
  }

  @override
  bool get focusUnmoved {
    reads += 1;
    final error = readError;
    if (error != null) {
      throw error;
    }
    return answer;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
