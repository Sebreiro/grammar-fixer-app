import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/json_config_store.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/sidecar_host_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/provider_registry.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/shared/register_tagged_prompt.dart';
import 'package:test/test.dart';

import '../../fakes/fake_logger.dart';

/// The drift check between the shipped prompt, the parser that enforces it,
/// and the adapter that reads its settings. The parser may only require a
/// closing sentinel while these hold: a prompt that stopped asking for one
/// would turn every real correction into a malformedResponse.
void main() {
  group('the shipped prompt (AD-16, CAP-9)', () {
    test('CAP-4 CAP-9: fresh installs use the same variant requirements '
        'as existing configured presets', () {
      expect(
        DefaultAppConfig.shippedSystemPrompt,
        endsWith(RegisterTaggedPrompt.responseFormat),
      );
    });

    test('AD-16: the prompt names all three register tags in enum '
        'declaration order', () {
      const prompt = DefaultAppConfig.shippedSystemPrompt;

      final positions = [
        for (final register in SuggestionRegister.values)
          prompt.indexOf('${register.name.toUpperCase()}:'),
      ];

      expect(
        positions,
        everyElement(greaterThanOrEqualTo(0)),
        reason: 'every AD-16 tag must appear in the prompt',
      );
      final sorted = [...positions]..sort();
      expect(
        positions,
        sorted,
        reason: 'the tags must be asked for in SuggestionRegister order',
      );
    });

    test('AD-16: the prompt mandates the parser own end sentinel as the final '
        'line', () {
      const prompt = DefaultAppConfig.shippedSystemPrompt;
      const sentinel = RegisterTaggedStreamParser.endSentinel;

      expect(prompt, contains('\n$sentinel\n'));
      expect(
        prompt.indexOf('\n$sentinel\n'),
        greaterThan(prompt.indexOf('SHORTER:')),
        reason: 'the sentinel closes the response, it does not open it',
      );
      expect(
        prompt,
        contains(
          RegExp('the final line is exactly $sentinel', caseSensitive: false),
        ),
      );
    });

    test('CAP-5: a response obeying the shipped prompt completes, and the '
        'same response cut off before the sentinel does not', () async {
      const parser = RegisterTaggedStreamParser();
      const body = 'FORMAL: a\nCASUAL: b\nSHORTER: c\n';

      final complete = await parser
          .parse(
            Stream.value('$body${RegisterTaggedStreamParser.endSentinel}\n'),
          )
          .toList();
      final truncated = await parser.parse(Stream.value(body)).toList();

      expect(complete.last, isA<CorrectionCompleted>());
      expect(
        truncated.last,
        isA<CorrectionFailed>().having(
          (failure) => failure.kind,
          'kind',
          CorrectionFailureKind.malformedResponse,
        ),
      );
    });
  });

  group('the shipped config (AD-5, AD-15)', () {
    test('CAP-8: the defaults survive the config store own validation and '
        'round-trip through the file', () async {
      final tempDir = Directory.systemTemp.createTempSync('default_config_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final paths = AppPaths.fromEnvironment({
        'XDG_CONFIG_HOME': '${tempDir.path}/config',
        'XDG_DATA_HOME': '${tempDir.path}/data',
        'XDG_RUNTIME_DIR': '${tempDir.path}/run',
      });
      final store = JsonConfigStore(
        paths: paths,
        defaults: DefaultAppConfig.build(),
      );
      addTearDown(store.close);

      // A first load seeds the defaults; a second store reads that file back.
      await store.load();
      final reloaded = await JsonConfigStore(
        paths: paths,
        defaults: DefaultAppConfig.build(),
      ).load();

      expect(reloaded.warning, isNull);
      expect(reloaded.config.activePresetId, DefaultAppConfig.shippedPresetId);
      expect(
        reloaded.config.presets.single.systemPrompt,
        DefaultAppConfig.shippedSystemPrompt,
      );
      expect(
        reloaded.config.hotkeyBinding.modifiers,
        DefaultAppConfig.build().hotkeyBinding.modifiers,
      );
    });

    test('AD-15: the active preset resolves to a shipped provider whose '
        'settings carry every key the adapter reads', () {
      final config = DefaultAppConfig.build();
      final preset = config.presets.singleWhere(
        (candidate) => candidate.id == config.activePresetId,
      );
      final providerConfig = config.providers[preset.providerId];
      if (providerConfig == null) {
        fail('the active preset must name a described provider');
      }

      final provider = ProviderRegistry(
        logger: FakeLogger(),
      ).create(preset.providerId, providerConfig);

      expect(provider, isA<ClaudeAgentSdkCorrectionProvider>());
      expect(
        providerConfig.settings.keys,
        containsAll(<String>[
          ClaudeAgentSdkCorrectionProvider.interpreterSettingsKey,
          ClaudeAgentSdkCorrectionProvider.sidecarSettingsKey,
          ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey,
        ]),
        reason: 'no compiled-in constant may stand in for an AD-19 setting',
      );
    });

    test('AD-19: the settings map is the one home for the timeout and the '
        'two paths', () {
      final config = DefaultAppConfig.build();
      final provider =
          config.providers[ClaudeAgentSdkCorrectionProvider.providerId];
      if (provider == null) {
        fail('the shipped provider id must be described in the defaults');
      }
      final settings = provider.settings;

      expect(
        int.tryParse(
          settings[ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey] ?? '',
        ),
        DefaultAppConfig.timeoutMillis,
      );
      expect(
        settings[ClaudeAgentSdkCorrectionProvider.interpreterSettingsKey],
        DefaultAppConfig.interpreterPath(),
      );
      expect(
        settings[ClaudeAgentSdkCorrectionProvider.sidecarSettingsKey],
        DefaultAppConfig.sidecarPath(),
      );
    });

    test('AD-5: the shipped preset is the one the defaults make active, so '
        'the composition root\'s dangling-id backstop is the shipped pair', () {
      final config = DefaultAppConfig.build();

      expect(
        DefaultAppConfig.shippedPreset.id,
        DefaultAppConfig.shippedPresetId,
      );
      expect(config.activePresetId, DefaultAppConfig.shippedPreset.id);
      expect(config.presets, [DefaultAppConfig.shippedPreset]);
    });

    test('AD-19: the two derived paths both resolve to something that exists '
        'on the machine running the suite', () {
      // The derivations themselves — including the installed-bundle branch —
      // are covered by sidecar_host_paths_test.dart. What this row adds is
      // that the values the defaults actually seed are real on this host.
      //
      // The precondition is asserted rather than assumed: a test runner with
      // a bundle beside it would take the other branch, and without this the
      // row would fail as an unexplained value mismatch instead of saying
      // that the toolchain layout moved.
      final runnerBundle =
          '${_directoryOf(Platform.resolvedExecutable)}/'
          '${SidecarHostPaths.bundleAssetRoot}';
      expect(
        Directory(runnerBundle).existsSync(),
        isFalse,
        reason:
            'this row assumes the test runner ships no flutter_assets bundle '
            'of its own; $runnerBundle now exists, so the seeded value is no '
            'longer the repo-relative one',
      );

      final seededScript = DefaultAppConfig.sidecarPath();
      expect(
        seededScript,
        '${Directory.current.path}/'
        '${SidecarHostPaths.repoRelativeScriptPath}',
        reason:
            'the seeded value is persisted and read back by a process with a '
            'different working directory, so it has to be absolute',
      );
      expect(File(seededScript).existsSync(), isTrue);
    });

    test('AD-19: the seeded interpreter is one of the two legal answers, and '
        'the provisioned one can actually import the SDK', () {
      // Split from the row above, which used to `return` here and so asserted
      // silently less on one of two hosts with nothing in the output saying
      // which branch it took.
      //
      // And the check is an import, not an existence test: a half-provisioned
      // `.venv-sidecar` — the state a failed `provision_sidecar.sh` leaves
      // behind — has an interpreter on disk that cannot import
      // `claude_agent_sdk`, and "the seeded value is real on this host" is not
      // a claim a file's existence supports.
      final seededInterpreter = DefaultAppConfig.interpreterPath();

      if (seededInterpreter == SidecarHostPaths.interpreterCommand) {
        expect(
          File(
            '${Directory.current.path}/'
            '${SidecarHostPaths.repoRelativeInterpreterPath}',
          ).existsSync(),
          isFalse,
          reason:
              'the bare command name is the answer only when no provisioned '
              'environment was found',
        );
        return;
      }

      expect(
        seededInterpreter,
        '${Directory.current.path}/'
        '${SidecarHostPaths.repoRelativeInterpreterPath}',
      );
      expect(
        Process.runSync(seededInterpreter, const [
          '-c',
          'import claude_agent_sdk',
        ]).exitCode,
        0,
        reason:
            'the interpreter the defaults seed must be able to run the '
            'sidecar; re-run tool/provision_sidecar.sh',
      );
    });

    test('the shipped configuration is immutable, so the one instance the '
        'daemon keeps as its fallback cannot be rewritten', () {
      // As a `static const AppConfig` field this was enforced by the language.
      // Two settings became host-derived, which made the const impossible, and
      // neither AppConfig nor ProviderConfig copies or wraps what it is handed —
      // so without the wrapping the guarantee would have quietly become a
      // convention on exactly the instance that is shared for the whole
      // lifetime of the process.
      final config = DefaultAppConfig.build();
      final provider =
          config.providers[ClaudeAgentSdkCorrectionProvider.providerId]!;

      expect(
        () => config.providers['another'] = provider,
        throwsUnsupportedError,
      );
      expect(
        () =>
            provider.settings[ClaudeAgentSdkCorrectionProvider
                    .interpreterSettingsKey] =
                '/tmp/rogue',
        throwsUnsupportedError,
      );
    });
  });
}

/// The directory part of a Linux path — the same arithmetic the derivation
/// does, repeated here only to state this row's precondition.
String _directoryOf(String path) => path.substring(0, path.lastIndexOf('/'));
