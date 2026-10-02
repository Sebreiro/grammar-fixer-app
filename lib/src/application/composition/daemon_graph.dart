import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/config/app_config.dart';
import '../../domain/config/provider_config.dart';
import '../../domain/config/provider_key_writer.dart';
import '../../domain/correction/correction_provider.dart';
import '../../domain/correction/preset.dart';
import '../../domain/hotkey/hotkey_bind_outcome.dart';
import '../../domain/logger.dart';
import '../../domain/tray/tray_port.dart';
import '../correction_controller.dart';
import '../panel_controller.dart';
import '../panel_close_controller.dart';
import '../settings_controller.dart';
import '../settings_state.dart';
import 'controller_providers.dart';

/// The provider graph as the daemon uses it: built eagerly, torn down in the
/// order shutdown needs.
///
/// This is the container-touching half of the daemon's lifecycle, and it lives
/// here because AD-17 puts Riverpod in `application/` and the spine forbids
/// infrastructure from importing this ring. `DaemonLifecycle` — which owns the
/// order the adapters close in — reaches this only through the callbacks
/// `main.dart` hands it, so neither half has to know the other's imports.
final class DaemonGraph {
  DaemonGraph({
    required this.container,
    required this._logger,
    this.tray,
    this.activePairForConfig,
    this.apiKeySourceLabel,
    this.providerKeyWriter,
    this.onConfigApplied,
  });

  final ProviderContainer container;
  final Logger _logger;
  final TrayPort? tray;
  final ({CorrectionProvider provider, Preset preset}) Function(AppConfig)?
  activePairForConfig;
  final Future<String> Function(ProviderConfig)? apiKeySourceLabel;
  final ProviderKeyWriter? providerKeyWriter;
  final void Function(AppConfig)? onConfigApplied;

  /// The controllers [build] constructed, held rather than re-read.
  ///
  /// Reading a provider *creates* it, so a `container.read` on the teardown
  /// path would build the very controllers it is about to dispose — opening
  /// three port subscriptions in a daemon that is going down. Null until
  /// [build] runs, which is what lets a shutdown racing an aborted startup
  /// tear down nothing instead.
  CorrectionController? _correction;
  PanelController? _panel;
  PanelCloseController? _panelClose;
  SettingsController? _settings;
  StreamSubscription<SettingsState>? _hotkeyStatusChanges;
  Future<void> _trayUpdates = Future<void>.value();

  /// Constructs every controller now, rather than on first read.
  ///
  /// A controller is a subscription: `CorrectionController` has to be
  /// listening to panel visibility before the first show and `PanelController`
  /// to hotkey activations before the first press. Building them lazily would
  /// make the first event the one that creates the listener, and so the one
  /// that is missed.
  void build() {
    _correction = container.read(correctionControllerProvider);
    _panel = container.read(panelControllerProvider);
    _panelClose = container.read(panelCloseControllerProvider);
    _settings = container.read(settingsControllerProvider);
    final keySource = apiKeySourceLabel;
    if (keySource != null) _settings?.attachApiKeySourceLabel(keySource);
    final keyWriter = providerKeyWriter;
    if (keyWriter != null) _settings?.attachProviderKeyWriter(keyWriter);
    _settings?.attachConfigListener(_applyActiveConfig);
    if (tray != null) {
      _hotkeyStatusChanges = _settings?.changes.listen((_) {
        _publishHotkeyStatus();
      });
      _publishHotkeyStatus();
    }
  }

  void _applyActiveConfig(AppConfig config) {
    onConfigApplied?.call(config);
    final resolve = activePairForConfig;
    final correction = _correction;
    if (resolve == null || correction == null) {
      return;
    }
    final pair = resolve(config);
    // The mounted panel keeps this controller. A config commit changes only
    // the pair for future corrections; it never invalidates its provider.
    correction.useActivePair(provider: pair.provider, preset: pair.preset);
  }

  /// Hands the startup bind's outcome to the settings surface (AD-12).
  ///
  /// [build] runs long before the hotkey is bound — a real bind can sit on a
  /// portal dialog for seconds (AD-11) and the window has to be warm first — so
  /// the outcome cannot be a constructor argument and arrives here instead.
  /// Without it the settings screen states "nothing has been requested yet" for
  /// the life of a daemon whose hotkey never bound, which is the half of AD-12
  /// the tray already gets told about.
  ///
  /// A hand-off arriving before [build] is a startup that failed before the
  /// graph existed; there is no surface to tell. Said out loud rather than
  /// dropped: every other swallow in this file logs, and an outcome discarded in
  /// silence is exactly the shape of the gap this method exists to close.
  void applyStartupBindOutcome(HotkeyBindOutcome outcome) {
    final settings = _settings;
    if (settings == null) {
      _log(
        () => _logger.warning(
          'the startup hotkey bind outcome reached no settings surface because '
          'the graph was never built',
          // The type, not the message: an adapter-authored sentence is a value
          // for a surface to render, not a log payload (see the Logger port).
          context: {'outcome': outcome.runtimeType.toString()},
        ),
      );
      return;
    }
    settings.applyStartupOutcome(outcome);
  }

  void _publishHotkeyStatus() {
    final status = _settings?.trayStatus;
    final target = tray;
    if (status == null || target == null) {
      return;
    }
    _trayUpdates = _trayUpdates.then((_) async {
      try {
        await target.setHotkeyStatus(status);
      } on Object catch (error) {
        _log(
          () => _logger.warning(
            'the tray could not show the current hotkey status',
            context: {'error_type': error.runtimeType.toString()},
          ),
        );
      }
    });
    unawaited(_trayUpdates);
  }

  /// Raises the panel without toggling it — AD-14's holder, asked by a later
  /// launch to show what it already has.
  ///
  /// A show request that lands before [build] is a launch racing a launch;
  /// there is no panel yet, so there is nothing to raise.
  void showPanel() => _panel?.showPanel();

  Stream<void> get quitRequests =>
      _panelClose?.quitRequests ?? const Stream<void>.empty();

  /// Disposes the controllers, correction first.
  ///
  /// Correction leads because it is the one that waits: its `dispose()` drains
  /// the CAP-7 history writes still in flight, and draining them while the
  /// rest of the graph is intact is what keeps a terminal event arriving
  /// during shutdown from reaching a half-torn-down surface.
  ///
  /// Each is guarded separately. One controller whose teardown rejects must
  /// not strand the other two — the caller's own guard would stop the whole
  /// step at the first failure.
  Future<void> disposeControllers() async {
    await _dispose(
      'the tray status subscription',
      _hotkeyStatusChanges?.cancel,
    );
    await _dispose('pending tray status updates', () => _trayUpdates);
    await _dispose('the correction controller', _correction?.dispose);
    await _dispose('the panel controller', _panel?.dispose);
    await _dispose('the panel close controller', _panelClose?.dispose);
    await _dispose('the settings controller', _settings?.dispose);
  }

  /// Releases the container. Its `onDispose` hooks call the same idempotent
  /// controller `dispose()`s again, which is the backstop for any path that
  /// never reached [disposeControllers].
  void dispose() => container.dispose();

  /// A null [run] means [build] never got that far, so there is nothing to
  /// tear down — not a step to log as failed.
  Future<void> _dispose(String what, Future<void> Function()? run) async {
    if (run == null) {
      return;
    }
    try {
      await run();
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'disposing $what failed',
          context: {'error_type': error.runtimeType.toString()},
        ),
      );
    }
  }

  /// Emits a log line without letting the logger's own failure escape — see
  /// the canonical note in `correction_controller.dart`.
  void _log(void Function() emit) {
    try {
      emit();
    } on Object {
      // Nowhere left to report this: the reporting channel is what broke.
    }
  }
}
