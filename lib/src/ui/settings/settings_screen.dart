import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/composition/controller_providers.dart';
import '../../application/composition/port_providers.dart';
import '../../application/settings_controller.dart';
import '../../application/settings_state.dart';
import '../../domain/config/provider_config.dart';
import '../../domain/hotkey/global_hotkey.dart';
import '../../domain/hotkey/hotkey_bind_outcome.dart';
import '../../domain/hotkey/hotkey_binding.dart';
import '../../domain/logger.dart';
import 'hotkey_capture_field.dart';
import 'hotkey_status_view.dart';
import 'preset_choice_list.dart';
import 'settings_failure_notice.dart';
import 'settings_pending_notice.dart';

/// The in-app settings surface: hotkey, active preset, and provider settings
/// (CAP-8, CAP-12).
///
/// One surface, one owner. Every mutation is one of `SettingsController`'s
/// methods, so AD-13's write-through to the config file holds by construction —
/// no widget here opens the config file, and nothing on this screen holds a
/// setting the config file does not. What this widget owns is only ephemeral UI:
/// subscriptions, the last state it rendered, and the capture-field generation.
/// Whether a mutation is in flight is deliberately **not** among them — see
/// [_changeHotkey].
///
/// Nothing here shows or hides the window (AD-4, AD-8). Reaching this screen is a
/// view swap inside the already-built tree, decided by `DaemonHome`, and [onBack]
/// is how this screen asks for the panel again rather than routing or popping.
///
/// The whole body scrolls, because no code sets a size or a minimum size for the
/// toplevel (deferred work) and a user can drag it to any height — the same
/// honest degradation the panel makes for the same reason.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({required this.onBack, super.key});

  /// Asks for the panel back. Owned by the view switch above, so this screen
  /// never decides what replaces it.
  final VoidCallback onBack;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Read once: `settingsControllerProvider` is a plain `Provider` whose value
  /// never changes in today's graph, and reading it is also what guarantees the
  /// controller — and so its config and binding-change subscriptions — exists.
  late final SettingsController _controller;

  /// The one port this widget reaches for, and only to report the two things
  /// that would otherwise be silent: a state stream that errors or ends.
  late final Logger _logger;

  late final StreamSubscription<SettingsState> _changes;
  late final StreamSubscription<void> _focusLosses;

  late SettingsState _state;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  bool _baseUrlChangedWhileEditing = false;
  bool _modelChangedWhileEditing = false;
  String _keySourceLabel = 'None configured';
  int _sourceGeneration = 0;
  int _captureGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(settingsControllerProvider);
    _logger = ref.read(loggerProvider);
    // The snapshot first, then the subscription: both in this one synchronous
    // step, so no state can be emitted between them and go unrendered.
    _state = _controller.state;
    _baseUrlController = TextEditingController(text: _state.compatibleBaseUrl);
    _modelController = TextEditingController(
      text: _state.compatiblePreset?.model ?? '',
    );
    unawaited(_refreshKeySource());
    _changes = _controller.changes.listen(
      _onStateChanged,
      onError: _onStateStreamError,
      onDone: _onStateStreamClosed,
    );
    _focusLosses = ref
        .read(panelControllerProvider)
        .focusLosses
        .listen(
          (_) => _discardDraft(),
          onError: (Object error) =>
              _report('the settings focus-loss stream errored', error),
        );
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    unawaited(_focusLosses.cancel());
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  /// Recreating the capture field abandons its ephemeral key combination and
  /// seeds the replacement from the controller's current committed binding.
  /// A view swap does the same by unmounting this entire screen.
  void _discardDraft() => setState(() => _captureGeneration++);

  void _onStateChanged(SettingsState state) {
    final previous = _state;
    setState(() {
      _state = state;
      if (previous.mutationInFlight &&
          !state.mutationInFlight &&
          state.hotkeyBindOutcome is HotkeyRetained) {
        _captureGeneration++;
      }
      _syncBaseUrl(previous, state);
      _syncModel(previous, state);
    });
    if (previous.config != state.config) unawaited(_refreshKeySource());
  }

  void _syncBaseUrl(SettingsState previous, SettingsState current) {
    final oldValue = previous.compatibleBaseUrl;
    final newValue = current.compatibleBaseUrl;
    if (oldValue != newValue && _baseUrlController.text == oldValue) {
      _baseUrlController.text = newValue;
    } else if (oldValue != newValue && _baseUrlController.text != newValue) {
      _baseUrlChangedWhileEditing = true;
    }
    if (_baseUrlController.text == newValue) {
      _baseUrlChangedWhileEditing = false;
    }
  }

  void _syncModel(SettingsState previous, SettingsState current) {
    final oldPreset = previous.compatiblePreset;
    final newPreset = current.compatiblePreset;
    final newValue = newPreset?.model ?? '';
    if (oldPreset?.id != newPreset?.id) {
      _modelController.text = newValue;
      _modelChangedWhileEditing = false;
      return;
    }
    if (oldPreset?.model != newPreset?.model &&
        _modelController.text == (oldPreset?.model ?? '')) {
      _modelController.text = newValue;
    } else if (oldPreset?.model != newPreset?.model &&
        _modelController.text != newValue) {
      _modelChangedWhileEditing = true;
    }
    if (_modelController.text == newValue) {
      _modelChangedWhileEditing = false;
    }
  }

  void _onProviderDraftChanged() => setState(() {
    if (_baseUrlController.text == _state.compatibleBaseUrl) {
      _baseUrlChangedWhileEditing = false;
    }
    if (_modelController.text == (_state.compatiblePreset?.model ?? '')) {
      _modelChangedWhileEditing = false;
    }
  });

  Future<void> _refreshKeySource() async {
    final generation = ++_sourceGeneration;
    final label = await _controller.keySourceLabel();
    if (!mounted || generation != _sourceGeneration) return;
    setState(() => _keySourceLabel = label);
  }

  void _onStateStreamError(Object error) {
    // The last rendered state stays: an error on this stream says nothing about
    // what the settings hold, and blanking the screen would discard the one
    // report of a failed mutation the user has.
    _report('the settings state stream errored', error);
  }

  void _onStateStreamClosed() {
    // Only `SettingsController.dispose()` closes it, which happens during
    // shutdown with the window already unmapped — a line for an operator, not a
    // state to render.
    _report(
      'the settings state stream closed while the settings screen was mounted',
      null,
    );
  }

  /// Emits a line without letting the logger's own failure escape — the ui-ring
  /// instance of the swallow `correction_controller.dart` documents.
  void _report(String message, Object? error) {
    try {
      _logger.error(
        message,
        // Type only. A caught error's `toString()` routinely carries the payload
        // that caused it, and on this surface that payload is a config value.
        context: error == null
            ? null
            : {'error_type': error.runtimeType.toString()},
      );
    } on Object {
      // Nowhere left to report this: the reporting channel is what broke.
    }
  }

  /// Issues a mutation. The in-flight bookkeeping is deliberately not here.
  ///
  /// `SettingsController` owns the one mutation slot and refuses a second while
  /// one is in flight, and it has to: this screen is unmounted by its own Back
  /// affordance and by a summon returning to the panel, so a flag it owned would
  /// be destroyed mid-mutation — Apply, Back, reopen, Apply would then issue two
  /// binds with the first still parked on a portal dialog. What is left here is
  /// the affordance: the controls read [SettingsState.mutationInFlight] and go
  /// disabled, and the pending notice says why.
  ///
  /// Discarded visibly (AGENTS.md §6): the controller reports every failure as a
  /// value on its own state stream (AD-13), so there is nothing for this call
  /// site to await or recover.
  void _changeHotkey(HotkeyBinding binding) =>
      unawaited(_controller.changeHotkey(binding));

  void _changePreset(String presetId) =>
      unawaited(_controller.changeActivePreset(presetId));

  void _saveProviderSettings() => unawaited(
    _controller.changeProviderSettings(
      baseUrl: _baseUrlController.text,
      model: _modelController.text,
    ),
  );

  bool get _providerSaveEnabled =>
      !_state.mutationInFlight &&
      _state.compatiblePreset != null &&
      _baseUrlController.text.trim().isNotEmpty &&
      _modelController.text.trim().isNotEmpty &&
      ProviderConfig.baseUrlProblem(_baseUrlController.text) == null;

  /// Who owns the binding, as the *returned* outcome states it — null when no
  /// backend has answered, so the field claims neither regime (AD-10).
  BindingAuthority? get _authority => switch (_state.hotkeyBindOutcome) {
    HotkeyBound(:final registration) => registration.authority,
    HotkeyRetained(:final registration) => registration.authority,
    HotkeyUnavailable() => null,
    null => null,
  };

  /// A structured backend result wins over the saved preference. When Wayland
  /// supplies only localized wording, the status view shows that wording and
  /// the capture field can only seed from the stored restart preference.
  HotkeyBinding get _captureBinding => switch (_state.hotkeyBindOutcome) {
    HotkeyBound(:final registration) =>
      registration.effective ?? _state.config.hotkeyBinding,
    HotkeyRetained(:final registration) =>
      registration.effective ?? _state.config.hotkeyBinding,
    HotkeyUnavailable() || null => _state.config.hotkeyBinding,
  };

  @override
  Widget build(BuildContext context) {
    final failure = _state.failure;
    final config = _state.config;
    final pending = _state.mutationInFlight;
    final enabled = !pending;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('Settings'),
      ),
      // The two notices sit **outside** the scroll view, and that is the whole
      // reason this body is a Column rather than one scrolling child. Nothing
      // sizes this window (deferred work), so the body really does scroll, and a
      // user scrolled down to the preset list would otherwise have the one report
      // that their change did not land rendered off-screen — a failure notice
      // nobody sees is the defect it exists to fix.
      //
      // **And they are capped at half the body, because pinning them cost the
      // other half of the screen.** Measured, not anticipated: at 420x160 with
      // both notices up the `Expanded` below resolved to *zero* height — the
      // status view, the hotkey field and the preset list were all unreachable —
      // and the Column overflowed by 28px on top of that. Two fixed-height
      // siblings of the only flexible child will do that on any window short
      // enough, and a user can drag this one to any height at all. The cap keeps
      // the notices visible (their whole point) while guaranteeing the controls
      // at least half the body; a notice taller than its share scrolls inside its
      // own band rather than eating into the controls'.
      //
      // **The failure is first inside the band, and the order is the point.**
      // Capping the band reintroduced the very clipping the hoist above fixed,
      // one level down: with both notices up the second one is what falls past
      // the cap, and that band scrolls with nothing to indicate there is
      // anything below it. Measured at 420x160 with the pending notice first,
      // *zero* of the failure notice's 80px was inside the visible band — on the
      // retry path, which is exactly when both are up (a mutation reissued after
      // a failure carries the failure forward). The pending notice restates what
      // the disabled controls already show; the failure notice is the only report
      // that a change did not land, so it takes the top of the band.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final noticeCeiling = constraints.maxHeight / 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pending || failure != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: noticeCeiling),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (failure != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                            child: SettingsFailureNotice(failure: failure),
                          ),
                        if (pending)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                            child: SettingsPendingNotice(),
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HotkeyStatusView(
                          outcome: _state.hotkeyBindOutcome,
                          backendDescription: _state.hotkeyBackendDescription,
                          preference: config.hotkeyBinding,
                        ),
                        const SizedBox(height: 12),
                        HotkeyCaptureField(
                          key: ValueKey(_captureGeneration),
                          binding: _captureBinding,
                          authority: _authority,
                          enabled: enabled,
                          // Supplied by the controller (DW-71), never reached
                          // for: the key vocabulary is built at the composition
                          // root, because AD-1 forbids this ring importing the
                          // infrastructure catalogue that holds it.
                          validator: _controller.captureValidator,
                          onApply: _changeHotkey,
                        ),
                        const Divider(height: 24),
                        PresetChoiceList(
                          presets: config.presets,
                          activePresetId: config.activePresetId,
                          enabled: enabled,
                          onSelect: _changePreset,
                        ),
                        const Divider(height: 24),
                        Text(
                          'OpenAI-compatible provider',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _baseUrlController,
                          onChanged: (_) => _onProviderDraftChanged(),
                          decoration: InputDecoration(
                            labelText: 'Base URL',
                            errorText: _baseUrlController.text.trim().isEmpty
                                ? 'Required'
                                : ProviderConfig.baseUrlProblem(
                                    _baseUrlController.text,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _modelController,
                          onChanged: (_) => _onProviderDraftChanged(),
                          decoration: InputDecoration(
                            labelText: 'Model',
                            errorText: _modelController.text.trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_baseUrlChangedWhileEditing ||
                            _modelChangedWhileEditing)
                          const Text(
                            'Provider settings changed while you were editing. '
                            'Saving will replace those changes with your draft.',
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed: _providerSaveEnabled
                                ? _saveProviderSettings
                                : null,
                            child: const Text('Save provider settings'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('API key source: $_keySourceLabel'),
                        if (_keySourceLabel == 'Config file')
                          const Text(
                            'This API key is stored as plaintext in config.json. '
                            'Move it to your system keyring or environment.',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
