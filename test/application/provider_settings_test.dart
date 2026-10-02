import 'dart:async';

import 'package:hotkey_grammar_corrector/src/application/settings_controller.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/secret_write_result.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:test/test.dart';

import '../fakes/fake_config_store.dart';
import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';
import '../fakes/fake_provider_key_writer.dart';

void main() {
  late FakeConfigStore config;
  late FakeProviderKeyWriter writer;
  late FakeLogger logger;
  late SettingsController controller;

  setUp(() {
    config = FakeConfigStore(current: DefaultAppConfig.build());
    writer = FakeProviderKeyWriter();
    logger = FakeLogger();
    controller = SettingsController(
      configStore: config,
      registrableKeys: HotkeyKeyCatalogue.registrableKeys(),
      hotkey: FakeGlobalHotkey(),
      logger: logger,
    )..attachProviderKeyWriter(writer);
  });
  tearDown(() async {
    await controller.dispose();
    config.dispose();
  });

  test('CAP-8: an entered API key is saved only to the keyring', () async {
    final before = config.current;
    expect(await controller.saveApiKey(' private-key '), isTrue);
    expect(writer.writes.single, (
      providerId: ProviderConfig.compatibleProviderId,
      apiKey: 'private-key',
    ));
    expect(config.writes, isEmpty);
    expect(config.current, before);
    expect(logger.lines, isEmpty);
    expect(controller.state.failure, isNull);
  });

  test(
    'CAP-13: a failed keyring save can be retried without a config write',
    () async {
      writer.result = SecretWriteResult.unavailable;
      expect(await controller.saveApiKey('private-key'), isFalse);
      expect(controller.state.failure?.message, contains('keyring'));
      writer.result = SecretWriteResult.saved;
      expect(await controller.saveApiKey('private-key'), isTrue);
      expect(controller.state.failure, isNull);
      expect(config.writes, isEmpty);
    },
  );

  test(
    'CAP-13: vendor errors do not leak entered keys and release controls',
    () async {
      writer.error = StateError('private-key');
      expect(await controller.saveApiKey('private-key'), isFalse);
      expect(controller.state.failure?.message, isNot(contains('private-key')));
      expect(logger.lines.toString(), isNot(contains('private-key')));
      expect(controller.state.mutationInFlight, isFalse);
      expect(await controller.saveApiKey(' '), isFalse);
      expect(writer.writes, hasLength(1));
    },
  );

  test(
    'CAP-13: saving endpoint settings does not retire a failed keyring save',
    () async {
      writer.result = SecretWriteResult.unavailable;
      await controller.saveApiKey('private-key');
      final failure = controller.state.failure;
      await controller.configureCompatibleProvider(
        baseUrl: 'https://api.example/v1',
        model: 'model',
      );
      expect(controller.state.failure, failure);
      writer.result = SecretWriteResult.saved;
      await controller.saveApiKey('private-key');
      expect(controller.state.failure, isNull);
    },
  );

  test('CAP-8: a keyring prompt keeps settings mutations serialized', () async {
    final gate = Completer<void>();
    writer.gate = gate;
    final saving = controller.saveApiKey('private-key');
    expect(controller.state.mutationInFlight, isTrue);
    await controller.changeActivePreset('anything');
    expect(await controller.saveApiKey('second-key'), isFalse);
    expect(config.writes, isEmpty);
    gate.complete();
    expect(await saving, isTrue);
    expect(controller.state.mutationInFlight, isFalse);
    expect(writer.writes, hasLength(1));
  });

  test(
    'CAP-8: first URL setup creates a full preset and retains Claude',
    () async {
      final original = config.current;
      await controller.configureCompatibleProvider(
        baseUrl: ' https://api.example/v1 ',
        model: ' url-model ',
      );
      final preset = controller.state.activePreset;
      expect(preset?.providerId, ProviderConfig.compatibleProviderId);
      expect(preset?.model, 'url-model');
      expect(preset?.systemPrompt, original.presets.single.systemPrompt);
      expect(
        config.current.providers['claude-agent-sdk'],
        original.providers['claude-agent-sdk'],
      );
      expect(config.current.presets.first, original.presets.single);
      expect(controller.state.compatibleBaseUrl, 'https://api.example/v1');
      await controller.changeActiveProvider('claude-agent-sdk');
      expect(config.current.activePresetId, original.activePresetId);
      await controller.changeActiveProvider(
        ProviderConfig.compatibleProviderId,
      );
      expect(controller.state.activePreset, preset);
      expect(config.current.presets, hasLength(2));
    },
  );

  test('CAP-13: failed first-time setup retains the active provider', () async {
    final original = config.current;
    await controller.configureCompatibleProvider(
      baseUrl: 'https://api.example/v1',
      model: ' ',
    );
    expect(config.writes, isEmpty);
    config.writeError = StateError('cannot save');
    await controller.configureCompatibleProvider(
      baseUrl: 'https://api.example/v1',
      model: 'model',
    );
    expect(config.current, original);
    expect(controller.state.failure, isNotNull);
  });
}
