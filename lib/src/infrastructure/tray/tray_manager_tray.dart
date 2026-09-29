import 'dart:async';

import '../../domain/hotkey/hotkey_bind_outcome.dart';
import '../../domain/logger.dart';
import '../../domain/tray/tray_port.dart';
import '../../domain/tray/hotkey_tray_status.dart';
import 'tray_icon.dart';
import 'tray_menu_entry.dart';

/// AD-12's [TrayPort], over a [TrayIcon].
///
/// The tray is the way in *because* the hotkey is not, so two rules shape
/// everything here.
///
/// *Unavailability is stated on both visible surfaces.* AD-12 says "the tray
/// icon and settings screen state that global hotkeys are unavailable". Read
/// narrowly that is the icon *image*; read as the tray surface it is the menu,
/// which is the only place a sentence fits. Both are done: the icon swaps to
/// [unavailableIconAsset] and a disabled line carrying the words is appended.
/// Neither is expensive — `setIcon` re-creates nothing, it is
/// `app_indicator_set_status(ACTIVE)` plus `set_icon_full`.
///
/// *The open-panel entry stays enabled while that statement is shown.* Greying
/// out the one route into the app on the one compositor family that needs it
/// would invert AD-12 rather than implement it.
///
/// No menu is pushed before [install]. That is a crash-avoidance rule, not
/// defensive style: `set_context_menu` dereferences an `AppIndicator*` that
/// only `set_icon` creates, with no null check
/// (`tray_manager-0.5.3/linux/tray_manager_plugin.cc:105-129, :143-152`). And
/// `DaemonStartup.bindHotkey` calls [setHotkeyUnavailable] without knowing
/// whether the tray was installed, so this adapter is where the rule has to
/// live.
final class TrayManagerTray implements TrayPort {
  TrayManagerTray({required this._icon, required this._logger}) {
    _selections = _icon.selections.listen(
      _onSelection,
      // AD-15 backstop: the seam promises a plain stream of entry keys. One
      // that errors instead must not end this subscription — it is the only
      // route from the menu to the panel, and since DW-114 the only route from
      // the menu to the daemon's exit as well.
      onError: (Object error) => _log(
        () => _logger.error(
          'the tray selection stream errored',
          context: _errorContext(error),
        ),
      ),
    );
  }

  /// The resident daemon's ordinary icon.
  static const String availableIconAsset =
      'assets/tray/hotkey-grammar-corrector.png';

  /// The same mark, desaturated and carrying a warning corner: AD-12's state,
  /// visible at a glance without opening the menu.
  static const String unavailableIconAsset =
      'assets/tray/hotkey-grammar-corrector-hotkey-unavailable.png';

  /// Adapter-owned identifiers echoed back on selection. Not labels: a label
  /// is what the user reads and may change without changing what it does.
  static const String _openPanelKey = 'open-panel';
  static const String _hotkeyUnavailableKey = 'hotkey-unavailable';
  static const String _quitKey = 'quit';

  static const String _openPanelLabel = 'Open the panel';

  /// One word, and no ellipsis: an ellipsis promises a dialog, and there is
  /// none. Picking this stops the daemon immediately — every correction is
  /// already in history (CAP-7) and copying is explicit (CAP-11), so there is
  /// nothing unsaved a confirmation step could protect.
  static const String _quitLabel = 'Quit';

  /// Startup's boolean hand-off has no cause; later typed snapshots do.
  static const String _hotkeyUnavailableLabel =
      'Global hotkey unavailable — use this menu to open the panel';

  final TrayIcon _icon;
  final Logger _logger;
  late final StreamSubscription<String> _selections;

  /// Broadcast, matching the port: a user-event notification stream that may
  /// have several independent listeners.
  final StreamController<void> _panelRequests =
      StreamController<void>.broadcast();

  /// Broadcast for the same reason [_panelRequests] is, and carrying the
  /// daemon's other exit trigger: the composition root turns an event here into
  /// the same ordered teardown a SIGTERM runs.
  final StreamController<void> _quitRequests =
      StreamController<void>.broadcast();

  /// Whether the native indicator exists. Set by [_push] the moment `setIcon`
  /// returns, because that native call is what creates it — not when a whole
  /// push succeeds. A menu refused *after* the indicator was created does not
  /// un-create it, and pretending otherwise would suppress every later push.
  bool _installed = false;

  /// Startup's availability and the later Settings-owned status.
  bool _hotkeyUnavailable = false;
  HotkeyTrayStatus? _status;

  /// The state the tray is actually *showing* — `null` when that is unknown,
  /// which is the case before the first push and after any push that failed
  /// partway.
  ///
  /// Kept separate from [_hotkeyUnavailable] deliberately. Collapsing the two
  /// makes one field mean both "what was asked for" and "what is on screen",
  /// and those diverge exactly when it matters: `setIcon` lands, `setMenu` is
  /// refused, and the icon now shows a state no field records. Short-circuiting
  /// on the request would then refuse the one call that could put it right,
  /// leaving AD-12's degradation stuck on the session it exists for, with no
  /// route back through the port — which offers no way to ask what the tray
  /// believes it is showing.
  ({bool unavailable, String? line})? _rendered;

  /// Native icon and menu writes must finish in request order. A newer
  /// binding result can arrive while the startup menu is still being pushed.
  Future<void> _pushTail = Future<void>.value();

  bool _disposed = false;

  @override
  Stream<void> get panelRequests => _panelRequests.stream;

  @override
  Stream<void> get quitRequests => _quitRequests.stream;

  @override
  Future<void> install() async {
    if (_disposed) {
      return;
    }
    await _push();
  }

  @override
  Future<void> setHotkeyUnavailable(bool unavailable) async {
    // The startup bind can finish after a backend change reached Settings.
    // That later typed result is authoritative for this surface too.
    if (_status != null) {
      return;
    }
    _hotkeyUnavailable = unavailable;
    // Against what is rendered, not against what was requested: an unknown
    // render state must always push, or a partial failure is permanent.
    if (_disposed || _rendered == _requested) {
      return;
    }
    if (!_installed) {
      // The state is remembered and [install] will render it. Pushing now
      // would push a menu at an indicator that does not exist yet.
      return;
    }
    await _push();
  }

  @override
  Future<void> setHotkeyStatus(HotkeyTrayStatus status) async {
    _status = status;
    if (_disposed || !_installed || _rendered == _requested) {
      return;
    }
    await _push();
  }

  ({bool unavailable, String? line}) get _requested {
    final status = _status;
    if (status == null) {
      return (
        unavailable: _hotkeyUnavailable,
        line: _hotkeyUnavailable ? _hotkeyUnavailableLabel : null,
      );
    }
    return (unavailable: status.unavailable, line: _statusLine(status));
  }

  String? _statusLine(HotkeyTrayStatus status) {
    return switch (status.outcome) {
      HotkeyUnavailable(cause: HotkeyUnavailableCause.noBackend) =>
        'Global shortcuts are unavailable to this app — use this menu to open the panel',
      HotkeyUnavailable(cause: HotkeyUnavailableCause.keyRefused) =>
        'The shortcut was refused — use this menu to open the panel',
      HotkeyUnavailable(cause: HotkeyUnavailableCause.revoked) =>
        'Your desktop removed the shortcut — use this menu to open the panel',
      HotkeyRetained() =>
        'That shortcut was refused; your previous shortcut still works',
      HotkeyBound() when status.rebindRefused =>
        'That shortcut was refused; your previous shortcut still works',
      HotkeyBound() => null,
    };
  }

  /// Deregisters from the seam, closes [panelRequests] and [quitRequests], and
  /// disposes the icon. Idempotent, and never throws: it runs on the shutdown
  /// path — which is the path a [quitRequests] event itself leads to, so each
  /// close is guarded separately and a failure is a log line rather than a
  /// daemon that cannot finish exiting.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _guard(
      'cancelling the tray selection subscription',
      _selections.cancel,
    );
    await _guard('closing the tray panel request stream', _panelRequests.close);
    await _guard('closing the tray quit request stream', _quitRequests.close);
    await _guard('disposing the tray icon', _icon.dispose);
  }

  /// Icon first, then menu — the native ordering rule, stated on [TrayIcon].
  ///
  /// A rejection propagates rather than being logged here: [install] is
  /// guarded by the composition root, which is what keeps a tray that will not
  /// install from blocking startup, and [setHotkeyUnavailable] is guarded by
  /// `DaemonStartup.bindHotkey` for the same reason.
  Future<void> _push() {
    final push = _pushTail.then((_) => _pushRequested());
    _pushTail = push.then<void>((_) {}, onError: (Object _) {});
    return push;
  }

  Future<void> _pushRequested() async {
    while (!_disposed && _rendered != _requested) {
      await _pushSnapshot();
    }
  }

  Future<void> _pushSnapshot() async {
    // Nothing is known-rendered while a push is in flight. A rejection between
    // the two calls leaves the icon and the menu describing different states,
    // and the only honest reading of that is "unknown" — which is what makes
    // the next call push instead of short-circuit.
    _rendered = null;
    final requested = _requested;
    await _icon.setIcon(
      requested.unavailable ? unavailableIconAsset : availableIconAsset,
    );
    // The indicator exists from here on, whatever happens below: `set_icon` is
    // the native call that creates it and sets it ACTIVE. So the A7 rule — no
    // menu before an indicator — is satisfied from this point even if the menu
    // is refused, and a later state change is allowed to try again rather than
    // leaving a live icon with the empty `gtk_menu_new()` `set_icon` attached.
    _installed = true;
    await _icon.setMenu(_menu(requested.line));
    _rendered = requested;
  }

  List<TrayMenuEntry> _menu(String? statusLine) {
    return [
      const TrayMenuEntry(
        key: _openPanelKey,
        label: _openPanelLabel,
        // Enabled in both states, deliberately: see the class doc.
        enabled: true,
      ),
      if (statusLine != null)
        TrayMenuEntry(
          key: _hotkeyUnavailableKey,
          label: statusLine,
          enabled: false,
        ),
      // Last, and after the conditional statement line: the statement explains
      // why one would reach for the entry above it and belongs beside it, and a
      // trailing Quit is what a desktop menu reads like.
      //
      // Enabled in both states for the same reason the open-panel entry is —
      // the tray is the surface that stays reachable when the hotkey is not, so
      // it is the surface that has to carry the way out.
      const TrayMenuEntry(key: _quitKey, label: _quitLabel, enabled: true),
    ];
  }

  void _onSelection(String key) {
    if (_disposed) {
      return;
    }
    switch (key) {
      case _openPanelKey:
        _panelRequests.add(null);
      case _quitKey:
        // The request only — the teardown belongs to the composition root, and
        // an adapter that ended the process could not be tested at all.
        _quitRequests.add(null);
      default:
        // Both arms mean the same thing — a seam that has drifted from the menu
        // it was given — but they are different drifts with different causes,
        // so they do not get one message. The statement line *is* an entry this
        // adapter builds; it is merely disabled. Sending an operator looking
        // for an invented key when a disabled entry was activated points at the
        // wrong fault.
        //
        // Explicitly defensive, and not evidence of a live path: through the
        // shipped seam neither is reachable. `TrayManager` drops a click whose
        // id is not in the menu it currently holds, and the statement entry is
        // pushed `disabled: true`, which the native `_create_menu` renders with
        // `gtk_widget_set_sensitive(item, FALSE)` and so cannot be activated.
        // It is kept because `TrayIcon` is an interface: what reaches here is
        // whatever an implementation of it emits, not what this one does.
        _log(
          () => _logger.warning(
            key == _hotkeyUnavailableKey
                ? 'the tray activated the disabled hotkey-unavailability '
                      'statement entry'
                : 'the tray reported a selection no menu entry carries',
            context: {'key': key},
          ),
        );
    }
  }

  /// Runs one teardown step, reducing its failure to a log line: a daemon that
  /// cannot exit is the worse failure.
  Future<void> _guard(String what, Future<void> Function() run) async {
    try {
      await run();
    } on Object catch (error) {
      _log(() => _logger.error('$what failed', context: _errorContext(error)));
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

/// The only part of a caught error that is safe to put in a log line — see the
/// [Logger] port's doc, and the canonical note in `correction_controller.dart`.
Map<String, Object?> _errorContext(Object error) {
  return {'error_type': error.runtimeType.toString()};
}
