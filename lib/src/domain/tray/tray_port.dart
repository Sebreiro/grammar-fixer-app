import 'hotkey_tray_status.dart';

/// The tray icon and menu — the daemon's always-reachable surface.
abstract interface class TrayPort {
  /// Puts the icon and menu in the tray. Called once at startup.
  Future<void> install();

  /// Emits when the user asks to open the panel from the tray menu — the
  /// path that keeps the app usable when no global hotkey is bound (AD-12).
  /// Broadcast: a user-event notification stream that may have multiple
  /// independent listeners.
  Stream<void> get panelRequests;

  /// Emits when the user asks to stop the daemon from the tray menu.
  ///
  /// The tray's half of the daemon's two exit triggers, and the only one a
  /// user has: without it a resident daemon can be stopped by a signal alone,
  /// which a tray-only user has no way to send (DW-114). The other trigger is
  /// SIGINT/SIGTERM/SIGHUP, and both reach the *same* ordered teardown — this
  /// stream carries the request, never the teardown itself.
  ///
  /// Broadcast, like [panelRequests]: a user-event notification stream that may
  /// have multiple independent listeners.
  Stream<void> get quitRequests;

  /// Shows or clears a neutral unavailable notice during startup binding
  /// (AD-12). A typed status supersedes this seed, even if the startup bind
  /// resolves later.
  Future<void> setHotkeyUnavailable(bool unavailable);

  /// Applies the same current result and refusal notice shown in Settings.
  /// The boolean setter above is retained for the startup bind hand-off.
  Future<void> setHotkeyStatus(HotkeyTrayStatus status);
}
