import '../../domain/hotkey/hotkey_binding.dart';
import '../../domain/hotkey/registrable_keys.dart';
import 'xdg_shortcut_trigger.dart';

/// Shared key vocabulary for capture, X11 grabs, and Wayland preferred triggers.
///
/// AD-9 keeps backend translation inside infrastructure. The shipped X11
/// registrar resolves a label to an X keysym, while this catalogue supplies
/// USB usages to capture and shares its offered labels with the Wayland trigger
/// serializer. Their parity tests keep one set of representable keys.
///
/// It is pure Dart on purpose. This is what lets `X11GlobalHotkey` refuse an
/// unrepresentable key *before* the backend is touched, so AD-12's "an
/// unrepresentable key is a value, not a throw" is decided in the binding-free
/// test set rather than against a channel.
///
/// Lookup trims and upper-cases because the binding is hand-editable config
/// (AD-13) and letter case does not change the key being requested.
final class HotkeyKeyCatalogue {
  const HotkeyKeyCatalogue._();

  /// USB HID Usage Tables 1.12 §10, Keyboard/Keypad page (0x07). The letters
  /// are one contiguous run of 26 usages, "Keyboard a and A" (0x04) through
  /// "Keyboard z and Z" (0x1d), so they are derived rather than listed: 26
  /// hand-written constants are 26 chances to transpose two digits, and
  /// nothing downstream would notice (a wrong-but-valid usage still resolves
  /// to a `PhysicalKeyboardKey`).
  static const int _letterRunStart = 0x00070004;
  static const int _letterRunLength = 26;

  /// The same table's digit run: "Keyboard 1 and !" (0x1e) through "Keyboard 0
  /// and )" (0x27). Note the wrap — **`0` sits at the end of the run**, after
  /// `9`, not before `1`.
  static const int _digitRunStart = 0x0007001e;
  static const int _digitRunLength = 10;

  /// The same table's function run: "Keyboard F1" (0x3a) through "Keyboard
  /// F12" (0x45). F13 and up continue elsewhere (0x68) and are deliberately
  /// not offered — they exist on almost no keyboard a user of this app has.
  static const int _functionRunStart = 0x0007003a;
  static const int _functionRunLength = 12;

  /// The keys that are not part of a run, in the order they are offered.
  ///
  /// Every one of these must also resolve to an X keysym name through
  /// `XdgShortcutTrigger.keysymNameFor`, which is what makes it grabbable —
  /// `X11KeyGrabRegistrar` hands that name to `XStringToKeysym`.
  /// `xdg_shortcut_trigger_test.dart` holds the two label sets equal in both
  /// directions, which is the drift check between this list and that one.
  ///
  /// It used to be justified the other way round: each key had to sit inside
  /// `uni_platform`'s physical-to-logical table so the GDK keyval the removed
  /// plugin needed was resolvable, pinned by a mocked-channel suite. Both the
  /// table and the suite are gone, and the constraint that replaced them is
  /// entirely inside this project.
  static const Map<String, int> _namedKeys = <String, int>{
    'Space': 0x0007002c,
    'Tab': 0x0007002b,
    'Enter': 0x00070028,
    'Escape': 0x00070029,
    'Backspace': 0x0007002a,
    'Insert': 0x00070049,
    'Delete': 0x0007004c,
    'Home': 0x0007004a,
    'End': 0x0007004d,
    'PageUp': 0x0007004b,
    'PageDown': 0x0007004e,
    'ArrowUp': 0x00070052,
    'ArrowDown': 0x00070051,
    'ArrowLeft': 0x00070050,
    'ArrowRight': 0x0007004f,
    'Minus': 0x0007002d,
    'Equal': 0x0007002e,
    'BracketLeft': 0x0007002f,
    'BracketRight': 0x00070030,
    'Backslash': 0x00070031,
    'Semicolon': 0x00070033,
    'Quote': 0x00070034,
    'Backquote': 0x00070035,
    'Comma': 0x00070036,
    'Period': 0x00070037,
    'Slash': 0x00070038,
  };

  static final Map<String, int> _namedKeysByUpperCase = <String, int>{
    for (final MapEntry(:key, :value) in _namedKeys.entries)
      key.toUpperCase(): value,
  };

  static final RegExp _functionKey = RegExp(r'^F([1-9]|1[0-2])$');

  /// The USB HID usage [label] names, or null when this build cannot register
  /// it — which `X11GlobalHotkey` turns into a `HotkeyUnavailable` carrying
  /// the label, without ever reaching the backend.
  static int? usbHidUsageFor(String label) {
    final normalized = label.trim().toUpperCase();
    if (normalized.isEmpty) {
      return null;
    }
    return _letterUsage(normalized) ??
        _digitUsage(normalized) ??
        _functionUsage(normalized) ??
        _namedKeysByUpperCase[normalized];
  }

  /// Every label this catalogue resolves, in the order they are offered:
  /// letters, digits (ending in `0`, as the HID run does), function keys, then
  /// the named keys.
  static Iterable<String> get labels => <String>[
    for (var index = 0; index < _letterRunLength; index += 1)
      String.fromCharCode(_upperA + index),
    for (var index = 0; index < _digitRunLength - 1; index += 1)
      String.fromCharCode(_digitOne + index),
    '0',
    for (var number = 1; number <= _functionRunLength; number += 1) 'F$number',
    ..._namedKeys.keys,
  ];

  // **There is no set of labels that binds the wrong key any more, and the
  // history stays here because it is a measured fact rather than a hunch.**
  //
  // Until phase 1 this file carried `labelsThatBindTheWrongKey` = `{Space, Tab,
  // Enter, F1, F2, F3, F4}`: seven labels the backend accepted and then bound
  // to a key nobody can press, so `X11GlobalHotkey` refused all seven before
  // touching it. The cause was entirely inside the removed vendor plugin.
  // `hotkey_manager` sent `hotKey.physicalKey.keyCode`, which `uni_platform`
  // resolved by scanning Flutter's `kGtkToLogicalKey` for the *first* entry
  // whose value was the logical key — and that table lists the keypad, ISO and
  // 3270 variants ahead of the ordinary ones, so `Space` became
  // `GDK_KEY_KP_Space`, `Tab` became `ISO_Left_Tab`, `Enter` became
  // `3270_Enter` and `F1`-`F4` became `KP_F1`-`KP_F4`.
  //
  // It was never X11's defect, nor keybinder's, nor GTK's. Measured three ways
  // on 2026-09-01 against the installed `libX11.so.6`, `libgdk-3.so.0` and
  // `libgtk-3.so.0`, plus a keycode round trip on a live `Xvfb`:
  // `XStringToKeysym("space")` -> 0x20, `"Tab"` -> 0xff09, `"Return"` ->
  // 0xff0d, `"F1"` -> 0xffbe, `"F4"` -> 0xffc1, and
  // `gtk_accelerator_parse("<Control><Shift>space")` -> keyval=0x0020. No
  // `KP_Space`, no `ISO_Left_Tab`, no `3270_Enter`, no `KP_F1`-`KP_F4`
  // anywhere.
  //
  // So with the plugin gone and `X11KeyGrabRegistrar` resolving keys by keysym
  // *name* through `XStringToKeysym`, all seven bind correctly: the table this
  // project could not see is no longer in the way. The set, its predicate and
  // the adapter's refusal branch were removed rather than left empty, because
  // an always-false predicate leaves branches that can never run (AGENTS.md
  // §1). DW-43 closes as resolved by this phase rather than being carried.
  //
  // **Not confirmed on a real X session.** The measurement is of the key *name*
  // resolution, which is the whole of what the old chain got wrong; that each
  // of the seven now grabs and fires under a real window manager is owed rather
  // than observed.

  /// The label [usbHidUsage] came from, or null when this catalogue does not
  /// produce it.
  ///
  /// The reverse of [usbHidUsageFor], and a *derivation* of the same table
  /// rather than a second one — a second table is a second thing to drift,
  /// which is the whole DW-41/DW-43 lesson. What a capture control has is the
  /// physical key's usage (`PhysicalKeyboardKey.usbHidUsage`), so this is the
  /// direction it needs; `X11KeyGrabRegistrar` needs the same answer to build a
  /// keysym name from a grab, and reads it here rather than keeping a private
  /// copy.
  static String? labelForUsage(int usbHidUsage) => _labelsByUsage[usbHidUsage];

  /// Whether [usbHidUsage] is one this catalogue produces.
  ///
  /// **No production caller.** Its only consumer was the removed
  /// `hotkey_manager` seam; the capture control asks [registrableKeys] instead,
  /// because a capture that is refused has to say *which* key it refused and so
  /// needs the label a bare predicate cannot give it. Kept because the
  /// binding-free gate reads it as the cheapest statement of what the table
  /// covers, and because it is now a view of the same map [labelForUsage]
  /// answers from rather than a second derivation of the labels.
  static bool carriesUsage(int usbHidUsage) =>
      _labelsByUsage.containsKey(usbHidUsage);

  /// This build's registrable vocabulary as a domain value, for the rings AD-1
  /// keeps this file out of.
  ///
  /// The composition root calls this and injects the result (see
  /// [RegistrableKeys]); nothing under `lib/src/application/` or `lib/src/ui/`
  /// may name this class at all.
  ///
  /// Each entry used to carry a portal half — [XdgShortcutTrigger]'s answer for
  /// the same label, so the two serializers stayed one vocabulary. That claim is
  /// still true and still load-bearing; it is simply no longer asserted by a
  /// field nothing could falsify. Plan 01-19 removed it because the flag was
  /// always true, which made the capture-time refusal reading it unreachable.
  /// The one-vocabulary invariant is asserted at build time instead:
  /// `hotkey_key_catalogue_test.dart` checks every label this table offers
  /// resolves through `XdgShortcutTrigger.keysymNameFor`, and
  /// `xdg_shortcut_trigger_test.dart`'s `parity with the X11 catalogue (AD-9)`
  /// group asserts the reverse direction and the same order. Same reason
  /// `X11KeyGrabRegistrar` asks that class for the keysym name instead of
  /// keeping a name table of its own.
  static RegistrableKeys registrableKeys() => RegistrableKeys([
    for (final MapEntry(key: usage, value: label) in _labelsByUsage.entries)
      RegistrableKey(usbHidUsage: usage, label: label),
  ]);

  /// Every usage [labels] produces, mapped back to the label that produced it.
  ///
  /// The `?` drops an entry the catalogue does not resolve, which it never does
  /// for its own [labels] — the marker is there so this stays total by
  /// construction rather than by that coincidence.
  static final Map<int, String> _labelsByUsage = <int, String>{
    for (final label in labels) ?usbHidUsageFor(label): label,
  };

  /// The lower-case name of each modifier.
  ///
  /// **No production caller as of phase 1**, like [carriesUsage]: this was the
  /// name the removed Linux plugin's `get_mods`
  /// compared against when it built a `GdkModifierType` mask, and it was also
  /// the name of `hotkey_manager`'s own `HotKeyModifier` value. Neither exists
  /// now. `X11KeyGrabRegistrar` maps a [HotkeyModifier] straight to an X core
  /// modifier mask, because X takes a bitmask and not a name. Retiring this
  /// belongs with the rest of this file's rework.
  ///
  /// An exhaustive `switch` with no default, so a fifth [HotkeyModifier] would
  /// not compile rather than silently serializing to nothing.
  static String modifierNameFor(HotkeyModifier modifier) => switch (modifier) {
    HotkeyModifier.control => 'control',
    HotkeyModifier.alt => 'alt',
    HotkeyModifier.shift => 'shift',
    HotkeyModifier.meta => 'meta',
  };

  static const int _upperA = 0x41;
  static const int _upperZ = 0x5a;
  static const int _digitZero = 0x30;
  static const int _digitOne = 0x31;
  static const int _digitNine = 0x39;

  static int? _letterUsage(String normalized) {
    if (normalized.length != 1) {
      return null;
    }
    final code = normalized.codeUnitAt(0);
    if (code < _upperA || code > _upperZ) {
      return null;
    }
    return _letterRunStart + code - _upperA;
  }

  static int? _digitUsage(String normalized) {
    if (normalized.length != 1) {
      return null;
    }
    final code = normalized.codeUnitAt(0);
    if (code < _digitZero || code > _digitNine) {
      return null;
    }
    // `0` is the last usage of the run, not the first: the run is 1..9 then 0.
    if (code == _digitZero) {
      return _digitRunStart + _digitRunLength - 1;
    }
    return _digitRunStart + code - _digitOne;
  }

  static int? _functionUsage(String normalized) {
    final match = _functionKey.firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return _functionRunStart + int.parse(match.group(1)!) - 1;
  }
}
