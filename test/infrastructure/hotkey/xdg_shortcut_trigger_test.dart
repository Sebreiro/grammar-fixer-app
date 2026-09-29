import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/xdg_shortcut_trigger.dart';
import 'package:test/test.dart';

/// AD-9's serialization for the Wayland adapter, held to totality.
///
/// Every keysym name asserted here was measured with `xkb_keysym_from_name`
/// against the installed xkbcommon 1.6.0, which is what makes the four
/// substitutions below facts rather than guesses: `Space`, `Enter`, `Backspace`
/// and `ArrowUp` — four of the fifteen named labels this app offers — are
/// `NoSymbol` as spelled, so passing the label through would put a name the
/// compositor cannot parse into `preferred_trigger`. Because the trigger is a
/// *hint* the portal may ignore, the symptom would be a shortcut silently bound
/// to something else, not an error.
///
/// Pure Dart: no Flutter binding, no D-Bus (AGENTS.md §7).
void main() {
  group('modifiers (AD-9)', () {
    test('AD-9: every HotkeyModifier maps to a keyword the shortcuts '
        'specification defines', () {
      expect(
        {
          for (final modifier in HotkeyModifier.values)
            modifier: XdgShortcutTrigger.modifierKeywordFor(modifier),
        },
        {
          HotkeyModifier.control: 'CTRL',
          HotkeyModifier.alt: 'ALT',
          HotkeyModifier.shift: 'SHIFT',
          // Not META and not SUPER: the specification's set is
          // CTRL/ALT/SHIFT/NUM/LOGO "as defined as XKB_MOD_NAME_*", and the
          // installed xkbcommon-names.h gives XKB_MOD_NAME_LOGO = "Mod4",
          // which is the modifier a Linux Super key produces.
          HotkeyModifier.meta: 'LOGO',
        },
        reason:
            'the mapping is an exhaustive switch, so a fifth modifier fails to '
            'compile rather than serializing to nothing — this row is what '
            'says the four that exist are right',
      );
    });

    test('AD-9: modifier order is fixed, whatever order the set was built '
        'in', () {
      // The binding arrives from a hand-editable config file, so the iteration
      // order of its Set is not something this app controls. Two spellings of
      // one combination would be two different strings to compare or log.
      final ascending = HotkeyBinding(
        modifiers: {
          HotkeyModifier.control,
          HotkeyModifier.alt,
          HotkeyModifier.shift,
          HotkeyModifier.meta,
        },
        key: 'G',
      );
      final descending = HotkeyBinding(
        modifiers: {
          HotkeyModifier.meta,
          HotkeyModifier.shift,
          HotkeyModifier.alt,
          HotkeyModifier.control,
        },
        key: 'G',
      );

      expect(XdgShortcutTrigger.forBinding(ascending), 'CTRL+ALT+SHIFT+LOGO+g');
      expect(
        XdgShortcutTrigger.forBinding(descending),
        XdgShortcutTrigger.forBinding(ascending),
      );
    });

    test('AD-9: a bare key carries no leading separator', () {
      expect(
        XdgShortcutTrigger.forBinding(HotkeyBinding(modifiers: {}, key: 'F12')),
        'F12',
        reason:
            'an empty modifier set is legal config, and "+F12" is not a trigger '
            'the specification defines',
      );
    });
  });

  group('keys (AD-9)', () {
    test(
      'AD-9: letters fold to lower case, so Ctrl+Shift+G is CTRL+SHIFT+g',
      () {
        // AD-9's own illustration, and correct rather than cosmetic: G is keysym
        // 0x47 and g is 0x67 — two different keysyms — while the app offers one
        // label for the key. The shortcuts specification's own example
        // lower-cases the key even under SHIFT.
        expect(
          XdgShortcutTrigger.forBinding(
            HotkeyBinding(
              modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
              key: 'G',
            ),
          ),
          'CTRL+SHIFT+g',
        );
        expect(XdgShortcutTrigger.keysymNameFor('G'), 'g');
        expect(XdgShortcutTrigger.keysymNameFor('g'), 'g');
      },
    );

    test('AD-9: digits are themselves', () {
      expect(
        {
          for (final label in ['1', '9', '0'])
            label: XdgShortcutTrigger.keysymNameFor(label),
        },
        {'1': '1', '9': '9', '0': '0'},
      );
    });

    test('AD-9: function keys are themselves', () {
      expect(
        {
          for (final label in ['F1', 'F12'])
            label: XdgShortcutTrigger.keysymNameFor(label),
        },
        {'F1': 'F1', 'F12': 'F12'},
      );
    });

    test('AD-9: the fifteen named labels resolve to the keysym names measured '
        'against xkbcommon, four of which are not the label', () {
      expect(
        {
          for (final label in const [
            'Space',
            'Tab',
            'Enter',
            'Escape',
            'Backspace',
            'Insert',
            'Delete',
            'Home',
            'End',
            'PageUp',
            'PageDown',
            'ArrowUp',
            'ArrowDown',
            'ArrowLeft',
            'ArrowRight',
          ])
            label: XdgShortcutTrigger.keysymNameFor(label),
        },
        {
          // `Space` is NoSymbol; the keysym is ASCII space, named lower case.
          'Space': 'space',
          'Tab': 'Tab',
          // `Enter` is NoSymbol.
          'Enter': 'Return',
          'Escape': 'Escape',
          // The capital S is not optional; `Backspace` is NoSymbol.
          'Backspace': 'BackSpace',
          'Insert': 'Insert',
          'Delete': 'Delete',
          'Home': 'Home',
          'End': 'End',
          // `Page_Up`/`Page_Down` do resolve, but canonicalize back to these.
          'PageUp': 'Prior',
          'PageDown': 'Next',
          // The `Arrow` prefix is Flutter's vocabulary, not X's; `ArrowUp` is
          // NoSymbol.
          'ArrowUp': 'Up',
          'ArrowDown': 'Down',
          'ArrowLeft': 'Left',
          'ArrowRight': 'Right',
        },
        reason:
            'this table exists because four of these labels are not keysym '
            'names, and preferred_trigger is a hint — an unparseable one is '
            'ignored silently rather than refused',
      );
    });

    test('AD-9: lookup trims and is case-insensitive, like the config it '
        'reads', () {
      expect(XdgShortcutTrigger.keysymNameFor('  space  '), 'space');
      expect(XdgShortcutTrigger.keysymNameFor('pageup'), 'Prior');
      expect(XdgShortcutTrigger.keysymNameFor('f7'), 'F7');
    });

    test('AD-9: anything this build does not offer resolves to null, which the '
        'adapter turns into an omitted preferred_trigger', () {
      for (final label in const ['', '  ', 'Compose', 'F25', 'AA']) {
        expect(
          XdgShortcutTrigger.keysymNameFor(label),
          isNull,
          reason:
              'the table is a whitelist of the labels this build offers, not a '
              'wrapper over xkbcommon — F25 is a real keysym (0xffd6, measured) '
              'that HotkeyKeyCatalogue cannot register, and the same config '
              'file must mean the same thing on both display servers',
        );
        expect(
          XdgShortcutTrigger.forBinding(
            HotkeyBinding(
              modifiers: const {HotkeyModifier.control},
              key: label,
            ),
          ),
          isNull,
          reason: 'a whole binding is unrepresentable when its key is',
        );
      }
    });
  });

  /// What these rows prove, stated exactly: **the two halves of AD-9 serialize
  /// one catalogue of key labels**, in both directions and in the same order.
  ///
  /// They used to carry a caveat that no longer holds: seven of the sixty-three
  /// labels — `Space`, `Tab`, `Enter` and `F1`-`F4` — were refused by
  /// `X11GlobalHotkey` before the backend was touched, because the removed
  /// vendor chain grabbed a keypad, ISO or 3270 variant of each, so `Alt+Space`
  /// was a working Wayland shortcut and a refused X11 one from the same config
  /// file. That divergence left the tree with the plugin (see
  /// `HotkeyKeyCatalogue` for the measurement), and the parity these rows
  /// assert is now parity of the *whole* vocabulary rather than of everything
  /// except seven exceptions.
  group('parity with the X11 catalogue (AD-9)', () {
    test('AD-9: every key label the X11 catalogue offers has a Wayland '
        'serialization', () {
      final unresolvable = [
        for (final label in HotkeyKeyCatalogue.labels)
          if (XdgShortcutTrigger.keysymNameFor(label) == null) label,
      ];

      expect(
        unresolvable,
        isEmpty,
        reason:
            'the two serializers must offer one catalogue: a label the config '
            'layer is allowed to hold and this side cannot express would reach '
            'the portal with no preferred_trigger at all, silently',
      );
    });

    test('AD-9: and this table offers no label the X11 catalogue lacks', () {
      final unknownToX11 = [
        for (final label in XdgShortcutTrigger.labels)
          if (HotkeyKeyCatalogue.usbHidUsageFor(label) == null) label,
      ];

      expect(
        unknownToX11,
        isEmpty,
        reason:
            'the other direction, and it matters as much: a label offered here '
            'and not there is a key a settings screen could offer on one '
            'display server and not the other',
      );
      expect(
        XdgShortcutTrigger.labels,
        HotkeyKeyCatalogue.labels,
        reason:
            'same labels, same order — the two halves of AD-9 serialize one '
            'catalogue of keys',
      );
    });

    test('AD-9: the seven labels the old vendor chain bound to the wrong key '
        'are expressible on both display servers now', () {
      // Re-pointed, not retired: the subject was
      // `HotkeyKeyCatalogue.labelsThatBindTheWrongKey`, which is gone, so the
      // seven are named here as the literals they were. They are still the
      // interesting labels — they are the ones a regression would break first,
      // and they are what DW-43 is closed on — but the claim has changed from
      // "the two servers diverge on exactly these" to "these bind on both, so
      // nothing diverges". Keeping them by name is what makes a future keysym
      // table that dropped one fail here rather than silently.
      expect(
        {
          for (final label in const [
            'Space',
            'Tab',
            'Enter',
            'F1',
            'F2',
            'F3',
            'F4',
          ])
            label: XdgShortcutTrigger.keysymNameFor(label),
        },
        {
          'Space': 'space',
          'Tab': 'Tab',
          'Enter': 'Return',
          'F1': 'F1',
          'F2': 'F2',
          'F3': 'F3',
          'F4': 'F4',
        },
        reason:
            'the labels the vendor chain resolved to KP_Space, ISO_Left_Tab, '
            '3270_Enter and KP_F1-KP_F4 must all still have ordinary keysym '
            'names on this side',
      );
      for (final label in const ['Space', 'Tab', 'Enter', 'F1', 'F4']) {
        expect(
          HotkeyKeyCatalogue.usbHidUsageFor(label),
          isNotNull,
          reason:
              'and the X11 side must still offer them, or the parity above is '
              'about a key only one server has',
        );
      }
      expect(
        XdgShortcutTrigger.forBinding(
          HotkeyBinding(modifiers: {HotkeyModifier.alt}, key: 'Space'),
        ),
        'ALT+space',
        reason:
            'the combination the old chain got wrong, expressed correctly here '
            '— which is why the adapter suite used it as its second binding',
      );
    });

    test('AD-9: no two labels serialize to the same keysym name', () {
      final names = [
        for (final label in XdgShortcutTrigger.labels)
          XdgShortcutTrigger.keysymNameFor(label)!,
      ];

      expect(
        names.toSet(),
        hasLength(names.length),
        reason:
            'a collision would let two configured keys request the same '
            'trigger, and the compositor would have no way to tell them apart',
      );
      expect(names, hasLength(63));
    });
  });
}
