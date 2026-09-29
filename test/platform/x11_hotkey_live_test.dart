import 'package:flutter_test/flutter_test.dart';

/// The runtime claims this story makes and does **not** observe.
///
/// AGENTS.md §8: a claim that is not observed in this container is stated as
/// unobserved. This test names the ones the X11 hotkey adapter is owed, so they
/// are owed rather than forgotten. It has no body on purpose — it must never be
/// written in a way that could pass here.
void main() {
  test(
    'CAP-1, CAP-12: a real X11 grab fires the panel in under 100 ms, and a '
    'rebind in settings takes effect without restarting the daemon',
    () {
      fail('this test has no body — see the skip reason');
    },
    skip:
        'not observable in this container. keybinder-3.0 grabs keys on an X '
        'display belonging to a session, and there is no session here: no '
        'compositor and no window manager, no xdg-desktop-portal, no session '
        'bus (DBUS_SESSION_BUS_ADDRESS is unset and /run/user/ is empty) and '
        'no login. Correcting what this reason used to say, twice over, and '
        'the second correction is the one this row cost the most. It first '
        'claimed keybinder-3.0, Xvfb, xvfb-run and xdotool were absent; all '
        'four are installed here. It then conceded that and argued the '
        'concession bought nothing, because every claim below is about the '
        'session and not the display — a grab firing out from under a focused '
        'application, a panel a user sees arrive, a summon timed against a '
        'screen — and concluded that "standing one up would produce a result '
        'about Xvfb". That conclusion is false. One was stood up on '
        '2026-09-04: Xvfb :99 plus openbox 3.6.1 plus the built release '
        'bundle, and it produced a real X11 grab that caught a real xdotool '
        'press, a real mapped and focused panel, a real focus-loss hide, and '
        'a major CAP-14 defect that a whole phase of green rows had not found '
        '(G-01-13, closed as DW-122; the run is '
        'test/platform/panel-toggle-observation.md and the refutation of the '
        'premise this row was repeating is DW-123). It did not produce a '
        'result about Xvfb. It produced the defect. Filed as '
        'DW-44; DW-9 and DW-26 record the same missing session for the window '
        'and the panel, which are different claims. What is proven instead, by tests '
        'that do run: the bind outcome logic, the release-then-grab order and '
        'every refusal path against a HotkeyRegistrar fake '
        '(x11_global_hotkey_test.dart); and the label-to-usage serialization '
        'against explicit numbers (hotkey_key_catalogue_test.dart). The seam '
        'itself has no automated suite: the mocked-channel one that used to '
        'cover the keyval, the modifier names and the register/unregister order '
        'went with the hotkey_manager plugin, and X11KeyGrabRegistrar cannot be '
        'driven by a mocked channel — it needs a real X server. It was '
        'exercised by hand against an Xvfb display when it landed (a contended '
        'grab refused, an uncontended one held, presses delivered, and still '
        'delivered with NumLock latched), which is recorded in phase 1 plan 02 '
        'summary rather than pinned by a test. What is owed on a real session: '
        'that a press raises the panel inside CAP-1 100 ms budget, and that the '
        'CAP-12 rebind is live without a restart. Whether the grab succeeded is '
        'no longer among them — XSetErrorHandler plus XSync makes a refusal '
        'readable and named, which is exactly what the discarded '
        'keybinder_bind result made impossible. Those are group D of '
        'test/platform/runtime-observation-checklist.md — step 8 for the '
        'grab itself, step 9 for the refusal now being readable, step 10 for '
        'the CAP-12 rebind and step 12 for the 100 ms budget.',
  );
}
