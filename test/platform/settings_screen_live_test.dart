import 'package:flutter_test/flutter_test.dart';

/// The runtime claims the settings-screen story makes and does **not** observe.
///
/// AGENTS.md §8: a claim that is not observed in this container is stated as
/// unobserved. Every widget row this story ships is a test of the widget *tree* —
/// pumped headless, at a surface size the test chose, against a fake config store
/// and a fake hotkey port. This test names what a real desktop session is still
/// owed, so it is owed rather than forgotten. It has no body on purpose: it must
/// never be written in a way that could pass here.
void main() {
  test(
    'CAP-8/CAP-12/AD-10/AD-11: the settings screen on a real display, an X11 '
    'rebind taking effect without a restart, a real portal dialog, a '
    'compositor-side rebind, and a config file changing on disk',
    () {
      fail('this test has no body — see the skip reason');
    },
    skip:
        'not observable in this container: no compositor, no '
        'xdg-desktop-portal, no session bus, no login and no assistive '
        'technology (DW-9, DW-26, DW-44). Two things this row used to put on '
        'that list are not on it any more. keybinder, which it dropped '
        'already: `pkg-config --modversion keybinder-3.0` answers 0.3.2 here. '
        'And "no reachable X display", which it kept — one was stood up on '
        '2026-09-04 and a real panel was watched and driven on it, Xvfb :99 '
        'under openbox 3.6.1, written up in '
        'test/platform/panel-toggle-observation.md, with the premise this row '
        'was repeating refuted in DW-123. What is missing is the session both '
        'of them would need, and every claim below turns on the session '
        'rather than on the display. Matrix D is owed on a session with a '
        'display. '
        '(1) That the screen renders legibly at the window\'s real size — '
        'no Dart code sets a size or a minimum size for the toplevel (DW-50, '
        'DW-53), so the surface every widget row here lays out against is a '
        'choice of the test\'s. The toplevel does have a predicted size: '
        'my_application.cc sets a 1280x720 GTK default that nothing '
        'overrides. (2) CAP-12 on X11: that a hotkey changed here '
        'takes effect without restarting the daemon, which needs a real '
        'keybinder grab and a real key press. (3) AD-11: that a real portal '
        'shows its own dialog when Apply is pressed, that its answer comes '
        'back with `effective: null` and a localized trigger_description as '
        'story 8 measured, and that the screen\'s "this backend cannot report '
        'the combination in effect" is therefore what a Wayland user actually '
        'sees. (4) AD-10: that a rebind made in the compositor\'s own settings '
        'produces a real ShortcutsChanged and updates this screen with no user '
        'action — the port member and both emissions are pinned against a fake '
        'portal on a real bus, which is not a compositor. (5) AD-13: that a '
        'config file edited on disk under a real ConfigStore reaches the '
        'screen at all — nothing watches the file, so the file half of CAP-8 '
        'takes effect on the next restart (filed since story 1) and every '
        'external-edit row here drives ConfigStore.changes directly. (6) That '
        'the affordance and the two views are usable with a real keyboard and '
        'a real screen reader; the semantics assertions here read a semantics '
        'tree, not an assistive technology. '
        'Claim (1) is step 13 of '
        'test/platform/runtime-observation-checklist.md, which opens this '
        'screen at the geometry it just measured and records whether both '
        'views are legible there; claim (2) is step 10. DW-72 — where this '
        'screen\'s affordance actually lands over the editor — is step 15. '
        'Claims (3), (4), (5) and (6) are named on that checklist under "Not '
        'covered here" rather than carried by it, and so is DW-53, which '
        'claim (1) names and neither procedure settles.',
  );
}
