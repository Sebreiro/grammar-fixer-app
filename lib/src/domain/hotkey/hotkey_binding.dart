import '../collection_equality.dart';

enum HotkeyModifier { control, alt, shift, meta }

final class HotkeyBinding {
  HotkeyBinding({required Set<HotkeyModifier> modifiers, required this.key})
    : modifiers = Set<HotkeyModifier>.unmodifiable(modifiers);

  /// Copied on construction rather than held by reference. Equality here is
  /// load-bearing — see [operator ==] — and a caller that mutated the set it
  /// passed in would silently change what an already-recorded binding compares
  /// equal to. The constructor is therefore not `const`, which is the price.
  ///
  /// The consequence specific to this type is a rebuild that never happens:
  /// `SettingsState` holds a binding transitively and compares by value, so a
  /// mutated set makes a `copyWith` produce a state that compares *equal* to
  /// the one before it, and an equal state suppresses the rebuild that would
  /// have shown the change. No exception, no log line, nothing to trace.
  ///
  /// This is API hardening, not a fix for a live defect: at the time it was
  /// written no caller retained a set it had passed in — the capture control
  /// hands over a fresh `{..._modifiers}` and the shipped default is a `const`
  /// set literal, immutable at runtime — so a reader should not go looking for
  /// the bug this closed. There was not one.
  final Set<HotkeyModifier> modifiers;
  final String key; // logical key label, e.g. 'Space', 'G'

  /// Value equality, added to AD-9's declaration without touching its fields.
  /// [modifiers] compares as a set: `{control, shift}` and `{shift, control}`
  /// are the same combination, and a consumer comparing the requested binding
  /// with the one the backend reported (AD-10) would otherwise see two equal
  /// combinations as different. An unmodifiable copy of the same elements
  /// compares and hashes exactly as the caller's set did — `setEquals` and
  /// `setHash` are both order-independent — so the copy is invisible here.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HotkeyBinding &&
        key == other.key &&
        setEquals(modifiers, other.modifiers);
  }

  @override
  int get hashCode => Object.hash(key, setHash(modifiers));
}
