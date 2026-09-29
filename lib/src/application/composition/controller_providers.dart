/// The three controllers, built from the port seams next door (AD-17).
///
/// Each registers `ref.onDispose`, so no path that disposes the container can
/// leak a controller — including a test that never reaches `main.dart`'s
/// teardown. That is a backstop, not the shutdown order: `main.dart` awaits
/// each `dispose()` in the order the daemon needs (a pending history write is
/// waited for before the database closes) and only then disposes the
/// container, which is why every controller's `dispose()` is idempotent.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/logger.dart';
import '../correction_controller.dart';
import '../panel_controller.dart';
import '../settings_controller.dart';
import 'port_providers.dart';

/// Owns one panel session: seed, run, stream, retry, persist (AD-18).
///
/// These ports are fixed for the container's lifetime. Reading them without
/// watching them keeps config changes from disposing the warm panel's
/// controller; [DaemonGraph] updates its active provider/preset pair in place.
final correctionControllerProvider = Provider<CorrectionController>((ref) {
  final logger = ref.read(loggerProvider);
  final controller = CorrectionController(
    clipboard: ref.read(clipboardProvider),
    // The graph updates this stable controller when config commits. Watching
    // either startup value would rebuild it and discard an in-flight run.
    provider: ref.read(activeCorrectionProviderProvider),
    preset: ref.read(activePresetProvider),
    repository: ref.read(correctionRepositoryProvider),
    clock: ref.read(clockProvider),
    logger: logger,
    panelVisibility: ref.read(panelVisibilityProvider),
  );
  _disposeWith(ref, logger, 'CorrectionController', controller.dispose);
  return controller;
});

/// The hotkey toggle, and nothing else (AD-8).
final panelControllerProvider = Provider<PanelController>((ref) {
  final logger = ref.watch(loggerProvider);
  final controller = PanelController(
    visibility: ref.watch(panelVisibilityProvider),
    hotkey: ref.watch(globalHotkeyProvider),
    logger: logger,
  );
  _disposeWith(ref, logger, 'PanelController', controller.dispose);
  return controller;
});

/// The settings surface and its write-through to config (AD-13).
final settingsControllerProvider = Provider<SettingsController>((ref) {
  final logger = ref.watch(loggerProvider);
  final controller = SettingsController(
    configStore: ref.watch(configStoreProvider),
    hotkey: ref.watch(globalHotkeyProvider),
    registrableKeys: ref.watch(registrableKeysProvider),
    logger: logger,
  );
  _disposeWith(ref, logger, 'SettingsController', controller.dispose);
  return controller;
});

/// Registers [dispose] as the provider's teardown without dropping its result.
///
/// `ref.onDispose` takes a `void Function()`, and every controller's
/// `dispose()` returns a `Future`. Handing it over directly type-checks and
/// discards both the wait and any rejection — so a teardown that fails on the
/// container-only path (an aborted startup, or a test that disposes without
/// going through `DaemonGraph`) surfaces as an unhandled async error instead
/// of the log line every other teardown step produces. This is the backstop,
/// not the shutdown order: `DaemonGraph.disposeControllers` still awaits each
/// one in the order the daemon needs.
///
/// [logger] is captured now rather than read back inside the callback: by the
/// time a teardown runs, reading another provider off a disposing container is
/// itself a way to fail.
void _disposeWith(
  Ref ref,
  Logger logger,
  String what,
  Future<void> Function() dispose,
) {
  ref.onDispose(() {
    unawaited(
      dispose().catchError((Object error) {
        logger.error(
          'disposing $what from the container teardown failed',
          context: {'error_type': error.runtimeType.toString()},
        );
      }),
    );
  });
}
