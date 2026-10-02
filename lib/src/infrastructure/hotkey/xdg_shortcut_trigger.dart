import '../../domain/hotkey/hotkey_binding.dart';

/// AD-9's serialization for the Wayland adapter: a [HotkeyBinding] turned into
/// the `preferred_trigger` string the XDG shortcuts specification defines.
///
/// The syntax is fixed by the freedesktop shortcuts specification: modifier
/// keywords out of `CTRL, ALT, SHIFT, NUM, LOGO` — "as defined as
/// `XKB_MOD_NAME_*`" — joined to the key by `+`, with the key an identifier
/// "taken from `xkbcommon-keysyms.h` without the `XKB_KEY_*` prefix". Its own
/// examples are `CTRL+a`, `CTRL+SHIFT+a` and `CTRL+ALT+Return`, which is where
/// two of the rules below come from: the key is lower-cased even under `SHIFT`,
/// and the key name is a **keysym name**, not a label.
///
/// That last point is the whole reason this type exists rather than the key
/// label being passed through. Several of the named labels this app offers
/// are not keysym names at all. Measured here by calling
/// `xkb_keysym_from_name` against the installed xkbcommon 1.6.0:
/// `Space`, `Enter`, `Backspace` and `ArrowUp` all answer `NoSymbol`, while
/// `space`, `Return`, `BackSpace` and `Up` resolve. Passing the label through
/// would put a name the compositor cannot parse in the request — and because
/// `preferred_trigger` is a *hint* the portal is free to ignore, the symptom
/// would be a shortcut silently bound to something else rather than an error.
///
/// It is deliberately a **whitelist keyed off the labels this build offers**,
/// not a wrapper over xkbcommon: `F25` is a perfectly real keysym (0xffd6,
/// measured) that `HotkeyKeyCatalogue` cannot register on X11, and a config
/// naming it must resolve to the same "this build does not offer that key" on
/// both display servers. `XdgShortcutTrigger.labels` is held equal to
/// `HotkeyKeyCatalogue.labels` by a test, in both directions, because a
/// combination that binds on X11 has to be expressible as a Wayland preference
/// or the same config file stops meaning the same thing across sessions.
///
/// Pure Dart, and pure decision-making: nothing here touches D-Bus. That is
/// what lets the whole table be held to totality in the binding-free test set,
/// the same division of labour `HotkeyKeyCatalogue` has on the X11 side.
final class XdgShortcutTrigger {
  const XdgShortcutTrigger._();

  /// The `preferred_trigger` for [binding], or null when this build cannot
  /// express it.
  ///
  /// A null is **not** a refusal. `WaylandPortalGlobalHotkey` omits the key
  /// from the shortcut vardict and carries on, because the compositor and the
  /// user pick the combination under the portal and the trigger is only a hint;
  /// see that class for why this is the opposite of the X11 adapter's answer to
  /// the same question.
  static String? forBinding(HotkeyBinding binding) {
    final keysymName = keysymNameFor(binding.key);
    if (keysymName == null) {
      return null;
    }
    return [
      // Fixed order, independent of the set's iteration order: the request is
      // built from a `Set` the config layer populates, and two spellings of one
      // combination would be two different strings to compare or log.
      for (final modifier in _modifierOrder)
        if (binding.modifiers.contains(modifier)) modifierKeywordFor(modifier),
      keysymName,
    ].join('+');
  }

  /// The keysym name [label] serializes to, or null when this build does not
  /// offer that key.
  ///
  /// Trims, because the binding is hand-editable config (AD-13), and folds
  /// letters to lower case, because `G` (0x47) and `g` (0x67) are two different
  /// keysyms while the app offers only one label for the key.
  static String? keysymNameFor(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final normalized = trimmed.toUpperCase();
    return _letterKeysymName(normalized) ??
        _digitKeysymName(normalized) ??
        _functionKeysymName(normalized) ??
        _namedKeysymNamesByUpperCase[normalized];
  }

  /// The modifier keyword the shortcuts specification defines for [modifier].
  ///
  /// An exhaustive `switch` with no default, so a fifth [HotkeyModifier] fails
  /// to compile rather than serializing to nothing.
  ///
  /// `meta` maps to `LOGO`, and on this adapter that is unambiguous rather than
  /// a guess: the specification's modifier set has no `META` or `SUPER`, and the
  /// installed `xkbcommon-names.h` gives `XKB_MOD_NAME_LOGO = "Mod4"` (measured
  /// here) — the modifier a Linux Super key actually produces. Worth saying
  /// because it is the *opposite* of the X11 side, where the same enum value
  /// reaches keybinder as GDK's virtual `GDK_META_MASK` rather than Mod4, and
  /// is filed in the deferred-work ledger as an open, unmeasurable question.
  static String modifierKeywordFor(HotkeyModifier modifier) =>
      switch (modifier) {
        HotkeyModifier.control => 'CTRL',
        HotkeyModifier.alt => 'ALT',
        HotkeyModifier.shift => 'SHIFT',
        HotkeyModifier.meta => 'LOGO',
      };

  /// Every label this type serializes, in the order `HotkeyKeyCatalogue`
  /// offers them: letters, digits (ending in `0`, as its HID run does),
  /// function keys, then the named keys.
  static Iterable<String> get labels => <String>[
    for (var index = 0; index < _letterCount; index += 1)
      String.fromCharCode(_upperA + index),
    for (var digit = 1; digit <= 9; digit += 1) '$digit',
    '0',
    for (var number = 1; number <= _functionKeyCount; number += 1) 'F$number',
    ..._namedKeysymNames.keys,
  ];

  /// The order the specification's own examples use — `CTRL+SHIFT+a`, never
  /// `SHIFT+CTRL+a`. `NUM` is absent because [HotkeyModifier] has no counterpart
  /// for it and this app offers no keypad keys.
  static const List<HotkeyModifier> _modifierOrder = <HotkeyModifier>[
    HotkeyModifier.control,
    HotkeyModifier.alt,
    HotkeyModifier.shift,
    HotkeyModifier.meta,
  ];

  /// The labels that are not a letter, a digit or a function key,
  /// mapped to the keysym name each one actually is.
  ///
  /// Every value was measured with `xkb_keysym_from_name` against xkbcommon
  /// 1.6.0 in this container. Examples of why the map exists:
  ///
  /// * `Space` → `space`. The capitalised form is `NoSymbol`; the keysym is the
  ///   ASCII space, whose canonical name is lower case.
  /// * `Enter` → `Return`. `Enter` is `NoSymbol`. (`KP_Enter` is the keypad
  ///   key, which this build does not offer.)
  /// * `Backspace` → `BackSpace`. The capital `S` is not optional: the
  ///   lower-cased spelling is `NoSymbol`.
  /// * `ArrowUp`/`Down`/`Left`/`Right` → `Up`/`Down`/`Left`/`Right`. The
  ///   `Arrow` prefix is Flutter's logical-key vocabulary, not X's.
  ///
  /// `PageUp`/`PageDown` are the subtler pair. `Page_Up` and `Page_Down` do
  /// resolve, but they are aliases: both canonicalize back through
  /// `xkb_keysym_get_name` to `Prior` and `Next`, which is what a compositor
  /// echoing the trigger will show. The canonical names are used so the request
  /// and any read-back agree.
  static const Map<String, String> _namedKeysymNames = <String, String>{
    'Space': 'space',
    'Tab': 'Tab',
    'Enter': 'Return',
    'Escape': 'Escape',
    'Backspace': 'BackSpace',
    'Insert': 'Insert',
    'Delete': 'Delete',
    'Home': 'Home',
    'End': 'End',
    'PageUp': 'Prior',
    'PageDown': 'Next',
    'ArrowUp': 'Up',
    'ArrowDown': 'Down',
    'ArrowLeft': 'Left',
    'ArrowRight': 'Right',
    'Minus': 'minus',
    'Equal': 'equal',
    'BracketLeft': 'bracketleft',
    'BracketRight': 'bracketright',
    'Backslash': 'backslash',
    'Semicolon': 'semicolon',
    'Quote': 'apostrophe',
    // Shift stays in the modifier set; a shifted character is not a new key.
    'Backquote': 'grave',
    'Comma': 'comma',
    'Period': 'period',
    'Slash': 'slash',
  };

  static final Map<String, String> _namedKeysymNamesByUpperCase =
      <String, String>{
        for (final MapEntry(:key, :value) in _namedKeysymNames.entries)
          key.toUpperCase(): value,
      };

  /// F1 through F12 only — the same run `HotkeyKeyCatalogue` offers. Higher
  /// function keys are real keysyms and are still not offered; see the class
  /// doc.
  static final RegExp _functionKey = RegExp(r'^F([1-9]|1[0-2])$');

  static const int _letterCount = 26;
  static const int _functionKeyCount = 12;
  static const int _upperA = 0x41;
  static const int _upperZ = 0x5a;
  static const int _digitZero = 0x30;
  static const int _digitNine = 0x39;

  static String? _letterKeysymName(String normalized) {
    if (normalized.length != 1) {
      return null;
    }
    final code = normalized.codeUnitAt(0);
    if (code < _upperA || code > _upperZ) {
      return null;
    }
    return normalized.toLowerCase();
  }

  static String? _digitKeysymName(String normalized) {
    if (normalized.length != 1) {
      return null;
    }
    final code = normalized.codeUnitAt(0);
    if (code < _digitZero || code > _digitNine) {
      return null;
    }
    return normalized;
  }

  static String? _functionKeysymName(String normalized) =>
      _functionKey.hasMatch(normalized) ? normalized : null;
}
