import 'keyboard_focus_witness.dart';

/// The [KeyboardFocusWitness] for every host that cannot answer the question.
/// It never suppresses anything.
///
/// [focusUnmoved] is `false` unconditionally, which is the seam's own
/// fail-safe direction stated as a whole implementation: a caller wired to this
/// witness answers a focus-out exactly as it did before the seam existed, so
/// CAP-14's focus-loss hide is untouched.
///
/// This is the Wayland arm. The XDG GlobalShortcuts portal takes no key grab —
/// the compositor owns the binding and delivers an activation, so nothing the
/// daemon does can produce the spurious `FocusOut(NotifyGrab)` that G-01-13 is
/// about — and there is no portal call that reports the keyboard owner either.
/// A witness that cannot prove a focus-out spurious must not claim it is, so
/// the honest Wayland answer is the null object rather than a second
/// implementation guessing.
final class AbsentKeyboardFocusWitness implements KeyboardFocusWitness {
  const AbsentKeyboardFocusWitness();

  @override
  void recordFocusGained() {
    // Nothing to record: there is no later comparison to make.
  }

  @override
  bool get focusUnmoved => false;

  @override
  Future<void> dispose() async {
    // Nothing was opened.
  }
}
