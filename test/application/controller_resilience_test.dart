import 'dart:async';

import 'package:hotkey_grammar_corrector/src/application/correction_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/panel_controller.dart';
import 'package:hotkey_grammar_corrector/src/application/settings_controller.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_event.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/suggestion_register.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/registrable_keys.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:test/test.dart';

import '../fakes/fake_clipboard_port.dart';
import '../fakes/fake_clock.dart';
import '../fakes/fake_config_store.dart';
import '../fakes/fake_correction_provider.dart';
import '../fakes/fake_correction_repository.dart';
import '../fakes/fake_global_hotkey.dart';
import '../fakes/fake_logger.dart';
import '../fakes/fake_panel_visibility.dart';

/// The one assertion no per-scenario test makes: that nothing escapes.
///
/// Each controller is driven through its whole lifecycle with every port it
/// calls set to fail, inside a [runZonedGuarded] whose error handler collects
/// what the guards missed. CAP-1's daemon is resident all day, so an
/// unhandled async error here is not a test artefact — it is the process
/// logging a stack trace nobody reads, once per failure, forever.
void main() {
  test('CAP-1: the correction controller survives a session in which every '
      'port it calls fails (AD-15)', () async {
    final unhandled = <Object>[];
    final logger = FakeLogger();

    await runZonedGuarded(() async {
      final clipboard = FakeClipboardPort(text: 'a seed nobody will see')
        ..readError = StateError('the clipboard read failed');
      final provider = FakeCorrectionProvider.manual();
      final repository = FakeCorrectionRepository()
        ..saveError = StateError('the history write failed');
      final panel = FakePanelVisibility();
      final controller = CorrectionController(
        clipboard: clipboard,
        provider: provider,
        preset: _preset,
        repository: repository,
        clock: FakeClock(),
        logger: logger,
        panelVisibility: panel,
      );

      // show: the seed fails, and the visibility stream breaks its contract.
      await panel.show();
      panel.emitChangesError(StateError('the window event decode failed'));
      await pumpEventQueue();

      // edit and submit: the run starts on what the user typed by hand.
      controller.editText('what the user typed');
      controller.submit();
      await pumpEventQueue();

      // terminal: a malformed completion, whose failed record cannot be
      // written either — and whose teardown cancel refuses. Under AD-19 that
      // cancel is the sidecar's process-group kill, and `_finish` fires it
      // without awaiting, so it is the likeliest of all these to escape.
      provider.runs.last.cancelError = StateError('the sidecar refused to die');
      provider.runs.last.emit(
        const CorrectionCompleted(
          suggestions: [
            Suggestion(register: SuggestionRegister.formal, text: 'only one'),
          ],
        ),
      );
      await pumpEventQueue();

      // retry: this time the provider will not even return a stream.
      provider.correctError = StateError('the sidecar could not spawn');
      controller.retry();
      await pumpEventQueue();

      // shutdown, with a rejected history write still pending and a
      // visibility subscription that will not come down either.
      panel.cancelError = StateError('the window event channel is gone');
      await controller.dispose();
      panel.cancelError = null;
      panel.dispose();
    }, (error, stack) => unhandled.add(error));

    expect(unhandled, isEmpty);
    // Named, not counted: `isNotEmpty` is satisfied by any one of these, so
    // six of the seven guards could stop reporting and the suite would stay
    // green. Every swallowed failure must reach the Logger port.
    expect(
      logger.lines.map((line) => line.message),
      containsAll([
        contains('clipboard read failed'),
        contains('panel visibility stream errored'),
        contains('malformed register set'),
        contains('provider threw'),
        contains('history write failed'),
        contains('cancelling the terminated correction failed'),
        contains('cancelling the panel visibility subscription failed'),
      ]),
    );
  });

  test('CAP-1: the panel controller survives a toggle in which every port it '
      'calls fails (AD-15)', () async {
    final unhandled = <Object>[];
    final logger = FakeLogger();

    await runZonedGuarded(() async {
      // The hide arm is only reachable from a visible panel, so the first
      // show has to land: a panel whose show always fails is never visible,
      // and every later press takes the show branch again.
      final panel = FakePanelVisibility()
        ..hideError = StateError('the window manager refused to hide');
      final hotkey = FakeGlobalHotkey();
      final controller = PanelController(
        visibility: panel,
        hotkey: hotkey,
        logger: logger,
      );

      controller.onHotkeyActivated();
      await pumpEventQueue();
      expect(
        panel.isVisible,
        isTrue,
        reason: 'the hide arm needs a visible panel',
      );

      // Now every call refuses, in both directions.
      panel.showError = StateError('the window manager refused to show');
      hotkey.press();
      hotkey.emitActivationsError(StateError('the portal signal failed'));
      await pumpEventQueue();

      // The hide never landed, so the panel is still visible; letting one
      // through gets back to the show arm, which now refuses too.
      panel.hideError = null;
      controller.onHotkeyActivated();
      await pumpEventQueue();
      controller.onHotkeyActivated();
      await pumpEventQueue();

      // The mirror itself refuses. It is read on the decision path, outside
      // the fired future, so it is the one visibility call that would reach
      // the caller — or, from the activations stream, the zone.
      panel.isVisibleError = StateError('the window handle is gone');
      hotkey.press();
      await pumpEventQueue();
      panel.isVisibleError = null;

      hotkey.cancelError = StateError('the portal session refused to close');
      await controller.dispose();
      hotkey.cancelError = null;
      await hotkey.dispose();
      panel.dispose();
    }, (error, stack) => unhandled.add(error));

    expect(unhandled, isEmpty);
    expect(
      logger.lines.map((line) => line.message),
      containsAll([
        contains('rejected show'),
        contains('rejected hide'),
        contains('activation stream errored'),
        contains('visibility mirror failed'),
        contains('cancelling the hotkey activation subscription failed'),
      ]),
    );
  });

  test('CAP-1: the settings controller survives mutations in which every '
      'port it calls fails (AD-12, AD-13)', () async {
    final unhandled = <Object>[];
    final logger = FakeLogger();

    await runZonedGuarded(() async {
      final configStore = FakeConfigStore(current: _config)
        ..writeError = StateError('config.json is read-only');
      final hotkey = FakeGlobalHotkey()
        ..bindError = StateError('the portal request timed out');
      final controller = SettingsController(
        configStore: configStore,
        registrableKeys: _registrableKeys,
        hotkey: hotkey,
        logger: logger,
      );

      configStore.emitChangesError(StateError('the config watcher failed'));
      await pumpEventQueue();

      await controller.changeHotkey(_altSpace);
      await controller.changeActivePreset('fast-preset');
      await pumpEventQueue();

      configStore.cancelError = StateError('the file watcher will not close');
      await controller.dispose();
      configStore.cancelError = null;
      configStore.dispose();
    }, (error, stack) => unhandled.add(error));

    expect(unhandled, isEmpty);
    expect(
      logger.lines.map((line) => line.message),
      containsAll([
        contains('change stream errored'),
        contains('hotkey backend threw'),
        contains('config write failed'),
        contains('cancelling the config subscription failed'),
      ]),
    );
  });
}

const Preset _preset = Preset(
  id: 'default-formal-casual-shorter',
  providerId: 'claude-agent-sdk',
  model: 'claude-sonnet-5',
  systemPrompt: 'correct the text',
);

const Preset _fastPreset = Preset(
  id: 'fast-preset',
  providerId: 'claude-agent-sdk',
  model: 'claude-haiku-4-5-20251001',
  systemPrompt: 'correct the text',
);

final HotkeyBinding _altSpace = HotkeyBinding(
  modifiers: {HotkeyModifier.alt},
  key: 'Space',
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

/// The vocabulary the composition root injects, so these rows validate against
/// the one this build actually ships rather than a hand-built stand-in. A test
/// may name the catalogue; AD-1's scans cover `lib/src/` only, and the whole
/// point of the seam is that nothing under `lib/src/application/` can.
final RegistrableKeys _registrableKeys = HotkeyKeyCatalogue.registrableKeys();
