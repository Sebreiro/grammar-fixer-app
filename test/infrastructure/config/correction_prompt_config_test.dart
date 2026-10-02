import 'dart:convert';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_write_conflict.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/json_config_store.dart';
import 'package:test/test.dart';

void main() {
  final defaults = DefaultAppConfig.build();
  late Directory directory;
  late AppPaths paths;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('prompt_config_');
    paths = AppPaths.fromEnvironment({
      'XDG_CONFIG_HOME': directory.path,
      'XDG_DATA_HOME': directory.path,
      'XDG_RUNTIME_DIR': directory.path,
    });
    file = File(paths.configFile);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  JsonConfigStore newStore() {
    final store = JsonConfigStore(paths: paths, defaults: defaults);
    addTearDown(store.close);
    return store;
  }

  Map<String, Object?> readJson() =>
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

  Map<String, Object?> firstPreset(Map<String, Object?> root) =>
      (root['presets'] as List<Object?>).first as Map<String, Object?>;

  File promptFile() => File(
    '${file.parent.path}/${firstPreset(readJson())['systemPromptFile'] as String}',
  );

  void changeJson(void Function(Map<String, Object?>) change) {
    final root = readJson();
    change(root);
    file.writeAsStringSync(jsonEncode(root));
  }

  AppConfig withPrompt(String prompt) {
    final preset = defaults.presets.single;
    return defaults.copyWith(
      presets: [
        Preset(
          id: preset.id,
          providerId: preset.providerId,
          model: preset.model,
          systemPrompt: prompt,
        ),
      ],
    );
  }

  test(
    'CAP-8: first run seeds the complete default prompt beside config once',
    () async {
      final initial = await newStore().load();
      expect(initial.warning, isNull);
      expect(initial.config, defaults);
      final preset = firstPreset(readJson());
      expect(
        preset['systemPromptFile'],
        'prompt-default-formal-casual-shorter.txt',
      );
      expect(preset.containsKey('systemPrompt'), isFalse);
      expect(preset['model'], DefaultAppConfig.shippedModel);
      expect(
        promptFile().readAsStringSync(),
        DefaultAppConfig.shippedSystemPrompt,
      );
      expect(promptFile().statSync().mode & 0x1ff, 0x180);
      final saved = file.readAsStringSync();
      expect((await newStore().load()).config, defaults);
      expect(file.readAsStringSync(), saved);
    },
  );

  test(
    'CAP-8: recreating a missing config preserves an existing default prompt',
    () async {
      await newStore().load();
      promptFile().writeAsStringSync('An existing custom prompt.');
      file.deleteSync();
      final result = await newStore().load();
      expect(result.warning, isNull);
      expect(
        result.config.presets.single.systemPrompt,
        'An existing custom prompt.',
      );
      expect(promptFile().readAsStringSync(), 'An existing custom prompt.');
    },
  );

  test(
    'CAP-8: legacy inline prompts migrate exactly without replacing existing files',
    () async {
      await newStore().load();
      final existing = promptFile();
      const prompt = ' Keep "quotes" and \\slashes.\n\nTone: café 日本語.\n';
      changeJson((root) {
        firstPreset(root)
          ..remove('systemPromptFile')
          ..['systemPrompt'] = prompt;
      });
      final result = await newStore().load();
      expect(result.warning, isNull);
      expect(result.config, withPrompt(prompt));
      expect(promptFile().readAsStringSync(), prompt);
      expect(promptFile().path, isNot(existing.path));
      expect(existing.readAsStringSync(), DefaultAppConfig.shippedSystemPrompt);
      expect(firstPreset(readJson()).containsKey('systemPrompt'), isFalse);
    },
  );

  test(
    'CAP-8: settings preserve a custom filename and the exact multiline prompt',
    () async {
      final store = newStore();
      await store.load();
      final customFile = File('${file.parent.path}/my grammar.txt');
      const prompt = ' Keep whitespace.\n\nPreserve café 日本語.\n';
      customFile.writeAsStringSync(prompt);
      changeJson(
        (root) => firstPreset(root)['systemPromptFile'] = 'my grammar.txt',
      );
      final edited = await store.load();
      expect(edited.warning, isNull);
      expect(edited.config, withPrompt(prompt));
      await store.write(edited.config.copyWith(logMaxBytes: 2048));
      expect(firstPreset(readJson())['systemPromptFile'], 'my grammar.txt');
      expect(customFile.readAsStringSync(), prompt);
      expect((await newStore().load()).config.logMaxBytes, 2048);
    },
  );

  test(
    'CAP-8: a live prompt-file edit is published with its paired model',
    () async {
      final store = newStore();
      await store.load();
      final change = store.changes.first;
      const prompt = 'Correct grammar while preserving meaning.\nUse END.';
      promptFile().writeAsStringSync(prompt);
      final edited = await change.timeout(const Duration(seconds: 3));
      expect(edited, withPrompt(prompt));
      expect(edited.presets.single.model, DefaultAppConfig.shippedModel);
    },
  );

  test(
    'CAP-8: a changed prompt-file reference is watched even when its text matches',
    () async {
      final store = newStore();
      await store.load();
      final replacement = File('${file.parent.path}/replacement.txt');
      replacement.writeAsStringSync(DefaultAppConfig.shippedSystemPrompt);
      changeJson(
        (root) => firstPreset(root)['systemPromptFile'] = 'replacement.txt',
      );
      await store.load();
      final change = store.changes.first;
      replacement.writeAsStringSync('Edit the new file.');
      expect(
        await change.timeout(const Duration(seconds: 3)),
        withPrompt('Edit the new file.'),
      );
      await store.write(store.current.copyWith(logMaxBytes: 2048));
      expect(firstPreset(readJson())['systemPromptFile'], 'replacement.txt');
    },
  );

  for (final invalid in <Object?>[
    null,
    42,
    '',
    '../outside.txt',
    '/tmp/outside.txt',
    'folder/prompt.txt',
    'folder\\prompt.txt',
    'prompt.json',
  ]) {
    test(
      'CAP-8: invalid prompt reference $invalid leaves the config intact',
      () async {
        await newStore().load();
        changeJson((root) => firstPreset(root)['systemPromptFile'] = invalid);
        final saved = file.readAsStringSync();
        final result = await newStore().load();
        expect(result.warning, contains('systemPromptFile'));
        expect(result.config, defaults);
        expect(file.readAsStringSync(), saved);
      },
    );
  }

  test('CAP-8: ambiguous inline and file prompts are rejected', () async {
    await newStore().load();
    changeJson((root) => firstPreset(root)['systemPrompt'] = 'Ambiguous.');
    final result = await newStore().load();
    expect(result.warning, contains('not both'));
    expect(result.config, defaults);
  });

  test('CAP-8: each preset needs its own prompt file', () async {
    await newStore().load();
    changeJson((root) {
      final presets = root['presets'] as List<Object?>;
      presets.add({...firstPreset(root), 'id': 'another-preset'});
    });
    final result = await newStore().load();
    expect(result.warning, contains('own systemPromptFile'));
    expect(result.config, defaults);
  });

  test(
    'CAP-8: missing and malformed prompt files warn without reseeding',
    () async {
      await newStore().load();
      final prompt = promptFile();
      prompt.deleteSync();
      expect((await newStore().load()).warning, contains('could not be read'));
      expect(prompt.existsSync(), isFalse);
      prompt.writeAsBytesSync([0xff]);
      expect((await newStore().load()).warning, contains('UTF-8'));
      expect(prompt.readAsBytesSync(), [0xff]);
    },
  );

  test(
    'CAP-8: blank prompt files and saves cannot overwrite a saved preset',
    () async {
      final store = newStore();
      await store.load();
      final saved = promptFile().readAsStringSync();
      await expectLater(store.write(withPrompt(' \n\t')), throwsArgumentError);
      expect(promptFile().readAsStringSync(), saved);
      promptFile().writeAsStringSync(' \n\t');
      final result = await newStore().load();
      expect(result.warning, contains('systemPrompt'));
      expect(result.config, defaults);
      expect(promptFile().readAsStringSync(), ' \n\t');
    },
  );

  test(
    'CAP-8: saving a prompt updates its text file and survives restart',
    () async {
      final store = newStore();
      await store.load();
      final savedConfig = file.readAsStringSync();
      const prompt = 'Grammar first.\nTone second.\n';
      await store.write(withPrompt(prompt));
      expect(promptFile().readAsStringSync(), prompt);
      expect(file.readAsStringSync(), savedConfig);
      expect((await newStore().load()).config, withPrompt(prompt));
    },
  );

  test(
    'CAP-8: a stale settings save refuses an external prompt edit',
    () async {
      final writer = newStore();
      // Writing before load leaves no watcher to consume the conflict first.
      await writer.write(defaults);
      promptFile().writeAsStringSync('External edit.');
      await expectLater(
        writer.write(withPrompt('Settings draft.')),
        throwsA(isA<ConfigWriteConflict>()),
      );
      expect(promptFile().readAsStringSync(), 'External edit.');
      expect(writer.current, withPrompt('External edit.'));
    },
  );

  test(
    'CAP-8: a failed config installation rolls back newly created prompt files',
    () async {
      file.parent.createSync(recursive: true);
      Directory(file.path).createSync();
      await expectLater(
        newStore().write(defaults),
        throwsA(isA<FileSystemException>()),
      );
      expect(file.parent.listSync().whereType<File>(), isEmpty);
      expect(Directory(file.path).existsSync(), isTrue);
    },
  );

  test(
    'CAP-8: failed inline migration keeps the saved custom prompt usable',
    () async {
      await newStore().load();
      const prompt = 'My saved custom prompt.';
      changeJson((root) {
        firstPreset(root)
          ..remove('systemPromptFile')
          ..['systemPrompt'] = prompt;
      });
      final saved = file.readAsStringSync();
      expect(Process.runSync('chmod', ['500', file.parent.path]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['700', file.parent.path]));
      final result = await newStore().load();
      expect(result.config, withPrompt(prompt));
      expect(result.warning, contains('could not move inline prompts'));
      expect(file.readAsStringSync(), saved);
    },
    skip: Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
        ? 'root bypasses directory write permissions'
        : false,
  );
}
