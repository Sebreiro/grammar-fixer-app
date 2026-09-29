import 'dart:async';

import '../../domain/hotkey/global_hotkey.dart';
import '../../domain/logger.dart';

/// Closes one adapter the daemon opened.
///
/// A typedef rather than an interface: `AppDatabase.close`,
/// `JsonConfigStore.close` and `SingleInstanceLock.dispose` share a shape but
/// no supertype, and inventing one for three tear-offs would be an
/// abstraction with no variation behind it (AGENTS.md §4.2).
typedef CloseAdapter = Future<void> Function();

/// Bounds one release without letting its failure skip the next owned resource.
///
/// Startup abort and normal shutdown use this same policy. The timeout abandons
/// the wait; an adapter that has already started may still finish later.
Future<void> runBoundedReleaseStep({
  required String name,
  required Future<void> Function() release,
  required Duration timeout,
  required Logger logger,
}) async {
  var timedOut = false;
  try {
    await release().timeout(timeout, onTimeout: () => timedOut = true);
  } on Object catch (error) {
    _logReleaseError(
      () => logger.error(
        '$name failed',
        context: {'error_type': error.runtimeType.toString()},
      ),
    );
    return;
  }
  if (timedOut) {
    _logReleaseError(
      () => logger.error(
        '$name did not finish within ${timeout.inMilliseconds} ms; it was '
        'abandoned so the remaining steps still run, and its work may still be '
        'in flight when the process exits',
        context: {'timeout_ms': timeout.inMilliseconds},
      ),
    );
  }
}

void _logReleaseError(void Function() emit) {
  try {
    emit();
  } on Object {
    // A broken reporting channel cannot hold resource release hostage.
  }
}

/// The resident daemon's runtime lifecycle: what a show request reaches, and
/// the order everything comes down in.
///
/// The teardown order **is** the contract, not a detail, so it lives here —
/// in one testable unit — rather than inline in `main.dart` where no test can
/// reach it. The container-side work arrives as callbacks because AD-17 keeps
/// Riverpod inside `application/` and `ui/`, and the spine forbids
/// infrastructure from importing application: this type must never see a
/// `ProviderContainer`.
final class DaemonLifecycle {
  DaemonLifecycle({
    required this._showRequests,
    required this._trayRequests,
    required this._onShowRequest,
    required this._disposeControllers,
    required this._disposeGraph,
    required this._closePanelVisibility,
    required this._closeTray,
    required this._hotkey,
    required this._closeHotkeyRegistrar,
    required this._closeDatabase,
    required this._closeConfigStore,
    required this._closeLock,
    required this._stepTimeout,
    required this._logger,
  });

  final Stream<void> _showRequests;

  /// AD-12's other way in: the tray menu's open-panel entry. Kept as its own
  /// parameter rather than merged with [_showRequests] because the two name
  /// different mechanisms, and an operator reading "the tray menu stream
  /// errored" learns something "a show-request stream errored" would hide.
  final Stream<void> _trayRequests;
  final void Function() _onShowRequest;
  final Future<void> Function() _disposeControllers;
  final void Function() _disposeGraph;
  final CloseAdapter _closePanelVisibility;
  final CloseAdapter _closeTray;
  final GlobalHotkey _hotkey;

  /// Closes the X11 key-grab seam, separately from [_hotkey].
  ///
  /// Both, and in this order, because they close different things. On an X11
  /// session the adapter owns the seam and disposes it, so this step is a no-op;
  /// on a Wayland session `WaylandPortalGlobalHotkey` never saw it, and this is
  /// the only step that closes the one `main.dart` built. Without it the two
  /// teardown paths disagree — `_releaseWithoutLifecycle` has closed both since
  /// the seam existed — and the path that actually runs on SIGTERM would be the
  /// less thorough of the two. Idempotent, like every other step here.
  final CloseAdapter _closeHotkeyRegistrar;
  final CloseAdapter _closeDatabase;
  final CloseAdapter _closeConfigStore;
  final CloseAdapter _closeLock;

  /// How long one teardown step may hold the daemon before it is abandoned.
  ///
  /// Required, and stated at the composition root rather than defaulted here:
  /// this is one half of a single policy — how long a single platform call may
  /// hold the daemon — and a default would let this site drift from the panel
  /// adapter's half of it without anyone deciding to.
  ///
  /// Per step, never a total deadline. Every step gets its own bound and the
  /// sequence continues after one expires, because the point is that
  /// [shutdown] reaches its end: `main.dart` calls `exit(0)`/`exit(1)` behind
  /// it, so a step that never completes is a daemon that never exits.
  final Duration _stepTimeout;
  final Logger _logger;

  StreamSubscription<void>? _showRequestSubscription;
  StreamSubscription<void>? _trayRequestSubscription;
  bool _shuttingDown = false;

  /// The one teardown, latched so every later caller awaits it rather than
  /// starting a second or being handed an already-completed future.
  Future<void>? _shutdown;
  Completer<void>? _startupCompleted;
  final Completer<void> _stopRequested = Completer<void>();

  /// Lets startup leave its ownership boundary before release begins.
  void beginStartup() {
    _startupCompleted = Completer<void>();
  }

  void finishStartup() {
    final completed = _startupCompleted;
    if (completed != null && !completed.isCompleted) {
      completed.complete();
    }
  }

  Future<void> get stopRequested => _stopRequested.future;

  /// True once [shutdown] has begun. A second signal must not restart the
  /// sequence half way through the first.
  bool get isShuttingDown => _shuttingDown;

  /// Starts listening for AD-14's show requests and the tray menu's.
  ///
  /// Both reach the same handler, because both mean the same thing: raise the
  /// resident panel. AD-12's tray entry is the way in precisely when no global
  /// hotkey could be bound, and AD-8 requires it reach `PanelVisibility.show()`
  /// through `PanelController.showPanel()` — which is exactly what the handler
  /// AD-14 already uses does.
  ///
  /// The handler is fired, never awaited: a later launch asking the resident
  /// daemon to show its panel is on CAP-1's path, and the panel controller's
  /// own `showPanel()` is what keeps the window-manager round trip off the
  /// decision (AD-8).
  ///
  /// A no-op once [shutdown] has begun. `main` installs the signal handlers
  /// before the window and the widget tree but calls this *after* `runApp`, so
  /// a stop signal can land between the two: the teardown then runs — step 1
  /// cancelling subscriptions that do not exist yet — and this would
  /// otherwise open fresh ones on a lock and a tray that have already been
  /// released. [shutdown] is latched so a second signal cannot restart the
  /// sequence; without this guard, startup could.
  void start() {
    if (_shuttingDown) {
      return;
    }
    _showRequestSubscription = _listenForPanelRequests(
      _showRequests,
      'single-instance show',
    );
    _trayRequestSubscription = _listenForPanelRequests(
      _trayRequests,
      'tray menu',
    );
  }

  /// Subscribes one request stream to the panel handler.
  ///
  /// [source] names the mechanism, and it is threaded all the way through to
  /// [_raisePanel] rather than used only on the stream's own error path: both
  /// sources funnel into one handler, so a shared message there would report
  /// every tray failure as a second launch's — undoing, on the more likely of
  /// the two paths, exactly the distinction these separate parameters exist to
  /// preserve.
  ///
  /// The stream-error branch is a **deliberately defensive** AD-15 backstop on
  /// the tray side, not a live path: `TrayManagerTray` absorbs its own seam's
  /// errors and only ever calls `add(null)`, so a shipped `panelRequests`
  /// cannot error today. It is kept because this type takes a bare
  /// `Stream<void>` from the composition root and cannot see which
  /// implementation is behind it — and because a subscription that ended on an
  /// error would take the tray menu, AD-12's whole fallback, down with it. The
  /// `SingleInstanceLock` side is the same shape.
  StreamSubscription<void> _listenForPanelRequests(
    Stream<void> requests,
    String source,
  ) {
    return requests.listen(
      (_) => _raisePanel(source),
      onError: (Object error) => _log(
        () => _logger.error(
          'the $source request stream errored',
          context: {'error_type': error.runtimeType.toString()},
        ),
      ),
    );
  }

  /// Runs the panel handler for a request from [source] without letting its
  /// failure escape.
  ///
  /// The handler reaches into the provider graph, and a graph that is being
  /// torn down throws on read — a request landing in that window would
  /// otherwise become an uncaught zone error in a daemon whose whole job is to
  /// stay up. Guarding the handler as well as the stream is the house pattern
  /// every controller in the application ring already follows.
  ///
  /// A no-op once [shutdown] has begun, for the same reason [start] is one.
  /// Step 1 cancels both subscriptions, so before the teardown steps were
  /// bounded nothing could arrive here afterwards — a `cancel()` that hung hung
  /// the whole teardown. It can now be abandoned instead, and steps 2 to 11
  /// then run with the subscription still delivering: without this guard a
  /// press landing in that window would map the panel on screen while the
  /// process is already on its way to `exit(0)`.
  void _raisePanel(String source) {
    if (_shuttingDown) {
      return;
    }
    try {
      _onShowRequest();
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'raising the panel for a $source request failed',
          context: {'error_type': error.runtimeType.toString()},
        ),
      );
    }
  }

  /// Brings the daemon down in the one order that is safe, and never throws.
  ///
  /// 1. **Both panel-request subscriptions** — the AD-14 one and the tray's —
  ///    so nothing reaches a controller mid-teardown.
  /// 2. **The controllers**, because `CorrectionController.dispose()` awaits
  ///    the history writes still in flight — CAP-7 retains a correction that
  ///    terminates as the daemon exits, and those writes need a live database.
  /// 3. **The graph**, whose own `onDispose` hooks call the same idempotent
  ///    `dispose()`s again behind step 2.
  /// 4. **The panel visibility adapter**, after the graph and before the rest.
  ///    It must outlive every controller that can still call `show()`/`hide()`
  ///    on it — `PanelController` fires those without awaiting, so one issued
  ///    during teardown is still in flight when its owner returns — and it
  ///    must close before the process exits, because it holds a window
  ///    listener and a stream of its own.
  /// 5. **The tray**, after the panel adapter for the same reason the panel
  ///    adapter goes after the graph: a menu pick already dispatched reaches
  ///    the panel through the adapter, so the tray must not outlive it, and
  ///    the tray holds a listener on the `tray_manager` singleton plus a
  ///    stream of its own that must be closed before the process exits.
  /// 6. **The adapters** — hotkey adapter, hotkey seam, database, config store,
  ///    lock. The adapter and the seam are both closed, in that order: on X11
  ///    the adapter owns the seam and the second step is a no-op, while on
  ///    Wayland the adapter never saw it and the second step is the only thing
  ///    that closes the one `main.dart` built. The database goes here and not
  ///    earlier because `AppDatabase.file` runs on a background isolate that
  ///    outlives `main` if it is never closed, and closing it before step 2
  ///    would strand the write step 2 is waiting for.
  ///
  /// Every step is guarded, in both directions: a step that **rejects** and a
  /// step whose future never **completes** each make a log line rather than a
  /// daemon that cannot exit. The second half matters because `main.dart` calls
  /// `exit(0)` after awaiting this, and two of these steps can genuinely hang
  /// (`disposeControllers` awaits the history writes still in flight, and
  /// closing the database awaits drift's background isolate).
  ///
  /// So the guarantee is "never throws, and finishes for every step that yields
  /// the isolate". The qualifier is not a hedge, and the residual it names is
  /// real: [_step] calls `run()` and only then applies the bound to the future
  /// it returned, so a step that blocks the isolate *synchronously* — a tight
  /// loop, a blocking syscall, a `_disposeGraph()` that never awaits — is past
  /// any timer, because the timer cannot fire until the isolate is free to run
  /// it. Nothing here can close that, and nothing here pretends to: the shipped
  /// steps are all asynchronous adapter closes, and a synchronous hang in one of
  /// them is a defect in that adapter rather than a case this bound covers.
  ///
  /// What the bound buys is the exit, not a tidy one: an abandoned step is not
  /// cancelled — Dart has no such thing — so its work may still be running when
  /// the process ends, and the CAP-7 write it was draining may be lost. That is
  /// the trade, taken deliberately: a daemon that cannot be stopped costs every
  /// later launch, and a lost write costs one correction.
  ///
  /// The ordering above is therefore a best-effort **sequence, not a
  /// guarantee**, once a step is abandoned, and step 6's database rationale is
  /// the case worth naming: abandoning step 2 and going on closes the database
  /// underneath a `CorrectionController.dispose()` that is still draining
  /// writes, so the write is not merely racing `exit()` — a later step in this
  /// same sequence tears the database out from under it. That is not a reason
  /// to reorder or to add a total deadline; it is why the trade is stated as
  /// "the exit, at the price of the drain" rather than as a tidy shutdown that
  /// happens to be bounded.
  ///
  /// Calling this again returns the *same* future, so a second caller waits
  /// for the teardown already running rather than being told it is finished.
  /// That distinction is the whole point on this path: both signal watchers
  /// await this and then `exit(0)`, so an early-resolving second call would
  /// end the process mid-drain and lose the CAP-7 write the ordering exists to
  /// protect.
  Future<void> shutdown() {
    if (!_stopRequested.isCompleted) {
      _stopRequested.complete();
    }
    return _shutdown ??= _run();
  }

  Future<void> _run() async {
    _shuttingDown = true;
    _log(() => _logger.info('shutting down'));

    final startupCompleted = _startupCompleted;
    if (startupCompleted != null && !startupCompleted.isCompleted) {
      await _step(
        'waiting for startup to release owned resources',
        () => startupCompleted.future,
      );
    }

    await _step('cancelling the show-request subscription', () async {
      _showRequestSubscription = await _cancelled(_showRequestSubscription);
    });
    await _step('cancelling the tray panel-request subscription', () async {
      _trayRequestSubscription = await _cancelled(_trayRequestSubscription);
    });
    await _step('disposing the controllers', _disposeControllers);
    await _step('disposing the provider graph', () async => _disposeGraph());
    await _step('closing the panel visibility adapter', _closePanelVisibility);
    await _step('closing the tray', _closeTray);
    await _step('disposing the hotkey adapter', _hotkey.dispose);
    await _step('releasing the global hotkey grab', _closeHotkeyRegistrar);
    await _step('closing the history database', _closeDatabase);
    await _step('closing the config store', _closeConfigStore);
    await _step('releasing the single-instance lock', _closeLock);
  }

  /// Cancels one panel-request subscription and yields the null that replaces
  /// it, so a second [start] after a teardown cannot resurrect a cancelled one
  /// and a second [shutdown] has nothing left to cancel.
  ///
  /// Shared by both subscriptions; their *log messages* are not, because
  /// [_step] names the step that failed and "the show-request subscription"
  /// and "the tray panel-request subscription" fail for different reasons.
  Future<StreamSubscription<void>?> _cancelled(
    StreamSubscription<void>? subscription,
  ) async {
    await subscription?.cancel();
    return null;
  }

  /// Runs one teardown step, reducing both of its failures — a rejection, and a
  /// future that never completes — to a log line, because a daemon that cannot
  /// exit is the worse failure.
  ///
  /// What the bound covers is precisely the *future*: `run()` is invoked first
  /// and the timer is armed on what it returns, so a step that never yields the
  /// isolate is unreachable here. See [shutdown]'s doc for why that residual is
  /// left standing.
  ///
  /// The expiry is reported through `onTimeout` and a local flag rather than by
  /// catching [TimeoutException], and that is the whole point of the shape: a
  /// step's own internals have their own deadlines (`SingleInstanceLock`'s
  /// handshake is one), so a `TimeoutException` thrown *by the step* must stay
  /// reported as that step failing rather than being relabelled as this policy
  /// firing.
  Future<void> _step(String what, Future<void> Function() run) =>
      runBoundedReleaseStep(
        name: what,
        release: run,
        timeout: _stepTimeout,
        logger: _logger,
      );

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
