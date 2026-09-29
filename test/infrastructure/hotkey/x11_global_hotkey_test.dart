import 'dart:async';

import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/domain/logger.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_grab.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_registrar.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/x11_global_hotkey.dart';
import 'package:test/test.dart';

import '../../fakes/fake_hotkey_registrar.dart';
import '../../fakes/fake_logger.dart';
import '../../fakes/throwing_logger.dart';

/// The X11 adapter's whole contract, over a [FakeHotkeyRegistrar].
///
/// Everything here is the decision-making half of the grab: what `bind()`
/// reports, what a refused rebind costs the user, what a press becomes, and what
/// every refusal degrades to. None of it needs a Flutter binding, which is the
/// point of the seam — the shipped one talks to `libX11.so.6` over `dart:ffi`
/// from a worker isolate, and the rules below would otherwise only be reachable
/// with a live X server.
///
/// What this suite deliberately cannot say: that a real key grab happened. See
/// `test/platform/x11_hotkey_live_test.dart`, which records that as owed.
///
/// Pure Dart: no Flutter binding (AGENTS.md §7).
void main() {
  late FakeHotkeyRegistrar registrar;
  late FakeLogger logger;

  setUp(() {
    registrar = FakeHotkeyRegistrar();
    logger = FakeLogger();
  });

  X11GlobalHotkey build({Logger? withLogger}) {
    final hotkey = X11GlobalHotkey(
      registrar: registrar,
      logger: withLogger ?? logger,
    );
    addTearDown(hotkey.dispose);
    return hotkey;
  }

  List<({String level, String message, Map<String, Object?>? context})>
  errors() => logger.lines.where((line) => line.level == 'error').toList();

  group('binding (CAP-1, CAP-12, AD-10, AD-12)', () {
    test('CAP-1, AD-10: a first bind grabs, and reports the combination it was '
        'given as the application-owned effective one', () async {
      final hotkey = build();

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(
        registrar.calls,
        ['grab(HotkeyGrab(control+shift 0x0007000a))'],
        reason:
            'the seam owns the swap now, so the adapter issues no bare release '
            'on the bind path — a release the adapter issued first is a release '
            'that has already happened when the grab is refused',
      );
      expect(
        registrar.grabs.single,
        HotkeyGrab(
          modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
          usbHidUsage: 0x0007000a,
        ),
      );
      expect(
        outcome,
        HotkeyBound(
          HotkeyRegistration(
            effective: _ctrlShiftG,
            authority: BindingAuthority.application,
          ),
        ),
      );
      expect(errors(), isEmpty);
    });

    test('CAP-12: a rebind is one atomic swap inside the seam, and reports the '
        'new combination — no restart involved', () async {
      final hotkey = build();
      await hotkey.bind(_ctrlShiftG);
      registrar.calls.clear();

      final outcome = await hotkey.bind(_altQ);

      expect(
        registrar.calls,
        ['grab(HotkeyGrab(alt 0x00070014))'],
        reason:
            'the seam acquires, confirms, and only then releases the previous '
            'combination, so at most one is ever held and a refused '
            'acquisition cannot leave the user without a shortcut',
      );
      expect(
        (outcome as HotkeyBound).registration.effective,
        _altQ,
        reason: 'AD-10 reports what is in effect, not what was in effect',
      );
    });

    test('CAP-12: rebinding to the same combination still reaches the seam — '
        'there is no short-circuit on an unchanged request', () async {
      final hotkey = build();
      await hotkey.bind(_ctrlShiftG);
      registrar.calls.clear();

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(
        registrar.calls,
        ['grab(HotkeyGrab(control+shift 0x0007000a))'],
        reason:
            'a short-circuit keyed off the *request* closes every recovery '
            'path — a binding that was refused, or lost, could then never be '
            'asked for again. The seam has an already-satisfied check of its '
            'own and it compares against what it actually holds, which is only '
            'ever set after a grab the server confirmed',
      );
      expect(outcome, isA<HotkeyBound>());
    });

    test('AD-12: a key this build cannot register is answered without the '
        'backend at all', () async {
      final hotkey = build();

      final outcome = await hotkey.bind(
        HotkeyBinding(modifiers: {HotkeyModifier.control}, key: 'Compose'),
      );

      expect(
        registrar.calls,
        isEmpty,
        reason:
            'the catalogue is the whole of what this build can register, so '
            'the answer needs no round trip',
      );
      expect((outcome as HotkeyUnavailable).message, contains('Compose'));
      expect(
        outcome.message,
        contains('tray menu'),
        reason: 'AD-12 keeps the app usable and the message says how',
      );
      expect(
        errors(),
        isEmpty,
        reason: 'a request that was answerable is not an error',
      );
    });

    test('AD-12: a refused grab with nothing held is a value, and logs the '
        'error type only', () async {
      registrar.grabError = StateError('the channel is gone');
      final hotkey = build();

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(outcome, isA<HotkeyUnavailable>());
      expect((outcome as HotkeyUnavailable).message, contains('tray menu'));
      expect(errors(), hasLength(1));
      expect(
        errors().single.context,
        {'error_type': 'StateError'},
        reason: 'a vendor error toString routinely carries its payload',
      );
    });

    test('HOTKEY-08, D-06, SC4: the cause comes from the seam\'s refusal code, '
        'so a no-backend refusal is not reported as a refused key', () async {
      // The row whose absence let the defect through a whole phase and a code
      // review. Nothing in `test/` asserted which cause *any* adapter produces
      // for a given backend condition — every `HotkeyUnavailableCause` in the
      // suite was hand-fed to a fake or to a domain equality row — so this
      // adapter hard-coding `keyRefused` for all four of the seam's refusals
      // was pinned by nothing. Live consequence: on a host where no X display
      // can be opened, the settings screen said "That combination was refused.
      // Choose a different one and apply it again", which is advice no
      // combination on that host can take.
      //
      // Both directions are asserted in one row on purpose: `noBackend` alone
      // would pass against a mapping that had merely swapped one hard-coded
      // literal for another.
      const noDisplayMessage =
          'no X display could be opened, so the shortcut cannot be '
          'registered — the tray menu still opens the panel';
      registrar.grabError = const HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.noBackend,
        message: noDisplayMessage,
      );
      final hotkey = build();

      final absent = await hotkey.bind(_ctrlShiftG);

      expect(
        absent,
        const HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: noDisplayMessage,
        ),
        reason:
            'the seam diagnosed noBackend in its own words, and the cause is '
            'the field a consumer reads instead of the sentence (HOTKEY-08). '
            'The sentence is carried through rather than replaced: it is '
            'project-authored, it is the specific diagnosis a three-value enum '
            'cannot hold, and it already names the tray (AD-12)',
      );
      expect(
        errors().single.context,
        {'error_type': 'HotkeyRegistrarRefusal', 'refusal_code': 'noBackend'},
        reason:
            'the operator gets the named code too — the journal used to carry '
            'only StateError, so the four refusals were indistinguishable '
            'there as well. Still no toString(): the code is an enum name this '
            'project authored',
      );

      // The contrast. A backend that answered and refused this one combination
      // is still `keyRefused`, because another combination may well bind — the
      // distinction AD-12 turns on.
      registrar.grabError = const HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.keyRefused,
        message:
            'another application already owns that shortcut, so it could not '
            'be registered — pick a different combination, or use the tray '
            'menu',
      );

      final refused = await hotkey.bind(_ctrlShiftG);

      expect(
        (refused as HotkeyUnavailable).cause,
        HotkeyUnavailableCause.keyRefused,
      );
      expect(refused.message, contains('pick a different combination'));
    });

    test('D-10, AD-10: a grab the seam refuses mid-rebind abandons the rebind '
        'and reports the combination that is still live', () async {
      // This row used to drive a refused *release*, because the adapter
      // released before it grabbed and that was the only refusal which could
      // reach a live previous combination. The claim is unchanged — a refusal
      // must not cost the user a shortcut they never asked to give up — and it
      // has moved to the call that now carries it. A rejected `grab` has
      // released nothing (see `HotkeyRegistrar.grab`), so the previous
      // combination is still grabbed and still opens the panel; saying "the
      // hotkey is inactive" there would be true of the request and false of the
      // machine.
      final hotkey = build();
      await hotkey.bind(_ctrlShiftG);
      registrar.calls.clear();
      registrar.grabError = StateError('another application owns that');

      final outcome = await hotkey.bind(_altQ);

      expect(
        registrar.calls,
        ['grab(HotkeyGrab(alt 0x00070014))'],
        reason:
            'the grab is attempted and refused, and no release accompanies it '
            'on either side: nothing the user had is spent on a failed request',
      );
      expect(
        (outcome as HotkeyBound).registration.effective,
        _ctrlShiftG,
        reason:
            'AD-10 effective is what is actually in effect, and the previous '
            'combination still is',
      );
      expect(outcome.registration.authority, BindingAuthority.application);
      expect(
        errors(),
        hasLength(1),
        reason:
            'the caller is handed a binding it did not ask for, so the '
            'abandonment must not also be silent',
      );
      expect(errors().single.context, {'error_type': 'StateError'});
      expect(errors().single.message, contains('abandoned'));

      // And the combination reported is the one that still reaches the panel —
      // which is the whole of D-10 and the half a call-sequence assertion
      // cannot state.
      final activations = <void>[];
      hotkey.activations.listen(activations.add);
      registrar.emitPress();
      await pumpEventQueue();

      expect(activations, hasLength(1));
    });

    test('HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears '
        'the previous combination instead of reporting it as in effect', () async {
      // The oracle for this defect, written before the fix exists and recorded
      // failing at this commit. `HotkeyRefusalCode.workerGone` was named
      // nowhere under `test/` at HEAD 8dab2e7 — `grep -rn workerGone test/`
      // returned 0 matches — and that absence is what let the adapter compute
      // `_refusalOf(error)` at `x11_global_hotkey.dart:213` and then branch only
      // on whether `_effective != null`, with the whole suite green.
      //
      // The distinction is AD-12's own dividing question, applied to the rebind
      // arm rather than the nothing-held one. A refusal the backend *answered*
      // has released nothing, so the previous combination is still grabbed and
      // still opens the panel — that is the row directly above, and it must not
      // change. A refusal that says the backend itself is gone took the holder
      // of that grab with it, so reporting the previous combination as in effect
      // names a shortcut nothing is serving while it is still taken from every
      // other application.
      //
      // The seam's own sentence, verbatim from `_onWorkerMessage`'s call to
      // `_failPending` (`x11_key_grab_registrar.dart:281-284`), so the row also
      // pins that the authored diagnosis is carried through rather than
      // replaced — the half the `noBackend` row above pins for the other code
      // on this arm.
      const workerGoneMessage =
          'the X11 hotkey worker stopped before answering, so no global '
          'shortcut is registered — the tray menu still opens the panel';
      final hotkey = build();

      expect(
        await hotkey.bind(_ctrlShiftG),
        isA<HotkeyBound>(),
        reason:
            'load-bearing rather than incidental: this row is about the rebind '
            'arm, so a previous combination has to be genuinely recorded '
            'first. A later change that made this first bind fail would move '
            'the row onto the nothing-held arm and turn it green for the wrong '
            'reason',
      );
      registrar.calls.clear();
      registrar.grabError = const HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.workerGone,
        message: workerGoneMessage,
      );

      final outcome = await hotkey.bind(_altQ);

      expect(
        outcome,
        const HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: workerGoneMessage,
        ),
        reason:
            'the worker that owned the previous grab is gone, so reporting the '
            'previous combination as effective would name a shortcut nothing '
            'is serving while it is still taken from every other application. '
            '`HotkeyUnavailableCause.noBackend` is the answer because there is '
            'nothing left to ask: inviting the user to pick a different '
            'combination is advice no combination on this host can take',
      );
      expect(
        hotkey.current?.outcome,
        const HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: workerGoneMessage,
        ),
        reason:
            'the adapter\'s own record has to agree with what it returned. '
            '`current` is what a settings screen mounting later reads '
            'synchronously (HOTKEY-06), so a fix that returned the right value '
            'and left the recorded status saying HotkeyBound would still show '
            'the user "In effect:" under a dead backend',
      );

      registrar.grabError = null;

      expect(
        await hotkey.bind(_altQ),
        isA<HotkeyBound>(),
        reason:
            'the recovery path stays open — the refusal was not recorded as '
            'held, so the same combination can be asked for again once a '
            'backend exists to ask, exactly as the nothing-held row below '
            'claims for its own arm',
      );

      expect(errors(), hasLength(1));
      expect(errors().single.context, {
        'error_type': 'HotkeyRegistrarRefusal',
        'refusal_code': 'workerGone',
      });
      expect(
        errors().single.message,
        'the X11 key grab was refused',
        reason:
            'stated as the positive rather than as the absence of the '
            'abandoned-rebind sentence, so the row cannot pass against an '
            'adapter that emits neither. This is a refusal the adapter answers '
            'as a refusal, and it is the line the nothing-held arm already '
            'emits for exactly that',
      );
    });

    test('D-10, AD-10, CR-02: keyRefused leaves the previous combination in '
        'effect, because a backend that answered has released nothing', () async {
      // The first of three control rows. The row above can be made green by a
      // fix that answers HotkeyUnavailable for *every* refusal — which would
      // silently undo the acquire-before-release ordering, D-10's product rule
      // and UAT test 3's live pass. These three are what make that
      // over-application fail loudly instead of passing quietly. All three are
      // green against the unfixed adapter at this commit and must stay green
      // through the fix: they are the routes that must not change.
      //
      // The claim, rather than a restatement of the assertion: a refusal the
      // backend *answered* has released nothing, so the previous combination is
      // still grabbed and still opening the panel. Saying "the hotkey is
      // inactive" there would be true of the request and false of the machine.
      const contendedMessage =
          'another application already owns that shortcut, so it could not '
          'be registered — pick a different combination, or use the tray menu';
      final hotkey = build();
      await hotkey.bind(_ctrlShiftG);
      registrar.calls.clear();
      registrar.grabError = const HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.keyRefused,
        message: contendedMessage,
      );

      final outcome = await hotkey.bind(_altQ);

      expect(
        (outcome as HotkeyBound).registration.effective,
        _ctrlShiftG,
        reason:
            'AD-10 effective is what is actually in effect, and a backend that '
            'refused this one combination is still holding the previous one',
      );
      expect(outcome.registration.authority, BindingAuthority.application);
      expect(
        errors(),
        hasLength(1),
        reason:
            'the caller is handed a binding it did not ask for, so the '
            'abandonment must not also be silent',
      );
      expect(errors().single.message, contains('abandoned'));

      // The half a call-sequence check cannot state: the combination reported
      // is the one that still reaches the panel.
      final activations = <void>[];
      hotkey.activations.listen(activations.add);
      registrar.emitPress();
      await pumpEventQueue();

      expect(
        activations,
        hasLength(1),
        reason:
            'the grab the refusal left standing is still delivering presses — '
            'which is what makes reporting it as in effect a true statement '
            'here and a false one for a backend that is gone',
      );
    });

    test('D-10, AD-10, CR-02: badRequest leaves the previous combination in '
        'effect — a protocol defect is not an absent backend', () async {
      // The code with no coverage of its own either. `_causeOf`'s doc says
      // badRequest lands on the non-defeatist reading deliberately: the two
      // halves of the registrar disagreeing about their own message shape is a
      // defect, not a property of the host, and a backend that answered at all
      // is still holding the previous grab. This row is what pins that reading
      // against a fix that reads the code and treats every refusal as fatal.
      const malformedMessage =
          'the grab request was malformed, so the shortcut could not be '
          'registered — the tray menu still opens the panel';
      final hotkey = build();
      await hotkey.bind(_ctrlShiftG);
      registrar.calls.clear();
      registrar.grabError = const HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.badRequest,
        message: malformedMessage,
      );

      final outcome = await hotkey.bind(_altQ);

      expect(
        (outcome as HotkeyBound).registration.effective,
        _ctrlShiftG,
        reason:
            'the request was rejected, not the backend lost — nothing the user '
            'had was spent on it',
      );
      expect(outcome.registration.authority, BindingAuthority.application);
      expect(errors(), hasLength(1));
      expect(errors().single.message, contains('abandoned'));
    });

    test('D-10, AD-10, CR-02: a rejection that is not a refusal leaves the '
        'previous combination in effect', () async {
      // This row overlaps the `D-10, AD-10: a grab the seam refuses mid-rebind
      // abandons the rebind` row above on its claim, and it exists anyway as
      // the third member of a matrix rather than as new coverage. Deleting it
      // as a duplicate costs the matrix its null case: keyRefused, badRequest
      // and *no refusal value at all* are the three inputs on which the fix
      // must not change its answer, and a reader comparing this group against
      // the fix needs all three side by side to see that the change is scoped
      // to the fourth.
      //
      // A bare StateError is what `_refusalOf` reduces to null, and `_causeOf`
      // takes the same non-defeatist reading for it: the disposed-during-bind
      // race is already answered elsewhere by `_shutDownDuringBind`.
      final hotkey = build();
      await hotkey.bind(_ctrlShiftG);
      registrar.calls.clear();
      registrar.grabError = StateError('the channel is gone');

      final outcome = await hotkey.bind(_altQ);

      expect((outcome as HotkeyBound).registration.effective, _ctrlShiftG);
      expect(outcome.registration.authority, BindingAuthority.application);
      expect(errors(), hasLength(1));
      expect(errors().single.message, contains('abandoned'));
      expect(
        errors().single.context,
        {'error_type': 'StateError'},
        reason:
            'no refusal_code key: `_refusalContext` adds one only when '
            '`_refusalOf` answered a value, and a vendor error toString '
            'routinely carries its payload so the type is all that is logged',
      );
    });

    test('HOTKEY-01, HOTKEY-08, CR-02: noBackend refused mid-rebind clears the '
        'previous combination too — the answer follows the cause, not the '
        'arm', () async {
      // The other code that maps to `HotkeyUnavailableCause.noBackend`, driven
      // on the arm it had no coverage for. The `HOTKEY-08, D-06, SC4` row above
      // drives `noBackend` on the *nothing-held* arm only, where the unfixed
      // adapter already answered correctly; nothing asserted what it does when
      // a previous combination is recorded. Without this row the fix could have
      // been written to key off `workerGone` alone and the suite would not have
      // noticed — which would leave a host whose display went away telling the
      // user a shortcut is in effect that nothing can serve.
      const noDisplayMessage =
          'no X display could be opened, so the shortcut cannot be '
          'registered — the tray menu still opens the panel';
      final hotkey = build();

      expect(
        await hotkey.bind(_ctrlShiftG),
        isA<HotkeyBound>(),
        reason:
            'load-bearing: this row is about the rebind arm, so a previous '
            'combination has to be genuinely recorded before the refusal',
      );
      registrar.grabError = const HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.noBackend,
        message: noDisplayMessage,
      );

      final outcome = await hotkey.bind(_altQ);

      expect(
        outcome,
        const HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: noDisplayMessage,
        ),
        reason:
            'there is no backend left to be holding the previous grab, so '
            'naming it as effective is the same false claim `workerGone` makes '
            'one row up — the code differs, the cause does not, and the cause '
            'is what the arm reads',
      );
      expect(
        hotkey.current?.outcome,
        const HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: noDisplayMessage,
        ),
        reason:
            'what a later-mounting settings screen reads synchronously has to '
            'agree with what bind() returned (HOTKEY-06)',
      );
      expect(errors(), hasLength(1));
      expect(errors().single.context, {
        'error_type': 'HotkeyRegistrarRefusal',
        'refusal_code': 'noBackend',
      });
      expect(
        errors().single.message,
        'the X11 key grab was refused',
        reason:
            'the arm that cleared the binding must not also emit the sentence '
            'claiming the previous combination is still in effect — a log line '
            'contradicting the value beside it moves the lie into the journal '
            'rather than removing it',
      );
    });

    test('HOTKEY-01, HOTKEY-08, CR-02: workerGone refused on a first bind is '
        'still noBackend — the code decides, not the arm', () async {
      // The other diagonal. Read with the `workerGone` rebind row above, this
      // is what says the answer follows the refusal code rather than whether
      // something happened to be held: the same code on the arm where nothing
      // is recorded produces the same cause and the same sentence. A fix that
      // had made the cause depend on `_effective` would pass one of these two
      // rows and fail the other.
      const workerGoneMessage =
          'the X11 hotkey worker stopped before answering, so no global '
          'shortcut is registered — the tray menu still opens the panel';
      registrar.grabError = const HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.workerGone,
        message: workerGoneMessage,
      );
      final hotkey = build();

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(
        outcome,
        const HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: workerGoneMessage,
        ),
        reason:
            'nothing was held and there is nothing left to ask, so both halves '
            'of the disjunct agree here — the row exists because they must '
            'agree, not because either alone is in doubt',
      );
      expect(hotkey.current?.outcome, outcome);
      expect(errors(), hasLength(1));
      expect(errors().single.context, {
        'error_type': 'HotkeyRegistrarRefusal',
        'refusal_code': 'workerGone',
      });
    });

    test('HOTKEY-01, CR-02: after a rebind cleared by workerGone the adapter '
        'binds a third combination and it fires', () async {
      // What the cleared `_effective` is *for*. Every other row here checks
      // that the adapter stops claiming something false; this one checks it did
      // not buy that by latching. A fix that cleared the field and then refused
      // to rebind — or that kept reporting the dead combination from `current`
      // — would satisfy the whole matrix above and still leave the user with no
      // shortcut and no way to ask for one.
      //
      // A third combination rather than a retry of either earlier one, so the
      // row cannot pass on a stale record of something already seen.
      const workerGoneMessage =
          'the X11 hotkey worker stopped before answering, so no global '
          'shortcut is registered — the tray menu still opens the panel';
      final hotkey = build();
      await hotkey.bind(_ctrlShiftG);
      registrar.grabError = const HotkeyRegistrarRefusal(
        code: HotkeyRefusalCode.workerGone,
        message: workerGoneMessage,
      );
      await hotkey.bind(_altQ);

      registrar.grabError = null;
      registrar.calls.clear();

      final recovered = await hotkey.bind(_ctrlAltM);

      expect(
        (recovered as HotkeyBound).registration.effective,
        _ctrlAltM,
        reason:
            'the path re-opens: nothing was recorded as held by the refusal, '
            'so the next request reaches the seam and is answered on its own '
            'merits',
      );
      expect(recovered.registration.authority, BindingAuthority.application);
      expect(
        registrar.calls,
        ['grab(HotkeyGrab(alt+control 0x00070010))'],
        reason:
            'one grab and no release: the adapter had already let go of its '
            'record, so there is nothing left for it to try to release',
      );
      expect(
        hotkey.current?.outcome,
        recovered,
        reason:
            'the recorded status follows the recovery too — a screen mounting '
            'after all this reads the combination that actually works',
      );

      final activations = <void>[];
      hotkey.activations.listen(activations.add);
      registrar.emitPress();
      await pumpEventQueue();

      expect(
        activations,
        hasLength(1),
        reason:
            'and the third combination genuinely opens the panel, which is the '
            'half no outcome value can state',
      );
      expect(
        errors(),
        hasLength(1),
        reason:
            'exactly the one refusal, and nothing added by the recovery — a '
            'successful bind is not an error',
      );
    });

    test('AD-12: a refused grab is never recorded as effective, so the same '
        'combination can always be asked for again', () async {
      // The row this replaces built its state through a *successful* release
      // mid-rebind — the adapter let the old combination go, then the grab was
      // refused, so nothing was in effect and `HotkeyUnavailable` was the truth.
      // That sequence is unreachable now, and deliberately: the release only
      // happens once the acquisition is confirmed, so a refusal never empties
      // `_effective`. The claim underneath it survives whole — a refusal must
      // not be mistaken for a registration — and this is where it is reachable:
      // a refused first bind leaves nothing held, and because nothing was
      // recorded, the identical request can be made again and succeed. A
      // short-circuit keyed off the request would have closed that path.
      final hotkey = build();
      registrar.grabError = StateError('the channel is gone');

      final refused = await hotkey.bind(_ctrlShiftG);

      expect(
        refused,
        isA<HotkeyUnavailable>(),
        reason: 'nothing was ever held, so "the hotkey is inactive" is true',
      );

      registrar.grabError = null;
      final retried = await hotkey.bind(_ctrlShiftG);

      expect(
        (retried as HotkeyBound).registration.effective,
        _ctrlShiftG,
        reason:
            'the refusal was not recorded as held, so the recovery path is '
            'open — asking for the same combination again is how a user gets '
            'back a shortcut a conflicting application has since released',
      );
      expect(registrar.calls, [
        'grab(HotkeyGrab(control+shift 0x0007000a))',
        'grab(HotkeyGrab(control+shift 0x0007000a))',
      ]);
    });

    test('CAP-12: an empty modifier set is legal config and is grabbed like '
        'any other', () async {
      final hotkey = build();

      final outcome = await hotkey.bind(
        HotkeyBinding(modifiers: {}, key: 'F12'),
      );

      expect(registrar.calls, ['grab(HotkeyGrab(0x00070045))']);
      expect(registrar.grabs.single.modifiers, isEmpty);
      expect(outcome, isA<HotkeyBound>());
    });

    test('AD-10, AD-12: a key outside the catalogue is refused before the '
        'backend is touched', () async {
      // Re-pointed, not retired. This row used to iterate
      // `HotkeyKeyCatalogue.labelsThatBindTheWrongKey` — seven labels the
      // removed vendor chain bound to a keypad, ISO or 3270 variant — and once
      // that set emptied the loop body would never have run, so the row would
      // have passed while asserting nothing. The live subject is the refusal
      // that remains: a label the catalogue does not resolve at all. It is the
      // one `_bind` answers first, and the reason it must answer without the
      // backend is unchanged — a grab this adapter knows can never fire is a
      // failed grab, and AD-10 forbids reporting one as success.
      final hotkey = build();

      for (final label in const ['PrintScreen', 'CapsLock', 'F13', 'Numpad0']) {
        expect(
          HotkeyKeyCatalogue.usbHidUsageFor(label),
          isNull,
          reason:
              'the row proves nothing unless these really are outside the '
              'catalogue — every one is a real physical key',
        );
        final outcome = await hotkey.bind(
          HotkeyBinding(modifiers: const {HotkeyModifier.alt}, key: label),
        );

        expect(
          outcome,
          isA<HotkeyUnavailable>(),
          reason:
              'the catalogue is the whole of what this build can register, so '
              'a label outside it is a settled no — the tray must not state '
              'that hotkeys are available for it',
        );
        expect((outcome as HotkeyUnavailable).message, contains(label));
        expect(outcome.message, contains('tray menu'));
      }

      expect(
        registrar.calls,
        isEmpty,
        reason: 'the answer is known without a round trip',
      );
    });

    test('AD-10: a rebind to a key this build cannot register keeps the live '
        'combination and reports *that*, not inactivity', () async {
      // The refusals above are answered before the backend is touched, so a
      // rebind that hits one has released nothing: the previous combination is
      // still grabbed and still opens the panel. Answering `HotkeyUnavailable`
      // there would say "the hotkey is inactive" about a shortcut that is very
      // much active — and `SettingsController.changeHotkey` stores the new
      // preference either way, so the tray and the settings screen would both
      // show no shortcut while the old one kept firing for the rest of the
      // session. AD-10 settles it: `effective` is what is actually in effect.
      // This is the same answer the refused-release path gives, for the same
      // reason.
      final hotkey = build();
      await hotkey.bind(_ctrlShiftG);
      registrar.calls.clear();

      final outcome = await hotkey.bind(
        HotkeyBinding(modifiers: {HotkeyModifier.control}, key: 'Compose'),
      );

      expect(
        registrar.calls,
        isEmpty,
        reason:
            'a request answerable without the backend must not drop a working '
            'shortcut on its way to failing',
      );
      expect(
        (outcome as HotkeyBound).registration.effective,
        _ctrlShiftG,
        reason: 'the previous combination is what is genuinely in effect',
      );
      expect(outcome.registration.authority, BindingAuthority.application);
      expect(
        errors(),
        hasLength(1),
        reason:
            'the caller is handed a binding it did not ask for, so the refusal '
            'must not also be silent',
      );

      final activations = <void>[];
      hotkey.activations.listen(activations.add);
      registrar.emitPress();
      await pumpEventQueue();

      expect(
        activations,
        hasLength(1),
        reason:
            'the reported combination is the one that still reaches the panel',
      );
    });

    test('CAP-12: Alt+Space is an ordinary rebind now that the vendor chain '
        'is gone', () async {
      // Re-pointed, not retired. This row asserted that a rebind to `Space`
      // kept the previous combination, because `Space` was one of the seven
      // labels the removed vendor chain bound to `KP_Space` and the adapter
      // refused it before the backend. It binds correctly now, so the row
      // asserts the opposite fact about the same combination — and that is
      // worth a row rather than a deletion, because `Alt+Space` is the exact
      // combination DW-43 was filed about.
      final hotkey = build();
      await hotkey.bind(_ctrlShiftG);
      registrar.calls.clear();

      final altSpace = HotkeyBinding(
        modifiers: {HotkeyModifier.alt},
        key: 'Space',
      );
      final outcome = await hotkey.bind(altSpace);

      expect(registrar.calls, ['grab(HotkeyGrab(alt 0x0007002c))']);
      expect((outcome as HotkeyBound).registration.effective, altSpace);
      expect(
        errors(),
        isEmpty,
        reason: 'nothing went wrong, so nothing is reported',
      );
    });

    test('AD-13: the catalogue lookup is case- and whitespace-insensitive, so '
        'a hand-edited spelling still grabs the key it names', () async {
      // Re-pointed, not retired. This row drove `' space '` and asserted a
      // *refusal*, because `Space` was one of the seven the old chain bound
      // wrongly and the adapter had to refuse every casing of it. The refusal
      // is gone with the defect; the normalization it relied on is not, and it
      // is what keeps a hand-edited config (AD-13) meaning one thing. So the
      // same input now has to reach the backend as the same grab a canonical
      // spelling would.
      final hotkey = build();

      final outcome = await hotkey.bind(
        HotkeyBinding(modifiers: {HotkeyModifier.alt}, key: ' space '),
      );

      expect(outcome, isA<HotkeyBound>());
      expect(
        registrar.calls,
        ['grab(HotkeyGrab(alt 0x0007002c))'],
        reason:
            'config is hand-edited, so a differently-cased or padded spelling '
            'must resolve to the one usage the catalogue holds for that key',
      );
    });

    test('CAP-12: two overlapping binds are serialized, so exactly one grab '
        'is live and the last request wins', () async {
      // Unserialized, two binds interleave across the await on the grab, and
      // the adapter's own record of what is in effect then reflects whichever
      // grab finished last rather than whichever was issued last — so a later
      // refused rebind would report a combination the user never ended up with.
      // Reachable from SettingsController.changeHotkey, which has no in-flight
      // guard of its own.
      final hotkey = build();

      final outcomes = await Future.wait([
        hotkey.bind(_ctrlShiftG),
        hotkey.bind(_altQ),
      ]);

      expect(registrar.calls, [
        'grab(HotkeyGrab(control+shift 0x0007000a))',
        'grab(HotkeyGrab(alt 0x00070014))',
      ]);
      expect(
        outcomes.map(
          (outcome) => (outcome as HotkeyBound).registration.effective,
        ),
        [_ctrlShiftG, _altQ],
        reason: 'each caller is told what its own request resolved to',
      );

      // And the adapter's own record agrees, which is what the next rebind
      // reports if its grab is refused (A6).
      registrar
        ..calls.clear()
        ..grabError = StateError('another application owns that');
      final abandoned = await hotkey.bind(_ctrlShiftG);

      expect(
        (abandoned as HotkeyBound).registration.effective,
        _altQ,
        reason: 'the last grab issued is the one that is actually in effect',
      );
    });

    test('AD-4: a dispose that lands while a bind is parked on the grab '
        'releases what arrives and reports no binding', () async {
      // A stop signal during a settings rebind: dispose() is deliberately not
      // queued behind bind(), because a daemon that must exit cannot wait on a
      // channel. Without the post-await recheck the grab lands on a torn-down
      // adapter and bind() reports HotkeyBound for a registration nothing will
      // ever release.
      final grabReached = Completer<void>();
      final letGrabFinish = Completer<void>();
      registrar.onGrab = () {
        if (!grabReached.isCompleted) {
          grabReached.complete();
        }
        return letGrabFinish.future;
      };
      final hotkey = build();

      final pending = hotkey.bind(_ctrlShiftG);
      await grabReached.future;
      await hotkey.dispose();
      letGrabFinish.complete();
      final outcome = await pending;

      expect(
        outcome,
        isA<HotkeyUnavailable>(),
        reason: 'nothing above this adapter could act on a bound hotkey now',
      );
      expect(
        registrar.calls,
        [
          'grab(HotkeyGrab(control+shift 0x0007000a))',
          'release()',
          'dispose()',
          'release()',
        ],
        reason:
            'the teardown released and disposed while the grab was parked, so '
            'it found nothing to let go of; the last release is the bind '
            'undoing the grab that landed behind it, which keeps this seam and '
            'the server from disagreeing about what is registered. The bind '
            'itself issues no release — that is the ordering change, and the '
            'three teardown entries after the grab are unchanged by it',
      );
    });

    test('AD-4: the same race against a seam that *rejects* the late grab is '
        'reported as the shutdown it is, not as a refusal by the session', () async {
      // Which branch this race actually takes depends on the seam, and the
      // shipped one rejects: `X11KeyGrabRegistrar.grab` notices the disposal
      // after the grab lands, undoes the registration itself, and throws. That
      // behaviour was deliberately preserved when the seam moved off
      // `hotkey_manager` onto a private X11 connection, precisely so this row
      // keeps describing production. So the row above — where the fake resolves quietly — exercises
      // the adapter's post-await recheck, and this one exercises what production
      // does. Both must say the backend was shut down. Reporting "this session
      // refused the global shortcut" would send the user to inspect their
      // compositor for something the daemon did to itself, and would log an
      // error for an ordinary stop signal.
      final grabReached = Completer<void>();
      final letGrabFinish = Completer<void>();
      registrar.onGrab = () {
        if (!grabReached.isCompleted) {
          grabReached.complete();
        }
        return letGrabFinish.future;
      };
      final hotkey = build();

      final pending = hotkey.bind(_ctrlShiftG);
      await grabReached.future;
      await hotkey.dispose();
      // Armed only now, so it applies to the parked grab as it finishes — the
      // fake deliberately does not refuse after dispose on its own, and making
      // it do so globally would let the adapter's own guards pass unpinned.
      registrar.grabError = StateError('the registrar was disposed');
      letGrabFinish.complete();
      final outcome = await pending;

      expect(
        (outcome as HotkeyUnavailable).message,
        contains('already been shut down'),
        reason: 'the accurate message existed but nothing could reach it',
      );
      expect(outcome.message, isNot(contains('session refused')));
      expect(
        errors(),
        isEmpty,
        reason:
            'a stop signal overlapping a rebind is not a backend failure, and '
            'the seam already undid its own registration',
      );
      expect(
        registrar.calls,
        [
          'grab(HotkeyGrab(control+shift 0x0007000a))',
          'release()',
          'dispose()',
        ],
        reason:
            'exactly one release fewer than the resolving row above: this '
            'branch issues no compensating release, because the shipped seam '
            'has already undone the registration and refuses a release once '
            'disposed — attempting one would log a teardown failure that did '
            'not happen',
      );
    });

    test('AD-12: bind after dispose is a value and reaches the seam zero '
        'times', () async {
      final hotkey = build();
      await hotkey.dispose();
      registrar.calls.clear();

      final outcome = await hotkey.bind(_ctrlShiftG);

      expect(outcome, isA<HotkeyUnavailable>());
      expect(registrar.calls, isEmpty);
    });
  });

  group('backend-initiated changes (AD-9, AD-10)', () {
    test('C4 AD-9: bindingChanges is an empty stream that closes — nothing '
        'outside this app changes a keybinder grab', () async {
      // Not an unimplemented member but a measured absence. The port's member
      // exists for the Wayland portal, where the compositor owns the binding and
      // can rebind or drop it behind the app's back; an X11 passive grab is only
      // ever changed by `bind()`, whose return value is already the whole
      // report. A closed stream says exactly that to a consumer.
      final hotkey = build();
      final changes = <HotkeyBindOutcome>[];
      var done = false;
      hotkey.bindingChanges.listen(changes.add, onDone: () => done = true);

      await hotkey.bind(_ctrlShiftG);
      await hotkey.bind(_altQ);
      registrar.emitPress();
      await pumpEventQueue();

      expect(changes, isEmpty);
      expect(
        done,
        isTrue,
        reason:
            'a stream that stays open would have a consumer waiting for an '
            'event this backend can never produce',
      );
    });

    test('C4 AD-4: the stream is still closed after dispose, and subscribing '
        'then never throws', () async {
      final hotkey = build();
      await hotkey.dispose();

      final changes = <HotkeyBindOutcome>[];
      var done = false;
      hotkey.bindingChanges.listen(changes.add, onDone: () => done = true);
      await pumpEventQueue();

      expect(changes, isEmpty);
      expect(done, isTrue);
    });
  });

  group('activations (CAP-1, AD-8)', () {
    test('CAP-1: a press reaches every listener exactly once', () async {
      final hotkey = build();
      final first = <void>[];
      final second = <void>[];
      // Two listeners: a single-subscription stream would throw on the second,
      // and PanelController is not promised to be the only consumer.
      hotkey.activations.listen(first.add);
      hotkey.activations.listen(second.add);
      await hotkey.bind(_ctrlShiftG);

      registrar.emitPress();
      await pumpEventQueue();

      expect(first, hasLength(1));
      expect(second, hasLength(1));
    });

    test('AD-4: a press after dispose reaches nobody and the stream is '
        'closed', () async {
      final hotkey = build();
      final fired = <void>[];
      var done = false;
      hotkey.activations.listen(fired.add, onDone: () => done = true);
      await hotkey.bind(_ctrlShiftG);
      await hotkey.dispose();

      registrar.emitPress();
      await pumpEventQueue();

      expect(fired, isEmpty);
      expect(done, isTrue);
    });

    test('AD-4: a press delivered mid-teardown is stopped by the adapter, not '
        'by a closed controller', () async {
      // The row above cannot say this, and by the spec's own rule that makes
      // the guard unpinned: after `dispose()` the fake's own stream is closed,
      // so `emitPress()` is a no-op and the adapter's `_disposed` check is
      // never reached. Here the cancel is refused — so the subscription stays
      // live, exactly as `CancelFailingStream` documents — and the press is
      // emitted from inside the teardown's release step, which runs after the
      // cancel and before the seam's stream is closed. The adapter's own guard
      // is the only thing left that can stop it.
      final hotkey = X11GlobalHotkey(registrar: registrar, logger: logger);
      final fired = <void>[];
      hotkey.activations.listen(fired.add);
      await hotkey.bind(_ctrlShiftG);
      // Armed only now, so the bind's own release does not fire it — that one
      // runs on a live adapter and would be delivered, correctly.
      registrar
        ..cancelError = StateError('the subscription is wedged')
        ..onRelease = () => registrar.emitPress();

      await hotkey.dispose();
      await pumpEventQueue();

      expect(
        fired,
        isEmpty,
        reason:
            'a torn-down adapter that still emitted would reach '
            'PanelController.onHotkeyActivated and move a disposed window',
      );
    });

    test('AD-15: an error on the press stream is logged by type and the next '
        'press still reaches the panel (CAP-1)', () async {
      final hotkey = build();
      final fired = <void>[];
      hotkey.activations.listen(fired.add);
      await hotkey.bind(_ctrlShiftG);

      registrar.emitPressError(StateError('the event channel hiccuped'));
      await pumpEventQueue();
      registrar.emitPress();
      await pumpEventQueue();

      expect(
        fired,
        hasLength(1),
        reason:
            'this is the only route from a key press to the panel; an error '
            'that ended the subscription would retire CAP-1 for the session',
      );
      expect(errors(), hasLength(1));
      expect(errors().single.context, {'error_type': 'StateError'});
    });
  });

  group('teardown (AD-4)', () {
    test('AD-4: dispose releases the grab, disposes the seam, closes the '
        'stream, and is safe to call twice', () async {
      final hotkey = X11GlobalHotkey(registrar: registrar, logger: logger);
      var done = false;
      hotkey.activations.listen(null, onDone: () => done = true);
      await hotkey.bind(_ctrlShiftG);
      registrar.calls.clear();

      await hotkey.dispose();
      await pumpEventQueue();

      expect(registrar.calls, ['release()', 'dispose()']);
      expect(registrar.disposed, isTrue);
      expect(done, isTrue, reason: 'shutdown must not leave a live stream');
      await expectLater(hotkey.dispose(), completes);
      expect(errors(), isEmpty);
    });

    test('AD-4: every later step still runs when the first ones fail, and '
        'nothing throws out of dispose', () async {
      registrar
        ..cancelError = StateError('the subscription is wedged')
        ..releaseError = StateError('the channel is gone')
        ..disposeError = StateError('and so is the seam');
      final hotkey = X11GlobalHotkey(registrar: registrar, logger: logger);
      var done = false;
      hotkey.activations.listen(null, onDone: () => done = true);

      await expectLater(hotkey.dispose(), completes);
      await pumpEventQueue();

      expect(
        registrar.calls,
        ['release()', 'dispose()'],
        reason: 'a failed cancel must not stop the release or the seam close',
      );
      expect(done, isTrue);
      expect(errors(), hasLength(3));
      expect(
        [for (final line in errors()) line.context],
        everyElement({'error_type': 'StateError'}),
        reason: 'the type only, on every one of them',
      );
    });
  });

  group('the logger is the thing that broke (AD-15)', () {
    test('AD-15: every failing path completes and emits no unhandled zone '
        'error when the logger itself throws', () async {
      final broken = ThrowingLogger();
      final errorsInZone = <Object>[];
      await runZonedGuarded(() async {
        registrar.grabError = StateError('the channel is gone');
        final hotkey = X11GlobalHotkey(registrar: registrar, logger: broken);
        expect(await hotkey.bind(_ctrlShiftG), isA<HotkeyUnavailable>());

        // The other side of the same refusal, and the reason this sub-case
        // stayed after the refused-release path it used to drive went away: an
        // abandoned rebind logs *and* returns a success value, so a logger that
        // throws there would take down a bind that otherwise worked.
        registrar.grabError = null;
        expect(await hotkey.bind(_altQ), isA<HotkeyBound>());
        registrar.grabError = StateError('still gone');
        expect(
          ((await hotkey.bind(_ctrlShiftG)) as HotkeyBound)
              .registration
              .effective,
          _altQ,
        );

        hotkey.activations.listen(null);
        registrar.emitPressError(StateError('the event channel hiccuped'));
        await pumpEventQueue();

        registrar
          ..cancelError = StateError('wedged')
          ..disposeError = StateError('and the seam');
        await expectLater(hotkey.dispose(), completes);
      }, (error, stack) => errorsInZone.add(error));
      await pumpEventQueue();

      expect(errorsInZone, isEmpty);
      expect(
        broken.attempts,
        isNotEmpty,
        reason: 'the guards must still have tried to report',
      );
    });
  });
}

final HotkeyBinding _ctrlShiftG = HotkeyBinding(
  modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
  key: 'G',
);

/// A second, different combination for the rebind rows.
///
/// It used to be Alt+Q *because* it could not be Alt+Space: `Space` was one of
/// the seven labels the removed vendor chain bound to the wrong keyval
/// (KP_Space), so `bind()` refused it before the seam was touched. That is no
/// longer true — the row above binds Alt+Space like any other combination — and
/// Alt+Q stays only because the rows that use it are written against it.
final HotkeyBinding _altQ = HotkeyBinding(
  modifiers: {HotkeyModifier.alt},
  key: 'Q',
);

/// A third combination, for the row that asserts the adapter recovers after a
/// rebind its own backend death cleared.
///
/// Third rather than a retry of either of the two above: a recovery row that
/// re-asked for a combination the adapter had already seen could pass against
/// an implementation that answered from a stale record instead of from a grab
/// it actually made.
final HotkeyBinding _ctrlAltM = HotkeyBinding(
  modifiers: {HotkeyModifier.control, HotkeyModifier.alt},
  key: 'M',
);
