import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/ui/settings/settings_failure_notice.dart';

import '../settings_harness.dart';

void main() {
  late SettingsHarness harness;
  setUp(() => harness = SettingsHarness());
  tearDown(() => harness.dispose());

  final promptField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText == 'Correction prompt',
  );
  final saveButton = find.widgetWithText(FilledButton, 'Save prompt');

  String draft(WidgetTester tester) =>
      tester.widget<TextField>(promptField).controller?.text ?? '';

  AppConfig withPrompt(String prompt) {
    final config = harness.configStore.current;
    return config.copyWith(
      presets: [
        for (final preset in config.presets)
          if (preset.id == config.activePresetId)
            Preset(
              id: preset.id,
              providerId: preset.providerId,
              model: preset.model,
              systemPrompt: prompt,
            )
          else
            preset,
      ],
    );
  }

  Future<void> edit(WidgetTester tester, String prompt) async {
    await tester.ensureVisible(promptField);
    await tester.enterText(promptField, prompt);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'CAP-8: Settings displays and saves the active correction prompt',
    (tester) async {
      await harness.pumpSettings(tester);
      expect(draft(tester), SettingsHarness.defaultPreset.systemPrompt);
      const prompt = 'Correct grammar.\nPreserve my intent.\n';
      await edit(tester, prompt);
      await save(tester);
      expect(
        harness.configStore.writes.single.presets.first.systemPrompt,
        prompt,
      );
      expect(
        harness.configStore.current.presets.first.model,
        SettingsHarness.defaultPreset.model,
      );
      expect(draft(tester), prompt);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    },
  );

  testWidgets('CAP-8: config edits update a clean prompt editor', (
    tester,
  ) async {
    await harness.pumpSettings(tester);
    await harness.configStore.write(withPrompt('Changed in config.'));
    await tester.pumpAndSettle();
    expect(draft(tester), 'Changed in config.');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
  });

  testWidgets(
    'CAP-8: conflicting config edits preserve the draft with a notice',
    (tester) async {
      await harness.pumpSettings(tester);
      await edit(tester, 'Unsaved draft.');
      await harness.configStore.write(withPrompt('External edit.'));
      await tester.pumpAndSettle();
      expect(draft(tester), 'Unsaved draft.');
      expect(
        find.textContaining('prompt changed while you were editing'),
        findsOneWidget,
      );
      await save(tester);
      expect(
        harness.configStore.current.presets.first.systemPrompt,
        'Unsaved draft.',
      );
      expect(
        find.textContaining('prompt changed while you were editing'),
        findsNothing,
      );
    },
  );

  testWidgets('CAP-8: switching presets discards the previous prompt draft', (
    tester,
  ) async {
    await harness.pumpSettings(tester);
    await edit(tester, 'Unsaved old preset prompt.');
    final option = find.widgetWithText(ListTile, SettingsHarness.fastPreset.id);
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(draft(tester), SettingsHarness.fastPreset.systemPrompt);
    expect(
      harness.configStore.current.presets.first,
      SettingsHarness.defaultPreset,
    );
  });

  testWidgets(
    'CAP-8: a failed prompt save leaves a draft that can be retried',
    (tester) async {
      await harness.pumpSettings(tester);
      harness.configStore.writeError = StateError('disk unavailable');
      await edit(tester, 'Retry this prompt.');
      await save(tester);
      expect(
        harness.configStore.current.presets.first,
        SettingsHarness.defaultPreset,
      );
      expect(draft(tester), 'Retry this prompt.');
      expect(find.byType(SettingsFailureNotice), findsOneWidget);
      harness.configStore.writeError = null;
      await save(tester);
      expect(
        harness.configStore.current.presets.first.systemPrompt,
        'Retry this prompt.',
      );
      expect(find.byType(SettingsFailureNotice), findsNothing);
    },
  );

  testWidgets('CAP-8: blank prompts cannot be saved', (tester) async {
    await harness.pumpSettings(tester);
    await edit(tester, ' \n\t');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    expect(
      tester.widget<TextField>(promptField).decoration?.errorText,
      'Required',
    );
    expect(harness.configStore.writes, isEmpty);
  });

  testWidgets('CAP-8: the prompt editor is disabled while saving', (
    tester,
  ) async {
    await harness.pumpSettings(tester);
    final gate = Completer<void>();
    harness.configStore.writeGate = gate;
    await edit(tester, 'A pending prompt.');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    expect(tester.widget<TextField>(promptField).enabled, isFalse);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(promptField).enabled, isTrue);
    expect(
      harness.configStore.current.presets.first.systemPrompt,
      'A pending prompt.',
    );
  });
}
