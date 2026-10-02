import 'dart:io';

import 'package:hotkey_grammar_corrector/src/application/settings_controller.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/secret_store.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/secret_write_result.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/config_fallback_provider_key_writer.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/json_config_store.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/provider_secret_fields.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/api_key_resolver.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/api_key_source.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:test/test.dart';

import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';
import '../fakes/fake_provider_key_writer.dart';

void main() {
  test(
    'CAP-8: fallback keys serve the next correction and survive restart privately',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'api_key_fallback_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final paths = AppPaths.fromEnvironment({
        'XDG_CONFIG_HOME': directory.path,
        'XDG_DATA_HOME': '${directory.path}/data',
        'XDG_RUNTIME_DIR': '${directory.path}/run',
      });
      final defaults = DefaultAppConfig.build();
      final store = JsonConfigStore(paths: paths, defaults: defaults);
      addTearDown(store.close);
      await store.load();
      final keyring = FakeProviderKeyWriter()
        ..result = SecretWriteResult.unavailable;
      final logger = FakeLogger();
      final hotkey = FakeGlobalHotkey();
      final activations = hotkey.activations.listen((_) {});
      addTearDown(() async {
        await activations.cancel();
        await hotkey.dispose();
      });
      final controller =
          SettingsController(
            configStore: store,
            registrableKeys: HotkeyKeyCatalogue.registrableKeys(),
            hotkey: hotkey,
            logger: logger,
          )..attachProviderKeyWriter(
            ConfigFallbackProviderKeyWriter(
              keyring: keyring,
              configStore: store,
            ),
          );
      addTearDown(controller.dispose);
      await controller.configureCompatibleProvider(
        baseUrl: 'https://example.test/v1',
        model: 'configured-model',
      );
      final before = store.current;
      var applied = before;
      var applications = 0;
      controller.attachConfigListener((config) {
        applied = config;
        applications++;
      });
      final resolver = ApiKeyResolver(
        const _UnavailableSecretStore(),
        const {},
      );

      for (final key in ['first-key', 'replacement-key']) {
        expect(await controller.saveApiKey(' $key '), isTrue);
        expect(applied, store.current);
        expect(controller.state.config, store.current);
        final provider = applied.providers[ProviderSecretFields.providerId];
        expect(provider, isNotNull);
        if (provider == null) return;
        expect(await resolver.resolve(provider), (
          apiKey: key,
          source: ApiKeySource.configFile,
        ));

        final restarted = JsonConfigStore(paths: paths, defaults: defaults);
        addTearDown(restarted.close);
        final loaded = await restarted.load();
        expect(loaded.warning, isNull);
        expect(loaded.config, store.current);
        expect(
          loaded.config.providers[ProviderSecretFields.providerId]?.settings,
          {'baseUrl': 'https://example.test/v1', 'apiKey': key},
        );
        expect(File(paths.configFile).statSync().mode & 0x1ff, 0x180);
        expect(loaded.config.presets, before.presets);
        expect(loaded.config.activePresetId, before.activePresetId);
      }
      await pumpEventQueue();
      expect(applications, 2);
      expect(logger.lines.toString(), isNot(contains('replacement-key')));
      expect(controller.state.failure, isNull);
    },
  );
}

final class _UnavailableSecretStore implements SecretStore {
  const _UnavailableSecretStore();

  @override
  Future<SecretLookup> readProviderKey(String providerId) async =>
      const SecretUnavailable();
}
