import 'dart:async';

import 'package:hotkey_grammar_corrector/src/application/panel_controller.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/absent_keyboard_focus_witness.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/panel_activation_context.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/window_manager_panel_visibility.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/tray/tray_manager_tray.dart';
import 'package:test/test.dart';

import '../../fakes/fake_global_hotkey.dart';
import '../../fakes/fake_logger.dart';
import '../../fakes/fake_panel_window.dart';
import '../../fakes/fake_tray_icon.dart';

void main() {
  late PanelActivationContext context;
  late FakePanelWindow window;
  late WindowManagerPanelVisibility visibility;

  setUp(() {
    context = PanelActivationContext();
    window = FakePanelWindow();
    visibility = WindowManagerPanelVisibility(
      window: window,
      focusWitness: const AbsentKeyboardFocusWitness(),
      requestTimeout: const Duration(minutes: 1),
      logger: FakeLogger(),
      activationContext: context,
    );
  });

  tearDown(() => visibility.dispose());

  test('CAP-1: each portal token belongs to one show intent', () async {
    context.preparePortal('first');
    final first = visibility.show();
    context.preparePortal('next');
    await window.settle();
    await first;
    expect(window.focusActivations.single?.token, 'first');

    final next = visibility.show();
    await window.settle();
    await next;
    expect(window.focusActivations.last?.token, 'next');

    final repeated = visibility.show();
    await window.settle();
    await repeated;
    expect(window.focusActivations.last, isNull);
  });

  test(
    'CAP-1: a superseding show uses only its own activation token',
    () async {
      context.preparePortal('old');
      final old = visibility.show();
      await pumpEventQueue();
      context.preparePortal('latest');
      final latest = visibility.show();
      await window.settle();
      await Future.wait([old, latest]);

      expect(window.focusActivations, hasLength(1));
      expect(window.focusActivations.single?.token, 'latest');
    },
  );

  test(
    'CAP-14: hide discards its hotkey token and supersedes pending focus',
    () async {
      context.preparePortal('show');
      final show = visibility.show();
      await pumpEventQueue();
      context.preparePortal('hide');
      final hide = visibility.hide();
      await window.settle();
      await Future.wait([show, hide]);
      expect(window.focusActivations, isEmpty);
      expect(context.take(), isNull);
      expect(window.visible, isFalse);

      final later = visibility.show();
      await window.settle();
      await later;
      expect(window.focusActivations.single, isNull);
    },
  );

  test(
    'CAP-1: tray provenance is prepared before its shared show request',
    () async {
      final icon = FakeTrayIcon();
      final tray = TrayManagerTray(
        icon: icon,
        logger: FakeLogger(),
        onPanelRequest: context.prepareTray,
      );
      addTearDown(tray.dispose);
      final request = Completer<void>();
      tray.panelRequests.listen((_) {
        unawaited(visibility.show().then(request.complete));
      });
      icon.emitSelection('open-panel');
      await pumpEventQueue();
      await window.settle();
      await request.future;
      expect(window.focusActivations.single?.fromTray, isTrue);
      expect(window.focusActivations.single?.token, isNull);

      icon.emitSelection('quit');
      await pumpEventQueue();
      expect(context.take(), isNull);
    },
  );

  test(
    'CAP-14: activation provenance leaves hotkey toggle and blur dismissal intact',
    () async {
      final hotkey = FakeGlobalHotkey();
      final controller = PanelController(
        visibility: visibility,
        hotkey: hotkey,
        logger: FakeLogger(),
      );
      addTearDown(controller.dispose);
      addTearDown(hotkey.dispose);

      context.preparePortal('show');
      controller.onHotkeyActivated();
      await window.settle();
      window.emitEvent('focus');
      await pumpEventQueue();
      window.emitEvent('blur');
      await window.settle();
      expect(visibility.isVisible, isFalse);

      context.preparePortal('return');
      controller.onHotkeyActivated();
      await window.settle();
      expect(window.focusActivations.last?.token, 'return');
      context.preparePortal('toggle-off');
      controller.onHotkeyActivated();
      await window.settle();
      expect(visibility.isVisible, isFalse);
      expect(context.take(), isNull);
    },
  );
}
