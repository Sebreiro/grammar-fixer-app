import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/xdg_shortcut_trigger.dart';
import 'package:test/test.dart';

/// AD-9's serialization for the X11 adapter, held to the numbers.
///
/// This is the suite that cannot be skipped. Every other guard on the grab path
/// is either a fake (which agrees with whatever the adapter does) or a mocked
/// channel (which agrees with whatever the catalogue produces): a usage shifted
/// by one still resolves to a real `PhysicalKeyboardKey`, still round-trips
/// through the plugin, and still registers — the wrong key. Only an explicit
/// assertion on the usage itself catches that, which is why the run starts and
/// ends are spelled out here rather than derived from the same constants the
/// implementation uses.
///
/// Pure Dart: no Flutter binding (AGENTS.md §7).
void main() {
  group('the key catalogue (AD-9)', () {
    test('AD-9: a letter resolves the same whatever its case — config is '
        'hand-edited and GTK lower-cases the accelerator anyway', () {
      expect(
        HotkeyKeyCatalogue.usbHidUsageFor('g'),
        HotkeyKeyCatalogue.usbHidUsageFor('G'),
      );
      expect(HotkeyKeyCatalogue.usbHidUsageFor('G'), 0x0007000a);
    });

    test('AD-9: surrounding whitespace is not part of the label', () {
      expect(HotkeyKeyCatalogue.usbHidUsageFor('  G  '), 0x0007000a);
      expect(HotkeyKeyCatalogue.usbHidUsageFor(' page up '), isNull);
      expect(HotkeyKeyCatalogue.usbHidUsageFor(' PageUp '), 0x0007004b);
    });

    test("AD-9: the letter run's ends are where HID puts them", () {
      expect(HotkeyKeyCatalogue.usbHidUsageFor('A'), 0x00070004);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('Z'), 0x0007001d);
    });

    test('AD-9: the digit run wraps — 0 sits at the end of it, not the '
        'start', () {
      expect(HotkeyKeyCatalogue.usbHidUsageFor('1'), 0x0007001e);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('9'), 0x00070026);
      expect(
        HotkeyKeyCatalogue.usbHidUsageFor('0'),
        0x00070027,
        reason:
            'HID orders the run 1..9 then 0; treating 0 as the first usage '
            'shifts every digit by one and binds the wrong key',
      );
    });

    test("AD-9: the function run's ends are where HID puts them", () {
      expect(HotkeyKeyCatalogue.usbHidUsageFor('F1'), 0x0007003a);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('F12'), 0x00070045);
    });

    test('AD-9: every named key resolves to its own usage', () {
      expect(HotkeyKeyCatalogue.usbHidUsageFor('Space'), 0x0007002c);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('Tab'), 0x0007002b);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('Enter'), 0x00070028);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('Escape'), 0x00070029);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('Backspace'), 0x0007002a);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('Insert'), 0x00070049);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('Delete'), 0x0007004c);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('Home'), 0x0007004a);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('End'), 0x0007004d);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('PageUp'), 0x0007004b);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('PageDown'), 0x0007004e);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('ArrowUp'), 0x00070052);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('ArrowDown'), 0x00070051);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('ArrowLeft'), 0x00070050);
      expect(HotkeyKeyCatalogue.usbHidUsageFor('ArrowRight'), 0x0007004f);
    });

    test('AD-12: anything else is null, which is what the adapter turns into '
        'HotkeyUnavailable without touching the backend', () {
      for (final label in const <String>[
        '',
        '  ',
        'Compose',
        'F25',
        'F0',
        'AA',
        'ctrl',
        'Page Up',
      ]) {
        expect(
          HotkeyKeyCatalogue.usbHidUsageFor(label),
          isNull,
          reason: '"$label" is not a key this build can register',
        );
      }
    });

    test('AD-9: no two labels share a usage', () {
      final labels = HotkeyKeyCatalogue.labels.toList();
      final usages = <int, String>{};
      final collisions = <String>[];

      for (final label in labels) {
        final usage = HotkeyKeyCatalogue.usbHidUsageFor(label);
        expect(usage, isNotNull, reason: '$label is offered but unresolvable');
        final owner = usages[usage!];
        if (owner != null) {
          collisions.add('$owner and $label both resolve to $usage');
        }
        usages[usage] = label;
      }

      expect(collisions, isEmpty);
      expect(
        labels,
        hasLength(26 + 10 + 12 + 15),
        reason:
            'the count is part of the claim: a run whose length drifted would '
            'otherwise leave the collision check passing over fewer keys',
      );
    });

    test('AD-9: every offered label survives a lower-case round trip', () {
      for (final label in HotkeyKeyCatalogue.labels) {
        expect(
          HotkeyKeyCatalogue.usbHidUsageFor(label.toLowerCase()),
          HotkeyKeyCatalogue.usbHidUsageFor(label),
          reason: 'config is hand-edited, so "$label" must survive any casing',
        );
      }
    });

    test('AD-9: carriesUsage accepts exactly what the catalogue produces', () {
      for (final label in HotkeyKeyCatalogue.labels) {
        expect(
          HotkeyKeyCatalogue.carriesUsage(
            HotkeyKeyCatalogue.usbHidUsageFor(label)!,
          ),
          isTrue,
        );
      }
      expect(
        HotkeyKeyCatalogue.carriesUsage(0x000700e0),
        isFalse,
        reason:
            'controlLeft is a real physical key and is not a shortcut key; the '
            'seam gates on this before it sends a keyval nothing checked',
      );
      expect(HotkeyKeyCatalogue.carriesUsage(0xdeadbeef), isFalse);
    });

    test('HOTKEY-04: the reverse lookup and the vocabulary are views of the '
        'one label table', () {
      // Re-pointed, not retired. This row used to pin
      // `labelsThatBindTheWrongKey` by literal value, because everything else
      // that touched the set derived from it — the adapter's refusal iterated
      // it, so a shrunken set was a shorter loop rather than a failure. That
      // set is gone: it was an artefact of the removed vendor plugin's own
      // reverse-lookup table, and with keys resolved by keysym name all seven
      // of its labels bind correctly (see the catalogue's own doc for the
      // measurement).
      //
      // What replaces it is the same *kind* of claim about what replaced the
      // set: the usage-to-label direction the capture control reads, and the
      // vocabulary the composition root injects, are both derivations of
      // `labels` rather than second tables. A second table is a second thing
      // to drift, which is the whole DW-41/DW-43 lesson, and a derivation that
      // silently stopped covering a label would leave a key the settings
      // screen refuses and the adapter accepts.
      for (final label in HotkeyKeyCatalogue.labels) {
        final usage = HotkeyKeyCatalogue.usbHidUsageFor(label);
        expect(usage, isNotNull);
        expect(
          HotkeyKeyCatalogue.labelForUsage(usage!),
          label,
          reason: 'the reverse lookup must answer with the label it came from',
        );
      }
      expect(
        HotkeyKeyCatalogue.labelForUsage(0x000700e0),
        isNull,
        reason:
            'controlLeft is a real physical key and no shortcut key, so a '
            'capture that pressed it has no label to offer',
      );

      final vocabulary = HotkeyKeyCatalogue.registrableKeys();
      expect(
        vocabulary.all.map((key) => key.label),
        HotkeyKeyCatalogue.labels,
        reason:
            'the injected vocabulary is this table, in this order — a screen '
            'validating against a subset would refuse a key the adapter binds',
      );
      for (final key in vocabulary.all) {
        expect(vocabulary.forUsage(key.usbHidUsage)?.label, key.label);
      }

      final withoutKeysymName = [
        for (final key in vocabulary.all)
          if (XdgShortcutTrigger.keysymNameFor(key.label) == null) key.label,
      ];
      expect(
        withoutKeysymName,
        isEmpty,
        reason:
            'this assertion IS the guard that used to be a capture-time '
            'refusal. Plan 01-19 deleted the portal-trigger flag on '
            'RegistrableKey and the fifth HotkeyCaptureRefusal value that read '
            'it, because the flag was true for every key the catalogue can '
            'produce, so that refusal could never fire. The invariant it stood '
            'for is real, and it is checked here instead — against '
            'registrableKeys(), the vocabulary the composition root actually '
            'injects — so a divergence fails the build in front of the '
            'developer who caused it rather than reaching a user as a sentence '
            'about a key they just pressed. The reverse direction (a label '
            'this table lacks) and the same-order claim are asserted by '
            "xdg_shortcut_trigger_test.dart's 'parity with the X11 catalogue "
            "(AD-9)' group",
      );
    });
  });

  group('the modifier mapping (AD-9)', () {
    test('AD-9: the mapping is total over HotkeyModifier.values', () {
      expect(
        {
          for (final modifier in HotkeyModifier.values)
            modifier: HotkeyKeyCatalogue.modifierNameFor(modifier),
        },
        {
          HotkeyModifier.control: 'control',
          HotkeyModifier.alt: 'alt',
          HotkeyModifier.shift: 'shift',
          HotkeyModifier.meta: 'meta',
        },
        reason:
            'these are the names the Linux plugin get_mods compares against, '
            'and they are also hotkey_manager HotKeyModifier value names — a '
            'fifth HotkeyModifier would not compile against the exhaustive '
            'switch rather than serializing to nothing',
      );
    });

    test('AD-9: no two modifiers share a name', () {
      expect(
        HotkeyModifier.values.map(HotkeyKeyCatalogue.modifierNameFor).toSet(),
        hasLength(HotkeyModifier.values.length),
      );
    });
  });
}
