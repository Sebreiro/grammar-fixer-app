import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/clipboard/system_clipboard.dart';

/// CAP-2's pre-fill and CAP-11's copy, at the channel the engine actually
/// uses.
///
/// `SystemClipboard` is a two-line adapter, and the two lines that matter are
/// the ones a fake cannot check: which platform method is invoked, and what
/// the platform's answer is turned into. Null in particular is a *modelled
/// value* — an empty clipboard is not a failed read — and the difference
/// between "resolved null" and "rejected" is the difference between an empty
/// editor and a warning in the daemon log.
///
/// Needs a Flutter binding for the mocked `SystemChannels.platform`, hence
/// `test/platform/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final channel = SystemChannels.platform;
  late List<MethodCall> platformCalls;

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      platformCalls.add(call);
      return handler(call);
    });
  }

  setUp(() => platformCalls = <MethodCall>[]);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'CAP-2: readText resolves to the plain text the clipboard holds',
    () async {
      answerWith((_) async => <String, Object?>{'text': 'hello'});

      expect(await const SystemClipboard().readText(), 'hello');
      expect(platformCalls.single.method, 'Clipboard.getData');
      expect(platformCalls.single.arguments, Clipboard.kTextPlain);
    },
  );

  test('CAP-2: readText resolves to null when the clipboard holds no plain '
      'text — absence is a modelled value, not an error', () async {
    answerWith((_) async => null);

    expect(await const SystemClipboard().readText(), isNull);
  });

  test('CAP-2: a denied read propagates as a failed future, never as a null '
      'standing in for an empty clipboard', () async {
    answerWith(
      (_) async => throw PlatformException(code: 'clipboard-unavailable'),
    );

    await expectLater(
      const SystemClipboard().readText(),
      throwsA(isA<PlatformException>()),
      reason:
          'CorrectionController logs the rejection and leaves the editor '
          'empty; reporting an empty clipboard it never read would be the '
          'faked behaviour AGENTS.md §8 rules out',
    );
  });

  test(
    'CAP-11: writeText puts exactly the given string on the clipboard',
    () async {
      answerWith((_) async => null);

      await const SystemClipboard().writeText('corrected');

      expect(platformCalls.single.method, 'Clipboard.setData');
      expect(platformCalls.single.arguments, <String, Object?>{
        'text': 'corrected',
      });
    },
  );

  test('CAP-11: a refused write propagates as a failed future', () async {
    answerWith((_) async => throw PlatformException(code: 'denied'));

    await expectLater(
      const SystemClipboard().writeText('corrected'),
      throwsA(isA<PlatformException>()),
    );
  });
}
