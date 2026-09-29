import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/controller_providers.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/port_providers.dart';
import 'package:hotkey_grammar_corrector/src/application/panel_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/settings_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/settings_state.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/domain/logger.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:hotkey_grammar_corrector/src/ui/daemon_app.dart';

import '../fakes/fake_clipboard_port.dart';
import '../fakes/fake_clock.dart';
import '../fakes/fake_config_store.dart';
import '../fakes/fake_correction_provider.dart';
import '../fakes/fake_correction_repository.dart';
import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';
import '../fakes/fake_panel_visibility.dart';

/// The settings screen pumped over the daemon's own provider graph, with the two
/// seams `PanelHarness` deliberately leaves throwing overridden as well.
///
/// It pumps `DaemonApp`, not `SettingsScreen`: the app supplies the
/// `MaterialApp` the Material widgets need, and it is also the only way to reach
/// the screen the way a user does — through `DaemonHome`'s affordance, which is
/// what keeps the view switch under test rather than assumed.
///
/// All three controllers are built in [pump] rather than left to the widgets'
/// `initState`, because that is what the daemon does: `DaemonGraph.build()`
/// constructs every one of them eagerly, so each port subscription exists before
/// any surface does. That is not tidiness in either direction — a harness that
/// let the screen create the settings controller would make every
/// backend-initiated change unobservable until the user happened to open
/// settings, and one that never built `PanelController` (this one did not) leaves
/// the whole tray and second-launch route to the panel unreachable, which is how
/// a real defect in it survived a green suite.
final class SettingsHarness {
  SettingsHarness({AppConfig? config, this.installedLogger})
    : configStore = FakeConfigStore(current: config ?? defaultConfig);

  /// Bound to `loggerProvider` in place of [logger] when a test needs the
  /// logger *itself* to fail. Nothing but a throwing logger can tell the ui
  /// ring's swallow apart from its absence.
  final Logger? installedLogger;

  static const Preset defaultPreset = Preset(
    id: 'default-formal-casual-shorter',
    providerId: 'claude-agent-sdk',
    model: 'claude-sonnet-5',
    systemPrompt: 'correct the text',
  );

  static const Preset fastPreset = Preset(
    id: 'fast-preset',
    providerId: 'claude-agent-sdk',
    model: 'claude-haiku-5',
    systemPrompt: 'correct the text quickly',
  );

  static const Preset localPreset = Preset(
    id: 'local-preset',
    providerId: 'local-model-server',
    model: 'qwen-3-8b',
    systemPrompt: 'correct the text locally',
  );

  static final HotkeyBinding ctrlShiftG = HotkeyBinding(
    modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
    key: 'G',
  );

  /// Three presets, two providers: A15 needs more than one option, and needs
  /// the provider id to be worth showing rather than the same on every row.
  static final AppConfig defaultConfig = AppConfig(
    providers: {
      'claude-agent-sdk': ProviderConfig(settings: {}),
      'local-model-server': ProviderConfig(settings: {}),
    },
    presets: [defaultPreset, fastPreset, localPreset],
    activePresetId: 'default-formal-casual-shorter',
    hotkeyBinding: ctrlShiftG,
  );

  final FakeConfigStore configStore;
  final FakeGlobalHotkey hotkey = FakeGlobalHotkey();
  final FakeClipboardPort clipboard = FakeClipboardPort(
    text: 'i has went to the store',
  );
  final FakeCorrectionProvider provider = FakeCorrectionProvider.manual();
  final FakeCorrectionRepository repository = FakeCorrectionRepository();
  final FakeClock clock = FakeClock();
  final FakeLogger logger = FakeLogger();
  final FakePanelVisibility panelVisibility = FakePanelVisibility();

  /// Ten of the eleven seams. `trayProvider` stays throwing: no widget may reach
  /// the tray, and an override it does not need would hide one that did.
  ///
  /// This one *is* needed even though no widget reads it: `globalHotkeyProvider`
  /// is what `panelControllerProvider` is built from, and [pump] builds that
  /// controller because the daemon does.
  late final ProviderContainer container = ProviderContainer.test(
    overrides: [
      loggerProvider.overrideWithValue(installedLogger ?? logger),
      clockProvider.overrideWithValue(clock),
      configStoreProvider.overrideWithValue(configStore),
      clipboardProvider.overrideWithValue(clipboard),
      panelVisibilityProvider.overrideWithValue(panelVisibility),
      globalHotkeyProvider.overrideWithValue(hotkey),
      // The vocabulary `main.dart` injects, so the capture control validates
      // against the keys this build really registers rather than a stand-in
      // that could drift from the catalogue.
      registrableKeysProvider.overrideWithValue(
        HotkeyKeyCatalogue.registrableKeys(),
      ),
      correctionRepositoryProvider.overrideWithValue(repository),
      activeCorrectionProviderProvider.overrideWithValue(provider),
      activePresetProvider.overrideWithValue(defaultPreset),
    ],
  );

  SettingsController get settings => container.read(settingsControllerProvider);

  SettingsState get state => settings.state;

  /// The correction the controller most recently started, for the rows that
  /// need a session with an answer in it before they swap views.
  FakeCorrectionRun get run => provider.runs.last;

  PanelController get panel => container.read(panelControllerProvider);

  /// Pumps the window with the panel showing and no session started.
  Future<void> pump(WidgetTester tester) async {
    // All three, eagerly, exactly as `DaemonGraph.build()` does. Reading only
    // the settings controller was how the tray/second-launch route to the panel
    // went unnoticed: with no `PanelController` there was nothing to press a
    // hotkey at and nothing to ask for a show, so every row here reached the
    // panel through the visibility fake — the one route that always carries a
    // transition with it.
    container.read(correctionControllerProvider);
    container.read(panelControllerProvider);
    container.read(settingsControllerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DaemonApp()),
    );
    await tester.pump();
  }

  /// Pumps, then activates the settings affordance the way a user does.
  Future<void> pumpSettings(WidgetTester tester) async {
    await pump(tester);
    await openSettings(tester);
  }

  /// Activates the overlaid affordance and settles the view swap.
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(affordance);
    await tester.pump();
  }

  /// The one finder for the way in, so no test re-derives it.
  static final Finder affordance = find.byTooltip('Open settings');

  /// A real summon: one press of the bound combination, through the AD-8 toggle.
  ///
  /// The route CAP-1 describes, and the one worth driving by default — it goes
  /// `GlobalHotkey.activations` → `PanelController` → `PanelVisibility.show()`,
  /// so nothing here assumes which of the two signals the home view reacts to.
  /// Plus the frames the AD-18 re-seed needs: the clipboard read is a future, so
  /// the seeded text arrives a microtask after the empty session.
  Future<void> summon(WidgetTester tester) async {
    hotkey.press();
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  /// A show of a window that is **already visible** — AD-14's second launch and
  /// AD-12's tray "open the panel" entry.
  ///
  /// `PanelVisibility.changes` emits on a transition, so this route carries no
  /// session with it and is the one the fresh-session signal cannot see.
  Future<void> requestShow(WidgetTester tester) async {
    panel.showPanel();
    await tester.pump();
    await tester.pump();
  }

  /// A visibility transition driven at the adapter, bypassing the toggle — a
  /// window event rather than a summon (a `restore`, say).
  Future<void> show(WidgetTester tester) async {
    await panelVisibility.show();
    await tester.pump();
    await tester.pump();
  }

  /// Test teardown only: closes the fake streams the controllers subscribed to.
  ///
  /// The hotkey is disposed now that `PanelController` is built and listening —
  /// its `activations` is single-subscription, and closing it with a listener
  /// present is what completes. Not awaited, because teardown here is
  /// synchronous and nothing depends on the close landing.
  void dispose() {
    configStore.dispose();
    panelVisibility.dispose();
    unawaited(hotkey.dispose());
  }
}
