import 'dart:io';

import 'package:test/test.dart';

/// AD-1 for the tray, and AD-8's half of it, stated where a reader looks.
///
/// `package:tray_manager` is a Flutter plugin behind a method channel, and it
/// re-exports `package:menu_base` — so a `Menu` or a `MenuItem` crossing the
/// `TrayIcon` seam would put a vendor type in the adapter's callers *and* add
/// an undeclared dependency (`depend_on_referenced_packages`) if imported
/// directly. Confining both to one file is what makes the seam's justification
/// (`tray_icon.dart`) mechanically true rather than merely stated.
///
/// The last row is AD-8's: the tray's open-panel action reaches
/// `PanelVisibility.show()` through `PanelController.showPanel()`, and the tray
/// constructs no window of its own. `hidden_window_test.dart` already fails on
/// any `window_manager` *mapping* call under `lib/src/infrastructure/tray/` —
/// its startup-path scan exempts only `lib/src/infrastructure/panel/` — so this
/// row is the stronger, blunter version: the tray may not name the package at
/// all.
void main() {
  test('AD-1: exactly one file under lib/ names package:tray_manager', () {
    expect(
      _filesReferencing('package:tray_manager'),
      ['lib/src/infrastructure/tray/tray_manager_tray_icon.dart'],
      reason: 'nothing above the seam may see a Menu, a MenuItem or a channel',
    );
  });

  test('AD-1: no file under lib/ names package:menu_base', () {
    expect(
      _filesReferencing('package:menu_base'),
      isEmpty,
      reason:
          'tray_manager re-exports menu_base, so importing it directly would '
          'also be an undeclared dependency',
    );
  });

  test('AD-8: no file under lib/src/infrastructure/tray/ names '
      'window_manager', () {
    expect(
      _filesReferencing(
        'window_manager',
      ).where((path) => path.startsWith(_trayDirectory)),
      isEmpty,
      reason:
          'the tray opens the panel through PanelController.showPanel(); it '
          'constructs no window and touches no window_manager API',
    );
  });

  test('the scan actually finds something, or it proves nothing', () {
    expect(_filesReferencing('package:tray_manager'), isNotEmpty);
    expect(
      Directory(_trayDirectory).listSync().whereType<File>(),
      isNotEmpty,
      reason: 'the tray directory must exist for the AD-8 row to mean anything',
    );
  });
}

const String _trayDirectory = 'lib/src/infrastructure/tray/';

/// Every file under `lib/` whose source names [reference], comments stripped so
/// a comment explaining the confinement never reads as a violation of it.
List<String> _filesReferencing(String reference) {
  return [
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')))
      if (_stripComments(file.readAsStringSync()).contains(reference))
        file.path,
  ];
}

String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp('//[^\n]*'), '');
