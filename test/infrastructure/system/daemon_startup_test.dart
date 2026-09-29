import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_status.dart';
import 'package:hotkey_grammar_corrector/src/domain/tray/tray_port.dart';
import 'package:hotkey_grammar_corrector/src/domain/tray/hotkey_tray_status.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/unconfigured_correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_grab.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/portal_app_id_regime.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/x11_global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/daemon_startup.dart';
import 'package:test/test.dart';

import '../../support/child_process.dart';
import '../../fakes/fake_hotkey_registrar.dart';
import '../../fakes/fake_logger.dart';
import '../../fakes/fake_tray_port.dart';

/// The pre-Flutter half of the composition root: the order AD-14 mandates,
/// and every way a degraded environment must still produce a running daemon.
///
/// This is the part of `main.dart` a test can actually execute. What is left
/// there — the Riverpod container, the window, the signal handlers — needs a
/// binding and a display; everything decided before that lives here.
///
/// Pure Dart: no Flutter binding (AGENTS.md §7).
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('daemon-startup-'));
  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  /// A fresh XDG layout under [root], with a runtime directory unique to this
  /// process so the abstract socket name cannot collide with another suite's.
  AppPaths pathsFor(String name, {String? runtimeDirectory}) {
    return AppPaths.fromEnvironment({
      'HOME': '${root.path}/$name',
      'XDG_CONFIG_HOME': '${root.path}/$name/config',
      'XDG_DATA_HOME': '${root.path}/$name/data',
      'XDG_RUNTIME_DIR':
          runtimeDirectory ?? '${root.path}/run-$pid-${root.path.hashCode}',
    });
  }

  late FakeHotkeyRegistrar registrar;

  setUp(() => registrar = FakeHotkeyRegistrar());

  Future<DaemonStartup> beginAt(
    AppPaths paths, {
    Map<String, String> environment = const {},
    FakeLogger? logger,
  }) async {
    final startup = await DaemonStartup.begin(
      paths: paths,
      environment: environment,
      logger: logger ?? FakeLogger(),
      registrar: registrar,
      portalAppIdRegime: PortalAppIdRegime.hostRegistry,
      requestTimeout: _shippedCallBudget,
    );
    if (startup == null) {
      fail('the lock was free, so begin() should have returned a daemon');
    }
    addTearDown(() async {
      await startup.database.close();
      await startup.configStore.close();
      await startup.hotkey.dispose();
      await startup.lock.dispose();
    });
    return startup;
  }

  group('the lock is free (AD-14)', () {
    test('AD-14: startup acquires the lock and hands back everything the '
        'graph needs', () async {
      final logger = FakeLogger();

      final startup = await beginAt(pathsFor('daemon'), logger: logger);

      expect(startup.configStore.current, DefaultAppConfig.build());
      expect(startup.active.preset, DefaultAppConfig.shippedPreset);
      expect(startup.active.provider, isA<ClaudeAgentSdkCorrectionProvider>());
      expect(
        logger.lines.where((line) => line.level != 'info'),
        isEmpty,
        reason: 'a clean environment starts up without a single warning',
      );
    });

    test('CAP-8: the config file is seeded on a first run, so there is one '
        'to edit', () async {
      final paths = pathsFor('daemon');

      await beginAt(paths);

      expect(File(paths.configFile).existsSync(), isTrue);
    });

    // One startup per test, deliberately: Dart's `ServerSocket.bind` refuses a
    // second unix bind from the same process even on a different address
    // (OS Error: "The shared flag to bind() needs to be `true` if binding
    // multiple times on the same path"), so two live daemons cannot coexist in
    // one isolate. The daemon only ever binds one.
    test(
      'AD-9: a Wayland session gets the portal adapter, and only it',
      () async {
        final startup = await beginAt(
          pathsFor('wayland'),
          environment: const {'XDG_SESSION_TYPE': 'wayland'},
        );

        expect(startup.hotkey, isA<WaylandPortalGlobalHotkey>());
        expect(
          registrar.calls,
          isEmpty,
          reason:
              'the portal adapter ignores the registrar, so a Wayland session '
              'never touches the X11 seam — it is handed one only because AD-9 '
              'makes the choice here rather than in main.dart',
        );
      },
    );

    test('AD-9: the Wayland branch is built without a session bus being '
        'touched at all', () async {
      // Fact 1 of the adapter's design, and a requirement on every `dart test`
      // run rather than a nicety: `DBusClient` is inert until its first call, so
      // constructing the portal adapter connects to nothing. If it connected
      // eagerly the connect would be an unawaited future inside a synchronous
      // constructor, which surfaces as an unhandled zone error — and in this
      // container it surfaces as a *failing* one, because there is no session
      // bus to reach (`DBUS_SESSION_BUS_ADDRESS` is unset and `/run/user/` is
      // empty). So this row bites here, and every startup on an X11 machine
      // would otherwise be paying for a socket it never uses.
      final logger = FakeLogger();
      final errorsInZone = <Object>[];
      DaemonStartup? startup;

      await runZonedGuarded(() async {
        startup = await beginAt(
          pathsFor('wayland-no-bus'),
          environment: const {'XDG_SESSION_TYPE': 'wayland'},
          logger: logger,
        );
      }, (error, stack) => errorsInZone.add(error));
      await pumpEventQueue();

      expect(startup?.hotkey, isA<WaylandPortalGlobalHotkey>());
      expect(
        errorsInZone,
        isEmpty,
        reason: 'construction must not reach for a bus, or ask for a socket',
      );
      expect(
        logger.lines.where((line) => line.level != 'info'),
        isEmpty,
        reason: 'and it must not report anything either — it did nothing',
      );
    });

    test('AD-12: a DBUS_SESSION_BUS_ADDRESS this build cannot read still '
        'starts a daemon, in its own process', () async {
      // In a child because `DBusClient.session()` reads `Platform.environment`,
      // which no in-process test can change — and the production path is exactly
      // the one worth driving: `DBusAddress` raises `FormatException` for any
      // value with no `transport:` prefix, and that throw would happen inside
      // `begin`'s try, which releases the AD-14 address and rethrows. Both
      // spellings people actually produce: an empty variable, and the bare
      // socket path.
      for (final address in const ['', '/run/user/1000/bus']) {
        final childHome = '${root.path}/bus-address-${address.hashCode}';

        final child = await runGuardedChild(
          dartExecutable,
          ['run', 'test/support/wayland_bus_address_child.dart'],
          environment: {
            'HOME': childHome,
            'XDG_CONFIG_HOME': '$childHome/config',
            'XDG_DATA_HOME': '$childHome/data',
            'XDG_RUNTIME_DIR': '${root.path}/run-bus-${address.hashCode}',
            'XDG_SESSION_TYPE': 'wayland',
            'DBUS_SESSION_BUS_ADDRESS': address,
          },
        );

        expect(
          child.exitCode,
          0,
          reason:
              'a bus address this build cannot parse must not stop the daemon: '
              'there would be no tray and no panel to fix the setting from. '
              'address: "$address", stderr: ${child.stderr}',
        );
        final lines = (child.stdout as String).trim().split('\n');
        expect(
          lines.first,
          'daemon:unavailable',
          reason: 'AD-12 makes it a value the tray renders, not a throw',
        );
        expect(
          lines.last,
          startsWith('message:'),
          reason: 'the child prints the sentence as well as the outcome type',
        );
        expect(
          lines.last,
          contains('tray menu'),
          reason:
              'AD-12 asks for a sentence naming the way in that still works, '
              'and this is the one refusal path no in-process test can reach — '
              'the type alone would leave the wording unobserved. address: '
              '"$address"',
        );
        expect(
          child.stderr,
          contains('DBUS_SESSION_BUS_ADDRESS'),
          reason:
              'the diagnosis is emitted at construction rather than at bind '
              'time precisely because the user own configuration is what '
              'decided it, so it has to name the variable',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('AD-9: an X11 session gets the X11 adapter, and only it', () async {
      final startup = await beginAt(
        pathsFor('x11'),
        environment: const {'XDG_SESSION_TYPE': 'x11'},
      );

      expect(startup.hotkey, isA<X11GlobalHotkey>());
    });

    test('AD-9: the registrar main.dart built is the one the X11 adapter '
        'grabs through', () async {
      // Type alone would be satisfied by an adapter that built a second seam
      // of its own — which would leave main.dart holding one that never grabs
      // and the abort path releasing nothing.
      final startup = await beginAt(
        pathsFor('x11-registrar'),
        environment: const {'XDG_SESSION_TYPE': 'x11'},
      );

      await startup.hotkey.bind(
        HotkeyBinding(
          modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
          key: 'G',
        ),
      );

      expect(registrar.calls, ['grab(HotkeyGrab(control+shift 0x0007000a))']);
    });
  });

  group('the lock is held (AD-14)', () {
    test('AD-14: a second startup builds nothing — no config file, no '
        'database, no provider, no hotkey adapter', () async {
      final runtimeDirectory = '${root.path}/run-contended';
      await beginAt(pathsFor('holder', runtimeDirectory: runtimeDirectory));
      // A different XDG home, same runtime directory: the two derive the same
      // abstract address, so the second is a genuine second launch, but its
      // artefacts land somewhere the first cannot have created them.
      final secondPaths = pathsFor(
        'second',
        runtimeDirectory: runtimeDirectory,
      );
      final logger = FakeLogger();

      final second = await DaemonStartup.begin(
        paths: secondPaths,
        environment: const {},
        logger: logger,
        registrar: registrar,
        portalAppIdRegime: PortalAppIdRegime.hostRegistry,
        requestTimeout: _shippedCallBudget,
      );

      expect(second, isNull);
      expect(
        File(secondPaths.configFile).existsSync(),
        isFalse,
        reason:
            'AD-13 seeds a config file on load; not reaching load is what '
            'proves nothing past the lock ran',
      );
      expect(File(secondPaths.databaseFile).existsSync(), isFalse);
      expect(logger.lines.single.level, 'info');
    });

    test(
      'AD-14, CAP-1: the holder receives exactly one show request',
      () async {
        final runtimeDirectory = '${root.path}/run-signalled';
        final holder = await beginAt(
          pathsFor('holder', runtimeDirectory: runtimeDirectory),
        );
        final requests = <void>[];
        holder.lock.showRequests.listen(requests.add);

        await DaemonStartup.begin(
          paths: pathsFor('second', runtimeDirectory: runtimeDirectory),
          environment: const {},
          logger: FakeLogger(),
          registrar: registrar,
          portalAppIdRegime: PortalAppIdRegime.hostRegistry,
          requestTimeout: _shippedCallBudget,
        );
        await pumpEventQueue();

        expect(requests, hasLength(1));
      },
    );

    test('AD-14: a second launch exits 0, in its own process, with an event '
        'loop that would otherwise keep it alive', () async {
      final runtimeDirectory = '${root.path}/run-child';
      await beginAt(pathsFor('holder', runtimeDirectory: runtimeDirectory));
      final childHome = '${root.path}/child';

      final child = await runGuardedChild(
        dartExecutable,
        ['run', 'test/support/daemon_startup_child.dart'],
        environment: {
          'HOME': childHome,
          'XDG_CONFIG_HOME': '$childHome/config',
          'XDG_DATA_HOME': '$childHome/data',
          'XDG_RUNTIME_DIR': runtimeDirectory,
        },
      );

      expect(child.exitCode, 0);
      expect((child.stdout as String).trim(), 'not-the-daemon');
      expect(
        File(
          '$childHome/config/hotkey-grammar-corrector/config.json',
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          '$childHome/data/hotkey-grammar-corrector/history.sqlite',
        ).existsSync(),
        isFalse,
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('AD-14: the same child on a free address becomes the daemon and '
        'does create both files — the control that keeps the row above '
        'from passing vacuously', () async {
      final childHome = '${root.path}/control';

      final child = await runGuardedChild(
        dartExecutable,
        ['run', 'test/support/daemon_startup_child.dart'],
        environment: {
          'HOME': childHome,
          'XDG_CONFIG_HOME': '$childHome/config',
          'XDG_DATA_HOME': '$childHome/data',
          'XDG_RUNTIME_DIR': '${root.path}/run-control',
        },
      );

      expect(child.exitCode, 0);
      expect((child.stdout as String).trim(), 'daemon');
      expect(
        File(
          '$childHome/config/hotkey-grammar-corrector/config.json',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '$childHome/data/hotkey-grammar-corrector/history.sqlite',
        ).existsSync(),
        isTrue,
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('the environment is degraded', () {
    test('AD-14: an unusable lock address logs its own warning and the '
        'daemon starts anyway', () async {
      // Over the 108-byte sun_path limit, which the lock reports rather than
      // risks: the kernel truncates an over-long abstract name, and two
      // runtime directories would then look like one instance.
      final paths = pathsFor('unlocked', runtimeDirectory: '/run/${'d' * 200}');
      final logger = FakeLogger();

      final startup = await beginAt(paths, logger: logger);

      expect(startup.configStore.current, DefaultAppConfig.build());
      final warnings = logger.lines.where((line) => line.level == 'warning');
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('single-instance'));
    });

    test('AD-13: a malformed config file logs the load warning, falls back '
        'to defaults, and startup continues', () async {
      final paths = pathsFor('malformed');
      File(paths.configFile)
        ..createSync(recursive: true)
        ..writeAsStringSync('{ this is not json');
      final logger = FakeLogger();

      final startup = await beginAt(paths, logger: logger);

      expect(startup.configStore.current, DefaultAppConfig.build());
      expect(startup.active.preset, DefaultAppConfig.shippedPreset);
      final warnings = logger.lines.where((line) => line.level == 'warning');
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('not valid JSON'));
    });

    test('AD-19: a config naming a provider this build does not ship still '
        'starts, and fails on the first correction instead', () async {
      final paths = pathsFor('unknown-provider');
      File(paths.configFile)
        ..createSync(recursive: true)
        ..writeAsStringSync(_configNaming('some-other-backend'));
      final logger = FakeLogger();

      final startup = await beginAt(paths, logger: logger);

      expect(startup.active.provider, isA<UnconfiguredCorrectionProvider>());
      expect(startup.active.preset.providerId, 'some-other-backend');
    });

    test('AD-13: a warned path resolution reaches the log before anything '
        'uses a path', () async {
      final paths = AppPaths.fromEnvironment({
        'HOME': '${root.path}/warned',
        'XDG_CONFIG_HOME': 'not-absolute',
        'XDG_RUNTIME_DIR': '${root.path}/run-warned',
      });
      final logger = FakeLogger();

      await beginAt(paths, logger: logger);

      expect(
        logger.lines.first.message,
        contains('XDG_CONFIG_HOME'),
        reason:
            'a user who set the variable would otherwise edit a config '
            'file the daemon never reads',
      );
    });
  });

  group('the startup bind (AD-12)', () {
    test('CAP-1, AD-10: on an X11 session with a registrar that takes the '
        'grab, the startup bind succeeds and the tray is told hotkeys are '
        'available', () async {
      final logger = FakeLogger();
      final tray = FakeTrayPort();
      addTearDown(tray.dispose);
      final startup = await beginAt(
        pathsFor('bind-x11'),
        environment: const {'XDG_SESSION_TYPE': 'x11'},
        logger: logger,
      );

      final outcome = await startup.bindHotkey(tray: tray);

      expect(
        outcome,
        HotkeyBound(
          HotkeyRegistration(
            effective: DefaultAppConfig.build().hotkeyBinding,
            authority: BindingAuthority.application,
          ),
        ),
        reason:
            'the first time this has been true: every earlier build reported '
            'unavailable from both adapters unconditionally',
      );
      expect(tray.hotkeyUnavailable, isFalse);
      expect(
        logger.lines.where((line) => line.level != 'info'),
        isEmpty,
        reason: 'a successful bind warns about nothing',
      );
    });

    test('AD-12: a backend that reports unavailable tells the tray, and the '
        'daemon stays up', () async {
      // Driven through the X11 branch on purpose, now that both adapters have
      // real backends. The Wayland arm would reach for whatever session bus the
      // machine running the suite happens to have — a portal dialog on a
      // developer's desktop, nothing here — so the branch under test would be
      // the environment rather than the code. What this row is about is
      // `bindHotkey`, which is display-server agnostic.
      final logger = FakeLogger();
      final tray = FakeTrayPort();
      addTearDown(tray.dispose);
      registrar.grabError = StateError('this session refused the grab');
      final startup = await beginAt(
        pathsFor('bind'),
        environment: const {'XDG_SESSION_TYPE': 'x11'},
        logger: logger,
      );

      final outcome = await startup.bindHotkey(tray: tray);

      expect(outcome, isA<HotkeyUnavailable>());
      expect(tray.hotkeyUnavailable, isTrue);
      final warnings = logger.lines.where((line) => line.level == 'warning');
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('unavailable'));
    });

    test('AD-12: the binding that is requested is the one config holds — the '
        'preference survives to the next launch', () async {
      final tray = FakeTrayPort();
      addTearDown(tray.dispose);
      final startup = await beginAt(pathsFor('bind-config'));

      await startup.bindHotkey(tray: tray);

      expect(
        startup.configStore.current.hotkeyBinding,
        DefaultAppConfig.build().hotkeyBinding,
      );
      expect(
        registrar.grabs.single,
        HotkeyGrab(
          modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
          usbHidUsage: 0x0007000a,
        ),
        reason:
            'the combination the file holds is the one that reaches the '
            'backend, not a compiled-in default',
      );
    });

    test('AD-12: a hotkey backend that throws instead of reporting '
        'unavailability is reduced to a value and logged', () async {
      final logger = FakeLogger();

      final outcome = await DaemonStartup.requestBinding(
        hotkey: const _ThrowingHotkey(),
        binding: DefaultAppConfig.build().hotkeyBinding,
        logger: logger,
      );

      expect(
        outcome,
        isA<HotkeyUnavailable>(),
        reason:
            'an unhandled rejection here would be an uncaught async error '
            'during startup, with no log line and nothing for the tray',
      );
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(
        errors.single.context,
        {'error_type': 'StateError'},
        reason: 'the type only — a vendor error toString carries its payload',
      );
    });

    test('AD-12: the value that guard produces is the one the tray is told '
        'about, so a throwing backend still shows as unavailable', () async {
      final tray = FakeTrayPort();
      addTearDown(tray.dispose);
      final logger = FakeLogger();
      final unavailable = await DaemonStartup.requestBinding(
        hotkey: const _ThrowingHotkey(),
        binding: DefaultAppConfig.build().hotkeyBinding,
        logger: logger,
      );
      registrar.grabError = StateError('this session refused the grab');
      final startup = await beginAt(
        pathsFor('bind-throws'),
        environment: const {'XDG_SESSION_TYPE': 'x11'},
        logger: logger,
      );

      await startup.bindHotkey(tray: tray);

      expect(unavailable, isA<HotkeyUnavailable>());
      expect(tray.hotkeyUnavailable, isTrue);
    });

    test('AD-12: the Wayland adapter on an unreachable bus is reduced to a '
        'value by the same guard, without a portal dialog anywhere', () async {
      // The rows above drive `bindHotkey` through the X11 arm on purpose — the
      // Wayland arm's default client would reach whatever session bus the machine
      // running this suite has, which on a developer's desktop means a real
      // portal dialog. This keeps the Wayland branch's AD-12 reduction observed
      // by pointing one at a socket that cannot exist, which is also the state
      // of this container.
      final logger = FakeLogger();
      final hotkey = WaylandPortalGlobalHotkey(
        client: DBusClient(
          DBusAddress.unix(path: '${root.path}/there-is-no-bus-here'),
        ),
        appIdRegime: PortalAppIdRegime.hostRegistry,
        requestTimeout: _shippedCallBudget,
        logger: logger,
      );
      addTearDown(hotkey.dispose);

      final outcome = await DaemonStartup.requestBinding(
        hotkey: hotkey,
        binding: DefaultAppConfig.build().hotkeyBinding,
        logger: logger,
      );

      expect((outcome as HotkeyUnavailable).message, contains('tray menu'));
      expect(
        logger.lines.where(
          (line) => line.message.contains('threw instead of reporting'),
        ),
        isEmpty,
        reason:
            'the adapter honoured AD-12 itself; the startup guard had nothing '
            'to absorb',
      );
    });

    test('AD-12: a tray that rejects is logged, and startup still '
        'completes', () async {
      final logger = FakeLogger();
      final startup = await beginAt(pathsFor('bind-no-tray'), logger: logger);

      await expectLater(
        startup.bindHotkey(tray: const _RejectingTray()),
        completes,
      );

      expect(
        logger.lines.where(
          (line) => line.message.contains('tray could not be told'),
        ),
        hasLength(1),
      );
    });
  });
}

/// A valid config whose active preset names [providerId], described but not
/// shipped — AD-19's "the daemon must still start" case.
String _configNaming(String providerId) =>
    '''
{
  "providers": {"$providerId": {"settings": {}}},
  "presets": [
    {
      "id": "elsewhere",
      "providerId": "$providerId",
      "model": "some-model",
      "systemPrompt": "correct this"
    }
  ],
  "activePresetId": "elsewhere",
  "hotkeyBinding": {"modifiers": ["control", "shift"], "key": "G"}
}
''';

/// A tray whose calls reject, standing in for a tray backend that is present
/// but broken — the shared fake accepts everything.
final class _RejectingTray implements TrayPort {
  const _RejectingTray();

  @override
  Future<void> install() => Future<void>.error(StateError('no tray'));

  @override
  Stream<void> get panelRequests => const Stream<void>.empty();

  @override
  Stream<void> get quitRequests => const Stream<void>.empty();

  @override
  Future<void> setHotkeyUnavailable(bool unavailable) =>
      Future<void>.error(StateError('no tray'));

  @override
  Future<void> setHotkeyStatus(HotkeyTrayStatus status) =>
      Future<void>.error(StateError('no tray'));
}

/// A backend that rejects rather than reporting unavailability — the AD-12
/// breach [DaemonStartup.requestBinding] exists to absorb. The two shipped
/// stubs both honour the contract, so it has to be injected.
final class _ThrowingHotkey implements GlobalHotkey {
  const _ThrowingHotkey();

  @override
  Stream<void> get activations => const Stream<void>.empty();

  @override
  Stream<HotkeyBindOutcome> get bindingChanges =>
      const Stream<HotkeyBindOutcome>.empty();

  /// An adapter whose `bind` rejects has produced no outcome, so there is no
  /// status for it to answer with either.
  @override
  HotkeyStatus? get current => null;

  @override
  Future<HotkeyBindOutcome> bind(HotkeyBinding binding) =>
      Future<HotkeyBindOutcome>.error(StateError('the portal is gone'));

  @override
  Future<void> dispose() async {}
}

/// The bound the shipped composition root hands the Wayland adapter
/// (`main.dart`'s `_unresponsiveCallBudget`), restated because `main.dart`
/// needs a binding this suite does not have —
/// `composition_wiring_test.dart` is what holds the two together.
const Duration _shippedCallBudget = Duration(seconds: 5);
