import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/ui/settings/hotkey_capture_field.dart';
import 'package:hotkey_grammar_corrector/src/ui/settings/settings_failure_notice.dart';
import 'package:hotkey_grammar_corrector/src/ui/settings/settings_pending_notice.dart';
import 'package:hotkey_grammar_corrector/src/ui/settings/settings_screen.dart';

import '../../fakes/throwing_logger.dart';
import '../settings_harness.dart';

/// The config half of the surface: the preset choice, what a refused or lost
/// write says, and what the screen does while a mutation is in flight (CAP-8,
/// CAP-12, AD-5, AD-13).
///
/// Every mutation here goes through `SettingsController`, which is the only path
/// to the config file (AD-13) — so what these rows check is what the *screen*
/// adds: that a preset is what is chosen and never a provider, that a failure is
/// rendered where a user will find it, and that the store's `current` is what is
/// shown when a write did not land.
void main() {
  late SettingsHarness harness;

  setUp(() => harness = SettingsHarness());
  // Whatever `harness` points at now — [replaceHarness] keeps that to exactly
  // one live instance, so the one this disposes is the only one there is.
  tearDown(() => harness.dispose());

  /// Swaps in a harness built differently — a throwing logger, say — closing the
  /// one `setUp` made first.
  ///
  /// The row that needed this used to build its own and leave `setUp`'s
  /// undisposed: its `FakeConfigStore`'s stream controller stayed open for the
  /// life of the suite, and `tearDown` only ever saw the replacement. One live
  /// harness at a time, and every one of them closed.
  SettingsHarness replaceHarness(SettingsHarness replacement) {
    harness.dispose();
    return harness = replacement;
  }

  final applyButton = find.widgetWithText(ElevatedButton, 'Apply');
  final presetOption = find.widgetWithText(
    ListTile,
    SettingsHarness.fastPreset.id,
  );

  Finder optionFor(String presetId) => find.widgetWithText(ListTile, presetId);

  const compatiblePreset = Preset(
    id: 'compatible-preset',
    providerId: ProviderConfig.compatibleProviderId,
    model: 'committed-model',
    systemPrompt: 'correct the text',
  );

  final baseUrlField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.labelText == 'Base URL',
  );
  final modelField = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == 'Model',
  );

  void useCompatiblePreset() {
    harness.configStore.current = SettingsHarness.defaultConfig.copyWith(
      providers: {
        ...SettingsHarness.defaultConfig.providers,
        ProviderConfig.compatibleProviderId: const ProviderConfig(
          settings: {ProviderConfig.baseUrlSetting: 'https://old.example/v1'},
        ),
      },
      presets: [...SettingsHarness.defaultConfig.presets, compatiblePreset],
      activePresetId: compatiblePreset.id,
    );
  }

  testWidgets('CAP-8: a plaintext config key source is disclosed and the '
      'warning clears when the source moves to the keyring', (tester) async {
    useCompatiblePreset();
    var source = 'Config file';
    harness.settings.attachApiKeySourceLabel((_) async => source);
    await harness.pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('API key source: Config file'), findsOneWidget);
    expect(find.textContaining('stored as plaintext'), findsOneWidget);

    source = 'System keyring';
    await harness.configStore.write(
      harness.configStore.current.copyWith(
        providers: {
          ...harness.configStore.current.providers,
          ProviderConfig.compatibleProviderId: const ProviderConfig(
            settings: {ProviderConfig.baseUrlSetting: 'https://new.example/v1'},
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('API key source: System keyring'), findsOneWidget);
    expect(find.textContaining('stored as plaintext'), findsNothing);
  });

  testWidgets('CAP-8: an older key source lookup cannot replace the label '
      'for a newer config edit', (tester) async {
    useCompatiblePreset();
    final labels = <Completer<String>>[];
    harness.settings.attachApiKeySourceLabel((_) {
      final lookup = Completer<String>();
      labels.add(lookup);
      return lookup.future;
    });
    await harness.pumpSettings(tester);
    expect(labels, hasLength(1));

    await harness.configStore.write(
      harness.configStore.current.copyWith(
        providers: {
          ...harness.configStore.current.providers,
          ProviderConfig.compatibleProviderId: const ProviderConfig(
            settings: {
              ProviderConfig.baseUrlSetting: 'https://latest.example/v1',
            },
          ),
        },
      ),
    );
    await tester.pump();
    expect(labels, hasLength(2));

    labels.last.complete('System keyring');
    await tester.pump();
    labels.first.complete('Config file');
    await tester.pump();

    expect(find.text('API key source: System keyring'), findsOneWidget);
    expect(find.textContaining('stored as plaintext'), findsNothing);
  });

  testWidgets('CAP-8: a key source lookup resolving after settings unmount '
      'does not set widget state', (tester) async {
    useCompatiblePreset();
    final label = Completer<String>();
    harness.settings.attachApiKeySourceLabel((_) => label.future);
    await harness.pumpSettings(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    label.complete('System keyring');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('CAP-13: a mounted settings screen survives its state stream '
      'closing even when logging fails', (tester) async {
    final logger = ThrowingLogger();
    replaceHarness(SettingsHarness(installedLogger: logger));
    await harness.pumpSettings(tester);

    unawaited(harness.settings.dispose());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(logger.attempts, contains('error'));
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// Scrolls the option into view, then taps it.
  ///
  /// The scroll is not ceremony: the notices sit above the scroll view, so a
  /// failure on screen pushes the preset list down, and on the default surface an
  /// option could end up below the fold — where a tap dispatches a pointer that
  /// hits nothing and the row goes on to assert against a mutation that never
  /// happened.
  Future<void> pick(WidgetTester tester, String presetId) async {
    await tester.ensureVisible(optionFor(presetId));
    await tester.pumpAndSettle();
    await tester.tap(optionFor(presetId));
    await tester.pumpAndSettle();
  }

  testWidgets('A15 CAP-8, AD-5: picking an option switches the active preset '
      'and never selects a provider', (tester) async {
    await harness.pumpSettings(tester);

    await pick(tester, SettingsHarness.fastPreset.id);

    expect(harness.configStore.writes, hasLength(1));
    expect(
      harness.configStore.writes.single.activePresetId,
      SettingsHarness.fastPreset.id,
    );
    expect(
      harness.configStore.current.activePresetId,
      SettingsHarness.fastPreset.id,
    );
    expect(
      harness.configStore.current.providers.keys,
      isNot(contains(harness.configStore.current.activePresetId)),
      reason:
          'AD-5: a preset carries its providerId and the composition root '
          'resolves the pair — a screen that wrote a provider id here would be '
          'choosing half of an indivisible unit',
    );
    expect(
      harness.configStore.writes.single.presets,
      same(SettingsHarness.defaultConfig.presets),
      reason: 'nothing but the active id changes; presets are not edited here',
    );
  });

  testWidgets('A15 CAP-8: every option names the provider and model it would '
      'switch to', (tester) async {
    await harness.pumpSettings(tester);

    for (final preset in SettingsHarness.defaultConfig.presets) {
      expect(find.text(preset.id), findsOneWidget);
      expect(
        find.text('${preset.providerId} · ${preset.model}'),
        findsOneWidget,
        reason:
            'CAP-8 is about which backend serves the next correction, so the '
            'backend has to be visible in the choice',
      );
    }
  });

  testWidgets('A16 CAP-8: the screen states that the next correction uses the '
      'selected preset', (tester) async {
    await harness.pumpSettings(tester);

    await pick(tester, SettingsHarness.localPreset.id);

    expect(
      harness.configStore.current.activePresetId,
      SettingsHarness.localPreset.id,
    );
    expect(
      find.textContaining('applies to the next correction'),
      findsOneWidget,
      reason:
          'the pair changes after the config write, while a running correction '
          'keeps its submitted pair',
    );
  });

  testWidgets('A12 AD-13: a write that fails renders the failure\'s own '
      'sentence and keeps showing the store\'s current value', (tester) async {
    harness.configStore.writeError = StateError('the config file is read-only');
    await harness.pumpSettings(tester);

    await pick(tester, SettingsHarness.fastPreset.id);

    expect(find.byType(SettingsFailureNotice), findsOneWidget);
    expect(
      find.textContaining('your settings could not be saved'),
      findsOneWidget,
    );
    expect(
      harness.configStore.current.activePresetId,
      SettingsHarness.defaultPreset.id,
    );
    expect(
      tester
          .widget<ListTile>(optionFor(SettingsHarness.defaultPreset.id))
          .selected,
      isTrue,
      reason:
          'the store owns the value (AD-13), so the screen shows what it holds '
          'and never the change that did not land',
    );
    expect(
      tester
          .widget<ListTile>(optionFor(SettingsHarness.fastPreset.id))
          .selected,
      isFalse,
    );
  });

  testWidgets(
    'A12 AD-13: the failure sentence is announced, not sighted-only',
    (tester) async {
      final semantics = tester.ensureSemantics();
      harness.configStore.writeError = StateError(
        'the config file is read-only',
      );
      await harness.pumpSettings(tester);

      await pick(tester, SettingsHarness.fastPreset.id);

      final notice = tester.getSemantics(
        find.descendant(
          of: find.byType(SettingsFailureNotice),
          matching: find.byType(Text),
        ),
      );
      expect(notice.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(notice.label, contains('could not be saved'));
      semantics.dispose();
    },
  );

  testWidgets('A13 AD-13: a value the store refuses says it was refused, not '
      'that the disk failed', (tester) async {
    harness.configStore.rejects = (config) =>
        config.activePresetId == SettingsHarness.fastPreset.id;
    await harness.pumpSettings(tester);

    await pick(tester, SettingsHarness.fastPreset.id);

    expect(
      find.textContaining('refused as invalid, so nothing was saved'),
      findsOneWidget,
      reason:
          'the store validates before it touches the file, so blaming the disk '
          'would send the user to fix the wrong thing',
    );
    expect(harness.configStore.writes, isEmpty);
    expect(
      harness.configStore.current.activePresetId,
      SettingsHarness.defaultPreset.id,
    );
  });

  testWidgets('A17 AD-11: the controls are disabled while a mutation is in '
      'flight, and a failed one re-enables them', (tester) async {
    final dialog = Completer<void>();
    harness.hotkey.bindGate = dialog;
    await harness.pumpSettings(tester);

    await tester.tap(applyButton);
    await tester.pump();

    expect(
      tester.widget<ElevatedButton>(applyButton).enabled,
      isFalse,
      reason:
          'a real bind can sit on a portal dialog for seconds (AD-11), and two '
          'overlapping mutations resolve last-completion-wins',
    );
    expect(tester.widget<ListTile>(presetOption).enabled, isFalse);
    // D-16, and re-pointed from the toggles and the key field D-14 removed:
    // the capture surface is read-only while a bind is in flight, so it offers
    // no tap that would start a capture at all.
    expect(
      tester
          .widget<InkWell>(
            find
                .descendant(
                  of: find.byType(HotkeyCaptureField),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .onTap,
      isNull,
    );

    dialog.complete();
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(applyButton).enabled, isTrue);
    expect(tester.widget<ListTile>(presetOption).enabled, isTrue);
  });

  testWidgets('A17 AD-11: a mutation whose write fails still re-enables the '
      'controls', (tester) async {
    harness.configStore.writeError = StateError('the config file is read-only');
    await harness.pumpSettings(tester);

    await pick(tester, SettingsHarness.fastPreset.id);

    expect(tester.widget<ElevatedButton>(applyButton).enabled, isTrue);
    expect(tester.widget<ListTile>(presetOption).enabled, isTrue);
  });

  testWidgets('A17 AD-13: a preset picked twice while the first write is still '
      'in flight is one mutation', (tester) async {
    // The second tap lands before any frame has re-rendered the list as
    // disabled, so what refuses it is the in-flight flag inside the callback.
    // Disabling the controls is that flag's affordance, not the invariant —
    // which is why both exist.
    final disk = Completer<void>();
    harness.configStore.writeGate = disk;
    await harness.pumpSettings(tester);

    await tester.tap(optionFor(SettingsHarness.fastPreset.id));
    await tester.tap(
      optionFor(SettingsHarness.localPreset.id),
      warnIfMissed: false,
    );
    disk.complete();
    await tester.pumpAndSettle();

    expect(harness.configStore.writes, hasLength(1));
    expect(
      harness.configStore.current.activePresetId,
      SettingsHarness.fastPreset.id,
      reason:
          'the mutation the user actually issued is the one that lands — the '
          'second is refused rather than queued behind it',
    );
  });

  testWidgets('A17 AD-13: Apply pressed twice while the bind is still in '
      'flight is one bind', (tester) async {
    final dialog = Completer<void>();
    harness.hotkey.bindGate = dialog;
    await harness.pumpSettings(tester);

    await tester.tap(applyButton);
    await tester.tap(applyButton, warnIfMissed: false);
    dialog.complete();
    await tester.pumpAndSettle();

    expect(harness.hotkey.bindCalls, hasLength(1));
    expect(harness.configStore.writes, hasLength(1));
  });

  testWidgets('A18 AD-13: a config the store emits on ConfigStore.changes '
      're-renders the screen and does not retire a displayed failure', (
    tester,
  ) async {
    // Named for what it drives, not for where a change might have come from.
    // Nothing watches the config file in this build — `changes` emits after a
    // successful `write()` and nothing else — so this row is the port's fan-out
    // to a second consumer, and reading it as file-watch coverage would be
    // reading coverage that does not exist (see the skip reason in
    // test/platform/settings_screen_live_test.dart).
    useCompatiblePreset();
    harness.configStore.writeError = StateError('the config file is read-only');
    await harness.pumpSettings(tester);
    await pick(tester, SettingsHarness.fastPreset.id);
    expect(find.byType(SettingsFailureNotice), findsOneWidget);

    harness.configStore.writeError = null;
    // Somebody else's write: the store echoes it, and this controller expected
    // no echo for it.
    await harness.configStore.write(
      harness.configStore.current.copyWith(
        activePresetId: SettingsHarness.localPreset.id,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ListTile>(optionFor(SettingsHarness.localPreset.id))
          .selected,
      isTrue,
      reason: 'the store is the one owner of the value, wherever it changed',
    );
    expect(
      find.byType(SettingsFailureNotice),
      findsOneWidget,
      reason:
          'somebody else\'s change landing says nothing about whether this '
          'user\'s did, so clearing the notice would report a success that '
          'never happened',
    );

    await harness.configStore.write(
      harness.configStore.current.copyWith(activePresetId: compatiblePreset.id),
    );
    await tester.pumpAndSettle();
    await tester.enterText(baseUrlField, 'https://draft.example/v1');
    final baseUrl =
        tester.widget<TextField>(baseUrlField).controller ??
        (throw StateError('Base URL has no controller'));
    final model =
        tester.widget<TextField>(modelField).controller ??
        (throw StateError('Model has no controller'));
    baseUrl.selection = const TextSelection.collapsed(offset: 8);
    final config = harness.configStore.current;
    await harness.configStore.write(
      config.copyWith(
        providers: {
          ...config.providers,
          ProviderConfig.compatibleProviderId: const ProviderConfig(
            settings: {
              ProviderConfig.baseUrlSetting: 'https://external.example/v1',
            },
          ),
        },
        presets: [
          for (final preset in config.presets)
            if (preset.id == compatiblePreset.id)
              Preset(
                id: preset.id,
                providerId: preset.providerId,
                model: 'external-model',
                systemPrompt: preset.systemPrompt,
              )
            else
              preset,
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(baseUrl.text, 'https://draft.example/v1');
    expect(baseUrl.selection, const TextSelection.collapsed(offset: 8));
    expect(model.text, 'external-model');
    expect(
      find.textContaining('changed while you were editing'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Save provider settings'));
    await tester.tap(find.text('Save provider settings'));
    await tester.pumpAndSettle();
    expect(harness.state.compatibleBaseUrl, 'https://draft.example/v1');
    expect(harness.state.compatiblePreset?.model, 'external-model');
    expect(find.textContaining('changed while you were editing'), findsNothing);

    await tester.enterText(modelField, 'draft-model');
    model.selection = const TextSelection.collapsed(offset: 3);
    final savedConfig = harness.configStore.current;
    await harness.configStore.write(
      savedConfig.copyWith(
        providers: {
          ...savedConfig.providers,
          ProviderConfig.compatibleProviderId: const ProviderConfig(
            settings: {
              ProviderConfig.baseUrlSetting: 'https://newer.example/v1',
            },
          ),
        },
        presets: [
          for (final preset in savedConfig.presets)
            if (preset.id == compatiblePreset.id)
              Preset(
                id: preset.id,
                providerId: preset.providerId,
                model: 'newer-model',
                systemPrompt: preset.systemPrompt,
              )
            else
              preset,
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(baseUrl.text, 'https://newer.example/v1');
    expect(model.text, 'draft-model');
    expect(model.selection, const TextSelection.collapsed(offset: 3));
    expect(
      find.textContaining('changed while you were editing'),
      findsOneWidget,
    );
  });

  testWidgets('A18 AD-13: a hotkey binding arriving on ConfigStore.changes '
      're-seeds the field the user is not editing', (tester) async {
    useCompatiblePreset();
    await harness.pumpSettings(tester);
    await tester.enterText(baseUrlField, 'https://draft.example/v1');
    await tester.enterText(modelField, 'draft-model');
    final baseUrl =
        tester.widget<TextField>(baseUrlField).controller ??
        (throw StateError('Base URL has no controller'));
    final model =
        tester.widget<TextField>(modelField).controller ??
        (throw StateError('Model has no controller'));
    baseUrl.selection = const TextSelection.collapsed(offset: 8);
    model.selection = const TextSelection.collapsed(offset: 3);

    await harness.configStore.write(
      harness.configStore.current.copyWith(
        hotkeyBinding: HotkeyBinding(
          modifiers: {HotkeyModifier.alt},
          key: 'F12',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Re-pointed from the key field and its toggles: one string now carries
    // what three controls used to, and the claim is the same — the stored
    // preference is the truth and the control follows it.
    expect(find.text('Alt+F12'), findsOneWidget);
    expect(find.text('Ctrl+Shift+G'), findsNothing);
    expect(baseUrl.text, 'https://draft.example/v1');
    expect(model.text, 'draft-model');
    expect(baseUrl.selection, const TextSelection.collapsed(offset: 8));
    expect(model.selection, const TextSelection.collapsed(offset: 3));
    expect(find.textContaining('changed while you were editing'), findsNothing);

    await tester.ensureVisible(find.text('Save provider settings'));
    await tester.tap(find.text('Save provider settings'));
    await tester.pumpAndSettle();
    expect(harness.state.compatibleBaseUrl, 'https://draft.example/v1');
    expect(harness.state.compatiblePreset?.model, 'draft-model');
  });

  testWidgets('A17 AD-11: a mutation in flight survives Back and the screen '
      'reopening, so the second Apply is refused', (tester) async {
    // The exit this story itself created. The in-flight flag used to live on the
    // screen's State, and Back unmounts the screen — so Apply, Back, reopen,
    // Apply issued two binds with the first still parked on the portal dialog,
    // which is the last-completion-wins race the disabled controls promise to
    // prevent. Three taps.
    final dialog = Completer<void>();
    harness.hotkey.bindGate = dialog;
    useCompatiblePreset();
    await harness.pumpSettings(tester);
    await tester.tap(applyButton);
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await harness.openSettings(tester);
    expect(
      tester.widget<ElevatedButton>(applyButton).enabled,
      isFalse,
      reason:
          'the reopened screen reads the controller, which still holds the slot',
    );
    await tester.tap(applyButton, warnIfMissed: false);
    dialog.complete();
    await tester.pumpAndSettle();

    expect(harness.hotkey.bindCalls, hasLength(1));
    expect(harness.configStore.writes, hasLength(1));

    const secondPreset = Preset(
      id: 'second-compatible-preset',
      providerId: ProviderConfig.compatibleProviderId,
      model: 'second-model',
      systemPrompt: 'correct the text differently',
    );
    await harness.configStore.write(
      harness.configStore.current.copyWith(
        presets: [...harness.configStore.current.presets, secondPreset],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(baseUrlField, 'https://draft.example/v1');
    await tester.enterText(modelField, 'draft-model');
    await pick(tester, secondPreset.id);
    expect(
      tester.widget<TextField>(baseUrlField).controller?.text,
      'https://draft.example/v1',
    );
    expect(
      tester.widget<TextField>(modelField).controller?.text,
      'second-model',
    );

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await harness.openSettings(tester);
    expect(
      tester.widget<TextField>(baseUrlField).controller?.text,
      'https://old.example/v1',
    );
    expect(
      tester.widget<TextField>(modelField).controller?.text,
      'second-model',
    );
  });

  testWidgets('A17 CAP-1: a mutation in flight survives a summon returning to '
      'the panel, so the second Apply is refused', (tester) async {
    // The other exit, and the one a user hits without trying: a summon swaps the
    // view back to the panel (CAP-1), which unmounts the settings screen exactly
    // as Back does.
    final dialog = Completer<void>();
    harness.hotkey.bindGate = dialog;
    await harness.pumpSettings(tester);
    await tester.tap(applyButton);
    await tester.pump();

    await harness.summon(tester);
    await harness.openSettings(tester);
    await tester.tap(applyButton, warnIfMissed: false);
    dialog.complete();
    await tester.pumpAndSettle();

    expect(harness.hotkey.bindCalls, hasLength(1));
    expect(harness.configStore.writes, hasLength(1));
  });

  testWidgets('A17: a mutation in flight is stated on screen, not just '
      'reflected in dead controls', (tester) async {
    // Every control disabled and the status block still reading "nothing is in
    // effect" is indistinguishable from a hung app — the same "running looks
    // like idle" defect the panel already paid for, and here the window is
    // seconds wide by design (AD-11).
    final semantics = tester.ensureSemantics();
    final dialog = Completer<void>();
    harness.hotkey.bindGate = dialog;
    await harness.pumpSettings(tester);
    expect(find.byType(SettingsPendingNotice), findsNothing);

    await tester.tap(applyButton);
    await tester.pump();

    expect(find.byType(SettingsPendingNotice), findsOneWidget);
    final notice = tester.getSemantics(find.byType(SettingsPendingNotice));
    expect(
      notice.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
      reason:
          'announced, or it fixes "in flight looks like hung" for sighted users '
          'only and leaves everyone else with controls that stopped responding '
          'for no stated reason',
    );
    expect(notice.label, contains('Applying'));

    dialog.complete();
    await tester.pumpAndSettle();

    expect(
      find.byType(SettingsPendingNotice),
      findsNothing,
      reason:
          'real progress, not a staged spinner: it goes when the mutation '
          'actually resolves',
    );
    semantics.dispose();
  });

  testWidgets('A17 AD-13: a store whose current value throws reports a failure '
      'and leaves the controls usable', (tester) async {
    // `ConfigStore.current` is the one port call a mutation makes outside an
    // await, so an adapter breaching AD-13 there escaped the mutation entirely:
    // an unhandled zone error, and every control disabled for the life of the
    // daemon because nothing cleared the in-flight slot.
    await harness.pumpSettings(tester);
    harness.configStore.currentError = StateError('the store was never loaded');

    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'an AD-13 breach is reduced to a value, like every other one',
    );
    expect(
      find.textContaining('your settings could not be saved'),
      findsOneWidget,
    );
    expect(
      harness.configStore.writes,
      isEmpty,
      reason:
          'a change cannot be derived from a value the store would not give, and '
          'deriving it from the surface\'s stale copy would overwrite whatever '
          'else had changed',
    );
    expect(
      tester.widget<ElevatedButton>(applyButton).enabled,
      isTrue,
      reason: 'and the user can try again once the store answers',
    );
    expect(find.byType(SettingsPendingNotice), findsNothing);
  });

  testWidgets('A15 CAP-8: the preset already active is inert, so no write can '
      'fail for a change nobody made', (tester) async {
    harness.configStore.writeError = StateError('the config file is read-only');
    await harness.pumpSettings(tester);

    await tester.tap(
      optionFor(SettingsHarness.defaultPreset.id),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(harness.configStore.writes, isEmpty);
    expect(
      find.byType(SettingsFailureNotice),
      findsNothing,
      reason:
          'selecting what is already selected is not a change, and reporting '
          '"your settings could not be saved" for one is a lie about the user\'s '
          'own action',
    );
  });

  testWidgets('A15 CAP-8: a preset that lost a failed write can be picked '
      'again', (tester) async {
    // The control for the row above: the guard is on the *active* option only,
    // or a retry after a failed write would be impossible.
    harness.configStore.writeError = StateError('the config file is read-only');
    await harness.pumpSettings(tester);
    await pick(tester, SettingsHarness.fastPreset.id);
    expect(find.byType(SettingsFailureNotice), findsOneWidget);
    harness.configStore.writeError = null;

    await pick(tester, SettingsHarness.fastPreset.id);

    expect(
      harness.configStore.current.activePresetId,
      SettingsHarness.fastPreset.id,
    );
    expect(find.byType(SettingsFailureNotice), findsNothing);
  });

  testWidgets('A12 AD-13: the failure notice is visible however far the body '
      'has been scrolled', (tester) async {
    // Nothing sizes this window, so the body really does scroll. A notice inside
    // the scroll view is rendered wherever the user is not looking, and the one
    // thing it reports is that their change did not land.
    const surface = Size(420, 300);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    harness.configStore.writeError = StateError('the config file is read-only');
    await harness.pumpSettings(tester);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await pick(tester, SettingsHarness.fastPreset.id);

    final notice = tester.getRect(find.byType(SettingsFailureNotice));
    expect(find.byType(SettingsFailureNotice), findsOneWidget);
    expect(
      notice.top,
      greaterThanOrEqualTo(0),
      reason: 'the notice is on screen, not scrolled above the fold',
    );
    expect(notice.bottom, lessThanOrEqualTo(surface.height));
    expect(notice.height, greaterThan(0));
  });

  testWidgets('A19 AD-15: every path holds up when the logger itself is the '
      'thing that broke', (tester) async {
    final logger = ThrowingLogger();
    replaceHarness(SettingsHarness(installedLogger: logger));
    harness.hotkey.bindError = StateError('the portal is gone');
    harness.configStore.writeError = StateError('the config file is read-only');
    await harness.pumpSettings(tester);

    await tester.tap(applyButton);
    await tester.pumpAndSettle();
    await pick(tester, SettingsHarness.fastPreset.id);
    harness.configStore.emitChangesError(StateError('the watcher died'));
    harness.hotkey.emitBindingChangesError(StateError('the bus went away'));
    await tester.pump();
    // The screen's own report path: only the controller's teardown closes its
    // stream, and nothing but a throwing logger can tell the swallow apart from
    // its absence. Not awaited — closing a stream whose listener is a mounted
    // widget needs a frame to deliver `done`, which is what the pump is for.
    unawaited(harness.settings.dispose());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(logger.attempts, isNotEmpty);
    expect(
      find.byType(SettingsScreen),
      findsOneWidget,
      reason: 'the swallow is the one sanctioned silence; the screen stays up',
    );
  });

  testWidgets('A20 AD-4: an unmounted screen cancels its subscription and sets '
      'no state afterwards', (tester) async {
    await harness.pumpSettings(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    harness.hotkey.emitBindingChange(
      const HotkeyUnavailable(
        cause: HotkeyUnavailableCause.revoked,
        message: 'the desktop dropped the shortcut',
      ),
    );
    await harness.configStore.write(
      SettingsHarness.defaultConfig.copyWith(
        activePresetId: SettingsHarness.localPreset.id,
      ),
    );
    await tester.pump();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A20 AD-4: a mutation that resolves after the screen is gone '
      'reports to nobody', (tester) async {
    final dialog = Completer<void>();
    harness.hotkey.bindGate = dialog;
    await harness.pumpSettings(tester);
    await tester.tap(applyButton);
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    dialog.complete();
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'the in-flight flag is cleared only while mounted — a bind that '
          'outlives the screen would otherwise set state on a disposed State',
    );
  });

  testWidgets('AD-13: both notices on a short window leave the controls '
      'reachable instead of taking the whole body', (tester) async {
    // Measured, not anticipated. The notices were hoisted out of the scroll view
    // so a failure could not render off-screen — correct, and it made them two
    // fixed-height siblings of the only flexible child. At 420x160 with both up,
    // the `Expanded` below resolved to *zero* height: the status view, the hotkey
    // field and the preset list were all unreachable, and the Column overflowed
    // by 28px on top of it. Nothing sizes this window, so any height is reachable.
    tester.view.physicalSize = const Size(420, 160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await harness.pumpSettings(tester);

    // A failure notice, from a write that did not land...
    harness.configStore.writeError = StateError('config.json is read-only');
    await harness.settings.changeActivePreset('fast-preset');
    await tester.pump();
    // ...and a pending notice beside it, from a bind parked on a portal dialog.
    harness.configStore.writeError = null;
    final dialog = Completer<void>();
    harness.hotkey.bindGate = dialog;
    unawaited(harness.settings.changeHotkey(SettingsHarness.ctrlShiftG));
    await tester.pump();

    expect(find.byType(SettingsFailureNotice), findsOneWidget);
    expect(find.byType(SettingsPendingNotice), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'and no RenderFlex overflow while both are up',
    );

    final body = tester.getSize(find.byType(SettingsScreen)).height;
    final scroll = tester.getRect(find.byType(SingleChildScrollView).last);
    expect(
      scroll.height,
      greaterThan(0),
      reason:
          'a zero-height scroll view scrolls nothing — every control on this '
          'screen was unreachable',
    );
    expect(
      scroll.height,
      greaterThanOrEqualTo((body - kToolbarHeight) / 2 - 1),
      reason:
          'the notices are capped at half the body, so the controls always keep '
          'the other half however tall the notices grow',
    );

    dialog.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('AD-13: the failure notice stays inside the capped band when the '
      'pending notice is up beside it', (tester) async {
    // The cap that stopped the notices eating the controls put the clipping back
    // one level down: the band scrolls, with nothing to indicate anything is
    // below it, so whichever notice is second is the one a short window hides.
    // Measured with the pending notice first: at 420x160 *zero* of the failure
    // notice's 80px was inside the visible band. That is the retry path — a
    // mutation reissued after a failure carries the failure forward — so it is
    // precisely when the user has been told to try again that the reason
    // disappeared. The failure is first now; this row is what says so.
    tester.view.physicalSize = const Size(420, 160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await harness.pumpSettings(tester);

    harness.configStore.writeError = StateError('config.json is read-only');
    await harness.settings.changeActivePreset('fast-preset');
    await tester.pump();
    final dialog = Completer<void>();
    harness.hotkey.bindGate = dialog;
    unawaited(harness.settings.changeHotkey(SettingsHarness.ctrlShiftG));
    await tester.pump();

    expect(find.byType(SettingsPendingNotice), findsOneWidget);

    // The band is the first scroll view; the controls are the last one.
    final band = tester.getRect(find.byType(SingleChildScrollView).first);
    final notice = tester.getRect(find.byType(SettingsFailureNotice));
    // At 420x160 the band is half of a 104px body and the notice is 80px, so it
    // genuinely does not fit and scrolls inside its own band — that is the cap
    // working. What must not happen is the notice starting *below* the band's
    // visible window, which is where the pending notice put it: none of it on
    // screen, in a band that gives no sign there is more.
    final visible =
        (notice.bottom < band.bottom ? notice.bottom : band.bottom) -
        (notice.top > band.top ? notice.top : band.top);
    expect(
      visible,
      greaterThan(0),
      reason:
          'the one report that a change did not land is clipped out of the '
          'band it lives in — the band scrolls, and nothing tells the user '
          'there is anything below the pending notice',
    );
    expect(
      notice.top,
      lessThan(tester.getRect(find.byType(SettingsPendingNotice)).top),
      reason:
          'the failure comes first: whichever notice is second is the one a '
          'short window hides, and the pending notice only restates what the '
          'disabled controls already show',
    );

    dialog.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('AD-13: the failure notice is its own live region, so the one '
      'report of a lost change is announced with its own words', (
    tester,
  ) async {
    // `liveRegion` alone lands on whichever node the surrounding layout happened
    // to form — an ancestor carrying other text, or none at all. A live region
    // with the wrong label announces the wrong thing and one with an empty label
    // announces nothing, and both failures are silent. This is the sentence that
    // must not be silent.
    final semantics = tester.ensureSemantics();
    harness.configStore.writeError = StateError('config.json is read-only');
    await harness.pumpSettings(tester);

    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    // The notice's **own** node, not a descendant Text: that is what
    // `container: true` buys, and asserting it here is what would catch the flag
    // drifting onto whatever the surrounding layout happened to form.
    final notice = tester.getSemantics(find.byType(SettingsFailureNotice));
    expect(notice.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(
      notice.label,
      contains('could not be saved'),
      reason:
          'the flag and the sentence have to be on the same node, or the '
          'announcement carries the wrong words or none',
    );
    semantics.dispose();
  });

  testWidgets('AD-13: a state change that leaves the stored binding alone does '
      'not wipe a combination the user is part-way through typing', (
    tester,
  ) async {
    // The field re-seeds from the config file, which is right when the file
    // changed and wrong when anything else did. A `bindingChanges` emission, a
    // mutation going in flight, an external write to a *different* setting — all
    // rebuild this widget with the same binding, and without the guard each one
    // would snap a half-typed combination back to what is stored.
    await harness.pumpSettings(tester);

    await tester.tap(
      find
          .descendant(
            of: find.byType(HotkeyCaptureField),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pump();
    await simulateKeyDownEvent(LogicalKeyboardKey.altLeft, platform: 'linux');
    await simulateKeyDownEvent(
      LogicalKeyboardKey.f12,
      physicalKey: PhysicalKeyboardKey.f12,
      platform: 'linux',
    );
    await simulateKeyUpEvent(
      LogicalKeyboardKey.f12,
      physicalKey: PhysicalKeyboardKey.f12,
      platform: 'linux',
    );
    await simulateKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'linux');
    await tester.pumpAndSettle();

    // Somebody else changes the *preset*, so the config emits and the binding
    // in it is untouched.
    await harness.configStore.write(
      SettingsHarness.defaultConfig.copyWith(activePresetId: 'fast-preset'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Alt+F12'),
      findsOneWidget,
      reason:
          'the user had just pressed it and nothing they pressed was stored '
          'yet — a rebuild that re-seeded would discard the whole capture',
    );

    // The control: when the *binding* really does change underneath, the field
    // does follow it.
    await harness.configStore.write(
      SettingsHarness.defaultConfig.copyWith(
        hotkeyBinding: HotkeyBinding(
          modifiers: {HotkeyModifier.meta},
          key: 'Insert',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Super+Insert'),
      findsOneWidget,
      reason: 'the stored preference is the truth and the control follows it',
    );
  });
}
