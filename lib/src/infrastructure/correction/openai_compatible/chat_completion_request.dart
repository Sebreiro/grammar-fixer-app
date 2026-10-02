import 'dart:convert';

import '../../../domain/correction/preset.dart';
import '../shared/register_tagged_prompt.dart';

/// Pure request mapping for the configured Chat Completions endpoint.
final class ChatCompletionRequest {
  const ChatCompletionRequest._();

  static String encode({
    required Uri endpoint,
    required String text,
    required Preset preset,
  }) => jsonEncode({
    'model': preset.model,
    'messages': [
      {
        'role': 'system',
        'content': RegisterTaggedPrompt.compose(preset.systemPrompt),
      },
      {'role': 'user', 'content': text},
    ],
    'stream': true,
    'temperature': 0.2,
    'n': 1,
    'max_tokens': 512,
    // Optional thinking can consume this budget before any tagged answer.
    // OpenRouter's controls must not reach other compatible endpoints.
    if (endpoint.host == 'openrouter.ai')
      'reasoning': {'enabled': false, 'exclude': true},
  });
}
