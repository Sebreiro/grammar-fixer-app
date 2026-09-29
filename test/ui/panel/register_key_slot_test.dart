import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/register_key_slot.dart';

/// AD-6's key slot, at and past the edge of the digit row.
///
/// The panel tests cover the three registers that exist; these cover the
/// derivation itself, which is the only way to reach the degradation an enum
/// with more than nine registers would take — `SuggestionRegister` is AD-2
/// verbatim and cannot be extended to reach it.
void main() {
  test('AD-6: the slot hint and the digit key agree for every register that '
      'exists today', () {
    for (final register in SuggestionRegister.values) {
      final index = SuggestionRegister.values.indexOf(register);
      expect(keySlotHintForIndex(index), equals('${index + 1}'));
      expect(
        digitKeyForIndex(index),
        equals(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + index)),
      );
    }
  });

  test('AD-6: index 8 is the last slot the digit row can express', () {
    expect(keySlotHintForIndex(8), equals('9'));
    expect(digitKeyForIndex(8), equals(LogicalKeyboardKey.digit9));
  });

  test('AD-6: the keypad key for a slot is the same slot, so a keypad selects '
      'the row its hint names', () {
    for (final register in SuggestionRegister.values) {
      final index = SuggestionRegister.values.indexOf(register);
      expect(
        numpadKeyForIndex(index),
        equals(LogicalKeyboardKey(LogicalKeyboardKey.numpad1.keyId + index)),
      );
    }
    // Checked rather than assumed, because the whole derivation rests on it:
    // `numpad1`..`numpad9` are as contiguous as `digit1`..`digit9`.
    expect(numpadKeyForIndex(0), equals(LogicalKeyboardKey.numpad1));
    expect(numpadKeyForIndex(1), equals(LogicalKeyboardKey.numpad2));
    expect(numpadKeyForIndex(8), equals(LogicalKeyboardKey.numpad9));
  });

  test('AD-6: the keypad runs out where the digit row does', () {
    expect(numpadKeyForIndex(9), isNull);
    expect(numpadKeyForIndex(-1), isNull);
  });

  test('AD-6: a register past the digit row gets no key and no hint, rather '
      'than a wrong one', () {
    expect(keySlotHintForIndex(9), isNull);
    expect(digitKeyForIndex(9), isNull);
  });

  test('AD-6: a register that is not in the enum has no slot at all', () {
    // `indexOf` answers -1 for a register the enum does not carry, which is
    // what both call sites hand in.
    expect(keySlotHintForIndex(-1), isNull);
    expect(digitKeyForIndex(-1), isNull);
  });
}
