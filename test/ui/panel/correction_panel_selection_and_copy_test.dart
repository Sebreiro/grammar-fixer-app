import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_card.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_list.dart';

import '../panel_harness.dart';

/// Selecting (CAP-4) and copying (CAP-11, CAP-14) — two distinct acts, which is
/// the whole of AD-18's last rule: the digits highlight, the buttons transfer,
/// and neither does the other's job.
///
/// Both are refused while a correction is still streaming: AD-3 calls deltas "a
/// progressive-rendering optimisation, never the record of truth", so a copy
/// taken from one would put a half-sentence on the clipboard that
/// `CorrectionCompleted` is about to replace.
void main() {
  late PanelHarness harness;

  setUp(() => harness = PanelHarness());
  tearDown(() => harness.dispose());

  Finder cardOf(SuggestionRegister register) => find.byWidgetPredicate(
    (widget) => widget is SuggestionCard && widget.register == register,
  );

  Finder copyButtonOf(SuggestionRegister register) => find.descendant(
    of: cardOf(register),
    matching: find.widgetWithText(TextButton, "Copy"),
  );

  SuggestionCard card(WidgetTester tester, SuggestionRegister register) =>
      tester.widget<SuggestionCard>(cardOf(register));

  /// The colour the card's `1`/`2`/`3` hint is painted in — the visible half of
  /// whether that key does anything.
  Color? hintColorOf(WidgetTester tester, SuggestionRegister register) {
    final index = SuggestionRegister.values.indexOf(register);
    return tester
        .widget<Text>(
          find.descendant(
            of: cardOf(register),
            matching: find.text('${index + 1}'),
          ),
        )
        .style
        ?.color;
  }

  /// AD-6's key, derived the way the panel derives it: the ids of `digit1` to
  /// `digit9` are the characters `'1'` to `'9'`.
  LogicalKeyboardKey digitFor(SuggestionRegister register) =>
      LogicalKeyboardKey(
        LogicalKeyboardKey.digit1.keyId +
            SuggestionRegister.values.indexOf(register),
      );

  Future<void> pressDigitFor(
    WidgetTester tester,
    SuggestionRegister register,
  ) async {
    await tester.sendKeyEvent(digitFor(register));
    await tester.pump();
  }

  Future<void> startCorrection(WidgetTester tester) async {
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
  }

  Future<void> completedSession(WidgetTester tester) async {
    await startCorrection(tester);
    await harness.completeRun(tester);
  }

  Future<void> tapCopy(WidgetTester tester, SuggestionRegister register) async {
    await tester.tap(copyButtonOf(register));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('CAP-4: a register\'s digit highlights that row and leaves the '
      'clipboard untouched', (tester) async {
    final chosen = SuggestionRegister.values[1];
    await completedSession(tester);

    await pressDigitFor(tester, chosen);

    expect(card(tester, chosen).selected, isTrue);
    for (final other in SuggestionRegister.values.where((r) => r != chosen)) {
      expect(card(tester, other).selected, isFalse);
    }
    expect(
      harness.clipboard.writes,
      isEmpty,
      reason: 'AD-18: copying is never implicit in selection',
    );
  });

  testWidgets('AD-18: the highlight survives typing in the editor — it belongs '
      'to the variant, not to the draft', (tester) async {
    final chosen = SuggestionRegister.values[1];
    await completedSession(tester);
    await pressDigitFor(tester, chosen);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'a second thought');
    await tester.pump();

    expect(harness.state.editorText, equals('a second thought'));
    expect(
      harness.state.selectedRegister,
      equals(chosen),
      reason:
          'editing the original does not un-pick the variant the user '
          'already chose; only a new run or a new session does (AD-18)',
    );
    expect(card(tester, chosen).selected, isTrue);
  });

  testWidgets('CAP-4: the highlight is rendered, not just recorded', (
    tester,
  ) async {
    final chosen = SuggestionRegister.values[1];
    await completedSession(tester);
    final theme = Theme.of(tester.element(find.byType(SuggestionList)));

    for (final register in SuggestionRegister.values) {
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: cardOf(register),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        equals(theme.colorScheme.surfaceContainer),
        reason: 'nothing is highlighted before a digit is pressed',
      );
    }

    await pressDigitFor(tester, chosen);

    expect(
      tester
          .widget<Material>(
            find
                .descendant(of: cardOf(chosen), matching: find.byType(Material))
                .first,
          )
          .color,
      equals(theme.colorScheme.primaryContainer),
      reason: 'a highlight the user cannot see is not a highlight (CAP-4)',
    );
    for (final other in SuggestionRegister.values.where((r) => r != chosen)) {
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: cardOf(other),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        equals(theme.colorScheme.surfaceContainer),
      );
    }
  });

  testWidgets('PANEL-02: selecting the same digit again keeps the highlight', (
    tester,
  ) async {
    final chosen = SuggestionRegister.values[1];
    await completedSession(tester);

    await pressDigitFor(tester, chosen);
    await pressDigitFor(tester, chosen);

    expect(harness.state.selectedRegister, equals(chosen));
    for (final register in SuggestionRegister.values) {
      expect(card(tester, register).selected, equals(register == chosen));
    }
  });

  testWidgets('AD-6: the keypad digit selects the same row as the digit row, '
      'both derived from the register\'s index', (tester) async {
    final chosen = SuggestionRegister.values[1];
    await completedSession(tester);

    await tester.sendKeyEvent(
      LogicalKeyboardKey(
        LogicalKeyboardKey.numpad1.keyId +
            SuggestionRegister.values.indexOf(chosen),
      ),
    );
    await tester.pump();

    expect(harness.state.selectedRegister, equals(chosen));
  });

  testWidgets('CAP-4: a variant\'s key hint is dimmed while its key would do '
      'nothing, and plain once it works', (tester) async {
    final first = SuggestionRegister.values.first;
    await startCorrection(tester);
    harness.run.emit(
      SuggestionDelta(register: first, textDelta: 'half-streamed'),
    );
    await tester.pump();
    await tester.pump();
    final theme = Theme.of(tester.element(find.byType(SuggestionList)));

    expect(
      hintColorOf(tester, first),
      equals(theme.disabledColor),
      reason:
          'while the deltas stream the digit selects nothing (AD-3), and a '
          'hint that promises otherwise is the DW-3 affordance sin again',
    );

    await harness.completeRun(tester);

    expect(hintColorOf(tester, first), equals(theme.colorScheme.onSurface));
  });

  testWidgets('CAP-11: a variant that came back as whitespace is neither '
      'copyable nor selectable', (tester) async {
    final blank = SuggestionRegister.values.first;
    await startCorrection(tester);
    harness.run.emit(
      CorrectionCompleted(
        suggestions: [
          for (final register in SuggestionRegister.values)
            Suggestion(
              register: register,
              text: register == blank ? '   \n ' : 'text for ${register.name}',
            ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextButton>(copyButtonOf(blank)).onPressed,
      isNull,
      reason: 'writing spaces over the user\'s clipboard is not a copy',
    );
    await pressDigitFor(tester, blank);
    expect(harness.state.selectedRegister, isNull);
    expect(harness.clipboard.writes, isEmpty);
  });

  testWidgets('CAP-3: a digit pressed in the editor is text, and highlights '
      'nothing', (tester) async {
    await completedSession(tester);

    // Back to the editor, the way a user who wants to keep typing gets there.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await pressDigitFor(tester, SuggestionRegister.values[1]);

    expect(harness.state.selectedRegister, isNull);
    for (final register in SuggestionRegister.values) {
      expect(card(tester, register).selected, isFalse);
    }

    await tester.enterText(find.byType(TextField), 'draft 2');
    await tester.pump();
    expect(harness.state.editorText, equals('draft 2'));
    expect(harness.state.selectedRegister, isNull);
  });

  testWidgets('AD-3: a digit pressed while the correction streams highlights '
      'nothing — there is nothing authoritative to select', (tester) async {
    await startCorrection(tester);
    harness.run.emit(
      SuggestionDelta(
        register: SuggestionRegister.values.first,
        textDelta: 'half-streamed',
      ),
    );
    await tester.pump();
    await tester.pump();

    await pressDigitFor(tester, SuggestionRegister.values.first);

    expect(harness.state.selectedRegister, isNull);
    expect(card(tester, SuggestionRegister.values.first).selected, isFalse);
  });

  testWidgets('AD-3: no row offers a copy while the correction streams', (
    tester,
  ) async {
    await startCorrection(tester);
    harness.run.emit(
      SuggestionDelta(
        register: SuggestionRegister.values.first,
        textDelta: 'half-streamed',
      ),
    );
    await tester.pump();
    await tester.pump();

    for (final register in SuggestionRegister.values) {
      expect(
        tester.widget<TextButton>(copyButtonOf(register)).onPressed,
        isNull,
        reason: 'a partial is not the record of truth (AD-3)',
      );
    }
    expect(harness.clipboard.writes, isEmpty);
  });

  testWidgets('CAP-11: a variant that came back empty offers no copy, rather '
      'than a button that does nothing', (tester) async {
    await startCorrection(tester);
    harness.run.emit(
      CorrectionCompleted(
        suggestions: [
          for (final register in SuggestionRegister.values)
            Suggestion(
              register: register,
              text: register == SuggestionRegister.values.first ? '' : 'text',
            ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(copyButtonOf(SuggestionRegister.values.first))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(copyButtonOf(SuggestionRegister.values.last))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('CAP-11: a row\'s copy button writes exactly that row\'s text, '
      'once', (tester) async {
    final chosen = SuggestionRegister.values[1];
    await completedSession(tester);

    await tapCopy(tester, chosen);

    expect(
      harness.clipboard.writes,
      equals([PanelHarness.completedTexts()[chosen]]),
    );
  });

  testWidgets('CAP-14: copying one variant leaves the panel open with every '
      'other variant still copyable', (tester) async {
    final first = SuggestionRegister.values.first;
    final last = SuggestionRegister.values.last;
    await completedSession(tester);

    await tapCopy(tester, first);
    await tapCopy(tester, last);

    expect(
      harness.clipboard.writes,
      equals([
        PanelHarness.completedTexts()[first],
        PanelHarness.completedTexts()[last],
      ]),
    );
    expect(
      find.byType(SuggestionCard),
      findsNWidgets(SuggestionRegister.values.length),
    );
    expect(
      harness.panelVisibility.isVisible,
      isTrue,
      reason:
          'a copy is not a dismissal; only the toggle and the focus-loss '
          'hide take the panel away (CAP-14, AD-4)',
    );
  });

  testWidgets('CAP-11: a rejected write shows one inline notice, logs the type '
      'only, and does not disable the next copy', (tester) async {
    final first = SuggestionRegister.values.first;
    final last = SuggestionRegister.values.last;
    await completedSession(tester);
    harness.clipboard.writeError = StateError('no clipboard owner');

    await tapCopy(tester, first);

    final notice = harness.state.copyFailure;
    expect(notice, isNotNull);
    expect(
      find.text("Couldn't copy this suggestion. Try again."),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(
      harness.state.failure,
      isNull,
      reason:
          'a failed copy is not a '
          'failed correction, so it offers no Retry',
    );
    expect(find.text('Retry'), findsNothing);

    final logged = harness.logger.lines.last;
    expect(logged.level, equals('error'));
    expect(logged.context, equals({'error_type': 'StateError'}));
    for (final line in harness.logger.lines) {
      expect(
        '${line.message} ${line.context}',
        isNot(contains(PanelHarness.completedTexts()[first])),
        reason: 'no log line carries a suggestion body',
      );
    }

    harness.clipboard.writeError = null;
    await tapCopy(tester, last);

    expect(
      harness.clipboard.writes,
      equals([PanelHarness.completedTexts()[last]]),
    );
    expect(harness.state.copyFailure, isNull);
    expect(
      find.text("Couldn't copy this suggestion. Try again."),
      findsNothing,
    );
  });

  testWidgets('AD-18: copying does not select and selecting does not copy', (
    tester,
  ) async {
    final copied = SuggestionRegister.values.first;
    final selected = SuggestionRegister.values[1];
    await completedSession(tester);

    await tapCopy(tester, copied);
    expect(
      harness.state.selectedRegister,
      isNull,
      reason: 'a copy is not a highlight',
    );

    await pressDigitFor(tester, selected);
    expect(harness.state.selectedRegister, equals(selected));
    expect(
      harness.clipboard.writes,
      equals([PanelHarness.completedTexts()[copied]]),
      reason: 'the digit added no second write',
    );
  });

  testWidgets('CAP-4: a held digit selects once — auto-repeat does not toggle '
      'the highlight back off', (tester) async {
    // `SingleActivator` accepts key repeats by default, and selecting is a
    // toggle: with the default a held key flips the highlight once per repeat
    // event and lands on whichever parity the release happens to leave.
    final chosen = SuggestionRegister.values[1];
    await completedSession(tester);

    await tester.sendKeyDownEvent(digitFor(chosen));
    await tester.pump();
    expect(harness.state.selectedRegister, equals(chosen));

    for (var repeat = 0; repeat < 3; repeat++) {
      await tester.sendKeyRepeatEvent(digitFor(chosen));
      await tester.pump();
    }
    await tester.sendKeyUpEvent(digitFor(chosen));
    await tester.pump();

    expect(
      harness.state.selectedRegister,
      equals(chosen),
      reason: 'three repeats would have left it deselected',
    );
    expect(card(tester, chosen).selected, isTrue);
  });

  testWidgets('CAP-4: a digit brings its variant into view — a highlight below '
      'the fold is a key that did nothing visible', (tester) async {
    tester.view.physicalSize = const Size(480, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final long = List.filled(
      40,
      'I have gone to the store and bought the thing',
    ).join(' ');
    await startCorrection(tester);
    await harness.completeRun(tester, long);

    final last = SuggestionRegister.values.last;
    final listRect = tester.getRect(find.byType(SuggestionList));
    final label = find.descendant(
      of: cardOf(last),
      matching: find.text(last.label),
    );

    expect(
      tester.getRect(label).top,
      greaterThan(listRect.bottom),
      reason:
          'the fixture has to start with the last variant below the fold, or '
          'this row proves nothing',
    );

    await pressDigitFor(tester, last);
    // The scroll is decided from the card's geometry, so it happens after the
    // frame that highlighted it.
    await tester.pump();

    final revealed = tester.getRect(label);
    expect(
      revealed.top,
      greaterThanOrEqualTo(listRect.top - 0.5),
      reason: 'scrolled into the variants viewport, not past its top',
    );
    expect(revealed.top, lessThan(listRect.bottom));
    expect(harness.state.selectedRegister, equals(last));
  });

  testWidgets('CAP-11: each copy button says which variant it copies, so three '
      'identical icons are distinguishable without seeing them', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await completedSession(tester);

    for (final register in SuggestionRegister.values) {
      expect(
        tester
            .getSemantics(
              find.byTooltip("Copy the ${register.label} suggestion"),
            )
            .tooltip,
        equals('Copy the ${register.label} suggestion'),
        reason: 'CAP-11 is "each suggestion has its own button"',
      );
    }

    handle.dispose();
  });

  testWidgets('CAP-11: the copy failure is announced, not only painted', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await completedSession(tester);
    harness.clipboard.writeError = StateError('no clipboard owner');

    await tapCopy(tester, SuggestionRegister.values.first);

    final notice = harness.state.copyFailure;
    expect(notice, isNotNull);
    expect(
      tester
          .getSemantics(find.text("Couldn't copy this suggestion. Try again."))
          .flagsCollection
          .isLiveRegion,
      isTrue,
      reason:
          'a notice assistive tech never reads leaves the user believing the '
          'copy succeeded — the silent lie copyFailure exists to prevent',
    );

    handle.dispose();
  });

  testWidgets('CAP-11: a second variant\'s failed copy is a different notice, '
      'so there is something new to announce', (tester) async {
    final first = SuggestionRegister.values.first;
    final second = SuggestionRegister.values[1];
    await completedSession(tester);
    harness.clipboard.writeError = StateError('no clipboard owner');

    await tapCopy(tester, first);
    final firstNotice = harness.state.copyFailure;
    await tapCopy(tester, second);
    final secondNotice = harness.state.copyFailure;

    expect(firstNotice, contains(first.name));
    expect(secondNotice, contains(second.name));
    expect(
      secondNotice,
      isNot(equals(firstNotice)),
      reason:
          'an identical sentence is an ==-equal state: the live region has '
          'nothing to re-announce and a distinct() consumer drops it',
    );
    expect(
      find.text("Couldn't copy this suggestion. Try again."),
      findsOneWidget,
    );
  });
}
