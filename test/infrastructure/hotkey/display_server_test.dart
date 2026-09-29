import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/display_server.dart';
import 'package:test/test.dart';

/// AD-9's detection rule, exercised as the pure function it is: the daemon
/// asks once at startup and constructs exactly one hotkey adapter, so getting
/// this wrong means the whole hotkey layer is wrong with no runtime recovery.
///
/// Pure Dart over an injected map: no session, no binding (AGENTS.md §7).
void main() {
  group('AD-9: XDG_SESSION_TYPE decides when it names a known type', () {
    test('CAP-1: XDG_SESSION_TYPE=wayland selects the Wayland adapter', () {
      expect(
        DisplayServer.fromEnvironment({'XDG_SESSION_TYPE': 'wayland'}),
        DisplayServer.wayland,
      );
    });

    test('CAP-1: XDG_SESSION_TYPE=x11 selects the X11 adapter', () {
      expect(
        DisplayServer.fromEnvironment({'XDG_SESSION_TYPE': 'x11'}),
        DisplayServer.x11,
      );
    });

    test('CAP-1: the session type wins over WAYLAND_DISPLAY', () {
      expect(
        DisplayServer.fromEnvironment({
          'XDG_SESSION_TYPE': 'x11',
          'WAYLAND_DISPLAY': 'wayland-0',
        }),
        DisplayServer.x11,
        reason:
            'XDG_SESSION_TYPE is the primary signal; the display variable '
            'is only the fallback',
      );
    });

    test('CAP-1: the session type is read case- and whitespace-insensitively, '
        'because it is an environment variable a user can set by hand', () {
      expect(
        DisplayServer.fromEnvironment({'XDG_SESSION_TYPE': ' Wayland '}),
        DisplayServer.wayland,
      );
    });
  });

  group('AD-9: WAYLAND_DISPLAY is the fallback', () {
    test('CAP-1: an unset session type plus a non-empty WAYLAND_DISPLAY '
        'selects Wayland', () {
      expect(
        DisplayServer.fromEnvironment({'WAYLAND_DISPLAY': 'wayland-0'}),
        DisplayServer.wayland,
      );
    });

    test('CAP-1: an unrecognised session type falls through to '
        'WAYLAND_DISPLAY', () {
      expect(
        DisplayServer.fromEnvironment({
          'XDG_SESSION_TYPE': 'tty',
          'WAYLAND_DISPLAY': 'wayland-0',
        }),
        DisplayServer.wayland,
      );
    });
  });

  group('AD-9: neither signal means X11', () {
    test('CAP-1: an empty environment selects the X11 adapter', () {
      expect(DisplayServer.fromEnvironment({}), DisplayServer.x11);
    });

    test('CAP-1: an empty WAYLAND_DISPLAY is not a Wayland session', () {
      expect(
        DisplayServer.fromEnvironment({'WAYLAND_DISPLAY': ''}),
        DisplayServer.x11,
      );
    });

    test('CAP-1: an unrecognised session type with no WAYLAND_DISPLAY selects '
        'the X11 adapter', () {
      expect(
        DisplayServer.fromEnvironment({'XDG_SESSION_TYPE': 'tty'}),
        DisplayServer.x11,
      );
    });
  });
}
