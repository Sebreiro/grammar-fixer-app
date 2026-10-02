import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/controller_providers.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/daemon_graph.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/port_providers.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/close_behavior.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/config_write_conflict.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_bind_outcome.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/global_hotkey.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';

import '../fakes/fake_clipboard_port.dart';
import '../fakes/fake_clock.dart';
import '../fakes/fake_config_store.dart';
import '../fakes/fake_correction_provider.dart';
import '../fakes/fake_correction_repository.dart';
import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';
import '../fakes/fake_panel_visibility.dart';
import '../fakes/fake_provider_key_writer.dart';
import '../fakes/fake_tray_port.dart';
import '../fakes/throwing_logger.dart';

/// The container-touching half of the daemon's lifecycle (AD-17).
///
/// `DaemonLifecycle` owns the order the *adapters* close in and is tested
/// without a binding; this is the half it reaches through callbacks, and the
/// only place the real controllers are driven through a real
/// `ProviderContainer`. It needs a Flutter binding, hence `test/composition/`.
void main() {
  late _Ports ports;

  setUp(() => ports = _Ports());
  tearDown(() => ports.dispose());

  DaemonGraph graphOver(ProviderContainer container) =>
      DaemonGraph(container: container, logger: ports.logger);

  ProviderContainer container() =>
      ProviderContainer.test(overrides: ports.overrides);

  test(
    'CAP-8: graph eagerly connects native Close to the persisted preference',
    () async {
      final graph = graphOver(container())..build();
      final requests = <void>[];
      graph.quitRequests.listen(requests.add);
      await ports.panelVisibility.show();
      ports.panelVisibility.requestClose();
      await pumpEventQueue();
      expect(ports.panelVisibility.isVisible, isFalse);
      expect(requests, isEmpty);
      await graph.container
          .read(settingsControllerProvider)
          .changeCloseBehavior(CloseBehavior.quit);
      await ports.panelVisibility.show();
      ports.panelVisibility.requestClose();
      await pumpEventQueue();
      expect(requests, hasLength(1));
      expect(ports.panelVisibility.isVisible, isTrue);
    },
  );

  test(
    'AD-4: disposing graph controllers stops native Close handling',
    () async {
      final graph = graphOver(container())..build();
      await graph.disposeControllers();
      await ports.panelVisibility.show();
      ports.panelVisibility.requestClose();
      await pumpEventQueue();
      expect(ports.panelVisibility.isVisible, isTrue);
    },
  );

  test(
    'CAP-8: persisted and external log limits reach the runtime config listener',
    () async {
      final limits = <int>[];
      final graph = DaemonGraph(
        container: container(),
        logger: ports.logger,
        onConfigApplied: (config) => limits.add(config.logMaxBytes),
      )..build();
      final settings = graph.container.read(settingsControllerProvider);
      await settings.changeLogMaxBytes(5242880);
      expect(ports.configStore.current.logMaxBytes, 5242880);
      await ports.configStore.write(
        ports.configStore.current.copyWith(logMaxBytes: 2048),
      );
      await pumpEventQueue();
      expect(limits, [5242880, 2048]);
      await graph.disposeControllers();
      graph.dispose();
    },
  );

  group('the graph is built at startup (AD-14, AD-17)', () {
    test('AD-18: build() constructs every controller, so the first show is '
        'not the event that creates the listener', () async {
      final graph = graphOver(container())..build();

      // Nothing read a provider after build(); if a controller were lazy this
      // show would arrive before anything was subscribed.
      await ports.panelVisibility.show();
      await pumpEventQueue();

      expect(ports.clipboard.readCalls, 1);
      expect(graph.container.read(panelControllerProvider), isNotNull);
      expect(graph.container.read(settingsControllerProvider), isNotNull);
    });

    test(
      'CAP-1: build() wires the hotkey adapter to the panel toggle',
      () async {
        graphOver(container()).build();

        ports.hotkey.press();
        await pumpEventQueue();

        expect(ports.panelVisibility.isVisible, isTrue);
      },
    );
  });

  group('the startup bind outcome reaches the settings surface (AD-12)', () {
    test('AD-12: applyStartupBindOutcome hands the outcome to the settings '
        'controller, so the screen states unavailability from its first '
        'frame', () {
      final graph = graphOver(container())..build();
      const outcome = HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: 'this compositor provides no global shortcuts portal',
      );

      graph.applyStartupBindOutcome(outcome);

      expect(
        graph.container
            .read(settingsControllerProvider)
            .state
            .hotkeyBindOutcome,
        equals(outcome),
        reason:
            'the graph is built before the bind is attempted — a real bind can '
            'sit on a portal dialog for seconds (AD-11) — so the outcome cannot '
            'be a constructor argument and arrives here instead',
      );
    });

    test('AD-12: a hand-off before build() does nothing and says so', () {
      final graph = graphOver(container());

      expect(
        () => graph.applyStartupBindOutcome(
          const HotkeyUnavailable(
            cause: HotkeyUnavailableCause.noBackend,
            message: 'no portal',
          ),
        ),
        returnsNormally,
      );

      final warnings = ports.logger.lines.where(
        (line) => line.level == 'warning',
      );
      expect(
        warnings.single.message,
        contains('reached no settings surface'),
        reason:
            'every other swallow in this file logs, and an outcome discarded in '
            'silence is the shape of the gap this method exists to close',
      );
      expect(
        warnings.single.context,
        equals({'outcome': 'HotkeyUnavailable'}),
        reason:
            'the type, not the message — an adapter-authored sentence is a value '
            'for a surface to render, not a log payload',
      );
    });
  });

  group('the live graph connects settings to daemon effects', () {
    test('CAP-1: startup bind and later changes publish the current tray '
        'status', () async {
      final graph = DaemonGraph(
        container: container(),
        logger: ports.logger,
        tray: ports.tray,
      )..build();
      const unavailable = HotkeyUnavailable(
        cause: HotkeyUnavailableCause.noBackend,
        message: 'no compositor shortcut service',
      );

      graph.applyStartupBindOutcome(unavailable);
      await pumpEventQueue();
      await graph.disposeControllers();

      expect(ports.tray.statuses, hasLength(1));
      expect(ports.tray.hotkeyStatus?.outcome, unavailable);
      expect(ports.tray.hotkeyUnavailable, isTrue);
    });

    test('CAP-13: a broken tray and logger cannot interrupt settings '
        'updates or teardown', () async {
      final logger = ThrowingLogger();
      ports.tray.hotkeyStatusError = StateError('tray disappeared');
      final graph = DaemonGraph(
        container: container(),
        logger: logger,
        tray: ports.tray,
      )..build();

      graph.applyStartupBindOutcome(
        const HotkeyUnavailable(
          cause: HotkeyUnavailableCause.noBackend,
          message: 'no compositor shortcut service',
        ),
      );
      await pumpEventQueue();
      await graph.disposeControllers();

      expect(logger.attempts, contains('warning'));
      expect(ports.tray.statuses, isEmpty);
    });

    test('CAP-8: a committed preset edit selects the provider for the next '
        'correction', () async {
      final graph = DaemonGraph(
        container: container(),
        logger: ports.logger,
        activePairForConfig: (config) => (
          provider: ports.provider,
          preset: config.presets.singleWhere(
            (preset) => preset.id == config.activePresetId,
          ),
        ),
      )..build();
      final settings = graph.container.read(settingsControllerProvider);

      await settings.changeActivePreset(_fastPreset.id);
      await ports.panelVisibility.show();
      await pumpEventQueue();
      final correction = graph.container.read(correctionControllerProvider);
      correction.submit();
      await pumpEventQueue();

      expect(ports.provider.correctCalls.single.preset, _fastPreset);
      await graph.disposeControllers();
    });

    test('CAP-8: the graph supplies only a credential source label to '
        'settings', () async {
      ports.configStore.current = _config.copyWith(
        providers: {
          ..._config.providers,
          ProviderConfig.compatibleProviderId: ProviderConfig(settings: {}),
        },
      );
      final graph = DaemonGraph(
        container: container(),
        logger: ports.logger,
        apiKeySourceLabel: (_) async => 'Secret Service',
      )..build();

      final label = await graph.container
          .read(settingsControllerProvider)
          .keySourceLabel();

      expect(label, 'Secret Service');
      await graph.disposeControllers();
    });

    test('CAP-8: provider endpoint and model save together while the prompt '
        'and other presets stay intact', () async {
      ports.configStore.current = _compatibleConfig;
      final graph = graphOver(container())..build();
      final settings = graph.container.read(settingsControllerProvider);

      await settings.changeProviderSettings(
        baseUrl: '  https://new.example/v1  ',
        model: '  new-model  ',
      );

      final saved = ports.configStore.writes.single;
      expect(
        saved
            .providers[ProviderConfig.compatibleProviderId]
            ?.settings[ProviderConfig.baseUrlSetting],
        'https://new.example/v1',
      );
      expect(saved.presets.first.model, 'new-model');
      expect(saved.presets.first.systemPrompt, _compatiblePreset.systemPrompt);
      expect(saved.presets.last, _fastPreset);
      expect(settings.state.failure, isNull);
      await graph.disposeControllers();
    });

    test(
      'CAP-8: the graph injects keyring saving without storing the key in config',
      () async {
        final writer = FakeProviderKeyWriter();
        final graph = DaemonGraph(
          container: container(),
          logger: ports.logger,
          providerKeyWriter: writer,
        )..build();
        final settings = graph.container.read(settingsControllerProvider);

        expect(await settings.saveApiKey('private-key'), isTrue);
        expect(writer.writes.single.apiKey, 'private-key');
        expect(ports.configStore.writes, isEmpty);
        await graph.disposeControllers();
      },
    );

    test(
      'CAP-13: invalid endpoint settings show a failure without writing',
      () async {
        ports.configStore.current = _compatibleConfig;
        final graph = graphOver(container())..build();
        final settings = graph.container.read(settingsControllerProvider);

        await settings.changeProviderSettings(baseUrl: ' ', model: 'model');
        expect(settings.state.failure?.message, contains('required'));
        await settings.changeProviderSettings(
          baseUrl: 'http://remote.example/v1',
          model: 'model',
        );
        expect(settings.state.failure?.message, contains('HTTPS'));
        expect(ports.configStore.writes, isEmpty);
        await graph.disposeControllers();
      },
    );

    test('CAP-13: an incompatible active preset rejects provider settings '
        'without changing config', () async {
      final graph = graphOver(container())..build();
      final settings = graph.container.read(settingsControllerProvider);

      await settings.changeProviderSettings(
        baseUrl: 'https://new.example/v1',
        model: 'new-model',
      );

      expect(settings.state.failure, isNotNull);
      expect(ports.configStore.writes, isEmpty);
      await graph.disposeControllers();
    });

    test('CAP-13: credential and live provider failures stay visible as '
        'settings failures after a committed write', () async {
      ports.configStore.current = _compatibleConfig;
      final graph = DaemonGraph(
        container: container(),
        logger: ports.logger,
        apiKeySourceLabel: (_) => throw StateError('keyring unavailable'),
        activePairForConfig: (_) => throw StateError('provider unavailable'),
      )..build();
      final settings = graph.container.read(settingsControllerProvider);

      expect(await settings.keySourceLabel(), 'None configured');
      await settings.changeProviderSettings(
        baseUrl: 'https://new.example/v1',
        model: 'new-model',
      );

      expect(ports.configStore.writes, hasLength(1));
      expect(
        ports.logger.lines.where((line) => line.level == 'error'),
        hasLength(2),
      );
      await graph.disposeControllers();
    });

    test('CAP-12: repeated file edit conflicts refuse the settings write '
        'without overwriting the store', () async {
      ports.configStore.writeError = const ConfigWriteConflict();
      final graph = graphOver(container())..build();
      final settings = graph.container.read(settingsControllerProvider);

      await settings.changeActivePreset(_fastPreset.id);

      expect(settings.state.failure?.message, contains('kept changing'));
      expect(ports.configStore.writes, isEmpty);
      expect(ports.configStore.current.activePresetId, _preset.id);
      await graph.disposeControllers();
    });

    test('CAP-13: a selected provider missing from config is surfaced as '
        'a rejected settings edit', () async {
      ports.configStore.current = _compatibleConfig.copyWith(
        providers: _config.providers,
      );
      final graph = graphOver(container())..build();
      final settings = graph.container.read(settingsControllerProvider);

      await settings.changeProviderSettings(
        baseUrl: 'https://new.example/v1',
        model: 'new-model',
      );

      expect(settings.state.failure?.message, contains('provider changed'));
      expect(ports.configStore.writes, isEmpty);
      await graph.disposeControllers();
    });

    test('CAP-12: a compositor retaining the old shortcut does not write '
        'an invented effective binding', () async {
      final graph = graphOver(container())..build();
      final settings = graph.container.read(settingsControllerProvider);
      ports.hotkey.emitBindingChange(
        const HotkeyRetained(
          HotkeyRegistration(
            effective: null,
            authority: BindingAuthority.compositor,
          ),
        ),
      );
      await pumpEventQueue();

      expect(settings.state.hotkeyBindOutcome, isA<HotkeyRetained>());
      expect(ports.configStore.writes, isEmpty);
      await graph.disposeControllers();
    });
  });

  group('a show request from a later launch (AD-14)', () {
    test('AD-14: showPanel() raises the panel through the real controller', () {
      final graph = graphOver(container())..build();

      graph.showPanel();

      expect(ports.panelVisibility.isVisible, isTrue);
    });

    test('AD-14: showPanel() on an already-visible panel leaves it up', () {
      final graph = graphOver(container())..build();
      graph.showPanel();

      graph.showPanel();

      expect(ports.panelVisibility.isVisible, isTrue);
    });
  });

  group('controller teardown (CAP-7)', () {
    test('CAP-7: disposeControllers() does not resolve until a history write '
        'in flight has landed', () async {
      final graph = graphOver(container())..build();
      final correction = graph.container.read(correctionControllerProvider);
      final saving = Completer<void>();
      ports.repository.saveGate = saving;
      await ports.panelVisibility.show();
      await pumpEventQueue();
      correction.editText('i has a text');
      correction.submit();
      await pumpEventQueue();

      var disposed = false;
      unawaited(graph.disposeControllers().then((_) => disposed = true));
      await pumpEventQueue();

      expect(
        disposed,
        isFalse,
        reason:
            'CAP-7 retains a correction that terminates as the daemon '
            'exits, so the database cannot close underneath the write',
      );

      saving.complete();
      await pumpEventQueue();

      expect(disposed, isTrue);
      expect(ports.repository.saved, hasLength(1));
    });

    test('CAP-7: the correction controller is disposed first — it is the one '
        'that drains pending history writes', () async {
      final graph = graphOver(container())..build();
      // The correction and panel controllers each observe visibility; the panel
      // controller also owns hotkey activations, and Settings owns config. A
      // rejecting cancel reports each subscription in controller teardown order.
      ports.panelVisibility.cancelError = StateError('window handle died');
      ports.hotkey.cancelError = StateError('grab already released');
      ports.configStore.cancelError = StateError('watcher already gone');

      await graph.disposeControllers();

      expect(
        [for (final line in ports.logger.lines) line.message],
        [
          'cancelling the panel visibility subscription failed',
          'cancelling the panel visibility subscription failed',
          'cancelling the hotkey activation subscription failed',
          'cancelling the panel close subscription failed',
          'cancelling the config subscription failed',
        ],
      );
      ports.panelVisibility.cancelError = null;
      ports.hotkey.cancelError = null;
      ports.configStore.cancelError = null;
    });

    test('CAP-7: one controller whose teardown rejects does not strand the '
        'other two', () async {
      final graph = graphOver(container())..build();
      graph.container.read(correctionControllerProvider);
      final settings = graph.container.read(settingsControllerProvider);
      // The correction controller cancels this subscription first, and a
      // rejected cancel is what a broken adapter looks like at shutdown.
      ports.panelVisibility.cancelError = StateError('the window handle died');

      await expectLater(graph.disposeControllers(), completes);

      // The settings controller still got its turn: a second dispose on a
      // torn-down controller is a no-op, and its mutations are dead.
      await expectLater(settings.dispose(), completes);
      await settings.changeActivePreset('fast-preset');
      expect(ports.configStore.writes, isEmpty);
      ports.panelVisibility.cancelError = null;
    });

    test('CAP-7: dispose() releases the container, and doing so after an '
        'explicit teardown is a no-op', () async {
      final graph = graphOver(container())..build();

      await graph.disposeControllers();

      expect(graph.dispose, returnsNormally);
      expect(graph.dispose, returnsNormally);
    });

    test('DW-37: a graph whose build() threw partway still tears down the '
        'controller it did construct', () async {
      // The premise of the aborted-startup teardown, executed. `build()` reads
      // its three providers in sequence, so a throw on the second leaves
      // `CorrectionController` constructed and subscribed to panel visibility
      // with no lifecycle to dispose it — the state `main.dart`'s
      // `_releaseWithoutLifecycle` now takes the graph in order to reach. Every
      // other teardown row in this group runs against a fully built graph, so
      // without this one the partial case is asserted by nothing that executes.
      //
      // Broken at the second of the three reads, which is where the sequence
      // matters: the first controller is already constructed and subscribed,
      // and the third is never reached.
      final graph = graphOver(
        ProviderContainer.test(
          overrides: [
            ...ports.overrides,
            panelControllerProvider.overrideWith(
              (ref) => throw StateError('the compositor refused the seam'),
            ),
          ],
        ),
      );

      expect(graph.build, throwsA(anything));

      await expectLater(graph.disposeControllers(), completes);

      // Observed here, between the two steps, and that placement is the whole
      // strength of this row. `dispose()` releases the container, whose
      // `onDispose` hooks tear the same controller down again as a backstop —
      // so a check made after both steps passes even when this one did
      // nothing, and a `build()` that assigned its fields only after all three
      // reads succeeded would sail through it. A live correction controller
      // answers a show by reading the clipboard; a disposed one does not.
      await ports.panelVisibility.show();
      await pumpEventQueue();

      expect(
        ports.clipboard.readCalls,
        0,
        reason:
            'the one controller a partial build did construct is subscribed to '
            'panel visibility, and disposeControllers is the step that has to '
            'cancel it — before the container, and long before the adapter',
      );

      expect(graph.dispose, returnsNormally);
    });

    test('DW-37: a graph that was never built tears down as a no-op', () async {
      // The other guard on the abort path: the failure can precede `build()`
      // entirely and both steps still run. The three controller fields being
      // *nullable* is what makes this safe — as `late` fields they would throw
      // a LateInitializationError into the abort's own per-step swallow, so the
      // abort would log a tidy failure and report healthy while disposing
      // nothing at all.
      final graph = graphOver(container());

      await expectLater(graph.disposeControllers(), completes);
      expect(graph.dispose, returnsNormally);
    });
  });
}

/// One fake per seam, plus the override list that installs them.
final class _Ports {
  final logger = FakeLogger();
  final clock = FakeClock();
  final configStore = FakeConfigStore(current: _config);
  final clipboard = FakeClipboardPort(text: 'from the clipboard');
  final panelVisibility = FakePanelVisibility();
  final hotkey = FakeGlobalHotkey();
  final tray = FakeTrayPort();
  final repository = FakeCorrectionRepository();
  final provider = FakeCorrectionProvider(
    script: const [
      CorrectionCompleted(
        suggestions: [
          Suggestion(register: SuggestionRegister.formal, text: 'Formal.'),
          Suggestion(register: SuggestionRegister.casual, text: 'Casual.'),
          Suggestion(register: SuggestionRegister.shorter, text: 'Short.'),
        ],
      ),
    ],
  );

  /// Inferred rather than annotated: `Override` is not exported by
  /// `package:flutter_riverpod`.
  late final overrides = [
    loggerProvider.overrideWithValue(logger),
    clockProvider.overrideWithValue(clock),
    configStoreProvider.overrideWithValue(configStore),
    clipboardProvider.overrideWithValue(clipboard),
    panelVisibilityProvider.overrideWithValue(panelVisibility),
    globalHotkeyProvider.overrideWithValue(hotkey),
    registrableKeysProvider.overrideWithValue(
      HotkeyKeyCatalogue.registrableKeys(),
    ),
    trayProvider.overrideWithValue(tray),
    correctionRepositoryProvider.overrideWithValue(repository),
    activeCorrectionProviderProvider.overrideWithValue(provider),
    activePresetProvider.overrideWithValue(_preset),
  ];

  void dispose() {
    configStore.dispose();
    panelVisibility.dispose();
    tray.dispose();
  }
}

const Preset _preset = Preset(
  id: 'default-formal-casual-shorter',
  providerId: 'claude-agent-sdk',
  model: 'claude-sonnet-5',
  systemPrompt: 'correct this',
);

const Preset _fastPreset = Preset(
  id: 'fast-preset',
  providerId: 'claude-agent-sdk',
  model: 'claude-haiku-5',
  systemPrompt: 'correct this fast',
);

const Preset _compatiblePreset = Preset(
  id: 'compatible',
  providerId: ProviderConfig.compatibleProviderId,
  model: 'old-model',
  systemPrompt: 'Keep this prompt.',
);

final AppConfig _compatibleConfig = _config.copyWith(
  providers: {
    ..._config.providers,
    ProviderConfig.compatibleProviderId: const ProviderConfig(
      settings: {ProviderConfig.baseUrlSetting: 'https://old.example/v1'},
    ),
  },
  presets: [_compatiblePreset, _fastPreset],
  activePresetId: _compatiblePreset.id,
);

final AppConfig _config = AppConfig(
  providers: {'claude-agent-sdk': ProviderConfig(settings: {})},
  presets: [_preset, _fastPreset],
  activePresetId: 'default-formal-casual-shorter',
  hotkeyBinding: HotkeyBinding(
    modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
    key: 'G',
  ),
);
