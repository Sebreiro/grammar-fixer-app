import 'package:hotkey_grammar_corrector/src/domain/panel/panel_visibility.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/window_manager_panel_visibility.dart';
import 'package:test/test.dart';

import '../../fakes/fake_keyboard_focus_witness.dart';
import '../../fakes/fake_logger.dart';
import '../../fakes/fake_panel_window.dart';

/// `PanelVisibility.changes` is broadcast, and the shipped adapter has to be
/// what proves it.
///
/// The port now documents the flavour, but a doc comment is not a mechanism:
/// the panel widget (story 9) and `CorrectionController` both subscribe at
/// startup, so a single-subscription adapter would throw
/// `Bad state: Stream has already been listened to` on the second listener,
/// during graph construction, before anything reached a user.
///
/// Pure Dart, no Flutter binding (AGENTS.md §7).
void main() {
  late FakePanelWindow window;
  late WindowManagerPanelVisibility visibility;

  setUp(() {
    window = FakePanelWindow();
    visibility = WindowManagerPanelVisibility(
      window: window,
      focusWitness: FakeKeyboardFocusWitness(),
      // Nothing here stalls a call: every request is settled by the test, so
      // the bound is present because the constructor requires it — one policy,
      // no site with a private default — and is deliberately far past anything
      // a loaded machine could reach. A bound these rows *could* hit would turn
      // them into abandonment rows that still emit the same transitions.
      requestTimeout: const Duration(minutes: 5),
      logger: FakeLogger(),
    );
  });

  tearDown(() => visibility.dispose());

  test('AD-8: changes reports itself broadcast', () {
    expect(visibility.changes.isBroadcast, isTrue);
  });

  test('CAP-2: two independent consumers each receive every transition, and '
      'neither subscription throws', () async {
    final panel = <PanelVisibilityState>[];
    final correction = <PanelVisibilityState>[];

    visibility.changes.listen(panel.add);
    expect(() => visibility.changes.listen(correction.add), returnsNormally);

    final showing = visibility.show();
    await window.settle();
    await showing;
    final hiding = visibility.hide();
    await window.settle();
    await hiding;
    await pumpEventQueue();

    expect(panel, [PanelVisibilityState.shown, PanelVisibilityState.dismissed]);
    expect(correction, [
      PanelVisibilityState.shown,
      PanelVisibilityState.dismissed,
    ]);
  });

  test('AD-8: a listener attached after a transition receives only what '
      'follows — isVisible is how the current value is read', () async {
    final showing = visibility.show();
    await window.settle();
    await showing;
    await pumpEventQueue();

    final late = <PanelVisibilityState>[];
    visibility.changes.listen(late.add);
    await pumpEventQueue();

    expect(late, isEmpty);
    expect(
      visibility.isVisible,
      isTrue,
      reason:
          'the stream carries transitions, not state; AD-8 makes the mirror '
          'the synchronous answer to "is it up right now"',
    );

    final hiding = visibility.hide();
    await window.settle();
    await hiding;
    await pumpEventQueue();

    expect(late, [PanelVisibilityState.dismissed]);
  });
}
