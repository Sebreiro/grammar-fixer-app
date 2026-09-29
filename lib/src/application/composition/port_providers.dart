/// The composition root's contract (AD-17): one typed seam per port, and
/// nothing else.
///
/// AD-17 puts the Riverpod graph in `application/composition/`, and AD-1
/// forbids this ring from importing `infrastructure/`. The override seam is
/// what reconciles them: every provider here is declared over a *domain* port
/// and throws until it is overridden, and `main.dart` — which lives outside
/// `lib/src/` and so outside the AD-1 gate — is the only file that supplies an
/// override, so it is the only place a concrete adapter is bound to a seam.
///
/// It is not the only file that *names* one: `DaemonStartup` constructs the
/// lock, the config store, the database and the chosen hotkey adapter, because
/// those are startup order rather than wiring and that order has to be
/// testable. What matters for AD-17 is that the binding happens in exactly one
/// place, and `test/architecture/composition_wiring_test.dart` is what holds
/// it there — every seam declared below must appear as an `overrideWithValue`
/// in `main.dart`.
///
/// Throwing, rather than defaulting, is deliberate: a port nobody overrode is
/// a composition mistake, and a mistake that surfaces as a startup failure
/// naming the missing override is worth far more than a silent null or a stub
/// that quietly does nothing all day.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/clipboard/clipboard_port.dart';
import '../../domain/clock.dart';
import '../../domain/config/config_store.dart';
import '../../domain/correction/correction_provider.dart';
import '../../domain/correction/preset.dart';
import '../../domain/history/correction_repository.dart';
import '../../domain/hotkey/global_hotkey.dart';
import '../../domain/hotkey/registrable_keys.dart';
import '../../domain/logger.dart';
import '../../domain/panel/panel_visibility.dart';
import '../../domain/tray/tray_port.dart';

/// Structured stderr lines (Consistency Conventions). The one port every
/// guard in the application ring recovers through.
final loggerProvider = Provider<Logger>(
  (ref) => throw UnimplementedError('main.dart must override loggerProvider'),
);

/// The single source of time; nothing else calls `DateTime.now()`.
final clockProvider = Provider<Clock>(
  (ref) => throw UnimplementedError('main.dart must override clockProvider'),
);

/// AD-13's sole owner of the config file, already loaded — the controllers
/// read `current` at construction.
final configStoreProvider = Provider<ConfigStore>(
  (ref) =>
      throw UnimplementedError('main.dart must override configStoreProvider'),
);

final clipboardProvider = Provider<ClipboardPort>(
  (ref) =>
      throw UnimplementedError('main.dart must override clipboardProvider'),
);

final panelVisibilityProvider = Provider<PanelVisibility>(
  (ref) => throw UnimplementedError(
    'main.dart must override panelVisibilityProvider',
  ),
);

/// Exactly one adapter, chosen once from the display server at startup — there
/// is no runtime switch (AD-9).
final globalHotkeyProvider = Provider<GlobalHotkey>(
  (ref) =>
      throw UnimplementedError('main.dart must override globalHotkeyProvider'),
);

final trayProvider = Provider<TrayPort>(
  (ref) => throw UnimplementedError('main.dart must override trayProvider'),
);

/// CAP-7 history behind its port; nothing above this sees a database row.
final correctionRepositoryProvider = Provider<CorrectionRepository>(
  (ref) => throw UnimplementedError(
    'main.dart must override correctionRepositoryProvider',
  ),
);

/// The active provider of AD-5's single pair. Resolved at the composition
/// root from config, and injected — nothing below selects a provider.
final activeCorrectionProviderProvider = Provider<CorrectionProvider>(
  (ref) => throw UnimplementedError(
    'main.dart must override activeCorrectionProviderProvider',
  ),
);

/// The keys this build can register as a shortcut (HOTKEY-04, DW-71).
///
/// Not a port, and the one seam here that is not: it is a *value* the
/// composition root derives from the infrastructure key catalogue, which AD-1
/// forbids both this ring and `ui` from importing. Declaring it over the domain
/// type is what keeps the declaration itself legal — a provider declared over
/// the catalogue's own type would need that import to name its own parameter
/// and would fail the gate on this line, which is why neither the type nor its
/// name appears anywhere under `lib/src/application/`. DW-71's "supplied by
/// `SettingsController`" is satisfied by injection: the controller holds what
/// `main.dart` built.
final registrableKeysProvider = Provider<RegistrableKeys>(
  (ref) => throw UnimplementedError(
    'main.dart must override registrableKeysProvider',
  ),
);

/// The active preset of AD-5's single pair — prompt and model together, never
/// a model id on its own.
final activePresetProvider = Provider<Preset>(
  (ref) =>
      throw UnimplementedError('main.dart must override activePresetProvider'),
);
