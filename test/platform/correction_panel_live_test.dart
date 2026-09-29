import 'package:flutter_test/flutter_test.dart';

/// The runtime claims the panel story makes and does **not** observe.
///
/// AGENTS.md §8: a claim that is not observed in this container is stated as
/// unobserved. Every widget test the panel ships is a test of the widget *tree*
/// — pumped headless, at a surface size the test chose, against a fake
/// clipboard. This test names what a real desktop session is still owed, so it
/// is owed rather than forgotten. It has no body on purpose: it must never be
/// written in a way that could pass here.
void main() {
  test(
    'CAP-1/CAP-10/CAP-11/CAP-14: the panel appears focused, hides on focus '
    'loss, copies to the real clipboard, and fits the window it is given',
    () {
      fail('this test has no body — see the skip reason');
    },
    skip:
        'not observable in this container, with one claim struck out below '
        'because it was observed after all. Correcting what this reason used '
        'to say: it asserted "no compositor and no reachable X display (DW-9, '
        'DW-26), so nothing about the panel *on screen* is seen". The display '
        'half is false — Xvfb :99 under openbox 3.6.1 was stood up here on '
        '2026-09-04 and the panel was watched on it, four routes at a time '
        '(DW-123 files the correction, DW-122 the defect it found). What is '
        'genuinely missing is the session the remaining claims need: no '
        'xdg-desktop-portal, no session bus, no login, no real system '
        'clipboard consumer, no real input method and no real keyboard. Five '
        'claims were owed on a session with a display; four still are. (1) '
        'CAP-1: '
        'that the summoned panel is visible and focused within 100 ms, and '
        'that the caret is in the editor when it arrives — the widget test '
        'proves only that the editor holds primary focus inside the tree, '
        'which says nothing about the toplevel holding the keyboard. (2) '
        'CAP-14: that the focus-loss hide leaves it dismissed rather than '
        'flickering, with the panel never calling hide() itself. '
        'OBSERVED — and this row wrote the defect down a year before anyone '
        'found it. "Dismissed rather than flickering, with the panel never '
        'calling hide() itself" is G-01-13 stated in advance, in this '
        'sentence, by a row that could not run. It is exactly what was '
        'happening: the daemon dismissed its own panel on its own shortcut '
        'and the toggle re-mapped it 8-16 ms later, so the panel flickered '
        'and never stayed hidden. Measured, diagnosed and fixed in 2026-09 '
        '(DW-122), then confirmed against a recorded baseline in '
        'test/platform/panel-toggle-observation.md: the hide route moved '
        'FLICKER to HIDE and the alternate route SHOW,FLICKER,FLICKER,FLICKER '
        'to SHOW,HIDE,SHOW,HIDE. This is the single best piece of evidence in '
        'this repository that a bodyless skipped row is worth writing. What '
        'the claim is still owed is a real desktop: one window manager on a '
        'synthetic server is neither GNOME/Mutter nor KDE/KWin. (3) CAP-11: '
        'that `ClipboardPort.writeText` reaches the real system clipboard and '
        'that a paste in another application yields exactly the copied '
        'variant; every copy assertion here reads FakeClipboardPort.writes. '
        '(4) CAP-10: that the original and a variant are both readable at the '
        'window\'s actual size — no Dart code sets a size or a minimum size '
        'for the toplevel, and CorrectionPanel.minimumPanelHeight is a floor '
        'the panel scrolls below rather than a size anything enforces. The '
        'size is not unpredicted, though: my_application.cc sets a 1280x720 '
        'GTK default and nothing overrides it, so the real surface is the '
        'Flutter template default rather than one chosen for this panel. '
        '(5) that '
        'Ctrl+Enter and the 1/2/3 keys arrive as this panel expects through a '
        'real input method and a real keyboard layout, including a keypad '
        'with Num Lock off, which the test key simulator does not model. '
        'Claims (1), (2) and (4) are steps on '
        'test/platform/runtime-observation-checklist.md — steps 5 and 6 for '
        'the focus half of claim (1) and for claim (2), step 12 for claim '
        '(1)\'s 100 ms half, which those two do not time, and step 13 for '
        'the size the window is actually given, which is DW-50. Claims (3) '
        'and (5) are named there under "Not covered here": they stay this '
        'suite\'s own.',
  );
}
