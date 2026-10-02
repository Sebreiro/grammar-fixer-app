import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/gtk_panel_activation_presenter.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/panel_activation.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/window_manager_panel_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'com.divertedriver.HotkeyGrammarCorrector/panel_activation',
  );
  const presenter = GtkPanelActivationPresenter();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'CAP-1: warm window focus delivers portal or tray provenance to GTK',
    () async {
      final window = WindowManagerPanelWindow(activationPresenter: presenter);
      addTearDown(window.dispose);
      await presenter.initialize();
      await window.focus(activation: const PanelActivation.portal('fresh'));
      await window.focus(activation: const PanelActivation.tray());
      await window.focus();

      expect(calls.map((call) => call.method), [
        'initialize',
        'present',
        'present',
        'present',
      ]);
      expect(calls[1].arguments, {'token': 'fresh', 'fromTray': false});
      expect(calls[2].arguments, {'token': null, 'fromTray': true});
      expect(calls[3].arguments, {'token': null, 'fromTray': false});
    },
  );

  test(
    'CAP-1: a disposed window cannot present with an activation token',
    () async {
      final window = WindowManagerPanelWindow(activationPresenter: presenter);
      await window.dispose();
      await window.focus(activation: const PanelActivation.portal('abandoned'));
      expect(calls, isEmpty);
    },
  );

  test(
    'CAP-1: native presentation failure reaches the visibility caller',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'invalid-activation');
      });
      await expectLater(
        presenter.present(const PanelActivation.tray()),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
