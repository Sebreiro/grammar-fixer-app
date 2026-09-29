import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/controller_providers.dart';
import 'package:hotkey_grammar_corrector/src/application/composition/port_providers.dart';
import 'package:hotkey_grammar_corrector/src/application/correction_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/panel_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/settings_controller.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
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
import '../fakes/fake_tray_port.dart';

/// The Riverpod graph itself (AD-17): every controller is built from the port
/// seams, an un-overridden seam is a startup failure, and disposing twice is a
/// no-op — which is what lets `main.dart` own the ordered async teardown while
/// the container's own `onDispose` hooks fire again behind it.
///
/// This is the one suite that needs a Flutter binding, which is why it lives in
/// its own directory: `package:flutter_riverpod` pulls in Flutter (AGENTS.md
/// §7 keeps every other ring binding-free).
void main() {
  late _Ports ports;

  setUp(() => ports = _Ports());
  tearDown(() => ports.dispose());

  ProviderContainer container() =>
      ProviderContainer.test(overrides: ports.overrides);

  group('the controllers are built from the injected ports (AD-17)', () {
    test('CAP-1: the panel controller toggles the injected visibility '
        'port', () {
      final controller = container().read(panelControllerProvider);
      expect(controller, isA<PanelController>());

      controller.onHotkeyActivated();

      expect(ports.panelVisibility.isVisible, isTrue);
    });

    test('CAP-1: the panel controller listens to the injected hotkey '
        'adapter', () async {
      container().read(panelControllerProvider);

      ports.hotkey.press();
      await pumpEventQueue();

      expect(ports.panelVisibility.isVisible, isTrue);
    });

    test('CAP-12: the settings controller reads the injected config store', () {
      final controller = container().read(settingsControllerProvider);
      expect(controller, isA<SettingsController>());

      expect(controller.state.config, ports.configStore.current);
    });

    test('AD-5: the active pair reaches the correction controller — the '
        'injected preset is what the injected provider is asked with', () {
      final controller = container().read(correctionControllerProvider);
      expect(controller, isA<CorrectionController>());

      controller.editText('i has a text');
      controller.submit();

      expect(ports.provider.correctCalls, hasLength(1));
      expect(ports.provider.correctCalls.single.preset, _preset);
      expect(ports.provider.correctCalls.single.text, 'i has a text');
    });

    test('AD-18: the correction controller subscribes to the injected panel '
        'visibility, so the first show already starts a session', () async {
      container().read(correctionControllerProvider);

      await ports.panelVisibility.show();
      await Future<void>.delayed(Duration.zero);

      expect(
        ports.clipboard.readCalls,
        1,
        reason: 'a show re-seeds the editor from the clipboard (CAP-2)',
      );
    });
  });

  group('an un-overridden seam is a startup failure (AD-17)', () {
    test('AD-17: reading a port with no override throws, naming main.dart', () {
      final bare = ProviderContainer.test();

      for (final read in <void Function()>[
        () => bare.read(loggerProvider),
        () => bare.read(clockProvider),
        () => bare.read(configStoreProvider),
        () => bare.read(clipboardProvider),
        () => bare.read(panelVisibilityProvider),
        () => bare.read(globalHotkeyProvider),
        () => bare.read(trayProvider),
        () => bare.read(correctionRepositoryProvider),
        () => bare.read(activeCorrectionProviderProvider),
        () => bare.read(activePresetProvider),
      ]) {
        expect(
          read,
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('main.dart must override'),
            ),
          ),
          reason:
              'a missing override must fail loudly at startup rather than '
              'leaving a silent null behind a port',
        );
      }
    });

    test('AD-17: a controller built over a missing seam fails too, rather '
        'than constructing half a graph', () {
      final partial = ProviderContainer.test(
        overrides: [loggerProvider.overrideWithValue(ports.logger)],
      );

      expect(() => partial.read(panelControllerProvider), throwsA(anything));
    });
  });

  group('teardown (CAP-7)', () {
    test('AD-4: disposing a controller twice is a no-op', () async {
      final built = container();
      final correction = built.read(correctionControllerProvider);
      final panel = built.read(panelControllerProvider);
      final settings = built.read(settingsControllerProvider);

      await correction.dispose();
      await panel.dispose();
      await settings.dispose();

      await expectLater(correction.dispose(), completes);
      await expectLater(panel.dispose(), completes);
      await expectLater(settings.dispose(), completes);
    });

    test('CAP-7: the container disposed after an explicit teardown is a '
        'no-op — main.dart awaits each dispose, then the container fires '
        'them again', () async {
      final built = container();
      final correction = built.read(correctionControllerProvider);
      built.read(panelControllerProvider);
      built.read(settingsControllerProvider);

      await correction.dispose();

      expect(built.dispose, returnsNormally);
      expect(built.dispose, returnsNormally);
    });

    test('AD-17: the container disposes controllers nothing else tore down, '
        'so no path leaks one', () async {
      final built = container();
      built.read(panelControllerProvider);

      built.dispose();
      // The hotkey subscription is gone, so a later press reaches nothing.
      ports.hotkey.press();
      await Future<void>.delayed(Duration.zero);

      expect(ports.panelVisibility.isVisible, isFalse);
    });
  });
}

/// One fake per seam, plus the override list that installs them — the test's
/// stand-in for what `main.dart` builds out of real adapters.
final class _Ports {
  final logger = FakeLogger();
  final clock = FakeClock();
  final configStore = FakeConfigStore(current: _config);
  final clipboard = FakeClipboardPort(text: 'from the clipboard');
  final panelVisibility = FakePanelVisibility();
  final hotkey = FakeGlobalHotkey();
  final tray = FakeTrayPort();
  final repository = FakeCorrectionRepository();
  final provider = FakeCorrectionProvider(script: const []);

  /// Inferred rather than annotated: `Override` is not exported by
  /// `package:flutter_riverpod`, and reaching into `package:riverpod` for the
  /// name would add an undeclared package dependency for a type the compiler
  /// already knows.
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

final AppConfig _config = AppConfig(
  providers: {'claude-agent-sdk': ProviderConfig(settings: {})},
  presets: [_preset],
  activePresetId: 'default-formal-casual-shorter',
  hotkeyBinding: HotkeyBinding(
    modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
    key: 'G',
  ),
);
