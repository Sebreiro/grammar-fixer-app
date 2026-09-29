import 'dart:async';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/tray/hotkey_tray_status.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/tray/tray_manager_tray.dart';
import 'package:test/test.dart';

import '../../fakes/fake_logger.dart';
import '../../fakes/fake_tray_icon.dart';
import '../../fakes/throwing_logger.dart';
import '../../support/declared_flutter_assets.dart';

/// AD-12's tray: the way into the app when no global hotkey could be bound,
/// and the surface that says so.
///
/// Binding-free (`package:test`, AGENTS.md §7). Everything decided here is
/// decision-making — which entries exist, what a pick maps to, and when a menu
/// is deliberately *not* pushed — and it is decided against the [FakeTrayIcon]
/// seam rather than against `trayManager`, which is a singleton behind a
/// private method channel. The seam's own translation to `menu_base` and the
/// click route are observed in `test/platform/tray_manager_tray_icon_test.dart`.
///
/// The call assertions are **sequences**, not sets, because the ordering is the
/// contract: `set_context_menu` dereferences the `AppIndicator*` that
/// `set_icon` creates, with no null check.
void main() {
  late FakeTrayIcon icon;
  late FakeLogger logger;
  late TrayManagerTray tray;

  setUp(() {
    icon = FakeTrayIcon();
    logger = FakeLogger();
    tray = TrayManagerTray(icon: icon, logger: logger);
  });

  tearDown(() async => tray.dispose());

  group('installation (AD-12)', () {
    test('AD-12: install() sets the available icon and then the menu, in that '
        'order — a menu pushed first dereferences a null indicator', () async {
      await tray.install();

      expect(icon.calls, [_setAvailableIcon, _menuWithoutStatement]);
    });

    test('AD-12, DW-114: the installed menu offers exactly two actions, and '
        'both are enabled', () async {
      await tray.install();

      expect(icon.menus.single, hasLength(2));
      for (final entry in icon.menus.single) {
        expect(entry.enabled, isTrue);
        expect(entry.label, isNotEmpty);
      }
    });

    test('AD-12: a seam that refuses the icon rejects install() — the '
        'composition root is what keeps that from stopping startup', () async {
      icon.setIconError = StateError('no StatusNotifier host');

      await expectLater(tray.install(), throwsA(isA<StateError>()));
      expect(
        icon.calls,
        [_setAvailableIcon],
        reason: 'the menu is not pushed behind an icon that was refused',
      );
    });

    test('AD-12: an install that failed leaves the tray uninstalled, so a '
        'later state change pushes nothing at an indicator that was '
        'refused', () async {
      // `_installed` is what the A7 guard consults, so recording it before the
      // indicator exists makes it a lie at exactly the moment it is read: a
      // menu pushed at an `AppIndicator*` whose creation was refused. This row
      // covers the icon being refused; the row below covers the other half —
      // `setIcon` landing and `setMenu` being refused, where the indicator
      // *does* exist and the opposite mistake is the dangerous one.
      icon.setIconError = StateError('no StatusNotifier host');
      await expectLater(tray.install(), throwsA(isA<StateError>()));
      icon.calls.clear();

      await tray.setHotkeyUnavailable(true);

      expect(
        icon.calls,
        isEmpty,
        reason: 'nothing may be pushed until an install has actually landed',
      );

      // And the state is still remembered, so an install that succeeds later
      // renders it — the A7 rule, reached by a different route.
      icon.setIconError = null;
      await tray.install();

      expect(icon.calls, [_setUnavailableIcon, _menuWithStatement]);
    });

    test('AD-12: an install that died at the menu still left a real indicator '
        'on screen, so the next state change repairs it rather than being '
        'suppressed for the life of the daemon', () async {
      // The native `set_icon` is what creates the indicator and sets it
      // ACTIVE, attaching an empty `gtk_menu_new()`. So an install that
      // reaches `setMenu` and is refused leaves a visible tray icon that does
      // nothing — and treating that as "not installed" makes it permanent:
      // every later push is suppressed by the A7 guard, nothing retries, and
      // `main.dart` would report a tray that is plainly there as absent.
      icon.setMenuError = StateError('the indicator went away');
      await expectLater(tray.install(), throwsA(isA<StateError>()));
      icon.calls.clear();
      icon.setMenuError = null;

      await tray.setHotkeyUnavailable(true);

      expect(
        icon.calls,
        [_setUnavailableIcon, _menuWithStatement],
        reason:
            'the indicator exists, so the tray is allowed — and required — to '
            'push at it again',
      );
    });
  });

  group('opening the panel (AD-12, AD-8)', () {
    test('AD-12: picking the open-panel entry asks for the panel exactly '
        'once', () async {
      await tray.install();
      final requests = <void>[];
      tray.panelRequests.listen(requests.add);

      icon.emitSelection(_openPanelKey(icon));
      await pumpEventQueue();

      expect(requests, hasLength(1));
    });

    test('AD-12: a key no entry carries raises no panel and is logged '
        'once', () async {
      await tray.install();
      final requests = <void>[];
      tray.panelRequests.listen(requests.add);

      icon.emitSelection(_inventedKey);
      await pumpEventQueue();

      expect(requests, isEmpty);
      final warnings = logger.lines.where((line) => line.level == 'warning');
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('no menu entry carries'));
    });

    test('AD-12: activating the disabled statement entry is logged as what it '
        'is, not as an invented key', () async {
      await tray.install();
      await tray.setHotkeyUnavailable(true);
      final requests = <void>[];
      tray.panelRequests.listen(requests.add);

      // The key of the statement line the adapter itself just pushed — an
      // entry it builds, so "no menu entry carries this" would be false. Read
      // out of the pushed menu by position rather than restated here, and no
      // longer `.last`: Quit is what sits last now.
      icon.emitSelection(_statementKey(icon));
      await pumpEventQueue();

      expect(requests, isEmpty);
      final warnings = logger.lines.where((line) => line.level == 'warning');
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('disabled'));
      expect(
        warnings.single.message,
        isNot(contains('no menu entry carries')),
        reason:
            'this key names an entry this adapter pushes; reporting it as one '
            'no entry carries points an operator at the wrong fault',
      );
    });

    test('AD-12: panelRequests is broadcast — two independent listeners each '
        'receive the pick', () async {
      await tray.install();
      final first = <void>[];
      final second = <void>[];
      tray.panelRequests.listen(first.add);
      tray.panelRequests.listen(second.add);

      icon.emitSelection(_openPanelKey(icon));
      await pumpEventQueue();

      expect(first, hasLength(1));
      expect(second, hasLength(1));
    });

    test('AD-15: a selection stream that errors is logged by type and the '
        'subscription survives the next pick', () async {
      await tray.install();
      final requests = <void>[];
      tray.panelRequests.listen(requests.add);

      icon.emitSelectionError(_PayloadCarryingError());
      await pumpEventQueue();
      icon.emitSelection(_openPanelKey(icon));
      await pumpEventQueue();

      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(errors.single.context, {'error_type': '_PayloadCarryingError'});
      expect(
        requests,
        hasLength(1),
        reason: 'the tray is the way in; an errored stream must not end it',
      );
    });
  });

  group('quitting from the tray (DW-114)', () {
    test('DW-114: the installed menu carries an enabled Quit entry beside the '
        'open-panel one', () async {
      await tray.install();

      final menu = icon.menus.single;
      expect(menu.last.label, 'Quit');
      expect(
        menu.last.enabled,
        isTrue,
        reason:
            'a resident daemon can otherwise only be stopped by a signal, '
            'which a tray-only user has no way to send',
      );
      // Both spellings. `...` is three ASCII full stops; `…` is U+2026, the one
      // a label written to desktop convention would actually use — and a
      // `contains('...')` cannot see it, so `Quit…` would walk straight past
      // the guard whose whole purpose is that no dialog is promised.
      for (final ellipsis in <String>['...', '…']) {
        expect(
          menu.last.label,
          isNot(contains(ellipsis)),
          reason: 'an ellipsis promises a dialog, and quitting is immediate',
        );
      }
    });

    test(
      'DW-114: the Quit entry is still there and still enabled while the '
      'hotkey is unavailable — that is the state the tray exists for',
      () async {
        await tray.install();

        await tray.setHotkeyUnavailable(true);

        final menu = icon.menus.last;
        expect(menu, hasLength(3));
        expect(
          menu.last.enabled,
          isTrue,
          reason:
              'greying out the way out on the one session family that cannot '
              'reach the hotkey would invert AD-12 the same way greying out the '
              'open-panel entry would',
        );
        expect(
          menu.last.label,
          'Quit',
          reason:
              'Quit stays last, after the statement line it does not explain',
        );
      },
    );

    test('DW-114: picking Quit asks for the daemon to stop exactly once, and '
        'asks for no panel', () async {
      await tray.install();
      final quits = <void>[];
      final panels = <void>[];
      tray.quitRequests.listen(quits.add);
      tray.panelRequests.listen(panels.add);

      icon.emitSelection(_quitKey(icon));
      await pumpEventQueue();

      expect(quits, hasLength(1));
      expect(
        panels,
        isEmpty,
        reason:
            'the two entries are two intents; routing a quit to the panel '
            'stream would raise the window of a daemon on its way out',
      );
    });

    test('DW-114: quitRequests is broadcast — two independent listeners each '
        'receive the pick', () async {
      // The port's doc promises it, the same way it does for panelRequests, and
      // nothing else here would notice a single-subscription controller behind
      // it: every other row in this group listens exactly once.
      await tray.install();
      final first = <void>[];
      final second = <void>[];
      tray.quitRequests.listen(first.add);
      tray.quitRequests.listen(second.add);

      icon.emitSelection(_quitKey(icon));
      await pumpEventQueue();

      expect(first, hasLength(1));
      expect(second, hasLength(1));
    });

    test('DW-114: picking the open-panel entry asks for no quit', () async {
      await tray.install();
      final quits = <void>[];
      tray.quitRequests.listen(quits.add);

      icon.emitSelection(_openPanelKey(icon));
      await pumpEventQueue();

      expect(
        quits,
        isEmpty,
        reason:
            'the composition root turns a quit request into the ordered '
            'teardown and exit(0); one emitted by mistake ends the daemon',
      );
    });

    test('CAP-7: dispose() closes quitRequests too, so a pick landing in the '
        'teardown gap reaches nothing', () async {
      await tray.install();
      final key = _quitKey(icon);
      var closed = false;
      final quits = <void>[];
      tray.quitRequests.listen(quits.add, onDone: () => closed = true);

      await tray.dispose();
      await pumpEventQueue();

      expect(
        closed,
        isTrue,
        reason:
            'this stream is closed by the very teardown a quit starts, and a '
            'controller left open is a daemon that exits holding it',
      );

      // Both halves are shut by now — the seam swallows this, and the adapter
      // would refuse it anyway — and that is the claim: a pick landing in the
      // teardown gap reaches no closed controller, which would throw.
      icon.emitSelection(key);
      await pumpEventQueue();

      expect(quits, isEmpty);
    });
  });

  group('the unavailable state is visible on both surfaces (AD-12)', () {
    test('AD-12: an unavailable hotkey swaps the icon and adds a disabled '
        'statement, while the way in stays enabled', () async {
      await tray.install();
      icon.calls.clear();

      await tray.setHotkeyUnavailable(true);

      expect(icon.calls, [_setUnavailableIcon, _menuWithStatement]);
      final menu = icon.menus.last;
      expect(menu, hasLength(3));
      expect(
        menu.first.enabled,
        isTrue,
        reason:
            'the tray is the way in *because* the hotkey is not — greying out '
            'the open-panel entry would invert AD-12',
      );
      // The statement sits between the entry it explains and the trailing
      // Quit, so it is the middle line rather than the last one.
      final statement = menu[1];
      expect(statement.enabled, isFalse);
      expect(
        statement.label.toLowerCase(),
        contains('unavailable'),
        reason: 'the menu is the only surface a sentence fits on',
      );
      expect(
        statement.label.toLowerCase(),
        isNot(contains('compositor')),
        reason:
            'the statement must not claim a cause the tray cannot know: three '
            'situations produce this state and only one is a compositor fact '
            '— a wlroots session with no GlobalShortcuts portal, an X11 build '
            'that registers no shortcut yet, and a backend that could not be '
            'reached. TrayPort takes a bool and carries none of that.',
      );
    });

    test('AD-12: hotkeys becoming available again restores the icon and drops '
        'the statement', () async {
      await tray.install();
      await tray.setHotkeyUnavailable(true);
      icon.calls.clear();

      await tray.setHotkeyUnavailable(false);

      expect(icon.calls, [_setAvailableIcon, _menuWithoutStatement]);
      expect(icon.menus.last, hasLength(2));

      await tray.setHotkeyStatus(
        const HotkeyTrayStatus(
          outcome: HotkeyRetained(
            HotkeyRegistration(
              effective: null,
              authority: BindingAuthority.compositor,
            ),
          ),
          rebindRefused: false,
        ),
      );
      expect(icon.calls.last, _menuWithStatement);
      expect(icon.calls, isNot(contains(_setUnavailableIcon)));
      expect(icon.menus.last.first.enabled, isTrue);
      expect(
        icon.menus.last[1].label,
        contains('previous shortcut still works'),
      );

      await tray.setHotkeyStatus(
        const HotkeyTrayStatus(
          outcome: HotkeyBound(
            HotkeyRegistration(
              effective: null,
              authority: BindingAuthority.compositor,
            ),
          ),
          rebindRefused: false,
        ),
      );
      expect(icon.menus.last, hasLength(2));

      await tray.setHotkeyStatus(
        const HotkeyTrayStatus(
          outcome: HotkeyUnavailable(
            cause: HotkeyUnavailableCause.revoked,
            message: 'the desktop removed the shortcut',
          ),
          rebindRefused: false,
        ),
      );
      expect(icon.calls.last, _menuWithStatement);
      expect(icon.menus.last[1].label, contains('removed'));
    });

    test('AD-12: a repeated startup state is inert and cannot replace a '
        'newer typed status', () async {
      await tray.install();
      await tray.setHotkeyUnavailable(true);
      icon.calls.clear();

      await tray.setHotkeyUnavailable(true);

      expect(icon.calls, isEmpty);

      final staleMenu = Completer<void>();
      icon.setMenuGate = staleMenu;
      final startupResult = tray.setHotkeyUnavailable(false);
      await pumpEventQueue();
      icon.setMenuGate = null;
      final backendChange = tray.setHotkeyStatus(
        const HotkeyTrayStatus(
          outcome: HotkeyUnavailable(
            cause: HotkeyUnavailableCause.revoked,
            message: 'the desktop revoked the binding',
          ),
          rebindRefused: false,
        ),
      );
      await pumpEventQueue();
      expect(
        icon.calls,
        [_setAvailableIcon, _menuWithoutStatement],
        reason: 'the newer status waits for the older native push to settle',
      );
      staleMenu.complete();
      await Future.wait([startupResult, backendChange]);
      expect(icon.calls.last, _menuWithStatement);
      expect(icon.menus.last[1].label, contains('removed'));
      icon.calls.clear();

      await tray.setHotkeyUnavailable(false);

      expect(icon.calls, isEmpty);
      expect(icon.menus.last[1].label, contains('removed'));
    });

    test('AD-12: a state reported before install() pushes nothing, and the '
        'install then renders it', () async {
      await tray.setHotkeyUnavailable(true);

      expect(
        icon.calls,
        isEmpty,
        reason:
            'a menu pushed before the icon exists dereferences a null '
            'AppIndicator* in native code — DaemonStartup.bindHotkey does not '
            'know whether the tray was installed, so the rule lives here',
      );

      await tray.install();

      expect(icon.calls, [_setUnavailableIcon, _menuWithStatement]);
    });

    test('AD-12: a seam that refuses the swap rejects the call rather than '
        'reporting a state it never showed', () async {
      await tray.install();
      icon.setMenuError = StateError('the indicator went away');

      await expectLater(
        tray.setHotkeyUnavailable(true),
        throwsA(isA<StateError>()),
      );

      // The second half of this test's own name, which the rejection alone
      // does not check. A refused push must not be remembered as rendered, or
      // the short-circuit blocks every retry: the icon would sit on the
      // degraded PNG with no statement line behind it, and the port offers no
      // way to ask what state the tray believes it is showing, so nothing
      // could ever put it right.
      icon.calls.clear();
      icon.setMenuError = null;

      await tray.setHotkeyUnavailable(true);

      expect(icon.calls, [
        _setUnavailableIcon,
        _menuWithStatement,
      ], reason: 'a refused swap is not a rendered state');
    });

    test('AD-12: a swap refused halfway is repaired by the opposite state too '
        '— the direction that decides whether a working hotkey stays '
        'advertised as broken', () async {
      // The retry above asks for the *same* state again. This is the other
      // direction, and it is the one that ships wrong: `setIcon` lands, so the
      // degraded PNG is already on screen, and `setMenu` is then refused. A
      // short-circuit that compares the request rather than what was rendered
      // sees "already false" and refuses the one call that would restore the
      // ordinary icon — leaving a working hotkey advertised as unavailable
      // with no route back through the port.
      await tray.install();
      icon.setMenuError = StateError('the indicator went away');
      await expectLater(
        tray.setHotkeyUnavailable(true),
        throwsA(isA<StateError>()),
      );
      expect(
        icon.calls.last,
        _menuWithStatement,
        reason: 'the icon swap landed before the menu was refused',
      );
      icon.calls.clear();
      icon.setMenuError = null;

      await tray.setHotkeyUnavailable(false);

      expect(icon.calls, [_setAvailableIcon, _menuWithoutStatement]);
    });
  });

  group('teardown (CAP-7)', () {
    test('CAP-7: dispose() disposes the seam, closes panelRequests, and leaves '
        'a later call with nothing to do', () async {
      await tray.install();
      var closed = false;
      tray.panelRequests.listen(null, onDone: () => closed = true);

      await tray.dispose();
      await pumpEventQueue();

      expect(icon.disposed, isTrue);
      expect(closed, isTrue);

      icon.calls.clear();
      await tray.install();
      await tray.setHotkeyUnavailable(true);

      expect(
        icon.calls,
        isEmpty,
        reason:
            'a torn-down tray must not push a menu at an indicator the '
            'daemon has already destroyed',
      );
    });

    test('CAP-7: a seam that refuses to close is logged, and disposal still '
        'completes — a daemon that cannot exit is the worse failure', () async {
      await tray.install();
      icon.disposeError = StateError('the channel is gone');

      await expectLater(tray.dispose(), completes);

      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('disposing the tray icon'));
    });

    test('CAP-7: a subscription cancel that rejects does not skip the two '
        'teardown steps behind it', () async {
      // The first of the three guarded steps, and the only one the fake could
      // not reach until it grew a cancel hook. Without its guard the throw
      // ends `dispose()` before `panelRequests` is closed and before the seam
      // is disposed — so `removeListener` and `destroy()` never run, the
      // indicator is never taken down, and `_disposed` has already latched, so
      // no retry can reach them either.
      await tray.install();
      icon.cancelError = StateError('the selection stream is gone');

      await expectLater(tray.dispose(), completes);

      expect(icon.disposed, isTrue, reason: 'the seam is still disposed');
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('tray selection subscription'));
    });

    test('AD-15: a logger whose own sink is gone does not turn a tray guard '
        'into an unhandled error (CAP-1)', () async {
      // Every recovery site here reports by logging, which makes the logger
      // the one port whose failure cannot be reported. `StderrLogger` ends in
      // `_sink.writeln`, which throws on a broken pipe — ordinary for a
      // systemd-launched daemon whose journal socket went away. Two of these
      // sites run inside stream callbacks, where a throw becomes an uncaught
      // zone error rather than reaching anyone, and the third is on the
      // shutdown path, where it would break `dispose()`'s documented promise
      // never to throw.
      final unhandled = <Object>[];
      final throwingLogger = ThrowingLogger();

      await runZonedGuarded(() async {
        final ownIcon = FakeTrayIcon();
        final resilient = TrayManagerTray(
          icon: ownIcon,
          logger: throwingLogger,
        );
        await resilient.install();

        ownIcon.emitSelection(_inventedKey);
        await pumpEventQueue();
        ownIcon.emitSelectionError(StateError('the seam broke its promise'));
        await pumpEventQueue();

        ownIcon.cancelError = StateError('the selection stream is gone');
        ownIcon.disposeError = StateError('the channel is gone');
        await expectLater(resilient.dispose(), completes);
      }, (error, _) => unhandled.add(error));
      await pumpEventQueue();

      expect(
        throwingLogger.attempts,
        hasLength(4),
        reason:
            'the unknown key, the errored stream, the refused cancel and the '
            'refused seam close each still tried to report',
      );
      expect(unhandled, isEmpty);
    });
  });

  group('the icon assets (AD-12)', () {
    // A real gate, not bookkeeping: `setIcon` takes a path resolved inside the
    // installed `flutter_assets`, so a renamed file or an undeclared directory
    // produces a broken indicator with no error anywhere — nothing else in the
    // suite would notice until a user saw a blank tray.
    test('AD-12: both icon assets exist and are readable 32x32 PNGs', () {
      // Existence alone would pass for a zero-length or truncated file, which
      // is exactly the failure this gate's own comment says it exists to
      // catch: the indicator renders nothing and reports nothing. The
      // signature and the IHDR dimensions both live in the first 24 bytes, so
      // checking them needs no decoder.
      for (final asset in [
        TrayManagerTray.availableIconAsset,
        TrayManagerTray.unavailableIconAsset,
      ]) {
        final file = File(asset);
        expect(
          file.existsSync(),
          isTrue,
          reason: '$asset is what the adapter hands to the indicator',
        );

        final bytes = file.readAsBytesSync();
        expect(
          bytes.length,
          greaterThanOrEqualTo(24),
          reason: '$asset is too short to carry a PNG header',
        );
        expect(
          bytes.sublist(0, 8),
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          reason: '$asset does not start with the PNG signature',
        );
        expect(
          String.fromCharCodes(bytes.sublist(12, 16)),
          'IHDR',
          reason: '$asset has no IHDR where the format puts it',
        );
        expect(
          [_bigEndian(bytes, 16), _bigEndian(bytes, 20)],
          [32, 32],
          reason: '$asset is not the 32x32 a tray indicator expects',
        );
      }
    });

    test('AD-12: the two states differ in their pixels, not merely their '
        'bytes', () {
      // Comparing the encoded files would compare compression output. Both
      // PNGs come from one generator whose only difference is a flag feeding
      // `zlib.compress`, so two visually identical glyphs that happened to
      // deflate differently would satisfy a raw byte comparison — and the
      // whole point of this gate is that the degraded state is *visibly*
      // distinguishable, which is the icon half of AD-12.
      expect(
        _pixels(TrayManagerTray.availableIconAsset),
        isNot(_pixels(TrayManagerTray.unavailableIconAsset)),
        reason: 'the icon half of AD-12 is the difference a user can see',
      );
    });

    test('AD-12: pubspec.yaml declares the icon directory under '
        'flutter: assets:', () {
      final directory =
          '${TrayManagerTray.availableIconAsset.split('/').take(2).join('/')}/';

      // Scoped to the block, not searched across the file: a commented-out
      // line, or the same entry parked under `dependencies:`, satisfies a bare
      // substring check while leaving the asset out of `flutter_assets` — the
      // exact failure this gate exists to catch.
      expect(
        declaredFlutterAssets(),
        contains(directory),
        reason:
            'an undeclared asset is not in flutter_assets, so the indicator '
            'would be created with a path to nothing',
      );
    });
  });
}

/// The decompressed image data of the PNG at [asset] — its pixels, not its
/// encoding.
///
/// Walks the chunk stream from the 8-byte signature, concatenates every `IDAT`
/// payload (the format permits the image to be split across several) and
/// inflates the result. What comes back is the raw scanline data, which two
/// different glyphs cannot share however they were compressed.
List<int> _pixels(String asset) {
  final bytes = File(asset).readAsBytesSync();
  final idat = <int>[];

  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = _bigEndian(bytes, offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (type == 'IDAT') {
      idat.addAll(bytes.sublist(offset + 8, offset + 8 + length));
    }
    if (type == 'IEND') {
      break;
    }
    // 4 length + 4 type + payload + 4 CRC.
    offset += 12 + length;
  }

  expect(idat, isNotEmpty, reason: '$asset carries no IDAT chunk');
  return zlib.decode(idat);
}

/// The four-byte big-endian integer at [offset] — how PNG writes every length
/// and dimension.
int _bigEndian(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

/// The keys the shipped menu gives its entries, read back from the menu the
/// adapter actually pushed rather than restated here — the adapter owns them,
/// and a test that hard-coded one would still pass if the two drifted apart.
String _openPanelKey(FakeTrayIcon icon) => icon.menus.last.first.key;
String _quitKey(FakeTrayIcon icon) => icon.menus.last.last.key;

/// The unavailability statement, which sits between the entry it explains and
/// the trailing Quit.
String _statementKey(FakeTrayIcon icon) => icon.menus.last[1].key;

/// A key no menu this adapter builds carries. Named rather than written inline
/// so it cannot drift into one the adapter later adds — which is exactly what
/// `'quit'` did once the Quit entry landed.
///
/// Deliberately not a plausible entry name: `'open-settings'` would re-arm that
/// same drift the day a Settings entry lands, and these rows would go on
/// claiming to test the unknown-key branch while testing the settings one.
const String _inventedKey = 'no-entry-carries-this-key';

const String _setAvailableIcon =
    'setIcon(${TrayManagerTray.availableIconAsset})';
const String _setUnavailableIcon =
    'setIcon(${TrayManagerTray.unavailableIconAsset})';
const String _menuWithoutStatement =
    'setMenu(open-panel:enabled, quit:enabled)';
const String _menuWithStatement =
    'setMenu(open-panel:enabled, hotkey-unavailable:disabled, quit:enabled)';

/// Stands in for a vendor exception whose `toString()` carries the payload that
/// caused it — the reason the [Logger] port bans logging one.
final class _PayloadCarryingError implements Exception {
  @override
  String toString() => 'failed: the user private clipboard text';
}
