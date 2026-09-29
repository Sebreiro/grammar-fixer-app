import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/portal_app_id_regime.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/daemon_startup.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/stderr_logger.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/system_clock.dart';

import '../fakes/fake_hotkey_registrar.dart';

/// Child entry point for AD-12's "an unreadable `DBUS_SESSION_BUS_ADDRESS` still
/// starts a daemon".
///
/// It has to be a second process for one reason: `DBusClient.session()` reads
/// `Platform.environment`, which no in-process test can change. The parent hands
/// the spelling to try over the environment, so what runs here is the production
/// path — `DaemonStartup.begin` selecting the Wayland arm of `_hotkeyFor`, which
/// constructs `WaylandPortalGlobalHotkey` with no injected client.
///
/// What the row is really about is the *lock*: a throw out of that constructor
/// happens inside `begin`'s try, which releases the AD-14 address and rethrows,
/// so a daemon that cannot parse a bus address would not start at all — no tray,
/// no panel, nothing to fix it from — where AD-12 and the spine's operational
/// envelope both require a degraded start.
///
/// Output contract: two lines on stdout — `daemon:<outcome>`, where `<outcome>`
/// is `unavailable` or `bound`, then `message:<the outcome's message>`. Anything
/// else — including a non-zero exit — is the failure.
///
/// The message is printed because the outcome *type* is only half of what AD-12
/// asks for: the other half is a sentence that names the way in that still
/// works, and this is the one refusal path whose sentence no in-process test can
/// reach. Its diagnostic goes to stderr, where the parent reads it too — the
/// user's own configuration is what caused this one, so it must say which
/// variable.
Future<void> main(List<String> arguments) async {
  final logger = StderrLogger(clock: const SystemClock());
  final startup = await DaemonStartup.begin(
    paths: AppPaths.fromEnvironment(Platform.environment),
    environment: Platform.environment,
    logger: logger,
    // The real X11 seam is behind a Flutter import and this child runs under
    // `dart run`. The Wayland arm ignores it, which is the arm this row takes.
    registrar: FakeHotkeyRegistrar(),
    // Answered the same way the daemon answers it, from this process's own
    // environment. This row's bus address is unreadable, so no portal call is
    // ever made and the branch cannot matter — but pinning it would state a
    // fact about packaging that this child has no business stating.
    portalAppIdRegime: PortalAppIdRegime.fromEnvironment(
      Platform.environment,
      fileExists: (path) => File(path).existsSync(),
    ),
    // The shipped bound, restated: this child runs under `dart run` and cannot
    // import `main.dart`, and it never reaches a portal anyway.
    requestTimeout: const Duration(seconds: 5),
  );
  if (startup == null) {
    stdout.writeln('daemon:not-the-daemon');
    exit(1);
  }

  // The whole AD-12 reduction, through the same static the composition root
  // uses: a hotkey backend that cannot reach a bus resolves to a value.
  final outcome = await DaemonStartup.requestBinding(
    hotkey: startup.hotkey,
    binding: startup.configStore.current.hotkeyBinding,
    logger: logger,
  );
  stdout.writeln(
    'daemon:${outcome is HotkeyUnavailable ? 'unavailable' : 'bound'}',
  );
  stdout.writeln(
    'message:${outcome is HotkeyUnavailable ? outcome.message : ''}',
  );

  await startup.database.close();
  await startup.configStore.close();
  await startup.hotkey.dispose();
  await startup.lock.dispose();
  exit(0);
}
