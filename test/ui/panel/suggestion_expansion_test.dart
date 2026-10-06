import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_expansion.dart';

import '../panel_harness.dart';

void main() {
  testWidgets('CAP-11/14: expanded copy failure is visible and retry copies '
      'the full answer without closing the panel', (tester) async {
    final harness = PanelHarness();
    addTearDown(harness.dispose);
    harness.clipboard.text = 'please correct this';
    await harness.pumpSession(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Correct'));
    await tester.pump();
    final answer = List.generate(20, (index) => 'Line $index.').join('\n');
    await harness.completeRun(tester, answer);
    await tester.tap(find.text('Show more').first);
    await tester.pumpAndSettle();
    final copy = find.byTooltip('Copy expanded Corrected suggestion');
    harness.clipboard.writeError = StateError('clipboard unavailable');
    await tester.tap(copy);
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(SuggestionExpansion),
        matching: find.text("Couldn't copy this suggestion. Try again."),
      ),
      findsOneWidget,
    );
    expect(harness.clipboard.writes, isEmpty);
    harness.clipboard.writeError = null;
    await tester.tap(copy);
    await tester.pump();
    await tester.pump();
    expect(harness.clipboard.writes, [
      '$answer ${SuggestionRegister.formal.name} text',
    ]);
    expect(find.text('Show less'), findsOneWidget);
    expect(harness.panelVisibility.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'CAP-10/11: long previews expand and copy the exact full answer',
    (tester) async {
      final harness = PanelHarness();
      addTearDown(harness.dispose);
      harness.clipboard.text = 'please correct this';
      await harness.pumpSession(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Correct'));
      await tester.pump();
      final answer = List.generate(20, (index) => '  Line $index.').join('\n');
      await harness.completeRun(tester, answer);
      expect(find.text('Show more'), findsWidgets);
      await tester.tap(find.text('Show more').first);
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy expanded Corrected suggestion'));
      await tester.pump();
      await tester.pump();
      expect(harness.clipboard.writes, [
        '$answer ${SuggestionRegister.formal.name} text',
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsNothing);
      expect(harness.panelVisibility.isVisible, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
