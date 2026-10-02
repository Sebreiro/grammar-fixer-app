import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/correction_panel.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_card.dart';

import '../panel_harness.dart';

void main() {
  late PanelHarness harness;
  final clipboardWrites = <String>[];
  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);
  const failure = CorrectionFailed(
    kind: CorrectionFailureKind.providerError,
    message: 'The provider stopped answering. Try again.',
  );

  setUp(() {
    harness = PanelHarness();
    clipboardWrites.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final arguments = call.arguments as Map<Object?, Object?>;
              final text = arguments['text'];
              if (text is String) {
                clipboardWrites.add(text);
              }
              return null;
            case 'Clipboard.hasStrings':
              return {'value': clipboardWrites.isNotEmpty};
            case 'Clipboard.getData':
              return {'text': clipboardWrites.lastOrNull};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    harness.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Finder selectable(String text) => find.byWidgetPredicate(
    (widget) => widget is SelectableText && widget.data == text,
  );

  Finder editableOf(Finder text) =>
      find.descendant(of: text, matching: find.byType(EditableText));

  Offset positionOf(WidgetTester tester, Finder text, int offset) {
    final editable = tester.state<EditableTextState>(editableOf(text));
    return editable.renderEditable.localToGlobal(
      editable.renderEditable
          .getLocalRectForCaret(TextPosition(offset: offset))
          .center,
    );
  }

  Future<void> selectWithMouse(
    WidgetTester tester,
    Finder text,
    TextSelection selection,
  ) async {
    await tester.ensureVisible(text);
    await tester.pump();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final start = positionOf(tester, text, selection.start);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await gesture.moveTo(positionOf(tester, text, selection.end));
    await gesture.up();
    await gesture.removePointer();
    await tester.pump();
  }

  Future<void> controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> copyWithMenu(WidgetTester tester, Finder text) async {
    await tester.tapAt(
      positionOf(tester, text, 8),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Paste'), findsNothing);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
  }

  Future<void> startCorrection(WidgetTester tester) async {
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
  }

  Future<void> showFailure(WidgetTester tester) async {
    await startCorrection(tester);
    harness.run.emit(failure);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('CAP-11 CAP-14: mouse-selected correction text copies with '
      'Ctrl+C and leaves the panel open', (tester) async {
    await startCorrection(tester);
    await harness.completeRun(tester);
    final text = PanelHarness.completedTexts().values.first;
    final output = selectable(text);

    await selectWithMouse(
      tester,
      output,
      const TextSelection(baseOffset: 4, extentOffset: 13),
    );
    expect(clipboardWrites, isEmpty);
    await controlKey(tester, LogicalKeyboardKey.keyC);

    expect(clipboardWrites, ['corrected']);
    expect(harness.panelVisibility.isVisible, isTrue);
    expect(find.byType(CorrectionPanel), findsOneWidget);
    expect(harness.clipboard.writes, isEmpty);
    expect(harness.repository.saved, hasLength(1));
  }, variant: desktop);

  testWidgets('CAP-11: right-click Copy preserves and copies the selected '
      'correction substring', (tester) async {
    await startCorrection(tester);
    await harness.completeRun(tester);
    final text = PanelHarness.completedTexts().values.first;
    final output = selectable(text);

    await selectWithMouse(
      tester,
      output,
      const TextSelection(baseOffset: 4, extentOffset: 13),
    );
    await copyWithMenu(tester, output);

    expect(clipboardWrites, ['corrected']);
    expect(harness.panelVisibility.isVisible, isTrue);
  }, variant: desktop);

  testWidgets(
    'CAP-11: Ctrl+A and Ctrl+C copy each entire read-only correction',
    (tester) async {
      await startCorrection(tester);
      await harness.completeRun(tester);

      for (final text in PanelHarness.completedTexts().values) {
        final output = selectable(text);
        await tester.ensureVisible(output);
        await tester.tap(output, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await controlKey(tester, LogicalKeyboardKey.keyA);
        await controlKey(tester, LogicalKeyboardKey.keyC);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(output, findsOneWidget);
        expect(
          tester.widget<EditableText>(editableOf(output)).controller.text,
          text,
        );
        expect(clipboardWrites.last, text);
      }

      expect(clipboardWrites, PanelHarness.completedTexts().values.toList());
      expect(harness.panelVisibility.isVisible, isTrue);
    },
    variant: desktop,
  );

  testWidgets(
    'CAP-4: tapping completed text keeps mouse and digit selection',
    (tester) async {
      await startCorrection(tester);
      await harness.completeRun(tester);
      final register = SuggestionRegister.values.first;
      final text = PanelHarness.completedTexts().values.first;

      await tester.tap(selectable(text), kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(harness.state.selectedRegister, register);
      expect(clipboardWrites, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(harness.state.selectedRegister, SuggestionRegister.values[1]);
    },
    variant: desktop,
  );

  testWidgets('CAP-13 CAP-14: mouse-selected error text copies with Ctrl+C '
      'without dismissing the panel', (tester) async {
    await showFailure(tester);
    final output = selectable(failure.message);

    await selectWithMouse(
      tester,
      output,
      const TextSelection(baseOffset: 4, extentOffset: 30),
    );
    await controlKey(tester, LogicalKeyboardKey.keyC);

    expect(clipboardWrites, ['provider stopped answering']);
    expect(harness.panelVisibility.isVisible, isTrue);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  }, variant: desktop);

  testWidgets('CAP-13: right-click Copy copies selected error text and Retry '
      'still runs the same correction', (tester) async {
    await showFailure(tester);
    final output = selectable(failure.message);

    await selectWithMouse(
      tester,
      output,
      const TextSelection(baseOffset: 4, extentOffset: 30),
    );
    await copyWithMenu(tester, output);
    expect(clipboardWrites, ['provider stopped answering']);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    expect(harness.provider.correctCalls, hasLength(2));
    expect(
      harness.provider.correctCalls.last.text,
      harness.provider.correctCalls.first.text,
    );
  }, variant: desktop);

  testWidgets('CAP-13: Ctrl+A and Ctrl+C copy the entire read-only error', (
    tester,
  ) async {
    await showFailure(tester);
    final output = selectable(failure.message);

    await tester.tap(output, kind: PointerDeviceKind.mouse);
    await controlKey(tester, LogicalKeyboardKey.keyA);
    await controlKey(tester, LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(clipboardWrites, [failure.message]);
    expect(output, findsOneWidget);
    expect(
      tester.widget<EditableText>(editableOf(output)).controller.text,
      failure.message,
    );
    expect(harness.state.failure?.message, failure.message);
  }, variant: desktop);

  testWidgets('CAP-11: inline copy errors can also be selected and copied', (
    tester,
  ) async {
    await startCorrection(tester);
    await harness.completeRun(tester);
    harness.clipboard.writeError = StateError('clipboard unavailable');
    final first = find.byWidgetPredicate(
      (widget) =>
          widget is SuggestionCard &&
          widget.register == SuggestionRegister.values.first,
    );
    await tester.tap(
      find.descendant(of: first, matching: find.byType(IconButton)),
    );
    await tester.pump();
    await tester.pump();
    const message = "Couldn't copy this suggestion. Try again.";
    final output = selectable(message);

    await tester.tap(output, kind: PointerDeviceKind.mouse);
    await controlKey(tester, LogicalKeyboardKey.keyA);
    await controlKey(tester, LogicalKeyboardKey.keyC);

    expect(clipboardWrites, [message]);
    expect(harness.panelVisibility.isVisible, isTrue);
  }, variant: desktop);

  testWidgets(
    'CAP-5 AD-3: streamed partials do not offer selection copying',
    (tester) async {
      await startCorrection(tester);
      harness.run.emit(
        SuggestionDelta(
          register: SuggestionRegister.values.first,
          textDelta: 'half-streamed',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('half-streamed'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(
        find.text('half-streamed'),
        kind: PointerDeviceKind.mouse,
      );
      await controlKey(tester, LogicalKeyboardKey.keyC);
      expect(clipboardWrites, isEmpty);
    },
    variant: desktop,
  );
}
