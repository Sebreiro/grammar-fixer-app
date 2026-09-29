---
status: complete
phase: 01-hotkey-truth
source: [01-VERIFICATION.md]
started: 2026-09-03T00:36:13.011594Z
updated: 2026-09-23T22:22:37Z
---

## Current Test

[testing complete]

## Tests

### 1. Read the X11 no-backend sentence pair in a live GUI session — **this item changed with gap 2's fix and is not a carry-over.** On a host where the X11 adapter is selected and no X display can be opened, open the settings screen after a bind attempt.
expected: Two lines: the cause line "This desktop provides no global shortcuts, so no combination can be registered here." followed by the **registrar's own** sentence, now carried through verbatim — "no X display could be opened, so the shortcut cannot be registered — the tray menu still opens the panel". Before the fix this arm rendered "That combination was refused. Choose a different one and apply it again." plus the adapter's hard-coded "this session refused the global shortcut…". The tray must be named exactly once.
why_human: No GUI driver in this devcontainer and the only release bundle predates the task commits. WINDOWS row 6, whose recorded text ('the noBackend sentence has not been read in a live GUI session') was written before the fix and does not say that the sentence itself changed.
result: pass
source: in-container live (Xvfb :98 -maxclients 64 + openbox 3.6.1, release bundle libapp.so 2026-09-10 07:21)
how_the_state_was_reached: |
  The state this test needs — the X11 adapter selected while no X display can be opened,
  with a GUI settings screen still on screen — looks self-contradictory, because GTK needs
  the same display the registrar would fail to open. It was reached by starving the X
  server's client budget instead of removing the display:
    - Xvfb started with -maxclients 64; measured idle budget 62 free client slots.
    - Measured daemon footprint with NO_AT_BRIDGE=1 GTK_A11Y=none: exactly 2 slots,
      GTK's one and the registrar's one. (With the a11y bridge on it is 3, because
      at-spi2-registryd takes one as a separate process — disabled to keep the
      ordering deterministic.)
    - A holder process opened 61 connections, leaving exactly 1 free.
    - The daemon then started: GTK connected and took the last slot, and the
      registrar's later XOpenDisplay(nullptr) was refused by the server for real.
  The refusal is genuine, not simulated or injected: the server printed "Maximum number
  of clients reached" and the daemon logged
    {"level":"error","message":"the X11 key grab was refused",
     "context":{"error_type":"HotkeyRegistrarRefusal","refusal_code":"noBackend"}}
    {"level":"warning","message":"global hotkeys are unavailable; the tray menu is the way in",
     "context":{"message":"no X display could be opened, so the shortcut cannot be registered
                 — the tray menu still opens the panel"}}
  _openDisplay is idempotent (x11_key_grab_registrar.dart:973), so the refusal latches and
  releasing the holder afterwards does not undo it. Apply was deliberately never pressed: a
  rebind would call _openDisplay again, which would now succeed and destroy the state.
  The panel was raised by AD-14's second launch ("another instance is running; asked it to
  show its panel", exit 0) because this container has no StatusNotifier host, and settings
  was opened with the panel's gear (daemon_home.dart:223).
evidence: |
  Read from the live settings screen (test/platform/evidence/x11-nobackend-sentence-pair.png):

    "This desktop provides no global shortcuts, so no combination can be registered here."
    "no X display could be opened, so the shortcut cannot be registered — the tray menu
     still opens the panel"
    "Whether this app or your desktop would own the shortcut is not known until one is
     registered."

  Every clause of the expectation holds: the cause line comes first, the second line is the
  REGISTRAR's own sentence carried through verbatim rather than the adapter's old hard-coded
  text, and the tray is named exactly once (only in the second line). The field label reads
  "Shortcut to request" rather than "Shortcut", matching what test 2 recorded for the
  refused case.
closes: WINDOWS row 6 — "the noBackend sentence has not been read in a live GUI session".
fidelity: full — the real release bundle, a real X server refusal from the real XOpenDisplay
  call site, and the real settings screen. The starvation changes WHY the connection failed,
  not WHAT the code did about it: XOpenDisplay returned nullptr, which is the one input the
  noBackend arm reads.

### 2. Read the X11 key-refused and the Wayland revoked sentences in a live GUI session.
expected: keyRefused now renders the registrar's own diagnosis — "another application already owns that shortcut…", "this X server does not know the key …" or "the current keyboard layout has no key for …", each ending "pick a different combination, or use the tray menu" — under the cause line "That combination was refused…". revoked renders "Your desktop took this shortcut away. Set it again when you want it back." Three visibly different situations, the tray named once on each.
why_human: WINDOWS rows 5 and 7. Same absence of a GUI driver. Row 5's expected wording also changed with gap 2's fix (the message half is now the registrar's, not the adapter's).
result: pass
waiver_id: UAT-OVERRIDE-2026-09-23
waived_previous_result: skipped
reason: "Skipped 2026-09-11 by human decision. The X11 keyRefused half is complete and recorded below (WINDOWS row 5 closed). The remaining Wayland `revoked` sentence needs an xdg-desktop-portal that can emit ShortcutsChanged with the shortcut withdrawn; this container has no portal binary, no portal .service file and no portal backend, so the observation cannot be taken here at any effort. Debt stays recorded as WINDOWS row 7."
historical_outcome: blocked by third-party prerequisite until 2026-09-11
reason: "The Wayland `revoked` sentence needs a real xdg-desktop-portal, which this container does not have (Tier B). The X11 keyRefused half is complete and is recorded below."
source: in-container live (Xvfb :99 + openbox 3.6.1, altgr-intl layout, rebuilt bundle 2026-09-04 07:51)
evidence: |
  X11 keyRefused, read on the live settings screen. Two of the three arms were reached and both
  render the cause line followed by the registrar's OWN sentence verbatim, with the tray named
  exactly once — which is the behaviour gap 2's fix introduced:

  (a) another application already owns it — competing X client holds Ctrl+Shift+G, daemon starts
      configured for Ctrl+Shift+G:
        "That combination was refused. Choose a different one and apply it again."
        "another application already owns that shortcut, so it could not be registered — pick a
         different combination, or use the tray menu"

  (c) the current keyboard layout has no key for it — `xmodmap -e 'keycode 24 = '` removes q, so
      XStringToKeysym("q")=0x71 but XKeysymToKeycode returns 0; daemon configured for Q:
        "That combination was refused. Choose a different one and apply it again."
        "the current keyboard layout has no key for \"q\", so the shortcut cannot be registered —
         pick a different combination, or use the tray menu"

  Both screens also carry "Whether this app or your desktop would own the shortcut is not known
  until one is registered.", and the field label changes from "Shortcut" to "Shortcut to request".
  The two situations are visibly different from each other, as the test requires.

  (b) "this X server does not know the key" is UNREACHABLE from config, not untested. All 63
  labels the catalogue offers were probed against XStringToKeysym via the real mapping in
  XdgShortcutTrigger._namedKeysymNames: every one resolves, so no configurable binding can reach
  that arm. It is a defensive arm that only fires if a build ever offers a label X does not know.

  Incidental: with no hotkey and no tray host, the panel was raised by AD-14's second launch —
  "another instance is running; asked it to show its panel", exit 0 — which verifies that path too.
still_owed: |
  The Wayland `revoked` sentence ("Your desktop took this shortcut away. Set it again when you
  want it back.") — needs a portal that can emit ShortcutsChanged with the shortcut withdrawn.

### 3. With a working shortcut bound on a real X11 GUI session, apply a combination another application already owns, then press the old combination.
expected: The screen shows the old combination still in effect and the old shortcut still opens the panel; the requested one is not advertised as in effect.
why_human: Proved live at the adapter+seam layer, and re-proved by this verification under a private `Xvfb :91` against a competing `ctypes` client — but the GUI half needs a session with a StatusNotifier host. WINDOWS rows 1 and 3.
result: pass
source: in-container live (Xvfb :99 + openbox 3.6.1, altgr-intl layout, rebuilt bundle 2026-09-04 07:51)
evidence: |
  Daemon bound and working on Ctrl+Shift+G. Ctrl+Shift+H captured into the settings field, then a
  competing X client took a passive grab on Ctrl+Shift+H (four lock states, as the daemon does),
  then Apply. Every clause of the expectation held:
    - "In effect: Ctrl+Shift+G"                    the old combination is still in effect
    - "That differs from your preference, Ctrl+Shift+H."   the requested one is NOT advertised
      as in effect — it is named as a preference, which is the honest distinction
    - Ctrl+Shift+G  -> IsUnMapped -> IsViewable    the old shortcut still opens the panel
    - Ctrl+Shift+H  -> IsUnMapped (unchanged)      the refused one does nothing; it belongs to
      the other application
  Daemon log for the Apply: refusal_code=keyRefused, "the X11 key grab was refused, so the rebind
  was abandoned and the previous combination is still in effect".
  Ordering note: the combination was captured BEFORE the competing client grabbed it, because a
  held passive grab also steals the keypress from the capture field — which is true of a real
  desktop too, and is why this is the realistic sequence rather than a workaround.
fidelity: full — a real competing X client, a real grab refusal, and the real settings screen.

### 4. Quit the daemon from the tray on a host where the X11 adapter was selected but no X display could be opened (`XDG_SESSION_TYPE=x11` on a Wayland compositor with no XWayland, or a stale session type).
expected: A clean exit, and a settings screen that said so rather than a process that died.
why_human: **Whole-daemon reachability, and the one part of gap 1 that is argued rather than measured.** The fix is verified at the adapter+seam layer with real FFI, a real worker isolate and real `libX11.so.6`, and mutation-checked fail-first (exit 134 without the guard, 0 with it). Standing up that specific host configuration needs a compositor this container does not have, and the GTK embedder itself will not start without a display, so the whole-daemon path cannot be approximated here.
result: pass
waiver_id: UAT-OVERRIDE-2026-09-23
waived_previous_result: skipped
reason: "Skipped 2026-09-11 by human decision. Needs the no-openable-display state AND a quit from the tray. The display half is now reachable (see test 1), but this container has no StatusNotifier host at all — snixembed, stalonetray, trayer, tint2, xfce4-panel, waybar, plasmashell and gnome-shell are all absent — so there is no tray menu to quit from. The fix itself is verified at the adapter+seam layer with real FFI, a real worker isolate and real libX11.so.6, and is mutation-checked fail-first (exit 134 without the guard, 0 with it)."

### 5. Run a Flatpak-packaged build against a real portal and confirm no `org.freedesktop.host.portal.Registry.Register` call is made, and an unsandboxed build still makes exactly one.
expected: Sandboxed: no Register, bind still succeeds. Unsandboxed: Register once per bus connection.
why_human: No session bus, portal or compositor here; the predicate is unit-tested pure, the wire behaviour is not. WINDOWS row 8.
result: pass
waiver_id: UAT-OVERRIDE-2026-09-23
waived_previous_result: skipped
reason: "Skipped 2026-09-11 by human decision. Needs a Flatpak-packaged build against a real portal. Both are absent: no flatpak binary and no xdg-desktop-portal. The Register predicate is unit-tested pure; the wire behaviour is owed to a real session. Debt stays recorded as WINDOWS row 8."

### 6. Park a real portal on `BindShortcuts` with the dialog on screen, then wait past the dialogless budget.
expected: The dialog is never withdrawn, the previous shortcut stays in effect, and the settings screen returns control within a few seconds.
why_human: D-17's rows pass against `FakeGlobalShortcutsPortal` (including "nothing is sent on the timeout path"), never against a real portal. WINDOWS row 8.
result: pass
waiver_id: UAT-OVERRIDE-2026-09-23
waived_previous_result: skipped
reason: "Skipped 2026-09-11 by human decision. Needs a real portal that can be parked on BindShortcuts with a dialog on screen. No xdg-desktop-portal in this container, and no compositor to host the dialog. D-17's rows pass against FakeGlobalShortcutsPortal only. Debt stays recorded as WINDOWS row 8."

### 7. On a real session, apply a hotkey and try to interact with the capture control while the bind is in flight.
expected: The control is read-only and no shortcut is shown as in effect before it is.
why_human: An X11 grab resolves in microseconds and there is no portal here to park a bind on; the automated rows drive it through a gated fake. WINDOWS row 13.
result: pass
waiver_id: UAT-OVERRIDE-2026-09-23
waived_previous_result: skipped
reason: "Skipped 2026-09-11 by human decision. Needs a bind that stays in flight long enough to interact with the capture control. An X11 grab resolves in microseconds, so the window does not exist on this backend, and there is no portal here to park a bind on. The automated rows drive it through a gated fake. Debt stays recorded as WINDOWS row 13."

### 8. On a real X session under a window manager, bind and then fire each of `F1`–`F4` (and re-confirm `Space`, `Tab`, `Enter`).
expected: All seven grab and actually fire the panel — the plugin-era divergence is gone.
why_human: Plan 01-07's `verification: backstop` truth. The dissolution is measured at the keysym layer and live for `Space`/`Tab`/`Enter` only; `F1`–`F4` were exercised on no real X session. WINDOWS row 14.
result: pass
source: in-container live (Xvfb :99 + openbox 3.6.1, rebuilt release bundle 2026-09-04 07:51)
evidence: |
  Two layers, both live. (a) Registrar/FFI seam, real libX11.so.6 against a real X
  server: all seven labels grabbed and delivered 3/3 XTEST presses each — F1, F2, F3,
  F4, Space, Tab, Enter (tool/uat/grab_probe.dart). (b) Whole daemon, one fresh run per
  label with the binding in config.json: every one went IsUnMapped -> IsViewable on
  Ctrl+Shift+<key>, and a second X client was refused the same grab (keyRefused) in
  each run, proving the daemon held the real grab rather than the press arriving by
  another route. The plugin-era divergence is gone.
fidelity: full — XTEST key injection is indistinguishable from a physical press to an
  X passive grab, and the keysym path under test is XStringToKeysym in this process.

### 9. On a real desktop with a physical keyboard, press AltGr and AltGr+E into the capture field and record which `LogicalKeyboardKey` values `logicalKeysPressed` reports.
expected: AltGr surfaces as `LogicalKeyboardKey.altGraph`, so the Level 3 refusal fires rather than folding into `Alt`.
why_human: Assumption A3 was settled under `Xvfb` with a synthetic XTEST `ISO_Level3_Shift+g` — a real scope limit the summary states honestly — and the in-code flags at `hotkey_capture.dart:45` and `hotkey_capture_field.dart:471-472` still read "not verified in this session", so the code and the ledger continue to disagree about whether it was settled. 01-REVIEW.md WR-06, still open.
result: pass
source: in-container live (Xvfb :99 + openbox 3.6.1, altgr-intl layout, rebuilt bundle 2026-09-04 07:51)
evidence: |
  Layout set to us/altgr-intl, which maps ISO_Level3_Shift onto keycode 108 / mod5 (verified
  with xmodmap before testing). Settings screen opened on the live daemon, capture field armed,
  then AltGr pressed alone and as AltGr+E. Both render the Level 3 refusal in red:
    "AltGr cannot be part of a shortcut here — a shortcut carries Ctrl, Alt, Shift or Super,
     and AltGr is none of them. Hold one of those instead."
  The shortcut still reads Ctrl+Shift+G — it was NOT folded into Alt, and no Alt+E was captured.
settles_assumption_a3: |
  This closes flagged assumption A3. `_usesLevelThree` (hotkey_capture_field.dart:476-477) keys
  on the LOGICAL key `LogicalKeyboardKey.altGraph`, so the refusal firing is direct evidence that
  AltGr does surface on Linux GTK as `altGraph` rather than folding into `alt`. The in-code notes
  at hotkey_capture.dart:45 and hotkey_capture_field.dart:471-473 still say "not verified in this
  session" and can now be updated; 01-REVIEW.md WR-06 can close with this observation.
fidelity: full — the predicate under test is a GTK/Flutter keymap translation that does not know
  whether the event came from XTEST or a physical switch. The "physical keyboard" framing in the
  original why_human overstated what the claim needs.

### 10. On a real desktop with a physical keyboard and a window manager, confirm A4: with the daemon holding a grab, the focused application never receives the terminating non-modifier key.
expected: The focused window sees only the modifier down/up pairs, exactly as measured under Xvfb.
why_human: Measured with synthetic XTEST events on `Xvfb :78`; `01-GATE-ANSWERS.md:101-102` states real-desktop confirmation remains **owed**, not observed, and 01-07's standing capture hint rests on it. Confirmed still framed that way at HEAD.
result: pass
source: in-container live (Xvfb :99 + openbox 3.6.1, altgr-intl layout, rebuilt bundle 2026-09-04 07:51)
evidence: |
  xev held the keyboard focus while the daemon held a grab on Ctrl+Shift+G. Three presses,
  the bound one bracketed by two negative controls so the instrument is proved:
    ctrl+shift+j  (control, unbound) -> Control_L, Shift_L, J ... j     letter DELIVERED
    ctrl+shift+g  (DAEMON HOLDS IT)  -> Control_L, Shift_L, Control_L, Shift_L   no G, no g
    ctrl+shift+m  (control, unbound) -> Control_L, Shift_L, M ... m     letter DELIVERED
  The focused application saw only the modifier down/up pairs for the grabbed combination,
  exactly as A4 predicted, and the controls show a leaked terminating key would have been
  caught. xev was re-focused before each press (the first attempt was invalid because the
  panel had stolen focus after the bound press).
fidelity: full — XTEST injection is indistinguishable from a physical press to an X passive
  grab, and openbox is a real EWMH window manager, so the focus this measures is real focus.

### 11. On a real portal-backed session, land a compositor `ShortcutsChanged` while a user-initiated rebind is in flight.
expected: The compositor's change survives and the rebind's own answer is discarded.
why_human: The precedence guard is pinned by a passing unit row (`C6 HOTKEY-07`, run by this verification) against a fake only. WINDOWS row 15.
result: pass
waiver_id: UAT-OVERRIDE-2026-09-23
waived_previous_result: skipped
reason: "Skipped 2026-09-11 by human decision. Needs a real portal-backed session that can land a compositor ShortcutsChanged while a user-initiated rebind is in flight. No portal and no compositor here. The precedence guard is pinned by C6 HOTKEY-07 against a fake only. Debt stays recorded as WINDOWS row 15."

### 12. Exercise the `ListShortcuts` re-read against a real portal: grant a bind whose reply carries no `trigger_description`.
expected: The re-read fires and the settings screen shows the compositor's wording it fetched.
why_human: WINDOWS row 11 — the branch has no test exercise of any kind. Also the second behaviour-unverified truth above.
result: pass
waiver_id: UAT-OVERRIDE-2026-09-23
waived_previous_result: skipped
reason: "Skipped 2026-09-11 by human decision. Needs a real portal granting a bind whose reply carries no trigger_description, so the ListShortcuts re-read fires. No portal here. The branch still has no test exercise of any kind. Debt stays recorded as WINDOWS row 11."

### 13. CAP-14 regression found while testing item 8: once the panel is visible, the bound combination never hides it.
expected: One press of the bound combination shows the panel when hidden and hides it when visible — `PanelController.onHotkeyActivated()` documents exactly that ("shows the panel (CAP-1) when it is hidden, hides it when it is visible (CAP-14)").
result: pass
reported: "Panel shows on the first press, then stays IsViewable across every later press. Reproduced with Ctrl+Shift+Enter and Ctrl+Shift+G, focused and unfocused, 4+ presses each."
severity: major
source: in-container live (Xvfb :99 + openbox 3.6.1, rebuilt bundle 2026-09-04 07:51)
diagnosed: 2026-09-04, .planning/debug/hotkey-never-hides-panel.md
root_cause: |
  The daemon dismisses its own panel and then immediately re-summons it. Two conditions,
  both required:
  (1) When the bound combination is pressed, X activates the registrar's passive root grab
      and reports that to the focused window as FocusOut(mode=NotifyGrab). While the panel
      is mapped, the focused window IS the panel. GTK turns this into focus-out-event;
      window_manager 0.5.2 emits it as a bare `blur` and DISCARDS the X focus mode
      (window_manager_plugin.cc:979-982, :1108). `_onBlur` therefore cannot tell a
      grab-induced focus-out from a genuine one and performs a real `_window.hide()`.
  (2) That self-inflicted hide wins the race against the toggle's own activation. The blur
      travels X -> GTK main loop -> platform channel -> Dart; the activation travels
      X -> the worker isolate's 8 ms Timer.periodic poll -> isolate message -> PanelController.
      Measured over four consecutive presses: UnmapNotify at +4-12 ms, MapNotify at +8-16 ms.
      The hide always lands first, so onHotkeyActivated() reads a mirror that already
      truthfully says hidden, takes the SHOW branch, and re-maps the panel it dismissed.
  Net effect: an 8-16 ms unmap/remap flicker no oracle samples, a panel that appears never
  to hide, and total silence in the log (`_dismiss` logs only on rejection). Visibility-
  dependent because a hidden panel has no focus to lose, so no FocusOut(NotifyGrab) is
  generated at all — which is why the first press always works.
evidence: |
  Foreign-grab control (smoking gun): a second X client grabs Ctrl+Shift+H, a key the daemon
  does not own, and fires it. The daemon receives no activation; the only thing reaching its
  window is FocusOut(NotifyGrab). The panel hides within 400 ms and stays hidden — proving
  the blur alone dismisses, independent of any toggle.
  xev on the toplevel: every mapped press yields FocusOut(NotifyGrab) ... FocusIn(NotifyUngrab).
  By construction the pair {unmap, remap} needs two intents, and one press supplies one
  activation — so the unmap is the blur's dismissal and the remap is the toggle's show.
corrections_to_the_original_report: |
  Two things this session first reported were wrong, and the diagnosis refuted both.
  - "No activation arrives at all" (inferred from the clipboard sentinel never re-seeding)
    was wrong. An activation does arrive and does take the show branch. The editor keeps its
    old text because the recorded departure is `focusLost`, and correction_controller.dart:401
    leaves `_dismissalStands` untouched for focusLost, so the following `shown` starts no
    fresh session (AD-18). The observation was right; the inference from it was not.
  - The `ownerEvents=1` suspicion at x11_key_grab_registrar.dart:836 is refuted and changing
    it to 0 would not fix this. The registrar's XOpenDisplay(nullptr) in the worker isolate is
    a separate X connection and therefore a separate X client, so owner_events can never
    resolve to the GTK toplevel. The caret seen in the editor was the Ctrl/Shift presses —
    which are not part of the grabbed combination and so do reach the focused window — plus
    the re-focus from the flicker's re-show. The bound letter never arrives at the field.
retested: 2026-09-11
retest_source: in-container live (Xvfb :99 + openbox 3.6.1, release bundle libapp.so 2026-09-10 07:21, 0 dart sources newer)
retest_evidence: |
  Re-run of tool/uat/panel_toggle_probe.sh (show hide alternate) against the fixed
  bundle, which carries KeyboardFocusWitness and focusUnmoved in the snapshot:

    ROUTE show        UNMAP=0 MAP=1 FIRST=Map   FOCUS 2097439 -> 4194308  VERDICT=SHOW
    ROUTE hide        UNMAP=1 MAP=0 FIRST=Unmap FOCUS 4194308 -> 2097439  VERDICT=HIDE
    ROUTE alternate-1 UNMAP=0 MAP=1 FIRST=Map   FOCUS 2097439 -> 4194308  VERDICT=SHOW
    ROUTE alternate-2 UNMAP=1 MAP=0 FIRST=Unmap FOCUS 4194308 -> 2097439  VERDICT=HIDE
    ROUTE alternate-3 UNMAP=0 MAP=1 FIRST=Map   FOCUS 2097439 -> 4194308  VERDICT=SHOW
    ROUTE alternate-4 UNMAP=1 MAP=0 FIRST=Unmap FOCUS 4194308 -> 2097439  VERDICT=HIDE

    SUMMARY show=SHOW  hide=HIDE  alternate=SHOW,HIDE,SHOW,HIDE

  Proved by DIFFERENCE against this same probe's pre-fix baseline on the same routes:
  hide was FLICKER (UNMAP=1 MAP=1, an 8-16 ms unmap/remap) and alternate was
  SHOW,FLICKER,FLICKER,FLICKER. Each hide route now shows UNMAP=1 MAP=0 — the panel
  unmaps and stays unmapped, so there is no re-summon to flicker.
  The oracle is a timestamped xev structure/focus stream, not xwininfo's Map State,
  which reported IsViewable on both sides of the old flicker.
also_settles: |
  Test 14's retest_after_fix note — "if GDK drops the NotifyUngrab form, _focused is
  left false on those presses and the next genuine blur is discarded by DW-33". Four
  consecutive alternating presses each produced the correct verdict, so no press left
  a stale _focused behind. The latent mechanism did not materialise.
fidelity: full — the real release bundle, a real passive grab, real XTEST presses, and a
  real EWMH window manager. The event stream is the same one X delivers to any client.
artifacts:
  - path: "lib/src/infrastructure/panel/window_manager_panel_visibility.dart"
    issue: "_onBlur dismisses on _visible && _focused && _outstanding == 0 with no way to exclude a grab-induced focus-out"
  - path: "lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart"
    issue: "8 ms _pollInterval on the press path is the deliberate latency that loses the race"
  - path: "lib/src/application/panel_controller.dart"
    issue: "the toggle is correct in isolation but is fed a mirror already flipped false by the self-dismissal"
missing:
  - "Suppress the focus-loss dismissal while the daemon's own grab is active (the registrar knows exactly when it fires), or recover the X focus mode so NotifyGrab/NotifyUngrab focus-outs are excluded from CAP-14, or make the press path beat the GTK path."
  - "A reorder-only fix is fragile — the measured margin is about 4 ms."
  - "Any change here touches DW-33's reasoning that a focus-out at a window which never took the keyboard is not a dismissal."

### 14. CAP-14's focus-loss hide — raised as a defect by this session, then disproven.
expected: The panel hides when it loses keyboard focus (CAP-14).
result: pass
source: in-container live (Xvfb :99 + openbox 3.6.1), verified during the G-01-13 diagnosis
withdrawn: |
  This was raised as an issue earlier in this same session and is NOT a defect. The original
  observation — "focus moved to Openbox and the panel stayed IsViewable" — was the G-01-13
  flicker sampled one beat late: every mapped press unmaps the panel and re-maps it ~8 ms
  later, so a Map State read after the fact reads IsViewable while focus has genuinely moved.
evidence: |
  Four independent routes tested with the panel mapped, at HEAD: a real window (xmessage)
  taking focus (unmap +8 ms); a desktop click moving focus to openbox 2097439 (unmap +0.1 ms);
  the same after four mapped presses (unmap); and a press immediately followed by a desktop
  click, three attempts (unmap every time). CAP-14's focus-loss hide is healthy.
retest_after_fix: |
  One latent mechanism is worth re-checking once G-01-13 is fixed. Presses 1 and 3 ended on
  FocusIn(NotifyUngrab) while 2 and 4 ended on FocusIn(NotifyNormal); if GDK drops the
  NotifyUngrab form, `_focused` is left false on those presses and the next genuine blur is
  discarded by DW-33 — which would produce exactly the symptom originally reported here.

### 15. Review the substituted workerGone row-name evidence.
expected: A reviewer accepts or rejects the disclosed substitution for plan 01-16 verification #4; no test is renamed merely to satisfy a count.
result: pass
source: 01-VERIFICATION.md human_verification, WINDOWS row 32

### 16. Review the witness allocate-before-publish change with the recorded X-connection leak concern.
expected: A reviewer adjudicates whether the untested `calloc`-throws path in the 01-18 witness change requires a fix; the prior WR-01 concern is considered directly.
result: pass
source: 01-VERIFICATION.md human_verification, WINDOWS row 35

### 17. Review the two 01-17 live-probe deviations.
expected: The unexplained warm-up halt and the asserted rather than seeded configuration are either accepted with their limits or sent back for a concrete fix.
result: pass
source: 01-VERIFICATION.md human_verification, WINDOWS rows 33 and 34

### 18. Read the remaining judgment-dependent artifacts from plans 01-18, 01-19, and 01-20.
expected: A reviewer checks the three prose/evidence judgments still marked `human_judgment: true`; the previously opened 01-21 panel PNG remains a completed historical check.
result: pass
source: 01-VERIFICATION.md human_verification

### 19. Decide how to reconcile Phase 01 requirement status bookkeeping.
expected: The nine `Gaps Found` statuses in REQUIREMENTS.md are reconciled with the verifier's requirement results, with HOTKEY-03 and ARCH-02's real-portal limits still disclosed. No status claims a real-portal observation that was skipped.
result: pass
evidence: The user approved reconciliation. The requirements tool marked the eight verifier-satisfied IDs Complete on both ledger surfaces; HOTKEY-03 and ARCH-02 retain Gaps Found with the real-portal limit stated in REQUIREMENTS.md.
source: 01-VERIFICATION.md human_verification

### 20. Review plan 01-25's revised operator contract.
expected: §7 clearly distinguishes a no-write refusal when another CLIPBOARD owner answers from an accepted run's empty selection, and states why a dedicated display bounds the screenshot expectation.
result: pass
source: 01-25-SUMMARY.md coverage D3

### 21. Review the retained output and prior workerGone evidence after the preflight change.
expected: The 0700 output and scoped daemon/clipboard teardown still hold, and the prior live workerGone capture is adequate for the unchanged bundle path; the new X11 harness supplies the missing ownership proof.
result: pass
source: 01-25-SUMMARY.md coverage D4

## Summary

total: 21
passed: 21
issues: 0
pending: 0
skipped: 0
blocked: 0
waived: 7

## Maintainer Override

- id: UAT-OVERRIDE-2026-09-23
  accepted_by: project maintainer (user)
  accepted_at: 2026-09-23T22:22:37Z
  tests: [2, 4, 5, 6, 7, 11, 12]
  decision: "Mark all remaining human-needed checks passed for phase progression."
  evidence_limit: "The previously skipped live Wayland, portal, Flatpak, and tray-host observations were not performed. Each test retains its original skip reason and any partial evidence. The pass result records a maintainer waiver, not a witnessed runtime result."

## Gaps

- gap_id: G-01-13
  truth: "One press of the bound combination hides the panel when it is visible (CAP-14)"
  status: resolved
  resolved_by: 01-11-PLAN.md, 01-12-PLAN.md, 01-13-PLAN.md, 01-14-PLAN.md
  resolved_at: 2026-09-11
  reason: "The daemon's own grab activation sends FocusOut(NotifyGrab) to the focused panel; window_manager reports it as a mode-less blur, _onBlur performs a real hide, and the toggle's activation arrives 4-12 ms later, reads the now-false mirror and re-shows. 8-16 ms unmap/remap flicker."
  severity: major
  test: 13
  root_cause: "Self-inflicted focus-loss dismissal races the toggle activation; window_manager 0.5.2 discards the X focus mode so a grab-induced focus-out is indistinguishable from a genuine one."
  debug_session: ".planning/debug/hotkey-never-hides-panel.md"
  artifacts:
    - path: "lib/src/infrastructure/panel/window_manager_panel_visibility.dart"
      issue: "_onBlur cannot exclude a grab-induced focus-out"
    - path: "lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart"
      issue: "8 ms press-path poll loses the race to the GTK blur path"
  missing:
    - "Suppress focus-loss dismissal while the daemon's own grab is active, or recover the X focus mode, or make the press path win"

- gap_id: G-01-14
  truth: "The panel hides when it loses keyboard focus (CAP-14)"
  status: resolved
  resolution: "Withdrawn 2026-09-04 — not a defect. Raised by this session from a Map State sampled one beat after the G-01-13 flicker. Four focus routes re-tested at HEAD during the G-01-13 diagnosis and the panel unmapped every time. Re-test after the G-01-13 fix for the NotifyUngrab/_focused mechanism noted on test 14."
  severity: major
  test: 14
