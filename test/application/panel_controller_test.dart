import 'dart:async';

import 'package:hotkey_grammar_corrector/src/application/panel_controller.dart';
import 'package:hotkey_grammar_corrector/src/domain/panel/panel_visibility.dart';
import 'package:test/test.dart';

import '../fakes/echoing_error.dart';
import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';
import '../fakes/fake_panel_visibility.dart';
import '../fakes/throwing_logger.dart';

/// The AD-8 toggle: CAP-1's show path and CAP-14's second press, and what it
/// does when the visibility port refuses.
void main() {
  late FakePanelVisibility visibility;
  late FakeGlobalHotkey hotkey;
  late FakeLogger logger;
  late PanelController controller;

  setUp(() {
    visibility = FakePanelVisibility();
    hotkey = FakeGlobalHotkey();
    logger = FakeLogger();
    controller = PanelController(
      visibility: visibility,
      hotkey: hotkey,
      logger: logger,
    );
  });

  tearDown(() async {
    await controller.dispose();
    await hotkey.dispose();
    visibility.dispose();
  });

  test('CAP-1: the hotkey shows the panel when it is hidden', () {
    controller.onHotkeyActivated();

    expect(visibility.isVisible, isTrue);
  });

  test('CAP-14: a second hotkey press hides the panel', () {
    controller.onHotkeyActivated();
    expect(visibility.isVisible, isTrue, reason: 'the first press shows');

    controller.onHotkeyActivated();

    // Both presses were handled without a microtask running between them,
    // which is AD-8's real claim: the decision awaits nothing.
    expect(visibility.isVisible, isFalse);
  });

  test('CAP-1: pressing the bound combination toggles the panel', () async {
    hotkey.press();
    await pumpEventQueue();
    expect(visibility.isVisible, isTrue);

    hotkey.press();
    await pumpEventQueue();
    expect(visibility.isVisible, isFalse);
  });

  test('AD-14: showPanel() shows a hidden panel', () {
    controller.showPanel();

    expect(visibility.isVisible, isTrue);
  });

  test('AD-14: showPanel() leaves an already-visible panel up — a second '
      'launch asks to see the panel, not to dismiss it', () {
    controller.onHotkeyActivated();
    expect(visibility.isVisible, isTrue, reason: 'the press shows');

    controller.showPanel();

    expect(
      visibility.isVisible,
      isTrue,
      reason: 'unlike the toggle, this path never hides',
    );
  });

  test('AD-8: a rejected showPanel() is logged, never thrown — AD-14 must '
      'not take the daemon down over a refused window map', () async {
    visibility.showError = StateError('the window manager refused the map');

    expect(controller.showPanel, returnsNormally);
    await pumpEventQueue();

    expect(logger.lines.single.level, equals('error'));
    expect(visibility.isVisible, isFalse);
  });

  group('showRequests (CAP-1, AD-12, AD-14)', () {
    test('AD-14: every show this controller asks for is announced, including '
        'one for a window that is already visible', () async {
      // The signal exists because `PanelVisibility.changes` cannot carry it:
      // that stream emits on a *transition*, so raising a window that is already
      // up produces no event at all — and a later launch and the tray's
      // open-panel entry both do exactly that. A surface keyed off the transition
      // therefore never learns it was summoned.
      final requests = <void>[];
      final transitions = <PanelVisibilityState>[];
      controller.showRequests.listen(requests.add);
      final watching = visibility.changes.listen(transitions.add);
      addTearDown(watching.cancel);

      controller.showPanel();
      await pumpEventQueue();
      expect(requests, hasLength(1));

      controller.showPanel();
      await pumpEventQueue();

      expect(
        requests,
        hasLength(2),
        reason: 'the second show moved no window and still has to be heard',
      );
      expect(
        transitions,
        equals([PanelVisibilityState.shown]),
        reason:
            'and the visibility stream saw only the first, which is the whole '
            'reason this one exists',
      );
    });

    test('CAP-1: a press that shows is announced, and a press that hides is '
        'not', () async {
      final requests = <void>[];
      controller.showRequests.listen(requests.add);

      hotkey.press();
      await pumpEventQueue();
      expect(requests, hasLength(1));

      hotkey.press();
      await pumpEventQueue();

      expect(
        requests,
        hasLength(1),
        reason:
            'CAP-14\'s second press hides, and a hide is not a request to show '
            '— a surface returning to the panel on one would fight the toggle',
      );
      expect(visibility.isVisible, isFalse);
    });

    test('CAP-1: the announcement does not delay the show, and a refused show '
        'is still announced', () async {
      // AD-8 forbids awaiting on this path. The port call is fired first and the
      // announcement is a synchronous add, so both have happened before
      // `showPanel()` returns — measured here without pumping anything.
      visibility.showError = StateError('the window manager refused the map');
      final requests = <void>[];
      controller.showRequests.listen(requests.add);

      controller.showPanel();
      await pumpEventQueue();

      expect(
        requests,
        hasLength(1),
        reason:
            'a request is an intent, not a confirmation: the user asked for the '
            'panel whether or not the window manager obliged',
      );
      expect(visibility.isVisible, isFalse);
    });

    test(
      'AD-4: a disposed controller closes the stream and announces no more',
      () async {
        final requests = <void>[];
        var done = false;
        controller.showRequests.listen(requests.add, onDone: () => done = true);

        await controller.dispose();
        controller.showPanel();
        await pumpEventQueue();

        expect(done, isTrue);
        expect(
          requests,
          isEmpty,
          reason: 'and adding to a closed controller must not throw either',
        );
      },
    );
  });

  test('CAP-14: the hotkey shows again after a focus-loss hide', () {
    controller.onHotkeyActivated();
    visibility.loseFocus();

    controller.onHotkeyActivated();

    expect(visibility.isVisible, isTrue);
  });

  test('a disposed controller stops responding to activations', () async {
    await controller.dispose();

    hotkey.press();
    await pumpEventQueue();

    expect(visibility.isVisible, isFalse);
  });

  group('a visibility port that refuses', () {
    test('CAP-1: a rejected show() is logged and never thrown at the '
        'hotkey path', () async {
      visibility.showError = StateError('the window manager refused');

      controller.onHotkeyActivated();
      await pumpEventQueue();

      expect(visibility.isVisible, isFalse);
      expect(logger.lines.single.level, equals('error'));
      expect(logger.lines.single.message, contains('show'));
    });

    test('CAP-14: a rejected hide() leaves the toggle usable on the next '
        'press', () async {
      controller.onHotkeyActivated();
      expect(visibility.isVisible, isTrue);
      visibility.hideError = StateError('the window manager refused');

      controller.onHotkeyActivated();
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue, reason: 'the hide never landed');
      visibility.hideError = null;
      controller.onHotkeyActivated();

      expect(visibility.isVisible, isFalse);
      final failures = logger.lines.where((line) => line.level == 'error');
      expect(failures, hasLength(1));
      expect(
        failures.single.message,
        contains('hide'),
        reason: 'an operator reading stderr must see which call refused',
      );
    });

    test('AD-15: a visibility port that throws synchronously instead of '
        'rejecting still never reaches the hotkey path (CAP-1)', () async {
      final throwing = _SynchronouslyThrowingVisibility();
      // Its own hotkey: `activations` is single-subscription, and the
      // controller built in setUp already holds the one subscription.
      final throwingController = PanelController(
        visibility: throwing,
        hotkey: FakeGlobalHotkey(),
        logger: logger,
      );
      addTearDown(throwingController.dispose);

      expect(throwingController.onHotkeyActivated, returnsNormally);

      expect(logger.lines.single.level, equals('error'));
      expect(logger.lines.single.message, contains('show'));
    });

    test('AD-15: a visibility mirror that throws is logged and the press '
        'still reaches the port (CAP-1)', () async {
      visibility.isVisibleError = StateError('the window handle is gone');

      expect(controller.onHotkeyActivated, returnsNormally);
      await pumpEventQueue();
      visibility.isVisibleError = null;

      expect(
        visibility.isVisible,
        isTrue,
        reason: 'hidden is the assumption, so the press asks for a show',
      );
      expect(logger.lines.single.level, equals('error'));
      expect(logger.lines.single.message, contains('visibility mirror'));
    });

    test('AD-15: a throwing visibility mirror on the activations path never '
        'reaches the zone (CAP-1)', () async {
      final unhandled = <Object>[];

      await runZonedGuarded(() async {
        // Its own ports: the mirror is read inside the subscription's own
        // callback, so the controller has to be built in this zone for the
        // handler to run in it.
        final ownHotkey = FakeGlobalHotkey();
        final failing = FakePanelVisibility()
          ..isVisibleError = StateError('the window handle is gone');
        final resilient = PanelController(
          visibility: failing,
          hotkey: ownHotkey,
          logger: logger,
        );

        ownHotkey.press();
        await pumpEventQueue();

        await resilient.dispose();
        await ownHotkey.dispose();
        failing.dispose();
      }, (error, _) => unhandled.add(error));
      await pumpEventQueue();

      expect(unhandled, isEmpty);
      expect(
        logger.lines.map((line) => line.message),
        contains(contains('visibility mirror')),
      );
    });

    test('AD-4: shutdown completes when cancelling the activations '
        'subscription rejects', () async {
      hotkey.cancelError = StateError('the portal session refused to close');

      await expectLater(controller.dispose(), completes);

      expect(logger.lines.single.level, equals('error'));
      expect(
        logger.lines.single.message,
        contains('cancelling the hotkey activation subscription failed'),
      );
      hotkey.cancelError = null;
    });

    test('AD-15: an activations stream error is logged and the next press '
        'still toggles (CAP-1)', () async {
      hotkey.emitActivationsError(StateError('the portal signal failed'));
      await pumpEventQueue();

      hotkey.press();
      await pumpEventQueue();

      expect(visibility.isVisible, isTrue);
      expect(logger.lines.single.level, equals('error'));
    });

    test('nothing sensitive reaches the log on any failure path', () async {
      const secret = 'the private message i pasted';
      visibility.showError = const EchoingError(
        'the compositor refused',
        secret,
      );

      controller.onHotkeyActivated();
      await pumpEventQueue();
      hotkey.emitActivationsError(
        const EchoingError('the portal signal failed', secret),
      );
      await pumpEventQueue();
      // The mirror and the teardown are guards too, and each reduces a caught
      // error of its own — an assertion over only the paths a test happens to
      // drive reads as exhaustive without being it.
      visibility.isVisibleError = const EchoingError(
        'the window handle is gone',
        secret,
      );
      controller.onHotkeyActivated();
      await pumpEventQueue();
      visibility.isVisibleError = null;
      hotkey.cancelError = const EchoingError(
        'the portal session refused',
        secret,
      );
      await controller.dispose();
      hotkey.cancelError = null;

      expect(logger.lines, hasLength(5), reason: 'every guard logged once');
      for (final line in logger.lines) {
        expect('${line.message} ${line.context}', isNot(contains(secret)));
      }
    });

    test('AD-15: a logger whose own sink is gone does not turn a guard into '
        'an unhandled error (CAP-1)', () async {
      final unhandled = <Object>[];
      final throwingLogger = ThrowingLogger();

      await runZonedGuarded(() async {
        final ownHotkey = FakeGlobalHotkey();
        final failing = FakePanelVisibility()
          ..showError = StateError('the window manager refused');
        final resilient = PanelController(
          visibility: failing,
          hotkey: ownHotkey,
          logger: throwingLogger,
        );

        resilient.onHotkeyActivated();
        await pumpEventQueue();
        ownHotkey.emitActivationsError(StateError('the portal signal failed'));
        await pumpEventQueue();
        // The mirror guard recovers by logging too, so it needs the swallow
        // as much as the other three.
        failing.isVisibleError = StateError('the window handle is gone');
        expect(resilient.onHotkeyActivated, returnsNormally);
        await pumpEventQueue();
        failing.isVisibleError = null;
        ownHotkey.cancelError = StateError('the portal session refused');

        await expectLater(resilient.dispose(), completes);
        failing.dispose();
      }, (error, _) => unhandled.add(error));
      await pumpEventQueue();

      expect(
        throwingLogger.attempts,
        hasLength(5),
        reason:
            'the show, the stream, the mirror, the show it fell back to, '
            'and the cancel each still tried to report',
      );
      expect(unhandled, isEmpty);
    });
  });
}

/// A visibility port whose `show()` throws before returning a future at all.
/// The port declares `Future<void>`, so this is out of contract — and the
/// one shape an `async` fake method cannot produce, which is why it needs a
/// double of its own.
final class _SynchronouslyThrowingVisibility implements PanelVisibility {
  @override
  Stream<void> get closeRequests => const Stream<void>.empty();

  @override
  bool get isVisible => false;

  @override
  Stream<PanelVisibilityState> get changes =>
      const Stream<PanelVisibilityState>.empty();

  @override
  Future<void> show() => throw StateError('the window manager refused');

  @override
  Future<void> hide() => throw StateError('the window manager refused');
}
