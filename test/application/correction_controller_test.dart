import 'dart:async';

import 'package:hotkey_grammar_corrector/src/application/correction_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/correction_state.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/domain/panel/panel_visibility.dart';
import 'package:test/test.dart';

import '../fakes/echoing_error.dart';
import '../fakes/fake_clipboard_port.dart';
import '../fakes/fake_clock.dart';
import '../fakes/fake_correction_provider.dart';
import '../fakes/fake_correction_repository.dart';
import '../fakes/fake_logger.dart';
import '../fakes/fake_panel_visibility.dart';
import '../fakes/throwing_logger.dart';

/// The panel session: seeding (CAP-2), correcting what the user edited
/// (CAP-3), streaming (CAP-5), history (CAP-7), and inline failure with
/// Retry (CAP-13) — under AD-3, AD-4, AD-7 and AD-18, including what each
/// port failure does to it.
void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());

  tearDown(() => harness.dispose());

  group('seeding a session', () {
    test('CAP-2: a show after a dismissal re-seeds the editor from the '
        'current clipboard', () async {
      harness.clipboard.text = 'first copy';
      await harness.show();
      expect(harness.state.editorText, equals('first copy'));

      harness.controller.editText('edited by the user');
      await harness.hide();
      harness.clipboard.text = 'second copy';
      await harness.show();

      expect(harness.state.editorText, equals('second copy'));
    });

    test('CAP-3: a late clipboard read does not overwrite user edits, '
        'including a cleared editor', () async {
      final gate = Completer<void>();
      harness.clipboard
        ..text = 'clipboard seed'
        ..readGate = gate;
      await harness.show();

      harness.controller.editText('typed before the read landed');
      gate.complete();
      await pumpEventQueue();

      expect(harness.state.editorText, equals('typed before the read landed'));

      final secondGate = Completer<void>();
      await harness.hide();
      harness.clipboard.readGate = secondGate;
      await harness.show();

      harness.controller.editText('typed and then cleared');
      harness.controller.editText('');
      secondGate.complete();
      await pumpEventQueue();

      expect(harness.state.editorText, isEmpty);
    });

    test('AD-18: a clipboard read that lands after a newer show does not seed '
        'the new session (CAP-2)', () async {
      // The guard this pins was unpinned until the fake captured its answer at
      // call time: with the old fake both reads returned whatever `text` held
      // when they *completed*, so the stale read happened to return the right
      // thing and deleting the guard failed nothing. What it protects: copy,
      // summon (the read parks on display-server IPC), hide, clear the
      // clipboard, summon again — the late read arrives holding the previous
      // clipboard and pastes it into a session AD-18 says is seeded from the
      // current one, under a caret the user is already typing at.
      final firstRead = Completer<void>();
      harness.clipboard
        ..text = 'the previous clipboard'
        ..readGate = firstRead;
      await harness.show();

      await harness.hide();
      harness.clipboard
        ..text = null
        ..readGate = null;
      await harness.show();

      firstRead.complete();
      await pumpEventQueue();

      expect(
        harness.state.editorText,
        isEmpty,
        reason:
            "the stale read's content belongs to a session that is over; the "
            'current session was seeded from the current clipboard',
      );
    });

    test('CAP-2: an empty clipboard seeds no second state, so the panel is '
        'not told a new session began twice (AD-18)', () async {
      // `CorrectionState.freshSession` is what `_beginSession` emits and the
      // panel's only signal that a session just started — it puts the caret back
      // in the editor on it. An empty clipboard used to re-emit an equal state
      // one IPC round-trip later, pulling focus back from wherever the user had
      // moved it in the meantime.
      //
      // The focus half of that is now answered twice over: `copyWith` does not
      // carry `isFreshSession`, so a seeded state reports no session whatever it
      // holds. What this row still pins is the emission itself — a state that
      // changes nothing is noise on a stream two widgets rebuild from.
      final states = <CorrectionState>[];
      final subscription = harness.controller.changes.listen(states.add);
      harness.clipboard.text = null;

      await harness.show();

      expect(states, hasLength(1));
      expect(states.single, equals(CorrectionState.freshSession));
      await subscription.cancel();
    });

    test('CAP-2: an empty clipboard seeds an empty editor', () async {
      harness.clipboard.text = null;

      await harness.show();

      expect(harness.state.editorText, isEmpty);
      expect(harness.state.status, equals(CorrectionStatus.idle));
    });

    test('AD-18: a show after a dismissal clears the previous session\'s '
        'suggestions', () async {
      await harness.show();
      harness.controller.submit();
      harness.run.emit(_completed('formal one', 'casual one', 'shorter one'));
      await pumpEventQueue();
      expect(harness.state.suggestionTexts, isNotEmpty);

      await harness.hide();
      await harness.show();

      expect(harness.state.suggestionTexts, isEmpty);
      expect(harness.state.submittedText, isNull);
      expect(harness.state.failure, isNull);
      expect(harness.state.status, equals(CorrectionStatus.idle));
    });
  });

  group('which returns begin a session (AD-18, DW-30)', () {
    // The human's rule of 2026-08-14 is three-way, not two. A dismissal ends
    // the session; an iconify and a loss of focus do not.
    // `PanelVisibility.changes` says which of the three happened and nothing
    // more — the policy is here, in the ring that owns AD-18.
    //
    // Before this, `changes` was a `Stream<bool>` and every `true` began a
    // session: a user who typed into the panel, iconified it and restored it got
    // their text replaced by the clipboard, and so did one whose panel took
    // itself down on a focus loss (DW-30).

    test('CAP-14/DW-30: a focus loss keeps the session — the panel comes back '
        'with what the user typed, and the clipboard is not read', () async {
      harness.clipboard.text = 'the clipboard the session was seeded from';
      await harness.show();
      harness.controller.editText('mine');

      await harness.loseFocus();
      harness.clipboard.text = 'theirs';
      await harness.show();

      expect(harness.state.editorText, equals('mine'));
      expect(
        harness.clipboard.readCalls,
        equals(1),
        reason:
            'the seed of the one session that began, and nothing since — a '
            'second read is a session this return was not entitled to start',
      );
    });

    test('CAP-2/DW-30: an iconify keeps the session — a workspace switch is '
        'not the user saying they are done with the window', () async {
      await harness.show();
      harness.controller.editText('mine');

      await harness.minimize();
      harness.clipboard.text = 'theirs';
      await harness.restore();

      expect(harness.state.editorText, equals('mine'));
      expect(harness.clipboard.readCalls, equals(1));
    });

    test('DW-31: the believed minimize/restore pair discards nothing — the '
        'timing window DW-31 opened is not an AD-18 session', () async {
      // The adapter reports that pair as `iconified` then `shown` whether or
      // not a request of ours was outstanding when it arrived (DW-31), so at
      // this ring the pair is the row above reached by the other gesture — and
      // this one says so on purpose: the pair was DW-30's sharpest case,
      // because with `setSkipTaskbar(true)` the hotkey is the only route back
      // and the press used to read as a summon.
      await harness.show();
      harness.controller.editText('mine');

      await harness.minimize();
      // The user presses the hotkey rather than waiting for a restore.
      harness.clipboard.text = 'theirs';
      await harness.show();

      expect(harness.state.editorText, equals('mine'));
    });

    test('AD-18: a dismissal ends the session — the hotkey toggle and the '
        'window\'s close control both reach the panel this way', () async {
      harness.clipboard.text = 'the first clipboard';
      await harness.show();
      harness.controller.editText('mine');

      await harness.hide();
      harness.clipboard.text = 'theirs';
      await harness.show();

      expect(harness.state.editorText, equals('theirs'));
      expect(harness.state.status, equals(CorrectionStatus.idle));
      expect(harness.state.suggestionTexts, isEmpty);
    });

    test('CAP-2/DW-30: a dismissal arriving after an iconify is what the next '
        'summon obeys — the last departure decides, not the first', () async {
      // The composed case, and the one the first pass of this change got wrong:
      // a departure landing over a panel that is already away used to be
      // swallowed, so the summon after an explicit dismissal handed back the
      // session the user had just closed.
      harness.clipboard.text = 'the first clipboard';
      await harness.show();
      harness.controller.editText('mine');

      await harness.minimize();
      await harness.hide();
      harness.clipboard.text = 'theirs';
      await harness.show();

      expect(
        harness.state.editorText,
        equals('theirs'),
        reason:
            'the user closed the iconified panel, and closing is the gesture '
            'that means start again (CAP-2)',
      );
    });

    test('CAP-2/DW-30: a dismissal arriving after a focus loss ends the '
        'session too', () async {
      harness.clipboard.text = 'the first clipboard';
      await harness.show();
      harness.controller.editText('mine');

      await harness.loseFocus();
      await harness.hide();
      harness.clipboard.text = 'theirs';
      await harness.show();

      expect(harness.state.editorText, equals('theirs'));
    });

    test('AD-18: the first summon of the daemon\'s life begins a session, with '
        'no departure behind it', () async {
      harness.clipboard.text = 'the clipboard at startup';

      await harness.show();

      expect(
        harness.state.editorText,
        equals('the clipboard at startup'),
        reason:
            'the dismissal latch starts standing, which is what makes the '
            'first summon a session without a special case for it',
      );
    });

    test('DW-30: the suggestions survive a focus loss, and a dismissal clears '
        'them (CAP-5, CAP-13)', () async {
      await harness.show();
      harness.controller.submit();
      harness.run.emit(_completed('formal one', 'casual one', 'shorter one'));
      await pumpEventQueue();
      expect(harness.state.suggestionTexts, isNotEmpty);

      await harness.loseFocus();
      await harness.show();

      expect(
        harness.state.suggestionTexts,
        isNotEmpty,
        reason:
            'a correction the user can still copy is not something a '
            'click-away asked to be rid of',
      );
      expect(harness.state.status, equals(CorrectionStatus.completed));

      await harness.hide();
      await harness.show();

      expect(
        harness.state.suggestionTexts,
        isEmpty,
        reason: 'and a dismissal is the request that does ask',
      );
    });

    test('CAP-13: an inline error survives an iconify — the first thing this '
        'change promises is the state exactly as it was', () async {
      await harness.show();
      harness.controller.submit();
      harness.run.emit(
        const CorrectionFailed(
          kind: CorrectionFailureKind.timeout,
          message: 'the provider timed out',
        ),
      );
      await pumpEventQueue();

      await harness.minimize();
      await harness.restore();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(harness.state.failure?.message, equals('the provider timed out'));
      expect(
        harness.state.submittedText,
        isNotNull,
        reason: 'so the Retry beside the error still has something to replay',
      );
    });

    test('AD-4/CAP-7: a correction still in flight across a focus loss lands '
        'into the session that comes back', () async {
      await harness.show();
      harness.controller.editText('what the user submitted');
      harness.controller.submit();

      await harness.loseFocus();
      await harness.show();
      harness.run.emit(_completed('formal one', 'casual one', 'shorter one'));
      await pumpEventQueue();

      expect(
        harness.state.status,
        equals(CorrectionStatus.completed),
        reason:
            'no departure is one of AD-4\'s cancellations, and the session the '
            'run belongs to is the session on screen — so the answer is '
            'rendered rather than recorded and dropped',
      );
      expect(harness.state.suggestionTexts, isNotEmpty);
      expect(harness.repository.saved, hasLength(1));
    });

    test('AD-4/CAP-13: the failed twin lands the same way — the error reaches '
        'the panel that asked for it', () async {
      await harness.show();
      harness.controller.editText('what the user submitted');
      harness.controller.submit();

      await harness.minimize();
      await harness.restore();
      harness.run.emit(
        const CorrectionFailed(
          kind: CorrectionFailureKind.providerUnavailable,
          message: 'the provider could not be reached',
        ),
      );
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(
        harness.state.failure?.message,
        equals('the provider could not be reached'),
      );
    });

    test('CAP-14/DW-30: a return that begins no session emits nothing at all '
        '— the panel is not told anything happened', () async {
      await harness.show();
      final states = <CorrectionState>[];
      final subscription = harness.controller.changes.listen(states.add);

      await harness.loseFocus();
      await harness.show();
      await harness.minimize();
      await harness.restore();

      expect(
        states,
        isEmpty,
        reason:
            'no session began and nothing in the state moved, so there is '
            'nothing for either consumer to act on',
      );
      await subscription.cancel();
    });

    // Both survivable departures, because the latch answers each of them with
    // its own arm of `_dismissalStandsAfter` and one arm passing says nothing
    // about the other: with only the `focusLost` row here, replacing the
    // `iconified` arm with a flat `false` left the whole suite green.
    for (final departure in const [
      PanelVisibilityState.focusLost,
      PanelVisibilityState.iconified,
    ]) {
      test('AD-18/CAP-2: a survivable ${departure.name} departure cannot erase '
          'a dismissal the user really made, whatever order they arrive in', () async {
        // The mirror image of DW-30, and the reason this ring latches "a
        // dismissal stands" rather than remembering the last state reported. The
        // shipped adapter gates its `hide`, `minimize` and blur arms so it cannot
        // emit this sequence — but that invariant lives two rings below AD-18, and
        // a rule that is only correct by the grace of three `if`s in an
        // infrastructure file is not a rule this layer owns.
        final panel = _RepeatingVisibility();
        final clipboard = FakeClipboardPort(text: 'the first clipboard');
        final controller = CorrectionController(
          clipboard: clipboard,
          provider: FakeCorrectionProvider.manual(),
          preset: _Harness.preset,
          repository: FakeCorrectionRepository(),
          clock: FakeClock(),
          logger: FakeLogger(),
          panelVisibility: panel,
        );
        addTearDown(() async {
          await controller.dispose();
          panel.dispose();
        });

        panel.emit(PanelVisibilityState.shown);
        await pumpEventQueue();
        controller.editText('mine');

        // The user dismisses the panel, and only then does a click-away or a
        // workspace switch report itself.
        panel.emit(PanelVisibilityState.dismissed);
        panel.emit(departure);
        await pumpEventQueue();
        clipboard.text = 'theirs';
        panel.emit(PanelVisibilityState.shown);
        await pumpEventQueue();

        expect(
          controller.state.editorText,
          equals('theirs'),
          reason:
              'the dismissal is the fact about what the user wanted; a departure '
              'that arrives after it says nothing that unsays it (CAP-2)',
        );
      });
    }

    test('AD-18: a second shown from an out-of-contract adapter begins no '
        'second session — the first summon consumed the dismissal', () async {
      // The port emits on a transition, so a duplicate `shown` is an adapter
      // breaking its promise. What makes it inert is that a summon *consumes*
      // the standing dismissal rather than merely being judged against it: the
      // second `shown` finds nothing standing, and the session already on
      // screen — with whatever the user typed in between — is kept.
      final panel = _RepeatingVisibility();
      final clipboard = FakeClipboardPort(text: 'the clipboard seed');
      final controller = CorrectionController(
        clipboard: clipboard,
        provider: FakeCorrectionProvider.manual(),
        preset: _Harness.preset,
        repository: FakeCorrectionRepository(),
        clock: FakeClock(),
        logger: FakeLogger(),
        panelVisibility: panel,
      );
      addTearDown(() async {
        await controller.dispose();
        panel.dispose();
      });

      panel.emit(PanelVisibilityState.shown);
      await pumpEventQueue();
      controller.editText('typed into the one session there was');
      clipboard.text = 'a clipboard nobody should read twice';

      panel.emit(PanelVisibilityState.shown);
      await pumpEventQueue();

      expect(
        controller.state.editorText,
        equals('typed into the one session there was'),
      );
      expect(clipboard.readCalls, equals(1));
    });

    test('CAP-14/DW-30: the fake reports no departure from a panel that is '
        'already away, because the adapter cannot either', () async {
      // Asserted about the fake rather than through the controller, and that
      // needs saying. `CorrectionController` latches "a dismissal stands", so a
      // survivable departure arriving over a dismissal is inert at this ring by
      // design — which means no controller row can tell whether the fake emitted
      // one. The fake is the application ring's only view of the port, so a fake
      // that can emit a sequence the shipped adapter cannot is a licence to pin
      // behaviour nothing implements. In the adapter, `_onBlur` returns on a
      // false mirror and the `minimize` and `hide` arms are gated on `_visible`
      // for the same reason.
      final reported = <PanelVisibilityState>[];
      final watching = harness.panel.changes.listen(reported.add);
      addTearDown(watching.cancel);

      await harness.show();
      await harness.hide();
      // A click-away and a workspace switch at a panel that is already gone.
      await harness.loseFocus();
      await harness.minimize();

      expect(
        reported,
        equals([PanelVisibilityState.shown, PanelVisibilityState.dismissed]),
        reason:
            'a hidden panel has no focus to lose and no window to iconify, so '
            'there is nothing for either gesture to report',
      );
    });

    test('CAP-2/DW-54: the state a session begins with is marked, and nothing '
        'built from it is', () async {
      final states = <CorrectionState>[];
      final subscription = harness.controller.changes.listen(states.add);

      await harness.show();

      expect(states.first.isFreshSession, isTrue);
      expect(
        states.skip(1).map((state) => state.isFreshSession),
        everyElement(isFalse),
        reason:
            'the clipboard seed is an update *within* the session it landed in',
      );
      await subscription.cancel();
    });

    test('CAP-3/DW-54: an editor the user clears by hand is not a session '
        'beginning', () async {
      harness.clipboard.text = 'the clipboard seed';
      await harness.show();
      final states = <CorrectionState>[];
      final subscription = harness.controller.changes.listen(states.add);

      // Select all, delete. An idle session with no suggestions and an empty
      // editor: the exact value `CorrectionState.empty` used to be compared to.
      harness.controller.editText('');
      await pumpEventQueue();

      expect(
        states.single.isFreshSession,
        isFalse,
        reason:
            'a keystroke is not a summon, and the two consumers act once per '
            'session beginning (DW-54)',
      );
      expect(states.single, isNot(equals(CorrectionState.freshSession)));
      await subscription.cancel();
    });
  });

  group('running a correction', () {
    test('CAP-3: the correction runs on what the user edited, not the '
        'clipboard seed', () async {
      harness.clipboard.text = 'clipboard seed';
      await harness.show();

      harness.controller.editText('what the user typed');
      harness.controller.submit();

      expect(
        harness.provider.correctCalls.single.text,
        equals('what the user typed'),
      );
    });

    test('AD-5: the correction runs on the injected preset', () async {
      await harness.show();

      harness.controller.submit();

      expect(
        harness.provider.correctCalls.single.preset,
        same(_Harness.preset),
      );
    });

    test('CAP-5: streamed deltas accumulate per register while the '
        'correction runs', () async {
      await harness.show();
      harness.controller.submit();

      harness.run.emit(
        const SuggestionDelta(
          register: SuggestionRegister.formal,
          textDelta: 'I have ',
        ),
      );
      harness.run.emit(
        const SuggestionDelta(
          register: SuggestionRegister.casual,
          textDelta: "I've ",
        ),
      );
      harness.run.emit(
        const SuggestionDelta(
          register: SuggestionRegister.formal,
          textDelta: 'reviewed it.',
        ),
      );
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.running));
      expect(
        harness.state.suggestionTexts,
        equals({
          SuggestionRegister.formal: 'I have reviewed it.',
          SuggestionRegister.casual: "I've ",
        }),
      );
    });

    test('AD-3: the completed suggestions replace the accumulated '
        'delta text', () async {
      await harness.show();
      harness.controller.submit();
      harness.run.emit(
        const SuggestionDelta(
          register: SuggestionRegister.formal,
          textDelta: 'half-streamed',
        ),
      );
      await pumpEventQueue();

      harness.run.emit(_completed('formal final', 'casual final', 'shorter'));
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.completed));
      expect(
        harness.state.suggestionTexts,
        equals({
          SuggestionRegister.formal: 'formal final',
          SuggestionRegister.casual: 'casual final',
          SuggestionRegister.shorter: 'shorter',
        }),
      );
    });

    test('CAP-13: a failure replaces the half-streamed suggestions '
        'inline', () async {
      await harness.show();
      harness.controller.submit();
      harness.run.emit(
        const SuggestionDelta(
          register: SuggestionRegister.formal,
          textDelta: 'half-streamed',
        ),
      );
      await pumpEventQueue();

      harness.run.emit(
        const CorrectionFailed(
          kind: CorrectionFailureKind.timeout,
          message: 'the provider timed out',
        ),
      );
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(harness.state.suggestionTexts, isEmpty);
      expect(
        harness.state.failure?.kind,
        equals(CorrectionFailureKind.timeout),
      );
      expect(harness.state.failure?.message, equals('the provider timed out'));
    });
  });

  group('persisting to history', () {
    test('CAP-7: a completed correction is saved exactly once, with its '
        'provenance', () async {
      harness.clock.millis = 1000;
      await harness.show();
      harness.controller.editText('teh text i wrote');
      harness.controller.submit();

      harness.clock.advance(250);
      harness.run.emit(_completed('formal', 'casual', 'shorter'));
      harness.run.close();
      await pumpEventQueue();

      final record = harness.repository.saved.single;
      expect(record.inputText, equals('teh text i wrote'));
      expect(record.outcome, equals(CorrectionOutcome.completed));
      expect(record.failureKind, isNull);
      expect(record.suggestions, hasLength(SuggestionRegister.values.length));
      expect(record.createdAtMillis, equals(1000));
      expect(record.latencyMs, equals(250));
      expect(record.presetId, equals(_Harness.preset.id));
      expect(record.providerId, equals(_Harness.preset.providerId));
      expect(record.model, equals(_Harness.preset.model));
    });

    test('CAP-13: a failed correction is saved with its failure kind and '
        'no suggestions', () async {
      await harness.show();
      harness.controller.submit();

      harness.run.emit(
        const CorrectionFailed(
          kind: CorrectionFailureKind.providerUnavailable,
          message: 'the sidecar interpreter is missing',
        ),
      );
      await pumpEventQueue();

      final record = harness.repository.saved.single;
      expect(record.outcome, equals(CorrectionOutcome.failed));
      expect(
        record.failureKind,
        equals(CorrectionFailureKind.providerUnavailable),
      );
      expect(record.suggestions, isEmpty);
    });

    test('AD-4: the provider subscription is torn down at the terminal '
        'event, even if the provider never closes its stream', () async {
      await harness.show();
      harness.controller.submit();
      final finished = harness.run;

      finished.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();

      expect(
        finished.cancelledByConsumer,
        isTrue,
        reason: 'AD-19 makes onCancel the sidecar process-group kill',
      );
    });

    test('AD-7: a provider that emits a second terminal event still '
        'records one correction', () async {
      await harness.show();
      harness.controller.submit();

      harness.run.emit(_completed('formal', 'casual', 'shorter'));
      harness.run.emit(_completed('again', 'again', 'again'));
      await pumpEventQueue();

      expect(harness.repository.saved, hasLength(1));
    });
  });

  group('retrying', () {
    test('CAP-13: Retry re-sends the submitted text, not what the user '
        'typed afterwards', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      harness.run.emit(
        const CorrectionFailed(
          kind: CorrectionFailureKind.providerError,
          message: 'the provider errored',
        ),
      );
      await pumpEventQueue();

      harness.controller.editText('something else entirely');
      harness.controller.retry();

      expect(
        harness.provider.correctCalls.map((call) => call.text),
        equals(['the text i submitted', 'the text i submitted']),
      );
      expect(
        harness.state.editorText,
        equals('something else entirely'),
        reason: 'Retry re-runs the correction; it does not rewrite the editor',
      );
      expect(harness.state.status, equals(CorrectionStatus.running));
      expect(harness.state.failure, isNull);
    });

    test('AD-18: Retry does nothing before the session has submitted '
        'anything', () async {
      await harness.show();

      harness.controller.retry();

      expect(harness.provider.correctCalls, isEmpty);
      expect(harness.state.status, equals(CorrectionStatus.idle));
    });
  });

  group('cancellation (AD-4)', () {
    test('AD-4: Retry cancels the in-flight correction and records '
        'nothing for it', () async {
      await harness.show();
      harness.controller.submit();
      final abandoned = harness.run;

      harness.controller.retry();
      await pumpEventQueue();

      expect(abandoned.cancelledByConsumer, isTrue);
      expect(harness.provider.runs, hasLength(2));
      expect(harness.repository.saved, isEmpty);
    });

    test('AD-4: starting a new correction cancels the in-flight one', () async {
      await harness.show();
      harness.controller.editText('first');
      harness.controller.submit();
      final abandoned = harness.run;

      harness.controller.editText('second');
      harness.controller.submit();
      await pumpEventQueue();

      expect(abandoned.cancelledByConsumer, isTrue);
      expect(harness.provider.correctCalls.last.text, equals('second'));
      expect(harness.repository.saved, isEmpty);
    });

    test('AD-4: nothing new is started after shutdown', () async {
      await harness.show();
      await harness.controller.dispose();

      harness.controller.editText('typed after shutdown');
      harness.controller.submit();

      expect(harness.provider.correctCalls, isEmpty);
      expect(harness.repository.saved, isEmpty);
    });

    test('AD-4: a clipboard read resolving after shutdown changes no '
        'state', () async {
      final gate = Completer<void>();
      harness.clipboard
        ..text = 'late seed'
        ..readGate = gate;
      await harness.show();
      final before = harness.state.editorText;

      await harness.controller.dispose();
      gate.complete();
      await pumpEventQueue();

      expect(harness.state.editorText, equals(before));
    });

    test('AD-4: daemon shutdown cancels the in-flight correction', () async {
      await harness.show();
      harness.controller.submit();
      final abandoned = harness.run;

      await harness.controller.dispose();

      expect(abandoned.cancelledByConsumer, isTrue);
      expect(harness.repository.saved, isEmpty);
    });

    test('CAP-7: hiding the panel does not cancel the correction, and the '
        'record is still persisted', () async {
      await harness.show();
      harness.controller.submit();
      final running = harness.run;

      await harness.hide();
      expect(
        running.cancelledByConsumer,
        isFalse,
        reason: 'hiding is not one of AD-4\'s three cancellations',
      );

      running.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();

      expect(harness.repository.saved, hasLength(1));
      expect(harness.state.status, equals(CorrectionStatus.completed));
    });

    test('CAP-13: a provider stream error becomes an inline failure rather '
        'than an escaping exception', () async {
      await harness.show();
      harness.controller.submit();

      harness.run.emitError(StateError('the adapter threw'));
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(
        harness.state.failure?.kind,
        equals(CorrectionFailureKind.providerError),
      );
      expect(
        harness.repository.saved.single.outcome,
        equals(CorrectionOutcome.failed),
      );
    });

    test('CAP-13: a provider that closes without a terminal event fails the '
        'correction instead of stranding it', () async {
      await harness.show();
      harness.controller.submit();

      harness.run.close();
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(
        harness.state.failure?.kind,
        equals(CorrectionFailureKind.providerError),
      );
      expect(harness.repository.saved, hasLength(1));
    });

    test('AD-18: a correction completing after the panel re-seeded is '
        'persisted but left out of the fresh session', () async {
      harness.clipboard.text = 'first copy';
      await harness.show();
      harness.controller.submit();
      final hidden = harness.run;

      await harness.hide();
      harness.clipboard.text = 'second copy';
      await harness.show();
      hidden.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();

      expect(harness.repository.saved, hasLength(1));
      expect(harness.state.status, equals(CorrectionStatus.idle));
      expect(harness.state.suggestionTexts, isEmpty);
      expect(harness.state.editorText, equals('second copy'));
    });
  });

  group('submitting nothing', () {
    test('CAP-3: an empty editor is not submitted', () async {
      await harness.show();
      harness.controller.editText('');

      harness.controller.submit();
      await pumpEventQueue();

      expect(harness.provider.correctCalls, isEmpty);
      expect(harness.repository.saveAttempts, isEmpty);
      expect(harness.state.status, equals(CorrectionStatus.idle));
      expect(harness.state.submittedText, isNull);
      expect(
        harness.logger.lines
            .where((line) => line.message != 'the correction failed')
            .single
            .level,
        equals('info'),
      );
      expect(
        harness.logger.lines
            .where((line) => line.message != 'the correction failed')
            .single
            .message,
        contains('empty editor'),
        reason:
            'this line is the only thing that tells an operator why a '
            'Correct press did nothing',
      );
    });

    test('CAP-3: an all-whitespace editor is not submitted either', () async {
      await harness.show();
      harness.controller.editText('   \n\t ');

      harness.controller.submit();
      await pumpEventQueue();

      expect(harness.provider.correctCalls, isEmpty);
      expect(harness.state.status, equals(CorrectionStatus.idle));
    });

    test('CAP-13: Retry after a guarded submit still has nothing to '
        'replay', () async {
      await harness.show();
      harness.controller.editText('');
      harness.controller.submit();

      harness.controller.retry();
      await pumpEventQueue();

      expect(harness.provider.correctCalls, isEmpty);
      expect(harness.state.status, equals(CorrectionStatus.idle));
    });
  });

  group('selecting and copying a suggestion', () {
    /// A completed session, which is the only state either act is allowed in.
    Future<void> completedSession() async {
      await harness.show();
      harness.controller.editText('i has went');
      harness.controller.submit();
      harness.run.emit(_completed('formal one', 'casual one', 'shorter one'));
      await pumpEventQueue();
    }

    test('CAP-4: selectSuggestion highlights the register and writes '
        'nothing', () async {
      await completedSession();

      harness.controller.selectSuggestion(SuggestionRegister.casual);
      // Pumped before the clipboard is read back: a write is a future, so
      // asserting straight away would pass however much selecting wrote.
      await pumpEventQueue();

      expect(harness.state.selectedRegister, equals(SuggestionRegister.casual));
      expect(
        harness.clipboard.writes,
        isEmpty,
        reason: 'AD-18: copying is never implicit in selection',
      );
    });

    test('AD-3: selectSuggestion is a no-op while the deltas are still '
        'streaming', () async {
      await harness.show();
      harness.controller.submit();
      harness.run.emit(
        const SuggestionDelta(
          register: SuggestionRegister.formal,
          textDelta: 'half-streamed',
        ),
      );
      await pumpEventQueue();

      harness.controller.selectSuggestion(SuggestionRegister.formal);

      expect(
        harness.state.selectedRegister,
        isNull,
        reason: 'a partial is not the record of truth (AD-3)',
      );
    });

    test('CAP-13: selectSuggestion is a no-op after a failure, which has no '
        'variants to highlight', () async {
      await harness.show();
      harness.controller.submit();
      harness.run.emit(
        const CorrectionFailed(
          kind: CorrectionFailureKind.timeout,
          message: 'the provider timed out',
        ),
      );
      await pumpEventQueue();

      harness.controller.selectSuggestion(SuggestionRegister.formal);

      expect(harness.state.selectedRegister, isNull);
    });

    test('CAP-11: copySuggestion writes exactly that register\'s completed '
        'text, once', () async {
      await completedSession();

      await harness.controller.copySuggestion(SuggestionRegister.casual);

      expect(harness.clipboard.writes, equals(['casual one']));
    });

    test('AD-3: copySuggestion writes nothing while the correction is still '
        'running', () async {
      await harness.show();
      harness.controller.submit();
      harness.run.emit(
        const SuggestionDelta(
          register: SuggestionRegister.formal,
          textDelta: 'half-streamed',
        ),
      );
      await pumpEventQueue();

      await harness.controller.copySuggestion(SuggestionRegister.formal);

      expect(
        harness.clipboard.writes,
        isEmpty,
        reason: 'the completed text is about to replace this (AD-3)',
      );
      expect(harness.state.copyFailure, 'There is no suggestion text to copy.');
    });

    test('CAP-14: every variant stays copyable, in the order they were '
        'copied', () async {
      await completedSession();

      await harness.controller.copySuggestion(SuggestionRegister.formal);
      await harness.controller.copySuggestion(SuggestionRegister.shorter);

      expect(harness.clipboard.writes, equals(['formal one', 'shorter one']));
    });

    test('CAP-11: a rejected write leaves a notice for the user and the error '
        'type for an operator, and never throws', () async {
      await completedSession();
      harness.clipboard.writeError = StateError('no clipboard owner');

      await expectLater(
        harness.controller.copySuggestion(SuggestionRegister.formal),
        completes,
      );

      expect(harness.state.copyFailure, isNotNull);
      expect(
        harness.state.failure,
        isNull,
        reason:
            'a failed copy is not a failed correction, so it must not offer '
            'CAP-13\'s Retry',
      );
      expect(harness.state.status, equals(CorrectionStatus.completed));
      final logged = harness.logger.lines.single;
      expect(logged.level, equals('error'));
      expect(logged.context, equals({'error_type': 'StateError'}));
      expect(
        '${logged.message} ${logged.context}',
        isNot(contains('formal one')),
        reason: 'no log line carries a suggestion body (Logging convention)',
      );
      expect(
        '${logged.message} ${logged.context}',
        isNot(contains('i has went')),
        reason: 'nor the editor text the clipboard seeded',
      );
    });

    test('CAP-14: a rejected copy does not disable the next one, which clears '
        'the notice and leaves the highlight alone', () async {
      await completedSession();
      harness.controller.selectSuggestion(SuggestionRegister.casual);
      harness.clipboard.writeError = StateError('no clipboard owner');
      await harness.controller.copySuggestion(SuggestionRegister.formal);

      harness.clipboard.writeError = null;
      await harness.controller.copySuggestion(SuggestionRegister.shorter);

      expect(harness.clipboard.writes, equals(['shorter one']));
      expect(harness.state.copyFailure, isNull);
      expect(
        harness.state.selectedRegister,
        equals(SuggestionRegister.casual),
        reason:
            'clearing the notice rebuilds the state by hand, and a field '
            'forgotten in that rebuild is a highlight the user loses to a '
            'copy they made of a different variant (AD-18)',
      );
    });

    test('CAP-4: the same digit again clears the highlight, so a selection is '
        'reversible', () async {
      await completedSession();

      harness.controller.selectSuggestion(SuggestionRegister.casual);
      harness.controller.selectSuggestion(SuggestionRegister.casual);

      expect(harness.state.selectedRegister, isNull);

      harness.controller.selectSuggestion(SuggestionRegister.casual);
      harness.controller.selectSuggestion(SuggestionRegister.shorter);

      expect(
        harness.state.selectedRegister,
        equals(SuggestionRegister.shorter),
        reason: 'a different digit moves the highlight rather than clearing it',
      );
    });

    test('CAP-4: deselecting keeps a copy notice that is still true', () async {
      await completedSession();
      harness.controller.selectSuggestion(SuggestionRegister.casual);
      harness.clipboard.writeError = StateError('no clipboard owner');
      await harness.controller.copySuggestion(SuggestionRegister.casual);
      final notice = harness.state.copyFailure;

      harness.controller.selectSuggestion(SuggestionRegister.casual);

      expect(harness.state.selectedRegister, isNull);
      expect(harness.state.copyFailure, equals(notice));
    });

    test('CAP-11: a variant that came back empty is neither copyable nor '
        'selectable', () async {
      await harness.show();
      harness.controller.editText('i has went');
      harness.controller.submit();
      harness.run.emit(_completed('', 'casual one', 'shorter one'));
      await pumpEventQueue();

      await harness.controller.copySuggestion(SuggestionRegister.formal);
      harness.controller.selectSuggestion(SuggestionRegister.formal);

      expect(
        harness.clipboard.writes,
        isEmpty,
        reason: 'there is nothing to put on the clipboard',
      );
      expect(harness.state.copyFailure, 'There is no suggestion text to copy.');
      expect(harness.state.selectedRegister, isNull);
    });

    test('CAP-11: a variant that came back as whitespace is not copyable '
        'either — it would overwrite the clipboard with nothing', () async {
      await harness.show();
      harness.controller.editText('i has went');
      harness.controller.submit();
      harness.run.emit(_completed('   \n ', 'casual one', 'shorter one'));
      await pumpEventQueue();

      await harness.controller.copySuggestion(SuggestionRegister.formal);
      harness.controller.selectSuggestion(SuggestionRegister.formal);

      expect(harness.clipboard.writes, isEmpty);
      expect(harness.state.selectedRegister, isNull);
    });

    test(
      'PANEL-03: a slow rejection precedes the later successful write',
      () async {
        await completedSession();
        final slow = Completer<void>();
        harness.clipboard
          ..writeGate = slow
          ..writeError = StateError('no clipboard owner');
        final rejecting = harness.controller.copySuggestion(
          SuggestionRegister.formal,
        );
        await pumpEventQueue();

        // The second copy is issued while the first is still in flight, which is
        // what the panel allows: every variant stays copyable (CAP-14).
        harness.clipboard
          ..writeGate = null
          ..writeError = null;
        final succeeding = harness.controller.copySuggestion(
          SuggestionRegister.shorter,
        );
        slow.complete();
        await rejecting;
        await succeeding;

        expect(harness.clipboard.writes, equals(['shorter one']));
        expect(
          harness.state.copyFailure,
          isNull,
          reason:
              'the clipboard holds the text the user asked for last, so a '
              'notice saying the copy failed would be false',
        );
        expect(
          harness.logger.lines,
          isEmpty,
          reason: 'and the superseded rejection is nobody\'s news',
        );
      },
    );

    test(
      'PANEL-03: slow and timed-out writes settle before later copies',
      () async {
        await completedSession();
        final slow = Completer<void>();
        harness.clipboard.writeGate = slow;
        final succeeding = harness.controller.copySuggestion(
          SuggestionRegister.formal,
        );
        await pumpEventQueue();

        harness.clipboard
          ..writeGate = null
          ..writeError = StateError('no clipboard owner');
        final rejecting = harness.controller.copySuggestion(
          SuggestionRegister.shorter,
        );
        slow.complete();
        await succeeding;
        await rejecting;
        final rejected = harness.state.copyFailure;

        expect(rejected, isNotNull);
        expect(harness.clipboard.writes, equals(['formal one']));
        expect(harness.state.copyFailure, equals(rejected));

        final late = Completer<void>();
        harness.clipboard
          ..writeGate = late
          ..writeError = null;
        final first = harness.controller.copySuggestion(
          SuggestionRegister.formal,
        );
        await pumpEventQueue();

        await first;
        expect(harness.state.copyFailure, isNotNull);
        expect(harness.clipboard.writes, equals(['formal one']));

        harness.clipboard.writeGate = null;
        final second = harness.controller.copySuggestion(
          SuggestionRegister.shorter,
        );
        await pumpEventQueue();
        expect(
          harness.clipboard.writes,
          equals(['formal one']),
          reason: 'a timed-out platform write still owns the physical queue',
        );
        expect(harness.state.copyPending, isTrue);

        late.complete();
        await second;

        expect(
          harness.clipboard.writes,
          equals(['formal one', 'formal one', 'shorter one']),
        );
        expect(harness.clipboard.text, equals('shorter one'));
        expect(harness.state.copySucceeded, isTrue);
        expect(
          harness.state.copyFailure,
          isNull,
          reason:
              'only the last request reports success and owns the clipboard',
        );
      },
    );

    test('AD-18: a rejection landing after a new submit paints no notice onto '
        'the new run', () async {
      await completedSession();
      final slow = Completer<void>();
      harness.clipboard
        ..writeGate = slow
        ..writeError = StateError('no clipboard owner');
      final rejecting = harness.controller.copySuggestion(
        SuggestionRegister.formal,
      );

      harness.controller.submit();
      await pumpEventQueue();
      slow.complete();
      await rejecting;

      expect(
        harness.state.copyFailure,
        isNull,
        reason:
            'the notice sits beside the variants, and these are not the '
            'variants that copy was taken from',
      );
      expect(harness.state.status, equals(CorrectionStatus.running));

      // And it does not arrive with the next answer either: `_onCompleted`
      // carries the state forward with copyWith, which cannot clear a field.
      harness.run.emit(_completed('formal two', 'casual two', 'shorter two'));
      await pumpEventQueue();

      expect(harness.state.copyFailure, isNull);
    });

    test(
      'AD-18: a new run drops a notice the previous answer earned',
      () async {
        await completedSession();
        harness.clipboard.writeError = StateError('no clipboard owner');
        await harness.controller.copySuggestion(SuggestionRegister.formal);
        expect(harness.state.copyFailure, isNotNull);

        harness.controller.submit();
        await pumpEventQueue();

        expect(
          harness.state.copyFailure,
          isNull,
          reason: 'the variants it was about are gone (AD-18)',
        );
      },
    );

    test('AD-18: copySuggestion never sets the highlight', () async {
      await completedSession();

      await harness.controller.copySuggestion(SuggestionRegister.formal);

      expect(harness.state.selectedRegister, isNull);
    });

    test('AD-18: a summon after a dismissal clears the highlight and the copy '
        'notice', () async {
      await completedSession();
      harness.controller.selectSuggestion(SuggestionRegister.casual);
      harness.clipboard.writeError = StateError('no clipboard owner');
      await harness.controller.copySuggestion(SuggestionRegister.casual);
      expect(harness.state.copyFailure, isNotNull);

      harness.clipboard.writeError = null;
      await harness.hide();
      await harness.show();

      expect(harness.state.selectedRegister, isNull);
      expect(harness.state.copyFailure, isNull);
    });

    test('AD-18: a new run clears the highlight, which belonged to the '
        'previous answer', () async {
      await completedSession();
      harness.controller.selectSuggestion(SuggestionRegister.casual);

      harness.controller.submit();
      await pumpEventQueue();

      expect(harness.state.selectedRegister, isNull);
    });

    test('AD-18: a copy that resolves after a new session began reports '
        'nothing into that session', () async {
      await completedSession();
      final gate = Completer<void>();
      harness.clipboard
        ..writeGate = gate
        ..writeError = StateError('no clipboard owner');
      final copying = harness.controller.copySuggestion(
        SuggestionRegister.formal,
      );

      await harness.hide();
      await harness.show();
      gate.complete();
      await copying;

      expect(
        harness.state.copyFailure,
        isNull,
        reason:
            'the session that asked for the copy is gone, so its failure '
            'would be attributed to whatever session is current now',
      );
      expect(
        harness.logger.lines,
        isEmpty,
        reason: 'and for the same reason it is not logged',
      );
    });

    test('CAP-3: a deselect carries the draft and the submitted text forward, '
        'so clearing the highlight cannot wipe what the user typed', () async {
      // The two clearing transitions rebuild the state field by field, because
      // `copyWith` cannot clear one. A field forgotten in that rebuild is a
      // field silently reset: the panel feeds the editor from `editorText`, so a
      // dropped draft is overwritten in the `TextField` the user is typing in,
      // and a dropped `submittedText` turns a later Retry into a no-op.
      await completedSession();
      harness.controller.selectSuggestion(SuggestionRegister.casual);
      harness.controller.editText('a draft i kept after the answer landed');

      harness.controller.selectSuggestion(SuggestionRegister.casual);

      expect(harness.state.selectedRegister, isNull);
      expect(
        harness.state.editorText,
        equals('a draft i kept after the answer landed'),
      );
      expect(harness.state.submittedText, equals('i has went'));
      expect(harness.state.status, equals(CorrectionStatus.completed));
      expect(harness.state.suggestionTexts, hasLength(3));
    });

    test('CAP-3: a successful copy that clears a notice carries the draft and '
        'the submitted text forward too', () async {
      await completedSession();
      harness.clipboard.writeError = StateError('no clipboard owner');
      await harness.controller.copySuggestion(SuggestionRegister.formal);
      expect(harness.state.copyFailure, isNotNull);
      harness.controller.editText('a draft i kept after the answer landed');

      harness.clipboard.writeError = null;
      await harness.controller.copySuggestion(SuggestionRegister.casual);

      expect(harness.state.copyFailure, isNull);
      expect(
        harness.state.editorText,
        equals('a draft i kept after the answer landed'),
      );
      expect(harness.state.submittedText, equals('i has went'));
      expect(harness.state.suggestionTexts, hasLength(3));
    });

    test('CAP-11: each variant\'s rejected copy is its own notice, so a second '
        'failure is a new state rather than the same one again', () async {
      await completedSession();
      harness.clipboard.writeError = StateError('no clipboard owner');

      await harness.controller.copySuggestion(SuggestionRegister.formal);
      final first = harness.state.copyFailure;
      await harness.controller.copySuggestion(SuggestionRegister.casual);
      final second = harness.state.copyFailure;

      expect(first, contains(SuggestionRegister.formal.name));
      expect(second, contains(SuggestionRegister.casual.name));
      expect(
        second,
        isNot(equals(first)),
        reason:
            'an identical sentence is an ==-equal state: nothing is emitted to '
            'announce and a distinct() consumer drops it',
      );
      for (final notice in [first, second]) {
        expect(
          notice,
          isNot(contains('one')),
          reason: 'and no notice carries a suggestion body',
        );
      }
    });
  });

  group('a completion whose registers break AD-3', () {
    test('AD-3: a completion with a duplicated register fails the correction '
        'instead of recording it as completed', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();

      harness.run.emit(
        const CorrectionCompleted(
          suggestions: [
            Suggestion(register: SuggestionRegister.formal, text: 'one'),
            Suggestion(register: SuggestionRegister.formal, text: 'two'),
            Suggestion(register: SuggestionRegister.casual, text: 'three'),
          ],
        ),
      );
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(
        harness.state.failure?.kind,
        equals(CorrectionFailureKind.malformedResponse),
      );
      expect(harness.state.suggestionTexts, isEmpty);

      final record = harness.repository.saved.single;
      expect(record.outcome, equals(CorrectionOutcome.failed));
      expect(
        record.failureKind,
        equals(CorrectionFailureKind.malformedResponse),
      );
      expect(record.suggestions, isEmpty);
      expect(
        harness.logger.lines
            .where((line) => line.message != 'the correction failed')
            .single
            .level,
        equals('error'),
      );
    });

    test('AD-3: a completion missing a register is treated the same '
        'way (CAP-7)', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();

      harness.run.emit(
        const CorrectionCompleted(
          suggestions: [
            Suggestion(register: SuggestionRegister.formal, text: 'one'),
            Suggestion(register: SuggestionRegister.casual, text: 'two'),
          ],
        ),
      );
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(
        harness.repository.saved.single.outcome,
        equals(CorrectionOutcome.failed),
      );
      expect(
        harness.repository.saved.single.failureKind,
        equals(CorrectionFailureKind.malformedResponse),
      );
    });

    test('CAP-13: Retry still works after a malformed completion', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      harness.run.emit(
        const CorrectionCompleted(
          suggestions: [
            Suggestion(register: SuggestionRegister.formal, text: 'only one'),
          ],
        ),
      );
      await pumpEventQueue();

      harness.controller.retry();

      expect(
        harness.provider.correctCalls.map((call) => call.text),
        equals(['the text i submitted', 'the text i submitted']),
      );
      expect(harness.state.status, equals(CorrectionStatus.running));
    });

    test('AD-3: a completion carrying every register plus a duplicate is '
        'rejected, not silently deduplicated (CAP-7)', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();

      harness.run.emit(
        const CorrectionCompleted(
          suggestions: [
            Suggestion(register: SuggestionRegister.formal, text: 'one'),
            Suggestion(register: SuggestionRegister.casual, text: 'two'),
            Suggestion(register: SuggestionRegister.shorter, text: 'three'),
            Suggestion(register: SuggestionRegister.formal, text: 'again'),
          ],
        ),
      );
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(
        harness.repository.saved.single.outcome,
        equals(CorrectionOutcome.failed),
      );
      expect(
        harness.repository.saved.single.failureKind,
        equals(CorrectionFailureKind.malformedResponse),
      );
    });

    test('AD-3: a completion carrying every register in any order is '
        'accepted (CAP-7)', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();

      harness.run.emit(
        const CorrectionCompleted(
          suggestions: [
            Suggestion(register: SuggestionRegister.shorter, text: 'short'),
            Suggestion(register: SuggestionRegister.formal, text: 'formal'),
            Suggestion(register: SuggestionRegister.casual, text: 'casual'),
          ],
        ),
      );
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.completed));
      expect(harness.repository.saved.single.suggestions, hasLength(3));
      expect(
        harness.repository.saved.single.outcome,
        equals(CorrectionOutcome.completed),
      );
      expect(harness.logger.lines, isEmpty);
    });
  });

  group('ports that fail (AD-15 backstops)', () {
    test('CAP-7: a rejected history write leaves the completed correction '
        'on screen and is attempted exactly once', () async {
      harness.repository.saveError = StateError('the history file is locked');
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();

      harness.run.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();

      expect(
        harness.state.status,
        equals(CorrectionStatus.completed),
        reason: 'the correction succeeded; only its record did not',
      );
      expect(harness.state.suggestionTexts, hasLength(3));
      expect(harness.state.failure, isNull);
      expect(harness.repository.saveAttempts, hasLength(1));
      expect(harness.repository.saved, isEmpty);
      expect(
        harness.logger.lines
            .where((line) => line.message != 'the correction failed')
            .single
            .level,
        equals('error'),
      );

      await harness.controller.dispose();
      expect(
        harness.repository.saveAttempts,
        hasLength(1),
        reason: 'AD-7 allows one attempt per terminal event, never a retry',
      );
    });

    test('CAP-2: a clipboard read that throws leaves the session usable with '
        'an empty editor', () async {
      harness.clipboard.readError = StateError('no selection owner');

      await harness.show();

      expect(harness.state.editorText, isEmpty);
      expect(harness.state.status, equals(CorrectionStatus.idle));
      expect(
        harness.logger.lines
            .where((line) => line.message != 'the correction failed')
            .single
            .level,
        equals('warning'),
      );

      harness.controller.editText('typed by hand instead');
      harness.controller.submit();

      expect(harness.provider.correctCalls, hasLength(1));
    });

    test('AD-3: a provider that throws instead of returning a stream becomes '
        'one inline failure (CAP-13)', () async {
      harness.provider.correctError = StateError('the sidecar could not spawn');
      await harness.show();
      harness.controller.editText('the text i submitted');

      harness.controller.submit();
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(
        harness.state.failure?.kind,
        equals(CorrectionFailureKind.providerError),
      );
      final record = harness.repository.saved.single;
      expect(record.outcome, equals(CorrectionOutcome.failed));
      expect(record.failureKind, equals(CorrectionFailureKind.providerError));
      expect(
        harness.logger.lines
            .where((line) => line.message != 'the correction failed')
            .single
            .level,
        equals('error'),
      );
    });

    test('CAP-2: a visibility stream error leaves the controller live for the '
        'next show, and the dismissal latch it holds intact', () async {
      harness.panel.emitChangesError(StateError('the window event failed'));
      await pumpEventQueue();
      expect(
        harness.logger.lines
            .where((line) => line.message != 'the correction failed')
            .single
            .level,
        equals('error'),
      );

      harness.clipboard.text = 'seeded after the stream error';
      await harness.show();

      expect(harness.state.editorText, equals('seeded after the stream error'));

      // And the error is not a departure either: an out-of-contract emission
      // must not be mistaken for the panel going away, or the summon after one
      // would discard the session the user is in the middle of (AD-18).
      harness.controller.editText('typed after the error');
      await harness.loseFocus();
      harness.panel.emitChangesError(StateError('and again on the way back'));
      await pumpEventQueue();
      harness.clipboard.text = 'a clipboard nobody should read';
      await harness.show();

      expect(
        harness.state.editorText,
        equals('typed after the error'),
        reason:
            'no dismissal stands — the last thing the stream *said* was a focus '
            'loss — and an error in between says nothing about where the window '
            'is',
      );
    });

    test('CAP-13: a rejected save leaves the inline failure and its Retry '
        'intact', () async {
      harness.repository.saveError = StateError('the history file is locked');
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();

      harness.run.emit(
        const CorrectionFailed(
          kind: CorrectionFailureKind.timeout,
          message: 'the provider timed out',
        ),
      );
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.failed));
      expect(
        harness.state.failure?.kind,
        equals(CorrectionFailureKind.timeout),
      );
      expect(harness.state.failure?.message, equals('the provider timed out'));
      expect(harness.state.submittedText, equals('the text i submitted'));
      expect(harness.repository.saveAttempts, hasLength(1));
      expect(harness.repository.saved, isEmpty);
      expect(
        harness.logger.lines
            .where((line) => line.message != 'the correction failed')
            .single
            .level,
        equals('error'),
      );
    });

    test('CAP-7: a rejected save for a record that landed after the re-seed '
        'leaves the fresh session untouched (AD-4)', () async {
      harness.clipboard.text = 'first copy';
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      final hidden = harness.run;

      await harness.hide();
      harness.clipboard.text = 'second copy';
      await harness.show();

      harness.repository.saveError = StateError('the history file is locked');
      hidden.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();

      expect(harness.repository.saveAttempts, hasLength(1));
      expect(harness.repository.saved, isEmpty);
      expect(harness.state.status, equals(CorrectionStatus.idle));
      expect(harness.state.suggestionTexts, isEmpty);
      expect(harness.state.editorText, equals('second copy'));
      expect(
        harness.logger.lines
            .where((line) => line.message != 'the correction failed')
            .single
            .level,
        equals('error'),
      );
    });

    test('AD-4: shutdown completes even when the pending history write '
        'rejects', () async {
      harness.repository.saveError = StateError('the history file is locked');
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      harness.run.emit(_completed('formal', 'casual', 'shorter'));

      await expectLater(harness.controller.dispose(), completes);
    });

    test('CAP-7: shutdown waits for a history write still in flight', () async {
      final writing = Completer<void>();
      harness.repository.saveGate = writing;
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      harness.run.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();

      var shutdown = false;
      unawaited(harness.controller.dispose().then((_) => shutdown = true));
      await pumpEventQueue();

      expect(
        shutdown,
        isFalse,
        reason:
            'a correction that terminates as the daemon exits is still '
            'retained (CAP-7), so shutdown cannot outrun its write',
      );
      expect(harness.repository.saved, isEmpty);

      writing.complete();
      await pumpEventQueue();

      expect(shutdown, isTrue);
      expect(harness.repository.saved, hasLength(1));
    });

    test('CAP-2: a clipboard read failing for a session already replaced is '
        'not reported against the current one', () async {
      final reading = Completer<void>();
      harness.clipboard
        ..readGate = reading
        ..readError = StateError('no selection owner');
      await harness.panel.show();
      await pumpEventQueue();
      expect(harness.logger.lines, isEmpty, reason: 'still parked on the read');

      // A second show supersedes the first before its read resolves. This one
      // fails too, and it is the session the user is actually looking at.
      harness.clipboard.readGate = null;
      await harness.hide();
      await harness.show();
      expect(harness.logger.lines, hasLength(1));

      reading.complete();
      await pumpEventQueue();

      expect(
        harness.logger.lines,
        hasLength(1),
        reason:
            'warning about a session that no longer exists would '
            'attribute the failure to the one that replaced it',
      );
    });

    test('CAP-2: a clipboard read failing after shutdown is not reported '
        'either', () async {
      // The staleness check has two halves and the session-token half is the
      // only one the test above can reach: here nothing supersedes the
      // session, the controller simply stops existing while the read is in
      // flight.
      final reading = Completer<void>();
      harness.clipboard
        ..readGate = reading
        ..readError = StateError('no selection owner');
      await harness.panel.show();
      await pumpEventQueue();
      expect(harness.logger.lines, isEmpty, reason: 'still parked on the read');

      await harness.controller.dispose();
      reading.complete();
      await pumpEventQueue();

      expect(
        harness.logger.lines,
        isEmpty,
        reason: 'a torn-down controller has nothing left to report against',
      );
    });
  });

  group('a cancel that rejects (AD-4)', () {
    test('CAP-13: Retry still starts its run when cancelling the in-flight '
        'one rejects', () async {
      final unhandled = <Object>[];

      await runZonedGuarded(() async {
        await harness.show();
        harness.controller.editText('the text i submitted');
        harness.controller.submit();
        harness.run.cancelError = StateError('the sidecar refused to die');

        harness.controller.retry();
        await pumpEventQueue();

        expect(harness.provider.correctCalls, hasLength(2));
        expect(harness.state.status, equals(CorrectionStatus.running));
      }, (error, stack) => unhandled.add(error));

      expect(
        unhandled,
        isEmpty,
        reason:
            'the cancel future is discarded, so an unguarded rejection '
            'would surface as an unhandled error in the daemon\'s zone',
      );
      expect(
        harness.logger.lines.where((line) => line.level == 'error'),
        hasLength(1),
      );
    });

    test('AD-4: a new submit still starts its run when cancelling the '
        'in-flight one rejects', () async {
      final unhandled = <Object>[];

      await runZonedGuarded(() async {
        await harness.show();
        harness.controller.editText('first');
        harness.controller.submit();
        harness.run.cancelError = StateError('the sidecar refused to die');

        harness.controller.editText('second');
        harness.controller.submit();
        await pumpEventQueue();

        expect(harness.provider.correctCalls.last.text, equals('second'));
        expect(harness.state.status, equals(CorrectionStatus.running));
        expect(harness.repository.saveAttempts, isEmpty);
      }, (error, stack) => unhandled.add(error));

      expect(unhandled, isEmpty);
      expect(
        harness.logger.lines.where((line) => line.level == 'error'),
        hasLength(1),
      );
    });

    test('AD-4: a blank submit does not cancel the correction already '
        'streaming (CAP-3)', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      final running = harness.run;

      harness.controller.editText('   ');
      harness.controller.submit();
      await pumpEventQueue();

      expect(
        running.cancelledByConsumer,
        isFalse,
        reason:
            'pressing Correct on a blank editor is a mistake; killing '
            'the run in progress would punish it',
      );
      expect(harness.provider.correctCalls, hasLength(1));
      expect(harness.state.status, equals(CorrectionStatus.running));

      running.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();

      expect(harness.state.status, equals(CorrectionStatus.completed));
      expect(harness.repository.saved, hasLength(1));
    });

    test('AD-4: shutdown completes when cancelling the visibility '
        'subscription rejects', () async {
      harness.panel.cancelError = StateError(
        'the window event stream '
        'refused to close',
      );
      await harness.show();

      await expectLater(harness.controller.dispose(), completes);

      final failures = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(failures, hasLength(1));
      expect(
        failures.single.message,
        contains('the panel visibility subscription'),
        reason:
            'one helper serves three subscriptions, so an operator reading '
            'stderr must see which of them refused',
      );
    });

    test('AD-4: shutdown completes when cancelling the in-flight run '
        'rejects', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      harness.run.cancelError = StateError('the sidecar refused to die');

      await expectLater(harness.controller.dispose(), completes);

      final failures = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(failures, hasLength(1));
      expect(failures.single.message, contains('the in-flight correction'));
    });

    test('AD-19: a teardown cancel refused at the terminal event is named '
        'and never escapes the zone', () async {
      // `_finish` fires this cancel without awaiting it, and it is the one of
      // the three cancel sites no other test reaches — under AD-19 it is the
      // sidecar's process-group kill, the likeliest of them all to refuse.
      final unhandled = <Object>[];

      await runZonedGuarded(() async {
        await harness.show();
        harness.controller.editText('the text i submitted');
        harness.controller.submit();
        harness.run.cancelError = StateError('the sidecar refused to die');

        harness.run.emit(_completed('formal', 'casual', 'shorter'));
        await pumpEventQueue();
      }, (error, stack) => unhandled.add(error));

      expect(unhandled, isEmpty);
      expect(harness.state.status, equals(CorrectionStatus.completed));
      final failures = harness.logger.lines.where(
        (line) => line.level == 'error',
      );
      expect(failures, hasLength(1));
      expect(failures.single.message, contains('the terminated correction'));
    });
  });

  group('after shutdown', () {
    test('AD-4: a run whose cancel refused still stops delivering, so '
        'shutdown cannot strand a history write (CAP-7)', () async {
      // Why `dispose()` needs no guard on the terminal-event path: cancelling
      // a subscription ends delivery even when the cancel itself rejects, so
      // the pending-write snapshot at the end of shutdown cannot miss one.
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      final running = harness.run;
      running.cancelError = StateError('the sidecar refused to die');

      await harness.controller.dispose();
      running.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();

      expect(harness.repository.saveAttempts, isEmpty);
    });

    test('CAP-11: a copy pressed after shutdown writes no clipboard', () async {
      // The widget tree outlives `dispose()` — AD-8 keeps it built — so the
      // copy button is still there to press while the ordered teardown is
      // closing the adapter underneath it. Pinning both new members here
      // because the equivalent property for `submit()` has had a row since
      // story 3, and neither of these did: deleting both `_disposed` arms
      // failed nothing.
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      harness.run.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();
      await harness.controller.dispose();

      await harness.controller.copySuggestion(SuggestionRegister.values.first);

      expect(harness.clipboard.writes, isEmpty);
    });

    test('AD-18: a visibility event arriving after shutdown starts no '
        'session and reads no clipboard (CAP-2)', () async {
      harness.panel.cancelError = StateError('the window event channel gone');
      await harness.show();
      expect(harness.clipboard.readCalls, equals(1));

      await harness.controller.dispose();
      harness.panel.cancelError = null;

      await harness.hide();
      await harness.show();

      expect(
        harness.clipboard.readCalls,
        equals(1),
        reason:
            'a refused cancel leaves the subscription live, and a session '
            'begun now would issue display-server IPC from a controller '
            'that is already torn down',
      );
    });
  });

  test('nothing sensitive reaches the log on any failure path', () async {
    const secret = 'the private message i pasted';
    const suggestionBody = 'a suggestion body nobody may log';
    final lines =
        <({String level, String message, Map<String, Object?>? context})>[];

    _Harness fresh() {
      final harness = _Harness();
      addTearDown(harness.dispose);
      return harness;
    }

    final seeding = fresh();
    seeding.clipboard
      ..text = secret
      ..readError = const EchoingError('selection owner vanished', secret);
    await seeding.show();
    lines.addAll(seeding.logger.lines);

    final refusing = fresh();
    // An echoing error, not a plain one: a failed spawn stringifies its
    // argument list, and the submitted text is on it. A hand-written
    // StateError cannot tell a logged type from a stringified error.
    refusing.provider.correctError = const EchoingError(
      'spawn failed',
      '--text $secret',
    );
    await refusing.show();
    refusing.controller.editText(secret);
    refusing.controller.submit();
    await pumpEventQueue();
    lines.addAll(refusing.logger.lines);

    final malformed = fresh();
    await malformed.show();
    malformed.controller.editText(secret);
    malformed.controller.submit();
    malformed.run.emit(
      const CorrectionCompleted(
        suggestions: [
          Suggestion(register: SuggestionRegister.formal, text: suggestionBody),
          Suggestion(register: SuggestionRegister.formal, text: suggestionBody),
        ],
      ),
    );
    await pumpEventQueue();
    lines.addAll(malformed.logger.lines);

    final rejecting = fresh();
    // The shape a real SqliteException takes when a statement fails during
    // execution: it appends the failing statement and its bound parameters,
    // which for the history write are the corrected text and every
    // suggestion body.
    rejecting.repository.saveError = const EchoingError(
      'while executing statement, disk image is malformed',
      '$secret, $suggestionBody',
    );
    await rejecting.show();
    rejecting.controller.editText(secret);
    rejecting.controller.submit();
    rejecting.run.emit(
      _completed(suggestionBody, suggestionBody, suggestionBody),
    );
    await pumpEventQueue();
    lines.addAll(rejecting.logger.lines);

    // The visibility stream and the cancel guards reduce a caught error too,
    // and neither is on any path above — an assertion over only the paths a
    // test happens to drive reads as exhaustive without being it.
    final streaming = fresh();
    await streaming.show();
    streaming.panel.emitChangesError(
      const EchoingError('the window event decode failed', secret),
    );
    await pumpEventQueue();
    streaming.controller.editText(secret);
    streaming.controller.submit();
    streaming.run.cancelError = const EchoingError(
      'the sidecar refused to die',
      '$secret, $suggestionBody',
    );
    streaming.controller.retry();
    await pumpEventQueue();
    lines.addAll(streaming.logger.lines);

    expect(
      lines,
      hasLength(8),
      reason: 'every guard and terminal correction failure is logged',
    );
    expect(
      lines.where((line) => line.message == 'the correction failed'),
      hasLength(2),
    );
    for (final line in lines) {
      final logged = '${line.message} ${line.context}';
      expect(logged, isNot(contains(secret)));
      expect(logged, isNot(contains(suggestionBody)));
    }
  });

  test(
    'CAP-13: each modeled failure is logged once with safe kind and session context',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.show();
      for (final kind in CorrectionFailureKind.values) {
        harness.controller.submit();
        harness.run.emit(
          CorrectionFailed(
            kind: kind,
            message: 'vendor message with private payload',
          ),
        );
        await pumpEventQueue();
      }
      final failures = harness.logger.lines
          .where((line) => line.message == 'the correction failed')
          .toList();
      expect(
        failures.map((line) => line.context?['failure_kind']),
        CorrectionFailureKind.values.map((kind) => kind.name),
      );
      expect(failures.every((line) => line.context?.keys.length == 2), isTrue);
      expect(
        failures.every(
          (line) => !line.context.toString().contains('private payload'),
        ),
        isTrue,
      );
    },
  );

  group('what a failure tells the user, and what it tells an operator', () {
    late _Harness harness;

    setUp(() => harness = _Harness());
    tearDown(() => harness.dispose());

    test('CAP-13: a provider that cannot start renders a sentence, not the '
        'exception it threw', () async {
      const secret = 'the private message i pasted';
      harness.provider.correctError = const EchoingError(
        'spawn failed',
        '--text $secret',
      );
      await harness.show();
      harness.controller.editText(secret);

      harness.controller.submit();
      await pumpEventQueue();

      final message = harness.state.failure!.message;
      expect(message, isNotEmpty);
      expect(
        message,
        isNot(contains(secret)),
        reason:
            'a failed spawn stringifies its argument list, and the '
            'submitted text is on it',
      );
      expect(message, isNot(contains('SqliteException')));
    });

    test('AD-3: an over-complete register set does not tell the user that '
        'variants are missing (CAP-13)', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();

      harness.run.emit(
        const CorrectionCompleted(
          suggestions: [
            Suggestion(register: SuggestionRegister.formal, text: 'one'),
            Suggestion(register: SuggestionRegister.casual, text: 'two'),
            Suggestion(register: SuggestionRegister.shorter, text: 'three'),
            Suggestion(register: SuggestionRegister.formal, text: 'again'),
          ],
        ),
      );
      await pumpEventQueue();

      expect(
        harness.state.failure!.message,
        isNot(contains('missing')),
        reason: 'nothing is missing here — the response was over-complete',
      );
      expect(harness.state.failure!.message, isNotEmpty);
    });

    test('CAP-7: a lost history row tells the operator which correction it '
        'was, and nothing about its content', () async {
      harness.repository.saveError = StateError('the history file is locked');
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();
      harness.clock.advance(1234);
      harness.run.emit(_completed('formal', 'casual', 'shorter'));
      await pumpEventQueue();

      // The values, not just the key set: a context that names every key and
      // reports another correction's preset — or `completed` for a failed
      // record — identifies the wrong lost correction just as effectively as
      // no context at all.
      expect(
        harness.logger.lines.single.context,
        equals({
          'preset_id': _Harness.preset.id,
          'provider_id': _Harness.preset.providerId,
          'model': _Harness.preset.model,
          'outcome': 'completed',
          'latency_ms': 1234,
          'error_type': 'StateError',
        }),
        reason: 'the operator has to identify the correction that was lost',
      );
      expect(
        harness.logger.lines.single.context!.keys,
        isNot(contains('input_text')),
      );
    });

    test('AD-3: a malformed register set logs the counts an operator needs '
        'to diagnose the provider', () async {
      await harness.show();
      harness.controller.editText('the text i submitted');
      harness.controller.submit();

      harness.run.emit(
        const CorrectionCompleted(
          suggestions: [
            Suggestion(register: SuggestionRegister.formal, text: 'one'),
            Suggestion(register: SuggestionRegister.casual, text: 'two'),
          ],
        ),
      );
      await pumpEventQueue();

      expect(
        harness.logger.lines
            .where(
              (line) =>
                  line.message ==
                  'the provider completed with a malformed register set',
            )
            .single
            .context,
        equals({
          'expected_registers': 3,
          'received_suggestions': 2,
          'distinct_registers': 2,
        }),
      );
    });

    test('AD-15: a logger whose own sink is gone does not turn a guard into '
        'an unhandled error (CAP-1)', () async {
      final unhandled = <Object>[];
      final throwingLogger = ThrowingLogger();

      await runZonedGuarded(() async {
        final clipboard = FakeClipboardPort(text: 'a seed')
          ..readError = StateError('no selection owner');
        final repository = FakeCorrectionRepository()
          ..saveError = StateError('the history file is locked');
        final panel = FakePanelVisibility();
        final provider = FakeCorrectionProvider.manual();
        final controller = CorrectionController(
          clipboard: clipboard,
          provider: provider,
          preset: _Harness.preset,
          repository: repository,
          clock: FakeClock(),
          logger: throwingLogger,
          panelVisibility: panel,
        );

        await panel.show();
        await pumpEventQueue();
        panel.emitChangesError(StateError('the window event decode failed'));
        await pumpEventQueue();
        controller.editText('what the user typed');
        controller.submit();
        provider.runs.last.emit(_completed('formal', 'casual', 'shorter'));
        await pumpEventQueue();

        await expectLater(controller.dispose(), completes);
        panel.dispose();
      }, (error, _) => unhandled.add(error));
      await pumpEventQueue();

      expect(
        throwingLogger.attempts,
        equals(['warning', 'error', 'error']),
        reason:
            'the seed, the visibility stream and the history write each '
            'still tried to report — `isNotEmpty` is satisfied by any one '
            'of them, so two could stop trying and stay green',
      );
      expect(unhandled, isEmpty);
    });

    test('AD-15: a broken logger does not break the guards the case above '
        'never reaches (CAP-1)', () async {
      // Four of this controller's seven log sites are unreachable from the
      // harness above, and each one recovers by logging: a swallow that
      // covers only the reached ones is a swallow that is half there.
      final unhandled = <Object>[];
      final throwingLogger = ThrowingLogger();

      await runZonedGuarded(() async {
        final panel = FakePanelVisibility();
        final provider = FakeCorrectionProvider.manual();
        final controller = CorrectionController(
          clipboard: FakeClipboardPort(text: 'a seed'),
          provider: provider,
          preset: _Harness.preset,
          repository: FakeCorrectionRepository(),
          clock: FakeClock(),
          logger: throwingLogger,
          panelVisibility: panel,
        );

        await panel.show();
        await pumpEventQueue();

        // the empty-submit guard
        controller.editText('   ');
        expect(controller.submit, returnsNormally);

        // the AD-3 register-set check
        controller.editText('what the user typed');
        controller.submit();
        provider.runs.last.emit(
          const CorrectionCompleted(
            suggestions: [
              Suggestion(register: SuggestionRegister.formal, text: 'one'),
            ],
          ),
        );
        await pumpEventQueue();

        // a provider that will not even return a stream
        provider.correctError = StateError('the sidecar could not spawn');
        expect(controller.retry, returnsNormally);
        await pumpEventQueue();

        // a teardown cancel that refuses
        provider.correctError = null;
        controller.editText('again');
        controller.submit();
        provider.runs.last.cancelError = StateError('the sidecar will not die');

        await expectLater(controller.dispose(), completes);
        panel.dispose();
      }, (error, _) => unhandled.add(error));
      await pumpEventQueue();

      expect(
        throwingLogger.attempts,
        equals(['info', 'error', 'error', 'error', 'error', 'error']),
        reason:
            'the empty-submit guard, the register check, the provider throw '
            'and the refused cancel each still tried to report',
      );
      expect(unhandled, isEmpty);
    });
  });
}

CorrectionCompleted _completed(String formal, String casual, String shorter) {
  return CorrectionCompleted(
    suggestions: [
      Suggestion(register: SuggestionRegister.formal, text: formal),
      Suggestion(register: SuggestionRegister.casual, text: casual),
      Suggestion(register: SuggestionRegister.shorter, text: shorter),
    ],
  );
}

/// The controller wired to nothing but fakes — no Flutter binding, no
/// ProviderContainer.
final class _Harness {
  _Harness() {
    controller = CorrectionController(
      clipboard: clipboard,
      provider: provider,
      preset: preset,
      repository: repository,
      clock: clock,
      logger: logger,
      panelVisibility: panel,
    );
  }

  static const Preset preset = Preset(
    id: 'default-formal-casual-shorter',
    providerId: 'claude-agent-sdk',
    model: 'claude-sonnet-5',
    systemPrompt: 'correct the text',
  );

  /// Seeded, because an empty editor is not submittable: the controller
  /// guards it, so a session that means to correct something must have text.
  final FakeClipboardPort clipboard = FakeClipboardPort(
    text: 'the clipboard seed',
  );
  final FakeCorrectionProvider provider = FakeCorrectionProvider.manual();
  final FakeCorrectionRepository repository = FakeCorrectionRepository();
  final FakeClock clock = FakeClock();
  final FakeLogger logger = FakeLogger();
  final FakePanelVisibility panel = FakePanelVisibility();

  late final CorrectionController controller;

  CorrectionState get state => controller.state;

  /// The correction the controller most recently started.
  FakeCorrectionRun get run => provider.runs.last;

  Future<void> show() async {
    await panel.show();
    await pumpEventQueue();
  }

  Future<void> hide() async {
    await panel.hide();
    await pumpEventQueue();
  }

  /// The adapter's focus-loss hide (CAP-14) — a departure the session survives.
  ///
  /// Every focus-loss site in this file goes through here rather than driving
  /// the fake and pumping inline, so a row reads as the gesture it is testing.
  Future<void> loseFocus() async {
    panel.loseFocus();
    await pumpEventQueue();
  }

  /// The window iconified by the window manager — the other survivable
  /// departure.
  Future<void> minimize() async {
    panel.minimize();
    await pumpEventQueue();
  }

  /// The window de-iconified by the window manager, which reports `shown`
  /// exactly as a summon does.
  Future<void> restore() async {
    panel.restore();
    await pumpEventQueue();
  }

  Future<void> dispose() async {
    await controller.dispose();
    panel.dispose();
  }
}

/// An adapter that breaks the port's transition contract on purpose: it reports
/// whatever a row pushes, including a second `shown`.
///
/// Deliberately not a capability of [FakePanelVisibility]. That fake exists to
/// be the port kept honestly, and a member for emitting a sequence the port
/// forbids would be a footgun in every other row that uses it.
final class _RepeatingVisibility implements PanelVisibility {
  @override
  Stream<void> get closeRequests => const Stream<void>.empty();

  final StreamController<PanelVisibilityState> _changes =
      StreamController<PanelVisibilityState>.broadcast();

  PanelVisibilityState _state = PanelVisibilityState.dismissed;

  @override
  bool get isVisible => _state.isVisible;

  @override
  Stream<PanelVisibilityState> get changes => _changes.stream;

  @override
  Future<void> show() async => emit(PanelVisibilityState.shown);

  @override
  Future<void> hide() async => emit(PanelVisibilityState.dismissed);

  void emit(PanelVisibilityState state) {
    _state = state;
    _changes.add(state);
  }

  void dispose() => unawaited(_changes.close());
}
