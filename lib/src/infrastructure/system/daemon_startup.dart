import 'dart:io';

import '../../domain/hotkey/global_hotkey.dart';
import '../../domain/hotkey/hotkey_bind_outcome.dart';
import '../../domain/hotkey/hotkey_binding.dart';
import '../../domain/logger.dart';
import '../../domain/tray/tray_port.dart';
import '../config/app_paths.dart';
import '../config/default_app_config.dart';
import '../config/json_config_store.dart';
import '../correction/active_correction.dart';
import '../correction/api_key_resolver.dart';
import '../correction/provider_registry.dart';
import '../correction/secret_service_secret_store.dart';
import '../hotkey/display_server.dart';
import '../hotkey/hotkey_registrar.dart';
import '../hotkey/portal_app_id_regime.dart';
import '../hotkey/wayland_portal_global_hotkey.dart';
import '../hotkey/x11_global_hotkey.dart';
import '../panel/absent_keyboard_focus_witness.dart';
import '../panel/keyboard_focus_witness.dart';
import '../panel/x11_keyboard_focus_witness.dart';
import '../persistence/app_database.dart';
import 'single_instance_lock.dart';

/// Everything the daemon builds before Flutter is involved, and the order it
/// builds it in.
///
/// This is composition-root work, kept out of `main.dart`'s body for one
/// reason: `main.dart` cannot be executed by a test — it needs a binding, a
/// window and a display — while every decision here is pure `dart:io` and can
/// be. The startup *ordering* AD-14 mandates is therefore observable rather
/// than merely readable: the lock is acquired before the config file is
/// touched, before the history database is opened, before a provider is
/// resolved, and before a hotkey adapter exists.
///
/// `main.dart` remains the only place that installs the Riverpod graph, the
/// window and the signal handlers — the parts that genuinely need a platform.
final class DaemonStartup {
  DaemonStartup._({
    required this.lock,
    required this.configStore,
    required this.database,
    required this.hotkey,
    required this.focusWitness,
    required this.active,
    required this.apiKeyResolver,
    required this.logger,
  });

  /// Runs the pre-Flutter half of startup.
  ///
  /// Returns null when this process is **not** the daemon (AD-14): another
  /// instance holds the address and has been asked to show its panel, and
  /// nothing else has been built — no config file read or seeded, no database
  /// opened, no provider resolved, no hotkey adapter constructed. The caller
  /// must then exit 0 (and, under Flutter, must do so explicitly: returning
  /// from `main` leaves the embedder's loop running).
  ///
  /// Never throws for a degraded environment. An unusable lock address and a
  /// malformed config file are both warnings on the [Logger] followed by a
  /// daemon that starts anyway (AD-14, AD-13) — a resident daemon that
  /// refuses to start leaves the user no surface on which to fix it.
  ///
  /// [registrar] is the X11 key-grab seam, built by the composition root
  /// because that is where vendor objects are built. AD-9's *selection* stays
  /// here, where a test can drive both environment branches without a binding;
  /// what is injected is only the backend the X11 branch would otherwise have
  /// to construct — and constructing it would put a Flutter import on this
  /// file's import graph, which `dart test` cannot resolve. The Wayland branch
  /// ignores it.
  ///
  /// [portalAppIdRegime] is the mirror image: the answer is resolved by the
  /// composition root, because deciding it needs a filesystem probe and this
  /// class takes an injected [environment] precisely so it needs none. The X11
  /// branch ignores it, the same way the Wayland branch ignores [registrar].
  ///
  /// [requestTimeout] is the composition root's single budget for a platform
  /// call that never settles, passed through to the Wayland adapter so that one
  /// number is argued with in one place (D-17). The X11 branch ignores it too:
  /// an `XGrabKey` is a synchronous round trip to the X server, not a request a
  /// desktop portal may sit on.
  static Future<DaemonStartup?> begin({
    required AppPaths paths,
    required Map<String, String> environment,
    required Logger logger,
    required HotkeyRegistrar registrar,
    required PortalAppIdRegime portalAppIdRegime,
    required Duration requestTimeout,
  }) async {
    final lock = SingleInstanceLock(paths: paths);
    try {
      // This warning and acquire can fail before the startup object exists.
      // Own the lock first so even a throw after binding releases the address.
      final pathsWarning = paths.warning;
      if (pathsWarning != null) {
        logger.warning(pathsWarning);
      }
      if (!await _isTheDaemon(lock, logger)) {
        return null;
      }

      // Past this line the AD-14 address is held, so every remaining step
      // owes it back on failure.
      final configStore = JsonConfigStore(
        paths: paths,
        defaults: DefaultAppConfig.build(),
      );
      // AD-13: the store is the only reader of the file, and a malformed one
      // surfaces its warning here rather than failing startup.
      final loadResult = await configStore.load();
      final loadWarning = loadResult.warning;
      if (loadWarning != null) {
        final errorType = loadResult.warningErrorType;
        logger.warning(
          loadResult.logWarning ?? loadWarning,
          context: errorType == null ? null : {'error_type': errorType},
        );
      }

      // AD-9: exactly one adapter, chosen once. Nothing reads the display
      // server again after this line — which is why it is read into a local
      // and handed to both choices below rather than called twice. The witness
      // is a second consumer of the *same* answer, not a second question.
      final displayServer = DisplayServer.fromEnvironment(environment);
      final apiKeyResolver = ApiKeyResolver(
        const SecretServiceSecretStore(),
        environment,
      );

      return DaemonStartup._(
        lock: lock,
        configStore: configStore,
        database: AppDatabase.file(File(paths.databaseFile)),
        hotkey: _hotkeyFor(
          displayServer,
          registrar: registrar,
          appIdRegime: portalAppIdRegime,
          requestTimeout: requestTimeout,
          logger: logger,
        ),
        focusWitness: _focusWitnessFor(displayServer),
        // AD-5: the single active pair, resolved through AD-15's registry map.
        active: ActiveCorrection.resolve(
          config: configStore.current,
          registry: ProviderRegistry(
            logger: logger,
            apiKeyResolver: apiKeyResolver,
          ),
          logger: logger,
        ),
        apiKeyResolver: apiKeyResolver,
        logger: logger,
      );
    } on Object {
      await _releaseAfterFailedStartup(lock, logger);
      rethrow;
    }
  }

  /// Hands the AD-14 address back after a startup that took it and then failed.
  ///
  /// Never throws: it runs on the way out of an error that is already being
  /// propagated, and a second failure here must not replace the first.
  static Future<void> _releaseAfterFailedStartup(
    SingleInstanceLock lock,
    Logger logger,
  ) async {
    try {
      await lock.dispose();
    } on Object catch (error) {
      logger.error(
        'could not release the single-instance address after a failed startup',
        context: {'error_type': error.runtimeType.toString()},
      );
    }
  }

  /// Held for the life of the daemon; [SingleInstanceLock.showRequests] is how
  /// a later launch reaches the resident panel (AD-14).
  final SingleInstanceLock lock;

  /// AD-13's single owner of the config file, already loaded.
  final JsonConfigStore configStore;

  /// CAP-7 history. Its background isolate outlives `main` unless closed.
  final AppDatabase database;

  /// The one hotkey adapter this session gets (AD-9).
  final GlobalHotkey hotkey;

  /// Whether a focus-out actually moved the keyboard, for the display server
  /// this session is on (G-01-13).
  ///
  /// Chosen here rather than in `main.dart` because it is decided by the *same*
  /// one-time display-server read AD-9's adapter choice is, and putting the two
  /// answers in two places is how a second read would arrive. Handed to
  /// `WindowManagerPanelVisibility`, which owns it and disposes it — nothing
  /// here closes it, so there is exactly one disposer.
  final KeyboardFocusWitness focusWitness;

  /// AD-5's `(CorrectionProvider, Preset)` pair.
  final ActiveCorrection active;
  final ApiKeyResolver apiKeyResolver;

  final Logger logger;

  /// Requests the configured combination and tells the tray what came back.
  ///
  /// AD-12 makes "no backend would take this binding" a state both the tray
  /// and the settings screen render, never an exception — so an unavailable
  /// hotkey leaves the daemon up with the tray menu as the way in. The tray
  /// call is guarded because a tray that cannot show the state must not be
  /// the thing that stops startup either; the rejection is logged so the
  /// missing half of AD-12 is visible rather than silent.
  Future<HotkeyBindOutcome?> bindHotkey({
    required TrayPort tray,
    Future<void>? stopRequested,
    bool Function()? isStopping,
  }) async {
    if (isStopping?.call() ?? false) {
      return null;
    }
    final binding = requestBinding(
      hotkey: hotkey,
      binding: configStore.current.hotkeyBinding,
      logger: logger,
    );
    final outcome = stopRequested == null
        ? await binding
        : await Future.any<HotkeyBindOutcome?>([
            binding,
            stopRequested.then<HotkeyBindOutcome?>((_) => null),
          ]);
    if (outcome == null || (isStopping?.call() ?? false)) {
      return null;
    }
    final unavailable = outcome is HotkeyUnavailable;
    if (unavailable) {
      logger.warning(
        'global hotkeys are unavailable; the tray menu is the way in',
        context: {'message': outcome.message},
      );
    }
    try {
      await tray.setHotkeyUnavailable(unavailable);
    } on Object catch (error) {
      logger.warning(
        'the tray could not be told whether hotkeys are available',
        context: {'error_type': error.runtimeType.toString()},
      );
    }
    return (isStopping?.call() ?? false) ? null : outcome;
  }

  /// Requests [binding] from [hotkey], reducing every way that can go wrong to
  /// a value (AD-12).
  ///
  /// AD-12 says a backend that cannot bind resolves to [HotkeyUnavailable] and
  /// never rejects, so an adapter that throws is breaking its own contract —
  /// and on this path it would break it during startup, where the rejection
  /// has no caller to catch it, produces no log line and never reaches the
  /// tray. `SettingsController._bind` guards the identical call for the
  /// identical reason; this is the startup twin of it.
  ///
  /// A named static rather than a private step of [bindHotkey], so the breach
  /// it absorbs is reachable by a test without standing up a whole startup —
  /// the shipped adapters honour the contract, so the only way to exercise the
  /// guard is to hand it one that does not.
  static Future<HotkeyBindOutcome> requestBinding({
    required GlobalHotkey hotkey,
    required HotkeyBinding binding,
    required Logger logger,
  }) async {
    try {
      return await hotkey.bind(binding);
    } on Object catch (error) {
      logger.error(
        'the hotkey backend threw instead of reporting unavailability',
        // The type only: a vendor exception's `toString()` routinely carries
        // the payload that caused it (see the Logger port's doc).
        context: {'error_type': error.runtimeType.toString()},
      );
      return const HotkeyUnavailable(
        // An adapter that threw told this backstop nothing about *why*, so the
        // only honest reading is the one this sentence already gives: the
        // backend was not reached. Not [HotkeyUnavailableCause.keyRefused] —
        // nothing here observed a backend working, so inviting the user to try
        // another combination would be a claim this arm cannot support.
        cause: HotkeyUnavailableCause.noBackend,
        message:
            'the hotkey backend could not be reached, so no global shortcut '
            'is registered — the tray menu still opens the panel',
      );
    }
  }

  /// AD-14. True when this process is the daemon: it acquired the address, or
  /// the address is unusable and starting anyway beats refusing to start.
  static Future<bool> _isTheDaemon(
    SingleInstanceLock lock,
    Logger logger,
  ) async {
    final acquisition = await lock.acquire();
    switch (acquisition.status) {
      case SingleInstanceStatus.acquired:
        return true;
      case SingleInstanceStatus.alreadyRunning:
        logger.info('another instance is running; asked it to show its panel');
        return false;
      case SingleInstanceStatus.unavailable:
        logger.warning(
          acquisition.warning ?? 'single-instance enforcement is unavailable',
        );
        return true;
    }
  }

  static GlobalHotkey _hotkeyFor(
    DisplayServer displayServer, {
    required HotkeyRegistrar registrar,
    required PortalAppIdRegime appIdRegime,
    required Duration requestTimeout,
    required Logger logger,
  }) {
    return switch (displayServer) {
      // The registrar is deliberately unused here: it is the X11 key-grab seam,
      // and it is inert until a grab is requested, so a Wayland session pays
      // nothing for having been handed one. The portal adapter builds its own
      // `DBusClient` instead, which is inert in exactly the same way — nothing
      // reaches a bus until the first `bind()` — so an X11 session pays nothing
      // for the arm it did not take either. AD-9 keeps this a single choice made
      // once rather than a negotiation — and the app-id regime is part of that
      // one choice, resolved by the caller before this switch runs.
      DisplayServer.wayland => WaylandPortalGlobalHotkey(
        appIdRegime: appIdRegime,
        requestTimeout: requestTimeout,
        logger: logger,
      ),
      DisplayServer.x11 => X11GlobalHotkey(
        registrar: registrar,
        logger: logger,
      ),
    };
  }

  /// The witness beside the adapter, from the same one display-server read.
  ///
  /// The Wayland arm is the null object, and that is the honest answer rather
  /// than an unimplemented one: the XDG GlobalShortcuts portal takes no key
  /// grab, so the compositor — not this daemon — owns the binding and nothing
  /// the daemon does can produce the spurious `FocusOut(NotifyGrab)` G-01-13 is
  /// about. There is no portal call that reports the keyboard owner either, and
  /// a witness that cannot prove a focus-out spurious must never claim it is.
  ///
  /// Takes no logger, and no request budget: the X11 answer is one synchronous
  /// Xlib call that reports its failures as values, so there is nothing here
  /// for either to carry. The one log line this seam can produce belongs to the
  /// panel adapter's AD-15 backstop, where the throw would be caught.
  static KeyboardFocusWitness _focusWitnessFor(DisplayServer displayServer) {
    return switch (displayServer) {
      DisplayServer.wayland => const AbsentKeyboardFocusWitness(),
      DisplayServer.x11 => X11KeyboardFocusWitness(),
    };
  }
}
