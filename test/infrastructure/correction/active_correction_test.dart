import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/active_correction.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/provider_registry.dart';
import 'package:test/test.dart';

import '../../fakes/fake_logger.dart';

/// AD-5's resolution of the single active pair, and the two ways a config can
/// name something the daemon cannot honour. Neither may block startup: AD-19
/// requires the tray, panel and settings to stay reachable so the user can fix
/// the setting.
///
/// Pure Dart: no Flutter binding (AGENTS.md §7).
void main() {
  group('the active pair resolves (AD-5, AD-15)', () {
    test('CAP-8: a config whose active preset names a shipped provider yields '
        'that preset and a registry-built provider', () {
      final logger = FakeLogger();

      final active = ActiveCorrection.resolve(
        config: DefaultAppConfig.build(),
        registry: ProviderRegistry(logger: logger),
        logger: logger,
      );

      expect(active.preset, DefaultAppConfig.shippedPreset);
      expect(active.provider, isA<ClaudeAgentSdkCorrectionProvider>());
      expect(
        logger.lines.where((line) => line.level == 'error'),
        isEmpty,
        reason: 'a well-formed config resolves without complaint',
      );
    });

    test('AD-15: selection is the registry map lookup — a second described '
        'provider that is not active is never built', () {
      final logger = FakeLogger();
      final config = _config(
        presets: const [_shippedPreset, _otherPreset],
        activePresetId: _shippedPreset.id,
      );

      final active = ActiveCorrection.resolve(
        config: config,
        registry: ProviderRegistry(logger: logger),
        logger: logger,
      );

      expect(active.preset.id, _shippedPreset.id);
      expect(active.provider, isA<ClaudeAgentSdkCorrectionProvider>());
    });
  });

  group('the active preset names a provider this build cannot build', () {
    test('AD-19: an unknown provider id yields exactly one '
        'CorrectionFailed(providerUnavailable) and then closes', () async {
      final logger = FakeLogger();
      final config = _config(
        providers: const {'no-such-provider': ProviderConfig(settings: {})},
        presets: const [_otherPreset],
        activePresetId: _otherPreset.id,
      );

      final active = ActiveCorrection.resolve(
        config: config,
        registry: ProviderRegistry(logger: logger),
        logger: logger,
      );
      final events = await active.provider
          .correct(text: 'i has a text', preset: active.preset)
          .toList();

      expect(events, hasLength(1));
      expect(
        events.single,
        isA<CorrectionFailed>()
            .having(
              (failure) => failure.kind,
              'kind',
              CorrectionFailureKind.providerUnavailable,
            )
            .having(
              (failure) => failure.message,
              'message',
              contains('no-such-provider'),
            ),
      );
      expect(
        logger.lines.where((line) => line.level == 'warning'),
        hasLength(1),
        reason: 'a config naming an unshipped provider warns at startup',
      );
    });

    test('AD-19: a provider the config never described also degrades rather '
        'than blocking startup', () async {
      final logger = FakeLogger();
      final config = _config(
        providers: const {},
        presets: const [_shippedPreset],
        activePresetId: _shippedPreset.id,
      );

      final active = ActiveCorrection.resolve(
        config: config,
        registry: ProviderRegistry(logger: logger),
        logger: logger,
      );
      final events = await active.provider
          .correct(text: 'i has a text', preset: active.preset)
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

    test('AD-3: the unavailable provider stays stateless — a second '
        'correction gets its own single terminal event', () async {
      final logger = FakeLogger();
      final active = ActiveCorrection.resolve(
        config: _config(
          providers: const {},
          presets: const [_shippedPreset],
          activePresetId: _shippedPreset.id,
        ),
        registry: ProviderRegistry(logger: logger),
        logger: logger,
      );

      final first = await active.provider
          .correct(text: 'one', preset: active.preset)
          .toList();
      final second = await active.provider
          .correct(text: 'two', preset: active.preset)
          .toList();

      expect(first, hasLength(1));
      expect(second, hasLength(1));
    });
  });

  group('the active preset id names no preset', () {
    test('AD-5: a dangling activePresetId falls back to the shipped preset '
        'and logs the id it could not find', () {
      final logger = FakeLogger();
      final config = _config(
        presets: const [_shippedPreset],
        activePresetId: 'preset-that-was-deleted',
      );

      final active = ActiveCorrection.resolve(
        config: config,
        registry: ProviderRegistry(logger: logger),
        logger: logger,
      );

      expect(active.preset, DefaultAppConfig.shippedPreset);
      expect(active.provider, isA<ClaudeAgentSdkCorrectionProvider>());
      final errors = logger.lines.where((line) => line.level == 'error');
      expect(errors, hasLength(1));
      expect(
        errors.single.context?['active_preset_id'],
        'preset-that-was-deleted',
      );
    });
  });
}

const Preset _shippedPreset = Preset(
  id: 'default-formal-casual-shorter',
  providerId: ClaudeAgentSdkCorrectionProvider.providerId,
  model: 'claude-sonnet-5',
  systemPrompt: 'correct this',
);

const Preset _otherPreset = Preset(
  id: 'preset-elsewhere',
  providerId: 'no-such-provider',
  model: 'some-model',
  systemPrompt: 'correct this too',
);

AppConfig _config({
  Map<String, ProviderConfig> providers = const {
    ClaudeAgentSdkCorrectionProvider.providerId: ProviderConfig(settings: {}),
    'no-such-provider': ProviderConfig(settings: {}),
  },
  required List<Preset> presets,
  required String activePresetId,
}) {
  return AppConfig(
    providers: providers,
    presets: presets,
    activePresetId: activePresetId,
    hotkeyBinding: HotkeyBinding(
      modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
      key: 'G',
    ),
  );
}
