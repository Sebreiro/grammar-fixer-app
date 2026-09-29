import '../domain/hotkey/hotkey_binding.dart';
import '../domain/hotkey/registrable_keys.dart';

/// What the user pressed, reduced to values no ring above `domain` has to
/// translate (D-14).
///
/// The capture control reads Flutter key events, which the application ring may
/// not name — AD-1 makes a `package:flutter/` import a violation here, not just
/// in `ui`. So the widget does the one job only it can do (turn a `KeyEvent` and
/// `HardwareKeyboard.instance.logicalKeysPressed` into these four values) and
/// the decision about whether the combination can be registered is made here,
/// where it is a pure predicate testable without a binding.
final class HotkeyCapture {
  const HotkeyCapture({
    required this.modifiers,
    required this.usbHidUsage,
    required this.keyIsModifier,
    required this.usesLevelThreeModifier,
  });

  /// The modifiers held at the moment the key went down.
  final Set<HotkeyModifier> modifiers;

  /// The physical key that went down, as `PhysicalKeyboardKey.usbHidUsage`
  /// reports it — the integer `RegistrableKeys` is keyed on.
  final int usbHidUsage;

  /// Whether the key that went down is itself a modifier.
  ///
  /// A fact only the ui ring can establish, because the modifier keys are named
  /// by Flutter's `LogicalKeyboardKey`, and it has to be carried rather than
  /// inferred: a modifier's own usage is outside the catalogue, so without this
  /// flag pressing `Ctrl` would be refused as "not a key this build can
  /// register" — a true sentence about the wrong thing, when what is actually
  /// happening is that the user is halfway through pressing their combination.
  final bool keyIsModifier;

  /// Whether the combination uses AltGr / Level 3.
  ///
  /// The predicate is the ui ring's, and the one it uses is the **logical** key:
  /// `LogicalKeyboardKey.altGraph` among the keys pressed. Not the physical
  /// `PhysicalKeyboardKey.altRight`, which is AltGr only on a layout that maps
  /// Level 3 to it and is an ordinary right Alt everywhere else — keying on the
  /// physical key would refuse a legitimate `Alt` combination on a US layout.
  ///
  /// That the GTK embedder does report AltGr as `altGraph` is measured, not
  /// assumed — this was flagged assumption A3, and it was settled by watching
  /// the refusal render on a live GTK session: the 01-07 run on 2026-09-02, and
  /// again by UAT test 9 on 2026-09-04 under an `altgr-intl` layout, where
  /// AltGr and AltGr+E each produced the Level 3 refusal and the stored
  /// shortcut was left as it was rather than folded into Alt. Both observations
  /// drove the keys with XTEST rather than a physical keyboard, and that is
  /// sufficient here rather than a caveat: the predicate reads a GTK/Flutter
  /// keymap translation, which cannot tell an injected event from a switch
  /// closing. `settings_screen_hotkey_test.dart`'s AltGr row pins it now.
  ///
  /// Refusing is the right answer rather than folding because `HotkeyModifier`
  /// has four values and none of them is Level 3 — so if the mapping ever
  /// changed, the predicate is what would have to change, not the refusal.
  final bool usesLevelThreeModifier;
}

/// Why a captured combination was refused (D-15). One value per subject, so the
/// surface renders one reason per cause rather than a single "invalid".
enum HotkeyCaptureRefusal {
  /// AltGr / `ISO_Level3_Shift`, which no `HotkeyModifier` can express.
  levelThreeModifier,

  /// Only modifiers were held; there is no key to grab yet.
  modifierOnly,

  /// No modifier at all (D-13).
  noModifier,

  /// A key outside this build's vocabulary.
  keyNotRegistrable,
}

/// The answer to "can this combination be saved?" (D-15).
sealed class HotkeyCaptureVerdict {
  const HotkeyCaptureVerdict();
}

/// The combination can be requested, as [binding].
final class HotkeyCaptureAccepted extends HotkeyCaptureVerdict {
  const HotkeyCaptureAccepted(this.binding);

  final HotkeyBinding binding;
}

/// The combination is refused, and [reason] is the sentence the user reads.
///
/// A refusal keeps whatever shortcut was already in effect: the point of
/// deciding at capture rather than at Apply is that the user never saves
/// something broken and never waits for a bind to tell them so.
final class HotkeyCaptureRefused extends HotkeyCaptureVerdict {
  const HotkeyCaptureRefused({required this.refusal, required this.reason});

  final HotkeyCaptureRefusal refusal;

  /// User-facing, and one sentence per [HotkeyCaptureRefusal] — a shared
  /// "that combination will not work" would tell the user nothing they can act
  /// on, which is the whole of what D-15 asks for beyond the refusal itself.
  final String reason;
}

/// Decides at capture time whether a combination this build cannot register is
/// being saved (D-13, D-15, HOTKEY-04).
///
/// **Not a replacement for the adapter's own check.** `X11GlobalHotkey._bind`
/// still refuses an unrepresentable key before the backend, because the binding
/// is hand-editable config (AD-13) and nothing forces a change through this
/// screen. This is the layer that stops the user *choosing* one.
final class HotkeyCaptureValidator {
  const HotkeyCaptureValidator(this._keys);

  /// Built at the composition root and injected — see [RegistrableKeys] for why
  /// the vocabulary cannot be reached for from this ring.
  final RegistrableKeys _keys;

  /// The verdict for [capture].
  ///
  /// The order of the branches is the order the reasons stop being true. Level 3
  /// comes first because an AltGr press carries no `HotkeyModifier` at all, so
  /// every later branch would describe it as "no modifier" — the right refusal
  /// with the wrong cause, and the user would go on to press AltGr with a
  /// modifier and be told the same untrue thing.
  HotkeyCaptureVerdict verdictFor(HotkeyCapture capture) {
    if (capture.usesLevelThreeModifier) {
      return const HotkeyCaptureRefused(
        refusal: HotkeyCaptureRefusal.levelThreeModifier,
        reason:
            'AltGr cannot be part of a shortcut here — a shortcut carries '
            'Ctrl, Alt, Shift or Super, and AltGr is none of them. Hold one of '
            'those instead.',
      );
    }
    if (capture.keyIsModifier) {
      return const HotkeyCaptureRefused(
        refusal: HotkeyCaptureRefusal.modifierOnly,
        reason: 'Keep holding, then press the key you want to use.',
      );
    }
    if (capture.modifiers.isEmpty) {
      return const HotkeyCaptureRefused(
        refusal: HotkeyCaptureRefusal.noModifier,
        reason:
            'A shortcut needs at least one of Ctrl, Alt, Shift or Super. A key '
            'on its own would be taken from every other application, including '
            'the one you are writing in.',
      );
    }
    final key = _keys.forUsage(capture.usbHidUsage);
    if (key == null) {
      return const HotkeyCaptureRefused(
        refusal: HotkeyCaptureRefusal.keyNotRegistrable,
        reason:
            'That key is not one this app can register as a shortcut. Letters, '
            'digits, F1 to F12, and the navigation keys all work.',
      );
    }
    return HotkeyCaptureAccepted(
      // A fresh set, never the capture's own: the widget goes on editing the
      // set it built this from, and a binding is a value.
      HotkeyBinding(modifiers: {...capture.modifiers}, key: key.label),
    );
  }
}
