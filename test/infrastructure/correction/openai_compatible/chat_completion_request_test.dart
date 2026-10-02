import 'dart:convert';

import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/openai_compatible/chat_completion_request.dart';
import 'package:test/test.dart';

const _preset = Preset(
  id: 'configured',
  providerId: 'openai-compatible',
  model: 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',
  systemPrompt: DefaultAppConfig.shippedSystemPrompt,
);

void main() {
  test('CAP-4 CAP-5: OpenRouter receives answer-only controls with the '
      'configured Nemotron model and default prompt', () {
    final body = _request('https://openrouter.ai/api/v1/chat/completions');

    expect(body['model'], _preset.model);
    expect(body['reasoning'], {'enabled': false, 'exclude': true});
    expect(body['stream'], isTrue);
    final messages = body['messages'] as List<Object?>;
    expect(messages, hasLength(2));
    final system = messages.first as Map<String, Object?>;
    final prompt = system['content'] as String;
    expect(system['role'], 'system');
    expect(prompt, startsWith('${_preset.systemPrompt}\n\n'));
    expect(prompt, contains('Begin your response with FORMAL:'));
    expect(messages.last, {'role': 'user', 'content': 'i has a draft'});
  });

  test('CAP-8: OpenRouter-only fields never reach other compatible hosts', () {
    for (final endpoint in [
      'https://api.openai.com/v1/chat/completions',
      'http://127.0.0.1:8080/v1/chat/completions',
      'https://openrouter.ai.example.com/v1/chat/completions',
      'https://example.com/openrouter.ai/chat/completions',
    ]) {
      final body = _request(endpoint);
      expect(body, isNot(contains('reasoning')), reason: endpoint);
      expect(body['model'], _preset.model);
    }
  });
}

Map<String, Object?> _request(String endpoint) =>
    jsonDecode(
          ChatCompletionRequest.encode(
            endpoint: Uri.parse(endpoint),
            text: 'i has a draft',
            preset: _preset,
          ),
        )
        as Map<String, Object?>;
