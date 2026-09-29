import 'package:hotkey_grammar_corrector/src/infrastructure/tray/tray_menu_entry.dart';
import 'package:test/test.dart';

import '../../support/value_equality.dart';

/// The value contract [TrayMenuEntry] declares, pinned.
///
/// `TrayMenuEntry` was the only hand-written value type under `lib/src/` with
/// no equality row: neutering its `==` and `hashCode` to identity semantics
/// left `dart analyze` clean and the whole binding-free suite green. That is
/// the degradation `test/support/value_equality.dart` exists to stop — its own
/// doc records five domain types going the same way undetected — and the entry
/// becomes load-bearing the moment the deferred entry-equality `setMenu`
/// short-circuit is revisited, since that guard's correctness rests entirely
/// on this `==`.
void main() {
  group('TrayMenuEntry', () {
    test('two entries holding the same value are equal and hash alike', () {
      // Built separately and without `const`: Dart canonicalises identical
      // constant expressions, so a `const` pair would compare an object with
      // itself and pass with no `operator==` declared at all.
      expectSameValue(
        TrayMenuEntry(
          key: 'open-panel',
          label: 'Open ${'panel'}',
          enabled: true,
        ),
        TrayMenuEntry(
          key: 'open-panel',
          label: 'Open ${'panel'}',
          enabled: true,
        ),
      );
    });

    test('each field is part of the value', () {
      const base = TrayMenuEntry(
        key: 'open-panel',
        label: 'Open the panel',
        enabled: true,
      );

      expect(
        base,
        isNot(
          const TrayMenuEntry(
            key: 'hotkey-unavailable',
            label: 'Open the panel',
            enabled: true,
          ),
        ),
        reason: 'key is what a selection comes back as',
      );
      expect(
        base,
        isNot(
          const TrayMenuEntry(
            key: 'open-panel',
            label: 'Something else',
            enabled: true,
          ),
        ),
        reason: 'label is what the user reads',
      );
      expect(
        base,
        isNot(
          const TrayMenuEntry(
            key: 'open-panel',
            label: 'Open the panel',
            enabled: false,
          ),
        ),
        reason:
            'enabled is the whole difference between AD-12 offering an action '
            'and merely stating one — a menu differing only here must not '
            'compare equal to the menu it replaces',
      );
    });

    test('toString names the state without inventing a label', () {
      const entry = TrayMenuEntry(
        key: 'hotkey-unavailable',
        label: 'No global hotkey',
        enabled: false,
      );

      expect(entry.toString(), contains('hotkey-unavailable'));
      expect(entry.toString(), contains('disabled'));
    });
  });
}
