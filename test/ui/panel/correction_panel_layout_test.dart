import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/correction_panel.dart';
import 'package:hotkey_grammar_corrector/src/ui/panel/suggestion_card.dart';

import '../panel_harness.dart';

/// CAP-10 at a small surface: the original and at least one variant are both
/// readable, "without scrolling one out of view", when both are long.
///
/// 480×360 is deliberately cramped — it is the constraint that makes the claim
/// worth asserting, since any layout satisfies it at 800×600. What this cannot
/// say is how the panel looks at the window's real size: this container has no
/// display, so the surface here is a choice of the test's, not an observation.
void main() {
  late PanelHarness harness;

  setUp(() => harness = PanelHarness());
  tearDown(() => harness.dispose());

  /// The panel's *own* viewport — the first `Scrollable` under it, which is the
  /// one `SingleChildScrollView` in `build()` wraps the whole layout in.
  ///
  /// Asked for by position rather than by type, because `find.byType(Scrollable)`
  /// is also satisfied by `SuggestionList`'s own scroll view and by the editor's
  /// internal one — so "a Scrollable exists" says nothing about whether the
  /// panel scrolls as a whole.
  ScrollPosition panelScroll(WidgetTester tester) => tester
      .firstState<ScrollableState>(
        find.descendant(
          of: find.byType(CorrectionPanel),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  /// A long original and long variants: the fixture that makes CAP-10's claim
  /// worth asserting, since any layout satisfies it with three short words.
  String longText(String sentence) => List.filled(40, sentence).join(' ');

  testWidgets('CAP-10: a long original and long variants are both on screen at '
      '480x360, with no overflow', (tester) async {
    const surface = Size(480, 360);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final longOriginal = List.filled(
      40,
      'i has went to the store and buyed the thing',
    ).join(' ');
    final longVariant = List.filled(
      40,
      'I have gone to the store and bought the thing',
    ).join(' ');

    harness.clipboard.text = longOriginal;
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await harness.completeRun(tester, longVariant);

    final first = SuggestionRegister.values.first;
    final firstCard = find.byWidgetPredicate(
      (widget) => widget is SuggestionCard && widget.register == first,
    );

    final editorRect = tester.getRect(find.byType(TextField));
    expect(editorRect.height, greaterThan(0));
    expect(editorRect.top, greaterThanOrEqualTo(0));
    expect(
      editorRect.bottom,
      lessThanOrEqualTo(surface.height),
      reason: 'the editor keeps its own bounded share of the panel',
    );

    // The first variant's label, its key hint and the start of its text are all
    // on screen beside the editor — not merely present in the tree.
    for (final inside in [
      find.descendant(of: firstCard, matching: find.text(first.label)),
      find.descendant(of: firstCard, matching: find.text('1')),
    ]) {
      final rect = tester.getRect(inside);
      expect(rect.height, greaterThan(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(surface.height));
    }

    final variantText = tester.getRect(
      find.descendant(
        of: firstCard,
        matching: find.text('$longVariant ${first.name} text'),
      ),
    );
    expect(
      variantText.top,
      greaterThan(editorRect.top),
      reason: 'the variants sit below the original, both visible (CAP-10)',
    );
    expect(
      variantText.top,
      lessThan(surface.height),
      reason: 'the first variant must not start below the bottom edge',
    );
    expect(
      variantText.height,
      greaterThan(0),
      reason: 'a variant clipped to nothing is not "readable"',
    );
    // `getRect` is global and answers for a child that is built but scrolled
    // out of the viewport, so "on screen" needs the visible band measured, not
    // just the top edge: without this, one outer scroll with the variants
    // pushed below the fold satisfies every check above.
    final visibleVariantText =
        (variantText.bottom < surface.height
            ? variantText.bottom
            : surface.height) -
        (variantText.top > 0 ? variantText.top : 0);
    expect(
      visibleVariantText,
      greaterThan(16),
      reason:
          'at least a line of the first variant has to be inside the '
          'viewport for CAP-10 to hold',
    );

    expect(
      tester.takeException(),
      isNull,
      reason:
          'a surface too small to satisfy CAP-10 must fail here rather '
          'than silently clip',
    );
  });

  testWidgets(
    'CAP-11: a copy notice does not take height off CAP-10\'s split',
    (tester) async {
      const surface = Size(480, 360);
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      harness.clipboard.text = 'i has went';
      await harness.pumpSession(tester);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await harness.completeRun(tester);
      final editorBefore = tester.getRect(find.byType(TextField));

      harness.clipboard.writeError = StateError('no clipboard owner');
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is SuggestionCard &&
                widget.register == SuggestionRegister.values.first,
          ),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump();
      await tester.pump();

      final notice = harness.state.copyFailure;
      expect(notice, isNotNull);
      expect(
        find.text("Couldn't copy this suggestion. Try again."),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byType(TextField)),
        equals(editorBefore),
        reason:
            'the notice belongs to the variants region; arriving between the '
            'two panes it would shrink the original the user is comparing '
            'against (CAP-10)',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('CAP-10: below the documented floor the panel scrolls as a whole '
      'rather than overflowing', (tester) async {
    // No code sets the window's size or a minimum for it, and a user can drag a
    // toplevel to any height — so the floor is what stands between a resize and
    // a RenderFlex overflow. 160 is well under it.
    const surface = Size(480, 160);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    harness.clipboard.text = 'i has went';
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await harness.completeRun(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'clipping and an overflow banner are both worse than scrolling',
    );
    expect(
      panelScroll(tester).maxScrollExtent,
      greaterThan(0),
      reason:
          'the panel itself has somewhere to scroll — the claim this row is '
          'named for. "A Scrollable exists" would be true with the outer scroll '
          'view deleted, because the variants have a scroll view of their own',
    );
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('CAP-10: at exactly the documented floor the original is '
      'readable, and the panel has nothing to scroll', (tester) async {
    // The floor is the height at which the class doc claims CAP-10 holds, so it
    // is the height CAP-10 has to be asserted at. "No overflow" is reached well
    // below it — at 240 the editor's share is 7.2 logical pixels, which
    // satisfies `height > 0` and no reader.
    final surface = Size(480, CorrectionPanel.minimumPanelHeight);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final longVariant = longText('I have gone to the store and bought it');
    harness.clipboard.text = longText('i has went to the store and buyed it');
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await harness.completeRun(tester, longVariant);

    final editorRect = tester.getRect(find.byType(TextField));
    expect(
      editorRect.height,
      greaterThanOrEqualTo(24),
      reason:
          'one full line of the editor\'s 16 px text. A share smaller than a '
          'line renders the original unreadable, which is the half of CAP-10 '
          'the floor exists to guarantee',
    );
    expect(editorRect.top, greaterThanOrEqualTo(0));
    expect(editorRect.bottom, lessThanOrEqualTo(surface.height));

    final first = SuggestionRegister.values.first;
    final firstCard = find.byWidgetPredicate(
      (widget) => widget is SuggestionCard && widget.register == first,
    );
    for (final inside in [
      find.descendant(of: firstCard, matching: find.text(first.label)),
      find.descendant(of: firstCard, matching: find.text('1')),
    ]) {
      final rect = tester.getRect(inside);
      expect(rect.height, greaterThan(0));
      expect(rect.top, greaterThan(editorRect.top));
      expect(rect.bottom, lessThanOrEqualTo(surface.height));
    }

    expect(
      panelScroll(tester).maxScrollExtent,
      equals(0),
      reason:
          'at and above the floor the box is the viewport, so the two panes '
          'split the surface rather than the whole panel scrolling',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('CAP-11: a narrow surface ellipsises the variant\'s label rather '
      'than overflowing its row and clipping the copy button', (tester) async {
    // Nothing sets the window's width or a minimum for it either, so a drag can
    // make the card's row narrower than its own contents. The label is what
    // gives way: the copy button has to stay on screen and hittable.
    const surface = Size(160, 360);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    harness.clipboard.text = 'i has went';
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await harness.completeRun(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'a RenderFlex overflow paints a yellow bar over the panel',
    );

    final first = SuggestionRegister.values.first;
    final copy = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is SuggestionCard && widget.register == first,
      ),
      matching: find.byType(IconButton),
    );
    final copyRect = tester.getRect(copy);
    expect(copyRect.right, lessThanOrEqualTo(surface.width));
    expect(copyRect.left, greaterThanOrEqualTo(0));

    await tester.tap(copy);
    await tester.pump();
    await tester.pump();

    expect(
      harness.clipboard.writes,
      equals([PanelHarness.completedTexts()[first]]),
      reason: 'clipped out of the row it would not have been reachable at all',
    );
  });

  testWidgets('CAP-11: a copy failure at a narrow surface does not overflow '
      'the region it is reported in', (tester) async {
    // Probe-measured before the fix: 120×300 — at the documented floor — is
    // clean until the copy fails, then the wrapped sentence overflows the
    // variants region by 23 px. A panel that reports a failed copy by painting
    // the overflow stripe over itself is a worse answer than saying nothing.
    final surface = Size(120, CorrectionPanel.minimumPanelHeight);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    harness.clipboard.text = 'i has went';
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await harness.completeRun(tester);
    expect(tester.takeException(), isNull);

    harness.clipboard.writeError = StateError('no clipboard owner');
    final first = SuggestionRegister.values.first;
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is SuggestionCard && widget.register == first,
        ),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(harness.state.copyFailure, isNotNull);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the notice is bounded and scrolls; it cannot claim the region',
    );
  });

  testWidgets('CAP-10: the floor follows the reader\'s text size, so the '
      'original still clears a line at 1.5x', (tester) async {
    // A constant floor certified CAP-10 at a height where the editor could not
    // show one line: everything the floor was measured against — the caption,
    // the button, the labels, the hints — scales with the text while the number
    // did not. Probed at 480×300: 31.2 px of editor at 1.0×, 23.2 at 1.5×,
    // against a line that is 24 px tall there.
    const scale = TextScaler.linear(1.5);
    final floor = CorrectionPanel.minimumPanelHeightFor(scale);
    expect(
      floor,
      greaterThan(CorrectionPanel.minimumPanelHeight),
      reason: 'a floor that ignores the text size is the defect itself',
    );

    final surface = Size(480, floor);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    harness.clipboard.text = longText('i has went to the store and buyed it');
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await harness.completeRun(
      tester,
      longText('I have gone to the store and bought it'),
    );

    final editorRect = tester.getRect(find.byType(TextField));
    expect(
      editorRect.height,
      greaterThanOrEqualTo(scale.scale(16)),
      reason: 'one full line of the editor\'s text at the reader\'s own scale',
    );
    final first = SuggestionRegister.values.first;
    final labelRect = tester.getRect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is SuggestionCard && widget.register == first,
        ),
        matching: find.text(first.label),
      ),
    );
    expect(labelRect.height, greaterThan(0));
    expect(labelRect.bottom, lessThanOrEqualTo(surface.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('CAP-4: selecting a variant below the floor brings its card into '
      'view without scrolling the original away', (tester) async {
    // `Scrollable.ensureVisible` walks *every* scrollable ancestor, and below
    // the floor the panel itself is one — so a digit press scrolled the user's
    // own text clean off the top of the panel (editor rect measured moving from
    // y=32 to y=-95), with no way back and the offset surviving the next show.
    const surface = Size(480, 160);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    harness.clipboard.text = 'i has went';
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await harness.completeRun(tester, longText('I have gone to the store'));
    final editorBefore = tester.getRect(find.byType(TextField));

    await tester.sendKeyEvent(
      LogicalKeyboardKey(
        LogicalKeyboardKey.digit1.keyId + SuggestionRegister.values.length - 1,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      harness.state.selectedRegister,
      equals(SuggestionRegister.values.last),
    );
    expect(
      tester.getRect(find.byType(TextField)),
      equals(editorBefore),
      reason:
          'bringing a card into view is the variants list\'s business; the '
          'panel it sits in must not move under the user',
    );
  });

  testWidgets('CAP-13: the inline error also lays out below the floor', (
    tester,
  ) async {
    const surface = Size(480, 160);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    harness.clipboard.text = 'i has went';
    await harness.pumpSession(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    harness.run.emit(
      const CorrectionFailed(
        kind: CorrectionFailureKind.providerError,
        message: 'the corrector stopped answering. Try again.',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });
}
