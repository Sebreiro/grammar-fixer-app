import 'package:flutter_test/flutter_test.dart';

/// The runtime claims this story makes and does **not** observe.
///
/// AGENTS.md §8: a claim that is not observed in this container is stated as
/// unobserved. This test names the one the tray adapter is owed, so it is owed
/// rather than forgotten. It has no body on purpose — it must never be written
/// in a way that could pass here.
void main() {
  test(
    'AD-12: the indicator appears on a real desktop, its menu opens the panel, '
    'and the unavailable state is visible on both the icon and the menu',
    () {
      fail('this test has no body — see the skip reason');
    },
    skip:
        'not observable in this container, and nothing a display can supply '
        'changes that. A StatusNotifier/AppIndicator host is what puts an '
        'icon in a tray, and there is none here — no compositor, no panel or '
        'shell hosting a StatusNotifier, and no xdg-desktop-portal. '
        'Correcting one clause this reason used to carry: it said there was '
        '"no reachable X display" and "no Xvfb/xvfb-run to stand one up". '
        'Both are installed, and one was stood up on 2026-09-04 with a real '
        'mapped panel watched and driven on it — Xvfb :99 under openbox '
        '3.6.1, written up in test/platform/panel-toggle-observation.md, with '
        'the premise refuted in DW-123. It changes nothing for this row: an X '
        'server with a bare window manager hosts no StatusNotifier item, so '
        'there is still nothing here to draw an indicator into, and this '
        'row\'s whole subject is exactly as unobservable as it was. Recorded '
        'as DW-9/DW-26 for the display half. What is '
        'proven instead, by tests that do run: the menu wiring and the state '
        'mapping against a TrayIcon fake (tray_manager_tray_test.dart), and '
        'the translation to menu_base and the click route against a mocked '
        'tray_manager channel (tray_manager_tray_icon_test.dart). What '
        'is owed on a real session: that the icon is actually drawn from the '
        'bundled asset path, that picking the open-panel entry raises the '
        'panel end to end, that the degraded icon plus the disabled '
        'statement line are both legible to a user on a wlroots compositor, '
        'and — since DW-114 gave the menu a Quit entry — that picking Quit '
        'actually stops the daemon and clears the indicator from the tray: '
        'that the ordered teardown runs to its end, that the process is gone '
        'afterwards rather than resident with no icon, and that the '
        'StatusNotifier item is removed rather than left as a dead entry the '
        'host keeps drawing. Nothing here can observe any of it, because '
        'nothing here hosts an indicator to pick from in the first place.',
  );
}
