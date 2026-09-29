import 'package:hotkey_grammar_corrector/src/domain/collection_equality.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_record.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_status.dart';
import 'package:hotkey_grammar_corrector/src/domain/tray/hotkey_tray_status.dart';
import 'package:test/test.dart';

import '../support/value_equality.dart';

/// Value equality across the domain ring: two values built separately from the
/// same data are the same value, and `hashCode` agrees with `==` for every
/// type given one. Without that, no consumer can dedupe — Riverpod's `select`
/// and `Stream.distinct` both fall back to identity — and every `Set` or `Map`
/// keyed by one of these silently misbehaves.
///
/// **Every positive row here goes through [expectSameValue], and nothing in
/// this file is built with `const`.** Both rules exist for one reason: Dart
/// canonicalises identical constant expressions to a single instance, so
/// `expect(const X(1), const X(1))` compares an object with itself and passes
/// with no `operator==` declared at all. An earlier revision of this file was
/// written that way, and neutering `Suggestion`, `HotkeyRegistration`,
/// `HotkeyBound`, `HotkeyUnavailable` and `CorrectionFailed` to identity
/// equality left the whole suite green. The nested values in [_record] and
/// [_config] are rebuilt per call for the same reason: a shared constant
/// element makes a list or map comparison pass without ever consulting the
/// element's own `==`.
///
/// Pure Dart: no Flutter binding (AGENTS.md §7).
void main() {
  test('HOTKEY-06: the current status includes the compositor wording in '
      'value equality', () {
    HotkeyStatus status(String? wording) => HotkeyStatus(
      outcome: HotkeyBound(
        HotkeyRegistration(
          effective: null,
          authority: BindingAuthority.compositor,
        ),
      ),
      backendDescription: wording,
    );

    expectSameValue(status('Super+Space'), status('Super+Space'));
    expect(status('Super+Space'), isNot(status('Ctrl+Shift+G')));
    expect(status(null), isNot(status('Super+Space')));
    expect(status(null), isNot('not a status'));
  });

  test('CAP-12: tray status distinguishes an active shortcut, a retained '
      'shortcut, and an unavailable one', () {
    HotkeyTrayStatus status(bool refused) => HotkeyTrayStatus(
      outcome: HotkeyBound(
        HotkeyRegistration(
          effective: null,
          authority: BindingAuthority.compositor,
        ),
      ),
      rebindRefused: refused,
    );

    expectSameValue(status(false), status(false));
    expect(status(false), isNot(status(true)));
    expect(status(false), isNot('not a status'));
    expect(status(false).unavailable, isFalse);
    expect(
      HotkeyTrayStatus(
        outcome: HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: 'portal unavailable',
        ),
        rebindRefused: false,
      ).unavailable,
      isTrue,
    );
  });

  group('collection equality helpers (AD-1: domain owns them)', () {
    test('AD-1: lists compare in order and hash in order', () {
      expect(listEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(listEquals([1, 2, 3], [3, 2, 1]), isFalse);
      expect(listEquals([1, 2], [1, 2, 3]), isFalse);
      expect(listHash([1, 2, 3]), listHash([1, 2, 3]));
    });

    test('AD-1: sets compare and hash without regard to order', () {
      expect(setEquals({1, 2}, {2, 1}), isTrue);
      expect(setEquals({1, 2}, {1, 3}), isFalse);
      expect(setHash({1, 2}), setHash({2, 1}));
    });

    test('AD-1: maps compare by key and value, and a null value is not the '
        'same as an absent key', () {
      expect(mapEquals({'a': 1, 'b': 2}, {'b': 2, 'a': 1}), isTrue);
      expect(mapEquals({'a': 1}, {'a': 2}), isFalse);
      expect(mapEquals<String, int?>({'a': null}, {'b': null}), isFalse);
      expect(mapHash({'a': 1, 'b': 2}), mapHash({'b': 2, 'a': 1}));
    });

    test('AD-1: a map hash keeps a swapped key/value pair distinct', () {
      expect(mapHash({'a': 'b'}), isNot(mapHash({'b': 'a'})));
    });
  });

  group('HotkeyBinding (AD-9)', () {
    test('CAP-12: two bindings whose modifier sets differ only in order are '
        'the same combination, and HOTKEY-09: they stay so after the caller '
        'mutates the set it passed in', () {
      // The sets are named locals the caller still holds, not literals passed
      // inline: the mutation below is the whole point of the defensive copy,
      // and a set literal handed straight to the constructor is a reference
      // nobody kept.
      final passedToFirst = {HotkeyModifier.control, HotkeyModifier.shift};
      final passedToSecond = {HotkeyModifier.shift, HotkeyModifier.control};
      final first = HotkeyBinding(modifiers: passedToFirst, key: 'G');
      final second = HotkeyBinding(modifiers: passedToSecond, key: 'G');

      expectSameValue(first, second);
      // The hash has to agree, or a Set keyed by a binding holds both.
      expect({first, second}, hasLength(1));

      // HOTKEY-09: the constructor copied, so a caller that still owns its set
      // cannot change what an already-recorded binding compares equal to. Held
      // by reference, `first` would now carry `alt` too and `second` nothing,
      // and the two would stop comparing equal — with no error anywhere,
      // because the only symptom is a state that compares equal and so
      // suppresses the rebuild that would have shown the change.
      passedToFirst.add(HotkeyModifier.alt);
      passedToSecond.clear();

      expectSameValue(first, second);
      expect({first, second}, hasLength(1));
      expect(
        first.modifiers,
        unorderedEquals({HotkeyModifier.control, HotkeyModifier.shift}),
        reason: 'the binding kept the combination it was constructed with',
      );
      expect(
        () => first.modifiers.add(HotkeyModifier.meta),
        throwsUnsupportedError,
        reason:
            'the set the binding exposes is unmodifiable, so a consumer '
            'reaching into it cannot mutate the value either',
      );
    });

    test('CAP-12: a different key, or a different modifier set, is a '
        'different binding', () {
      final binding = HotkeyBinding(
        modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
        key: 'G',
      );

      expect(
        binding,
        isNot(
          HotkeyBinding(
            modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
            key: 'H',
          ),
        ),
      );
      expect(
        binding,
        isNot(
          HotkeyBinding(
            modifiers: {HotkeyModifier.control, HotkeyModifier.alt},
            key: 'G',
          ),
        ),
      );
      expect(
        binding,
        isNot(HotkeyBinding(modifiers: {}, key: 'G')),
        reason: 'a subset is not the same combination',
      );
    });
  });

  group('HotkeyRegistration and HotkeyBindOutcome (AD-9, AD-10, AD-12)', () {
    test('AD-10: registrations compare by effective binding and authority', () {
      expectSameValue(
        HotkeyRegistration(
          effective: HotkeyBinding(modifiers: {HotkeyModifier.alt}, key: 'Sp'),
          authority: BindingAuthority.compositor,
        ),
        HotkeyRegistration(
          effective: HotkeyBinding(modifiers: {HotkeyModifier.alt}, key: 'Sp'),
          authority: BindingAuthority.compositor,
        ),
      );
      expect(
        HotkeyRegistration(
          effective: HotkeyBinding(modifiers: {HotkeyModifier.alt}, key: 'Sp'),
          authority: BindingAuthority.compositor,
        ),
        isNot(
          HotkeyRegistration(
            effective: HotkeyBinding(
              modifiers: {HotkeyModifier.alt},
              key: 'Sp',
            ),
            authority: BindingAuthority.application,
          ),
        ),
      );
      expect(
        HotkeyRegistration(
          effective: null,
          authority: BindingAuthority.compositor,
        ),
        isNot(
          HotkeyRegistration(
            effective: HotkeyBinding(
              modifiers: {HotkeyModifier.alt},
              key: 'Sp',
            ),
            authority: BindingAuthority.compositor,
          ),
        ),
      );
    });

    test('AD-12: bound and unavailable outcomes compare by value and never '
        'to each other', () {
      HotkeyRegistration registration() => HotkeyRegistration(
        effective: null,
        authority: BindingAuthority.application,
      );

      expectSameValue(HotkeyBound(registration()), HotkeyBound(registration()));
      expectSameValue(
        HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: 'no portal',
        ),
        HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: 'no portal',
        ),
      );
      expect(
        HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: 'no portal',
        ),
        isNot(
          HotkeyUnavailable(
            cause: HotkeyUnavailableCause.noBackend,
            message: 'no grabs',
          ),
        ),
      );
      // HOTKEY-08: the cause participates in equality on its own. Two outcomes
      // with identical prose say different things to the user — "nothing you
      // try will help" against "your shortcut was taken away" — and
      // `SettingsState` contains this transitively, so a pair that compared
      // equal here would suppress the rebuild that changes what the screen
      // says.
      expect(
        HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: 'no portal',
        ),
        isNot(
          HotkeyUnavailable(
            cause: HotkeyUnavailableCause.revoked,
            message: 'no portal',
          ),
        ),
      );
      expect(
        HotkeyUnavailable(
          cause: HotkeyUnavailableCause.keyRefused,
          message: 'no portal',
        ).hashCode,
        isNot(
          HotkeyUnavailable(
            cause: HotkeyUnavailableCause.revoked,
            message: 'no portal',
          ).hashCode,
        ),
      );
      expect(
        HotkeyBound(registration()),
        isNot(
          HotkeyUnavailable(
            cause: HotkeyUnavailableCause.noBackend,
            message: 'no portal',
          ),
        ),
      );
    });
  });

  group('Preset, Suggestion and CorrectionFailed (AD-2)', () {
    test('AD-5: presets compare across all four fields, prompt included', () {
      expectSameValue(_preset(), _preset());
      expect(
        _preset(),
        isNot(_preset(systemPrompt: 'a different prompt')),
        reason:
            'AD-5 binds the prompt to the model; a changed prompt is a '
            'changed preset',
      );
      expect(_preset(), isNot(_preset(id: 'preset-b')));
      expect(_preset(), isNot(_preset(providerId: 'other-provider')));
      expect(_preset(), isNot(_preset(model: 'claude-haiku-5')));
    });

    test('CAP-4: suggestions compare by register and text', () {
      Suggestion formal() =>
          Suggestion(register: SuggestionRegister.formal, text: 'Good day.');

      expectSameValue(formal(), formal());
      expect(
        formal(),
        isNot(Suggestion(register: SuggestionRegister.casual, text: 'Good d.')),
      );
      expect(
        formal(),
        isNot(Suggestion(register: SuggestionRegister.formal, text: 'Hi.')),
      );
    });

    test('CAP-13: failures compare by kind and message', () {
      CorrectionFailed failure() => CorrectionFailed(
        kind: CorrectionFailureKind.providerUnavailable,
        message: 'no provider',
      );

      expectSameValue(failure(), failure());
      expect(
        failure(),
        isNot(
          CorrectionFailed(
            kind: CorrectionFailureKind.providerError,
            message: 'no provider',
          ),
        ),
      );
      expect(
        failure(),
        isNot(
          CorrectionFailed(
            kind: CorrectionFailureKind.providerUnavailable,
            message: 'a different sentence',
          ),
        ),
      );
    });
  });

  group('CorrectionRecord (AD-7)', () {
    test('CAP-7: two records built separately from one correction are the '
        'same record, suggestions included', () {
      expectSameValue(_record(), _record());
    });

    test('CAP-7: a differing nested suggestion makes the records differ', () {
      expect(
        _record(),
        isNot(
          _record(
            suggestions: [
              Suggestion(register: SuggestionRegister.formal, text: 'other'),
              Suggestion(register: SuggestionRegister.casual, text: 'casual'),
              Suggestion(register: SuggestionRegister.shorter, text: 'short'),
            ],
          ),
        ),
      );
    });

    test('AD-6: reordered suggestions are a different record, because the '
        'order is the 1/2/3 key mapping', () {
      expect(
        _record(),
        isNot(_record(suggestions: _suggestions().reversed.toList())),
      );
    });

    test('CAP-7: a differing provenance field makes the records differ', () {
      expect(_record(), isNot(_record(model: 'claude-haiku-5')));
      expect(_record(), isNot(_record(latencyMs: 999)));
      expect(_record(), isNot(_record(inputText: 'something else')));
    });
  });

  group('ProviderConfig and AppConfig (AD-13, AD-15)', () {
    test('CAP-8: provider configs compare their settings as maps', () {
      expectSameValue(
        ProviderConfig(settings: {'a': '1', 'b': '2'}),
        ProviderConfig(settings: {'b': '2', 'a': '1'}),
      );
      expect(
        ProviderConfig(settings: {'a': '1'}),
        isNot(ProviderConfig(settings: {'a': '2'})),
      );
    });

    test(
      'CAP-8: two separately built configs with equal contents are equal',
      () {
        expectSameValue(_config(), _config());
        expect({_config(), _config()}, hasLength(1));
      },
    );

    test(
      'CAP-8: one differing field — nested or not — makes configs differ',
      () {
        expect(_config(), isNot(_config(activePresetId: 'preset-b')));
        expect(
          _config(),
          isNot(
            _config(
              hotkeyBinding: HotkeyBinding(
                modifiers: {HotkeyModifier.meta},
                key: 'G',
              ),
            ),
          ),
        );
        expect(
          _config(),
          isNot(
            _config(
              providers: {
                'claude-agent-sdk': ProviderConfig(
                  settings: {'interpreter': '/usr/bin/python3.12'},
                ),
              },
            ),
          ),
          reason: 'a nested ProviderConfig setting is part of the value',
        );
        expect(
          _config(),
          isNot(
            _config(presets: [_preset(systemPrompt: 'a different prompt')]),
          ),
          reason: 'a nested Preset is part of the value',
        );
      },
    );

    test('AD-19: AppConfig carries no interpreter or sidecar path to compare '
        '— copyWith names exactly the four fields that exist', () {
      final copied = _config().copyWith(activePresetId: 'preset-a');

      expectSameValue(copied, _config());
    });
  });
}

Preset _preset({
  String id = 'preset-a',
  String providerId = 'claude-agent-sdk',
  String model = 'claude-sonnet-5',
  String systemPrompt = 'correct this',
}) {
  return Preset(
    id: id,
    providerId: providerId,
    model: model,
    systemPrompt: systemPrompt,
  );
}

List<Suggestion> _suggestions() => [
  Suggestion(register: SuggestionRegister.formal, text: 'formal'),
  Suggestion(register: SuggestionRegister.casual, text: 'casual'),
  Suggestion(register: SuggestionRegister.shorter, text: 'short'),
];

CorrectionRecord _record({
  String inputText = 'i has a text',
  String model = 'claude-sonnet-5',
  int latencyMs = 1200,
  List<Suggestion>? suggestions,
}) {
  return CorrectionRecord(
    createdAtMillis: 1700000000000,
    inputText: inputText,
    presetId: 'preset-a',
    providerId: 'claude-agent-sdk',
    model: model,
    latencyMs: latencyMs,
    outcome: CorrectionOutcome.completed,
    suggestions: suggestions ?? _suggestions(),
  );
}

AppConfig _config({
  Map<String, ProviderConfig>? providers,
  List<Preset>? presets,
  String activePresetId = 'preset-a',
  HotkeyBinding? hotkeyBinding,
}) {
  return AppConfig(
    providers:
        providers ??
        {
          'claude-agent-sdk': ProviderConfig(
            settings: {'interpreter': 'python3', 'sidecar': 'sidecar.py'},
          ),
        },
    presets: presets ?? [_preset()],
    activePresetId: activePresetId,
    hotkeyBinding:
        hotkeyBinding ??
        HotkeyBinding(
          modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
          key: 'G',
        ),
  );
}
