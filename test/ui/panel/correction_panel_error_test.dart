import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/correction_error_notice.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/correction_panel.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_card.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_list.dart';

import '../../fakes/throwing_logger.dart';
import '../panel_harness.dart';

/// CAP-13: the failure is rendered *inside* the panel, in place of the empty or
/// half-streamed variants, with a Retry that re-runs the captured input.
///
/// "Inline" is asserted negatively as well as positively: no `SnackBar`, no
/// dialog, no second route anywhere in the tree. CAP-13 rules those out by name.
void main() {
  late PanelHarness harness;

  setUp(() => harness = PanelHarness());
  tearDown(() => harness.dispose());

  const failed = CorrectionFailed(
    kind: CorrectionFailureKind.providerError,
    message: 'the corrector stopped answering. Try again.',
  );

  Future<void> startCorrection(WidgetTester tester) async {
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
  }

  Future<void> emitTerminal(WidgetTester tester, CorrectionEvent event) async {
    harness.run.emit(event);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('CAP-13: the error replaces the half-streamed rows inside the '
      'panel, with no dialog, snackbar or second route in the tree', (
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
    expect(find.text('half-streamed'), findsOneWidget);

    await emitTerminal(tester, failed);

    expect(find.text(failed.message), findsOneWidget);
    expect(find.byType(CorrectionErrorNotice), findsOneWidget);
    expect(find.text('half-streamed'), findsNothing);
    expect(find.byType(SuggestionList), findsNothing);
    expect(find.byType(SuggestionCard), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    // Deliberately no assertion about `Tooltip`: CAP-13 rules out a toast, a
    // dialog and a separate window, and a tooltip is none of those — the copy
    // buttons carry one so that three identical icons are distinguishable to a
    // screen reader (CAP-11).
    expect(
      find.byType(CorrectionPanel),
      findsOneWidget,
      reason: 'the user never left the panel they were already looking at',
    );
  });

  testWidgets('CAP-13: the panel renders the failure\'s own message and adds '
      'nothing of its own to it', (tester) async {
    await startCorrection(tester);

    await emitTerminal(tester, failed);

    expect(
      find.textContaining(failed.kind.name),
      findsNothing,
      reason: 'the failure kind is a log-side classification, not a sentence',
    );
    expect(
      tester
          .widget<CorrectionErrorNotice>(find.byType(CorrectionErrorNotice))
          .message,
      equals(failed.message),
    );
  });

  testWidgets('CAP-13: Retry re-runs the captured submitted text, not what the '
      'editor holds now (AD-18)', (tester) async {
    await harness.pumpSession(tester);
    await tester.enterText(find.byType(TextField), 'the text i submitted');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'typed on while it ran');
    await tester.pump();
    await emitTerminal(tester, failed);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    await tester.pump();

    expect(
      harness.provider.correctCalls.map((call) => call.text),
      equals(['the text i submitted', 'the text i submitted']),
    );
  });

  testWidgets('CAP-13: a Retry that succeeds puts the variants back in place '
      'of the notice', (tester) async {
    await startCorrection(tester);
    await emitTerminal(tester, failed);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    await tester.pump();
    await harness.completeRun(tester);

    expect(find.byType(CorrectionErrorNotice), findsNothing);
    expect(find.text(failed.message), findsNothing);
    expect(
      find.byType(SuggestionCard),
      findsNWidgets(SuggestionRegister.values.length),
    );
  });

  testWidgets('CAP-13: the inline failure is announced, not only painted', (
    tester,
  ) async {
    // The copy-failure notice got a live region; this one — the message about
    // the variants *vanishing* — did not, so the panel announced the lesser of
    // its two failures and stayed silent about the greater.
    final handle = tester.ensureSemantics();
    await startCorrection(tester);
    await emitTerminal(tester, failed);

    expect(
      tester
          .getSemantics(find.text(failed.message))
          .flagsCollection
          .isLiveRegion,
      isTrue,
      reason:
          'the suggestions this replaces simply disappear; a user who cannot '
          'see the message is left with a panel that lost its answer silently',
    );

    handle.dispose();
  });

  testWidgets('AD-15: a logger whose own sink is gone does not turn the '
      "panel's report into an unhandled error", (tester) async {
    // The ui-ring instance of the swallow all three controllers carry, and the
    // only one with no `ThrowingLogger` row: deleting the `try`/`on Object`
    // from the panel's `_report` left every widget test green. The daemon runs
    // `StderrLogger`, whose sink a closed parent terminal turns into a broken
    // pipe — and this report fires from a stream callback, so a throw out of it
    // becomes an unhandled async error in the daemon's zone at shutdown.
    final throwing = ThrowingLogger();
    harness = PanelHarness(installedLogger: throwing);
    await harness.pumpSession(tester);

    harness.container.dispose();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(
      throwing.attempts,
      isNotEmpty,
      reason: 'the panel must still have tried to report the closed stream',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AD-15: a state stream that closes under a mounted panel is '
      'reported, and leaves the last correction on screen', (tester) async {
    await startCorrection(tester);
    await harness.completeRun(tester);
    final rendered = PanelHarness.completedTexts().values.first;
    expect(find.text(rendered), findsOneWidget);

    // What shutdown does: the controller closes `changes` while this tree is
    // still mounted. There is no live session to render after it, so the panel
    // keeps what it has rather than blanking the variants out from under a user
    // who may still be reading them.
    harness.container.dispose();
    // `runAsync`, not a plain pump: the container's teardown hands the
    // controller's async `dispose()` off outside the test's fake-async zone,
    // and closing the stream sits behind the subscription cancel it awaits
    // first — so only real event-loop turns get there.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.text(rendered), findsOneWidget);
    expect(
      harness.logger.lines.map((line) => line.message),
      contains('the panel state stream closed while the panel was mounted'),
      reason:
          'a subscription that silently stops delivering is the one '
          'failure a panel cannot show and an operator cannot guess',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('CAP-13: the notice lays out in an unbounded-height parent, so '
      'the error path cannot be what breaks the panel', (tester) async {
    // The panel gives it a bounded box today. This pins the notice's own
    // contract instead of that call site: a widget whose whole job is to render
    // a failure must not throw at layout when the tree around it changes.
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: Column(
            children: [
              CorrectionErrorNotice(message: failed.message, onRetry: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(failed.message), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('AD-3: a completed event with a malformed register set reaches '
      'the panel as an inline error, never as suggestions', (tester) async {
    await startCorrection(tester);

    await emitTerminal(
      tester,
      CorrectionCompleted(
        suggestions: [
          Suggestion(
            register: SuggestionRegister.values.first,
            text: 'the only variant that came back',
          ),
        ],
      ),
    );

    expect(find.byType(CorrectionErrorNotice), findsOneWidget);
    expect(find.text('the only variant that came back'), findsNothing);
    expect(find.byType(SuggestionCard), findsNothing);
  });
}
