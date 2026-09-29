import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/tray/tray_manager_tray_icon.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/tray/tray_menu_entry.dart';
import 'package:tray_manager/tray_manager.dart';

/// The channel-level assumptions the binding-free tray suite takes on trust.
///
/// `tray_manager_tray_test.dart` drives a `TrayIcon` fake and so proves the
/// menu wiring and the state mapping without a binding — but it can say nothing
/// about whether the seam reaches the plugin at all. Three claims live only
/// here: that an asset path reaches `setIcon` as the plugin expects, that the
/// entries translate to a `menu_base` `Menu` preserving order and the disabled
/// flags, and that a click comes back as the entry's own key.
///
/// Needs a Flutter binding — a mocked method channel is the only way to reach
/// `trayManager`, which is a singleton behind a private channel. Hence
/// `test/platform/`, outside the binding-free `dart test` set. Not skipped: the
/// channel is reachable headlessly. Only a *real* indicator is not, and that is
/// what `tray_live_test.dart` records as owed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tray_manager');
  late List<MethodCall> platformCalls;
  late TrayManagerTrayIcon icon;

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// When set, the matching platform method rejects — the Linux handler
  /// answering `notImplemented`, or a channel that has gone away.
  late Set<String> refusedMethods;

  setUp(() {
    platformCalls = <MethodCall>[];
    refusedMethods = <String>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      platformCalls.add(call);
      if (refusedMethods.contains(call.method)) {
        throw PlatformException(code: 'refused', message: call.method);
      }
      return true;
    });
    icon = TrayManagerTrayIcon();
  });

  /// Every method the seam invoked, in order.
  List<String> invoked() => [for (final call in platformCalls) call.method];

  /// The two Linux methods this seam must never reach, asserted in [tearDown]
  /// after every row.
  ///
  /// `setToolTip` is not implemented by the Linux handler at all — it falls
  /// through to `notImplemented`, which reaches Dart as a rejection — and
  /// `setTitle` calls `app_indicator_set_label` on the same `AppIndicator*`
  /// that only `set_icon` creates, with no null check. Both are one line away
  /// from anyone editing this seam, and neither would fail any other test.
  void expectNeverReached() {
    expect(
      invoked(),
      isNot(anyElement(isIn(<String>['setToolTip', 'setTitle']))),
      reason:
          'setToolTip answers notImplemented on Linux and setTitle '
          'dereferences the indicator set_icon creates',
    );
  }

  tearDown(() async {
    // Asserted here rather than only per row: called by hand it was reached by
    // four of the seven rows, leaving the click and disposed-seam paths — the
    // two a stray `setTitle` is most likely to be added to — uncovered by the
    // very helper written to cover them. In `tearDown` no future row can
    // forget it. Before `dispose()`, so what is checked is what the row drove.
    expectNeverReached();
    refusedMethods = <String>{};
    await icon.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// Delivers a click the way the Linux plugin does: one inbound
  /// `onTrayMenuItemClick` carrying the item id the plugin was given.
  Future<void> deliverClick(int id) {
    return messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onTrayMenuItemClick', <String, Object?>{'id': id}),
      ),
      (_) {},
    );
  }

  /// The item ids of the last menu pushed, in order, as the plugin received
  /// them — the only handle a click has on an entry.
  List<int> lastMenuItemIds() {
    final menu =
        (platformCalls
                    .lastWhere((call) => call.method == 'setContextMenu')
                    .arguments
                as Map<Object?, Object?>)['menu']
            as Map<Object?, Object?>;
    return [
      for (final item in menu['items']! as List<Object?>)
        (item! as Map<Object?, Object?>)['id']! as int,
    ];
  }

  test('AD-12: setIcon reaches the plugin once, with the asset path the '
      'bundle resolves', () async {
    await icon.setIcon('assets/tray/hotkey-grammar-corrector.png');

    expect(invoked(), ['setIcon']);
    final arguments = platformCalls.single.arguments as Map<Object?, Object?>;
    expect(
      arguments['iconPath'] as String,
      endsWith('assets/tray/hotkey-grammar-corrector.png'),
      reason:
          'on a non-sandboxed Linux build tray_manager joins the given path '
          'onto <executable dir>/data/flutter_assets, so what is passed here '
          'is an asset path and the asset must be declared in pubspec.yaml',
    );
    expect(
      arguments['iconPath'] as String,
      contains('data/flutter_assets'),
      reason:
          'the join itself, which endsWith cannot see: the sandbox branch '
          'passes the argument through unjoined and would satisfy the '
          'assertion above unchanged. Which branch a shipped build takes is '
          'not observable here — TrayManager.setIcon switches on '
          'defaultTargetPlatform, and flutter test forces that to android — so '
          'what is pinned is the value the non-sandboxed Linux branch produces',
    );
    expectNeverReached();
  });

  test('AD-12: setMenu reaches the plugin once, carrying the labels and the '
      'disabled flags in order', () async {
    await icon.setMenu(const [
      TrayMenuEntry(key: 'open-panel', label: 'Open the panel', enabled: true),
      TrayMenuEntry(
        key: 'hotkey-unavailable',
        label: 'Global hotkey unavailable — use this menu to open the panel',
        enabled: false,
      ),
    ]);

    expect(invoked(), ['setContextMenu']);
    final menu =
        (platformCalls.single.arguments as Map<Object?, Object?>)['menu']
            as Map<Object?, Object?>;
    final items = (menu['items']! as List<Object?>)
        .cast<Map<Object?, Object?>>();

    expect(
      [for (final item in items) (item['label'], item['disabled'])],
      [
        ('Open the panel', false),
        ('Global hotkey unavailable — use this menu to open the panel', true),
      ],
      reason:
          'order and the disabled flags are both AD-12: the statement is a '
          'line the user cannot pick, and the way in above it is one they can',
    );
    expectNeverReached();
  });

  test(
    'AD-12: a click on an installed item comes back as that entry key',
    () async {
      await icon.setIcon('assets/tray/hotkey-grammar-corrector.png');
      await icon.setMenu(const [
        TrayMenuEntry(
          key: 'open-panel',
          label: 'Open the panel',
          enabled: true,
        ),
        TrayMenuEntry(
          key: 'hotkey-unavailable',
          label: 'Unavailable',
          enabled: false,
        ),
      ]);
      final selections = <String>[];
      icon.selections.listen(selections.add);
      final ids = lastMenuItemIds();

      await deliverClick(ids.first);
      await pumpEventQueue();

      expect(selections, ['open-panel']);
      expect(
        invoked(),
        ['setIcon', 'setContextMenu'],
        reason:
            'the ordering rule holds at the channel too, not only against the '
            'fake: set_context_menu dereferences the AppIndicator* that '
            'set_icon creates, with no null check',
      );
      expectNeverReached();
    },
  );

  test(
    'AD-12: a click whose id matches no installed item emits nothing',
    () async {
      await icon.setMenu(const [
        TrayMenuEntry(
          key: 'open-panel',
          label: 'Open the panel',
          enabled: true,
        ),
      ]);
      final selections = <String>[];
      icon.selections.listen(selections.add);

      await deliverClick(lastMenuItemIds().first + 4242);
      await pumpEventQueue();

      expect(selections, isEmpty);
    },
  );

  test('CAP-7: dispose destroys the indicator, deregisters from the singleton '
      'and closes selections', () async {
    var closed = false;
    icon.selections.listen(null, onDone: () => closed = true);
    expect(
      trayManager.hasListeners,
      isTrue,
      reason: 'the constructor is what registers the seam',
    );

    await icon.dispose();
    await pumpEventQueue();

    expect(invoked(), ['destroy']);
    expectNeverReached();
    expect(
      trayManager.hasListeners,
      isFalse,
      reason:
          'a daemon that exits with a listener still on the tray_manager '
          'singleton is what forgetting removeListener would ship',
    );
    expect(closed, isTrue);
  });

  test('CAP-7: a destroy that rejects still deregisters and still closes '
      'selections', () async {
    // `_disposed` latches first, so a close skipped here can never be reached
    // again: the second dispose() returns immediately. That would leave two of
    // the three things dispose()'s own doc promises undone, and the stream
    // open for the life of the process.
    var closed = false;
    icon.selections.listen(null, onDone: () => closed = true);
    refusedMethods.add('destroy');

    await expectLater(icon.dispose(), throwsA(isA<PlatformException>()));
    await pumpEventQueue();

    expect(closed, isTrue);
    expect(trayManager.hasListeners, isFalse);
  });

  test('CAP-7: a disposed seam invokes nothing further', () async {
    await icon.dispose();
    platformCalls.clear();

    await icon.setIcon('assets/tray/hotkey-grammar-corrector.png');
    await icon.setMenu(const [
      TrayMenuEntry(key: 'open-panel', label: 'Open the panel', enabled: true),
    ]);

    expect(platformCalls, isEmpty);
  });
}
