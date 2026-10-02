import 'package:hotkey_grammar_corrector/src/domain/config/app_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/config/provider_config.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/correction_provider.dart';
import 'package:hotkey_grammar_corrector/src/domain/correction/preset.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:test/test.dart';

import 'fakes/fake_clipboard_port.dart';
import 'fakes/fake_clock.dart';
import 'fakes/fake_config_store.dart';
import 'fakes/fake_correction_provider.dart';
import 'fakes/fake_correction_repository.dart';
import 'fakes/fake_global_hotkey.dart';
import 'fakes/fake_logger.dart';
import 'fakes/fake_panel_visibility.dart';
import 'fakes/fake_provider_key_writer.dart';
import 'fakes/fake_tray_port.dart';

/// Smoke test only: constructs one fake per domain port (AGENTS.md §4.1) so
/// `dart test` exercises them. Behaviour tests are out of this slice.
void main() {
  test('every domain port has a constructible fake', () {
    const preset = Preset(
      id: 'default-formal-casual-shorter',
      providerId: 'claude-agent-sdk',
      model: 'claude-sonnet-5',
      systemPrompt: 'correct the text',
    );
    final config = AppConfig(
      providers: {'claude-agent-sdk': ProviderConfig(settings: {})},
      presets: [preset],
      activePresetId: 'default-formal-casual-shorter',
      hotkeyBinding: HotkeyBinding(
        modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
        key: 'G',
      ),
    );

    final fakes = [
      FakeCorrectionProvider(script: const []),
      FakeGlobalHotkey(),
      FakePanelVisibility(),
      FakeClipboardPort(),
      FakeTrayPort(),
      FakeCorrectionRepository(),
      FakeConfigStore(current: config),
      FakeProviderKeyWriter(),
      FakeClock(),
      FakeLogger(),
    ];

    expect(fakes, hasLength(10));
    expect(fakes.whereType<CorrectionProvider>(), hasLength(1));
  });
}
