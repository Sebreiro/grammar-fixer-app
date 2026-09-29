/// Which display server this session is running under (AD-9).
///
/// Detection is a pure function over an injected environment map, which is the
/// only shape that can be exercised with no session at all — and the daemon
/// asks exactly once, at startup, because AD-9 forbids a runtime switch
/// between the two hotkey adapters.
enum DisplayServer {
  x11,
  wayland;

  /// AD-9's rule, in order: `XDG_SESSION_TYPE` decides when it names a session
  /// type this app knows; otherwise a non-empty `WAYLAND_DISPLAY` means
  /// Wayland; otherwise X11.
  ///
  /// X11 is the fallback rather than an error because a session that reports
  /// nothing is far more often a bare X server than a Wayland compositor
  /// hiding its socket — and AD-12 makes a wrong guess a visible
  /// `HotkeyUnavailable`, not a crash.
  ///
  /// That last clause is a claim about the X11 adapter's no-display path, and
  /// it is worth naming what has to hold for it to be true, because it was
  /// false once. `X11KeyGrabRegistrar` answers a failed `XOpenDisplay` with a
  /// `noBackend` refusal, `X11GlobalHotkey` maps that code to
  /// `HotkeyUnavailableCause.noBackend`, and the worker's teardown skips
  /// `XCloseDisplay` when no display was ever opened. Drop the last of those
  /// three and a wrong guess here is a `SIGSEGV` on every exit path rather
  /// than a sentence on the settings screen.
  static DisplayServer fromEnvironment(Map<String, String> environment) {
    final sessionType = environment['XDG_SESSION_TYPE']?.trim().toLowerCase();
    if (sessionType == 'wayland') {
      return DisplayServer.wayland;
    }
    if (sessionType == 'x11') {
      return DisplayServer.x11;
    }
    // Trimmed like the session type, and for a sharper reason: this choice is
    // made once and AD-9 forbids a runtime switch, so a stray space in an
    // exported variable would pin an X11 session to the Wayland adapter for
    // the life of the daemon.
    final waylandDisplay = environment['WAYLAND_DISPLAY']?.trim();
    if (waylandDisplay != null && waylandDisplay.isNotEmpty) {
      return DisplayServer.wayland;
    }
    return DisplayServer.x11;
  }
}
