import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_card.dart';

import '../ui/panel_harness.dart';
import '../ui/settings_harness.dart';

void main() {
  late SettingsHarness harness;

  setUp(() => harness = SettingsHarness());
  tearDown(() => harness.dispose());

  testWidgets('CAP-1 CAP-3 CAP-5 CAP-7 CAP-11 CAP-14: a hotkey correction '
      'streams, persists, and copies while the panel stays open', (
    tester,
  ) async {
    await harness.pump(tester);
    await harness.summon(tester);

    expect(harness.clipboard.readCalls, 1);
    expect(find.text('i has went to the store'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'i has went home');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(harness.provider.correctCalls.single.text, 'i has went home');
    harness.run.emit(
      const SuggestionDelta(
        register: SuggestionRegister.formal,
        textDelta: 'I have gone',
      ),
    );
    await tester.pump();
    expect(find.text('I have gone'), findsOneWidget);
    expect(harness.repository.saved, isEmpty);

    harness.run.emit(PanelHarness.completedEvent('Corrected'));
    await tester.pump();
    await tester.pump();

    final record = harness.repository.saved.single;
    expect(record.inputText, 'i has went home');
    expect(record.outcome, CorrectionOutcome.completed);
    expect(record.suggestions, hasLength(SuggestionRegister.values.length));
    expect(record.suggestions.first.text, 'Corrected formal text');
    expect(find.text('I have gone'), findsNothing);

    final copyButton = find.byTooltip('Copy the formal suggestion');
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pump();
    await tester.pump();

    expect(harness.clipboard.writes, ['Corrected formal text']);
    expect(harness.panelVisibility.isVisible, isTrue);
    expect(find.byType(SuggestionCard), findsNWidgets(3));
  });
}
