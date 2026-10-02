import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/ui/settings/hotkey_capture_field.dart';
import 'package:hotkey_grammar_corrector/src/ui/settings/hotkey_status_view.dart';

import '../settings_harness.dart';

/// AD-10 on screen: what is actually in effect, in whichever vocabulary the
/// backend that reported it can be truthful in, and what the screen says when
/// it reported neither (CAP-12, HOTKEY-03, AD-11, AD-12).
///
/// Every row here drives the outcome the backend *returns* and asserts what the
/// screen says about it. The requested binding is never what is rendered as
/// effective, which is the whole of what AD-10 exists to prevent — on Wayland the
/// compositor picks the combination, and a screen that printed the request there
/// would be claiming it set a hotkey somebody else chose.
///
/// **No row expects a regime sentence, and several assert its absence** (D-03,
/// ratified 2026-09-01): the app still grabs directly on X11 and declares
/// through the portal on Wayland, and the screen says nothing about which.
void main() {
  late SettingsHarness harness;

  setUp(() => harness = SettingsHarness());
  tearDown(() => harness.dispose());

  final applyButton = find.widgetWithText(ElevatedButton, 'Apply');

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(applyButton);
    await tester.pumpAndSettle();
  }

  /// The capture surface itself, rather than the whole control: the control
  /// also holds the Apply button and, on X11, the standing hint's own button.
  final captureSurface = find
      .descendant(
        of: find.byType(HotkeyCaptureField),
        matching: find.byType(InkWell),
      )
      .first;

  /// Drives the capture the way a user does (D-14): click the box, hold the
  /// modifiers, press the key.
  ///
  /// Linux is the default simulator keymap. Shifted punctuation uses the web
  /// simulator because the legacy GLFW map omits those symbols and apostrophe.
  Future<void> capture(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    PhysicalKeyboardKey? physicalKey,
    List<LogicalKeyboardKey> holding = const [],
    bool release = true,
    String platform = 'linux',
  }) async {
    await tester.tap(captureSurface);
    await tester.pump();
    for (final modifier in holding) {
      await simulateKeyDownEvent(modifier, platform: platform);
    }
    await tester.pump();
    await simulateKeyDownEvent(
      key,
      physicalKey: physicalKey,
      platform: platform,
    );
    await tester.pump();
    if (release) {
      await simulateKeyUpEvent(
        key,
        physicalKey: physicalKey,
        platform: platform,
      );
      for (final modifier in holding.reversed) {
        await simulateKeyUpEvent(modifier, platform: platform);
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> pushFromBackend(
    WidgetTester tester,
    HotkeyBindOutcome outcome,
  ) async {
    harness.hotkey.emitBindingChange(outcome);
    await tester.pump();
    await tester.pump();
  }

  final HotkeyBinding altSpace = HotkeyBinding(
    modifiers: {HotkeyModifier.alt},
    key: 'Space',
  );

  testWidgets('CAP-14: focus loss abandons an uncommitted shortcut draft '
      'without writing settings', (tester) async {
    await harness.pump(tester);
    await harness.show(tester);
    await harness.openSettings(tester);
    await capture(
      tester,
      LogicalKeyboardKey.space,
      physicalKey: PhysicalKeyboardKey.space,
      holding: const [LogicalKeyboardKey.altLeft],
    );
    expect(
      find.descendant(
        of: find.byType(HotkeyCaptureField),
        matching: find.text('Alt+Space'),
      ),
      findsOneWidget,
    );

    harness.panelVisibility.loseFocus();
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(HotkeyCaptureField),
        matching: find.text('Ctrl+Shift+G'),
      ),
      findsOneWidget,
    );
    expect(harness.configStore.writes, isEmpty);
  });

  testWidgets(
    'A7 AD-10: before anything is asked of a backend the screen names '
    'no regime and no effective combination',
    (tester) async {
      await harness.pumpSettings(tester);

      expect(
        find.textContaining('No shortcut has been requested yet'),
        findsOneWidget,
      );
      expect(find.textContaining('In effect:'), findsNothing);
      expect(find.textContaining('owns this shortcut'), findsNothing);
      expect(
        find.text('Shortcut to request'),
        findsOneWidget,
        reason:
            'the field claims neither regime while no backend has answered — '
            'calling it "Shortcut" would assert X11 semantics on both display '
            'servers',
      );
    },
  );

  testWidgets('A1 CAP-12, AD-10, D-03: on X11 the effective combination is '
      'rendered and no regime is named', (tester) async {
    await harness.pumpSettings(tester);

    await apply(tester);

    expect(
      find.text('In effect: Ctrl+Shift+G'),
      findsOneWidget,
      reason: 'the returned registration, not the request',
    );
    expect(
      find.textContaining('owns this shortcut'),
      findsNothing,
      reason:
          'D-03 drops the authoritative-versus-advisory read-out from the UI: '
          'one UI everywhere, mechanism hidden. What is left is the shortcut '
          'in effect',
    );
    expect(find.textContaining('takes effect'), findsNothing);
    expect(find.text('Shortcut'), findsOneWidget);
    expect(find.textContaining('differs from your preference'), findsNothing);
  });

  testWidgets('A1 AD-10: a refused X11 rebind keeps the previous effective '
      'combination in both status and config', (tester) async {
    // The X11 case where the two genuinely differ, and the reason this row
    // exists beside the one above: when a rebind is abandoned — the release the
    // backend refused, or a key this build cannot register — the adapter answers
    // `HotkeyBound` carrying the previous combination. D-18 keeps that same
    // effective combination in config rather than storing the refused request.
    harness.hotkey.onBind = (binding) => HotkeyBound(
      HotkeyRegistration(
        effective: SettingsHarness.ctrlShiftG,
        authority: BindingAuthority.application,
      ),
    );
    await harness.pumpSettings(tester);

    await capture(
      tester,
      LogicalKeyboardKey.space,
      physicalKey: PhysicalKeyboardKey.space,
      holding: const [LogicalKeyboardKey.altLeft],
    );
    await apply(tester);

    expect(
      harness.configStore.current.hotkeyBinding,
      SettingsHarness.ctrlShiftG,
    );
    expect(
      find.text('In effect: Ctrl+Shift+G'),
      findsOneWidget,
      reason:
          'AD-10: effective is what is actually in effect, and the previous '
          'combination still is',
    );
    expect(
      find.textContaining('differs from your preference'),
      findsNothing,
      reason: 'D-18 no longer persists the refused request as a preference',
    );
    expect(find.text('In effect: Alt+Space'), findsNothing);
  });

  testWidgets('A2 CAP-12, AD-10, AD-11, D-02: on Wayland the field is still a '
      'preference, the combination the desktop chose is what is shown, and no '
      'regime is named', (tester) async {
    harness.hotkey.onBind = (binding) => HotkeyBound(
      HotkeyRegistration(
        effective: binding,
        authority: BindingAuthority.compositor,
      ),
    );
    await harness.pumpSettings(tester);

    await apply(tester);

    expect(
      find.text('Shortcut preference'),
      findsOneWidget,
      reason:
          'AD-10: under the portal the field is a preference, not a setting. '
          'D-03 hides the regime *read-out*, not the fact that what the user '
          'types here is a request rather than a setting',
    );
    expect(
      find.text('In effect: Ctrl+Shift+G'),
      findsOneWidget,
      reason:
          'D-02: a desktop that took the request is bound, and the reported '
          'combination is what is shown',
    );
    expect(
      find.textContaining('owns this shortcut'),
      findsNothing,
      reason: 'D-03: neither regime is named, on either display server',
    );
    expect(find.textContaining('chooses the combination'), findsNothing);

    harness.hotkey.onBind = (binding) => HotkeyRetained(
      HotkeyRegistration(
        effective: SettingsHarness.ctrlShiftG,
        authority: BindingAuthority.compositor,
      ),
    );
    await capture(
      tester,
      LogicalKeyboardKey.space,
      physicalKey: PhysicalKeyboardKey.space,
      holding: const [LogicalKeyboardKey.altLeft],
    );
    await apply(tester);

    expect(
      harness.configStore.current.hotkeyBinding,
      SettingsHarness.ctrlShiftG,
    );
    expect(find.text('In effect: Ctrl+Shift+G'), findsOneWidget);
    expect(find.text('In effect: Alt+Space'), findsNothing);
    expect(find.textContaining('That combination was refused'), findsOneWidget);
    expect(
      find.textContaining('previous shortcut still works'),
      findsOneWidget,
    );

    await pushFromBackend(
      tester,
      HotkeyBound(
        HotkeyRegistration(
          effective: HotkeyBinding(modifiers: {HotkeyModifier.meta}, key: 'F1'),
          authority: BindingAuthority.compositor,
        ),
      ),
    );
    expect(find.text('In effect: Super+F1'), findsOneWidget);
    expect(find.textContaining('That combination was refused'), findsNothing);
  });

  testWidgets('A3 AD-10, T-01-30: a backend that reported neither a '
      'combination nor a description says so, and the request is not shown in '
      'its place', (tester) async {
    // Case 3 of three: bound, and nothing reported about what is held. The
    // backend authors no wording either — `backendDescription` stays null — so
    // there is nothing truthful left to show, and what must not happen is the
    // screen reaching for the preference to fill the gap.
    harness.hotkey.onBind = (binding) => const HotkeyBound(
      HotkeyRegistration(
        effective: null,
        authority: BindingAuthority.compositor,
      ),
    );
    await harness.pumpSettings(tester);

    await apply(tester);

    expect(
      find.textContaining('nothing was reported about which combination'),
      findsOneWidget,
    );
    expect(find.textContaining('In effect:'), findsNothing);
    expect(
      find.textContaining('describes it as'),
      findsNothing,
      reason: 'no wording arrived, so none is promised',
    );
    expect(
      find.descendant(
        of: find.byType(HotkeyStatusView),
        matching: find.textContaining('Ctrl+Shift+G'),
      ),
      findsNothing,
      reason:
          'printing the request where the effective combination goes is exactly '
          'the settings-UI-claiming-a-hotkey-it-did-not-set that AD-10 forbids, '
          'and it is the threat register row T-01-30',
    );
    expect(find.textContaining('your preference'), findsNothing);

    harness.hotkey.onBind = (binding) => const HotkeyRetained(
      HotkeyRegistration(
        effective: null,
        authority: BindingAuthority.compositor,
      ),
    );
    await capture(
      tester,
      LogicalKeyboardKey.space,
      physicalKey: PhysicalKeyboardKey.space,
      holding: const [LogicalKeyboardKey.altLeft],
    );
    await apply(tester);
    expect(
      harness.configStore.current.hotkeyBinding,
      SettingsHarness.ctrlShiftG,
    );
    expect(
      find.descendant(
        of: find.byType(HotkeyCaptureField),
        matching: find.text('Ctrl+Shift+G'),
      ),
      findsOneWidget,
      reason: 'a refused request reseeds capture from the saved prior binding',
    );
    expect(find.textContaining('That combination was refused'), findsOneWidget);
    expect(
      find.textContaining('nothing was reported about which combination'),
      findsOneWidget,
    );
  });

  testWidgets('A4 AD-10: a compositor choice becomes the one configured '
      'effective combination', (tester) async {
    harness.hotkey.onBind = (binding) => HotkeyBound(
      HotkeyRegistration(
        effective: HotkeyBinding(modifiers: {HotkeyModifier.meta}, key: 'F1'),
        authority: BindingAuthority.compositor,
      ),
    );
    await harness.pumpSettings(tester);

    await apply(tester);

    expect(find.text('In effect: Super+F1'), findsOneWidget);
    expect(harness.configStore.current.hotkeyBinding.key, 'F1');
    expect(
      find.textContaining('differs from your preference'),
      findsNothing,
      reason: 'D-18 replaces the stored preference with the read-back',
    );
  });

  testWidgets('A5 AD-10: a compositor that honoured the request claims no '
      'difference, whatever order the modifiers arrive in', (tester) async {
    harness.hotkey.onBind = (binding) => HotkeyBound(
      HotkeyRegistration(
        // The same combination, built with the set iterated the other way.
        effective: HotkeyBinding(
          modifiers: {HotkeyModifier.shift, HotkeyModifier.control},
          key: 'G',
        ),
        authority: BindingAuthority.compositor,
      ),
    );
    await harness.pumpSettings(tester);

    await apply(tester);

    expect(find.text('In effect: Ctrl+Shift+G'), findsOneWidget);
    expect(
      find.textContaining('differs from your preference'),
      findsNothing,
      reason:
          'HotkeyBinding compares its modifiers as a set, and the label writes '
          'them in a fixed order, so iteration order cannot fake a difference',
    );
  });

  testWidgets('A6 AD-12: with no backend at all the screen states '
      'unavailability in the outcome\'s own words, names the tray exactly once, '
      'claims no regime, and leaves the field usable', (tester) async {
    // The adapter's real sentence, verbatim, because that is what makes the
    // duplication testable: every `HotkeyUnavailable` in this codebase already
    // ends by naming the tray, so a screen that appended the clause itself
    // printed it twice — and a hand-written fixture with no tray clause is why
    // that passed.
    const message =
        'this compositor provides no global shortcuts portal, so the hotkey '
        'is inactive — the tray menu still opens the panel';
    harness.hotkey.onBind = (binding) => const HotkeyUnavailable(
      cause: HotkeyUnavailableCause.noBackend,
      message: message,
    );
    await harness.pumpSettings(tester);

    await apply(tester);

    expect(
      find.text(message),
      findsOneWidget,
      reason:
          'AD-12 names the settings screen as a consumer of this state, and the '
          'adapter is what knows why it could not bind',
    );
    expect(
      find.textContaining('unavailable on this desktop'),
      findsNothing,
      reason:
          'the screen must not generalise one outcome into a verdict on the '
          'whole desktop: this state is also where a single refused key label '
          'and a compositor dropping one shortcut land, both from backends that '
          'answered and work',
    );
    expect(
      find.textContaining('tray menu still opens the panel'),
      findsOneWidget,
      reason:
          'once — the outcome\'s own message carries the clause, so a sentence '
          'of the screen\'s own beside it says the same thing twice',
    );
    expect(
      find.textContaining('Global shortcuts are unavailable to this app'),
      findsOneWidget,
      reason:
          'D-06/HOTKEY-08: the cause selects this sentence, and on this cause '
          'it tells the user no combination will help — the one thing the '
          'adapter message does not say',
    );
    expect(
      find.textContaining('Choose a different one'),
      findsNothing,
      reason:
          'inviting a retry would be wrong here: there is no backend for a '
          'different combination to reach',
    );
    expect(
      tester.widget<ElevatedButton>(applyButton).enabled,
      isTrue,
      reason: 'the user has to be able to fix the combination and try again',
    );
  });

  testWidgets('A6 AD-10, AD-12: an unavailable backend makes the screen claim '
      'no regime at all, rather than falling back to app-owned', (
    tester,
  ) async {
    // The wlroots case, which is AD-12's headline one: no portal, so no backend
    // answered and nothing is known about who *would* own the shortcut. Claiming
    // this app owns it is precisely what the SPEC's Ratified Divergence forbids,
    // and the display server is a fact this ring cannot see (AD-1) — so the
    // honest answer is to say the question is open.
    harness.hotkey.onBind = (binding) => const HotkeyUnavailable(
      cause: HotkeyUnavailableCause.noBackend,
      message: 'this compositor provides no global shortcuts portal',
    );
    await harness.pumpSettings(tester);

    await apply(tester);

    expect(
      find.textContaining('This app owns this shortcut'),
      findsNothing,
      reason: 'no backend answered, so app ownership is not a claim to make',
    );
    expect(
      find.textContaining('Your desktop owns this shortcut'),
      findsNothing,
    );
    expect(
      find.textContaining('is not known until one is registered'),
      findsOneWidget,
      reason: 'and the screen says so rather than being silent about it',
    );
    expect(
      find.textContaining('No backend answered'),
      findsNothing,
      reason:
          'saying no backend answered is itself a claim, and a false one on the '
          'two paths this story made reachable — an X11 backend refusing one key '
          'label, and a working portal reporting a dropped shortcut',
    );
    expect(
      find.text('Shortcut'),
      findsNothing,
      reason:
          'the field label is the other place ownership leaks — "Shortcut" is '
          'the X11-authoritative label',
    );
    expect(find.text('Shortcut to request'), findsOneWidget);
  });

  testWidgets('CAP-12, D-14: the modifiers the capture reads and the '
      'combination the screen reads back use one vocabulary', (tester) async {
    // `Super` in the read-out beside a control that said `meta` would be one key
    // with two names on one screen. The label helper is the single home for the
    // answer, so this row drives every modifier at once and reads it back.
    //
    // Re-pointed from the toggles: D-14 removes them. The modifiers used to be
    // clicked one chip at a time and are now read from the keyboard at the
    // moment the key goes down, which is also what makes a modifier-only press
    // commit nothing — there is no state to leave half-set.
    harness.hotkey.onBind = (binding) => HotkeyBound(
      HotkeyRegistration(
        effective: binding,
        authority: BindingAuthority.application,
      ),
    );
    await harness.pumpSettings(tester);

    expect(
      find.byType(FilterChip),
      findsNothing,
      reason: 'the per-modifier toggles are gone with the text field (D-14)',
    );
    expect(
      find.descendant(
        of: find.byType(HotkeyCaptureField),
        matching: find.byType(TextField),
      ),
      findsNothing,
      reason:
          'and no free-text hotkey field remains — a user never has to know '
          'their key is called Pause',
    );

    await capture(
      tester,
      LogicalKeyboardKey.keyG,
      physicalKey: PhysicalKeyboardKey.keyG,
      holding: const [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.metaLeft,
      ],
    );

    expect(
      find.text('Ctrl+Alt+Shift+Super+G'),
      findsOneWidget,
      reason:
          'the capture spells the combination with the one label helper, in '
          'the enum order, so the box and the read-out agree',
    );
    for (final modifier in HotkeyModifier.values) {
      expect(
        find.textContaining(modifier.name),
        findsNothing,
        reason: 'and never the raw enum name for ${modifier.name}',
      );
    }

    await apply(tester);

    expect(find.text('In effect: Ctrl+Alt+Shift+Super+G'), findsOneWidget);
  });

  testWidgets('A8 AD-10, AD-11: a rebind made in the compositor updates the '
      'screen with no user action', (tester) async {
    await harness.pumpSettings(tester);
    expect(
      find.textContaining('No shortcut has been requested yet'),
      findsOneWidget,
    );

    await pushFromBackend(
      tester,
      HotkeyBound(
        HotkeyRegistration(
          effective: HotkeyBinding(modifiers: {HotkeyModifier.meta}, key: 'F1'),
          authority: BindingAuthority.compositor,
        ),
      ),
    );

    expect(find.text('In effect: Super+F1'), findsOneWidget);
    expect(
      find.textContaining('owns this shortcut'),
      findsNothing,
      reason: 'D-03: the change is shown, the regime behind it is not',
    );
    expect(
      harness.hotkey.bindCalls,
      isEmpty,
      reason: 'nothing the app asked for produced this — the desktop did',
    );
  });

  testWidgets('A9 AD-11, AD-12: a shortcut the desktop dropped switches the '
      'screen to the unavailable statement', (tester) async {
    await harness.pumpSettings(tester);
    await apply(tester);
    expect(find.text('In effect: Ctrl+Shift+G'), findsOneWidget);

    await pushFromBackend(
      tester,
      const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.revoked,
        message: 'your desktop no longer holds this shortcut',
      ),
    );

    expect(find.text('your desktop no longer holds this shortcut'), findsOne);
    expect(
      find.textContaining('unavailable on this desktop'),
      findsNothing,
      reason:
          'a desktop that dropped one shortcut is a working desktop that '
          'answered — this is the exact case the blanket preamble was false on',
    );
    expect(
      find.textContaining('In effect:'),
      findsNothing,
      reason: 'there is nothing in effect any more',
    );
    // D-06/HOTKEY-08: the three causes are three different things on screen,
    // and the screen picks between them by reading the cause — not by matching
    // on the message, which is identical prose across the pushes below.
    expect(
      find.textContaining('Your desktop took this shortcut away'),
      findsOneWidget,
      reason:
          'a shortcut that was working and was taken away — D-08 says the '
          'daemon does not re-claim it, so the user is told setting it again '
          'is theirs to do',
    );
    expect(find.text('No shortcut is currently in effect.'), findsOneWidget);
    expect(
      find.textContaining('is not known until one is registered'),
      findsNothing,
      reason: 'a revoked shortcut was registered before the desktop took it',
    );
    expect(
      find.textContaining('Global shortcuts are unavailable to this app'),
      findsNothing,
      reason: 'a desktop that revoked one shortcut demonstrably has them',
    );

    await pushFromBackend(
      tester,
      // Same message text, different cause. If the screen were selecting on
      // prose this push would be indistinguishable from the one above.
      const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.keyRefused,
        message: 'your desktop no longer holds this shortcut',
      ),
    );

    expect(
      find.textContaining('That combination was refused'),
      findsOneWidget,
      reason:
          'the cause changed and the message did not, so only a screen reading '
          'the cause can render this differently',
    );
    expect(
      find.textContaining('Your desktop took this shortcut away'),
      findsNothing,
    );

    // The empty-message path: an adapter whose sentence is blank must not
    // produce a blank unavailable state, and D-07 still has to hold when there
    // is no adapter message to have carried the tray clause.
    await pushFromBackend(
      tester,
      const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.revoked,
        message: '   ',
      ),
    );

    expect(
      find.textContaining('Your desktop took this shortcut away'),
      findsOneWidget,
      reason: 'the cause alone still yields a sentence',
    );
    expect(
      find.textContaining('tray menu still opens the panel'),
      findsOneWidget,
      reason:
          'D-07: every unavailable rendering tells the user the panel is still '
          'reachable — here the screen supplies it, because the blank message '
          'cannot and there is therefore nothing to say it twice',
    );
  });

  testWidgets('A8, A9 AD-11: the read-out is announced, so a change nobody '
      'asked for is not sighted-only', (tester) async {
    // The status block is the only place a compositor-side rebind or a dropped
    // shortcut becomes visible, and both arrive with **no user action** — so a
    // reader who cannot see the screen would otherwise never learn their hotkey
    // moved or stopped working. Asserted in both multi-line states, because a
    // live-region annotation that only lands when the subtree collapses to a
    // single node would pass on the one state nothing ever changes into.
    final semantics = tester.ensureSemantics();
    await harness.pumpSettings(tester);

    for (final outcome in <HotkeyBindOutcome>[
      HotkeyBound(
        HotkeyRegistration(
          effective: HotkeyBinding(modifiers: {HotkeyModifier.meta}, key: 'F1'),
          authority: BindingAuthority.compositor,
        ),
      ),
      const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.revoked,
        message: 'your desktop no longer holds this shortcut',
      ),
    ]) {
      await pushFromBackend(tester, outcome);

      final node = tester.getSemantics(find.byType(HotkeyStatusView));
      expect(
        node.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue,
        reason: 'assistive technology is told when this block changes',
      );
      expect(
        node.label,
        isNotEmpty,
        reason:
            'and the node carrying the flag is the one carrying the sentences — '
            'a live region with an empty label announces nothing',
      );
    }
    semantics.dispose();
  });

  testWidgets('A15 HOTKEY-03, D-04: a backend that reports wording instead of '
      'a combination has that wording shown verbatim, labelled as the '
      'desktop\'s own', (tester) async {
    // Case 2 of three, and the ordinary Wayland one: the portal carries no
    // machine-readable combination anywhere in its replies, only a localized
    // `trigger_description`. A German desktop is used deliberately — this is
    // the row that would catch a re-rendering into this app's `Ctrl+Shift+G`
    // notation, which DW-66's ratified decision rejected as silently wrong on
    // a translated string.
    const wording = 'Strg+Umschalt+G';
    harness.hotkey.backendDescription = wording;
    harness.hotkey.onBind = (binding) => const HotkeyBound(
      HotkeyRegistration(
        effective: null,
        authority: BindingAuthority.compositor,
      ),
    );
    await harness.pumpSettings(tester);

    await apply(tester);

    expect(
      find.text(wording),
      findsOneWidget,
      reason:
          'the exact string the desktop sent, on a line of its own — not '
          'interpolated, not recased, not respelled',
    );
    expect(
      find.textContaining('describes it as'),
      findsOneWidget,
      reason:
          'DW-66 decision: rendered, and clearly labelled as the desktop own '
          'wording rather than this app',
    );
    expect(
      find.textContaining('In effect:'),
      findsNothing,
      reason: 'there is no combination to put after it',
    );
    expect(
      find.textContaining('differs from your preference'),
      findsNothing,
      reason:
          'D-05: the wording is prose and the preference is a structure, so '
          'nothing comparable exists and a comparison invented here would be '
          'the silent wrongness that forbids',
    );
    expect(
      find.descendant(
        of: find.byType(HotkeyStatusView),
        matching: find.textContaining('Ctrl+Shift+G'),
      ),
      findsNothing,
      reason:
          'and the requested combination is nowhere in the read-out — the whole '
          'point of HOTKEY-03. Scoped to the read-out as the T-01-30 row is, '
          'and for the same reason: the capture control is an input and shows '
          'its own input',
    );
    expect(find.textContaining('owns this shortcut'), findsNothing);
  });

  testWidgets('A10 CAP-12, AD-13: changing the combination calls the '
      'controller once, writes through to config, and renders the returned '
      'outcome', (tester) async {
    await harness.pumpSettings(tester);

    await capture(
      tester,
      LogicalKeyboardKey.space,
      physicalKey: PhysicalKeyboardKey.space,
      holding: const [LogicalKeyboardKey.altLeft],
    );

    await apply(tester);

    expect(harness.hotkey.bindCalls, [altSpace]);
    expect(harness.configStore.writes.single.hotkeyBinding, altSpace);
    expect(harness.configStore.current.hotkeyBinding, altSpace);
    expect(find.text('In effect: Alt+Space'), findsOneWidget);
  });

  for (final (label, physicalKey, baseKey, shiftedKey) in const [
    (
      'Minus',
      PhysicalKeyboardKey.minus,
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.underscore,
    ),
    (
      'Equal',
      PhysicalKeyboardKey.equal,
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.add,
    ),
    (
      'BracketLeft',
      PhysicalKeyboardKey.bracketLeft,
      LogicalKeyboardKey.bracketLeft,
      LogicalKeyboardKey.braceLeft,
    ),
    (
      'BracketRight',
      PhysicalKeyboardKey.bracketRight,
      LogicalKeyboardKey.bracketRight,
      LogicalKeyboardKey.braceRight,
    ),
    (
      'Backslash',
      PhysicalKeyboardKey.backslash,
      LogicalKeyboardKey.backslash,
      LogicalKeyboardKey.bar,
    ),
    (
      'Semicolon',
      PhysicalKeyboardKey.semicolon,
      LogicalKeyboardKey.semicolon,
      LogicalKeyboardKey.colon,
    ),
    (
      'Quote',
      PhysicalKeyboardKey.quote,
      LogicalKeyboardKey.quoteSingle,
      LogicalKeyboardKey.quote,
    ),
    (
      'Backquote',
      PhysicalKeyboardKey.backquote,
      LogicalKeyboardKey.backquote,
      LogicalKeyboardKey.tilde,
    ),
    (
      'Comma',
      PhysicalKeyboardKey.comma,
      LogicalKeyboardKey.comma,
      LogicalKeyboardKey.less,
    ),
    (
      'Period',
      PhysicalKeyboardKey.period,
      LogicalKeyboardKey.period,
      LogicalKeyboardKey.greater,
    ),
    (
      'Slash',
      PhysicalKeyboardKey.slash,
      LogicalKeyboardKey.slash,
      LogicalKeyboardKey.question,
    ),
  ]) {
    for (final logicalKey in [baseKey, shiftedKey]) {
      testWidgets('CAP-12: Ctrl+Shift+${logicalKey.keyLabel} is accepted and '
          'saved as the $label shortcut', (tester) async {
        await harness.pumpSettings(tester);
        await capture(
          tester,
          logicalKey,
          physicalKey: physicalKey,
          // GLFW's legacy simulator map omits apostrophe and shifted symbols.
          // The web simulator delivers the same KeyData to the capture widget.
          platform: logicalKey == baseKey && label != 'Quote' ? 'linux' : 'web',
          holding: const [
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.shiftLeft,
          ],
        );

        expect(find.text('Ctrl+Shift+$label'), findsOneWidget);
        expect(
          find.textContaining('not one this app can register'),
          findsNothing,
        );
        await apply(tester);

        final binding = HotkeyBinding(
          modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
          key: label,
        );
        expect(harness.hotkey.bindCalls, [binding]);
        expect(harness.configStore.writes.single.hotkeyBinding, binding);
        expect(harness.configStore.current.hotkeyBinding, binding);
        expect(find.text('In effect: Ctrl+Shift+$label'), findsOneWidget);
      });
    }
  }

  testWidgets('D-13, D-15, T-01-36, T-01-37: a bare key and an AltGr '
      'combination are each refused at capture, with their own reason, and '
      'neither reaches the controller', (tester) async {
    // Re-pointed from "a key that trims to empty disables Apply": there is no
    // text to trim any more. The claim underneath survives whole — a
    // combination the app can tell will not work must never reach the
    // controller — and D-15 moves the answer from Apply to the capture itself,
    // so it is checked here rather than on the button.
    //
    // Two subjects, because they must not share a sentence. A bare key would be
    // grabbed system-wide and stop reaching every other app, including the one
    // the user is writing in (D-13, T-01-36). An AltGr combination cannot be
    // represented at all — `HotkeyModifier` has four values and none is Level 3
    // — so folding it into Alt would produce a shortcut that looks right on
    // screen and fires on a different physical key (T-01-37).
    await harness.pumpSettings(tester);

    await capture(
      tester,
      LogicalKeyboardKey.keyJ,
      physicalKey: PhysicalKeyboardKey.keyJ,
    );

    expect(
      find.textContaining('A shortcut needs at least one of'),
      findsOneWidget,
      reason: 'refused with the reason, not silently ignored (D-15)',
    );
    expect(
      find.text('Ctrl+Shift+G'),
      findsOneWidget,
      reason: 'and the previous combination is what the control still holds',
    );

    // `platform: 'web'` for the AltGr press alone, and it is a limitation of
    // the simulator rather than a claim about the app: the raw-event half of
    // `simulateKeyDownEvent` resolves a key code out of `kGlfwToLogicalKey` for
    // `linux`, and GLFW has no AltGr at all, so a logical `altGraph` cannot be
    // spelled on that keymap. The web map does carry `AltGraph`, and what the
    // widget reads is the `KeyData` both paths produce.
    await tester.tap(captureSurface);
    await tester.pump();
    await simulateKeyDownEvent(
      LogicalKeyboardKey.altGraph,
      physicalKey: PhysicalKeyboardKey.altRight,
      platform: 'web',
    );
    await simulateKeyDownEvent(
      LogicalKeyboardKey.keyG,
      physicalKey: PhysicalKeyboardKey.keyG,
      platform: 'linux',
    );
    await tester.pumpAndSettle();
    await simulateKeyUpEvent(
      LogicalKeyboardKey.keyG,
      physicalKey: PhysicalKeyboardKey.keyG,
      platform: 'linux',
    );
    await simulateKeyUpEvent(
      LogicalKeyboardKey.altGraph,
      physicalKey: PhysicalKeyboardKey.altRight,
      platform: 'web',
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('AltGr cannot be part of a shortcut'),
      findsOneWidget,
      reason:
          'its own reason, and not the bare-key one: the two are different '
          'things for the user to do about',
    );
    expect(
      find.textContaining('A shortcut needs at least one of'),
      findsNothing,
      reason:
          'an AltGr press carries no HotkeyModifier at all, so the no-modifier '
          'branch would have described it with the wrong cause',
    );
    expect(find.text('Ctrl+Shift+G'), findsOneWidget);

    await apply(tester);

    expect(
      harness.hotkey.bindCalls,
      [SettingsHarness.ctrlShiftG],
      reason:
          'Apply requests what the control holds, which is the stored '
          'preference — neither refused combination reached the controller',
    );
  });

  testWidgets('D-14, D-15: a modifier on its own commits nothing, a held key '
      'commits once, and a refusal clears when a combination that works is '
      'captured', (tester) async {
    // The control for the row above: the refusal has to follow the capture, or
    // it would either never appear or never clear. Re-pointed from the emptied
    // key field for the same reason that row was.
    //
    // It carries the two pitfalls that only a driven capture can show. A
    // modifier-only press is the first half of every legitimate combination, so
    // it must commit nothing and leave the capture waiting rather than refuse
    // the user's own correct behaviour. And `HardwareKeyboard` delivers one
    // key-down, zero or more repeats and one key-up: acting on a repeat would
    // re-commit the capture for as long as the key was held.
    await harness.pumpSettings(tester);

    await tester.tap(captureSurface);
    await tester.pump();
    await simulateKeyDownEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'linux',
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('press the key you want'),
      findsOneWidget,
      reason: 'the capture says what it is waiting for',
    );
    expect(
      find.text('Ctrl+Shift+G'),
      findsOneWidget,
      reason: 'and nothing is committed from a modifier alone',
    );

    // Held down, with repeats, then released: exactly one commit.
    await simulateKeyDownEvent(
      LogicalKeyboardKey.keyK,
      physicalKey: PhysicalKeyboardKey.keyK,
      platform: 'linux',
    );
    for (var repeat = 0; repeat < 3; repeat += 1) {
      await simulateKeyRepeatEvent(
        LogicalKeyboardKey.keyK,
        physicalKey: PhysicalKeyboardKey.keyK,
        platform: 'linux',
      );
    }
    await simulateKeyUpEvent(
      LogicalKeyboardKey.keyK,
      physicalKey: PhysicalKeyboardKey.keyK,
      platform: 'linux',
    );
    await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft, platform: 'linux');
    await tester.pumpAndSettle();

    expect(
      find.text('Ctrl+K'),
      findsOneWidget,
      reason: 'the accepted combination replaces the previous one',
    );
    expect(
      find.textContaining('press the key you want'),
      findsNothing,
      reason: 'and the waiting line goes with it',
    );

    await apply(tester);

    expect(
      harness.hotkey.bindCalls,
      [
        HotkeyBinding(modifiers: {HotkeyModifier.control}, key: 'K'),
      ],
      reason:
          'once, not once per repeat event — a held key that re-committed '
          'would issue a bind per repeat through the button',
    );
  });

  testWidgets('A14 AD-12: a backend that throws instead of reporting leaves '
      'both halves on screen and the screen usable', (tester) async {
    harness.hotkey.bindError = StateError('the portal is gone');
    await harness.pumpSettings(tester);

    await apply(tester);

    expect(
      find.textContaining('the hotkey backend could not be reached'),
      findsOneWidget,
      reason: 'the controller reduces an AD-12 breach to the outcome it names',
    );
    expect(
      find.textContaining('the shortcut could not be registered'),
      findsOneWidget,
      reason:
          'and to a failure sentence, because a lost bind leaves no other '
          'trace on this surface',
    );
    expect(tester.widget<ElevatedButton>(applyButton).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AD-10: nothing the port pushes can carry a malformed payload — '
      'the member is typed as the same value bind() answers with', (
    tester,
  ) async {
    // Not a runtime assertion but a stated one: `bindingChanges` is
    // `Stream<HotkeyBindOutcome>`, so a compositor-side change and an initial
    // bind reach this screen as the same sealed pair and the switch that renders
    // them is exhaustive. The row that could fail is the error path below.
    await harness.pumpSettings(tester);

    harness.hotkey.emitBindingChangesError(StateError('the bus went away'));
    await tester.pump();
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'AD-15 backstop: an adapter that errors this stream must not take '
          'the surface down with it',
    );
    expect(
      find.textContaining('No shortcut has been requested yet'),
      findsOneWidget,
      reason: 'and the last known state stays rendered',
    );
  });

  testWidgets('D-13, D-14, D-16, Task 1: Tab is capturable, the standing hint '
      'about the current shortcut is up before anything is pressed, and the '
      'control is read-only while a bind is in flight', (tester) async {
    // Re-pointed from "deselecting every modifier is cautioned rather than
    // refused". **That row asserted the opposite of what now holds**, and the
    // reversal is D-13: at least one modifier is always required, not
    // cautioned about. The refusal itself is the row above; what is left here
    // is the rest of the capture's behaviour, which had nowhere else to go.
    //
    // `Tab` is the sharpest of the three. It was one of the seven labels the
    // removed vendor plugin bound to the wrong key, so it is bindable again —
    // and a capture surface that did not answer `handled` would hand it to
    // focus traversal instead, making the key most likely to be wanted the one
    // key that cannot be set.
    final dialog = Completer<void>();
    harness.hotkey.onBind = (binding) => HotkeyBound(
      HotkeyRegistration(
        effective: binding,
        authority: BindingAuthority.application,
      ),
    );
    await harness.pumpSettings(tester);

    // The hint is standing text on the display server where the app itself
    // holds the grab, and it is up before the user has pressed anything —
    // Task 1's `explain-in-place`. A hint that appeared only after a failed
    // capture would be indistinguishable from the control being broken.
    await apply(tester);
    expect(
      find.textContaining('cannot be pressed into this box'),
      findsOneWidget,
      reason:
          'the user is told why their own shortcut behaves differently, rather '
          'than left with a control that looks like it ignored them',
    );
    expect(
      find.widgetWithText(TextButton, 'Keep current'),
      findsOneWidget,
      reason: 'and offered the plain affordance that goes with it',
    );

    await capture(
      tester,
      LogicalKeyboardKey.tab,
      physicalKey: PhysicalKeyboardKey.tab,
      holding: const [LogicalKeyboardKey.controlLeft],
    );

    expect(
      find.text('Ctrl+Tab'),
      findsOneWidget,
      reason:
          'Tab reached the capture instead of moving focus — the whole reason '
          'the handler answers handled',
    );

    // Keep current abandons the capture without writing or binding: keeping the
    // shortcut you have *is* the absence of a change.
    final bindsBefore = harness.hotkey.bindCalls.length;
    await tester.tap(find.widgetWithText(TextButton, 'Keep current'));
    await tester.pumpAndSettle();

    expect(find.text('Ctrl+Shift+G'), findsOneWidget);
    expect(harness.hotkey.bindCalls, hasLength(bindsBefore));
    expect(harness.configStore.writes, hasLength(1));

    // D-16: with a bind parked on a portal dialog the control is read-only, and
    // a key pressed at it changes nothing.
    harness.hotkey.bindGate = dialog;
    await tester.tap(applyButton);
    await tester.pump();

    await simulateKeyDownEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'linux',
    );
    await simulateKeyDownEvent(
      LogicalKeyboardKey.keyM,
      physicalKey: PhysicalKeyboardKey.keyM,
      platform: 'linux',
    );
    await tester.pump();

    expect(
      find.text('Ctrl+M'),
      findsNothing,
      reason: 'nothing is captured while a bind is in flight',
    );
    expect(tester.widget<ElevatedButton>(applyButton).enabled, isFalse);

    await simulateKeyUpEvent(
      LogicalKeyboardKey.keyM,
      physicalKey: PhysicalKeyboardKey.keyM,
      platform: 'linux',
    );
    await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft, platform: 'linux');
    dialog.complete();
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(applyButton).enabled, isTrue);
  });
}
