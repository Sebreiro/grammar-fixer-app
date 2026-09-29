import 'global_hotkey.dart';
import 'hotkey_bind_outcome.dart';

/// What a backend reports about the global shortcut **right now**, readable
/// without having been listening when it changed (HOTKEY-06, HOTKEY-03).
///
/// Two fields, because a surface needs two different things and only one of
/// them is structured. [outcome] is what a consumer branches on — bound,
/// retained after a refused replacement, or unavailable with a typed cause.
/// [backendDescription] is the backend's own wording for what is in effect;
/// one backend reports nothing else.
final class HotkeyStatus {
  const HotkeyStatus({required this.outcome, required this.backendDescription});

  /// The last outcome this backend produced — from `bind()` or from a
  /// backend-originated change, whichever is newer.
  ///
  /// Non-nullable, and that is what [GlobalHotkey.current]'s own nullability is
  /// for: "nothing has been asked of a backend yet" is the absence of a status,
  /// not a status carrying an absent outcome. So a consumer holding one of
  /// these always has something to render.
  ///
  /// *Whichever is newer* is the whole of the contract here, and it is the
  /// backend's to keep: a compositor-originated change that lands after a bind
  /// supersedes it, and one that lands before it does not. The rule for a
  /// consumer that watches `bind()` and `bindingChanges` separately — where the
  /// two can race in the same turn — is a different question, stated on the
  /// port by plan 01-08.
  final HotkeyBindOutcome outcome;

  /// The backend's own user-readable text for what is in effect, verbatim —
  /// or null when the backend authors no such text.
  ///
  /// The Wayland portal's `trigger_description`, which is documented as
  /// "user-readable text describing how to trigger the shortcut for the client
  /// to render". It is localized and backend-specific: a German desktop sends
  /// `Strg+Umschalt+G`. **Never parsed.** Turning it back into a
  /// [HotkeyBinding] would be a prediction of vendor and locale behaviour that
  /// fails silently, which is what DW-66's ratified `decision:` rejected in
  /// 2026-08 — the phrase is rendered, and rendered as the desktop's own
  /// wording rather than this app's.
  ///
  /// **Null on X11**, and that is a fact about the backend rather than a gap:
  /// there this app owns the grab, so what is in effect is the structured
  /// combination in [HotkeyRegistration.effective] and a surface renders it
  /// with `hotkeyBindingLabel`. There is no second, backend-authored spelling
  /// to carry.
  ///
  /// Null also when a backend that *does* author text has nothing in effect to
  /// describe: an unavailable outcome carries no description, because there is
  /// no shortcut for one to be about.
  final String? backendDescription;

  /// Value equality over both fields, for the reason [HotkeyRegistration]'s own
  /// override gives: `SettingsState` contains this transitively, and a state
  /// that compares by identity cannot be deduped by any consumer.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HotkeyStatus &&
        outcome == other.outcome &&
        backendDescription == other.backendDescription;
  }

  @override
  int get hashCode => Object.hash(outcome, backendDescription);
}
