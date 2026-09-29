import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/controller_providers.dart';
import 'package:hotkey_grammar_corrector/src/ui/daemon_home.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/correction_panel.dart';
import 'package:hotkey_grammar_corrector/src/ui/settings/settings_screen.dart';

import 'panel_harness.dart';
import 'settings_harness.dart';

/// How the settings screen is reached, and how the window gets back to the panel
/// (CAP-1, CAP-12, CAP-14, AD-18).
///
/// The two views swap rather than stack, and none of it is a route: CAP-14 hides
/// the panel on focus loss, so a dialog or a second toplevel would dismiss the
/// window it was opened from. That is asserted negatively as well as positively.
void main() {
  late SettingsHarness harness;

  setUp(() => harness = SettingsHarness());
  tearDown(() => harness.dispose());

  /// The tooltip message of whatever currently holds focus, or null.
  ///
  /// Identifies the affordance precisely rather than by widget type: the idle
  /// panel already carries three (disabled) copy `IconButton`s, and a row that
  /// matched any of them would pass while the affordance stayed unreachable.
  String? focusedTooltip() =>
      primaryFocus?.context?.findAncestorWidgetOfExactType<Tooltip>()?.message;

  testWidgets('B1 CAP-12: activating the affordance shows the settings screen '
      'in place of the panel, with no route and no second window', (
    tester,
  ) async {
    await harness.pump(tester);
    expect(find.byType(CorrectionPanel), findsOneWidget);

    await harness.openSettings(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      find.byType(CorrectionPanel),
      findsNothing,
      reason:
          'a swap, not a stack — everything the panel holds lives in the '
          'controller, so unmounting it costs nothing',
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      harness.panelVisibility.isVisible,
      isFalse,
      reason:
          'AD-4 and AD-8: nothing in the ui ring shows or hides the window, so '
          'reaching settings moved no window — the mirror would have flipped. '
          'The structural half is ad1_import_rule_test.dart, which bans '
          'the visibility seam from this ring outright',
    );
  });

  testWidgets('B2 CAP-3: Back returns to the panel with the session\'s editor '
      'text and suggestions intact', (tester) async {
    await harness.pump(tester);
    await harness.summon(tester);
    await tester.enterText(find.byType(TextField), 'i has went to the shop');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    harness.run.emit(PanelHarness.completedEvent());
    await tester.pump();
    await tester.pump();
    expect(find.text('the corrected formal text'), findsOneWidget);

    await harness.openSettings(tester);
    expect(find.text('the corrected formal text'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pump();

    expect(find.byType(CorrectionPanel), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(
      find.text('i has went to the shop'),
      findsOneWidget,
      reason:
          'the editor text lives in CorrectionController, not in the widget, '
          'so a remount renders it again',
    );
    expect(find.text('the corrected formal text'), findsOneWidget);
    expect(
      harness.panelVisibility.isVisible,
      isTrue,
      reason:
          'going back hid nothing — the view swapped underneath a window '
          'the toggle still owns',
    );
  });

  testWidgets('B3 CAP-1, AD-18: a summon while settings is showing comes up on '
      'the panel', (tester) async {
    await harness.pumpSettings(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    // A real press, through the AD-8 toggle rather than the visibility fake:
    // CAP-1's route is `activations` -> PanelController -> `show()`, and driving
    // the adapter directly would skip the controller this claim depends on.
    await harness.summon(tester);

    expect(
      find.byType(CorrectionPanel),
      findsOneWidget,
      reason:
          'CAP-1 promises the hotkey summons the correction panel; a window '
          'that came up showing settings would break it',
    );
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('B3 AD-12, AD-14: a show of a window that is already visible '
      'comes up on the panel too', (tester) async {
    // The route with no session behind it, and the one that was broken.
    // `PanelVisibility.changes` emits on a *transition*, so raising a window
    // that is already visible starts no fresh session at all — and that is
    // exactly what AD-14's second launch and AD-12's tray "open the panel" entry
    // do. Before `PanelController.showRequests` existed, the tray raised a window
    // still showing the settings screen, on a screen printing "the tray menu
    // still opens the panel".
    await harness.pump(tester);
    await harness.summon(tester);
    expect(harness.panelVisibility.isVisible, isTrue);
    await harness.openSettings(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await harness.requestShow(tester);

    expect(
      find.byType(CorrectionPanel),
      findsOneWidget,
      reason:
          'the tray menu really does open the panel, which is what the settings '
          'screen itself tells the user on the unavailable path',
    );
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('B3 CAP-1: a summon of a hidden window raises both signals and '
      'the swap is still one swap', (tester) async {
    // A hidden-window summon produces the show request *and* the fresh session
    // it starts, so the two handlers both fire. Idempotence is what makes that
    // free, and a swap that assumed a single signal would be the bug.
    await harness.pumpSettings(tester);

    await harness.summon(tester);

    expect(find.byType(CorrectionPanel), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(harness.panelVisibility.isVisible, isTrue);
  });

  testWidgets('B3 AD-18: an ordinary session update leaves the panel showing '
      'and does not re-decide the view', (tester) async {
    // The other half of the same predicate: only a *fresh* session returns to
    // the panel, so a keystroke cannot rebuild the home view on every character.
    await harness.pump(tester);
    await harness.summon(tester);

    await tester.enterText(find.byType(TextField), 'typed by hand');
    await tester.pump();

    expect(find.byType(CorrectionPanel), findsOneWidget);
    expect(find.text('typed by hand'), findsOneWidget);
  });

  testWidgets('B3 AD-18: an ordinary session update while settings is showing '
      'does not evict the user from it', (tester) async {
    // The row above cannot fail on the guard it names. It drives a session
    // update with the **panel** already showing, where the return-to-panel call
    // is a no-op either way. Only a non-fresh update arriving while *settings*
    // is up can tell the two apart, and without the guard every streaming delta,
    // completion and copy failure tears the settings screen down mid-edit.
    //
    // **This row is that measurement, and the note here has been wrong twice.**
    // It first recorded that deleting `if (!state.isFreshSession) return;` from
    // `DaemonHome` "left the entire suite green" — true before this row existed,
    // and false since DW-54 stamped the marker. The correction that replaced it
    // then claimed the deletion "fails exactly this row and nothing else", which
    // overlooked the DW-54 row added thirty lines below in the same change.
    // Re-measured on the follow-up pass: the deletion fails **two** rows in
    // `flutter test test/ui` — this one and `CAP-3/DW-54: an editor the user
    // clears by hand does not evict them from settings`. Both are consumers of
    // the same guard, which is the thing the measurement is for.
    //
    // Note the deletion still leaves the CI-scoped `dart test` command green:
    // `.github/workflows/ci.yml` does not run `test/ui`. That is a pre-existing
    // gate decision, not something DW-30 introduced.
    await harness.pump(tester);
    await harness.summon(tester);
    await tester.enterText(find.byType(TextField), 'i has went to the store');
    await tester.pump();

    await harness.openSettings(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    // An ordinary session update: text changing in the editor the user is no
    // longer looking at. Non-fresh by construction — it carries content.
    harness.container
        .read(correctionControllerProvider)
        .editText('i has went to the shop');
    await tester.pump();
    await tester.pump();

    expect(
      find.byType(SettingsScreen),
      findsOneWidget,
      reason:
          'nothing about a session update asks for the panel — only a fresh '
          'session (a show) does, and that is what CAP-1 promises',
    );
    expect(find.byType(CorrectionPanel), findsNothing);
  });

  testWidgets('CAP-3/DW-54: an editor the user clears by hand does not evict '
      'them from settings — a keystroke is not a summon', (tester) async {
    // The case DW-54 predicted would end the old inference's harmlessness, at
    // the consumer surface rather than only at the state. `isFreshSession` used
    // to be `this == empty`, so an idle session with no suggestions whose editor
    // the user emptied produced *exactly* the value `_beginSession` emits — and
    // this view acted on it, swapping the settings screen the user was editing
    // for the panel. Every other field is already at its default here, which is
    // what makes the cleared editor the whole of the difference.
    await harness.pump(tester);
    await harness.summon(tester);
    await harness.openSettings(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    // Select all, delete.
    harness.container.read(correctionControllerProvider).editText('');
    await tester.pump();
    await tester.pump();

    expect(
      find.byType(SettingsScreen),
      findsOneWidget,
      reason:
          'the marker is stamped on the one state a session begins with, so a '
          'hand-cleared editor no longer looks like one (DW-54)',
    );
    expect(find.byType(CorrectionPanel), findsNothing);
  });

  testWidgets('CAP-1/DW-30: a window-manager restore is not a summon — it '
      'leaves the window where the user left it', (tester) async {
    // The paragraph `daemon_home.dart` states about DW-30, asserted. A
    // de-iconify raises no show request, and because the panel comes back to the
    // session it left rather than a new one it raises no fresh session either —
    // so there is no signal here at all and settings stays up. CAP-1 is about
    // what a *summon* opens; this is the window returning, not the user asking.
    await harness.pump(tester);
    await harness.summon(tester);
    await harness.openSettings(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    harness.panelVisibility.minimize();
    await tester.pump();
    harness.panelVisibility.restore();
    await tester.pump();
    await tester.pump();

    expect(
      find.byType(SettingsScreen),
      findsOneWidget,
      reason:
          'nothing asked for the panel: the iconify kept the session and the '
          'restore began none, so neither signal this view reads was raised',
    );
    expect(find.byType(CorrectionPanel), findsNothing);

    // And the contrast, so the row cannot pass by the view being inert: a real
    // summon after a dismissal does return to the panel.
    await harness.panelVisibility.hide();
    await tester.pump();
    await harness.summon(tester);

    expect(find.byType(CorrectionPanel), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('B4 CAP-12: the affordance is labelled with what it opens and is '
      'reachable from the keyboard', (tester) async {
    // Disposed inside the body rather than in a tearDown: the framework's
    // end-of-test check for leaked semantics handles runs first.
    final semantics = tester.ensureSemantics();
    await harness.pump(tester);

    final node = tester.getSemantics(SettingsHarness.affordance);
    expect(
      node.tooltip,
      'Open settings',
      reason:
          'an unlabelled icon is the whole affordance for a user who cannot '
          'see it — the tooltip is what carries the name to assistive '
          'technology as well as to a pointer',
    );
    expect(
      node.getSemanticsData().flagsCollection.isButton,
      isTrue,
      reason: 'and it is announced as something that can be activated',
    );

    // Tab until the affordance holds focus, stopping when traversal has cycled
    // rather than at a hand-picked count. A magic bound is coupled to however
    // many focusables the panel happens to carry today; "focus came back to
    // somewhere it has already been" is the honest end of the traversal, and it
    // is what makes this row's failure mean "unreachable" rather than "the
    // number was too small".
    final visited = <FocusNode>{};
    final trail = <String>[];
    var reached = false;
    while (!reached) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = primaryFocus;
      if (focused == null || !visited.add(focused)) {
        break; // traversal has cycled: everything reachable has been seen
      }
      trail.add(focusedTooltip() ?? focused.debugLabel ?? '<unlabelled>');
      reached = focusedTooltip() == 'Open settings';
    }
    expect(
      reached,
      isTrue,
      reason:
          'focus traversal cycled without reaching the settings affordance; it '
          'visited ${trail.join(' -> ')}',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.byType(SettingsScreen),
      findsOneWidget,
      reason: 'and activating it from the keyboard opens what it names',
    );
    semantics.dispose();
  });

  testWidgets('AD-4: the home view sets no state after it is unmounted, on '
      'either of the two signals that would', (tester) async {
    // **Settings has to be showing when it goes.** `_returnToPanel` early-returns
    // on `!_showingSettings`, so a teardown row that unmounts with the panel up
    // reaches no `setState` on either path and holds however the cancels are
    // written: measured, deleting either `cancel()` left the whole suite green.
    // That is the same blind spot the `isFreshSession` guard had — a row naming
    // a property while standing where the property cannot bite.
    await harness.pumpSettings(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());

    // Signal one: a show request, the route with no session behind it.
    harness.panel.showPanel();
    await tester.pump();
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason:
          'the show-request subscription outlived the widget and called '
          'setState on a disposed State',
    );

    // Signal two: a fresh session, from a real visibility transition.
    await harness.panelVisibility.hide();
    await harness.panelVisibility.show();
    await tester.pump();
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason:
          'the correction-state subscription outlived the widget and called '
          'setState on a disposed State',
    );

    expect(find.byType(DaemonHome), findsNothing);
  });
}
