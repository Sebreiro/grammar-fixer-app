import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/window_manager_panel_window.dart';
import 'package:window_manager/window_manager.dart';

/// The one channel-level assumption the binding-free suite takes on trust.
///
/// `window_manager_panel_visibility_test.dart` drives a `PanelWindow` fake and
/// so proves the mirror logic without a binding — but it can say nothing about
/// whether the real seam reaches the plugin at all. Two claims live only here:
/// that `show` is **two** channel calls rather than one (the `isMinimized`
/// pre-hop that makes an unserialised `hide` able to overtake it), and that
/// `show`/`hide`/`focus`/`blur`/`close` reach Dart through the untyped
/// `onWindowEvent` hook, which is the only route `window_manager 0.5.2` offers
/// for the first two, the route the visibility adapter answers `close` from
/// (DW-12), and the route `focus` takes to the adapter's keyboard flag, without
/// which no `blur` is ever answered (DW-33).
///
/// Needs a Flutter binding — a mocked method channel is the only way to reach
/// `windowManager`, which is a singleton behind a private channel. Hence
/// `test/platform/`, outside the binding-free `dart test` set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  late List<String> platformCalls;
  late WindowManagerPanelWindow window;

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    platformCalls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      platformCalls.add(call.method);
      if (call.method == 'isMinimized') {
        return false;
      }
      return true;
    });
    window = WindowManagerPanelWindow();
  });

  tearDown(() async {
    await window.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// Delivers an event the way the Linux plugin does: an inbound `onEvent`
  /// method call carrying the event name.
  Future<void> deliverEvent(String name) {
    return messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onEvent', <String, Object?>{'eventName': name}),
      ),
      (_) {},
    );
  }

  test('CAP-1: show() is the isMinimized pre-hop and then show, in that '
      'order', () async {
    await window.show();

    expect(
      platformCalls,
      ['isMinimized', 'show'],
      reason:
          'an exact sequence, not a contains: the pre-hop is a second await '
          'point that lets a later hide reach the platform first, and a '
          'contains-style assertion would filter out the very thing the '
          'serialisation in the visibility adapter exists to answer',
    );
  });

  test('CAP-1: focus() invokes focus — window_manager\'s Linux show is '
      'gtk_widget_show alone and does not raise or focus', () async {
    await window.focus();

    expect(platformCalls, ['focus']);
  });

  test('CAP-14: hide() invokes hide with no pre-hop of its own', () async {
    await window.hide();

    expect(platformCalls, ['hide']);
  });

  test('AD-8: show, focus, blur, hide and close all reach events through '
      'onWindowEvent', () async {
    final received = <String>[];
    window.events.listen(received.add);

    await deliverEvent('show');
    await deliverEvent('focus');
    await deliverEvent('blur');
    await deliverEvent('hide');
    await deliverEvent('close');
    await pumpEventQueue();

    expect(
      received,
      ['show', 'focus', 'blur', 'hide', 'close'],
      reason:
          'WindowListener declares no onWindowShow/onWindowHide and the '
          'dispatch map has no entry for either, so the untyped hook is the '
          'only route to the two events the mirror is reconciled from. '
          '`close` is here for a different reason (DW-12): the dispatch map '
          'does carry it, but the visibility adapter answers it from this '
          'stream, and a forwarder narrowed to the names above would leave a '
          'dismissed panel on screen with every binding-free suite green — '
          'setPreventClose(true) means GTK will not take the toplevel down '
          'either, so nothing else would notice. `focus` is here for a third '
          'reason (DW-33): the adapter dismisses on `blur` only when a '
          '`focus` first said the window held the keyboard, so a forwarder '
          'that dropped it would not misreport the panel — it would stop '
          'CAP-14 dismissing it at all',
    );
  });

  test('AD-8: a disposed seam makes no further window calls', () async {
    await window.dispose();
    platformCalls.clear();

    await window.show();
    await window.hide();
    await window.focus();

    expect(
      platformCalls,
      isEmpty,
      reason:
          'once the listener is deregistered and events are closed, a call '
          'that still moved the real window could never be echoed back, so '
          'no mirror above it could ever correct itself',
    );
  });

  test(
    'AD-8: a disposed seam deregisters — a later event reaches nothing',
    () async {
      final received = <String>[];
      window.events.listen(received.add);

      // Observe the registry itself, not only the silence. The silence is
      // guaranteed by `_disposed` and by the closed controller whether or not
      // `removeListener` ever runs, so asserting it alone leaves the call
      // pinned by nothing: deleting `windowManager.removeListener(this)` used
      // to fail no test in the suite. A daemon that exits with a listener
      // still on the `window_manager` singleton is what that would ship.
      expect(
        windowManager.listeners,
        contains(window),
        reason: 'the constructor is what registers the seam',
      );

      await window.dispose();

      expect(
        windowManager.listeners,
        isNot(contains(window)),
        reason: 'dispose() deregisters from the singleton, not just locally',
      );

      await deliverEvent('show');
      await pumpEventQueue();

      expect(received, isEmpty);
    },
  );
}
