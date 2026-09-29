/// The keys this build can register as a shortcut, in a vocabulary the rings
/// above infrastructure are allowed to hold (AD-1).
///
/// The table itself belongs to the infrastructure key catalogue and stays
/// there — this is the *value* that catalogue produces, carried across the
/// rings by injection from the composition root rather than by an import. The
/// catalogue is deliberately not named here either: `lib/main.dart` and
/// `lib/src/infrastructure/` are the only places in the project that spell it.
///
/// AD-1 forbids both the application ring (`ad1_import_rule_test.dart`'s second
/// rule) and the ui ring (its third) from naming an infrastructure type, and
/// both rules fail on the import directive, so a controller that imported the
/// catalogue to "supply" it would fail exactly as loudly as a widget that
/// imported it. DW-71 ratified the route: the vocabulary is *supplied* to
/// `SettingsController`, which means the controller holds a value somebody
/// else built. That somebody is `main.dart`,
/// the only file outside `lib/src/` and the only one that overrides a seam.
///
/// Keyed on the USB HID usage rather than the label, because that is what a
/// capture control has: `KeyEvent.physicalKey.usbHidUsage` is exactly the
/// integer the catalogue is keyed on and that `HotkeyGrab` carries, so a
/// captured key is looked up directly — no label guessing and no dependence on
/// the keyboard layout.
final class RegistrableKeys {
  RegistrableKeys(Iterable<RegistrableKey> keys)
    : _byUsage = Map<int, RegistrableKey>.unmodifiable(<int, RegistrableKey>{
        for (final key in keys) key.usbHidUsage: key,
      });

  /// Copied and made unmodifiable on construction, so a caller that keeps
  /// mutating the iterable it passed cannot change a supposedly fixed
  /// vocabulary underneath the validator reading it.
  final Map<int, RegistrableKey> _byUsage;

  /// The key [usbHidUsage] names, or null when this build offers no such key —
  /// which is one of the four subjects `HotkeyCaptureValidator` refuses.
  RegistrableKey? forUsage(int usbHidUsage) => _byUsage[usbHidUsage];

  /// Every key in the vocabulary, for a surface that wants to describe it.
  Iterable<RegistrableKey> get all => _byUsage.values;
}

/// One key of [RegistrableKeys]: the usage a capture reports and the label the
/// config file and the settings screen spell it with.
///
/// It carried a third clause until plan 01-19 — whether the Wayland portal
/// could be told about the key. Every key the shipped catalogue produces could
/// be, by construction, so the flag was always true and the refusal reading it
/// could never fire. The invariant it stood for is real and is now asserted at
/// build time instead: `hotkey_key_catalogue_test.dart` over the injected
/// vocabulary, and `xdg_shortcut_trigger_test.dart`'s parity group in both
/// directions.
final class RegistrableKey {
  const RegistrableKey({required this.usbHidUsage, required this.label});

  /// USB HID Usage Tables 1.12 §10, Keyboard/Keypad page — the same integer
  /// `PhysicalKeyboardKey.usbHidUsage` reports.
  final int usbHidUsage;

  /// What `HotkeyBinding.key` holds for this key.
  final String label;
}
