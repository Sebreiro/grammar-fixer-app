import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/controller_providers.dart';
import 'package:hotkey_grammar_corrector/src/application/correction_state.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_card.dart';

import '../panel_harness.dart';

/// The micro-editor half of the panel: the CAP-2 re-seed, CAP-3 editing, the
/// AD-18 replacement on the summon after a dismissal, DW-3's disabled Correct
/// action, and where the keyboard is at each step.
///
/// Headless — nothing here needs a display. What it therefore does *not*
/// observe is stated in the story's completion notes: that the window appears,
/// that it takes the keyboard from another application, and that the real
/// system clipboard is what seeded it.
void main() {
  late PanelHarness harness;

  setUp(() => harness = PanelHarness());
  tearDown(() => harness.dispose());

  TextField editor(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  String editorText(WidgetTester tester) =>
      editor(tester).controller?.text ?? '';

  ElevatedButton correctButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byType(ElevatedButton));

  testWidgets('CAP-2: the panel shows the clipboard text the show re-seeded '
      'from, and corrects nothing on its own', (tester) async {
    harness.clipboard.text = 'i has went';

    await harness.pumpSession(tester);

    expect(editorText(tester), equals('i has went'));
    expect(find.text('i has went'), findsOneWidget);
    expect(
      harness.provider.correctCalls,
      isEmpty,
      reason: 'CAP-2 pre-fills the editor; correcting is the user\'s act',
    );
  });

  testWidgets('CAP-2: a clipboard that cannot be read leaves the editor empty '
      'and the panel usable', (tester) async {
    harness.clipboard.readError = StateError('no selection owner');

    await harness.pumpSession(tester);

    expect(editorText(tester), isEmpty);
    await tester.enterText(find.byType(TextField), 'typed by hand');
    await tester.pump();

    expect(harness.state.editorText, equals('typed by hand'));
    expect(correctButton(tester).onPressed, isNotNull);
  });

  testWidgets('CAP-3: what the user types is what the controller holds and '
      'what a submit sends', (tester) async {
    await harness.pumpSession(tester);

    await tester.enterText(find.byType(TextField), 'i have gone to the store');
    await tester.pump();
    expect(harness.state.editorText, equals('i have gone to the store'));

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(
      harness.provider.correctCalls.single.text,
      equals('i have gone to the store'),
    );
  });

  testWidgets('CAP-3: replacing the controller under a mounted panel keeps '
      'the unsubmitted editor draft', (tester) async {
    await harness.pumpSession(tester);
    await tester.enterText(find.byType(TextField), 'an unsaved draft');
    await tester.pump();
    final previous = harness.controller;

    harness.container.invalidate(correctionControllerProvider);
    await tester.pump();
    await tester.pump();

    expect(harness.controller, isNot(same(previous)));
    expect(editorText(tester), 'an unsaved draft');
    expect(harness.state.editorText, 'an unsaved draft');
  });

  testWidgets('CAP-3: Ctrl+Enter submits the editor, so Enter stays the '
      'multi-line editor\'s own key', (tester) async {
    await harness.pumpSession(tester);
    await tester.enterText(find.byType(TextField), 'first line');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(harness.provider.correctCalls.single.text, equals('first line'));
  });

  testWidgets('CAP-3: Ctrl+Enter submits from the keypad too, the way every '
      'selection slot answers to its keypad twin', (tester) async {
    // The keypad's Enter is `numpadEnter`, a different logical key. Every 1/2/3
    // slot was deliberately given its keypad twin; the accelerator was not, so
    // a user submitting from the pad pressed a key that did nothing at all —
    // no run, no line, no affordance change.
    await harness.pumpSession(tester);
    await tester.enterText(find.byType(TextField), 'first line');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(harness.provider.correctCalls.single.text, equals('first line'));
  });

  testWidgets('CAP-3: the Correct action names its accelerator, so the one '
      'keystroke that starts a correction is discoverable', (tester) async {
    // The panel dims a variant's 1/2/3 hint when the key would do nothing; the
    // submit accelerator was advertised nowhere at all.
    await harness.pumpSession(tester);

    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.widgetWithText(ElevatedButton, 'Correct'),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      equals('Correct (Ctrl+Enter)'),
    );
  });

  testWidgets('AD-4: a held Ctrl+Enter acts once — auto-repeat does not submit '
      'again', (tester) async {
    // `SingleActivator` accepts key repeats by default, and `submit()` cancels
    // the in-flight run before starting the next — so a held accelerator would
    // kill and re-spawn a correction once per repeat event.
    //
    // Asserted on a *blank* editor, which is the only case where the repeats can
    // reach the accelerator at all: a submit that starts a run hands focus to
    // the variants, and the accelerator is scoped to the editor subtree, so from
    // the second press onwards the key is already out of scope. That second
    // guard is not the one this row is about.
    harness.clipboard.text = '   ';
    await harness.pumpSession(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    for (var repeat = 0; repeat < 3; repeat++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
      harness.logger.lines
          .where((line) => line.message == 'an empty editor was not submitted')
          .length,
      equals(1),
      reason:
          'one press, one refusal: three repeats would have called submit() '
          'four times over',
    );
    expect(harness.provider.correctCalls, isEmpty);
  });

  testWidgets('AD-18: a dismissal and a summon replace the editor with the '
      'clipboard, and nothing of the last session survives', (tester) async {
    harness.clipboard.text = 'first copy';
    await harness.pumpSession(tester);
    await tester.enterText(find.byType(TextField), 'edited by the user');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await harness.completeRun(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(harness.state.selectedRegister, isNotNull);

    await harness.hide(tester);
    harness.clipboard.text = 'second copy';
    await harness.show(tester);

    expect(editorText(tester), equals('second copy'));
    // CAP-1 promises a panel that is *focused*, and the tree is never rebuilt
    // (AD-8), so the editor's `autofocus` fired for the first session only —
    // without a re-focus on every session this summon eats the first keystroke.
    expect(
      editor(tester).focusNode?.hasFocus,
      isTrue,
      reason: 'the second summon must be typeable without a click too',
    );
    tester.testTextInput.enterText('typed with no click');
    await tester.pump();
    expect(harness.state.editorText, equals('typed with no click'));

    expect(harness.state.suggestionTexts, isEmpty);
    expect(harness.state.submittedText, isNull);
    expect(harness.state.failure, isNull);
    expect(harness.state.selectedRegister, isNull);
    for (final card in tester.widgetList<SuggestionCard>(
      find.byType(SuggestionCard),
    )) {
      expect(card.text, isEmpty);
      expect(card.selected, isFalse);
    }
    expect(
      find.text(PanelHarness.completedTexts()[SuggestionRegister.formal] ?? ''),
      findsNothing,
    );
  });

  testWidgets('DW-3: the Correct action is disabled while the editor is '
      'empty, so the empty-submit invariant has an affordance', (tester) async {
    harness.clipboard.text = null;

    await harness.pumpSession(tester);

    expect(correctButton(tester).onPressed, isNull);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(harness.provider.correctCalls, isEmpty);
  });

  testWidgets('DW-3: an editor holding only spaces and newlines is not '
      'submittable either, by key or by button', (tester) async {
    harness.clipboard.text = '  \n\t ';

    await harness.pumpSession(tester);
    expect(editorText(tester), equals('  \n\t '));
    expect(correctButton(tester).onPressed, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(harness.provider.correctCalls, isEmpty);
    expect(harness.state.status, equals(CorrectionStatus.idle));
  });

  testWidgets('DW-3: the accelerator on a blank editor reaches the '
      'controller\'s own guard rather than being refused by the widget', (
    tester,
  ) async {
    harness.clipboard.text = '   ';
    await harness.pumpSession(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(harness.provider.correctCalls, isEmpty);
    expect(
      harness.logger.lines.map((line) => line.message),
      contains('an empty editor was not submitted'),
      reason:
          'the invariant is the controller\'s and its line is what tells an '
          'operator why a Correct press did nothing; the disabled button is '
          'the affordance on top of it, not a replacement for it',
    );
    expect(
      editor(tester).focusNode?.hasFocus,
      isTrue,
      reason:
          'a refused submit must not move the caret out of the editor the '
          'user still has to type in',
    );
  });

  testWidgets('AD-4: Ctrl+Enter in the suggestions region does not re-run and '
      'discard a correction the user is reading (CAP-13)', (tester) async {
    await harness.pumpSession(tester);
    await tester.enterText(find.byType(TextField), 'i has went');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await harness.completeRun(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
      harness.provider.correctCalls,
      hasLength(1),
      reason:
          'the accelerator belongs to the editor; here it would cancel the '
          'run whose answer is on screen (AD-4) and throw that answer away',
    );
    expect(harness.state.status, equals(CorrectionStatus.completed));
    expect(harness.state.selectedRegister, isNotNull);
  });

  testWidgets('CAP-3: typing does not move the caret to the end of the '
      'line, so the re-seed cannot fight the user', (tester) async {
    harness.clipboard.text = 'i has went';
    await harness.pumpSession(tester);

    final controller = editor(tester).controller;
    controller?.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    expect(controller?.selection.baseOffset, equals(5));

    // The rebuild the controller answers a keystroke with must leave the
    // caret alone; only a genuinely different text replaces the field.
    harness.controller.editText('i has went');
    await tester.pump();

    expect(controller?.selection.baseOffset, equals(5));
  });

  testWidgets('DW-30: a return that begins no session leaves the caret where '
      'the user left it, and the editor holding what they typed', (
    tester,
  ) async {
    // The user-visible half of DW-30, and the only place a widget stands behind
    // it: everything else about the three-way rule is asserted at the
    // controller. A focus loss (CAP-14) is a departure the session survives, so
    // the panel that comes back was never rebuilt — the text is still there and
    // nothing pulled the caret anywhere.
    //
    // Submitting first is deliberate. It moves focus into the suggestions
    // region, which makes the claim falsifiable: if the return began a session
    // the panel would put the caret back in the editor, exactly as the second
    // summon after a dismissal does two rows above. That the caret stays in the
    // suggestions region is the rule working rather than a defect — nothing was
    // rebuilt, so nothing moved.
    await harness.pumpSession(tester);
    await tester.enterText(find.byType(TextField), 'what the user typed');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(editor(tester).focusNode?.hasFocus, isFalse);

    harness.panelVisibility.loseFocus();
    await tester.pump();
    harness.clipboard.text = 'a clipboard this return must not read';
    await harness.show(tester);

    expect(
      editorText(tester),
      equals('what the user typed'),
      reason: 'a click-away did not ask for the text to be thrown away',
    );
    expect(
      editor(tester).focusNode?.hasFocus,
      isFalse,
      reason:
          'and no session began, so nothing asked for the caret back — it is '
          'still in the suggestions region where the submit put it',
    );
  });

  testWidgets('CAP-3: focus starts in the editor and submitting hands it to '
      'the suggestions region', (tester) async {
    await harness.pumpSession(tester);

    expect(
      editor(tester).focusNode?.hasFocus,
      isTrue,
      reason: 'a summoned panel must be typeable without a click (CAP-1)',
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(
      editor(tester).focusNode?.hasFocus,
      isFalse,
      reason:
          'the 1/2/3 keys are scoped to the suggestions region, so submit '
          'is what puts them in reach',
    );
  });
}
