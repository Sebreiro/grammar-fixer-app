# Desktop-session checklist — the four facts about the installed entries

**This is a manual procedure**, and unlike most "we could not test this here"
notes, that is a measured claim rather than an assumption. `Xvfb` and `xvfb-run`
are installed in the development container, and so are `xwininfo`, `xdotool` and
`xprop` — a display can be stood up here. What `Xvfb` supplies is a bare X
server, and none of the four facts below is about a display. They are about a
compositor, an `xdg-desktop-portal` with a GlobalShortcuts backend, a session bus
(`DBUS_SESSION_BUS_ADDRESS` is unset here and `/run/user/` is empty), and a real
login cycle. A synthetic X server provides none of those, so automating these
steps against one would produce results that look like observations and are not.
(`desktop-file-validate` is genuinely absent here too, which is why the
prerequisites below treat it as something the target machine may or may not
have.)

The file exists to hold one rule: a claim that is not observed in this container
is stated as unobserved, never quietly reported as met.
`test/architecture/desktop_entries_test.dart`
is green from top to bottom, and every row in it reads bytes or runs the
installer into a temporary XDG tree — a check of paths and file contents, and no
evidence at all about a desktop. `test/platform/desktop_entries_live_test.dart`
is the unconditionally skipped row that says so. This is the procedure that row
points at.

**Ledger entry this procedure settles:** DW-87. Claims outside it are named under
[Not covered here](#not-covered-here).

This is a **separate** procedure from
`test/platform/runtime-observation-checklist.md` on purpose. Everything here
needs a login cycle and a second physical launch — a different session shape from
the display-and-grab observations, which all run inside one login. Splitting them
keeps each one runnable start to finish.

---

## Prerequisites

- **A GNOME **Wayland** session, and ideally a KDE Wayland one too.** Steps 2 and
  3 are portal claims and are meaningless on X11 — each says so at the top. AD-11's
  association rule is GNOME's; running the same steps on KDE is what tells us
  whether the rule generalises. Record which you used, and the session type.
- **`xdg-desktop-portal` running with a GlobalShortcuts backend**, and a session
  bus (`echo $DBUS_SESSION_BUS_ADDRESS` is non-empty).
- **Every daemon start on Wayland raises a portal grant dialog. Accept it.**
  The bind goes through `BindShortcuts`, and a dismissed or refused dialog logs
  "the compositor did not grant the global shortcut" and leaves the hotkey
  inactive. Steps 2, 3 and 4 all start the daemon — step 3 three times — so
  expect the dialog each time, and treat a dismissed one as a void attempt rather
  than a result. **The combination is the compositor's choice, not the app's**:
  what the app sends is a `preferred_trigger` hint, and the combination it reads
  back is always null, so the settings screen cannot show you what is bound. Read
  it from the desktop's own keyboard-shortcut settings. Wherever a step below says
  "press the combination", it means that one.
- **`XDG_DATA_HOME` and `XDG_CONFIG_HOME` must be absolute, or unset.** Check with
  `echo "${XDG_DATA_HOME:-unset}"` / `echo "${XDG_CONFIG_HOME:-unset}"`. The XDG
  specification requires a *relative* value to be ignored, and the installer obeys
  that — it warns and falls back to `$HOME/.local/share` — while the
  `${XDG_DATA_HOME:-$HOME/.local/share}` expansions in the steps below would
  honour it. The two would then be pointing at different directories, which
  silently breaks step 3's removal and leaves an autostart entry that cleanup
  cannot find. If either is relative, unset it for the whole run. Safest of all:
  take the three directories from the installer's own `wrote …` output in step 1
  and use those paths verbatim.
- **A build.** `flutter build linux --debug`, leaving the binary at
  `build/linux/x64/debug/bundle/hotkey_grammar_corrector`. Note its **absolute**
  path — the installer refuses a relative one, because a compositor resolves a
  relative `Exec` against its own working directory rather than yours.
- **A session you are willing to log out of and back into once** — step 4 is a
  real logout. [Cleaning up](#cleaning-up) then asks you to remove the autostart
  entry before you next log out, so the daemon does not keep starting for
  whoever uses the machine after you.
- **`desktop-file-validate`** if your distribution ships `desktop-file-utils`.
  Optional, but it is the one check that reads the entries against the
  specification rather than against this repository's own hand-rolled reader.
- **Know what you are about to write into your real session.** The installer
  writes three files under your actual `$XDG_DATA_HOME` and `$XDG_CONFIG_HOME`,
  and step 3 temporarily moves one of them aside.
  [Cleaning up](#cleaning-up) lists every path involved, including the backup.
- **A backup directory for step 3.** Create it now so the commands below can name
  it: `mkdir -p ~/hgc-checklist-backup`. Do **not** use `/tmp` — a run that spans
  a logout can lose it, and step 3 is the step that spans a logout if you stop
  half-way.

---

## 1. Install the entries

- *Applies to:* X11 and Wayland — this is a file-installation step.
- *Action:*
  ```
  flutter build linux --debug
  tool/install_desktop_entries.sh \
    --exec "$PWD/build/linux/x64/debug/bundle/hotkey_grammar_corrector"
  ```
- *Expected:* three `wrote …` lines, in this order — the app-id entry under
  `${XDG_DATA_HOME:-~/.local/share}/applications/`, the autostart entry under
  `${XDG_CONFIG_HOME:-~/.config}/autostart/`, and the icon under
  `${XDG_DATA_HOME:-~/.local/share}/icons/hicolor/32x32/apps/` — each named
  `com.divertedriver.HotkeyGrammarCorrector`, followed by either a refreshed
  desktop-database line or a line saying `update-desktop-database` was not found.
  Exit status 0. **Record the three paths exactly as the `wrote …` lines give
  them** — those are the directories the rest of this procedure has to use. If a
  `warning: XDG_DATA_HOME is relative` or `XDG_CONFIG_HOME is relative` line
  appears, stop: the prerequisites explain why, and continuing produces a step 3
  that removes nothing while reading as a finding.
- *Then:* open the installed app-id entry and confirm its `Exec=` line carries
  the absolute path you passed, not the bare `hotkey_grammar_corrector` default.
  If you have it, run `desktop-file-validate` on both installed files and record
  its output verbatim, including warnings.
- *Settles:* none — this is the precondition for steps 2 to 5, and not itself
  one of DW-87's four facts.
- *If it diverges:* record the exit status, the stderr, and which of the three
  files exist afterwards. A partial install is the interesting case — the
  installer stages every write through a temporary file and renames, so a
  half-written entry should not be possible.
- [ ] **Done** — observation written into the results table below.

---

## 2. The compositor associates the registered app id with the installed entry

- *Applies to:* **Wayland only** (GNOME, and ideally KDE). This is a portal
  claim: on X11 the hotkey is a keybinder grab and no desktop entry is involved
  at all, so running this step there tells you nothing about AD-11 while looking
  as though it did.

This is the first of DW-87's four facts, and the one AD-11 makes a precondition
of the Wayland hotkey working at all: GNOME discards a GlobalShortcuts bind when
the app id the process registers has no installed desktop entry of the same
basename. The failure is silent — the portal handshake succeeds and the hotkey
simply never fires.

- *Action:* first confirm nothing of ours is already running —
  `pgrep -a hotkey_grammar_` must print nothing; if it prints something,
  `pkill hotkey_grammar_` and check again. Step 1 has just installed an autostart
  entry, and AD-14's lock means a launch made while an instance is up signals
  that instance and exits, leaving you inspecting the portal registration of a
  process you did not start. (Those two commands are truncated to the process
  name on purpose — see the note in
  `test/platform/runtime-observation-checklist.md`; the full
  `hotkey_grammar_corrector` is 24 characters and `pgrep` matches nothing at all
  against it, while `-f` would match your own shell.) Then start the daemon from
  a terminal. Once it is up, open the desktop's
  own keyboard-shortcuts settings and look for the application's global shortcut
  entry. On GNOME this is Settings → Keyboard → View and Customize Shortcuts,
  where portal-registered shortcuts appear under the owning application.
- *Expected:* the shortcut is listed, and it is listed **under the application's
  `Name` and icon from the installed entry** — not under a bare id, not under
  "Unknown application". That association, and its icon, is what
  `g_set_prgname(APPLICATION_ID)` exists to create.
- *Settles:* DW-87, fact 1.
- *If it diverges:* record exactly how the compositor labels it, and the output
  of `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path
  /org/freedesktop/portal/desktop --method
  org.freedesktop.DBus.Properties.Get org.freedesktop.portal.GlobalShortcuts
  version` alongside the compositor's name and version.
- [ ] **Done** — observation written into the results table below.

---

## 3. The bind survives *because of* the installed entry

- *Applies to:* **Wayland only**, for the same reason as step 2. On X11 the bind
  comes from keybinder and removing the app-id entry changes nothing — a reader
  who runs this step on X11 records "the bind worked either way, so AD-11's
  premise does not hold", which is a false finding this gate exists to prevent.

The second fact, and the one that needs care: **a bind that works either way
proves nothing about the file.** The observable is the removal.

> **This step moves a file out of your live session.** Sub-step 3.5 puts it back
> and is not optional. If you abandon the run at any point after 3.3 — for any
> reason, including a crash or a logout — do 3.5 before you do anything else, or
> you leave a machine whose global shortcut silently stops working and no
> installed file explaining why. [Cleaning up](#cleaning-up) names the backup
> path so it can be recovered even if you lose this page.

- *Action:*
  1. With the entries installed and the daemon running — and the portal grant
     dialog accepted — press the bound combination, read from the desktop's own
     keyboard-shortcut settings rather than from the app (see
     [Prerequisites](#prerequisites)). Confirm the panel appears.

     **If it does not appear, stop here.** Do not run 3.3. Record 3.1 as "no bind
     to test" along with whether the grant dialog appeared and what you did with
     it, and go to step 4. A removal test against a bind that never worked
     observes nothing at all, and 3.3 moves a file out of your live session to
     get it — all cost, no observation.
  2. Stop the daemon.
  3. Move the app-id entry into the backup directory from the prerequisites.
     Note the `apps` variable: step 1 installed under `$XDG_DATA_HOME` if you
     have one set, and a hardcoded `~/.local/share` would silently fail to move
     anything on such a machine — leaving the entry installed, the panel
     appearing at 3.4, and you recording "the bind is not resting on the file"
     when nothing was ever removed.
     ```
     apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
     mv "$apps/com.divertedriver.HotkeyGrammarCorrector.desktop" \
        ~/hgc-checklist-backup/
     update-desktop-database "$apps"   # if you have it
     ```
     **Confirm the removal before going on** — the removal *is* the observable,
     so an unverified one invalidates the whole step:
     ```
     ls "$apps/com.divertedriver.HotkeyGrammarCorrector.desktop"   # must fail
     ls ~/hgc-checklist-backup/                                    # must show it
     ```
     Leave the autostart entry alone.
  4. Start the daemon again and press the combination.
  5. **Put it back** — this is the sub-step that is not optional:
     ```
     apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
     mv ~/hgc-checklist-backup/com.divertedriver.HotkeyGrammarCorrector.desktop \
        "$apps/"
     update-desktop-database "$apps"   # if you have it
     ```
     Restart the daemon and press the combination once more.
- *Expected:* the panel appears at 3.1, **does not** appear at 3.4, and appears
  again at 3.5. If it appears at 3.4 as well — on a *Wayland* session, with the
  portal in play — the bind is not resting on the file and AD-11's premise does
  not hold on this compositor, which is a finding, not a failure, and is exactly
  why this step exists.
- *Settles:* DW-87, fact 2.
- *If it diverges:* record all three outcomes, and whether the daemon logged
  anything different at 3.4 — the portal handshake is expected to succeed either
  way, which is the whole problem. **Before recording 3.4's non-appearance as the
  expected result, rule out the three other things that look identical to it:** a
  grant dialog you dismissed or that never appeared, a grant the compositor
  refused (the log line names it), and a wrong keypress because the compositor
  rebound the trigger between starts. Each produces "the panel did not appear" on
  a machine where the file had nothing to do with it. Say which you ruled out and
  how.
- *Before moving on:* confirm the entry is back where it belongs —
  `ls "${XDG_DATA_HOME:-$HOME/.local/share}/applications/com.divertedriver.HotkeyGrammarCorrector.desktop"`
  must succeed and `ls ~/hgc-checklist-backup/` must be empty. Step 4 is a
  logout, and logging out with the entry still in the backup directory is how a
  temporary move becomes a permanent one.
- [ ] **Done** — observation written into the results table below.

---

## 4. Autostart starts the daemon at login

- *Applies to:* X11 and Wayland — autostart is an XDG mechanism, not a portal
  one. Record which session type you logged into.
- *Action:* make sure the daemon is **not** running (`pkill hotkey_grammar_`,
  then `pgrep -a hotkey_grammar_` to confirm nothing is left — truncated to the
  process name deliberately; see step 2). Confirm step 3.5 was done. Log out
  fully. Log back in. Wait thirty seconds, touching nothing.
- *Expected:* `pgrep -a hotkey_grammar_` finds exactly **one** process, which
  nobody launched, and pressing the combination raises the panel. Confirm also
  that no window is on screen and nothing is in the task switcher before you press
  anything — here that is part of "the daemon came up correctly", not a separate
  claim: the mapped-window question belongs to DW-9 and is observed by
  `test/platform/runtime-observation-checklist.md`, which this procedure does not
  carry.
- *Settles:* DW-87, fact 3.
- *If it diverges:* record whether the process is absent (autostart never ran) or
  present with a dead hotkey — two different failures.
  `journalctl --user -b | grep -i hotkey` usually carries the reason for the
  first.
- *A note on the tray:* if you see a tray indicator, note it; it is convenient
  extra evidence that the daemon came up. **Its absence is not a divergence** —
  the prerequisites ask for a GNOME Wayland session, and stock GNOME has hosted
  no StatusNotifier tray since 3.26 without the AppIndicator extension, so a
  perfectly healthy daemon shows no indicator there. `pgrep` and the hotkey are
  the liveness evidence this step actually rests on. AD-12's own tray claims —
  that the icon is drawn from the bundled asset, that its menu entry raises the
  panel, that the degraded state is legible — are not covered by this procedure;
  see [Not covered here](#not-covered-here).
- [ ] **Done** — observation written into the results table below.

---

## 5. An autostarted daemon plus a manual launch resolve to one instance

- *Applies to:* X11 and Wayland — AD-14's lock is a unix socket under
  `$XDG_RUNTIME_DIR` and knows nothing about the display server.
- *Action:* with the autostarted daemon from step 4 still running, launch the
  binary by hand from a terminal, using the same absolute path you installed. **The
  terminal has to belong to the graphical session you logged into** — a terminal
  window on that desktop, not an `ssh` connection and not a detached `tmux`. Before
  launching, run `echo $XDG_RUNTIME_DIR` there and confirm it is non-empty; then,
  after step 4's daemon started, confirm it is the same value the session has
  (`grep -z XDG_RUNTIME_DIR /proc/$(pgrep hotkey_grammar_)/environ | tr -d '\0'`).
  As soon as it returns, `echo $?`, then `pgrep -a hotkey_grammar_`.
- *Expected:* the manual launch exits **0** without staying resident, the
  autostarted instance's panel appears, and `pgrep` still finds exactly one
  process. One instance, one hotkey bind.
- *Settles:* DW-87, fact 4.
- *If it diverges:* record the exit code, the process count, whether any panel
  appeared, and any warning line naming the single-instance socket. Two live
  processes means the hotkey is bound twice, which is the outcome AD-14's lock
  exists to prevent. **First rule out a mis-scoped terminal:** the lock's address
  comes from `$XDG_RUNTIME_DIR`, so a terminal with a different or empty value
  computes a different address, and both processes were entitled to bind. That is
  not an AD-14 failure — it is the wrong terminal, and the step has to be redone.
  Record both values before concluding anything.
- *What this does and does not test:* the lock derives its address from
  `$XDG_RUNTIME_DIR` and never reads `Exec`
  (`lib/src/infrastructure/system/single_instance_lock.dart`), so two *different*
  commands under one runtime directory would meet the same lock. Identical `Exec`
  lines do not buy this result — what they buy is that login starts the same
  binary a user would start by hand, which is what makes this step's pairing
  meaningful in the first place.
- [ ] **Done** — observation written into the results table below.

---

## Cleaning up

Do this even if you abandoned the run part-way.

**First, the one that matters most.** If step 3 moved the app-id entry aside and
3.5 did not put it back, put it back now:

```
data="${XDG_DATA_HOME:-$HOME/.local/share}"
ls ~/hgc-checklist-backup/            # should be empty; if not, restore it:
mv ~/hgc-checklist-backup/com.divertedriver.HotkeyGrammarCorrector.desktop \
   "$data/applications/"
update-desktop-database "$data/applications"   # if you have it
```

The cache refresh belongs on this path too, not only on 3.5's. This is the
restore that runs after an *abandoned* run — which is exactly when the entry was
left displaced, and a stale desktop cache is the failure mode step 3 studies.

Then remove what you no longer want. Every path the run touched:

```
data="${XDG_DATA_HOME:-$HOME/.local/share}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
rmdir ~/hgc-checklist-backup                          # the step 3 backup, once empty
rm -f "$config/autostart/com.divertedriver.HotkeyGrammarCorrector.desktop"
rm -f "$data/applications/com.divertedriver.HotkeyGrammarCorrector.desktop"
rm -f "$data/icons/hicolor/32x32/apps/com.divertedriver.HotkeyGrammarCorrector.png"
update-desktop-database "$data/applications"   # if you have it
pkill hotkey_grammar_
```

Note that `rm -f` succeeds silently against a file that is not there, so it
cannot tell you whether the app-id entry was in the applications directory or
still in the backup directory when you ran it — which is why the backup check
comes first and is a separate command.

Remove the autostart entry before you log out for the last time, or the daemon
will keep starting at every login.

---

## Not covered here

- **Everything that needs only a display and one login** — no toplevel mapped at
  startup, residency, the summon being visible and focused, the focus-loss hide,
  the window-event echo ordering, the real X11 grab, the 100 ms budget, the live
  rebind, the panel's geometry and the settings affordance. Those are DW-9,
  DW-25, DW-26, DW-39, DW-44, DW-50 and DW-72, and they have their own procedure
  at **`test/platform/runtime-observation-checklist.md`**.
- **The tray indicator (AD-12)** — the icon's asset path, its menu raising the
  panel, and the legibility of the degraded state. Named in
  **`test/platform/tray_live_test.dart`**, owned by a ledger entry outside this
  one, and deliberately not folded in here: step 4 uses the indicator only as a
  liveness signal.
- **The X11 hotkey path.** Steps 2 and 3 are gated to Wayland because the claim
  is the portal's. What happens to a keybinder grab when a desktop entry is
  missing is not a question AD-11 asks, and no step here answers it.
- **The packaging format.** Whether these entries survive a Flatpak or a Snap is
  a separate open question — the AD-11 handshake changes shape under a sandbox,
  and none of it is what this procedure observes.
- **CI.** That the workflow file runs at all is its own open item and has nothing
  to do with a desktop.

---

## Recording the results

**This file is not the record.** Do not edit it to hold results, and do not edit
the deferred-work ledger either — hand the completed table to whoever is closing
DW-87.

```
Date            :
Operator        :
Desktop         : GNOME | KDE | other  (name and version)
Session type    : wayland | x11        (steps 2 and 3 need wayland)
Distribution    :
Portal          : xdg-desktop-portal version, and the backend behind it
Flutter version :
Repo commit     :
Binary path     : (the absolute path passed to --exec)
desktop-file-validate output (verbatim, warnings included):
```

| Step | Fact | Observed | As expected? | Notes |
|------|------|----------|--------------|-------|
| 1 | install (precondition) |  | yes / no |  |
| 2 | app id ↔ installed entry |  | yes / no / n/a (x11) |  |
| 3 | bind survives *because of* the file |  | see the block below |  |
| 4 | autostart at login |  | yes / no |  |
| 5 | one instance, manual launch exits 0 |  | yes / no |  |

Step 3 needs all three of its outcomes written down, not one verdict, plus the
confirmation that the file went back:

```
3.1 Bind with the entry installed  : panel appeared? yes | no
3.4 Bind with the entry removed    : panel appeared? yes | no
3.5 Bind with the entry restored   : panel appeared? yes | no
App-id entry back in $XDG_DATA_HOME/applications/ ?   yes | no
~/hgc-checklist-backup/ empty ?                       yes | no
```

Confirm before you file the results:

```
Cleaning up completed?  yes | no
```
