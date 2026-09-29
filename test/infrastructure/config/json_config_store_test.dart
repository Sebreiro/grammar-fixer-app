import 'dart:convert';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_write_conflict.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/json_config_store.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/provider_secret_fields.dart';
import 'package:test/test.dart';

/// Behaviour tests for `JsonConfigStore` (AD-13, CAP-8), covering every
/// Config row of the spec's I/O & Edge-Case Matrix over a temp directory.
/// Pure Dart: no Flutter binding, no real XDG session.
void main() {
  final defaults = DefaultAppConfig.build();

  late Directory tempDir;
  late AppPaths paths;
  late File configFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('config_store_');
    paths = AppPaths.fromEnvironment({
      'XDG_CONFIG_HOME': '${tempDir.path}/config',
      'XDG_DATA_HOME': '${tempDir.path}/data',
      'XDG_RUNTIME_DIR': '${tempDir.path}/run',
    });
    configFile = File(paths.configFile);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  JsonConfigStore newStore() {
    final store = JsonConfigStore(paths: paths, defaults: defaults);
    addTearDown(store.close);
    return store;
  }

  void writeRaw(String contents) {
    configFile.parent.createSync(recursive: true);
    configFile.writeAsStringSync(contents);
  }

  /// A well-formed file for the corruption rows, produced by the store's own
  /// encoder so a fixture can never drift from the codec under test.
  Future<Map<String, Object?>> validJson() async {
    final store = newStore();
    await store.write(_custom);
    return jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
  }

  Future<void> writeCorrupted(
    void Function(Map<String, Object?> json) corrupt,
  ) async {
    final json = await validJson();
    corrupt(json);
    writeRaw(jsonEncode(json));
  }

  group('loading (AD-13)', () {
    test('CAP-8: a first run adopts the defaults and seeds the file so there '
        'is something to edit', () async {
      final store = newStore();

      final result = await store.load();

      expect(result.warning, isNull);
      _expectSameConfig(result.config, defaults);
      _expectSameConfig(store.current, defaults);
      expect(
        configFile.existsSync(),
        isTrue,
        reason: "CAP-8's other half is a person opening this file",
      );
    });

    test('CAP-8: a well-formed file becomes current with no warning', () async {
      await validJson();

      final result = await newStore().load();

      expect(result.warning, isNull);
      _expectSameConfig(result.config, _custom);
    });

    test('AD-13: an unparseable file yields the defaults plus a warning, '
        'never a throw', () async {
      writeRaw('{ this is not json');

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, isNotNull);
      expect(result.warning, contains('JSON'));
    });

    test('AD-13: a field of the wrong type yields the defaults plus a warning '
        'naming the field', () async {
      await writeCorrupted((json) => json['activePresetId'] = 42);

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, contains('activePresetId'));
    });

    test(
      'CAP-8: malformed nested settings identify the field to repair',
      () async {
        final cases = <(String, void Function(Map<String, Object?>))>[
          ('presets', (json) => json['presets'] = 'not a list'),
          (
            'hotkeyBinding.modifiers',
            (json) =>
                (json['hotkeyBinding']! as Map<String, Object?>)['modifiers'] =
                    'control',
          ),
          ('providers', (json) => json['providers'] = <Object?>[]),
          ('presets', (json) => json['presets'] = null),
        ];
        for (final (field, corrupt) in cases) {
          await writeCorrupted(corrupt);
          final result = await newStore().load();
          expect(result.warning, contains(field));
          _expectSameConfig(result.config, defaults);
        }
      },
    );

    test(
      'CAP-12: reloading a changed config publishes the external edit',
      () async {
        final store = newStore();
        await store.load();
        final seen = <AppConfig>[];
        store.changes.listen(seen.add);
        await validJson();

        final result = await store.load();
        await pumpEventQueue();

        expect(result.warning, isNull);
        _expectSameConfig(result.config, _custom);
        expect(seen, contains(_custom));
      },
    );

    test(
      'CAP-12: a stale writer refuses to overwrite an external edit',
      () async {
        final store = newStore();
        await store.load();
        await validJson();

        await expectLater(
          store.write(defaults),
          throwsA(isA<ConfigWriteConflict>()),
        );
        _expectSameConfig(store.current, _custom);
        _expectSameConfig((await newStore().load()).config, _custom);
      },
    );

    test('CAP-13: a malformed external file blocks a stale write', () async {
      final store = newStore();
      await store.load();
      writeRaw('{broken');

      await expectLater(
        store.write(_custom),
        throwsA(isA<FileSystemException>()),
      );
      _expectSameConfig(store.current, defaults);
    });

    test('AD-19: a config written by an older build, still carrying the '
        'sidecarPath and interpreterPath keys, loads unchanged rather than '
        'being condemned to defaults', () async {
      // Story 1 seeds a config file on every first run, and that build wrote
      // both keys. Collapsing the duplicated AD-19 path home removed them from
      // AppConfig, so every already-installed file now carries two keys the
      // decoder no longer reads. Treating those as a malformed file would
      // silently discard the user's presets and hotkey on upgrade — the whole
      // point is that the surviving home is ProviderConfig.settings.
      await writeCorrupted((json) {
        json['sidecarPath'] = '/opt/sidecar/claude_agent_sdk_sidecar.py';
        json['interpreterPath'] = '/usr/bin/python3';
      });

      final result = await newStore().load();

      expect(result.warning, isNull);
      _expectSameConfig(result.config, _custom);
    });

    test('AD-13: an unknown HotkeyModifier name yields the defaults plus a '
        'warning naming the offending value', () async {
      await writeCorrupted((json) {
        (json['hotkeyBinding']! as Map<String, Object?>)['modifiers'] = [
          'control',
          'hyper',
        ];
      });

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, contains('hyper'));
    });

    test('AD-13: modifiers stored as enum indices are rejected — enums travel '
        'by name, never by index', () async {
      await writeCorrupted((json) {
        (json['hotkeyBinding']! as Map<String, Object?>)['modifiers'] = [0, 2];
      });

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, isNotNull);
    });

    test('AD-13: two presets sharing an id yield the defaults plus a warning '
        'naming it', () async {
      // Consumers resolve the active preset with a single-match lookup, so a
      // certified-valid config with a duplicate id crashes downstream.
      await writeCorrupted((json) {
        final presets = json['presets']! as List<Object?>;
        final duplicate = {...presets.first! as Map<String, Object?>};
        duplicate['id'] = 'preset-b';
        presets.add(duplicate);
      });

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, contains('preset-b'));
    });

    test(
      'AD-13: an empty hotkey key yields the defaults plus a warning',
      () async {
        await writeCorrupted((json) {
          (json['hotkeyBinding']! as Map<String, Object?>)['key'] = '';
        });

        final result = await newStore().load();

        _expectSameConfig(result.config, defaults);
        expect(result.warning, contains('key'));
      },
    );

    test('AD-13: an empty modifier set is accepted — a bare-key binding is '
        'legitimate and is not this store to rule out', () async {
      await writeCorrupted((json) {
        (json['hotkeyBinding']! as Map<String, Object?>)['modifiers'] =
            <Object?>[];
      });

      final result = await newStore().load();

      expect(result.warning, isNull);
      expect(result.config.hotkeyBinding.modifiers, isEmpty);
    });

    test('CAP-8: a numeric or boolean provider setting is coerced rather than '
        'discarding the whole config', () async {
      // The shipped file contains "timeoutMillis": "60000"; a user editing it
      // into the natural JSON 60000 must not silently lose their presets,
      // provider settings and hotkey.
      await writeCorrupted((json) {
        final providers = json['providers']! as Map<String, Object?>;
        final settings =
            (providers['p-one']! as Map<String, Object?>)['settings']!
                as Map<String, Object?>;
        settings['timeoutMillis'] = 60000;
        settings['verbose'] = true;
      });

      final result = await newStore().load();

      expect(result.warning, isNull);
      expect(
        result.config.providers['p-one']?.settings['timeoutMillis'],
        '60000',
      );
      expect(result.config.providers['p-one']?.settings['verbose'], 'true');
      expect(
        result.config.activePresetId,
        _custom.activePresetId,
        reason: 'the rest of the config survives an unquoted number',
      );
    });

    test('AD-13: a structured provider setting still fails, because an object '
        'carries no obvious intent', () async {
      await writeCorrupted((json) {
        final providers = json['providers']! as Map<String, Object?>;
        final settings =
            (providers['p-one']! as Map<String, Object?>)['settings']!
                as Map<String, Object?>;
        settings['interpreter'] = <String, Object?>{'path': '/usr/bin/python3'};
      });

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, contains('interpreter'));
    });

    test('AD-13: an activePresetId naming no preset yields the defaults plus '
        'a warning naming the dangling id', () async {
      await writeCorrupted((json) => json['activePresetId'] = 'preset-ghost');

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, contains('preset-ghost'));
    });

    test('AD-13: a preset naming no provider yields the defaults plus a '
        'warning naming the dangling id', () async {
      await writeCorrupted((json) {
        final presets = json['presets']! as List<Object?>;
        (presets.first! as Map<String, Object?>)['providerId'] = 'p-ghost';
      });

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, contains('p-ghost'));
    });

    test('AD-13: a file that cannot be read yields the defaults plus a '
        'warning, never a throw', () async {
      writeRaw('{}');
      Process.runSync('chmod', ['000', configFile.path]);
      addTearDown(() => Process.runSync('chmod', ['600', configFile.path]));

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, isNotNull);
    }, skip: _rootSkipReason());

    test('CAP-8: reading current before load is programmer error', () {
      expect(() => newStore().current, throwsStateError);
    });
  });

  group('writing (AD-13, CAP-12)', () {
    test('CAP-8: a written config round-trips field by field, modifiers '
        'restored from their names', () async {
      final writer = newStore();
      await writer.load();

      await writer.write(_custom);
      final reloaded = await newStore().load();

      expect(reloaded.warning, isNull);
      _expectSameConfig(reloaded.config, _custom);
      expect(
        reloaded.config.hotkeyBinding.modifiers,
        _custom.hotkeyBinding.modifiers,
      );
      expect(
        configFile.readAsStringSync(),
        contains('"${HotkeyModifier.meta.name}"'),
        reason: 'enums are persisted by name, never by index',
      );
    });

    test('CAP-12: a write updates current, emits once, and leaves no temp '
        'file behind', () async {
      final store = newStore();
      await store.load();
      final seen = <AppConfig>[];
      store.changes.listen(seen.add);

      await store.write(_custom);
      await pumpEventQueue();

      _expectSameConfig(store.current, _custom);
      expect(seen, hasLength(1));
      expect(
        configFile.parent
            .listSync()
            .map((entry) => entry.path)
            .where((path) => path.endsWith('.tmp')),
        isEmpty,
        reason: 'the atomic write renames its temp file into place',
      );

      expect(configFile.statSync().mode & 0x1ff, 0x180);
      final handEdited =
          jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
      final providers = handEdited['providers']! as Map<String, Object?>;
      providers[ProviderSecretFields.providerId] = {
        'settings': {ProviderSecretFields.configKey: 'hand-placed-key'},
      };
      writeRaw(jsonEncode(handEdited));
      expect(Process.runSync('chmod', ['400', configFile.path]).exitCode, 0);

      final protectedStore = newStore();
      final loaded = await protectedStore.load();
      expect(loaded.warning, isNull);
      await protectedStore.write(
        loaded.config.copyWith(activePresetId: 'preset-a'),
      );

      final rewritten =
          jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
      final rewrittenProviders =
          rewritten['providers']! as Map<String, Object?>;
      final keyProvider =
          rewrittenProviders[ProviderSecretFields.providerId]!
              as Map<String, Object?>;
      final keySettings = keyProvider['settings']! as Map<String, Object?>;
      expect(keySettings[ProviderSecretFields.configKey], 'hand-placed-key');
      expect(
        configFile.statSync().mode & 0x1ff,
        0x100,
        reason: 'the rewrite must retain the hand-protected file mode',
      );
    });

    test('AD-13: changes is broadcast — two listeners both see every '
        'write', () async {
      final store = newStore();
      await store.load();
      final first = <AppConfig>[];
      final second = <AppConfig>[];
      store.changes.listen(first.add);
      store.changes.listen(second.add);

      await store.write(_custom);
      await store.write(defaults);
      await pumpEventQueue();

      expect(first, hasLength(2));
      expect(second, hasLength(2));
    });

    test('AD-13: writing a config with a dangling id throws ArgumentError '
        'naming it and changes nothing', () async {
      final store = newStore();
      await store.load();
      final seen = <AppConfig>[];
      store.changes.listen(seen.add);
      final invalid = _custom.copyWith(activePresetId: 'preset-ghost');

      await expectLater(
        store.write(invalid),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains('preset-ghost'),
          ),
        ),
      );
      await pumpEventQueue();

      _expectSameConfig(store.current, defaults);
      expect(seen, isEmpty);
      expect(
        configFile.readAsStringSync(),
        isNot(contains('preset-ghost')),
        reason: 'a rejected write never reaches the file',
      );
    });

    test('AD-13: writing duplicate preset ids or an empty hotkey key is '
        'rejected on the same terms as a dangling id', () async {
      final store = newStore();
      await store.load();
      final duplicated = _custom.copyWith(
        presets: [_custom.presets.first, _custom.presets.first],
        activePresetId: _custom.presets.first.id,
      );
      final keyless = _custom.copyWith(
        hotkeyBinding: HotkeyBinding(
          modifiers: {HotkeyModifier.control},
          key: '',
        ),
      );

      await expectLater(store.write(duplicated), throwsArgumentError);
      await expectLater(store.write(keyless), throwsArgumentError);

      _expectSameConfig(store.current, defaults);
    });

    test('CAP-12: two overlapping writes both land, in order, without '
        'truncating each other scratch file', () async {
      // SettingsController.changeHotkey awaits a portal dialog that can sit
      // for seconds, so a changeActivePreset landing in that window is
      // reachable in-process — with a fixed temp name the loser used to fail
      // its rename with PathNotFoundException.
      final store = newStore();
      await store.load();
      final other = _custom.copyWith(activePresetId: 'preset-a');

      await Future.wait([store.write(_custom), store.write(other)]);

      _expectSameConfig(store.current, other);
      final reloaded = await newStore().load();
      expect(reloaded.warning, isNull);
      _expectSameConfig(reloaded.config, other);
      expect(
        configFile.parent
            .listSync()
            .map((entry) => entry.path)
            .where((path) => path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('AD-13: a write that resolves after close does not add to a closed '
        'controller', () async {
      final store = JsonConfigStore(paths: paths, defaults: defaults);
      await store.load();

      final pending = store.write(_custom);
      await store.close();

      await expectLater(pending, completes);
      await pumpEventQueue();
    });

    test('CAP-13: a write to a read-only directory propagates the filesystem '
        'error and leaves current alone', () async {
      final store = newStore();
      await store.load();
      final directory = configFile.parent;
      Process.runSync('chmod', ['500', directory.path]);
      addTearDown(() => Process.runSync('chmod', ['700', directory.path]));

      await expectLater(
        store.write(_custom),
        throwsA(isA<FileSystemException>()),
      );

      _expectSameConfig(store.current, defaults);
    }, skip: _rootSkipReason());

    test('AD-13: a seed write that cannot happen degrades to a warning '
        'instead of failing startup', () async {
      // The config home exists but is read-only, so the first-run seed fails
      // where a resident daemon must nonetheless come up.
      configFile.parent.parent.createSync(recursive: true);
      Process.runSync('chmod', ['500', configFile.parent.parent.path]);
      addTearDown(
        () => Process.runSync('chmod', ['700', configFile.parent.parent.path]),
      );

      final result = await newStore().load();

      _expectSameConfig(result.config, defaults);
      expect(result.warning, isNotNull);
    }, skip: _rootSkipReason());
  });

  test('AD-13: app_paths.dart resolves the config path and '
      'json_config_store.dart is its only reader in lib/', () {
    // AppPaths resolves the layout and JsonConfigStore opens it. A source may
    // name the key-source enum's `configFile` without reading the file, so the
    // scan looks for the actual path accessor instead of that generic word.
    const resolver = 'lib/src/infrastructure/config/app_paths.dart';
    const owner = 'lib/src/infrastructure/config/json_config_store.dart';
    const forbidden = [
      AppPaths.configFileName,
      'configFileName',
      'paths.configFile',
    ];

    // The settings warning names the file for the user; it never opens it.
    const displayWarning =
        'This API key is stored as plaintext in config.json. ';
    final readers = [
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')))
        if (file.path != resolver && file.path != owner)
          if (forbidden.any(
            file.readAsStringSync().replaceAll(displayWarning, '').contains,
          ))
            file.path,
    ];

    expect(readers, isEmpty);
  });
}

/// A config sharing no field value with the shipped defaults, so a test that
/// confuses the two cannot pass by accident.
final AppConfig _custom = AppConfig(
  providers: {
    'p-one': ProviderConfig(
      settings: {'interpreter': '/usr/bin/python3', 'timeoutMillis': '1500'},
    ),
    'p-two': ProviderConfig(settings: {}),
  },
  presets: [
    Preset(
      id: 'preset-a',
      providerId: 'p-one',
      model: 'model-a',
      systemPrompt: 'prompt A',
    ),
    Preset(
      id: 'preset-b',
      providerId: 'p-two',
      model: 'model-b',
      systemPrompt: 'prompt B',
    ),
  ],
  activePresetId: 'preset-b',
  hotkeyBinding: HotkeyBinding(
    modifiers: {HotkeyModifier.meta, HotkeyModifier.alt},
    key: 'Space',
  ),
);

/// Field by field, deliberately: `AppConfig` now compares by value, but a
/// single `expect(actual, expected)` reports only "they differ", and these
/// rows exist to say *which* field a codec change lost.
void _expectSameConfig(AppConfig actual, AppConfig expected) {
  expect(actual.activePresetId, expected.activePresetId);
  expect(actual.hotkeyBinding.key, expected.hotkeyBinding.key);
  expect(actual.hotkeyBinding.modifiers, expected.hotkeyBinding.modifiers);
  expect(actual.providers.keys, expected.providers.keys);
  for (final id in expected.providers.keys) {
    expect(actual.providers[id]?.settings, expected.providers[id]?.settings);
  }
  expect(
    [for (final preset in actual.presets) preset.id],
    [for (final preset in expected.presets) preset.id],
  );
  for (var index = 0; index < expected.presets.length; index += 1) {
    final actualPreset = actual.presets[index];
    final expectedPreset = expected.presets[index];
    expect(actualPreset.providerId, expectedPreset.providerId);
    expect(actualPreset.model, expectedPreset.model);
    expect(actualPreset.systemPrompt, expectedPreset.systemPrompt);
  }
  // The whole value too, so a field added to AppConfig and forgotten by the
  // codec fails here rather than passing every row above.
  expect(actual, expected);
}

/// Root ignores directory mode bits, so the unwritable-target rows cannot be
/// staged there at all.
String? _rootSkipReason() {
  final uid = Process.runSync('id', ['-u']).stdout.toString().trim();
  return uid == '0'
      ? 'the test process is root, which ignores directory mode bits'
      : null;
}
