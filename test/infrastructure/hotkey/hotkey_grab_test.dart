import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_grab.dart';
import 'package:test/test.dart';

/// The value that crosses the `HotkeyRegistrar` seam.
///
/// Equality here is load-bearing rather than decorative: every "the seam was
/// asked for exactly this" assertion in the adapter suite compares two
/// `HotkeyGrab`s, and a type that compared by identity would make all of them
/// pass vacuously — the lesson `TrayMenuEntry` cost story 6 a review pass.
///
/// Pure Dart: no Flutter binding (AGENTS.md §7).
void main() {
  test('AD-9: two grabs with the same key and the same modifiers are equal '
      'however the set was built', () {
    final ordered = HotkeyGrab(
      modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
      usbHidUsage: 0x0007000a,
    );
    final reversed = HotkeyGrab(
      modifiers: {HotkeyModifier.shift, HotkeyModifier.control},
      usbHidUsage: 0x0007000a,
    );

    expect(ordered, reversed);
    expect(
      ordered.hashCode,
      reversed.hashCode,
      reason:
          'a hash that disagreed with == would put two equal grabs in '
          'different buckets of every Set and Map keyed by one',
    );
  });

  test('AD-9: a different key or a different modifier set is a different '
      'grab', () {
    final base = HotkeyGrab(
      modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
      usbHidUsage: 0x0007000a,
    );

    expect(
      base,
      isNot(
        HotkeyGrab(
          modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
          usbHidUsage: 0x0007002c,
        ),
      ),
    );
    expect(
      base,
      isNot(
        HotkeyGrab(
          modifiers: {HotkeyModifier.control},
          usbHidUsage: 0x0007000a,
        ),
      ),
    );
  });

  test('AD-9: the modifier set is copied, so a caller mutating what it passed '
      'in cannot change a grab already recorded', () {
    final requested = <HotkeyModifier>{HotkeyModifier.control};
    final grab = HotkeyGrab(modifiers: requested, usbHidUsage: 0x0007000a);
    final asRequested = HotkeyGrab(
      modifiers: {HotkeyModifier.control},
      usbHidUsage: 0x0007000a,
    );

    requested.add(HotkeyModifier.meta);

    expect(
      grab,
      asRequested,
      reason:
          'held by reference, this grab would silently become Ctrl+Meta+G '
          'after the fact — and the fake records grabs in a list that a row '
          'compares against later',
    );
    expect(grab.modifiers, {HotkeyModifier.control});
  });

  test('AD-9: the copy is unmodifiable, so nothing downstream can mutate a '
      'grab in flight', () {
    final grab = HotkeyGrab(
      modifiers: {HotkeyModifier.control},
      usbHidUsage: 0x0007000a,
    );

    expect(
      () => grab.modifiers.add(HotkeyModifier.meta),
      throwsUnsupportedError,
    );
  });

  test('AD-9: toString renders the combination, so a failed comparison names '
      'two different grabs rather than two identical instances', () {
    expect(
      HotkeyGrab(
        modifiers: {HotkeyModifier.shift, HotkeyModifier.control},
        usbHidUsage: 0x0007000a,
      ).toString(),
      'HotkeyGrab(control+shift 0x0007000a)',
    );
  });
}
