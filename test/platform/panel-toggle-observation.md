# Panel-toggle observation — G-01-13 proved against a recorded baseline

**This file is a record of an observation that was made, not a procedure for one
that is owed.** That distinction decides where it belongs, so state it here
before a later reader files it wrongly. `test/platform/runtime-observation-checklist.md`
and `test/platform/desktop-session-checklist.md` are the opposite kind of
document: they hold claims this container *cannot* observe, they are pointed at
by six unconditionally skipped rows with a `fail()` body, and
`test/architecture/runtime_checklists_test.dart` pins them in its `_procedures`
list so the pointers cannot rot. **This file is deliberately not added to that
list.** Nothing here is owed to a real desktop, nothing skipped points at it, and
registering it would say the opposite of what it is. What is owed from a real
desktop is in [6. Not settled here](#6-not-settled-here), in that register.

**Date of the run:** 2026-09-10.
**Gaps this settles:** G-01-13 (the defect), and the G-01-14 re-test that UAT
test 14's `retest_after_fix` block asks for. `01-UAT.md` tests 13 and 14 are the
items; `WINDOWS.md` 24 is the behaviour change section 3 names.

## Environment

| Fact | Value |
| --- | --- |
| Display | `Xvfb :99 -screen 0 1440x900x24 -nolisten tcp` |
| Window manager | `openbox 3.6.1` |
| Kernel | Linux 6.12.63-1-MANJARO (dev container) |
| Toolchain | Flutter 3.44.8 stable |
| Bundle | `build/linux/x64/release/bundle/hotkey_grammar_corrector` (release) |
| Bundle Dart snapshot | `lib/libapp.so`, built `2026-09-10T14:21:40Z` |
| Commit the snapshot was built from | `dc6079b` + `791ddb9` — the two 01-12 fix commits, the later at `2026-09-10T14:11:16Z` |
| Harness | `tool/uat/panel_toggle_probe.sh` (`panel_toggle_probe`), routes run as `all`, twice |
| Session isolation | one throwaway `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_RUNTIME_DIR` per route (T-01-55) |

**Why the bundle's provenance is stated three ways rather than by its mtime**
(T-01-65). A run against a bundle built *before* the fix is indistinguishable
from a run against a fixed one except in its verdicts, so "the bundle is fresh"
is the one claim here that cannot be taken on trust. Three facts settle it, and
the launcher's own mtime is *not* one of them:

1. `flutter build linux --release` was re-run immediately before the measurement
   and produced no new output — the build was already current.
2. The last commit touching `lib/` is `791ddb9` at `2026-09-10T14:11:16Z`; the
   AOT snapshot `lib/libapp.so` is dated `2026-09-10T14:21:40Z`, ten minutes
   later, and `git status --short lib/` was empty at build time. Nothing in the
   Dart tree was newer than the snapshot.
3. `strings build/linux/x64/release/bundle/lib/libapp.so` contains
   `X11KeyboardFocusWitness`, `AbsentKeyboardFocusWitness` and
   `_keyboardStillHere` — three symbols that did not exist before `dc6079b`. The
   fix is *in* the artifact that was measured, which is a stronger statement than
   any timestamp.

The launcher executable `hotkey_grammar_corrector` is still dated 2026-09-04 and
this is expected, not stale: it holds no Dart code. Do not use it as the
freshness signal.

---

## 1. What was wrong

Once the panel was visible, the bound combination never hid it. The daemon's own
passive grab generates a `FocusOut(NotifyGrab)` on the panel at the instant the
combination is pressed, and the adapter treated any focus-out as a CAP-14
dismissal — so the daemon dismissed its own panel on its own shortcut. That
dismissal then raced the toggle's own activation and *won*, so the panel unmapped
and the toggle immediately re-mapped it.

The defect was an AND-gate, which is why it survived a phase: it needs a focus
loss the app inflicted on itself **and** a toggle arriving in the same beat to
re-show what the dismissal took away. Either condition alone looks healthy.
`foreign-grab` in section 3 is the route that isolates the first condition from
the second, and it is the diagnosis's smoking gun.

## 2. Why `xwininfo`'s Map State is the wrong oracle for it

Because the unmap and the re-map are 8–16 ms apart (measured, 01-UAT.md test 13),
and `Map State` is a state, not a transition. A read taken after the beat reports
`IsViewable` on **both** sides of the flicker: before the press because the panel
was up, and after it because the toggle had already put it back. The panel really
did unmap and re-map — 01-11's event stream counted both events — and the state
oracle was blind to all of it. That is also how UAT test 14 came to be raised as
a defect and then withdrawn: it was this flicker sampled one beat late.

So every verdict below is classified from a timestamped X event stream on the
daemon's own toplevel (`xev -event structure -event focus`, one line-prefixed
epoch per line), by counting `UnmapNotify`/`MapNotify` and their order. No
tolerance, no retry, and no "if it looks hidden, call it hidden".

**One aside, flagged as an aside.** During the section 5 check the disqualified
oracle happened to answer correctly: `IsViewable` → `IsUnMapped` → `IsViewable`
across summon, hide and re-summon. That is not a rehabilitation of `Map State`.
It reads correctly *now* precisely because there is no longer a flicker to
mis-sample, which is the thing this document exists to establish by other means.

## 3. The route table — before and after

Pre-fix verdicts are quoted from 01-11's recorded baseline, not re-derived. Both
`all` runs on the fixed build agreed on every verdict; window ids in the focus
columns differ between runs (a fresh `xmessage` each time) and no verdict does.

| Route | Pre-fix (01-11) | Post-fix (this run) | What it proves |
| --- | --- | --- | --- |
| `show` | `SHOW` | `SHOW` | CAP-1's summon is untouched. A hidden panel has no focus to lose, so this route never had the defect. |
| `hide` | **`FLICKER`** | **`HIDE`** | G-01-13 itself. One press at a visible panel now produces one `UnmapNotify` and no `MapNotify`. |
| `alternate` | **`SHOW,FLICKER,FLICKER,FLICKER`** | **`SHOW,HIDE,SHOW,HIDE`** | The reporter's "shows once, then never hides". Four presses from hidden now alternate. |
| `focus-steal` | `HIDE` | `HIDE` | CAP-14 is not broken by the fix: a real second toplevel taking the keyboard still dismisses. |
| `desktop-click` | `HIDE` | `HIDE` | CAP-14 not broken, second route: a desktop click still dismisses. |
| `steal-after-presses` | *(no baseline — added here)* | `HIDE` | Regression guard. See section 4 for what it does and does not carry. |
| `press-then-click` ×3 | *(no baseline — added here)* | `HIDE,HIDE,HIDE` | Regression guard, same register. |
| `foreign-grab` | `HIDE` | **`NOTHING`** | Condition 1 alone, isolated. **`NOTHING` is the pass on this route** — see below. |

The verbatim post-fix result lines, second run:

```
ROUTE show UNMAP=0 MAP=1 FIRST=Map FOCUS_BEFORE=2097439 FOCUS_AFTER=4194308 WINDOW=all VERDICT=SHOW
ROUTE hide UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=all VERDICT=HIDE
ROUTE alternate-1 UNMAP=0 MAP=1 FIRST=Map FOCUS_BEFORE=2097439 FOCUS_AFTER=4194308 WINDOW=all VERDICT=SHOW
ROUTE alternate-2 UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=all VERDICT=HIDE
ROUTE alternate-3 UNMAP=0 MAP=1 FIRST=Map FOCUS_BEFORE=2097439 FOCUS_AFTER=4194308 WINDOW=all VERDICT=SHOW
ROUTE alternate-4 UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=all VERDICT=HIDE
ROUTE focus-steal UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=10485792 WINDOW=all VERDICT=HIDE
ROUTE desktop-click UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=all VERDICT=HIDE
ROUTE steal-after-presses UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=10485792 PRESTEAL=mapped WINDOW=post-steal VERDICT=HIDE
ROUTE press-then-click-1 UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=post-click VERDICT=HIDE
ROUTE press-then-click-2 UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=post-click VERDICT=HIDE
ROUTE press-then-click-3 UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=post-click VERDICT=HIDE
ROUTE foreign-grab UNMAP=0 MAP=0 FIRST=none FOCUS_BEFORE=4194308 FOCUS_AFTER=4194308 WINDOW=all VERDICT=NOTHING
```

No route on either run classified `FLICKER`, and no route's classified window
contains a `MapNotify` at all where it contains an `UnmapNotify`: every
dismissal is a single clean edge. (`press-then-click`'s *whole* stream does
contain an unmap followed by a map — that is the route deliberately
re-establishing a mapped panel between the press and the click, and it lies
outside the `WINDOW=post-click` slice it classifies from.)

### `foreign-grab`: `NOTHING` is the pass, and it is a behaviour change

Read this row carefully, because a reader skimming for `HIDE` will mis-read it.
`foreign-grab` fires a combination the daemon does **not** own — a second X
client holds a passive grab on it — so the daemon receives no activation of any
kind. The only thing that reaches its window is a grab-induced focus-out. Before
the fix that alone dismissed the panel: condition 1 of the defect, on its own,
with no toggle to confuse it. After the fix it must do nothing, because the
keyboard demonstrably never went anywhere — and the focus columns now say so
directly: `FOCUS_BEFORE=FOCUS_AFTER=4194308`, the panel's own window on both
sides. `UNMAP=0 MAP=0 VERDICT=NOTHING` is therefore the *fix working*, not the
harness failing.

**And it is a deliberate behaviour change, stated as a change rather than
absorbed into the fix's claim.** A foreign client's global shortcut fired while
our panel is up no longer dismisses the panel. This cannot be narrowed away: a
foreign passive grab moves no focus, exactly as ours does not, so the two are
indistinguishable to a question about the focus — and that indistinguishability
*is* the mechanism the fix keys on. Not dismissing is arguably the better answer
(the panel keeps the keyboard back), but it is not the old answer. Recorded in
`WINDOWS.md` as entry 24; 01-14 owes the ledger entry.

This also settles, empirically, a point 01-11 could only infer. 01-11 warned that
the pre-fix `foreign-grab` focus reading `4194308 -> 2097439` was an artefact of
the dismissal rather than a real transfer. With the dismissal gone the same route
reads `4194308 -> 4194308`: the focus never moved, and openbox held it only
because the panel had unmapped.

## 4. The G-01-14 re-test, and what it does not settle

UAT test 14 was **withdrawn** during the G-01-13 diagnosis — it was this flicker
sampled one beat late, not a second defect. Its `retest_after_fix` block names a
latent mechanism, and 01-12 changed the very state that mechanism turns on
(`_focused` now survives a suppressed focus-out, removing the arm's dependence on
a `FocusIn(NotifyUngrab)` coming back to re-arm it). So its four focus routes are
owed here as a **regression guard** over that change.

All four post-fix verdicts, all `HIDE`:

| Test 14 route | Harness route | Post-fix |
| --- | --- | --- |
| a real window (`xmessage`) takes the focus | `focus-steal` | `HIDE` |
| a desktop click moves focus to openbox | `desktop-click` | `HIDE` |
| the same after four mapped presses | `steal-after-presses` | `HIDE` (`PRESTEAL=mapped`, `WINDOW=post-steal`) |
| a press then a desktop click, three attempts | `press-then-click-1..3` | `HIDE,HIDE,HIDE` |

**What that does not settle. Four things, plainly:**

1. The `NotifyUngrab`/`_focused` mechanism `retest_after_fix` names **has never
   reproduced in this container**. It was *inferred* — from presses 1 and 3
   ending on `FocusIn(NotifyUngrab)` while 2 and 4 ended on
   `FocusIn(NotifyNormal)` — and never observed. Nobody has seen GDK drop the
   `NotifyUngrab` form here.
2. `steal-after-presses` and `press-then-click` have **no pre-fix baseline**,
   because 01-11 did not carry them. Their rows in section 3 have an empty
   "before" column for that reason and not by oversight.
3. Per UAT test 14's **own HEAD evidence** the blur path was healthy on the
   broken build and every one of its four routes dismissed. So a `HIDE` from
   these two routes **discriminates nothing**: it is the same answer the broken
   build gave.
4. They are therefore **regression guards over 01-12's change to the recorded
   keyboard state, not evidence that the mechanism was exercised.** What they buy
   is the absence of a symptom after an edit that could plausibly have introduced
   one — moving a `_focused` clear is exactly the kind of change that breaks a
   dismissal three gestures later — and that is worth having, at that value and
   no more.

Both routes also set a trap for themselves that a naive form would fall into, and
both traps produce a green result rather than a red one. Post-fix each press
*toggles*, so `steal-after-presses` asserts `PRESTEAL=mapped` — an
event-confirmed mapped panel immediately before the steal, re-established with
one further press if the press count left it hidden — rather than letting press
parity decide whether there was a panel to dismiss. And in `press-then-click` the
press at a mapped panel now dismisses the panel *itself*, so a whole-press window
would read `UNMAP=1 MAP=0` and go green over the toggle's own unmap while never
testing the click; that route therefore re-establishes a mapped panel between the
press and the click and classifies only from `WINDOW=post-click`.

**One finding falls out of that, and it is a finding rather than a workaround.**
The state UAT test 14 worried about — a suppressed focus-out with the panel still
mapped — is **no longer reachable by that gesture at all**, because the press now
hides the panel. The one route that still produces it is `foreign-grab`: a
suppressed focus-out with no activation, panel left up. If the
`NotifyUngrab`/`_focused` mechanism ever does reproduce, **composing
`foreign-grab` with a click is the probe that would exercise it.** That route is
deliberately not added here.

## 5. The AD-18 consequence — the clipboard sentinel, re-seeded

Confirmed by hand, on the same bundle and display.

AD-18 is why this is visible at all. Before the fix, the departure recorded for a
press at a visible panel was `focusLost`, and `correction_controller.dart:401`
leaves `_dismissalStands` untouched for `focusLost` — so the following `shown`
began no fresh session and the editor kept its text. After the fix the press
produces a real `hide()` request, whose departure is `dismissed`, so the next
`shown` clears the panel and re-seeds from the clipboard. This is the reporter's
original "clipboard sentinel not re-seeded" observation resolving from the other
side, and it is a second oracle that touches `xev` not at all.

Procedure and result:

| Step | Observed |
| --- | --- |
| `ZZALPHA111` on the clipboard, press to show | editor reads `ZZALPHA111`; `Map State: IsViewable` |
| `QQBETA222` on the clipboard, press to hide | `Map State: IsUnMapped` |
| press to show again | editor reads **`QQBETA222`**; `Map State: IsViewable` |

**Pass.** Before the fix the second summon kept `ZZALPHA111`.

Screenshots, in `test/platform/evidence/`:

- `panel-toggle-ad18-first-summon.png` — the first summon, editor reading `ZZALPHA111`.
- `panel-toggle-ad18-second-summon.png` — the summon after the hide, editor reading `QQBETA222`.

The two strings are sentinels chosen so that no real user text ever reached the
clipboard or an artifact (T-01-67). Reading text off a screenshot is a human
check by design and is not gated by any automated assertion.

## 6. Not settled here

In the register `runtime-observation-checklist.md` fixes: a claim that was not
observed is stated as unobserved, never quietly reported as met. What follows was
argued, or not reached, and is owed to somewhere other than this container.

- **The Wayland arm is unobserved, and unchanged by argument rather than by
  measurement.** There is no `xdg-desktop-portal` and no GlobalShortcuts backend
  in this container, so the portal path could not be exercised at all. It is
  wired to `AbsentKeyboardFocusWitness`, a null object that never suppresses, so
  the reasoning is that Wayland's dismissal behaviour is byte-for-byte what it
  was before `dc6079b`. That is a reading of the composition root, not an
  observation of a running compositor. Nobody has watched a panel on Wayland do
  any of this.
- **One window manager only.** Every verdict above was measured under
  `openbox 3.6.1` on `Xvfb`. Focus handoff, map/unmap sequencing and grab
  interaction are exactly the areas where window managers differ, so this is one
  confirmation short of a real desktop. GNOME/Mutter and KDE/KWin are unmeasured.
- **A real physical keyboard is unmeasured.** Every press here came from
  `xdotool key`, i.e. `XTestFakeKeyEvent`. That is a synthetic event on the same
  display; it exercised the grab and the toggle, but it is not a human finger on
  a real keyboard and does not settle anything about hardware autorepeat or
  modifier latching.
- **The `NotifyUngrab`/`_focused` mechanism of section 4 remains unreproduced**,
  and no route here exercises it. Named again because it would be easy to read
  four `HIDE`s as having settled it.
- **Nothing here measures latency.** CAP-1's <100 ms summon budget is not this
  document's subject; the harness settles 1000 ms after every stimulus precisely
  so timing plays no part in a verdict.
