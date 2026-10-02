import 'dart:async';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/secret_store.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/provider_secret_fields.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/api_key_resolver.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/api_key_source.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/openai_compatible/openai_compatible_correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/provider_registry.dart';
import 'package:test/test.dart';

import '../fakes/fake_logger.dart';

void main() {
  test('CAP-8: keyring, environment, and config sources take precedence '
      'without passing key text to settings', () async {
    const config = ProviderConfig(settings: {'apiKey': ' file-key '});
    final keyring = _SecretStore(const SecretFound(' ring-key '));
    final resolver = ApiKeyResolver(keyring, const {
      'OPENAI_API_KEY': ' env-key ',
    });

    expect(await resolver.resolve(config), (
      apiKey: 'ring-key',
      source: ApiKeySource.systemKeyring,
    ));
    expect(
      await resolver.sourceForSettings(config),
      ApiKeySource.systemKeyring,
    );

    keyring.answer = const SecretFound('   ');
    expect(await resolver.resolve(config), (
      apiKey: 'env-key',
      source: ApiKeySource.environment,
    ));

    keyring.answer = const SecretUnavailable();
    final fileResolver = ApiKeyResolver(keyring, const {});
    expect(await fileResolver.resolve(config), (
      apiKey: 'file-key',
      source: ApiKeySource.configFile,
    ));

    keyring.answer = const SecretAbsent();
    expect(
      await fileResolver.resolve(
        const ProviderConfig(settings: {'apiKey': ' '}),
      ),
      (apiKey: null, source: ApiKeySource.none),
    );
    expect(keyring.providerIds, everyElement(ProviderSecretFields.providerId));
    expect(
      [for (final source in ApiKeySource.values) source.settingsLabel],
      [
        'System keyring',
        'Environment variable',
        'Config file',
        'None configured',
      ],
    );
  });

  test('CAP-8: a resolved key reaches only the active HTTP request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final authorization = Completer<String?>();
    server.listen((request) async {
      authorization.complete(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      request.response.write(
        'data: {"choices":[{"delta":{"content":"FORMAL: Fixed\\nCASUAL: Better\\nSHORTER: Good\\nEND"},"finish_reason":null}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n',
      );
      await request.response.close();
    });
    final resolver = ApiKeyResolver(
      _SecretStore(const SecretFound(' private-key ')),
      const {'OPENAI_API_KEY': 'ignored-key'},
    );
    final provider = OpenAiCompatibleCorrectionProvider(
      logger: FakeLogger(),
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      resolveApiKey: () async =>
          (await resolver.resolve(const ProviderConfig(settings: {}))).apiKey,
    );

    final events = await provider
        .correct(
          text: 'draft',
          preset: const Preset(
            id: 'compatible',
            providerId: OpenAiCompatibleCorrectionProvider.providerId,
            model: 'local-model',
            systemPrompt: 'Correct the text',
          ),
        )
        .toList()
        .timeout(const Duration(seconds: 5));

    expect(await authorization.future, 'Bearer private-key');
    expect(events.last, isA<CorrectionCompleted>());
  });

  test('CAP-8: the provider registry wires the configured endpoint to the '
      'winning credential source', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final authorization = Completer<String?>();
    server.listen((request) async {
      authorization.complete(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      request.response.write(
        'data: {"choices":[{"delta":{"content":"FORMAL: Fixed\\nCASUAL: Better\\nSHORTER: Good\\nEND"},"finish_reason":null}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n',
      );
      await request.response.close();
    });
    final keyring = _SecretStore(const SecretFound(' ring-key '));
    final registry = ProviderRegistry(
      logger: FakeLogger(),
      apiKeyResolver: ApiKeyResolver(keyring, const {
        'OPENAI_API_KEY': 'env-key',
      }),
    );
    final provider =
        registry.create(
          OpenAiCompatibleCorrectionProvider.providerId,
          ProviderConfig(
            settings: {'baseUrl': 'http://127.0.0.1:${server.port}/v1'},
          ),
        ) ??
        (throw StateError('the configured provider was not registered'));

    final events = await provider
        .correct(
          text: 'draft',
          preset: const Preset(
            id: 'compatible',
            providerId: OpenAiCompatibleCorrectionProvider.providerId,
            model: 'local-model',
            systemPrompt: 'Correct the text',
          ),
        )
        .toList()
        .timeout(const Duration(seconds: 5));

    expect(await authorization.future, 'Bearer ring-key');
    expect(events.last, isA<CorrectionCompleted>());
    expect(keyring.providerIds, [ProviderSecretFields.providerId]);
  });
}

final class _SecretStore implements SecretStore {
  _SecretStore(this.answer);

  SecretLookup answer;
  final List<String> providerIds = [];

  @override
  Future<SecretLookup> readProviderKey(String providerId) async {
    providerIds.add(providerId);
    return answer;
  }
}
