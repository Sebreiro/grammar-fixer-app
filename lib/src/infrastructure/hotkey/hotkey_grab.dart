import '../../domain/collection_equality.dart';
import '../../domain/hotkey/hotkey_binding.dart';

/// One grab request, as it crosses the `HotkeyRegistrar` seam.
///
/// Carries domain types and a USB HID usage only, so no `HotKey`,
/// `HotKeyModifier`, `PhysicalKeyboardKey`, GDK keyval or accelerator string
/// ever reaches `X11GlobalHotkey` (AD-9). The translation from
/// [HotkeyBinding.key] to [usbHidUsage] is `HotkeyKeyCatalogue`'s, and it
/// happens above this type; the translation from a usage to the backend's own
/// vocabulary happens below it, inside the one file that names the vendor
/// package.
///
/// Value equality because a hand-written value type without it compares by
/// identity, which makes every "the seam was asked for exactly this" assertion
/// pass vacuously — the lesson `TrayMenuEntry` cost a review pass to learn.
final class HotkeyGrab {
  HotkeyGrab({
    required Set<HotkeyModifier> modifiers,
    required this.usbHidUsage,
  }) : modifiers = Set<HotkeyModifier>.unmodifiable(modifiers);

  /// Copied on construction rather than held by reference. Equality here is
  /// load-bearing — see below — and a caller that mutated the set it passed in
  /// would silently change what an already-recorded grab compares equal to.
  /// The constructor is therefore not `const`, which is the price.
  final Set<HotkeyModifier> modifiers;

  /// The USB HID Usage Tables 1.12 usage of the key itself, on the
  /// Keyboard/Keypad page — `0x0007000a` for G.
  final int usbHidUsage;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HotkeyGrab &&
        usbHidUsage == other.usbHidUsage &&
        setEquals(modifiers, other.modifiers);
  }

  @override
  int get hashCode => Object.hash(usbHidUsage, setHash(modifiers));

  /// Rendered for test failure messages, where "two grabs differ" is otherwise
  /// two identical `Instance of 'HotkeyGrab'` lines.
  @override
  String toString() {
    final names = modifiers.map((modifier) => modifier.name).toList()..sort();
    // The separator goes with the names, not before the usage: an empty
    // modifier set is legal config, and `HotkeyGrab( 0x00070045)` reads as a
    // dropped modifier or a truncation rather than as the bare-key grab it is.
    final prefix = names.isEmpty ? '' : '${names.join('+')} ';
    return 'HotkeyGrab($prefix'
        '0x${usbHidUsage.toRadixString(16).padLeft(8, '0')})';
  }
}
