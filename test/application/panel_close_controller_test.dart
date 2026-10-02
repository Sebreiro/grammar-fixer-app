import 'package:hotkey_grammar_corrector/src/application/panel_close_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/panel_controller.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/close_behavior.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:test/test.dart';

import '../fakes/echoing_error.dart';
import '../fakes/fake_config_store.dart';
import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';
import '../fakes/fake_panel_visibility.dart';
import '../fakes/throwing_logger.dart';

void main() {
  late FakeConfigStore configStore;
  late FakePanelVisibility visibility;
  late FakeLogger logger;
  late PanelCloseController controller;

  setUp(() {
    configStore = FakeConfigStore(current: DefaultAppConfig.build());
    visibility = FakePanelVisibility();
    logger = FakeLogger();
    controller = PanelCloseController(
      configStore: configStore,
      visibility: visibility,
      logger: logger,
    );
  });

  tearDown(() async {
    await controller.dispose();
    visibility.dispose();
    configStore.dispose();
  });

  test(
    'CAP-1: native close defaults to tray and the warm panel can reopen',
    () async {
      final requests = <void>[];
      controller.quitRequests.listen(requests.add);
      await visibility.show();
      visibility.requestClose();
      await pumpEventQueue();
      expect(visibility.isVisible, isFalse);
      expect(requests, isEmpty);
      await visibility.show();
      expect(visibility.isVisible, isTrue);
    },
  );

  test(
    'CAP-8: a committed quit preference requests teardown without hiding',
    () async {
      configStore.current = configStore.current.copyWith(
        closeBehavior: CloseBehavior.quit,
      );
      final request = controller.quitRequests.first;
      await visibility.show();
      visibility.requestClose();
      await request;
      expect(visibility.isVisible, isTrue);
    },
  );

  test('CAP-8: native close reads the latest external config edit', () async {
    configStore.current = configStore.current.copyWith(
      closeBehavior: CloseBehavior.quit,
    );
    await configStore.write(
      configStore.current.copyWith(closeBehavior: CloseBehavior.closeToTray),
    );
    final requests = <void>[];
    controller.quitRequests.listen(requests.add);
    await visibility.show();
    visibility.requestClose();
    await pumpEventQueue();
    expect(visibility.isVisible, isFalse);
    expect(requests, isEmpty);
  });

  test('CAP-7: repeated quit on close requests one orderly teardown', () async {
    configStore.current = configStore.current.copyWith(
      closeBehavior: CloseBehavior.quit,
    );
    final requests = <void>[];
    controller.quitRequests.listen(requests.add);
    visibility.requestClose();
    visibility.requestClose();
    await pumpEventQueue();
    expect(requests, hasLength(1));
  });

  test(
    'CAP-14: hotkey and focus-loss dismissals still hide with quit selected',
    () async {
      configStore.current = configStore.current.copyWith(
        closeBehavior: CloseBehavior.quit,
      );
      final hotkey = FakeGlobalHotkey();
      final panel = PanelController(
        visibility: visibility,
        hotkey: hotkey,
        logger: logger,
      );
      addTearDown(() async {
        await panel.dispose();
        await hotkey.dispose();
      });
      final requests = <void>[];
      controller.quitRequests.listen(requests.add);
      panel.onHotkeyActivated();
      panel.onHotkeyActivated();
      expect(visibility.isVisible, isFalse);
      panel.showPanel();
      visibility.loseFocus();
      await pumpEventQueue();
      expect(visibility.isVisible, isFalse);
      expect(requests, isEmpty);
    },
  );

  test('CAP-13: a rejected close hide is logged without quitting', () async {
    await visibility.show();
    visibility.hideError = const EchoingError(
      'hide failed',
      'private clipboard text',
    );
    visibility.requestClose();
    await pumpEventQueue();
    expect(visibility.isVisible, isTrue);
    expect(logger.lines.single.message, contains('close hide'));
    expect(logger.lines.single.context, {'error_type': 'EchoingError'});
  });

  test('CAP-13: a close-stream error leaves the next close working', () async {
    await visibility.show();
    visibility.emitCloseError(
      const EchoingError('stream failed', 'private text'),
    );
    await pumpEventQueue();
    visibility.requestClose();
    await pumpEventQueue();
    expect(visibility.isVisible, isFalse);
    expect(logger.lines.single.context, {'error_type': 'EchoingError'});
  });

  test(
    'CAP-13: an unreadable close preference retains the tray default',
    () async {
      configStore.currentError = StateError('store unavailable');
      await visibility.show();
      visibility.requestClose();
      await pumpEventQueue();
      expect(visibility.isVisible, isFalse);
      expect(logger.lines.single.message, contains('closing to tray'));
    },
  );

  test(
    'AD-4: disposal cancels close handling and completes the quit stream',
    () async {
      var completed = false;
      controller.quitRequests.listen(
        (_) => fail('disposed controller emitted quit'),
        onDone: () => completed = true,
      );
      await controller.dispose();
      await controller.dispose();
      await visibility.show();
      visibility.requestClose();
      await pumpEventQueue();
      expect(completed, isTrue);
      expect(visibility.isVisible, isTrue);
    },
  );

  test(
    'AD-4: failed cancellation still closes quit events and prevents effects',
    () async {
      visibility.cancelError = StateError('cancellation refused');
      await controller.dispose();
      await visibility.show();
      visibility.requestClose();
      await pumpEventQueue();
      expect(visibility.isVisible, isTrue);
      expect(logger.lines.single.message, contains('cancelling'));
    },
  );

  test('AD-15: close handling survives a failed logging channel', () async {
    await controller.dispose();
    controller = PanelCloseController(
      configStore: configStore,
      visibility: visibility,
      logger: ThrowingLogger(),
    );
    await visibility.show();
    visibility.emitCloseError(StateError('channel unavailable'));
    await pumpEventQueue();
    visibility.requestClose();
    await pumpEventQueue();
    expect(visibility.isVisible, isFalse);
  });
}
