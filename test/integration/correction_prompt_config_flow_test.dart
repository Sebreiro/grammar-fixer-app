import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/application/settings_controller.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/json_config_store.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/openai_compatible/openai_compatible_correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:test/test.dart';

import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';

void main() {
  test(
    'CAP-8: file and Settings prompt edits reach the next adapter call with the same model',
    () async {
      final directory = await Directory.systemTemp.createTemp('prompt_flow_');
      addTearDown(() => directory.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <Map<String, Object?>>[];
      final subscription = server.listen(
        (request) => unawaited(_reply(request, requests)),
      );
      addTearDown(subscription.cancel);
      final paths = AppPaths.fromEnvironment({
        'XDG_CONFIG_HOME': directory.path,
        'XDG_DATA_HOME': directory.path,
        'XDG_RUNTIME_DIR': directory.path,
      });
      const preset = Preset(
        id: 'compatible-preset',
        providerId: ProviderConfig.compatibleProviderId,
        model: 'configured-model',
        systemPrompt: DefaultAppConfig.shippedSystemPrompt,
      );
      final defaults = DefaultAppConfig.build().copyWith(
        providers: {
          ProviderConfig.compatibleProviderId: ProviderConfig(
            settings: {
              ProviderConfig.baseUrlSetting:
                  'http://127.0.0.1:${server.port}/v1',
            },
          ),
        },
        presets: [preset],
        activePresetId: preset.id,
      );
      final store = JsonConfigStore(paths: paths, defaults: defaults);
      addTearDown(store.close);
      await store.load();
      final settings = SettingsController(
        configStore: store,
        hotkey: FakeGlobalHotkey(),
        logger: FakeLogger(),
        registrableKeys: HotkeyKeyCatalogue.registrableKeys(),
      );
      addTearDown(settings.dispose);
      var activePreset = preset;
      final applied = Completer<void>();
      settings.attachConfigListener((config) {
        activePreset = config.presets.single;
        if (!applied.isCompleted) applied.complete();
      });
      final provider = OpenAiCompatibleCorrectionProvider(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        logger: FakeLogger(),
      );
      final root =
          jsonDecode(await File(paths.configFile).readAsString())
              as Map<String, Object?>;
      final reference =
          (root['presets'] as List<Object?>).single as Map<String, Object?>;
      final prompt = File(
        '${File(paths.configFile).parent.path}/${reference['systemPromptFile'] as String}',
      );
      const fileEdit =
          'Correct grammar and preserve my meaning.\nUse natural English.\n';
      await prompt.writeAsString(fileEdit);
      await applied.future.timeout(const Duration(seconds: 3));
      final first = await provider
          .correct(text: 'i has a draft', preset: activePreset)
          .toList();
      expect(first.last, isA<CorrectionCompleted>());
      _expectRequest(requests.single, fileEdit);
      const settingsEdit =
          'Use my updated grammar instructions.\nPreserve the response format.';
      await settings.changeCorrectionPrompt(
        preset: activePreset,
        systemPrompt: settingsEdit,
      );
      expect(settings.state.failure, isNull);
      expect(await prompt.readAsString(), settingsEdit);
      final second = await provider
          .correct(text: 'i has another draft', preset: activePreset)
          .toList();
      expect(second.last, isA<CorrectionCompleted>());
      expect(requests, hasLength(2));
      _expectRequest(requests.last, settingsEdit);
    },
  );
}

void _expectRequest(Map<String, Object?> request, String prompt) {
  expect(request['model'], 'configured-model');
  final messages = request['messages'] as List<Object?>;
  final systemMessage = messages.first as Map<String, Object?>;
  expect(systemMessage['role'], 'system');
  final content = systemMessage['content'] as String;
  expect(content, startsWith('$prompt\n\n'));
  for (final tag in ['FORMAL:', 'CASUAL:', 'SHORTER:', '\nEND\n']) {
    expect(content, contains(tag));
  }
  expect(content, contains('Begin your response with FORMAL:'));
}

Future<void> _reply(
  HttpRequest request,
  List<Map<String, Object?>> requests,
) async {
  final body = await utf8.decoder.bind(request).join();
  final payload = jsonDecode(body) as Map<String, Object?>;
  requests.add(payload);
  final messages = payload['messages'] as List<Object?>;
  final prompt = (messages.first as Map<String, Object?>)['content'] as String;
  final hasFormat = [
    'FORMAL:',
    'CASUAL:',
    'SHORTER:',
    '\nEND\n',
  ].every(prompt.contains);
  request.response.headers.contentType = ContentType('text', 'event-stream');
  final frame = jsonEncode({
    'choices': [
      {
        'delta': {
          'content': hasFormat
              ? 'FORMAL: I have a draft.\nCASUAL: I have a draft.\nSHORTER: My draft.\nEND\n'
              : 'We have a draft.',
        },
      },
    ],
  });
  final stop = jsonEncode({
    'choices': [
      {'delta': <String, Object?>{}, 'finish_reason': 'stop'},
    ],
  });
  request.response.write('data: $frame\n\ndata: $stop\n\ndata: [DONE]\n\n');
  await request.response.close();
}
