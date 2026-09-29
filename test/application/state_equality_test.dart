import 'package:hotkey_grammar_corrector/src/application/correction_state.dart';
import 'package:hotkey_grammar_corrector/src/application/settings_state.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:test/test.dart';

import '../support/value_equality.dart';

/// The two application states compare by value, so a consumer can dedupe.
///
/// `CorrectionState` is re-emitted per keystroke and per streamed delta and
/// `SettingsState` on every external config write; with identity equality
/// every one of those is a distinct event and nothing downstream can collapse
/// them. Pure Dart: no Flutter binding (AGENTS.md §7).
///
/// Every positive row goes through [expectSameValue] and nothing here is built
/// with `const` — see that helper for why a const-declared row asserts nothing.
void main() {
  group('CorrectionState (CAP-3, CAP-5, CAP-13)', () {
    test('CAP-5: two states with equal suggestionTexts maps are equal, even '
        'though each delta rebuilds the map', () {
      final first = _correctionState(
        suggestionTexts: {
          SuggestionRegister.formal: 'Good day.',
          SuggestionRegister.casual: 'Hey.',
        },
      );
      final second = _correctionState(
        suggestionTexts: {
          SuggestionRegister.casual: 'Hey.',
          SuggestionRegister.formal: 'Good day.',
        },
      );

      expectSameValue(first, second);
    });

    test('CAP-3: one differing field makes the states differ', () {
      expect(
        _correctionState(),
        isNot(_correctionState(editorText: 'i has other text')),
      );
      expect(
        _correctionState(),
        isNot(_correctionState(submittedText: 'something else')),
      );
      expect(
        _correctionState(),
        isNot(
          _correctionState(
            suggestionTexts: {SuggestionRegister.formal: 'Good evening.'},
          ),
        ),
      );
    });

    test('CAP-13: two failed states differ when the failure differs', () {
      CorrectionState failed({
        CorrectionFailureKind kind = CorrectionFailureKind.providerUnavailable,
      }) => CorrectionState(
        editorText: 'text',
        status: CorrectionStatus.failed,
        suggestionTexts: {},
        failure: CorrectionFailed(kind: kind, message: 'no provider'),
      );

      expectSameValue(failed(), failed());
      expect(
        failed(),
        isNot(failed(kind: CorrectionFailureKind.providerError)),
        reason: 'the nested CorrectionFailed is part of the state value',
      );
    });

    test('CAP-4: the highlight is part of the state value, so a consumer that '
        'dedupes still sees it change', () {
      expectSameValue(
        _correctionState(selectedRegister: SuggestionRegister.casual),
        _correctionState(selectedRegister: SuggestionRegister.casual),
      );
      expect(
        _correctionState(),
        isNot(_correctionState(selectedRegister: SuggestionRegister.casual)),
      );
      expect(
        _correctionState(selectedRegister: SuggestionRegister.formal),
        isNot(_correctionState(selectedRegister: SuggestionRegister.casual)),
      );
    });

    test('CAP-11: the copy notice is part of the state value too', () {
      expectSameValue(
        _correctionState(copyFailure: 'the copy failed'),
        _correctionState(copyFailure: 'the copy failed'),
      );
      expect(
        _correctionState(),
        isNot(_correctionState(copyFailure: 'the copy failed')),
      );
    });

    test('CAP-3/DW-54: an idle state with a hand-cleared editor is not the '
        'state a session begins with — the marker is part of the value', () {
      // The whole of DW-54 at the state level. `isFreshSession` used to be
      // `this == empty`, so the state a user produced by selecting all and
      // deleting was indistinguishable from the state `_beginSession` emits —
      // and both consumers acted on it: the panel pulled the caret back to the
      // editor, and the daemon's home view returned to the panel view.
      final handCleared = CorrectionState(
        editorText: '',
        status: CorrectionStatus.idle,
        suggestionTexts: {},
      );

      expect(handCleared.isFreshSession, isFalse);
      expect(handCleared, isNot(equals(CorrectionState.freshSession)));
      expect(
        CorrectionState.freshSession.isFreshSession,
        isTrue,
        reason: 'and the one state a session begins with still says so',
      );
    });

    test('CAP-3/DW-54: CorrectionState.empty is not the state a session begins '
        'with either — the initial state and a summon are two facts', () {
      // Not because of anything `initState` does with it: the panel assigns that
      // snapshot to its field and never routes it through the fresh-session
      // branch. The reason is value equality itself. The marker takes part in
      // `==`, so folding these two into one constant would make "this daemon has
      // never shown a panel" compare equal to "a session just began" — DW-54's
      // conflation moved from a getter into a constant. And a holder of that
      // ambiguity already exists: an empty-clipboard session skips its seeding
      // emission, so `controller.state` keeps the marker true for the rest of it.
      expect(CorrectionState.empty.isFreshSession, isFalse);
      expect(
        CorrectionState.empty,
        isNot(equals(CorrectionState.freshSession)),
        reason:
            'the two differ in nothing but the marker, which is exactly why the '
            'marker has to take part in ==',
      );

      // The reason above is a claim about every other field, and `!=` on its own
      // cannot pin it: the two constants are written out by hand, so a field
      // added to one and not the other would leave them differing in something
      // *besides* the marker while the assertion above still passed — true for
      // the wrong reason, and the marker would stop being what tells them apart.
      final empty = CorrectionState.empty;
      final fresh = CorrectionState.freshSession;
      expect(fresh.editorText, equals(empty.editorText));
      expect(fresh.status, equals(empty.status));
      expect(fresh.suggestionTexts, equals(empty.suggestionTexts));
      expect(fresh.submittedText, equals(empty.submittedText));
      expect(fresh.failure, equals(empty.failure));
      expect(fresh.selectedRegister, equals(empty.selectedRegister));
      expect(fresh.copyFailure, equals(empty.copyFailure));
      expect(
        fresh.copyWith(),
        equals(empty),
        reason:
            'the whole of it in one line: strip the marker and the two are the '
            'same value, because copyWith is what drops it',
      );
    });

    test('CAP-2/DW-54: the marker cannot be stamped on a state that is not a '
        'session beginning — the constructor says so, not just the doc', () {
      // `freshSession` is documented as "the only value that carries
      // isFreshSession", and the constructor is public with the marker as an
      // ordinary named parameter. Without this assert that sentence was the
      // whole of the enforcement, and a caller could hand either consumer a
      // completed or failed session wearing the marker — DW-54's conflation
      // through the one door the type claimed was shut.
      expect(
        () => CorrectionState(
          editorText: 'a session already under way',
          status: CorrectionStatus.idle,
          suggestionTexts: const {},
          isFreshSession: true,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => CorrectionState(
          editorText: '',
          status: CorrectionStatus.failed,
          suggestionTexts: const {},
          failure: const CorrectionFailed(
            kind: CorrectionFailureKind.providerUnavailable,
            message: 'the previous session failed',
          ),
          isFreshSession: true,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'a session does not begin holding the previous one\'s error',
      );
      expect(
        CorrectionState.freshSession.isFreshSession,
        isTrue,
        reason: 'and the one shape that is a session beginning still builds',
      );
    });

    test('CAP-2/DW-54: copyWith never carries the session marker — a state '
        'built from a session beginning is not one', () {
      final seeded = CorrectionState.freshSession.copyWith(
        editorText: 'the clipboard seed',
      );

      expect(seeded.isFreshSession, isFalse);
      expect(
        CorrectionState.freshSession.copyWith().isFreshSession,
        isFalse,
        reason:
            'not even a copyWith that changes nothing: the marker belongs to '
            'the emission, not to the shape of the value',
      );
      expect(
        CorrectionState.freshSession.copyWith(),
        isNot(equals(CorrectionState.freshSession)),
        reason:
            'which is only observable because the marker takes part in == — '
            'without that, a copy would keep reading as a summon',
      );
    });

    test('CAP-5: Stream.distinct() collapses two successive equal correction '
        'states into one event', () async {
      final events = await Stream<CorrectionState>.fromIterable([
        _correctionState(),
        _correctionState(),
        _correctionState(editorText: 'typed on'),
        _correctionState(editorText: 'typed on'),
      ]).distinct().toList();

      expect(events, hasLength(2));
    });
  });

  group('SettingsState (CAP-8, CAP-12)', () {
    test('CAP-12: states with equal config, bind outcome and failure are '
        'equal', () {
      expectSameValue(_settingsState(), _settingsState());
    });

    test('CAP-8, HOTKEY-03: a differing config, outcome, backend wording or '
        'failure kind makes the states differ', () {
      expect(
        _settingsState(),
        isNot(_settingsState(config: _config(activePresetId: 'preset-b'))),
      );
      expect(
        _settingsState(),
        isNot(
          _settingsState(
            outcome: HotkeyUnavailable(
              cause: HotkeyUnavailableCause.noBackend,
              message: 'no portal backend',
            ),
          ),
        ),
        reason: 'the nested HotkeyBindOutcome is part of the state value',
      );
      expect(
        _settingsState(),
        isNot(_settingsState(backendDescription: 'Strg+Umschalt+G')),
        reason:
            'the desktop own wording is the only thing on screen about the '
            'shortcut in force on Wayland, so a state carrying new wording '
            'that compared equal to the old one would never be rendered',
      );
      expect(
        _settingsState(),
        isNot(
          _settingsState(
            failure: SettingsFailure(
              kind: SettingsFailureKind.configRejected,
              message: 'refused',
            ),
          ),
        ),
      );
    });

    test('AD-11: the in-flight flag is part of the state value, so the frame '
        'that announces a mutation is not deduped away', () {
      // `Stream.distinct()` and Riverpod's `select` both compare by `==`. Leaving
      // this field out of equality would make the in-flight announcement equal to
      // the state before it whenever nothing else changed — which is exactly the
      // case it exists for — and the surface would never render the pending
      // affordance or disable its controls.
      expect(_settingsState(), isNot(_settingsState(mutationInFlight: true)));
      expectSameValue(
        _settingsState(mutationInFlight: true),
        _settingsState(mutationInFlight: true),
      );
    });

    test('CAP-12: failures compare by kind and message', () {
      SettingsFailure failure({
        SettingsFailureKind kind = SettingsFailureKind.configWriteFailed,
      }) => SettingsFailure(kind: kind, message: 'unwritable');

      expectSameValue(failure(), failure());
      expect(
        failure(),
        isNot(failure(kind: SettingsFailureKind.hotkeyBindFailed)),
      );
    });

    test('CAP-8: Stream.distinct() collapses two successive equal settings '
        'states into one event', () async {
      final events = await Stream<SettingsState>.fromIterable([
        _settingsState(),
        _settingsState(),
        _settingsState(config: _config(activePresetId: 'preset-b')),
      ]).distinct().toList();

      expect(events, hasLength(2));
    });
  });
}

// Every nested value below is rebuilt per call rather than shared as a
// constant: a list, map or field that both sides hold the *same* instance of
// compares equal without the element's own `==` ever being consulted, which is
// exactly how an equality suite stops testing equality.

CorrectionState _correctionState({
  String editorText = 'i has a text',
  String? submittedText = 'i has a text',
  Map<SuggestionRegister, String>? suggestionTexts,
  SuggestionRegister? selectedRegister,
  String? copyFailure,
}) {
  return CorrectionState(
    editorText: editorText,
    status: CorrectionStatus.running,
    suggestionTexts:
        suggestionTexts ?? {SuggestionRegister.formal: 'Good day.'},
    submittedText: submittedText,
    selectedRegister: selectedRegister,
    copyFailure: copyFailure,
  );
}

SettingsState _settingsState({
  AppConfig? config,
  HotkeyBindOutcome? outcome,
  String? backendDescription,
  SettingsFailure? failure,
  bool mutationInFlight = false,
}) {
  return SettingsState(
    config: config ?? _config(),
    hotkeyBindOutcome:
        outcome ??
        HotkeyBound(
          HotkeyRegistration(
            effective: _binding(),
            authority: BindingAuthority.application,
          ),
        ),
    hotkeyBackendDescription: backendDescription,
    failure: failure,
    mutationInFlight: mutationInFlight,
  );
}

HotkeyBinding _binding() => HotkeyBinding(
  modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
  key: 'G',
);

AppConfig _config({String activePresetId = 'preset-a'}) {
  return AppConfig(
    providers: {
      'claude-agent-sdk': ProviderConfig(settings: {'interpreter': 'python3'}),
    },
    presets: [
      Preset(
        id: 'preset-a',
        providerId: 'claude-agent-sdk',
        model: 'claude-sonnet-5',
        systemPrompt: 'correct this',
      ),
      Preset(
        id: 'preset-b',
        providerId: 'claude-agent-sdk',
        model: 'claude-haiku-5',
        systemPrompt: 'correct this fast',
      ),
    ],
    activePresetId: activePresetId,
    hotkeyBinding: _binding(),
  );
}
