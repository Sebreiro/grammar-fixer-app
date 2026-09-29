import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/sidecar_host_paths.dart';
import 'package:test/test.dart';

/// Reports, inside the routine gate, that the live smoke did not run — and why.
///
/// The live smoke's own skip reasons are `skip:` strings on a `live`-tagged
/// file, and there is no invocation that shows them to anybody:
///
/// * the routine command and CI pass `--exclude-tags=live`, which drops the
///   suite before its reasons are ever produced;
/// * `dart test --tags=live <file>` prints the *suite-level* reason from
///   `dart_test.yaml`, not the per-row dependency reasons;
/// * `--run-skipped`, which the README teaches, suppresses the dependency
///   skips entirely, so the rows execute instead of reporting.
///
/// So the condition the deferred item was filed for — an end-to-end check that
/// skips silently on every machine — survived writing better skip reasons. This
/// row is the fix that actually reaches an operator: it is untagged, it always
/// runs, and it prints what the live chain currently resolves to on this host
/// plus the exact command that exercises it.
///
/// It deliberately spawns nothing. The `claude` CLI is located by walking
/// `PATH` rather than by running it, because reporting on a dependency must not
/// become a reason to start it.
void main() {
  test('AD-19: the live end-to-end smoke is excluded from this command, and '
      'the run output says so', () {
    final interpreter = File(_venvInterpreter);
    final interpreterReady = interpreter.existsSync();
    final sdkReady = interpreterReady && _canImportSdk();
    final cli = _firstOnPath('claude');

    // print, not a doc comment: reaching the output of the command a developer
    // and CI actually run is this row's only job.
    // ignore: avoid_print
    print(
      'NOT RUN HERE — $_liveSuite is tagged `live`, which the routine command '
      'and CI both exclude, so nothing below was exercised end to end.\n'
      '  sidecar environment : ${interpreterReady ? _venvInterpreter : "missing — run tool/provision_sidecar.sh"}\n'
      '  claude_agent_sdk    : ${sdkReady ? "importable" : "not importable"}\n'
      '  claude CLI          : ${cli ?? "not on PATH"}\n'
      '  run it with         : $_enablingCommand',
    );

    // The row still has to be able to fail, or it is a print statement wearing
    // a test's clothes. What it pins is that the command it prints names a
    // suite that exists — a renamed or deleted live file would otherwise leave
    // this advice pointing at nothing. Deliberately the only assertion: an
    // earlier version also checked that `_enablingCommand` contained
    // `_liveSuite` and `--tags=live`, both of which it is built by interpolating
    // and could therefore never fail.
    expect(
      File(_liveSuite).existsSync(),
      isTrue,
      reason: 'the command this row prints must name a suite that exists',
    );
  });
}

const String _venvInterpreter = SidecarHostPaths.repoRelativeInterpreterPath;

const String _liveSuite =
    'test/infrastructure/correction/claude_agent_sdk/'
    'claude_agent_sdk_sidecar_live_test.dart';

const String _enablingCommand =
    'dart test --tags=live --run-skipped $_liveSuite';

bool _canImportSdk() =>
    Process.runSync(_venvInterpreter, [
      '-c',
      'import claude_agent_sdk',
    ]).exitCode ==
    0;

/// The first executable named [command] on `PATH`, or null.
///
/// Resolved by looking rather than by running: this file reports on the live
/// chain and must never be the thing that starts a `claude` process.
String? _firstOnPath(String command) {
  for (final directory in (Platform.environment['PATH'] ?? '').split(':')) {
    if (directory.isEmpty) {
      continue;
    }
    final candidate = File('$directory/$command');
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  return null;
}
