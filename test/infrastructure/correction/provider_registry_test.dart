import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/provider_registry.dart';
import 'package:test/test.dart';

import '../../fakes/fake_logger.dart';

/// Unit tests for `ProviderRegistry` (AD-15): a map lookup, never a switch,
/// and construction that never throws however incomplete the config is.
void main() {
  late FakeLogger logger;
  late ProviderRegistry registry;

  setUp(() {
    logger = FakeLogger();
    registry = ProviderRegistry(logger: logger);
  });

  test('AD-15: create returns the claude-agent-sdk provider for its id', () {
    const config = ProviderConfig(
      settings: {
        ClaudeAgentSdkCorrectionProvider.interpreterSettingsKey:
            '/usr/bin/python3',
        ClaudeAgentSdkCorrectionProvider.sidecarSettingsKey: '/opt/s.py',
      },
    );

    final provider = registry.create(
      ClaudeAgentSdkCorrectionProvider.providerId,
      config,
    );

    expect(provider, isA<ClaudeAgentSdkCorrectionProvider>());
  });

  test('AD-15: create returns null for an unknown provider id', () {
    const config = ProviderConfig(settings: {});

    expect(registry.create('no-such-provider', config), isNull);
  });

  group('the AD-19 timeout setting', () {
    test('AD-19: an absent timeoutMillis silently takes the adapter '
        'default', () {
      const config = ProviderConfig(settings: {});

      registry.create(ClaudeAgentSdkCorrectionProvider.providerId, config);

      expect(logger.lines, isEmpty);
    });

    test('AD-19: a timeoutMillis that is not a number falls back to the '
        'adapter default and logs a warning naming the key', () {
      const config = ProviderConfig(
        settings: {ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey: 'soon'},
      );

      final provider = registry.create(
        ClaudeAgentSdkCorrectionProvider.providerId,
        config,
      );

      expect(provider, isA<ClaudeAgentSdkCorrectionProvider>());
      final warning = _singleWarning(logger);
      expect(
        warning.message,
        allOf(
          contains(ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey),
          contains('not a whole number'),
        ),
      );
      expect(
        warning.context?['value'],
        'soon',
        reason: 'the operator has to be able to see what they typed',
      );
    });

    test('AD-19: a non-positive timeoutMillis is rejected as too small, not '
        'as a typo — a zero deadline would fail every correction '
        'instantly', () {
      const config = ProviderConfig(
        settings: {ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey: '0'},
      );

      registry.create(ClaudeAgentSdkCorrectionProvider.providerId, config);

      expect(
        _singleWarning(logger).message,
        contains('greater than zero'),
        reason:
            'telling an operator that "0" is unparseable sends them hunting '
            'for a typo instead of looking at what they meant',
      );
    });

    test('AD-19: a timeoutMillis that overflows Duration into a negative is '
        'rejected — it would fire the deadline instantly', () {
      // int.tryParse takes this happily; Duration(milliseconds: it) yields a
      // negative inMilliseconds, so every correction would fail as timeout.
      const config = ProviderConfig(
        settings: {
          ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey:
              '9223372036854775807',
        },
      );

      registry.create(ClaudeAgentSdkCorrectionProvider.providerId, config);

      expect(_singleWarning(logger).message, contains('at most'));
    });

    test('AD-19: an absurdly large timeoutMillis is rejected — it would '
        'silently reinstate the hang AD-19 exists to prevent', () {
      const config = ProviderConfig(
        settings: {
          ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey:
              '999999999999999999',
        },
      );

      registry.create(ClaudeAgentSdkCorrectionProvider.providerId, config);

      expect(_singleWarning(logger).message, contains('at most'));
    });

    test('AD-19: a few-hundred-millisecond timeout is accepted — the bound is '
        'an upper one only, and the adapter tests configure 250 ms', () {
      const config = ProviderConfig(
        settings: {ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey: '250'},
      );

      registry.create(ClaudeAgentSdkCorrectionProvider.providerId, config);

      expect(logger.lines, isEmpty);
    });
  });

  test('AD-19: a provider built from empty settings never throws — it emits '
      'providerUnavailable on the first correct()', () async {
    const config = ProviderConfig(settings: {});
    const preset = Preset(
      id: 'test-preset',
      providerId: 'claude-agent-sdk',
      model: 'test-model',
      systemPrompt: 'unused',
    );

    final provider = registry.create(
      ClaudeAgentSdkCorrectionProvider.providerId,
      config,
    );
    if (provider == null) {
      fail('the registry must know its shipped provider id');
    }
    final events = await provider
        .correct(text: 'input under test', preset: preset)
        .toList();

    expect(events, hasLength(1));
    expect(
      events.single,
      isA<CorrectionFailed>().having(
        (failure) => failure.kind,
        'kind',
        CorrectionFailureKind.providerUnavailable,
      ),
    );
  });
}

/// Every rejection row cares about the same shape: exactly one warning, and
/// what it says.
({String level, String message, Map<String, Object?>? context}) _singleWarning(
  FakeLogger logger,
) {
  final warnings = logger.lines
      .where((line) => line.level == 'warning')
      .toList();
  expect(warnings, hasLength(1));
  return warnings.single;
}
