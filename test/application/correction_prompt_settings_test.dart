import 'dart:async';

import 'package:hotkey_grammar_corrector/src/application/settings_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/settings_state.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:test/test.dart';

import '../fakes/fake_config_store.dart';
import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';

void main() {
  final defaults = DefaultAppConfig.build();
  late FakeConfigStore store;
  late SettingsController controller;
  late FakeGlobalHotkey hotkey;
  final preset = defaults.presets.single;
  final other = Preset(
    id: 'another-preset',
    providerId: preset.providerId,
    model: 'another-model',
    systemPrompt: 'Another prompt.',
  );

  setUp(() {
    store = FakeConfigStore(
      current: defaults.copyWith(presets: [preset, other]),
    );
    hotkey = FakeGlobalHotkey();
    controller = SettingsController(
      configStore: store,
      hotkey: hotkey,
      logger: FakeLogger(),
      registrableKeys: HotkeyKeyCatalogue.registrableKeys(),
    );
  });

  tearDown(() async {
    await controller.dispose();
    store.dispose();
  });

  Future<void> save(String prompt) =>
      controller.changeCorrectionPrompt(preset: preset, systemPrompt: prompt);

  test(
    'CAP-8: saving a prompt retains its model, provider and other presets',
    () async {
      final applied = <AppConfig>[];
      controller.attachConfigListener(applied.add);
      const prompt = '  Correct grammar.\nPreserve intent.\n';
      await save(prompt);
      final edited = store.current.presets.first;
      expect(edited.systemPrompt, prompt);
      expect(edited.id, preset.id);
      expect(edited.model, preset.model);
      expect(edited.providerId, preset.providerId);
      expect(store.current.presets.last, other);
      expect(store.current.providers, defaults.providers);
      expect(store.current.activePresetId, defaults.activePresetId);
      expect(controller.state.config, store.current);
      expect(applied, [store.current]);
      expect(hotkey.bindCalls, isEmpty);
    },
  );

  test('CAP-8: blank prompt is refused without a config write', () async {
    await save(' \n\t');
    expect(store.writes, isEmpty);
    expect(controller.state.config.presets.first, preset);
    expect(controller.state.failure?.kind, SettingsFailureKind.configRejected);
    expect(controller.state.mutationInFlight, isFalse);
  });

  test(
    'CAP-8: failed prompt save keeps the committed prompt and can retry',
    () async {
      store.writeError = StateError('disk is unavailable');
      await save('New prompt.');
      expect(controller.state.config.presets.first, preset);
      expect(
        controller.state.failure?.kind,
        SettingsFailureKind.configWriteFailed,
      );
      store.writeError = null;
      await save('New prompt.');
      expect(controller.state.config.presets.first.systemPrompt, 'New prompt.');
      expect(controller.state.failure, isNull);
    },
  );

  test(
    'CAP-8: a prompt draft cannot overwrite a newly active preset',
    () async {
      store.current = store.current.copyWith(activePresetId: other.id);
      await save('Old preset draft.');
      expect(store.writes, isEmpty);
      expect(store.current.presets.last, other);
      expect(
        controller.state.failure?.kind,
        SettingsFailureKind.configRejected,
      );
      expect(
        controller.state.failure?.message,
        contains('active preset or prompt changed'),
      );
    },
  );

  test('CAP-8: the prompt save shares the settings mutation lock', () async {
    final gate = Completer<void>();
    store.writeGate = gate;
    final first = save('First prompt.');
    expect(controller.state.mutationInFlight, isTrue);
    await save('Second prompt.');
    gate.complete();
    await first;
    expect(store.writes, hasLength(1));
    expect(store.current.presets.first.systemPrompt, 'First prompt.');
  });

  test(
    'CAP-8: a prompt draft cannot overwrite an unseen config edit',
    () async {
      final external = Preset(
        id: preset.id,
        providerId: preset.providerId,
        model: preset.model,
        systemPrompt: 'Unseen external edit.',
      );
      store.current = store.current.copyWith(presets: [external, other]);
      await save('My old draft.');
      expect(store.writes, isEmpty);
      expect(store.current.presets.first, external);
      expect(
        controller.state.failure?.kind,
        SettingsFailureKind.configRejected,
      );
    },
  );
}
