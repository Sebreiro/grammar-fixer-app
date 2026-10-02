import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/close_behavior.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_load_result.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_store.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_write_conflict.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/secret_write_result.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/config_fallback_provider_key_writer.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/provider_secret_fields.dart';
import 'package:test/test.dart';

import '../../fakes/fake_config_store.dart';
import '../../fakes/fake_provider_key_writer.dart';

void main() {
  const providerId = ProviderSecretFields.providerId;
  late FakeConfigStore config;
  late FakeProviderKeyWriter keyring;
  late ConfigFallbackProviderKeyWriter writer;

  setUp(() {
    final defaults = DefaultAppConfig.build();
    config = FakeConfigStore(
      current: defaults.copyWith(
        providers: {
          ...defaults.providers,
          providerId: const ProviderConfig(
            settings: {
              'baseUrl': 'https://example.test/v1',
              'timeoutMillis': '5',
            },
          ),
        },
      ),
    );
    keyring = FakeProviderKeyWriter();
    writer = ConfigFallbackProviderKeyWriter(
      keyring: keyring,
      configStore: config,
    );
  });
  tearDown(() => config.dispose());

  test(
    'CAP-8: successful keyring saving never copies a key into config',
    () async {
      final before = config.current;
      config.writeError = StateError('config unavailable');
      expect(
        await writer.writeProviderKey(providerId, ' private-key '),
        SecretWriteResult.saved,
      );
      expect(keyring.writes.single.apiKey, 'private-key');
      expect(config.writes, isEmpty);
      expect(config.current, before);
    },
  );

  test(
    'CAP-8: unavailable keyring saving persists the key and preserves settings',
    () async {
      keyring.result = SecretWriteResult.unavailable;
      final before = config.current;
      expect(
        await writer.writeProviderKey(providerId, ' private-key '),
        SecretWriteResult.saved,
      );
      expect(config.writes, hasLength(1));
      expect(config.current.providers[providerId]?.settings, {
        ...?before.providers[providerId]?.settings,
        ProviderSecretFields.configKey: 'private-key',
      });
      expect(
        config.current.providers['claude-agent-sdk'],
        before.providers['claude-agent-sdk'],
      );
      expect(config.current.presets, before.presets);
      expect(config.current.activePresetId, before.activePresetId);
      expect(config.current.hotkeyBinding, before.hotkeyBinding);
      expect(
        before.providers[providerId]?.settings,
        isNot(contains(ProviderSecretFields.configKey)),
      );
    },
  );

  test(
    'CAP-8: config saving creates a missing provider without switching presets',
    () async {
      config.current = DefaultAppConfig.build();
      final before = config.current;
      keyring.result = SecretWriteResult.unavailable;
      expect(
        await writer.writeProviderKey(providerId, 'private-key'),
        SecretWriteResult.saved,
      );
      expect(config.current.providers[providerId]?.settings, {
        ProviderSecretFields.configKey: 'private-key',
      });
      expect(config.current.presets, before.presets);
      expect(config.current.activePresetId, before.activePresetId);
    },
  );

  test('CAP-8: a throwing keyring adapter still uses config saving', () async {
    keyring.error = StateError('private-key');
    expect(
      await writer.writeProviderKey(providerId, 'private-key'),
      SecretWriteResult.saved,
    );
    expect(
      config.current.providers[providerId]?.settings[ProviderSecretFields
          .configKey],
      'private-key',
    );
  });

  test('CAP-13: empty input reaches neither storage destination', () async {
    expect(
      await writer.writeProviderKey(providerId, ' '),
      SecretWriteResult.unavailable,
    );
    expect(keyring.writes, isEmpty);
    expect(config.writes, isEmpty);
  });

  test(
    'CAP-13: failed config persistence leaves the old key and allows retry',
    () async {
      keyring.result = SecretWriteResult.unavailable;
      await writer.writeProviderKey(providerId, 'old-key');
      final before = config.current;
      config.writeError = StateError('private-key');
      expect(
        await writer.writeProviderKey(providerId, 'new-key'),
        SecretWriteResult.unavailable,
      );
      expect(config.current, before);
      config.writeError = null;
      expect(
        await writer.writeProviderKey(providerId, 'new-key'),
        SecretWriteResult.saved,
      );
      expect(
        config.current.providers[providerId]?.settings[ProviderSecretFields
            .configKey],
        'new-key',
      );
    },
  );

  test('CAP-13: an unreadable current config reports failure', () async {
    keyring.result = SecretWriteResult.unavailable;
    config.currentError = StateError('private-key');
    expect(
      await writer.writeProviderKey(providerId, 'private-key'),
      SecretWriteResult.unavailable,
    );
    expect(config.writes, isEmpty);
  });

  test(
    'CAP-8: a config conflict merges the key into the latest hand edit',
    () async {
      keyring.result = SecretWriteResult.unavailable;
      final conflicts = _ConflictingConfigStore(config);
      writer = ConfigFallbackProviderKeyWriter(
        keyring: keyring,
        configStore: conflicts,
      );
      expect(
        await writer.writeProviderKey(providerId, 'private-key'),
        SecretWriteResult.saved,
      );
      expect(conflicts.attempts, 2);
      expect(keyring.writes, hasLength(1));
      expect(config.current.closeBehavior, CloseBehavior.quit);
      expect(
        config.current.providers[providerId]?.settings[ProviderSecretFields
            .configKey],
        'private-key',
      );
    },
  );

  test(
    'CAP-13: repeated config conflicts stop after a bounded retry',
    () async {
      keyring.result = SecretWriteResult.unavailable;
      final conflicts = _ConflictingConfigStore(config, remainingConflicts: 4);
      writer = ConfigFallbackProviderKeyWriter(
        keyring: keyring,
        configStore: conflicts,
      );
      expect(
        await writer.writeProviderKey(providerId, 'private-key'),
        SecretWriteResult.unavailable,
      );
      expect(conflicts.attempts, 3);
      expect(config.writes, isEmpty);
    },
  );
}

final class _ConflictingConfigStore implements ConfigStore {
  _ConflictingConfigStore(this.delegate, {this.remainingConflicts = 1});

  final FakeConfigStore delegate;
  int remainingConflicts;
  int attempts = 0;

  @override
  AppConfig get current => delegate.current;

  @override
  Stream<AppConfig> get changes => delegate.changes;

  @override
  Future<ConfigLoadResult> load() => delegate.load();

  @override
  Future<void> write(AppConfig config) async {
    attempts++;
    if (remainingConflicts > 0) {
      remainingConflicts--;
      delegate.current = current.copyWith(closeBehavior: CloseBehavior.quit);
      throw const ConfigWriteConflict();
    }
    await delegate.write(config);
  }
}
