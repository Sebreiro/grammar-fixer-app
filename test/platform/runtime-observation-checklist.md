# Runtime observation checklist — the session claims nothing here can observe

**This is a manual procedure.** Nothing in this file runs unattended, and
nothing in it should be automated.

Be precise about why, because the obvious objection has a measured answer:
`Xvfb` and `xvfb-run` **are** installed in the development container, and so are
`xwininfo`, `xdotool` and `xprop`. A display can be stood up here. What cannot
be stood up is a *session*. `Xvfb` supplies a bare X server and nothing else —
no compositor and no window manager to map, focus, place or dismiss a toplevel;
no `xdg-desktop-portal`; no session bus (`DBUS_SESSION_BUS_ADDRESS` is unset and
`/run/user/` is empty); no login cycle; and no user to watch the screen. Every
claim below is a claim about one of those, which is exactly why three stories
that reached for a headless harness came back with nothing. Running these steps
against a synthetic display would produce results that look like observations
and are not.

The file exists to hold one rule: a claim that is not observed in this container
is stated as unobserved, never quietly reported as met. Six suites do exactly
that — they are
unconditionally skipped rows with a `fail()` body, so they can never report a
claim as met from here — and until this file existed, what was owed lived only
in their skip prose. This is the procedure those rows point at: the list of
things a person standing at a real Linux desktop should do, and what they should
see.

**Ledger entries this procedure settles:** DW-9, DW-25, DW-26, DW-39, DW-44,
DW-50, DW-72. Claims outside that list are named under
[Not covered here](#not-covered-here) rather than quietly folded in.

**The one rule for the reader:** record what you observe, do not decide what
should be. Several steps below sit underneath decisions that are still open — a
panel size, a first-run position, an inset that clears the settings icon. Those
decisions exist to be *informed* by these numbers. Write the number down; leave
the choice to whoever owns it.

**Before you start, read [Cleaning up](#cleaning-up).** Several steps change
things that outlive the run: a desktop-level keyboard shortcut, the app's own
binding, the config file, and the desktop's text scaling factor.

---

## Prerequisites

Work through these before step 1. A run that starts without them produces
observations nobody can trust.

- **A real desktop session** — a compositor or window manager, a session bus, and
  a screen you are looking at. That is the entire point of this file. An `ssh`
  connection with `DISPLAY` forwarded is not one: it changes the grab semantics
  group D depends on and the placement group E measures.
- **An X11 session for the grab steps (8 to 11).** `echo $XDG_SESSION_TYPE`
  answers `x11`. An X passive grab works on an X display and nowhere else, so
  those steps cannot run on Wayland at all — not "runs differently", cannot run.
  Step 12, the latency budget, is *not* one of them: it runs on either session
  type.
- **Optionally a second pass on GNOME or KDE Wayland**, with `xdg-desktop-portal`
  running and a GlobalShortcuts backend behind it. Every step outside group D is
  runnable on either session type. Some of them — 2, 5, 13, 15 and 16 — are
  *written* against X11 enumerators, but the observation each makes is not an X11
  observation, and each names the compositor-side inspector to substitute.
  **The per-step *Applies to:* line is the authority on what you can run; this
  bullet is a summary of it and nothing more.** Where the two disagree, the step
  is right and this bullet is stale. The portal's *own* claims are not part of
  this file (see [Not covered here](#not-covered-here)).
- **On Wayland, expect a portal dialog on every daemon start, and do not expect
  the app to tell you which combination is bound.** The Wayland path binds through
  the portal's `BindShortcuts`, which raises a grant dialog the user has to
  accept; dismissing it logs "the compositor did not grant the global shortcut"
  and leaves the hotkey inactive. The combination is then the **compositor's**
  choice, not the app's — what the app sends is a `preferred_trigger` hint, and
  the effective combination it reads back is always null by measurement, so the
  settings screen cannot display it. Read the actual combination out of the
  desktop's own keyboard-shortcut settings, never out of the app. Any step below
  that says "press the bound combination" means that one. This matters because a
  dismissed dialog, a refused grab and a wrong keypress all look exactly like
  "the panel did not appear".
- **How to find the daemon's process.** Throughout this file:
  `pgrep -a hotkey_grammar_` to look, `pkill hotkey_grammar_` to stop it. Both
  match the *process name*, and both are deliberately truncated. Do not "correct"
  them to the full `hotkey_grammar_corrector`: Linux truncates a process name to
  15 characters, so `pgrep -a hotkey_grammar_corrector` matches nothing at all —
  it prints a warning saying so and exits 1 — which turns every "confirm nothing
  is running" guard into one that always passes and every "finds exactly one
  process" expectation into one that can never be met. Do not reach for `-f`
  either: it matches whole command lines, and this project's own directory is
  named `hotkey_grammar_corrector`, so `pkill -f hotkey_grammar_corrector` kills
  your editor, your test run, and the shell you typed it in.
- **A build.** `flutter build linux --debug`, which leaves the binary at
  `build/linux/x64/debug/bundle/hotkey_grammar_corrector`. Use the debug build,
  not a release one: its log lines on stderr are half the evidence below.
- **A terminal to launch it from**, so stderr is visible. Do not launch it from a
  file manager or an application grid for these steps.
- **`libX11.so.6` is resolvable.** Since phase 1 the grab goes through
  `dart:ffi` to libX11 rather than through keybinder, so `libkeybinder-3.0-0` is
  no longer required at all and checking for it proves nothing. libX11 is an
  unconditional `DT_NEEDED` of `libgdk-3.so.0`, so on any machine where this app
  starts it is already loaded — meaning group D's "library absent" branch is
  structurally unreachable rather than merely handled.
- **A window enumerator.** `xwininfo`, `xdotool` and `xprop` are the ones this
  file uses. Install whichever your distribution provides before step 2 — every
  enumerator step below is written against `xwininfo` and `xdotool`. **`wmctrl` is
  not a substitute for step 2**, whatever it can do elsewhere: it lists
  `_NET_CLIENT_LIST`, which holds managed, mapped windows, and it reports no map
  state at all — so it cannot tell an unmapped toplevel from an absent one, which
  is the entire distinction step 2 turns on. It is a fine substitute for the
  window *lists* in steps 13 and 15.
- **The shipped hotkey must be free before you start.** Check the desktop's own
  keyboard settings for anything already bound to **Ctrl+Shift+G** and write down
  what you find. If the desktop grabs it first, steps 5 and 8 record a failure
  that belongs to your machine's configuration rather than to the app. Step 9
  deliberately creates that conflict later and puts it back, so it matters that
  you know what was there beforehand.
- **The config file** lives at
  `${XDG_CONFIG_HOME:-~/.config}/hotkey-grammar-corrector/config.json`. The
  shipped binding is **Ctrl+Shift+G**. Note whether the file already exists
  before you start, and copy it to `config.json.pre-run` — step 14 deletes it,
  and takes its *own* backup at `config.json.step14`. Keep the two names
  distinct: they hold different bindings, and cleanup restores the pre-run one.
- **A stopwatch method for step 12, with a visible zero.** The interval starts at
  the key press, and a screen capture cannot see a key press — so
  `ffmpeg -f x11grab -framerate 120 …` on its own gives you a stop with no start.
  Either put the press on screen (capture a terminal running `xev` or
  `xinput test-xi2 --root` alongside the panel, and time from the frame its line
  appears) or use a phone camera at 240 fps pointed at the keyboard and the screen
  together. A wall clock cannot resolve 100 ms either way.

---

## A. Startup: the window that is never mapped

Settles the first two of DW-9's three facts. The static half — that the runner
shows no toplevel and nothing under `lib/` calls `windowManager.show()` — is
already pinned by `test/architecture/hidden_window_test.dart`. What is owed is
that the built binary actually behaves that way when it runs.

**1. Launch the daemon, with nothing of ours already running.**

- *Applies to:* X11 and Wayland.
- *Action:* first confirm no instance is up — `pgrep -a hotkey_grammar_` must
  print nothing. If it prints anything, `pkill hotkey_grammar_` and check again;
  an autostart entry from a previous run is the usual culprit.
  Then run `./build/linux/x64/debug/bundle/hotkey_grammar_corrector` from a
  terminal and watch the screen for five seconds without touching anything.
- *Expected:* no window appears anywhere — no toplevel on screen, nothing in the
  task switcher, nothing in the taskbar (`setSkipTaskbar(true)` is set at
  startup). The process stays in the foreground and does not exit.
- *Settles:* DW-9 (AD-8, "the launched daemon maps no window").
- *If it diverges:* write down what appeared, its title, its size, and how long
  after launch it appeared. A window that flashes and vanishes is a divergence
  too — capture it on video if you cannot catch it by eye. **Check the guard
  first:** a panel appearing almost immediately is the signature of a daemon that
  was already running, which makes this a step 4 observation and not a step 1
  one.
- [ ] **Done** — observation written into the results table below.

**2. Enumerate the toplevels.**

- *Applies to:* X11 only. On Wayland there is no equivalent client-side
  enumerator — check the compositor's own window list (GNOME's Looking Glass, or
  `kwin`'s debug console on KDE) and say which you used.
- *Action:* with the daemon still running,
  `xwininfo -root -tree | grep -iE 'hotkey.?grammar.?corrector'`. The pattern
  matches **three** spellings on purpose, because which one is live depends on how
  far startup got and on which branch the runner took. (a)
  `hotkey_grammar_corrector`, from `gtk_window_set_title` on the runner's
  no-header-bar branch. (b) `Hotkey Grammar Corrector`, once Dart's `setTitle`
  runs. (c) `com.divertedriver.HotkeyGrammarCorrector` — on the header-bar branch
  the runner calls `gtk_header_bar_set_title` and never
  `gtk_window_set_title`, so GTK falls back to the application name, which
  `g_set_prgname(APPLICATION_ID)` has set to the app id. The optional separators
  are what make (c) match; a pattern requiring a character between the words
  misses it, and (c) is precisely the case this step is looking for — a startup
  that never reached Dart. If a window id comes back, run `xwininfo -id <id>` on
  it.
- *Expected:* either no match at all, or a match whose `Map State:` reads
  `IsUnMapped`. The embedder realizes the view before Dart runs, so an unmapped
  toplevel existing is expected; a viewable one is not.
- *Settles:* DW-9.
- *If it diverges:* paste the full `xwininfo -id <id>` output, including
  `Map State`, `Override Redirect State`, and the geometry. Note that "no match"
  is only good news once you have confirmed the grep pattern would have matched a
  window that *was* there — summon the panel and re-run the same command; it must
  find it then. **Then dismiss the panel and confirm it is gone before you go
  on.** A panel left up here makes the next two steps unreadable: the second
  launch calls `showPanel()`, which does not toggle, so its only observable is
  satisfied by a panel that was already on screen.
- [ ] **Done** — observation written into the results table below.

**3. Residency.**

- *Applies to:* X11 and Wayland.
- *Action:* note the pid, leave the daemon alone for five minutes, then
  `ps -o pid,etime,rss,stat -p <pid>`.
- *Expected:* the process is still alive, `stat` is a sleeping state, and `etime`
  is the full five minutes. Write the `rss` number down whatever it is.
- *Settles:* DW-9 ("the process stays resident").
- *If it diverges:* record the exit status (`echo $?` in the launching terminal)
  and the last twenty lines of stderr. Note that the `rss` figure is recorded,
  never judged here:
  `_bmad-output/specs/spec-hotkey-grammar-corrector/risks.md` carries a ~96 MB
  baseline, and this step exists to replace that estimate with a measurement, not
  to pass or fail against it.
- [ ] **Done** — observation written into the results table below.

---

## B. The second launch

Settles DW-9's third fact, and the mechanism behind it.

**4. Launch a second copy while the first is running.**

- *Applies to:* X11 and Wayland.
- *Action:* **confirm the panel is hidden first** — this step's only observable
  is a panel *appearing*, and the second launch routes to `showPanel()`, which
  shows without toggling, so a panel that was already up proves nothing and no
  transition is witnessed. Then, from a second terminal, run the same binary
  again. Immediately after it returns, `echo $?`.
- *Expected:* the second process exits **0** without staying resident, and the
  **first** instance's panel appears on screen. That is AD-14's lock resolving a
  double launch to one instance: the second process reaches the address the
  first holds, writes one `show-panel` line, and leaves.
- *Settles:* DW-9 ("a second launch exits 0").
- *If it diverges:* record the exit code, whether a second process stayed alive
  (`pgrep -a hotkey_grammar_`), whether any panel appeared, and any
  warning line about the single-instance socket. Two live processes and two
  hotkey binds is the failure this step exists to catch.
- *Worth knowing while you read the result:* the lock's address is derived from
  `$XDG_RUNTIME_DIR` and never from the `Exec` line of any desktop entry
  (`lib/src/infrastructure/system/single_instance_lock.dart`). Two *different*
  commands under the same runtime directory would meet the same lock, so this
  step says nothing about `Exec` — that is the desktop procedure's business
  (`test/platform/desktop-session-checklist.md`, step 5).
- *Before you record a divergence:* run `echo $XDG_RUNTIME_DIR` in **both** the
  terminal that started the first instance and the second terminal, and record
  both. If they differ, or either is empty, the two processes computed different
  lock addresses and both were entitled to bind — that is not an AD-14 failure,
  it is a mis-scoped terminal, and the step has to be redone from a terminal
  belonging to the graphical session. An `ssh` or detached `tmux` terminal is the
  usual way to get this wrong.
- [ ] **Done** — observation written into the results table below.

---

## C. The summon, the dismissal, and the echo

Settles DW-26 and DW-25. Worth running on both session types.

**5. The panel is visible *and* focused.**

- *Applies to:* X11 for the divergence instruction below, which needs
  `xdotool getactivewindow`. The observation itself applies to both — on Wayland,
  substitute the compositor's own "which window has focus" view (GNOME's Looking
  Glass, KDE's `kwin` debug console) and say which you used.
- *Action:* **confirm the panel is hidden first** — step 4 leaves the first
  instance's panel on screen, and the hotkey is a toggle, so pressing it against
  a visible panel *hides* it. Dismiss it and check the screen. Then, with the
  daemon running and the keyboard focus in some other application, press
  **Ctrl+Shift+G**. Without clicking anything, immediately type `HELLO`.
- *Expected:* the panel appears, and all five characters land in its editor. The
  caret is already in the editor when the panel arrives — no click is needed to
  put it there.
- *Settles:* DW-26 (CAP-1, "visible and focused").
- *If it diverges:* the interesting divergence is a panel that is *on screen but
  does not hold the keyboard* — the characters go to the application underneath.
  Write down which window `xdotool getactivewindow` reports while the panel is up
  (X11), or the compositor's own answer to the same question (Wayland), and
  whether clicking the panel then makes typing work. **First rule out the
  toggle**: if the panel was visible when you pressed, the press dismissed it and
  `HELLO` went to whatever was underneath — which produces exactly this
  signature. Redo the step from a hidden panel before recording anything.
- [ ] **Done** — observation written into the results table below.

**6. The focus-loss hide.**

- *Applies to:* X11 and Wayland.
- *Action:* with the panel up, click on a different application's window.
- *Expected:* the panel disappears once, immediately, and stays gone. No flicker,
  no reappearance, no second dismissal animation.
- *Settles:* DW-26 (CAP-14).
- *If it diverges:* record whether the panel reappeared, whether it flickered
  before settling, and any stderr line naming a rejected hide. A panel that
  hides and comes back is a different defect from one that never hides — say
  which you saw.
- [ ] **Done** — observation written into the results table below.

**7. Window-event echo ordering, end to end into Dart.**

- *Applies to:* X11 and Wayland. This is an engine-level ordering question, not a
  display-server one, so a divergence on one and not the other is itself a
  finding.
- *Action:* start with the panel **hidden**, and confirm it is — if a previous
  step left it up, dismiss it first and check the screen. Then press the hotkey
  **twice in rapid succession** — under roughly 100 ms apart. On X11,
  `xdotool key --clearmodifiers ctrl+shift+g ctrl+shift+g` is the reliable way to
  get the interval. **Repeat the whole thing ten times either way** — by hand if
  you have no `xdotool`, and ten times *with* it too. This is a race, and one
  clean pass is not a result.
- *Expected:* the panel ends **hidden** and stays hidden, on all ten. Press 1
  shows it and press 2 hides it again, so a healthy run may flicker and settles
  hidden. It must not reappear without a further press, and no stderr line about a
  fresh session or a clipboard read appears *after* the panel is down.
- *Why the panel must start hidden:* the hotkey is a strict toggle, and the
  visibility mirror is updated **synchronously** before each request is enqueued
  (`window_manager_panel_visibility.dart`, `show`/`hide`), so two presses always
  alternate — there is no state in which a pair of presses is a no-op. From a
  hidden start the pair is show-then-hide, which leaves the **show** superseded,
  and a superseded show is what DW-25 is about: `focus()` maps a hidden toplevel,
  so even the trailing half of a show is enough to put the window back. Starting
  from a *visible* panel runs the pair as hide-then-show, leaves the hide
  superseded, and ends **visible** — a different question, and not this one. Get
  the starting state wrong and every one of the ten attempts reads as a
  divergence on a machine with nothing wrong with it.
- *Settles:* DW-25.
- *What a clean run does and does not mean:* this step can **falsify** the
  ordering and cannot confirm it. A panel that stays hidden is equally what you
  see when the race simply did not occur on those ten attempts — and the plugin
  source suggests it usually will not. So record a clean run as
  **"not reproduced in N attempts"**, with N, and never as "ordering confirmed".
  A single divergence is decisive; ten clean passes are evidence and not proof.
  Whoever closes DW-25 needs the number, not a tick.
- *Why this is the observable:* the visibility adapter ignores a window event
  while a request of its own is outstanding, because such an event is its own
  echo (`window_manager_panel_visibility.dart`, `_reconcile`). The plugin source
  says the echo is emitted synchronously from inside the `gtk_widget_show` the
  method handler itself calls, so it goes out before that handler replies. What
  no test in this repository can check is the last link — that the Flutter engine
  preserves that ordering into Dart. If it does not, a superseded `show` echo
  lands with nothing outstanding, is believed, and `changes` emits a spurious
  `true`; under AD-18 that is a cleared editor and a fresh clipboard read against
  a panel on its way out.
- *If it diverges:* record the full terminal output from the moment of the double
  press onward, with timestamps if you can get them, and whether the panel came
  back on screen without a further press. **The tell that matters is a
  fresh-session or clipboard-read line logged after the panel went down** — that
  is a `changes` emission nobody asked for. Note that the editor's contents
  cannot serve as the tell here: under AD-18 every legitimate `show()` of a
  hidden window begins a fresh session, so press 1 clears the editor whether or
  not the race occurred. Anything you type beforehand marks the session boundary,
  not the defect.
- [ ] **Done** — observation written into the results table below.

---

## D. The real grab

Settles DW-44 and DW-39. **Steps 8 to 11 are X11 only** — an X passive grab takes
on an X display, and the Wayland path is the portal, whose own claims this file
does not carry. **Step 12 is the exception**: its claim is CAP-1's latency
budget, which is owed on either session type, so it runs on Wayland too against
whatever combination the compositor bound (see the portal bullet in
[Prerequisites](#prerequisites)). Run the steps in order: 9 changes a
desktop-level shortcut that 10 needs released again, and 12 needs a daemon that
has been left alone.

**8. The grab is genuinely global.**

- *Applies to:* X11 only.
- *Action:* with the daemon running, focus a terminal, then a browser, then a
  text editor, and press Ctrl+Shift+G in each.
- *Expected:* the panel appears every time, from every application, and the
  focused application never sees the key itself (a browser does not open its own
  Ctrl+Shift+G action).
- *Settles:* DW-44 ("that the X server actually grants the grab").
- *If it diverges:* record which applications the press reached the panel from
  and which it did not, and whether the focused application acted on the key
  instead.
- [ ] **Done** — observation written into the results table below.

**9. A refused grab.**

- *Applies to:* X11 only.
- *Action:* stop the daemon. Bind Ctrl+Shift+G to something else at the desktop
  level — the desktop's own keyboard-shortcut settings are the easiest way — then
  start the daemon again. **Write down the registrar the build carries before you
  read the result**: `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart`
  (the shipped one since phase 1) — or, on a build from before that,
  the removed `hotkey_manager` seam.
- *Expected:* record two things separately. (a) Whether pressing the combination
  reaches the panel at all. (b) Whether the application nonetheless reports the
  hotkey as available — the tray state and the settings screen both claim it.
- *Settles:* DW-39, DW-44.
- *Why both halves:* `hotkey_manager_linux`'s `hkm_register` discarded
  `keybinder_bind`'s `gboolean` and answered success unconditionally, so on the
  old build the expected result was the uncomfortable one — a shortcut that does
  nothing, reported as bound. **That inverted in phase 1.** On the shipped
  `X11KeyGrabRegistrar` the expected result is now (a) the combination does not
  reach the panel *and* (b) the application says so: `bind()` reports it
  unavailable and the settings screen names the tray as the way in that still
  works. `XSetErrorHandler` plus `XSync` makes the server's `BadAccess` answer
  synchronous, so the refusal is readable rather than guessed. If you observe
  the old behaviour — a shortcut reported as bound that does nothing — that is a
  regression on HOTKEY-01, not the documented state.
- *If it diverges:* record the stderr output at bind time and the exact wording
  the settings screen shows for the combination.
- *Before moving on:* **remove the desktop-level binding you just added and
  restart the daemon.** Leaving it in place makes step 10's "the old combination
  no longer works" true for the wrong reason — the desktop would still be holding
  it — and the step would record a pass that proves nothing.
- [ ] **Done** — observation written into the results table below.

**10. CAP-12: a rebind takes effect without a restart.**

- *Applies to:* X11 only.
- *Action:* start from a clean state — no desktop-level binding on Ctrl+Shift+G
  (step 9's teardown), and a daemon that has been running untouched since it was
  last started. Confirm Ctrl+Shift+G summons the panel. Then, with the panel up,
  open the settings screen through the corner affordance, change the combination
  to something free (Ctrl+Alt+Y is usually clear), apply, and dismiss the panel.
  Now press the **new** combination, then the **old** one.
- *Expected:* the new combination summons the panel. The old one does nothing.
  The daemon was never restarted between the rebind and the presses.
- *Settles:* DW-44 (CAP-12).
- *If it diverges:* record whether the old combination still works (the release
  half failed), whether the new one works only after a restart (the grab half
  failed), or whether both work (neither half happened).
- [ ] **Done** — observation written into the results table below.

**11. GTK main-thread marshalling.**

- *Applies to:* nothing on the shipped route — **retired in phase 1**, see below. Formerly X11 only, and only to a build carrying the `dart:ffi` keybinder
  registrar.**
- *Action:* rebind ten times in a row, pressing the current combination between
  each to confirm the bind took. **Alternate between two free combinations** —
  Ctrl+Alt+Y and Ctrl+Alt+U, say — rather than "repeating step 10", which after
  its first iteration would rebind Ctrl+Alt+Y to itself and prove nothing. Then
  leave the daemon running for a minute.
- *Note the combination you finish on.* Steps 12 and 13 summon the panel, and
  after this step the shipped Ctrl+Shift+G is **not** what does it. Nothing
  restores it until step 14.
- *Expected:* every bind takes effect, no press is dropped, and stderr carries no
  `Gdk-WARNING`, `Gtk-CRITICAL`, `GLib-CRITICAL` or `X Error` line, and no hang.
- *Settles:* DW-39.
- *If it diverges:* record the full stderr and which rebind iteration it appeared
  on. A warning that appears on the first iteration and one that appears on the
  ninth are different bugs.
- *If not applicable:* write "not applicable — no GTK marshalling on this route" and move
  on. The marshalling surface does not exist until the FFI registrar lands, and
  recording a pass for it would be a claim about code that is not there.
- [ ] **Done** — observation written into the results table below.

**12. CAP-1: the 100 ms budget.**

- *Applies to:* X11 for the measurement as written. The claim is owed on Wayland
  too, but the summon there goes through the portal rather than an X grab,
  so record the session type beside every number.
- *Action:* **run this last in group D**, because steps 9, 10 and 11 all restart
  or rebind the daemon and would spoil the resident samples. **Press whichever
  combination is currently bound** — if you did steps 10 and 11, that is the one
  you finished 11 on, not Ctrl+Shift+G. Confirm it before you measure, because
  fumbling for a dead combination is measured as latency and this is the one step
  where that matters. On X11 the settings screen shows it. **On Wayland it does
  not** — the effective combination reads back as null there, so take it from the
  desktop's own keyboard-shortcut settings instead. Restart the daemon
  once, take the **cold** sample on its first summon, then leave it alone —
  untouched, no rebinds, no restarts — for at least an hour, and take four more
  samples. Measure the interval between the key press and the panel being on
  screen using the capture method from the prerequisites.
- *Expected:* under 100 ms, every time. Record all five numbers, which one is the
  cold sample, and the method used to get them — a single number with no method
  behind it is not evidence.
- *Settles:* DW-44 (CAP-1).
- *If it diverges:* record whether the slow summons are the cold one or the warm
  ones, and whether the delay is before the window appears or between the window
  appearing and it being drawn.
- [ ] **Done** — observation written into the results table below.

---

## E. Geometry and the settings affordance

Settles DW-50 and DW-72. **Every step in this group is a measurement.** Nothing
here chooses a size, a position, or a remedy for the affordance — those
decisions are already scoped in the ledger and are waiting on exactly these
numbers. Record; do not pick.

**13. The size the panel actually gets, and the settings screen inside it.**

- *Applies to:* X11 only as written — it reads geometry through `xwininfo` and
  `xdotool`. On Wayland, take the numbers from the compositor's own window
  inspector instead and say which you used.
- *Action:* summon the panel — with whichever combination is currently bound;
  after steps 10 and 11 that is not Ctrl+Shift+G — and run
  `xwininfo -id $(xdotool getactivewindow)`,
  or plain `xwininfo` and click on the panel. Record the screen resolution and
  the desktop's scale factor. **Then, without resizing or moving the window, open
  the settings screen through the corner affordance and look at it at that same
  geometry** — both the hotkey view and the provider/preset view.
- *Expected:* **roughly 1280x720, minus decorations.** There *is* a prediction
  here, and it is not "nothing": `linux/runner/my_application.cc` calls
  `gtk_window_set_default_size(window, 1280, 720)` on the startup path, and
  nothing on the Dart side overrides it — the hidden-window setup sets only the
  title and the taskbar hint, never a size, a minimum size or a position. So the
  number to expect is the Flutter template's default, surviving into a tray
  daemon's panel. **If you measure 1280x720, flag it explicitly** rather than
  recording it as unremarkable: it means the panel has the template's geometry
  rather than one chosen for it, which is a different finding from "the panel has
  no geometry" and is the one that explains why the layout tests only ever
  checked 480x360. Position is genuinely unpredicted — nothing sets one.
  Write down `Width`, `Height`, `Absolute upper-left X`,
  `Absolute upper-left Y`, the screen resolution, and the scale factor. Then
  answer two questions. (a) Are the original text and at least one variant both
  readable at that size without scrolling? (b) Is the settings screen legible at
  that same size — are its labels, its hotkey field and its Apply control all
  reachable without the view clipping or scrolling awkwardly?
- *Settles:* DW-50.
- *If it diverges:* record the measured size against the predicted 1280x720 and
  say which it is — the template default, or something else, in which case name
  what you think supplied it. Flag it loudly if the window arrives clipped, at a
  size where the first variant is cut off, or full-screen, and flag it separately
  if the panel is usable at that size while the settings screen is not. Those are
  two different findings and only one of them is about the panel. Do **not**
  choose a size, a minimum size or a position to fix any of this: recording what
  the panel gets is the whole job here, and picking the remedy is the decision
  this observation exists to inform.
- [ ] **Done** — observation written into the results table below.

**14. Where it appears, and whether it stays there.**

- *Applies to:* X11 and Wayland — but Wayland compositors do not generally let a
  client read or set its own position, so record what the compositor does rather
  than expecting the same answer as X11.
- *Action:* **stop the daemon first** — `pkill hotkey_grammar_`, then
  `pgrep -a hotkey_grammar_` to confirm nothing is left. This is not optional
  bookkeeping: AD-14's lock means "starting" the daemon while one is already
  running does not start anything. The launch signals the process that is
  already up and exits 0, and that process still holds the rebind from steps 10
  and 11 in memory, because nothing watches the config file (AD-13). You would
  then press Ctrl+Shift+G, see nothing happen, and record a placement failure
  that is really a stale daemon. Step 12 leaves one resident for an hour, so
  this is the likely state when you arrive here. With it stopped: copy the config
  file to `config.json.step14` — **not** over `config.json.pre-run`, which holds
  the binding that was on this machine before the run and is the one cleanup
  restores — then delete it. Now start the daemon and summon
  the panel with **Ctrl+Shift+G** — the deletion reseeds the shipped binding, so
  any rebind from steps 10 and 11 is gone and the shipped combination is live
  again. Record
  where the compositor put the panel. Drag it somewhere distinctive, dismiss it,
  summon it again. Then stop the daemon, start it again, and summon once more.
- *Expected:* record the position on first summon, after the move, and after the
  restart. Today nothing persists a position, so whatever happens is the
  observation.
- *Settles:* DW-50.
- *If it diverges:* record whether the compositor centres it, corners it, or
  places it under the pointer — placement policy differs between GNOME, KDE and
  wlroots, so name the compositor and its version alongside the result.
- [ ] **Done** — observation written into the results table below.

**15. The region the settings affordance takes from the editor.**

- *Applies to:* X11 only as written — the measurement is against the geometry
  from step 13. On Wayland, use the compositor's inspector for the window
  rectangle and measure the region relative to it.
- *Action:* with the panel up, click at the very top-right corner of the editor —
  right on the gear icon — then a few pixels left of it, and a few pixels below
  it, until you find the boundary where a click starts focusing the editor
  instead of opening settings. Measure that region in pixels.
- *Expected:* record the region's width and height, and its size relative to the
  window measured in step 13. Then answer one practical question: when a line of
  text in the editor reaches the right-hand edge, does a click at the end of that
  line land on the affordance?
- *Settles:* DW-72.
- *If it diverges:* nothing to diverge from. Do not adjust an inset, a padding
  value, or the affordance's position while you are here — the measurement is
  what the fix needs, and a fix made blind is what put this on the list.
- [ ] **Done** — observation written into the results table below.

**16. Repeat at a larger text size.**

- *Applies to:* X11 and Wayland, with the same enumerator caveat as steps 13
  and 15.
- *Action:* raise the desktop's text scaling factor to 1.5 — note its previous
  value first, you are putting it back in [Cleaning up](#cleaning-up) — and
  repeat steps 13 and 15.
- *Expected:* both sets of numbers again. The panel's height floor follows the
  reader's text size, so the two measurements are not the same measurement twice.
- *Settles:* DW-50, DW-72.
- *If it diverges:* record whether the original text stops being readable, and at
  what scale factor that starts.
- [ ] **Done** — observation written into the results table below.

---

## Cleaning up

This procedure changes three things that outlive it. Put them all back, and do it
even if you abandoned the run part-way — a half-finished run leaves the same
mess as a finished one.

1. **The desktop-level keyboard shortcut from step 9.** Remove the binding you
   added on Ctrl+Shift+G in the desktop's own keyboard settings, and **put back
   whatever the prerequisites had you write down as already bound there** — if
   something was, deleting "the binding you added" leaves the machine short of a
   shortcut its owner had. Step 9's own teardown says to do this before step 10;
   check it again here, because a leftover desktop-level grab on Ctrl+Shift+G
   silently breaks the app for whoever uses this machine next.
2. **The config file, and with it the app's own binding from steps 10 and 11.**
   Do this as one action, in this order, or you will undo your own work:
   - If you backed up a config file before the run, **restore
     `config.json.pre-run`** over whatever step 14 left behind — that one, not
     `config.json.step14`, which holds steps 10 and 11's rebind and would put the
     machine back on Ctrl+Alt+Y. Restoring it restores the binding it carried too,
     so there is nothing further to do — do *not* also rebind through the settings
     screen first; the restore would overwrite it. Delete both backup copies once
     the restore is confirmed.
   - If you had no config file before the run, delete the one the run created —
     `rm -f ${XDG_CONFIG_HOME:-~/.config}/hotkey-grammar-corrector/config.json` —
     rather than leaving a config nobody chose. The next start reseeds
     Ctrl+Shift+G.
   - Only if you want to keep the run's config for some reason: rebind to
     Ctrl+Shift+G through the settings screen instead of either of the above.
3. **The text scaling factor from step 16.** Put it back to the value you noted.

Then stop the daemon: `pkill hotkey_grammar_`, and confirm with
`pgrep -a hotkey_grammar_` that nothing is left. If you also worked
through `test/platform/desktop-session-checklist.md`, that file has its own
cleanup for the entries it installs — this one does not cover them.

---

## Not covered here

These claims are real and owed, and they are **not** part of this procedure.
They are listed so nobody assumes a completed run of this file settles them.

- **The tray indicator (AD-12, DW-114).** That the icon is drawn from the bundled
  asset path, that its open-panel entry raises the panel end to end, that the
  degraded icon plus the disabled statement line are legible on a wlroots
  compositor, and — since the menu gained a **Quit** entry — that picking Quit
  actually stops the daemon and clears the indicator from the tray, rather than
  leaving a dead item the host keeps drawing. Those claims live in
  **`test/platform/tray_live_test.dart`** and belong to a ledger entry outside
  this one. Do not fold them in here.
- **A window close as a dismissal (DW-12).** That activating a real window
  manager's close control, with the daemon's startup `setPreventClose(true)` in
  effect, delivers the close event with the toplevel **still mapped**; that the
  panel adapter's own `hide` is therefore what puts the window away; that the
  daemon is still resident afterwards; and that the next summon brings the same
  warm window back rather than building a new one. Group C above is titled *The
  summon, the dismissal, and the echo*, and the dismissal it covers is the
  **focus-loss** one (CAP-14) — a completed run of group C settles nothing about
  the close control, so do not read it as covering that. The claim lives in
  **`test/platform/panel_visibility_live_test.dart`**; do not add a step for it
  here.
- **A summon that never gets the keyboard, and a click-away during a second
  summon (DW-32, DW-33).** That a window manager with focus-stealing
  prevention maps the panel *without* handing it the keyboard and the panel
  nonetheless stays up — the adapter answers a focus-out only when a focus-in
  first said the window ever held the keyboard — and that clicking away during a
  second summon of an already-visible panel dismisses it once that round trip
  ends, rather than the blur being swallowed by the request in flight. Group C
  above observes the focus-loss dismissal from a panel that is already settled
  and already focused, which is neither of those situations, so a completed run
  of it settles neither claim. A third claim of the same kind rides with them:
  that a panel the window manager brings back on its own — deiconified after a
  minimize, or mapped by a `show` nobody here asked for — is handed the keyboard
  again before any focus-out reaches it. The adapter forgets the keyboard
  whenever the mirror goes to false, a minimize included, and neither of those
  arms restores it when the panel comes back — only a real focus-in does. Where
  the window manager brings the panel back without focusing it, that panel
  cannot answer a click-away until the user first clicks into it. **Observing a
  focus-in is not enough to settle this claim, and an earlier wording here read
  as though it were:** the adapter records one only while its mirror already
  reads true, so a focus-in delivered *before* the `window-state-event` carrying
  `restore` is discarded and leaves the panel in exactly the state a missing
  focus-in would. GTK raises `focus-in-event` and `window-state-event` from
  independent compositor events with no ordering guarantee between them, so what
  a session has to record is the **order** of the two, not merely that both
  occurred — and then whether a click-away is answered afterwards. All three
  live in
  **`test/platform/panel_visibility_live_test.dart`**; do not add an entry for
  them here.
- **The desktop entries (DW-87).** Installing the entries, the compositor
  associating the registered app id with the installed file, the bind surviving
  *because of* that association, autostart at login, and a manual launch beside
  an autostarted daemon. Those need a login cycle and a second physical launch,
  which is a different session shape from everything above — they have their own
  procedure at **`test/platform/desktop-session-checklist.md`**.
- **The Wayland portal's own behaviour.** That a real portal shows its own dialog
  on Apply, that its answer comes back with `effective: null`, that a rebind made
  in the compositor's settings produces a real `ShortcutsChanged` — named in
  `test/platform/settings_screen_live_test.dart` and
  `test/platform/wayland_hotkey_live_test.dart`. Group D above is the X11 grab
  and nothing else.
- **The real system clipboard (CAP-11)** and the input-method/keyboard-layout
  claims named in `test/platform/correction_panel_live_test.dart` — including
  Ctrl+Enter and the 1/2/3 keys through a real input method, and a keypad with
  Num Lock off. That suite points here for its geometry claim (step 13), its
  focus claims (steps 5 and 6) and its latency claim (step 12); its clipboard and
  keyboard-layout claims are its own.
- **Accessibility.** That the panel, the settings affordance and the two settings
  views are usable with a real keyboard and a real screen reader — claim (6) of
  `test/platform/settings_screen_live_test.dart`. The semantics assertions in
  that story read a semantics tree, not an assistive technology, and nothing in
  this procedure exercises one either. Step 13 asks only whether the settings
  screen is *legible* at the observed geometry, which is a different question.
- **DW-53 — the panel's minimum-height floor is a widget-side fallback, not a
  window constraint.** Steps 13 and 16 measure the height the window is actually
  given, which is an input to that entry, but the entry itself is about where the
  floor is enforced. It is already **closed** — decided along with DW-50, which
  makes the floor a real toplevel minimum size — so it is not owed by anyone and
  a run of this file neither settles nor reopens it. Record the heights; do not
  file them against DW-53.
- **The `meta` modifier.** Which X11 mask a Super-based binding actually takes —
  `GDK_META_MASK` against Mod4 — is parked inside DW-44's own entry and is not a
  step here. It is deliberately absent rather than overlooked: closing it means
  choosing between refusing `meta` and translating it to `super`, and this
  procedure records observations rather than picking remedies. If you find
  yourself wanting to test a Super binding, that is the entry to reopen, not a
  step to add.
- **Config-file watching (AD-13)** — nothing watches the file, so the file half of
  CAP-8 takes effect on the next restart. That is a known open item, not
  something a session observation would change.

---

## Recording the results

Fill this in as you go and keep it with the run. **This file is not the record**
— do not edit it to hold results, and do not edit the deferred-work ledger
either; hand the completed table to whoever is closing the entries, and let the
ledger be updated there.

```
Date            :
Operator        :
Machine         : (CPU, RAM, GPU driver)
Session type    : x11 | wayland
Compositor      : (name and version)
Screen          : (resolution, refresh rate, scale factor)
Distribution    :
libX11          : (ldd on the built binary | grep libX11)
Enumerators     : (xwininfo / xdotool / xprop / wmctrl — which were available)
Flutter version :
Repo commit     :
Binary path     :
Config file     : present before the run? yes | no
  pre-run backup  : ______  (restored by cleanup)
  step 14 backup  : ______  (holds the rebind; deleted, not restored)
Text scale before the run :
```

| Step | Settles | Observed | As expected? | Notes |
|------|---------|----------|--------------|-------|
| 1  | DW-9  |  | yes / no / n/a |  |
| 2  | DW-9  |  | yes / no / n/a |  |
| 3  | DW-9  |  | yes / no / n/a |  |
| 4  | DW-9  |  | yes / no / n/a |  |
| 5  | DW-26 |  | yes / no / n/a |  |
| 6  | DW-26 |  | yes / no / n/a |  |
| 7  | DW-25 |  | diverged / not reproduced in ___ attempts |  |
| 8  | DW-44 |  | yes / no / n/a |  |
| 9  | DW-39, DW-44 |  | see the block below |  |
| 10 | DW-44 |  | yes / no / n/a |  |
| 11 | DW-39 |  | yes / no / n/a |  |
| 12 | DW-44 |  | yes / no / n/a |  |
| 13 | DW-50 |  | measurement |  |
| 14 | DW-50 |  | measurement |  |
| 15 | DW-72 |  | measurement |  |
| 16 | DW-50, DW-72 |  | measurement |  |

Step 9 asks for two answers and the registrar that makes them readable, so it
gets its own block rather than one cell:

```
Registrar in the build          : X11KeyGrabRegistrar (dart:ffi to libX11)
(a) Press reached the panel     : yes | no
(b) App reported it as available: yes | no
    tray state shown            :
    settings screen wording     :
stderr at bind time             :
Desktop-level binding removed and daemon restarted before step 10? yes | no
```

Measurements recorded rather than judged (steps 12 to 16), and the numbers wanted
from them:

```
Panel size on first summon      : ____ x ____ px   at scale ____
Settings screen legible there?  : yes | no    what clipped, if anything: ______
Panel position on first summon  : x ____  y ____
Position after a move + resummon : x ____  y ____
Position after a daemon restart : x ____  y ____
Affordance region               : ____ x ____ px
Does a click at the end of a full-width line hit it?  yes | no
Panel size at 1.5x text scale   : ____ x ____ px
Affordance region at 1.5x       : ____ x ____ px
Summon latency, cold sample (ms): ____
Summon latency, 4 warm samples  : ____ ____ ____ ____   after ____ resident
                                  method: ______
Resident RSS after 5 minutes    : ____ MB
```

Confirm before you file the results:

```
Cleaning up completed (all three items)?  yes | no
```


## Taskbar and native Close preference (quick task 261002-3x4)

Repeat on a real X11 desktop and a real Wayland desktop with a taskbar/dock:

1. Start the packaged daemon with desktop entries installed. Its hidden window must not appear in the running-window list. Summon the panel; the app should appear with its installed icon. Open Settings; the same taskbar entry stays available.
2. Leave **When closing the window** at **Close to tray**. Close from Settings, then reopen from the tray. Close from the panel; the window and its running taskbar entry disappear while the tray daemon stays available. Reopen with the hotkey or tray; the warm window returns.
3. Minimize the panel, then restore from its taskbar entry; the panel and its current session return.
4. Select **Quit app**. Verify `closeBehavior` in config.json becomes `quit`. Dismiss by hotkey and by clicking away; both still hide and the daemon stays resident. Reopen and press native Close; the process exits and the tray disappears. Repeat native Close from Settings. Restart; the setting remains **Quit app**.
5. Change `closeBehavior` in the config file between `closeToTray` and `quit` with Settings open; the field updates. Re-select **Close to tray** and verify config.json is updated. Remove the key and restart; the tray default returns.

These are compositor observations; source/property tests alone do not verify the desktop's actual taskbar presentation.


## KDE Wayland raising (quick task 261002-4z2)

Record Plasma/KWin versions, session type, GTK backend, app build commit, and whether the GlobalShortcuts portal supplied activation tokens. These checks require a real KDE desktop; the private-bus tests prove delivery/order, not compositor foreground focus.

1. Launch the new build once and verify it starts hidden. Open the panel from the tray, then work in another application. Choose **Open the panel** again: the same panel must reach the foreground and accept typing. Repeat with Settings showing and after tray menu replacement caused by a hotkey status update.
2. Repeat from another focused application with the registered portal hotkey. A hidden panel must show and accept typing; a second press while the panel is visible must hide it. Clicking away must still hide it. Returning after focus loss must preserve the editor and suggestions.
3. Minimize the panel to the taskbar and repeat both entry routes. Restoring must preserve the session. Opening from the taskbar must continue to work.
4. Keep the daemon resident for at least ten minutes, interacting with other applications throughout, and repeat tray and hotkey summons. Record foreground focus, rather than only mapping or a successful method reply.
5. Measure hotkey-to-visible-and-focused latency against CAP-1's 100 ms budget. Record the measuring method and distribution. The automated tests provide no latency verdict.
6. If a summon fails, reproduce from a terminal with `WAYLAND_DEBUG=client` and inspect the activation request and actual keyboard focus. Keep token values and unrelated application text out of shared evidence. A backend that supplies no fresh token remains subject to compositor activation policy; record that absence rather than claiming a foreground pass.
