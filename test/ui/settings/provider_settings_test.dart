import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/secret_write_result.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/config_fallback_provider_key_writer.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/config/provider_secret_fields.dart';
import 'package:hotkey_grammar_corrector/src/ui/settings/settings_failure_notice.dart';

import '../../fakes/fake_provider_key_writer.dart';
import '../settings_harness.dart';

void main() {
  late SettingsHarness harness;
  late FakeProviderKeyWriter writer;

  final baseUrl = _field('Base URL');
  final model = _field('Model');
  final keyField = _field('API key');

  setUp(() {
    harness = SettingsHarness(
      config: SettingsHarness.defaultConfig.copyWith(
        providers: {
          'claude-agent-sdk':
              SettingsHarness.defaultConfig.providers['claude-agent-sdk'] ??
              const ProviderConfig(settings: {}),
        },
        presets: [SettingsHarness.defaultPreset, SettingsHarness.fastPreset],
      ),
    );
    writer = FakeProviderKeyWriter();
    harness.settings.attachProviderKeyWriter(
      ConfigFallbackProviderKeyWriter(
        keyring: writer,
        configStore: harness.configStore,
      ),
    );
    harness.settings.attachApiKeySourceLabel((provider) async {
      if (writer.writes.isNotEmpty &&
          writer.result == SecretWriteResult.saved) {
        return 'System keyring';
      }
      return provider.settings.containsKey(ProviderSecretFields.configKey)
          ? 'Config file'
          : 'None configured';
    });
  });
  tearDown(() => harness.dispose());

  Future<void> choose(WidgetTester tester, String providerId) async {
    final option = find.byKey(ValueKey('provider-$providerId'));
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'CAP-8: fresh URL setup activates one provider and keeps Claude configuration',
    (tester) async {
      await harness.pumpSettings(tester);
      await harness.selectCategory(tester, 'AI');
      expect(baseUrl, findsNothing);
      expect(model, findsNothing);
      expect(keyField, findsNothing);
      await choose(tester, ProviderConfig.compatibleProviderId);
      expect(harness.configStore.writes, isEmpty);
      expect(find.textContaining('Save the URL and model'), findsOneWidget);
      expect(find.text(SettingsHarness.fastPreset.id), findsNothing);
      await tester.enterText(baseUrl, 'https://api.example/v1');
      await tester.enterText(model, 'url-model');
      await press(tester, 'Save provider settings');

      final saved = harness.configStore.current;
      final active = harness.state.activePreset;
      expect(active?.providerId, ProviderConfig.compatibleProviderId);
      expect(active?.model, 'url-model');
      expect(saved.presets, contains(SettingsHarness.defaultPreset));
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        ProviderConfig.compatibleProviderId,
      );
      expect(find.text(SettingsHarness.fastPreset.id), findsNothing);

      await choose(tester, 'claude-agent-sdk');
      expect(baseUrl, findsNothing);
      expect(keyField, findsNothing);
      expect(harness.state.activePreset?.providerId, 'claude-agent-sdk');
      expect(find.text(SettingsHarness.fastPreset.id), findsOneWidget);
      expect(harness.state.compatibleBaseUrl, 'https://api.example/v1');
      await choose(tester, ProviderConfig.compatibleProviderId);
      expect(harness.state.activePreset, active);
      expect(
        tester.widget<TextField>(baseUrl).controller?.text,
        'https://api.example/v1',
      );
      expect(harness.configStore.current.presets, hasLength(3));
    },
  );

  testWidgets(
    'CAP-8: masked key entry saves to the keyring and clears only after success',
    (tester) async {
      await harness.pumpSettings(tester);
      await harness.selectCategory(tester, 'AI');
      await choose(tester, ProviderConfig.compatibleProviderId);
      final field = tester.widget<TextField>(keyField);
      expect(field.obscureText, isTrue);
      expect(field.controller?.text, isEmpty);
      await tester.enterText(keyField, 'private-key');
      await press(tester, 'Save API key');
      expect(writer.writes.single.apiKey, 'private-key');
      expect(field.controller?.text, isEmpty);
      expect(find.text('API key saved.'), findsOneWidget);
      expect(find.text('API key source: System keyring'), findsOneWidget);
      expect(harness.configStore.writes, isEmpty);
    },
  );

  testWidgets(
    'CAP-13: failure in both stores leaves the draft retryable and controls unlock',
    (tester) async {
      writer.result = SecretWriteResult.unavailable;
      harness.configStore.writeError = StateError('private-key');
      await harness.pumpSettings(tester);
      await harness.selectCategory(tester, 'AI');
      await choose(tester, ProviderConfig.compatibleProviderId);
      await tester.enterText(keyField, 'private-key');
      await press(tester, 'Save API key');
      expect(find.byType(SettingsFailureNotice), findsOneWidget);
      expect(
        tester.widget<TextField>(keyField).controller?.text,
        'private-key',
      );
      expect(find.text('API key saved.'), findsNothing);
      expect(harness.configStore.writes, isEmpty);
      harness.configStore.writeError = null;
      await press(tester, 'Save API key');
      expect(find.byType(SettingsFailureNotice), findsNothing);
      expect(tester.widget<TextField>(keyField).controller?.text, isEmpty);
      expect(find.text('API key saved.'), findsOneWidget);
      expect(find.text('API key source: Config file'), findsOneWidget);
    },
  );

  testWidgets(
    'CAP-8: inaccessible keyring saving clears the draft and shows config storage',
    (tester) async {
      writer.result = SecretWriteResult.unavailable;
      await harness.pumpSettings(tester);
      await harness.selectCategory(tester, 'AI');
      await choose(tester, ProviderConfig.compatibleProviderId);
      await tester.enterText(keyField, ' private-key ');
      await press(tester, 'Save API key');

      expect(tester.widget<TextField>(keyField).controller?.text, isEmpty);
      expect(find.byType(SettingsFailureNotice), findsNothing);
      expect(find.text('API key saved.'), findsOneWidget);
      expect(find.text('API key source: Config file'), findsOneWidget);
      expect(
        find.textContaining('stored as plaintext in config.json'),
        findsOneWidget,
      );
      expect(find.text('private-key'), findsNothing);
      expect(
        harness
            .configStore
            .current
            .providers[ProviderConfig.compatibleProviderId]
            ?.settings[ProviderSecretFields.configKey],
        'private-key',
      );
    },
  );

  testWidgets(
    'CAP-8: fallback persistence keeps controls locked and the draft until committed',
    (tester) async {
      writer.result = SecretWriteResult.unavailable;
      final gate = Completer<void>();
      harness.configStore.writeGate = gate;
      await harness.pumpSettings(tester);
      await harness.selectCategory(tester, 'AI');
      await choose(tester, ProviderConfig.compatibleProviderId);
      await tester.enterText(keyField, 'private-key');
      final save = find.widgetWithText(FilledButton, 'Save API key');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();

      expect(tester.widget<TextField>(keyField).enabled, isFalse);
      expect(
        tester.widget<TextField>(keyField).controller?.text,
        'private-key',
      );
      expect(find.text('API key saved.'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(keyField).enabled, isTrue);
      expect(tester.widget<TextField>(keyField).controller?.text, isEmpty);
      expect(find.text('API key source: Config file'), findsOneWidget);
    },
  );

  testWidgets(
    'CAP-8: a keyring prompt disables provider choices and form fields',
    (tester) async {
      final gate = Completer<void>();
      writer.gate = gate;
      await harness.pumpSettings(tester);
      await harness.selectCategory(tester, 'AI');
      await choose(tester, ProviderConfig.compatibleProviderId);
      await tester.enterText(keyField, 'private-key');
      final save = find.widgetWithText(FilledButton, 'Save API key');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<TextField>(keyField).enabled, isFalse);
      expect(tester.widget<TextField>(baseUrl).enabled, isFalse);
      expect(tester.widget<TextField>(model).enabled, isFalse);
      for (final tile in tester.widgetList<RadioListTile<String>>(
        find.byType(RadioListTile<String>),
      )) {
        expect(tile.enabled, isFalse);
      }
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(keyField).enabled, isTrue);
    },
  );

  testWidgets(
    'CAP-13: a failed provider switch keeps the committed radio choice',
    (tester) async {
      await harness.settings.configureCompatibleProvider(
        baseUrl: 'https://api.example/v1',
        model: 'model',
      );
      await harness.pumpSettings(tester);
      await harness.selectCategory(tester, 'AI');
      harness.configStore.writeError = StateError('read-only');
      await choose(tester, 'claude-agent-sdk');
      expect(
        harness.state.activePreset?.providerId,
        ProviderConfig.compatibleProviderId,
      );
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        ProviderConfig.compatibleProviderId,
      );
      expect(find.byType(SettingsFailureNotice), findsOneWidget);
    },
  );
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
