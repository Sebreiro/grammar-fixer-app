import '../../domain/hotkey/hotkey_binding.dart';

/// One home for rendering a [HotkeyBinding] as text, so the preference and the
/// effective combination are never spelled two ways on one screen.
///
/// The modifier order is [HotkeyModifier.values]', not the set's iteration
/// order: `{shift, control}` and `{control, shift}` are the same combination
/// (that is what the type's set-based `==` says), and a reader shown
/// `Shift+Control+G` beside `Control+Shift+G` would reasonably conclude they
/// differ. Deriving the order from the enum also means a fifth modifier lands in
/// a fixed place rather than wherever a hand-written list forgot to put it.
///
/// Deliberately not a display-server syntax. Each adapter serializes a binding
/// to its own backend's spelling and that vocabulary never rises out of the ring
/// it lives in (AD-9); this is prose for a settings screen.
String hotkeyBindingLabel(HotkeyBinding binding) {
  final parts = [
    for (final modifier in HotkeyModifier.values)
      if (binding.modifiers.contains(modifier)) hotkeyModifierLabel(modifier),
    binding.key,
  ];
  return parts.join('+');
}

/// What a user calls one modifier, rather than what the enum does: the Super key
/// is labelled `Meta` on no Linux keyboard anyone ships.
///
/// Public because the toggle the user clicks has to say the same word this
/// read-out does. It said `meta` while the sentence two lines above said `Super`,
/// which is one vocabulary with two homes — exactly what this file exists to
/// prevent. Exhaustive, so a fifth [HotkeyModifier] does not compile until
/// someone decides what to call it.
String hotkeyModifierLabel(HotkeyModifier modifier) => switch (modifier) {
  HotkeyModifier.control => 'Ctrl',
  HotkeyModifier.alt => 'Alt',
  HotkeyModifier.shift => 'Shift',
  HotkeyModifier.meta => 'Super',
};
