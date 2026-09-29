import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

// Narrowly, because `widgets.dart` re-exports `FlutterError` but neither the
// details type its handler is handed nor the dispatcher that owns the other
// half of the framework's error surface.
import 'package:flutter/foundation.dart'
    show FlutterErrorDetails, PlatformDispatcher;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'src/application/composition/daemon_graph.dart';
import 'src/application/composition/port_providers.dart';
import 'src/domain/clock.dart';
import 'src/domain/logger.dart';
import 'src/domain/tray/tray_port.dart';
import 'src/infrastructure/clipboard/system_clipboard.dart';
import 'src/infrastructure/config/app_paths.dart';
import 'src/infrastructure/correction/active_correction.dart';
import 'src/infrastructure/correction/provider_registry.dart';
import 'src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'src/infrastructure/hotkey/hotkey_registrar.dart';
import 'src/infrastructure/hotkey/portal_app_id_regime.dart';
import 'src/infrastructure/hotkey/x11_key_grab_registrar.dart';
import 'src/infrastructure/panel/window_manager_panel_visibility.dart';
import 'src/infrastructure/panel/window_manager_panel_window.dart';
import 'src/infrastructure/persistence/drift_correction_repository.dart';
import 'src/infrastructure/system/daemon_lifecycle.dart';
import 'src/infrastructure/system/daemon_startup.dart';
import 'src/infrastructure/system/stderr_logger.dart';
import 'src/infrastructure/system/system_clock.dart';
import 'src/infrastructure/tray/tray_manager_tray.dart';
import 'src/infrastructure/tray/tray_manager_tray_icon.dart';
import 'src/ui/daemon_app.dart';
import 'src/ui/panel/correction_panel.dart';

/// The composition root (AD-17): the one file that names a concrete adapter on
/// both sides of every port. It lives outside `lib/src/`, and so outside AD-1's
/// ring gate, which is precisely what lets the Riverpod graph in
/// `application/composition/` declare its seams over domain ports alone.
///
/// Deliberately thin. Everything decidable without a platform lives in a type
/// a test can construct — `DaemonStartup` owns the pre-Flutter startup order
/// (AD-14, AD-13, AD-9, AD-5), `DaemonGraph` the container, `DaemonLifecycle`
/// the teardown order — because nothing in this function is reachable by
/// `dart test` or `flutter test`: it needs a binding, a window and a display.
/// What is left here is exactly what genuinely needs those.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const clock = SystemClock();
  final logger = StderrLogger(clock: clock);
  // Immediately, so the two framework channels are covered for the whole
  // process rather than from `runApp` onwards: a throw inside a widget build
  // or an uncaught async error is reported by the framework, not raised into
  // `main`'s guard, and would otherwise reach `FlutterError.dumpErrorToConsole`
  // — which prints the exception's `toString()`, the one thing the Logger port
  // forbids for a daemon that reads the clipboard.
  _installErrorHandlers(logger);
  // Built above the not-the-daemon branch, unlike the tray seam, because
  // `DaemonStartup.begin` is what chooses the adapter that needs it — and
  // safely so: this construction is *inert*. `TrayManagerTrayIcon()` registers
  // a listener on the `tray_manager` singleton the moment it exists, which is
  // why it must not run in a process on its way out; this one allocates a
  // stream controller and touches nothing else. The registrar opens no library,
  // spawns no isolate and makes no X connection until a grab is requested, so a
  // launch that exits 0 here has cost the session nothing — and neither has a
  // Wayland session, which never asks this arm for a grab at all.
  final hotkeyRegistrar = X11KeyGrabRegistrar();
  DaemonStartup? startup;
  DaemonLifecycle? lifecycle;
  // Capture each resource before the next construction or await can throw.
  // The abort guard also covers begin, before it can return a startup object.
  WindowManagerPanelVisibility? openedPanelVisibility;
  TrayManagerTrayIcon? openedTrayIcon;
  TrayManagerTray? openedTray;
  DaemonGraph? openedGraph;
  try {
    startup = await DaemonStartup.begin(
      paths: AppPaths.fromEnvironment(Platform.environment),
      environment: Platform.environment,
      logger: logger,
      registrar: hotkeyRegistrar,
      // Asked here, once, for the same reason the display server is: it is a fact
      // about how this process was packaged and launched, it cannot change while
      // the daemon runs, and answering it needs a real filesystem probe —
      // `DaemonStartup` takes an injected environment map precisely so that it
      // needs none. Inside a Flatpak the portal derives the application id from
      // the sandbox metadata, so the host registry must not be called at all.
      portalAppIdRegime: PortalAppIdRegime.fromEnvironment(
        Platform.environment,
        fileExists: (path) => File(path).existsSync(),
      ),
      // The third site to take the one bound, and the reason it is stated here
      // rather than inside the adapter: D-17 says a portal that never answers
      // must fail after a few seconds so the settings screen never hangs, and
      // "a few seconds" is the same policy question the panel adapter and the
      // teardown already answered once.
      requestTimeout: _unresponsiveCallBudget,
    );
    if (startup == null) {
      // Returning from main leaves the GTK loop resident after the holder was
      // signalled. A failed exit is caught by this same abort guard.
      exit(0);
    }

    // The address is now held, and every later step shares this guard.
    final trayIcon = TrayManagerTrayIcon();
    openedTrayIcon = trayIcon;
    final tray = TrayManagerTray(icon: trayIcon, logger: logger);
    openedTray = tray;
    // Built here, before the window is prepared and long before `runApp`,
    // because its constructor is what registers the window listener and an
    // event delivered before that reaches nobody. Note the reason is *not*
    // `windowManager.ensureInitialized()`: on Linux that answers a bare `true`
    // and connects nothing, so it orders nothing either.
    final panelVisibility = WindowManagerPanelVisibility(
      window: WindowManagerPanelWindow(),
      // Chosen by `DaemonStartup` from the one display-server read AD-9's
      // hotkey adapter is chosen by, so the two answers cannot disagree. The
      // adapter owns it from here: `dispose()` disposes it, and nothing else
      // closes it.
      focusWitness: startup.focusWitness,
      requestTimeout: _unresponsiveCallBudget,
      logger: logger,
    );
    openedPanelVisibility = panelVisibility;

    final apiKeyResolver = startup.apiKeyResolver;
    final graph = DaemonGraph(
      container: _container(
        startup: startup,
        clock: clock,
        logger: logger,
        tray: tray,
        panelVisibility: panelVisibility,
      ),
      logger: logger,
      tray: tray,
      apiKeySourceLabel: (config) async =>
          (await apiKeyResolver.sourceForSettings(config)).settingsLabel,
      activePairForConfig: (config) {
        final active = ActiveCorrection.resolve(
          config: config,
          registry: ProviderRegistry(
            logger: logger,
            apiKeyResolver: apiKeyResolver,
          ),
          logger: logger,
        );
        return (provider: active.provider, preset: active.preset);
      },
    );
    // Captured before `build()`, not through a `..build()` cascade: a cascade
    // evaluates to the graph only if `build()` returns, so the partial build
    // this local exists for is exactly the case a cascade would leave
    // uncaptured.
    openedGraph = graph;
    graph.build();

    lifecycle = DaemonLifecycle(
      showRequests: startup.lock.showRequests,
      trayRequests: tray.panelRequests,
      onShowRequest: graph.showPanel,
      disposeControllers: graph.disposeControllers,
      disposeGraph: graph.dispose,
      closePanelVisibility: panelVisibility.dispose,
      closeTray: tray.dispose,
      hotkey: startup.hotkey,
      closeHotkeyRegistrar: hotkeyRegistrar.dispose,
      closeDatabase: startup.database.close,
      closeConfigStore: startup.configStore.close,
      closeLock: startup.lock.dispose,
      stepTimeout: _unresponsiveCallBudget,
      logger: logger,
    );
    lifecycle.beginStartup();
    // Installed before the window and the bind, not after: those are the two
    // slowest steps in startup, and a stop signal arriving during either must
    // still reach the ordered teardown rather than killing the daemon with a
    // history write in flight.
    _installSignalHandlers(lifecycle);
    // Immediately after, and for the same reason: the tray menu's Quit entry is
    // the daemon's second exit trigger, and it reaches the identical teardown.
    // The menu it belongs to is not pushed until `tray.install()` further down,
    // so nothing can be picked before this subscription exists — but the
    // ordering is stated here rather than relied on there.
    _installQuitHandler(tray: tray, lifecycle: lifecycle);

    try {
      await _finishStartup(
        graph: graph,
        startup: startup,
        tray: tray,
        lifecycle: lifecycle,
        logger: logger,
      );
    } finally {
      lifecycle.finishStartup();
    }
  } on Object catch (error) {
    await _abort(
      error: error,
      lifecycle: lifecycle,
      graph: openedGraph,
      panelVisibility: openedPanelVisibility,
      trayIcon: openedTrayIcon,
      tray: openedTray,
      hotkeyRegistrar: hotkeyRegistrar,
      startup: startup,
      logger: logger,
    );
  }
}

/// How long startup waits for the engine's first frame before going on without
/// it.
///
/// A number chosen here rather than derived: generous enough that no session
/// which renders at all reaches it — the first frame of this widget tree is
/// milliseconds' work — and short enough that a session which never will still
/// gets a daemon with a tray, a hotkey and a live show-request subscription.
/// Named so that the argument about the number happens in one place.
const Duration _firstFrameBudget = Duration(seconds: 5);

/// How long a single platform call may hold the daemon before it is abandoned.
///
/// One policy, one number, handed to both places that need it: a teardown step
/// in [DaemonLifecycle] and a window call in [WindowManagerPanelVisibility].
/// Both parameters are required precisely so neither adapter can acquire a
/// private default and let the two drift apart.
///
/// The two sides do not budget the same *unit*, and the number is chosen
/// knowing that. On the panel side it bounds one platform call. On the teardown
/// side it bounds one step, which can be a composite — `disposeControllers`
/// awaits every history write still in flight, and disposing the graph runs
/// every `onDispose` hook behind it. A step is the granularity a teardown can
/// actually abandon at, so it is the granularity the bound is stated at.
///
/// Why one number is defensible for both, stated as what it actually costs.
/// The bound is per step and per call, never a total, so each side multiplies
/// it. A teardown that stalls at every step costs this budget once per step in
/// `DaemonLifecycle._run()` — eleven today, so just under a minute, and the
/// figure moves with the step list rather than with this comment. A single
/// `show` request can spend it **twice**, but only against a window that
/// answers the map and then stalls the focus: an unanswered map ends the
/// request instead of going on to `focus()`, so a window that answers nothing
/// costs one budget per press. The panel-side worst case is therefore 10 s per
/// press for a half-responsive window and 5 s for a dead one. Both worst cases
/// are deliberately affordable against the alternative: on the panel side the
/// alternative to a bound is the current forever, where one call that never
/// settles parks the whole request chain and the panel stops responding until
/// the daemon is restarted, and on the teardown side a stop that overruns its
/// supervisor's grace ends in `SIGKILL` — a worse ending than this one, and a
/// *later* one.
///
/// The 90 s that ceiling is argued against is **systemd's stock
/// `DefaultTimeoutStopSec`, not a figure this project's packaging sets**: no
/// `.service` unit ships here, and the daemon is installed as an XDG autostart
/// entry (`linux/packaging/autostart/`). It is used as a reference because it
/// is the most generous grace the daemon is likely to be stopped under; a
/// desktop session's own logout grace can be considerably shorter, which is an
/// argument for the eleven-step worst case being *low*, never for it being
/// affordable because 90 is far away.
///
/// And why it is not smaller: neither side wants a number that fires on a
/// merely slow call. A portal dialog and a drift isolate finishing its last
/// write are both ordinary at second scale.
///
/// Abandoning is not cancelling: Dart cannot stop the call, so the bound stops
/// the daemon *waiting* on it and nothing more.
const Duration _unresponsiveCallBudget = Duration(seconds: 5);

/// The half of startup that needs the platform: the hidden window, the widget
/// tree, the AD-14 show-request subscription, and the hotkey request.
Future<void> _finishStartup({
  required DaemonGraph graph,
  required DaemonStartup startup,
  required TrayPort tray,
  required DaemonLifecycle lifecycle,
  required Logger logger,
}) async {
  if (lifecycle.isShuttingDown) {
    return;
  }
  await _createHiddenWindow();
  if (lifecycle.isShuttingDown) {
    return;
  }
  runApp(
    UncontrolledProviderScope(
      container: graph.container,
      child: const DaemonApp(),
    ),
  );

  // CAP-1 says the window is warm before the first toggle, and `runApp`
  // returning does not say that: it schedules the first frame, it does not
  // wait for one. Until the engine has rendered, a show request would map a
  // toplevel whose widget tree has been built but never laid out or painted.
  //
  // Bounded, because `linux/runner/my_application.cc` realizes the view and
  // never shows the toplevel (AD-8), and an unmapped toplevel is not a
  // configuration in which a begin-frame is owed. An unbounded await on such a
  // session would hold the AD-14 address with no subscription, no tray and no
  // hotkey — the state `_abort` exists to prevent, reached without a throw, so
  // `_abort` would never run. The bound makes the two cases identical wherever
  // a frame is produced and merely honest where one is not: the spine's
  // operational envelope says a missing dependency degrades one capability and
  // never blocks startup, and everything that makes this daemon reachable is
  // still below this line.
  try {
    await WidgetsBinding.instance.endOfFrame.timeout(_firstFrameBudget);
  } on TimeoutException {
    // Through `_log` for the same reason the tray guard is: a broken stderr
    // must not turn the step that promises never to block startup into the
    // one that aborts it.
    _log(
      () => logger.warning(
        'the engine produced no frame within the first-frame budget; starting '
        'anyway, so the first panel toggle may be slower than CAP-1 allows',
        context: {'budget_ms': _firstFrameBudget.inMilliseconds},
      ),
    );
  } on Object catch (error) {
    // The expiry is not the only way out of that await, though it is the only
    // way the *future* fails: `SchedulerBinding.endOfFrame` only ever
    // `complete()`s its completer — there is no `completeError` path — so a
    // binding that cannot schedule a frame hangs, and the hang is what the
    // timeout above covers. What this clause catches is the synchronous half:
    // reading the getter runs `scheduleFrame()`, and a binding that is not in
    // a state to be asked throws out of it before there is a future to await.
    // Without this clause that throw escapes into `main`'s guard and runs
    // `_abort` → exit(1) — making the step whose whole contract is "never
    // blocks startup" the one that ends it, which is the same trap the tray
    // guard below avoids.
    _log(
      () => logger.error(
        'waiting for the engine first frame failed; starting anyway, so the '
        'first panel toggle may be slower than CAP-1 allows',
        context: {'error_type': error.runtimeType.toString()},
      ),
    );
  }

  if (lifecycle.isShuttingDown) {
    return;
  }

  // Only now, because this is what makes a second launch map the window and
  // the mapping path is live now that a real adapter is behind it: a show
  // request arriving before `runApp` would put an untitled, taskbar-listed,
  // widget-tree-less toplevel on screen. It still opens before `bindHotkey`,
  // which can sit on a portal dialog for seconds (AD-11) — a launch during
  // that must be served.
  //
  // Nothing arriving before this line *during startup* is lost.
  // `SingleInstanceLock` holds a pending-show flag that the first subscriber
  // drains (DW-19), so a launch landing during `_createHiddenWindow`, `runApp`
  // or the frame await raises the panel here instead of being dropped. That
  // window is wide — moving this line past `runApp` widened it, and the await
  // above widens it again — and closing it in the lock is what makes both
  // moves affordable. A flag, not a queue: however many launches arrived, the
  // panel comes up once.
  //
  // Startup is the whole of the guarantee, and the qualifier is load-bearing:
  // `showRequests`' own doc names the teardown window it does not cover — a
  // line landing after `shutdown()` cancels this subscription sets a flag
  // nothing is left to drain — and `DaemonLifecycle.start()` after a shutdown
  // is a no-op. A dropped launch during a restart is still a dropped launch.
  lifecycle.start();

  // Before the bind, because `bindHotkey` is what calls `setHotkeyUnavailable`
  // and no menu may be pushed at an indicator that does not exist yet — the
  // native `set_context_menu` dereferences the `AppIndicator*` that `set_icon`
  // creates, with no null check. After `lifecycle.start()`, so the menu's
  // open-panel entry has a subscriber the moment it can be picked.
  //
  // Guarded, because the spine's operational envelope says a missing
  // dependency degrades one capability and never blocks startup.
  //
  // What this guard actually reaches is narrower than "no tray": a *rejection*
  // from the channel — the plugin absent, the channel gone, or `setContextMenu`
  // refused. A session with no StatusNotifier host is **not** among them and
  // never will be through this package: the Linux `set_icon` handler never
  // checks `app_indicator_new`'s result and answers a bare `true` regardless
  // (`tray_manager-0.5.3/linux/tray_manager_plugin.cc:118-129`), so `install()`
  // resolves and this catch does not run. That the indicator is silent on a
  // host-less session is a real gap in AD-12's degradation story and is filed
  // as deferred work; it is not something this guard can close.
  try {
    await tray.install();
  } on Object catch (error) {
    // Through `_log`, not straight at the logger: `StderrLogger` ends in
    // `_sink.writeln`, which throws on a broken stderr — EPIPE or EBADF is
    // ordinary for a systemd-launched daemon whose journal socket went away.
    // That throw would escape into `main`'s catch and run `_abort` → exit(1),
    // making the guard whose whole purpose is "never blocks startup" the thing
    // that aborts it.
    _log(
      () => logger.error(
        // Says only what it knows, in both directions. `bindHotkey` has not
        // run yet, so claiming the hotkey works would contradict the very next
        // line on a session where it does not — and the install may have got
        // as far as creating the indicator before it was refused, so claiming
        // there is no tray menu would be false on exactly the partial-failure
        // path the adapter's `_rendered` split exists to recover from: the
        // `setHotkeyUnavailable` that `bindHotkey` always issues re-pushes the
        // menu one await later.
        'the tray install did not complete; the tray may be absent or showing '
        'no menu, and the panel may still be reachable by the global hotkey '
        'or by launching the app again',
        context: {'error_type': error.runtimeType.toString()},
      ),
    );
  }

  // After `runApp`, because a real backend's bind can sit on a portal dialog
  // for seconds (AD-11) and the window must be warm before then, not after.
  // Its answer goes to the settings surface as well as to the tray: AD-12 names
  // both as consumers of an unavailable hotkey, and this is the ordering that
  // makes the settings half true from the screen's first frame.
  final outcome = await startup.bindHotkey(
    tray: tray,
    stopRequested: lifecycle.stopRequested,
    isStopping: () => lifecycle.isShuttingDown,
  );
  if (outcome != null && !lifecycle.isShuttingDown) {
    graph.applyStartupBindOutcome(outcome);
  }
}

/// Gives up on a startup that failed after the AD-14 address was taken.
///
/// This is the one failure a resident daemon cannot shrug off. Every other
/// degradation here is modelled — an unusable lock, a malformed config, a
/// backend that cannot bind — but a startup step that throws leaves a process
/// holding the singleton address with nothing behind it: no panel, no hotkey,
/// no tray. Every later launch would then be signalled, see `alreadyRunning`,
/// and exit 0 in silence, with no way in at all. So the address goes back, in
/// order, and the exit code says the launch failed.
///
/// What reaches here is the *startup path* failing: the window, the container
/// and its port seams, a controller constructor, the lifecycle. It is not
/// every error a widget can produce. A throw inside a `build()` or a layout is
/// reported to `FlutterError.onError`, which [_installErrorHandlers] points at
/// the logger, and an uncaught async error goes to the platform dispatcher's
/// handler beside it — neither is raised into the guard around this, and
/// neither should be: one screen that fails to build is a degraded surface,
/// not a reason to take down an all-day resident daemon whose hotkey, tray and
/// history still work.
///
/// [lifecycle] is null when the failure landed before it was built. When
/// [startup] has returned, the address and any partially built graph belong to
/// the pre-lifecycle cleanup. When it has not returned, [DaemonStartup.begin]
/// releases its own lock and only the registrar belongs to this caller.
///
/// [trayIcon] and [tray] are separate parameters because the failure can land
/// between their two constructors. [tray] owns [trayIcon] and disposes it, so
/// exactly one of the two is closed — never both.
///
/// [hotkeyRegistrar] is built before the AD-14 address can be taken. It is
/// typed as the seam interface rather than as `X11KeyGrabRegistrar` because these two
/// helpers only ever call `dispose()` on it — AD-9's claim that swapping this
/// backend is a one-file change is only true while nothing outside that file
/// names its type. Closing it on the no-lifecycle branch is **defensive, and
/// releases nothing on any path that exists today** — the only caller of
/// `bindHotkey` is `_finishStartup`, and `lifecycle` is assigned before that
/// runs, so a failure that reaches [_releaseWithoutLifecycle] cannot have
/// grabbed anything yet. It is kept for the reason the tray's
/// `else if (trayIcon != null)` arm is: the step that closes a seam must not be
/// the thing someone has to remember to add when the ordering changes. Note what
/// the step does *not* buy, so the next reader does not over-trust it: this
/// branch is followed by `exit(1)`, and the X server drops a disconnecting
/// client's passive grabs, so an unreleased grab could not have outlived the
/// process either way.
///
/// [graph] is what makes that branch cover the partial build: `build()` reads
/// its providers in sequence, so a throw partway through leaves earlier
/// controllers constructed — and subscribed to `changes` — with no lifecycle to
/// dispose them. It is null only when the failure preceded the graph itself.
/// Its two steps lead the list, in `DaemonLifecycle.shutdown()`'s order: the
/// controllers come down before the panel adapter they still hold a
/// subscription to, and the container after them.
///
/// One residual it still does not cover, stated so the next reader does not
/// over-trust it: a controller whose **own constructor** throws after
/// subscribing. `ref.onDispose` is registered inside the constructor body only
/// once it returns, and `DaemonGraph`'s field for it is assigned only once
/// `container.read` returns — so such a controller is reachable by neither
/// `disposeControllers()` nor `container.dispose()`, and its subscription
/// outlives both. The `exit(1)` below is what bounds it; closing it properly
/// would mean a controller that subscribes outside its constructor, which is a
/// different change from this one.
Future<void> _abort({
  required Object error,
  required DaemonLifecycle? lifecycle,
  required DaemonGraph? graph,
  required WindowManagerPanelVisibility? panelVisibility,
  required TrayManagerTrayIcon? trayIcon,
  required TrayManagerTray? tray,
  required HotkeyRegistrar hotkeyRegistrar,
  required DaemonStartup? startup,
  required Logger logger,
  Duration stepTimeout = _unresponsiveCallBudget,
}) async {
  // Through `_log`, like every other log on this path, and now load-bearing:
  // `_installErrorHandlers` answers `true` for everything that reaches the root
  // zone, so a throw from a broken stderr here is caught, logged and
  // *handled*, and `exit(1)` below never runs. The process then sits on the
  // embedder's loop holding the AD-14 address with no panel, no tray and no
  // hotkey: the exact state this function exists to prevent, reached by the
  // guard against it failing.
  //
  // What the handler changed is the *reporting*, not the residency. An error
  // escaping `main` never ended this process — the GTK loop is already running
  // by then, so `exit(1)` was skipped before this bundle too. The handler is
  // why nothing is printed when it happens, which is what turns a loud
  // wedged daemon into a silent one; the wrap is what stops it happening.
  try {
    _log(
      () => logger.error(
        'startup failed before the daemon became ready; shutting down rather '
        'than leaving a resident process with no way in',
        context: {'error_type': error.runtimeType.toString()},
      ),
    );
    if (lifecycle != null) {
      await lifecycle.shutdown();
    } else if (startup != null) {
      await _releaseWithoutLifecycle(
        graph: graph,
        panelVisibility: panelVisibility,
        trayIcon: trayIcon,
        tray: tray,
        hotkeyRegistrar: hotkeyRegistrar,
        startup: startup,
        logger: logger,
        timeout: stepTimeout,
      );
    } else {
      // begin owns its lock until it either returns or releases it on failure.
      // No graph or window exists yet; only the inert registrar is ours.
      await runBoundedReleaseStep(
        name: 'releasing the global hotkey grab',
        release: hotkeyRegistrar.dispose,
        timeout: stepTimeout,
        logger: logger,
      );
    }
  } finally {
    // Even a broken cleanup step must not leave the GTK loop resident.
    exit(1);
  }
}

/// The teardown for a failure too early to have a [DaemonLifecycle].
///
/// Each step is independent, because the point is to leave nothing behind: a
/// database that will not close must not stop the address going back.
Future<void> _releaseWithoutLifecycle({
  required DaemonGraph? graph,
  required WindowManagerPanelVisibility? panelVisibility,
  required TrayManagerTrayIcon? trayIcon,
  required TrayManagerTray? tray,
  required HotkeyRegistrar hotkeyRegistrar,
  required DaemonStartup startup,
  required Logger logger,
  required Duration timeout,
}) async {
  for (final step in <(String, Future<void> Function())>[
    // First, and in this order, because that is where DaemonLifecycle.shutdown()
    // puts them: a controller's dispose can still call show()/hide() on the
    // panel adapter, and the container's own onDispose hooks call the same
    // idempotent controller disposes again behind the first step. Both are
    // absent when the failure preceded the graph.
    if (graph != null) ('disposing the controllers', graph.disposeControllers),
    if (graph != null)
      ('disposing the provider graph', () async => graph.dispose()),
    if (panelVisibility != null)
      ('closing the panel visibility adapter', panelVisibility.dispose),
    // After the panel adapter, matching DaemonLifecycle.shutdown()'s order.
    // The tray owns the seam and disposes it, so exactly one of these runs:
    // the `else` covers a failure that landed between the two constructors,
    // where a listener is registered and nothing above it exists yet.
    //
    // That `else` is explicitly defensive, and not evidence of a live path:
    // with the concrete types named above, the only code between
    // `openedTrayIcon = trayIcon` and `openedTray = tray` is
    // `TrayManagerTray`'s constructor, whose body is one `listen()` on a
    // broadcast controller's stream and cannot throw. It is kept because the
    // constructor takes a `TrayIcon`, so what runs there is whatever an
    // implementation of that interface does — the same reason the adapter
    // keeps its unknown-key branch and the lifecycle keeps its tray AD-15 one.
    if (tray != null)
      ('closing the tray', tray.dispose)
    else if (trayIcon != null)
      ('closing the tray icon', trayIcon.dispose),
    // Both, and in this order, because they close different things and this
    // branch runs precisely when no lifecycle exists to do either. The adapter
    // owns a broadcast controller and a subscription to the seam's press
    // stream, and its own `dispose()` releases the grab and disposes the seam
    // in turn — so the second step is a no-op on an X11 session and is what
    // closes the seam on a Wayland one, where no adapter ever held it. Both
    // are idempotent. Placed where `DaemonLifecycle.shutdown()` puts the
    // hotkey adapter — after the tray, before the database.
    ('disposing the hotkey adapter', startup.hotkey.dispose),
    ('releasing the global hotkey grab', hotkeyRegistrar.dispose),
    ('closing the database', startup.database.close),
    ('closing the config store', startup.configStore.close),
    ('releasing the single-instance address', startup.lock.dispose),
  ]) {
    await runBoundedReleaseStep(
      name: step.$1,
      release: step.$2,
      timeout: timeout,
      logger: logger,
    );
  }
}

/// Installs the concrete adapters as the graph's port overrides.
///
/// This list is the whole of AD-17's other half: every seam
/// `application/composition/port_providers.dart` declares gets its
/// implementation here, and nowhere else in the project names one.
ProviderContainer _container({
  required DaemonStartup startup,
  required Clock clock,
  required Logger logger,
  required TrayPort tray,
  required WindowManagerPanelVisibility panelVisibility,
}) {
  return ProviderContainer(
    overrides: [
      loggerProvider.overrideWithValue(logger),
      clockProvider.overrideWithValue(clock),
      configStoreProvider.overrideWithValue(startup.configStore),
      clipboardProvider.overrideWithValue(const SystemClipboard()),
      panelVisibilityProvider.overrideWithValue(panelVisibility),
      globalHotkeyProvider.overrideWithValue(startup.hotkey),
      // The only place under this project's own code that names
      // `HotkeyKeyCatalogue` outside `lib/src/infrastructure/`, and the reason
      // this file exists at the composition root: AD-1 forbids the import in
      // the application ring and in the ui ring alike, so the settings surface
      // gets the key vocabulary as a domain value built here (DW-71).
      registrableKeysProvider.overrideWithValue(
        HotkeyKeyCatalogue.registrableKeys(),
      ),
      trayProvider.overrideWithValue(tray),
      correctionRepositoryProvider.overrideWithValue(
        DriftCorrectionRepository(startup.database),
      ),
      activeCorrectionProviderProvider.overrideWithValue(
        startup.active.provider,
      ),
      activePresetProvider.overrideWithValue(startup.active.preset),
    ],
  );
}

/// AD-8: the window is created once, warm, and never mapped. Nothing here can
/// make the panel visible — the toggle is the only thing that ever does.
///
/// Deliberately **not** `waitUntilReadyToShow`, which is not the inert
/// preparation its name suggests: it runs three conditional recovery calls of
/// its own, and one of them — `if (await isMinimized()) await restore()` —
/// is `gtk_window_deiconify` plus `gtk_window_present` on Linux, which maps
/// *and* raises the toplevel. That is AD-8 broken on a branch no test here
/// observes, in exchange for convenience this daemon does not need. The
/// required window properties are set directly, and none can map a window.
Future<void> _createHiddenWindow() async {
  await windowManager.ensureInitialized();
  final geometry = _initialPanelGeometry();
  await windowManager.setTitle('Hotkey Grammar Corrector');
  // A tray daemon has no business in the task switcher while it is hidden.
  await windowManager.setSkipTaskbar(true);
  // Geometry is prepared on the hidden toplevel, before any hotkey can summon
  // it. These calls configure GTK's size hints and bounds; none presents it.
  // The display snapshot is best effort: Wayland owns ordinary toplevel
  // placement, and a pointer moving after startup cannot update this position
  // without putting platform I/O on the hotkey path (D-16).
  await windowManager.setMinimumSize(geometry.minimumSize);
  await windowManager.setSize(geometry.size);
  await windowManager.setPosition(geometry.position);
  // DW-12: a window close is a dismissal, not an exit. Without this,
  // `on_window_close` returns a false `_is_prevent_close` and GTK destroys the
  // toplevel — abandoning whatever CAP-7 write is in flight and leaving the
  // next hotkey press with no warm window to raise (CAP-1). With it the `close`
  // event still arrives, and `WindowManagerPanelVisibility` turns it into a
  // real `hide()`.
  //
  // A property, set once, exactly like `setSkipTaskbar` above — and it makes no
  // GTK call at all: `set_prevent_close` assigns `self->_is_prevent_close` and
  // returns (`window_manager-0.5.2/linux/window_manager_plugin.cc:70-77`). That
  // is why it belongs on the startup path rather than behind the `PanelWindow`
  // seam, whose whole purpose is the three toggle requests.
  //
  // What it refuses is broader than the user's close button, and that is worth
  // stating: the flag is global and permanent, so a **session manager** asking
  // this toplevel to close — a logout, an end-session request — is refused by
  // the same `false`. That is acceptable rather than overlooked, because a
  // logout does not reach this daemon as a window close alone. Under a systemd
  // user session — which is how a logout ends on the desktops this ships for —
  // stopping the session scope delivers `SIGTERM`, and a terminal close or an
  // X-session hangup delivers `SIGHUP`; [_installSignalHandlers] watches both,
  // and SIGHUP is in that list for exactly this path. Where neither is
  // guaranteed — an XDG-autostart launch under a session manager that only
  // asks windows to close — the display connection drops as the session tears
  // down, which ends the process regardless of this flag. What is *not* claimed
  // is that a close request alone reaches the teardown: it does not, by
  // design, and nothing here observes the end-session path (see
  // `test/platform/runtime-observation-checklist.md`'s `## Not covered here`).
  await windowManager.setPreventClose(true);
}

({Size size, Size minimumSize, Offset position}) _initialPanelGeometry() {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final textScaler = TextScaler.linear(dispatcher.textScaleFactor);
  final minimumHeight = math.max(
    360.0,
    CorrectionPanel.minimumPanelHeightFor(textScaler) + 60,
  );
  final preferredMinimum = Size(480, minimumHeight);
  final preferredSize = Size(640, math.max(520.0, minimumHeight));
  final available = _startupDisplaySize();
  if (available == null) {
    return (
      size: preferredSize,
      minimumSize: preferredMinimum,
      position: Offset.zero,
    );
  }

  final size = Size(
    math.min(preferredSize.width, available.width),
    math.min(preferredSize.height, available.height),
  );
  final minimumSize = Size(
    math.min(preferredMinimum.width, available.width),
    math.min(preferredMinimum.height, available.height),
  );
  return (
    size: size,
    minimumSize: minimumSize,
    position: Offset(
      (available.width - size.width) / 2,
      (available.height - size.height) / 2,
    ),
  );
}

Size? _startupDisplaySize() {
  final display =
      WidgetsBinding.instance.platformDispatcher.views.firstOrNull?.display;
  final ratio = display?.devicePixelRatio;
  if (display == null || ratio == null || !ratio.isFinite || ratio <= 0) {
    return null;
  }
  final available = display.size / ratio;
  if (!available.width.isFinite ||
      !available.height.isFinite ||
      available.width <= 0 ||
      available.height <= 0) {
    return null;
  }
  return available;
}

/// Points the framework's two error channels at the [Logger] port, so a
/// failure they report is a log line rather than a dead surface or a dead
/// daemon.
///
/// Both are installed, because they catch different halves: `FlutterError`
/// takes what the framework catches itself — a throw in `build()`, in layout,
/// in paint, in a gesture callback — and `PlatformDispatcher.onError` takes
/// what escapes into the root zone, which is every unawaited future the
/// application ring's own guards did not already absorb. Neither reaches
/// `main`'s guard, so without these two lines both end at the framework's
/// default: `dumpErrorToConsole`, which prints the exception's `toString()` and
/// its stack. That is precisely what the Logger port forbids — a vendor
/// exception carries the statement and parameters that caused it, and for the
/// CAP-7 history write those parameters are the corrected text itself.
///
/// So each handler emits **only** the runtime type (plus the framework's own
/// `library`, which the framework authored and no user text reaches). No
/// message body, no stack.
///
/// And neither ends the process. `onError` returns true — handled — because
/// this daemon's job is to be resident: one screen that will not build is a
/// degraded surface, and the hotkey, the tray and the history behind it keep
/// working. The startup path is the only failure that still aborts, and it has
/// [_abort].
void _installErrorHandlers(Logger logger) {
  FlutterError.onError = (FlutterErrorDetails details) {
    // Silent details are dropped: a silent detail is one the framework has
    // already handled and does not want reported twice.
    //
    // Not quite the default this replaces, and the difference is stated rather
    // than glossed. `FlutterError.dumpErrorToConsole` computes
    // `reportError = isInDebugMode || !details.silent` — it honours the flag
    // in a release build and deliberately ignores it in a debug one. This
    // handler honours it in both, so a debug session sees less than the
    // framework would show it. That is the trade taken: the alternative is a
    // `kDebugMode` branch inside the one channel that must never surprise, on
    // a daemon whose release behaviour is the behaviour under test.
    if (details.silent) {
      return;
    }
    // Through `_log`, like every other log on this path: `StderrLogger` ends
    // in `_sink.writeln`, and a throw from a broken stderr inside an error
    // handler is an error reported from an error handler.
    _log(
      () => logger.error(
        'the framework reported a widget-tree error; the surface it came from '
        'may be broken and the daemon stays up',
        context: {
          'error_type': details.exception.runtimeType.toString(),
          'library': details.library,
        },
      ),
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _log(
      () => logger.error(
        'an asynchronous error reached the root zone unhandled; the daemon '
        'stays up',
        context: {'error_type': error.runtimeType.toString()},
      ),
    );
    return true;
  };
}

/// A resident daemon is stopped by a signal — `systemctl stop`, a logout, or
/// Ctrl-C in a terminal — so that is where the ordered teardown hangs. It is
/// one of the daemon's two triggers for it; [_installQuitHandler] is the other,
/// and both run the identical sequence.
///
/// The subscriptions are deliberately never cancelled. Dart restores the OS
/// default disposition once the last listener for a signal goes away, so a
/// handler that took only the first event would leave the second `SIGTERM` —
/// the one an impatient operator or a `systemd` stop timeout sends — killing
/// the process outright, mid-drain, with the CAP-7 write the ordering exists
/// to protect still in flight. Staying subscribed means a repeat signal lands
/// on [DaemonLifecycle.shutdown], which latches: the second caller awaits the
/// teardown already running instead of racing it.
///
/// The `exit(0)` is here rather than inside that method for the same reason
/// the graph is: a function that ends the process cannot be run by a test, and
/// the teardown order is the part worth testing.
void _installSignalHandlers(DaemonLifecycle lifecycle) {
  // SIGHUP belongs here with the other two: its default disposition terminates
  // the process outright, and it is what a terminal close or an X-session
  // logout delivers — the logout this method's own doc names. Without it that
  // path skips every teardown step and abandons the CAP-7 write in flight.
  for (final signal in [
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
    ProcessSignal.sighup,
  ]) {
    signal.watch().listen((_) async {
      final alreadyStopping = lifecycle.isShuttingDown;
      if (alreadyStopping) {
        // Say so, so an operator watching a slow stop knows the signal landed
        // and the daemon is draining rather than ignoring them.
        _log(
          () => stderr.writeln(
            'received a second stop signal; already shutting down',
          ),
        );
      }
      await lifecycle.shutdown();
      exit(0);
    });
  }
}

/// The daemon's other exit trigger: AD-12's tray menu (DW-114).
///
/// A signal is the only way to stop a resident daemon, and a tray-only user has
/// no way to send one — so the menu carries a Quit entry, and this is what it
/// reaches. Deliberately the *same* teardown a `SIGTERM` reaches, latched the
/// same way and followed by the same `exit(0)`: two triggers, one exit path.
/// Anything else would be a second shutdown order to keep in step with the
/// first, and the ordering is what protects the CAP-7 write in flight.
///
/// Immediate, with no confirmation: every correction is already in history
/// (CAP-7) and copying a suggestion is explicit (CAP-11), so a "quit anyway?"
/// step would guard nothing and would put a modal in front of the one action a
/// user reaches for when the daemon is already misbehaving.
///
/// The `exit(0)` is here rather than inside [DaemonLifecycle.shutdown] for the
/// reason [_installSignalHandlers] states: a function that ends the process
/// cannot be run by a test, and the teardown order is the part worth testing.
///
/// The subscription is never cancelled and its `onError` arm never ends it —
/// [DaemonLifecycle.shutdown] cancels the streams it owns, and this one is
/// closed by `tray.dispose()` inside that very teardown. A seam that breaks
/// [TrayPort]'s promise (AD-15) must not take the exit route down with it.
void _installQuitHandler({
  required TrayPort tray,
  required DaemonLifecycle lifecycle,
}) {
  tray.quitRequests.listen(
    (_) async {
      if (lifecycle.isShuttingDown) {
        // The same courtesy the repeat-signal branch extends — a user whose
        // pick lands on a slow stop should learn the daemon is draining rather
        // than ignoring them — but **not for as long**, and the difference is
        // stated rather than implied.
        //
        // The line says a stop was already in progress, and deliberately does
        // not say the user picked twice: `isShuttingDown` is true for *any*
        // teardown, so this branch is also where a **first** pick lands during
        // a `systemctl stop`, a logout, or `_abort`'s own shutdown. Claiming a
        // repeat there would send whoever reads the journal looking for a
        // second pick that never happened.
        //
        // This branch is reachable only while the
        // tray is still alive: the teardown's `closing the tray` step disposes
        // it — named rather than numbered, because
        // [DaemonLifecycle.shutdown]'s doc groups the eleven `_step` calls into
        // six numbered stages and the tray is the fifth of those, so an ordinal
        // here would contradict the doc it points at — and
        // `TrayManagerTray._onSelection` returns early once `_disposed` is set,
        // so a pick after that point is silent and no line is written. The
        // signal watchers stay responsive for the whole teardown, because
        // nothing cancels them. Narrower on purpose: making the two identical
        // would mean keeping a tray subscription alive past the step that
        // closes the tray, which is a mechanism, not a log line.
        //
        // `shutdown()` latches either way, so a second pick that does reach
        // here awaits the teardown already running instead of racing it.
        _log(
          () => stderr.writeln(
            'the tray Quit entry was picked; a stop was already in progress, '
            'so this awaits the teardown already running',
          ),
        );
      } else {
        // The common branch, and the one worth a line: a resident daemon found
        // gone is first asked *what stopped it*, and without this the only
        // trace is `DaemonLifecycle`'s own `shutting down` — identical to what
        // a SIGTERM leaves behind. One line separates "the user chose to quit"
        // from "the session manager stopped us".
        _log(
          () => stderr.writeln('the tray Quit entry was picked; shutting down'),
        );
      }
      await lifecycle.shutdown();
      exit(0);
    },
    // Only the runtime type reaches the line: the Logger port forbids an
    // exception body on a channel that runs all day.
    //
    // Raw `stderr` rather than the [Logger] a caller could pass in — and that
    // is a choice, not a constraint: `logger` is live at this handler's call
    // site. The two exit triggers are deliberately kept identical down to what
    // they leave behind, and [_installSignalHandlers] genuinely cannot reach a
    // logger without being handed one it does not otherwise need. Splitting
    // them would mean a tray Quit and a `SIGTERM` reading differently in the
    // journal for no reason a reader could act on.
    onError: (Object error) => _log(
      () => stderr.writeln(
        'the tray quit-request stream errored; the daemon stays up and a stop '
        'signal still brings it down '
        '(error_type: ${error.runtimeType})',
      ),
    ),
  );
}

/// Writes a startup-path note without letting a broken stderr take the daemon
/// down — the same reasoning as the application ring's `_log`, at the one
/// point that has no [Logger] of its own to reach for.
void _log(void Function() emit) {
  try {
    emit();
  } on Object {
    // Nowhere left to report this: the reporting channel is what broke.
  }
}
