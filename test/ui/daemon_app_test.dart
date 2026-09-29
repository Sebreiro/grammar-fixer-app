import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/ui/daemon_home.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/correction_panel.dart';

import 'panel_harness.dart';

/// The daemon's root widget, which the panel harness already pumps.
///
/// Three of its properties are decisions about what the user sees the moment the
/// toggle maps the window, and each is a one-line revert away from a defect
/// nothing else in the suite would notice: the DEBUG ribbon shipping in the
/// `flutter build linux --debug` artifact the story's acceptance criteria
/// produce, and a panel that flashes as the one bright window on a dark desktop.
void main() {
  late PanelHarness harness;

  setUp(() => harness = PanelHarness());
  tearDown(() => harness.dispose());

  testWidgets('CAP-1: the summoned panel carries no debug ribbon and follows '
      'the desktop between light and dark', (tester) async {
    await harness.pump(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(
      app.debugShowCheckedModeBanner,
      isFalse,
      reason:
          'the panel is small and every pixel of it is content; the ribbon '
          'would ship in the debug artifact and cover part of a variant',
    );
    expect(app.theme?.colorScheme.brightness, equals(Brightness.light));
    expect(
      app.darkTheme?.colorScheme.brightness,
      equals(Brightness.dark),
      reason: 'a dark scheme has to exist for themeMode to have a choice',
    );
    expect(
      app.themeMode,
      equals(ThemeMode.system),
      reason:
          'a panel summoned over whatever the user is writing in follows the '
          'desktop rather than picking for it. Stated, not guarded: '
          'ThemeMode.system is also MaterialApp\'s own default, so deleting the '
          'argument cannot fail this — what the row pins is darkTheme, which '
          'has no default and without which themeMode has no dark to choose',
    );
    expect(
      app.home,
      isA<DaemonHome>(),
      reason:
          'the window has two views now (CAP-12), and which one is showing is '
          'DaemonHome\'s to decide — a summon always ends at the panel (CAP-1), '
          'which test/ui/daemon_home_test.dart is what holds',
    );
    expect(
      find.byType(CorrectionPanel),
      findsOneWidget,
      reason:
          'and the panel is what a window nobody has opened settings on '
          'shows — the SizedBox.shrink() home story 9 replaced',
    );
  });
}
