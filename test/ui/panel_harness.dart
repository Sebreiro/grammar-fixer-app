import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/controller_providers.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/port_providers.dart';
import 'package:hotkey_grammar_corrector/src/application/correction_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/correction_state.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/domain/logger.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:hotkey_grammar_corrector/src/ui/daemon_app.dart';

import '../fakes/fake_clipboard_port.dart';
import '../fakes/fake_config_store.dart';
import 'settings_harness.dart';
import '../fakes/fake_clock.dart';
import '../fakes/fake_correction_provider.dart';
import '../fakes/fake_correction_repository.dart';
import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';
import '../fakes/fake_panel_visibility.dart';

/// The panel pumped over the daemon's own provider graph, with every port seam
/// the correction session touches replaced by its fake.
///
/// It pumps `DaemonApp` rather than `CorrectionPanel` directly: the app is what
/// supplies the `MaterialApp` the panel's Material widgets need, and making it
/// the entry point is also what keeps `daemon_app.dart`'s home under test.
///
/// [pumpSession] exists because the order matters and is easy to get wrong:
/// `correctionControllerProvider` is lazy and the controller's *constructor* is
/// what subscribes to `PanelVisibility.changes`, so a `show()` issued before the
/// first pump reaches nobody and the panel renders an empty session forever.
final class PanelHarness {
  PanelHarness({
    String? clipboardText = 'i has went to the store',
    this.installedLogger,
  }) : clipboard = FakeClipboardPort(text: clipboardText);

  /// Bound to `loggerProvider` in place of [logger] when a test needs the
  /// logger *itself* to fail. The panel's own report path swallows that, the
  /// way all three controllers do, and nothing but a throwing logger can tell
  /// the swallow apart from its absence.
  final Logger? installedLogger;

  static const Preset preset = Preset(
    id: 'default-formal-casual-shorter',
    providerId: 'claude-agent-sdk',
    model: 'claude-sonnet-5',
    systemPrompt: 'correct the text',
  );

  final FakeClipboardPort clipboard;
  final FakeCorrectionProvider provider = FakeCorrectionProvider.manual();
  final FakeCorrectionRepository repository = FakeCorrectionRepository();
  final FakeClock clock = FakeClock();
  final FakeLogger logger = FakeLogger();
  final FakePanelVisibility panelVisibility = FakePanelVisibility();
  final FakeGlobalHotkey hotkey = FakeGlobalHotkey();

  /// The root also creates the retained Settings draft owner, so config uses
  /// its fake even while the panel is visible. Tray remains outside this tree.
  ///
  /// `globalHotkey` used to be the third of those and is not any more. `DaemonApp`
  /// is what this harness pumps, and its home now watches
  /// `PanelController.showRequests` — a show of a window that is *already*
  /// visible raises no visibility transition, so a summon from the tray or a
  /// second launch reaches a surface only through that signal. The controller is
  /// built from this seam, so the seam is genuinely needed rather than merely
  /// convenient.
  late final ProviderContainer container = ProviderContainer.test(
    overrides: [
      registrableKeysProvider.overrideWithValue(
        HotkeyKeyCatalogue.registrableKeys(),
      ),
      configStoreProvider.overrideWithValue(
        FakeConfigStore(current: SettingsHarness.defaultConfig),
      ),
      loggerProvider.overrideWithValue(installedLogger ?? logger),
      clockProvider.overrideWithValue(clock),
      clipboardProvider.overrideWithValue(clipboard),
      panelVisibilityProvider.overrideWithValue(panelVisibility),
      globalHotkeyProvider.overrideWithValue(hotkey),
      correctionRepositoryProvider.overrideWithValue(repository),
      activeCorrectionProviderProvider.overrideWithValue(provider),
      activePresetProvider.overrideWithValue(preset),
    ],
  );

  CorrectionController get controller =>
      container.read(correctionControllerProvider);

  CorrectionState get state => controller.state;

  /// The correction the controller most recently started.
  FakeCorrectionRun get run => provider.runs.last;

  /// Pumps the panel with no session started yet.
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DaemonApp()),
    );
    // A second frame: the editor's autofocus and the first state emission both
    // land after the first build.
    await tester.pump();
  }

  /// Pumps, then starts a session the way the AD-8 toggle does.
  Future<void> pumpSession(WidgetTester tester) async {
    await pump(tester);
    await show(tester);
  }

  /// A show, plus the frames the re-seed needs: the clipboard read is a future,
  /// so the seeded text arrives a microtask after the empty session does.
  Future<void> show(WidgetTester tester) async {
    await panelVisibility.show();
    await tester.pump();
    await tester.pump();
  }

  Future<void> hide(WidgetTester tester) async {
    await panelVisibility.hide();
    await tester.pump();
  }

  /// One suggestion per register, its text derived from the register's own
  /// `name` — so a test can say what it expects without naming `formal`,
  /// `casual` or `shorter` positionally (AD-6).
  static Map<SuggestionRegister, String> completedTexts([
    String prefix = 'the corrected',
  ]) {
    return {
      for (final register in SuggestionRegister.values)
        register: '$prefix ${register.name} text',
    };
  }

  static CorrectionCompleted completedEvent([String prefix = 'the corrected']) {
    return CorrectionCompleted(
      suggestions: [
        for (final entry in completedTexts(prefix).entries)
          Suggestion(register: entry.key, text: entry.value),
      ],
    );
  }

  /// Completes the in-flight correction and pumps the frame that renders it.
  Future<void> completeRun(
    WidgetTester tester, [
    String prefix = 'the corrected',
  ]) async {
    run.emit(completedEvent(prefix));
    await tester.pump();
    await tester.pump();
  }

  /// Test teardown only: closes the fakes' streams so the controllers'
  /// subscriptions have something to end.
  ///
  /// The hotkey is closed as well as the visibility fake, now that
  /// `PanelController` is built from it and listening to `activations`. Not
  /// awaited, because teardown here is synchronous and nothing depends on the
  /// close landing.
  void dispose() {
    panelVisibility.dispose();
    unawaited(hotkey.dispose());
  }
}
