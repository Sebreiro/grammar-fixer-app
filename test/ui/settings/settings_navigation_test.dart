import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import '../settings_harness.dart';

void main() {
  for (final size in const [
    Size(840, 650),
    Size(640, 520),
    Size(480, 360),
    Size(320, 520),
    Size(1100, 700),
  ]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'CAP-8/12: Settings ${size.width}x${size.height} $brightness ${scale}x reaches each category',
          (tester) async {
            final harness = SettingsHarness();
            addTearDown(harness.dispose);
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.platformBrightnessTestValue = brightness;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearAllTestValues);
            await harness.pumpSettings(tester);
            expect(find.text('When closing the window'), findsOneWidget);
            await harness.selectCategory(tester, 'AI');
            expect(find.text('AI provider'), findsOneWidget);
            await harness.selectCategory(tester, 'Advanced');
            final prompt = find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'Correction prompt',
            );
            await tester.ensureVisible(prompt);
            await tester.enterText(prompt, 'Draft at ${size.width}');
            await tester.pump();
            await tester.ensureVisible(find.text('Save prompt'));
            await tester.tap(find.text('Save prompt'));
            await tester.pumpAndSettle();
            expect(
              harness.state.activePreset?.systemPrompt,
              'Draft at ${size.width}',
            );
            await tester.tap(find.byType(BackButton));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  testWidgets(
    'CAP-8/12: unsaved credentials survive categories and clear on Back and summon',
    (tester) async {
      final harness = SettingsHarness();
      addTearDown(harness.dispose);
      await harness.pumpSettings(tester);
      await harness.selectCategory(tester, 'AI');
      await tester.tap(
        find.byKey(
          const ValueKey('provider-${ProviderConfig.compatibleProviderId}'),
        ),
      );
      await tester.pumpAndSettle();
      final key = field('API key');
      await tester.ensureVisible(key);
      await tester.enterText(key, 'secret draft');
      await harness.selectCategory(tester, 'Advanced');
      await harness.selectCategory(tester, 'AI');
      expect(tester.widget<TextField>(key).controller?.text, 'secret draft');
      expect(tester.widget<TextField>(key).obscureText, isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await harness.openSettings(tester);
      expect(tester.widget<TextField>(key).controller?.text, isEmpty);
      await tester.ensureVisible(key);
      await tester.enterText(key, 'another draft');
      await harness.summon(tester);
      await harness.openSettings(tester);
      expect(tester.widget<TextField>(key).controller?.text, isEmpty);
      expect(harness.configStore.writes, isEmpty);
    },
  );

  testWidgets(
    'CAP-8: dirty prompt survives external edits while away with overwrite warning',
    (tester) async {
      final harness = SettingsHarness();
      addTearDown(harness.dispose);
      await harness.pumpSettings(tester);
      await harness.selectCategory(tester, 'Advanced');
      await tester.enterText(field('Correction prompt'), 'Retained draft');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final config = harness.configStore.current;
      await harness.configStore.write(
        config.copyWith(
          presets: [
            for (final preset in config.presets)
              if (preset.id == config.activePresetId)
                Preset(
                  id: preset.id,
                  providerId: preset.providerId,
                  model: preset.model,
                  systemPrompt: 'External prompt',
                )
              else
                preset,
          ],
        ),
      );
      await tester.pump();
      await harness.openSettings(tester);
      expect(
        tester.widget<TextField>(field('Correction prompt')).controller?.text,
        'Retained draft',
      );
      expect(
        find.textContaining('prompt changed while you were editing'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Save prompt'));
      await tester.tap(find.text('Save prompt'));
      await tester.pumpAndSettle();
      expect(harness.state.activePreset?.systemPrompt, 'Retained draft');
    },
  );
  testWidgets('CAP-8/12: prompt draft survives category and Back navigation', (
    tester,
  ) async {
    final harness = SettingsHarness();
    addTearDown(harness.dispose);
    await harness.pumpSettings(tester);
    expect(find.text('General'), findsWidgets);
    await tester.tap(find.text('Advanced').first);
    await tester.pumpAndSettle();
    final prompt = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Correction prompt',
    );
    await tester.enterText(prompt, 'My unsaved prompt');
    await tester.tap(find.text('General').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(SettingsHarness.affordance);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(prompt).controller?.text,
      'My unsaved prompt',
    );
    expect(harness.configStore.writes, isEmpty);
  });
}
