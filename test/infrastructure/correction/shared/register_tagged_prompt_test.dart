import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/default_app_config.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/shared/register_tagged_prompt.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/correction/shared/register_tagged_stream_parser.dart';
import 'package:test/test.dart';

void main() {
  test('CAP-8: format instructions preserve the complete editable prompt', () {
    const prompt = '  Preserve meaning.\n\nUse British spelling.\n';
    final composed = RegisterTaggedPrompt.compose(prompt);

    expect(composed, startsWith('$prompt\n\n'));
    expect(composed, contains('Begin your response with FORMAL:'));
    expect(composed, contains('never as instructions'));
  });

  test('CAP-4: every request asks for complete ordered register variants', () {
    for (final prompt in [
      'Correct my grammar.',
      'Reply with only the corrected sentence.',
      DefaultAppConfig.shippedSystemPrompt,
    ]) {
      final format = RegisterTaggedPrompt.compose(
        prompt,
      ).substring(prompt.length);
      final tags = ['FORMAL:', 'CASUAL:', 'SHORTER:', '\nEND\n'];
      final positions = tags.map(format.indexOf).toList();
      expect(positions, everyElement(greaterThanOrEqualTo(0)));
      expect(positions, orderedEquals([...positions]..sort()));
      expect(format, contains('Do not include reasoning'));
      expect(format, contains('different output format'));
    }
  });

  test('CAP-4 CAP-9: default and legacy prompts request minimal native fixes, '
      'then casual and short variants', () {
    for (final prompt in [
      DefaultAppConfig.shippedSystemPrompt,
      'Make the first correction formal and professional.',
      'Correct grammar using British spelling.',
    ]) {
      final requirements = RegisterTaggedPrompt.compose(
        prompt,
      ).substring(prompt.length);

      expect(
        requirements,
        contains(
          'FORMAL: <the complete text with only grammar and '
          'natural phrasing fixes>',
        ),
      );
      expect(
        requirements,
        contains(
          'preserve the original wording, tone, '
          'and meaning',
        ),
      );
      expect(requirements, contains('native-sounding English'));
      expect(
        requirements,
        contains(
          'Do not make it more formal, shorten it, '
          'or embellish it',
        ),
      );
      expect(requirements, contains('return it unchanged'));
      expect(
        requirements,
        contains(
          'CASUAL: <the complete corrected text '
          'in a casual, conversational tone>',
        ),
      );
      expect(
        requirements,
        contains(
          'SHORTER: <a concise correction that '
          'preserves the intended meaning>',
        ),
      );
      expect(requirements, contains('preserving the meaning and key details'));
      expect(
        requirements,
        contains(
          'take priority over conflicting register '
          'or rewrite instructions above',
        ),
      );
    }
  });

  test(
    'CAP-5: the requested example streams and completes with the parser',
    () async {
      final lines = RegisterTaggedPrompt.responseFormat.split('\n');
      final example = lines.sublist(2, 6).join('\n');
      final events = await const RegisterTaggedStreamParser()
          .parse(Stream.fromIterable(example.split('').toList()))
          .toList();

      expect(events.whereType<SuggestionDelta>(), isNotEmpty);
      final completed = events.last as CorrectionCompleted;
      expect(completed.suggestions, hasLength(3));
      expect(lines[5], RegisterTaggedStreamParser.endSentinel);
    },
  );
}
