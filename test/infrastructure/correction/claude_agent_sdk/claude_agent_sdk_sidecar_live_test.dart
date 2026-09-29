@Tags(['live'])
library;

import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart';
import 'package:test/test.dart';

import '../../../fakes/fake_logger.dart';

/// One live smoke against the real Python sidecar, the real
/// `claude_agent_sdk`, and the real `claude` CLI. Skips — with the reason —
/// on machines missing any of the three, so CI without the toolchain stays
/// green while a developer machine actually exercises the AD-19 chain.
///
/// Tagged `live` and excluded from the routine gate: it spawns a nested
/// `claude` process, which is not something a merge check should do. It is
/// also the only check that a real model honours the shipped prompt's END
/// sentinel, so run it deliberately after changing that prompt.
///
/// Every skip reason here is a banner rather than a sentence: it names the row,
/// the dependency that is missing, and the exact command that makes the row
/// run. A skip that says only "not available" is worth almost nothing in a run
/// output — the reader still has to open the file to learn what to install.
void main() {
  final interpreterPath = '${Directory.current.path}/.venv-sidecar/bin/python3';
  const sidecarPath = 'assets/sidecar/claude_agent_sdk_sidecar.py';
  final skipReason = _liveDependencySkipReason(interpreterPath);
  final unprovisionedSkipReason = _unprovisionedInterpreterSkipReason();

  // Printed as well as returned as a `skip:` reason, because a skip string on
  // a tagged file reaches nobody: `--exclude-tags=live` drops the suite before
  // the reason exists, and `--run-skipped` — the opt-in the README teaches —
  // suppresses the skip and runs the row instead. Loading this suite at all
  // now reports its own status.
  for (final banner in [skipReason, unprovisionedSkipReason]) {
    if (banner != null) {
      // The run output is the whole point; a logger would write somewhere
      // nobody reading a test run is looking.
      // ignore: avoid_print
      print(banner);
    }
  }

  test(
    'CAP-5/CAP-9: the live sidecar streams three tagged registers into '
    'CorrectionCompleted with non-empty suggestions',
    () async {
      // The shipped prompt, not an inline copy: this smoke exists to prove
      // that what the app actually ships makes a real model produce a
      // parseable, END-terminated response.
      const preset = Preset(
        id: DefaultAppConfig.shippedPresetId,
        providerId: ClaudeAgentSdkCorrectionProvider.providerId,
        model: DefaultAppConfig.shippedModel,
        systemPrompt: DefaultAppConfig.shippedSystemPrompt,
      );
      final provider = ClaudeAgentSdkCorrectionProvider(
        interpreterPath: interpreterPath,
        sidecarPath: sidecarPath,
        logger: FakeLogger(),
      );

      final events = await provider
          .correct(text: 'i has went to the store yesterday', preset: preset)
          .toList();

      final failures = events.whereType<CorrectionFailed>();
      expect(
        failures,
        isEmpty,
        reason: failures
            .map((failure) => '${failure.kind.name}: ${failure.message}')
            .join('; '),
      );
      final completed = events.whereType<CorrectionCompleted>().single;
      expect(completed.suggestions, hasLength(3));
      for (final suggestion in completed.suggestions) {
        expect(
          suggestion.text,
          isNotEmpty,
          reason: '${suggestion.register.name} must carry a rewrite',
        );
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'AD-19: the real sidecar under an interpreter without claude_agent_sdk '
    'reports providerUnavailable naming the package',
    () async {
      // The stub rows cover the adapter's half of this; only the real script
      // proves the sidecar's own import guard emits a well-formed error line
      // — and it needs no `claude` CLI, so it runs on more machines than the
      // smoke above.
      const preset = Preset(
        id: 'unprovisioned-preset',
        providerId: 'claude-agent-sdk',
        model: 'claude-sonnet-5',
        systemPrompt: 'never reaches the model',
      );
      final provider = ClaudeAgentSdkCorrectionProvider(
        interpreterPath: _sdkFreeInterpreter,
        sidecarPath: sidecarPath,
        logger: FakeLogger(),
      );

      final events = await provider
          .correct(text: 'input under test', preset: preset)
          .toList();

      expect(events, hasLength(1));
      final failure = events.single as CorrectionFailed;
      expect(failure.kind, CorrectionFailureKind.providerUnavailable);
      expect(failure.message, contains('claude_agent_sdk'));
      // The adapter's own deadline is 60 s, well past dart test's 30 s
      // default, so without this a slow real run dies as an unattributable
      // framework timeout instead of as whatever actually went wrong.
    },
    skip: unprovisionedSkipReason,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// A stock interpreter is the realistic "user pointed at the wrong python"
/// case: it exists, it runs, and it cannot import the SDK.
const _sdkFreeInterpreter = '/usr/bin/python3';

/// The command that runs everything in this file. Repeated into every skip
/// reason, because the tag exclusion is the *other* half of why a row here did
/// not run and a reader of the output cannot see it.
const _enablingCommand =
    'dart test --tags=live --run-skipped '
    'test/infrastructure/correction/claude_agent_sdk/'
    'claude_agent_sdk_sidecar_live_test.dart';

String? _unprovisionedInterpreterSkipReason() {
  const row = 'the unprovisioned-host row (AD-19 import guard)';
  if (!File(_sdkFreeInterpreter).existsSync()) {
    return 'SKIPPED $row: this machine has no stock interpreter at '
        '$_sdkFreeInterpreter to stand in for an unprovisioned host. '
        'Install a system python3, then run: $_enablingCommand';
  }
  final probe = Process.runSync(_sdkFreeInterpreter, [
    '-c',
    'import claude_agent_sdk',
  ]);
  if (probe.exitCode == 0) {
    return 'SKIPPED $row: $_sdkFreeInterpreter can import claude_agent_sdk, '
        'so it cannot stand in for an unprovisioned host. Point '
        '_sdkFreeInterpreter at an interpreter without the package, then '
        'run: $_enablingCommand';
  }
  return null;
}

/// Synchronous probes only: the skip decision must exist before `test()`
/// registers, so this runs in `main()` with `Process.runSync`.
String? _liveDependencySkipReason(String interpreterPath) {
  const row = 'the live end-to-end smoke (CAP-5/CAP-9)';
  if (!File(interpreterPath).existsSync()) {
    return 'SKIPPED $row: the pinned sidecar environment is missing at '
        '$interpreterPath. Create it with tool/provision_sidecar.sh, then '
        'run: $_enablingCommand';
  }
  final importProbe = Process.runSync(interpreterPath, [
    '-c',
    'import claude_agent_sdk',
  ]);
  if (importProbe.exitCode != 0) {
    return 'SKIPPED $row: $interpreterPath cannot import claude_agent_sdk '
        '(${importProbe.stderr}). Fix it with tool/provision_sidecar.sh, '
        'then run: $_enablingCommand';
  }
  try {
    final cliProbe = Process.runSync('claude', ['--version']);
    if (cliProbe.exitCode != 0) {
      return 'SKIPPED $row: the claude CLI is on PATH but not runnable '
          '(${cliProbe.stderr}). Reinstall it, then run: $_enablingCommand';
    }
  } on ProcessException {
    return 'SKIPPED $row: the claude CLI is not on PATH. Install it with '
        '`npm install -g @anthropic-ai/claude-code`, then run: '
        '$_enablingCommand';
  }
  return null;
}
