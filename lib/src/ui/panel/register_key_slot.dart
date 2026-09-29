/// AD-6's key slot, derived from a register's position and nothing else.
///
/// `SuggestionRegister.values.indexOf(r) + 1` is both the selecting key and the
/// panel's top-to-bottom order, so the hint a card prints and the activator the
/// panel listens for have to come from one derivation — two copies of it are
/// two chances for the card to promise a key that selects a different row.
///
/// The keyboard's digit row runs out at 9. A register past that gets no key
/// and no hint, rather than a wrong one: the honest degradation for an enum
/// that outgrows the digits, and the reason both functions are written over an
/// index rather than over a register, since today's enum has three values and
/// the branch is otherwise unreachable by any test.
library;

import 'package:flutter/services.dart';

/// The highest index the digit row can express.
const int _lastDigitIndex = 8;

/// The `1`/`2`/`3` label for the register at [index], or null past the digit
/// row.
String? keySlotHintForIndex(int index) {
  if (index < 0 || index > _lastDigitIndex) {
    return null;
  }
  return '${index + 1}';
}

/// The digit key that selects the register at [index], or null past the digit
/// row.
///
/// The logical key ids of `digit1`..`digit9` are the characters `'1'`..`'9'`,
/// so the key for [index] is one arithmetic step from `digit1`.
LogicalKeyboardKey? digitKeyForIndex(int index) {
  if (index < 0 || index > _lastDigitIndex) {
    return null;
  }
  return LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + index);
}

/// The numeric-keypad key that selects the register at [index], or null past
/// the digit row.
///
/// The same arithmetic holds here, and it was checked rather than assumed:
/// `numpad1`..`numpad9` are `0x00200000231`..`0x00200000239` in
/// `keyboard_key.g.dart`, contiguous exactly as `digit1`..`digit9` are.
///
/// It is a *second* activator for the same slot, not a replacement: a keypad
/// only reports these logical keys while Num Lock is on, so the digit row stays
/// the key AD-6 names and this is the one a user with a keypad expects to work
/// too. Nothing about AD-6's mapping changes — both come from [index].
LogicalKeyboardKey? numpadKeyForIndex(int index) {
  if (index < 0 || index > _lastDigitIndex) {
    return null;
  }
  return LogicalKeyboardKey(LogicalKeyboardKey.numpad1.keyId + index);
}
