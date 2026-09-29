import 'package:flutter_test/flutter_test.dart';

/// The runtime claims the packaging story makes and does **not** observe.
///
/// AGENTS.md §8: a claim that is not observed in this container is stated as
/// unobserved. `test/architecture/desktop_entries_test.dart` reads file
/// contents and runs the installer into a temporary XDG tree — a check of bytes
/// and paths — and every row in it is green. None of that is evidence about a
/// desktop, and a reader of the run output would see only passing rows about a
/// feature whose whole purpose is what a compositor does with the files. This
/// row exists so the gap is visible in the same place the green is. It has no
/// body on purpose — it must never be written in a way that could pass here.
void main() {
  test(
    'AD-11, AD-14: a real session honours the installed desktop entries',
    () {
      fail('this test has no body — see the skip reason');
    },
    skip:
        'not observable in this container. Missing here: no compositor, no '
        'xdg-desktop-portal and no GlobalShortcuts backend behind one, no '
        'session bus (DBUS_SESSION_BUS_ADDRESS is unset and /run/user/ is '
        'empty), no login session to autostart anything, no XDG_RUNTIME_DIR '
        'holding a real daemon socket, and no desktop-file-validate to check '
        'the entries against the specification rather than against the '
        'hand-rolled reader in desktop_entries_test.dart. What is owed on a '
        'real GNOME (and ideally KDE) session, all four of which are what '
        'AD-11 and AD-14 actually promise: (1) that the compositor associates '
        'the app id the daemon registers with '
        'com.divertedriver.HotkeyGrammarCorrector.desktop installed under '
        '\${XDG_DATA_HOME:-~/.local/share}/applications/, which is the '
        'association g_set_prgname exists to create; (2) that the '
        'GlobalShortcuts bind survives *because of* that association — the '
        'observable being that the same bind is discarded when the file is '
        'removed, since a bind that works either way proves nothing about the '
        'file; (3) that the autostart entry under '
        '\${XDG_CONFIG_HOME:-~/.config}/autostart/ actually starts the daemon '
        'at login and leaves the hotkey live without anyone launching it — a '
        'tray indicator is extra evidence rather than part of the fact, since '
        'stock GNOME Wayland hosts none without the AppIndicator extension; and (4) that an autostarted daemon plus a manual launch resolve '
        'to one instance — the manual launch reaching AD-14 singleton lock, '
        'raising the running instance panel and exiting 0 rather than binding '
        'the hotkey a second time. Note that (4) is not what identical Exec '
        'lines buy: SingleInstanceLock derives its address from '
        'XDG_RUNTIME_DIR and never reads Exec, so two *different* commands '
        'would meet the same lock. Identical Exec buys that login starts the '
        'same binary a user would. Recorded as deferred-work DW-87. '
        'All four are written up as steps in '
        'test/platform/desktop-session-checklist.md — step 2 for the '
        'association, step 3 for the bind surviving because of the file, '
        'step 4 for autostart at login and step 5 for the manual second '
        'launch — each with an expected result and what to write down when '
        'it diverges.',
  );
}
