import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_card.dart';

import '../panel_harness.dart';

/// Streaming (CAP-5) and the shape of the rows it streams into (CAP-4, AD-6).
///
/// The order and the key digits are asserted by *deriving* both from
/// `SuggestionRegister.values`, never by naming `formal`, `casual` or `shorter`
/// positionally: AD-6 says a reorder or an added register must carry the panel
/// with it, and a test that spells the names out is a test that would have to be
/// edited alongside the enum.
void main() {
  late PanelHarness harness;

  setUp(() => harness = PanelHarness());
  tearDown(() => harness.dispose());

  Finder cardOf(SuggestionRegister register) => find.byWidgetPredicate(
    (widget) => widget is SuggestionCard && widget.register == register,
  );

  SuggestionCard card(WidgetTester tester, SuggestionRegister register) =>
      tester.widget<SuggestionCard>(cardOf(register));

  Future<void> startCorrection(WidgetTester tester) async {
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
  }

  Future<void> emitDelta(
    WidgetTester tester,
    SuggestionRegister register,
    String textDelta,
  ) async {
    harness.run.emit(SuggestionDelta(register: register, textDelta: textDelta));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('CAP-5: each register\'s row shows its own partial text as the '
      'deltas arrive, interleaved and out of order', (tester) async {
    final registers = SuggestionRegister.values;
    await startCorrection(tester);

    await emitDelta(tester, registers.last, 'Gone ');
    await emitDelta(tester, registers.first, 'I have ');
    await emitDelta(tester, registers.last, 'to the store.');

    expect(card(tester, registers.first).text, equals('I have '));
    expect(card(tester, registers.last).text, equals('Gone to the store.'));
    expect(find.text('I have '), findsOneWidget);
    expect(find.text('Gone to the store.'), findsOneWidget);
  });

  testWidgets('AD-3: the completed suggestions replace every half-streamed '
      'row, so nothing from a delta is still on screen', (tester) async {
    await startCorrection(tester);
    await emitDelta(tester, SuggestionRegister.values.first, 'half-streamed');
    expect(find.text('half-streamed'), findsOneWidget);

    await harness.completeRun(tester);

    expect(find.text('half-streamed'), findsNothing);
    for (final entry in PanelHarness.completedTexts().entries) {
      expect(card(tester, entry.key).text, equals(entry.value));
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('AD-6: the rows are SuggestionRegister.values, top to bottom, '
      'in that order', (tester) async {
    await startCorrection(tester);
    await harness.completeRun(tester);

    final rendered = tester
        .widgetList<SuggestionCard>(find.byType(SuggestionCard))
        .map((card) => card.register)
        .toList();
    expect(rendered, equals(SuggestionRegister.values));

    // Tree order is not screen order, so the rects are asserted too: the enum's
    // order is the *panel's* order, which is what CAP-4's 1/2/3 refers to.
    final tops = SuggestionRegister.values
        .map((register) => tester.getTopLeft(cardOf(register)).dy)
        .toList();
    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: 'row $i must sit below row ${i - 1}',
      );
    }
  });

  testWidgets('AD-6: each row\'s key hint is its own indexOf + 1, and its '
      'label is the register\'s name', (tester) async {
    await startCorrection(tester);
    await harness.completeRun(tester);

    // Gathered rather than asserted register by register: a loop that throws on
    // the first mismatch would report one wrong key where the mapping is wrong
    // for several, and "the hint is always 1" is exactly that shape.
    expect(
      [
        for (final register in SuggestionRegister.values)
          card(tester, register).keyHint,
      ],
      equals([
        for (final register in SuggestionRegister.values)
          '${SuggestionRegister.values.indexOf(register) + 1}',
      ]),
      reason: 'AD-6 makes the selecting key indexOf + 1, per register',
    );

    for (final register in SuggestionRegister.values) {
      final index = SuggestionRegister.values.indexOf(register);
      expect(
        find.descendant(
          of: cardOf(register),
          matching: find.text('${index + 1}'),
        ),
        findsOneWidget,
        reason: 'the hint AD-6 derives must be the one on screen',
      );
      expect(
        find.descendant(
          of: cardOf(register),
          matching: find.text(register.name),
        ),
        findsOneWidget,
        reason: 'the label derives from .name and is never written out',
      );
    }
  });

  testWidgets('CAP-5: the panel shows real progress from the submit until the '
      'answer lands, so a waiting user is not looking at an idle panel', (
    tester,
  ) async {
    await harness.pumpSession(tester);
    expect(
      find.byType(LinearProgressIndicator),
      findsNothing,
      reason: 'an idle session has nothing in flight to report',
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(
      find.byType(LinearProgressIndicator),
      findsOneWidget,
      reason:
          'this is the one state CAP-1 puts the user in, and a panel that '
          'looks idle invites a second Correct press that cancels the run '
          'being waited for (AD-4)',
    );
    await emitDelta(tester, SuggestionRegister.values.first, 'I have ');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await harness.completeRun(tester);

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('CAP-5: the progress affordance is announced, not only painted', (
    tester,
  ) async {
    // Otherwise "running looks like idle" is fixed for sighted users only, and
    // the trap it was fixed for — pressing Correct again, which under AD-4
    // cancels the run being waited for — stays fully open for everyone else.
    final handle = tester.ensureSemantics();
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    final progress = tester.getSemantics(find.byType(LinearProgressIndicator));
    expect(progress.label, equals('correcting'));
    expect(progress.flagsCollection.isLiveRegion, isTrue);

    handle.dispose();
  });

  testWidgets('CAP-13: the progress affordance is gone once the correction '
      'failed, replaced by the error rather than joined by it', (tester) async {
    await startCorrection(tester);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    harness.run.emit(
      const CorrectionFailed(
        kind: CorrectionFailureKind.timeout,
        message: 'the corrector timed out. Try again.',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('the corrector timed out. Try again.'), findsOneWidget);
  });

  testWidgets('CAP-5: a register with no delta yet still holds its row, so '
      'the list does not reflow as text arrives', (tester) async {
    await startCorrection(tester);

    await emitDelta(tester, SuggestionRegister.values.first, 'only this one');

    expect(
      find.byType(SuggestionCard),
      findsNWidgets(SuggestionRegister.values.length),
    );
    for (final register in SuggestionRegister.values.skip(1)) {
      expect(card(tester, register).text, isEmpty);
    }
  });
}
