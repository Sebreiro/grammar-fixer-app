import 'package:flutter_test/flutter_test.dart';

/// The runtime claims this story makes and does **not** observe.
///
/// AGENTS.md §8: a claim that is not observed in this container is stated as
/// unobserved. This test names the ones the Wayland portal adapter is owed, so
/// they are owed rather than forgotten. It has no body on purpose — it must never
/// be written in a way that could pass here.
void main() {
  test(
    'CAP-1, CAP-12, AD-11: a real GlobalShortcuts portal accepts the binding '
    'and a real key press raises the panel',
    () {
      fail('this test has no body — see the skip reason');
    },
    skip:
        'not observable in this container, and matrix C of the story records '
        'the whole of what is owed. Missing here: no compositor, no '
        'xdg-desktop-portal, no GlobalShortcuts backend behind one (only GNOME '
        'and KDE ship one at all), no session bus '
        '(DBUS_SESSION_BUS_ADDRESS is unset and /run/user/ is empty, so '
        'DBusClient.session() fails with SocketException — which is why the '
        'no-bus row of the adapter suite is literally the state of this '
        'machine). Correcting one clause this reason used to carry: it said '
        'there was "no way to press a key". There is — xdotool is installed, '
        'and XTEST presses on an Xvfb display drove the entire X11 toggle '
        'measurement here on 2026-09-04 '
        '(test/platform/panel-toggle-observation.md; DW-123 files the premise '
        'this row was repeating). It buys nothing on this path, which is why '
        'the rest of the reason stands unchanged: with no GlobalShortcuts '
        'backend there is no portal to accept a binding and nothing to '
        'deliver an Activated signal, so a synthetic press reaches no '
        'shortcut of ours. What is owed on a real desktop: '
        'that the portal dialog appears, that the compositor accepts the '
        'binding rather than discarding it, that Activated arrives on a real '
        'press inside CAP-1 100 ms budget, that ShortcutsChanged arrives after '
        'a rebind made in the compositor own settings, and that the bind '
        'survives at all. That last one has a **precondition rather than a '
        'defect** behind it: AD-11 requires an installed .desktop file whose '
        'basename matches the reverse-DNS application id, and shipping '
        'com.divertedriver.HotkeyGrammarCorrector.desktop is the packaging '
        'story. Until it ships, a real GNOME session is expected to return an '
        'empty shortcuts set and this adapter is expected to report the hotkey '
        'unavailable naming that file — which is a correct report, not a bug in '
        'this code. What is proven instead, by tests that do run: the whole '
        'AD-11 call order, the Registry tolerance, the read-back check, every '
        'AD-12 refusal, the Request/Response race and the teardown, against a '
        'fake portal service on a real in-process D-Bus bus '
        '(wayland_portal_global_hotkey_test.dart); and the trigger '
        'serialization against keysym names measured with xkb_keysym_from_name '
        'on the installed xkbcommon 1.6.0 (xdg_shortcut_trigger_test.dart). '
        'Neither is a runtime observation of a desktop and neither may be '
        'reported as one.',
  );
}
