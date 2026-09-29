import '../hotkey/hotkey_bind_outcome.dart';

/// The current shortcut result and any refusal still shown in Settings.
final class HotkeyTrayStatus {
  const HotkeyTrayStatus({required this.outcome, required this.rebindRefused});

  final HotkeyBindOutcome outcome;
  final bool rebindRefused;

  bool get unavailable => outcome is HotkeyUnavailable;

  @override
  bool operator ==(Object other) =>
      other is HotkeyTrayStatus &&
      outcome == other.outcome &&
      rebindRefused == other.rebindRefused;

  @override
  int get hashCode => Object.hash(outcome, rebindRefused);
}
