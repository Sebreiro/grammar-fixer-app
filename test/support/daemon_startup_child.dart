import 'dart:async';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/portal_app_id_regime.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/persistence/drift_correction_repository.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/daemon_startup.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/stderr_logger.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/system_clock.dart';

import '../fakes/fake_hotkey_registrar.dart';

/// Child entry point for AD-14's "a second launch exits 0 having built
/// nothing".
///
/// It has to be a second process for two reasons. `exit()` cannot be observed
/// from inside the process that calls it, so the exit code is only readable
/// from a parent; and the artefacts the row is about — a seeded `config.json`,
/// a `history.sqlite` — are per-process only if the XDG homes differ, which is
/// what the parent hands over here.
///
/// The pending timer stands in for the Flutter engine's event loop. It is the
/// reason `main.dart` cannot simply *return* when it is not the daemon: with
/// something keeping the VM alive, a caller that returns instead of exiting
/// hangs, and this child would then be killed by the parent's timeout rather
/// than reporting 0. That makes the exit contract an assertion rather than a
/// comment.
///
/// Output contract: `not-the-daemon` or `daemon` on stdout.
Future<void> main(List<String> arguments) async {
  final keepAlive = Timer(const Duration(minutes: 5), () {});

  final startup = await DaemonStartup.begin(
    paths: AppPaths.fromEnvironment(Platform.environment),
    environment: Platform.environment,
    logger: StderrLogger(clock: const SystemClock()),
    // The real seam is behind a Flutter import and this child runs under
    // `dart run`; the fake is inert and never grabbed here, which is all this
    // row needs — it is about what startup builds before the hotkey, not about
    // the hotkey.
    registrar: FakeHotkeyRegistrar(),
    // Unsandboxed, and resolved the same way the daemon resolves it: this
    // child runs under `dart run` in an ordinary container, where
    // `/.flatpak-info` is absent. The regime is irrelevant to what this row
    // asserts — it never reaches a portal — but it is answered honestly rather
    // than pinned, so a sandboxed run of this child would take the same branch
    // the daemon would.
    portalAppIdRegime: PortalAppIdRegime.fromEnvironment(
      Platform.environment,
      fileExists: (path) => File(path).existsSync(),
    ),
    // The shipped bound, restated: this child runs under `dart run` and cannot
    // import `main.dart`, and it never reaches a portal anyway.
    requestTimeout: const Duration(seconds: 5),
  );

  if (startup == null) {
    stdout.writeln('not-the-daemon');
    exit(0);
  }

  stdout.writeln('daemon');
  // Drift opens the database file lazily, on the first statement — so without
  // a read here the control run would create no `history.sqlite` either, and
  // the parent's "the second launch created no database" assertion would pass
  // for the wrong reason. One `recent()` is the cheapest thing that makes the
  // artefact observable, and it goes through the CAP-7 port rather than around
  // it.
  await DriftCorrectionRepository(startup.database).recent(limit: 1);
  // The control run opens real adapters, so it closes them: an unclosed
  // AppDatabase keeps a background isolate alive, which is the whole reason
  // shutdown has an order at all.
  await startup.database.close();
  await startup.configStore.close();
  await startup.hotkey.dispose();
  await startup.lock.dispose();
  keepAlive.cancel();
  exit(0);
}
