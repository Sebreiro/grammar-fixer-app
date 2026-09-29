# Worker-gone rebind observation — G-01-15 proved against a build that predates the fix

**This file is a record of an observation that was made, not a procedure for one
that is owed.** It is the same kind of artefact as
`test/platform/panel-toggle-observation.md` and is filed the same way:
`test/platform/runtime-observation-checklist.md` and
`test/platform/desktop-session-checklist.md` are the opposite kind of document —
manual procedures, pinned in `test/architecture/runtime_checklists_test.dart`'s
`_procedures` list because unconditionally skipped rows point at them by path.
**This file is deliberately not added to that list**, and section 6 says why in
its own voice rather than leaving the absence to be inferred.

**Date of the runs:** 2026-09-11.
**Gap this settles:** G-01-15 — `01-VERIFICATION.md` `gaps[0]`, `01-REVIEW.md`
CR-02. That gap's own words set the bar this file has to clear: *"this is code
inspection plus a zero-coverage finding, NOT an observed runtime failure. Nobody
killed the worker mid-grab and watched the screen"*, and *"the closure plan
should include the observation, not just the patch"*. Plan 01-15 is the oracle,
01-16 is the patch, and this is the observation.

**Harness:** `tool/uat/worker_gone_probe.sh`, one case `rebind-worker-gone`, run
`--at <rev>` at two revisions.

---

## 1. What was wrong

`X11GlobalHotkey`'s seam-refused catch arm computed the refusal's code
(`_refusalOf(error)`) and then branched only on whether a previous combination
happened to be recorded, so the distinction the whole `HotkeyRefusalCode` enum
exists to carry was discarded exactly where it changes the answer. A
`workerGone` refusal — the isolate that owns the X connection died with a reply
pending — therefore took the abandoned-rebind arm, which returns
`HotkeyBound(previous)` and logs *"the rebind was abandoned and the previous
combination is still in effect"*. The settings screen then rendered **"In
effect: Ctrl+Shift+G"** for a grab that no living code path serves and that the
X server is still swallowing from every other application.

## 2. The contrivance, named first rather than last

**Nothing outside this process can kill this daemon's worker isolate on demand,
and that is a finding in its own right rather than an inconvenience.**
`_X11Worker.handle` carries no `on Object` guard and `Isolate.spawn` defaults to
`errorsAreFatal: true`, so a Dart throw on the grab path really is fatal to the
worker at exactly the moment a reply is pending — `_ask` registers `_pending[id]`
*before* `commands.send(...)`, so there is an in-flight completer for
`_failPending` to complete when `onError` arrives. But every throw the worker can
actually take today is already guarded into a modelled refusal: `_openBindings`
catches `DynamicLibrary.open` and the whole `_X11Bindings` construction, and
`_openDisplay` reads a null pointer as a value. **So the arm is reachable in
production and unreachable from outside the process.** The worker death is
therefore injected, and this is the one contrived link in the run.

The injection, verbatim, as both runs printed it (`git diff` taken inside the
probe's throwaway worktree — one hunk, one file, and the probe halts if it is
not):

```diff
diff --git a/lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart b/lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart
index a3d7584..c89f018 100644
--- a/lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart
+++ b/lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart
@@ -704,6 +704,16 @@ final class _X11Worker {
   }
 
   void _grab(int id, String keysymName, int modifierMask) {
+    // PROBE INJECTION - tool/uat/worker_gone_probe.sh, gap G-01-15.
+    // The one contrived link: nothing outside this process can kill the worker
+    // isolate on demand. `handle` has no `on Object` guard and `Isolate.spawn`
+    // defaults to errorsAreFatal, so this throw is fatal to the worker at exactly
+    // the moment a reply is pending. Everything after the death is the shipped chain.
+    if (keysymName == 'F9') {
+      throw StateError(
+        'worker_gone_probe.sh injected worker death for keysymName=$keysymName',
+      );
+    }
     final bindings = _openBindings();
     if (bindings == null) {
       _reply(
```

**Fidelity, in UAT test 1's register: full, with one substitution.** What the
injection changes is **why** the worker died, not **what** the code did about it.
Everything downstream of the isolate's death is the shipped chain and no fake
appears anywhere on it: `Isolate.spawn`'s `onError`/`onExit` port,
`_onWorkerMessage`'s default arm, `_failPending`, `_refusalFor`'s
`workerGone` mapping, the real `HotkeyRegistrarRefusal` crossing the real seam,
`X11GlobalHotkey`'s catch arm, `_causeOf`, `_recordStatus`, the real
`SettingsController`, the real `HotkeyStatusView`, GTK, and a real X server. The
daemon under test is a real `flutter build linux --release` bundle, built by the
probe from a detached `git worktree` at the named revision; the startup bind of
`Ctrl+Shift+G` is a real `XGrabKey` on a real display, confirmed by a real press
mapping the panel before anything is contrived; and the rebind is driven through
the real settings screen — the gear, the capture field, `Ctrl+Shift+F9`, Apply —
with `xdotool`.

`F9` is the marker key because it is in `HotkeyKeyCatalogue`'s F1–F12 run, so the
startup bind of keysym `g` succeeds and `_effective` is genuinely set, and the
rebind is the one press that kills the worker. `Ctrl+Shift+F9` carries two
modifiers, so D-13's at-least-one-modifier rule is satisfied and the capture
field accepts it.

## 3. The before/after pair

| Run | Revision | `REFUSAL_CODE` | `LOG` | `VERDICT` | What the screen says |
| --- | --- | --- | --- | --- | --- |
| pre-fix | `4247446` (`42474469d8d2784445713f7f28aa7dc53b8d2a2a`) — the parent of 01-16's `lib/` commit `b421a9c` | `workerGone` | `abandoned` | **`REPORTED_IN_EFFECT`** | **"In effect: Ctrl+Shift+G"** — the false report |
| post-fix | `23ad817` and `49c5f9f` (both carry 01-16's fix; `git diff --numstat 23ad817 49c5f9f -- lib/` is empty) | `workerGone` | `refused` | **`REPORTED_UNAVAILABLE`** | the `noBackend` cause line, then the registrar's own sentence |

The verbatim result lines, with the daemon's own log line for the Apply beneath
each:

```
RESULT rebind-worker-gone REV=4247446 INJECTED=yes BOUND=Ctrl+Shift+G REQUESTED=Ctrl+Shift+F9 REFUSAL_CODE=workerGone LOG=abandoned SCREEN=/tmp/worker-gone-probe-out/pre-fix-4247446-20260911062323/settings-after-rebind.png VERDICT=REPORTED_IN_EFFECT
  {"timestamp":1789133029653,"level":"error","message":"the X11 key grab was refused, so the rebind was abandoned and the previous combination is still in effect","context":{"error_type":"HotkeyRegistrarRefusal","refusal_code":"workerGone"}}
```

```
RESULT rebind-worker-gone REV=49c5f9f INJECTED=yes BOUND=Ctrl+Shift+G REQUESTED=Ctrl+Shift+F9 REFUSAL_CODE=workerGone LOG=refused SCREEN=/tmp/worker-gone-probe-out/post-fix-2-49c5f9f-20260911062625/settings-after-rebind.png VERDICT=REPORTED_UNAVAILABLE
  {"timestamp":1789133211177,"level":"error","message":"the X11 key grab was refused","context":{"error_type":"HotkeyRegistrarRefusal","refusal_code":"workerGone"}}
  {"timestamp":1789133211177,"level":"warning","message":"global hotkeys are unavailable on this backend","context":{"outcome":"HotkeyUnavailable"}}
```

`REFUSAL_CODE=workerGone` on **both** sides is what makes this a proof by
difference rather than two unrelated runs: the same code reaches the same arm at
both revisions, and only the answer changes. `VERDICT` is classified from the
daemon log alone — `abandoned` ⇒ `REPORTED_IN_EFFECT`, `refused` ⇒
`REPORTED_UNAVAILABLE`, anything else ⇒ `UNCLASSIFIED` with the raw lines
printed. The screen is recorded, not classified: an OCR verdict would be a second
oracle with a second failure mode, and the point of this record is that a human
reads the sentence.

### What the screen renders, transcribed

**Post-fix** (`test/platform/evidence/worker-gone-rebind-sentence-pair.png`,
captured by the `49c5f9f` run and byte-identical to the `23ad817` run's capture —
`compare -metric AE` reports **0** differing pixels):

```
"This desktop provides no global shortcuts, so no combination can be registered here."
"the X11 hotkey worker stopped before answering, so no global shortcut is registered — the tray menu still opens the panel"
"Whether this app or your desktop would own the shortcut is not known until one is registered."
```

The second line is the **registrar's own** sentence (`_failPending`'s wording at
`x11_key_grab_registrar.dart:281-284`) carried through verbatim, which is the
same property UAT test 1 recorded for the `noBackend` pair. **The tray is named
exactly once across the pair** — only in the second line, because `_causeLine`'s
three sentences deliberately never mention it (AD-12, D-07). The field label has
changed from "Shortcut" to "Shortcut to request", which is
`HotkeyCaptureField._fieldLabel` answering `null` authority: nothing is claimed
about who would own the shortcut, because nothing holds one. **No "In effect:"
line appears at all**, and the standing "Keep current" hint is gone with it.

**Pre-fix**, from the same point in the same run sequence
(`/tmp/worker-gone-probe-out/pre-fix-4247446-20260911062323/settings-after-rebind.png`,
not committed — the committed image is the post-fix one):

```
"In effect: Ctrl+Shift+G"
"That differs from your preference, Ctrl+Shift+F9."
```

The pre-fix screen also contradicts itself one control lower down, which is
worth recording because it is the same falsehood seen from a second direction:
the capture field's standing hint reads *"Your current shortcut, Ctrl+Shift+F9,
cannot be pressed into this box: while it is registered it goes to this app
instead of to this window"* — the config write-through has persisted
`Ctrl+Shift+F9` — while the status view above it names `Ctrl+Shift+G` as the one
in effect. Neither is registered. The worker that held `Ctrl+Shift+G` is dead.

### Run agreement, and the one halt

Three runs produced verdicts and they agree: two post-fix runs from clean starts
(`23ad817`, `49c5f9f`) match on every field of the result line except `REV`, the
`SCREEN` path and the log timestamps, and their screen captures are byte-identical;
the pre-fix run (`4247446`) reports the opposite verdict.

**A fourth run halted and is reported rather than dropped.** An earlier post-fix
attempt halted at the warm-up step with *"Ctrl+Shift+G did not map the panel
within 10 s (Map State is still IsUnMapped) — the daemon does not own the grab,
so nothing this run observed could be trusted"*. A halt is not a verdict and this
one is not recorded as one. Its cause is **undiagnosed**: that run's daemon log
lived under the temp root the exit trap removes, so the evidence was destroyed
with it — which is the defect the probe's own `49c5f9f` commit then fixed by
writing the daemon log into the surviving output directory instead. Two
candidates remain open, and either is checkable the next time it happens: the
startup `XGrabKey` was refused (the log would carry a `keyRefused` line at
startup), or the press was delivered and the panel did not map (the log would
carry nothing and the halt screenshot, absent here because `import` cannot
capture an unmapped window, would show the state). It reproduced neither in the
run before it nor in the two after it.

## 4. The environment

| Fact | Value |
| --- | --- |
| Display | `Xvfb :99 -screen 0 1440x900x24 -nolisten tcp` |
| Window manager | `openbox 3.6.1` |
| Kernel | Linux 6.12.63-1-MANJARO (dev container) |
| Toolchain | Flutter 3.44.8 stable |
| Bundle | built by the probe, per run, from a detached `git worktree` — `flutter build linux --release` |
| Pre-fix snapshot | `lib/libapp.so` built `2026-09-11T13:23:42Z`, from `4247446` |
| Post-fix snapshots | `2026-09-11T13:21:11Z` from `23ad817`; `2026-09-11T13:26:44Z` from `49c5f9f` |
| Freshness | asserted per run: the AOT snapshot must be newer than the worktree that produced it (the launcher's own mtime is **not** the signal — it carries no Dart code, panel-toggle-observation.md, T-01-65) |
| Session isolation | one throwaway `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_RUNTIME_DIR` per run (T-01-81), removed by the exit trap |
| Panel route | AD-14's second launch, because this container has no StatusNotifier host; settings opened with the panel's gear (`daemon_home.dart:223`) |
| Presses | `xdotool key --clearmodifiers`, i.e. `XTestFakeKeyEvent` |

**The developer's tree is provably untouched by all four runs.** The injection is
applied only inside the throwaway worktree; the probe refuses to start unless
`git status --porcelain -uno -- lib/ test/ tool/` prints nothing, and asserts the
same scoped emptiness plus the absence of any `git worktree list` entry under its
own `worker-gone-probe.` temp root on the way out, including on halts. Both held
after every run. Nothing in the probe uses `git checkout --` or `git stash`.

## 5. What this run does NOT settle

In the register `runtime-observation-checklist.md` fixes: a claim that was not
observed is stated as unobserved, never quietly reported as met. **This run
closes G-01-15 and nothing else.** Each item below is named with the phase or
gate that owns it.

- **The stranded passive grab is not released, and this run now shows that
  directly rather than arguing it.** Killing the isolate does not close the X
  socket it opened — the `Display` is a raw pointer with no finalizer — so the
  server keeps the passive grab and keeps swallowing the combination for every
  other application until the process exits. The post-fix daemon's own shutdown
  log says so out loud: `"disposing the hotkey adapter did not finish within
  5000 ms; it was abandoned…"` followed by `"releasing the global hotkey grab did
  not finish within 5000 ms; it was abandoned…"`. What changed in 01-16 is that
  the user is now *told* the shortcut is not in effect instead of being told it
  is; the grab itself is still stranded, and releasing it needs worker-lifecycle
  replacement. **Phase 5 (CR-01 / WR-01 / CR-03 / WR-02)**, filed by plan 01-20
  as T-01-76's accepted residual.
- **The `noBackend` cause line overstates for a dead worker.** "This desktop
  provides no global shortcuts, so no combination can be registered here" is not
  true of this host: the desktop *does* provide global shortcuts; this daemon's
  worker died. The registrar's second sentence beside it is accurate, so the pair
  overstates in its first line and is accurate in its second — which is still
  better than the single line that was simply false, and is not the same as being
  right. That text is `hotkey_status_view`'s, and it belongs to **WR-06 /
  SETTINGS-09 (FLAT-16), Phase 2**. It was deliberately not edited here.
- **The Wayland arm is untouched and unobservable here.** No portal binary, no
  portal `.service` file, no GlobalShortcuts backend and no session bus in this
  container. Both of `01-VERIFICATION.md`'s `behavior_unverified_items` stand
  unchanged — the compositor's own description text read back verbatim, and the
  divergent-grant / revoked transitions — and nothing in this run touches either.
- **The seven UAT rows recorded `result: skipped`** on 2026-09-11 by human
  decision are **not** closed by this run, each for the reason recorded against
  it: test 2's Wayland `revoked` half, test 4 (no StatusNotifier host at all),
  test 5 (no `flatpak`, no portal), test 6 (no portal to park, no compositor to
  host the dialog), test 7 (an X11 grab resolves in microseconds and there is no
  portal here to park a bind on), test 11 and test 12 (no portal). This run
  raised a panel and a settings screen; it did not acquire a tray, a portal or a
  Flatpak sandbox.
- **One window manager only.** Every reading above was taken under
  `openbox 3.6.1` on `Xvfb`. GNOME/Mutter and KDE/KWin are unmeasured, and grab
  interaction and focus handoff are exactly where window managers differ.
- **Every press was synthetic.** `xdotool key` is `XTestFakeKeyEvent` — a
  synthetic event on the same display. It exercises the grab and the capture
  field, and it is not a human finger on a real keyboard; it settles nothing
  about hardware autorepeat or modifier latching. The same two limits §6 of the
  panel-toggle record already states.
- **Nothing here measures latency.** CAP-1's <100 ms summon budget is not this
  document's subject; the probe settles 1.5 s after every GUI step so that timing
  plays no part in any reading.
- **The `workerGone` code is not shown to arise unaided.** The probe proves the
  chain from the isolate's death onward. It does not prove that any production
  input can kill the worker today — section 2 says the opposite, and that
  unreachability is itself the reason the death is injected.

## 6. Why this file is NOT added to `runtime_checklists_test.dart`'s `_procedures`

It is not added, and these are the three reasons, each checkable against the tree
as it stands:

1. **`_procedures` holds manual procedures.** Each entry is a step-numbered
   instruction sheet whose every step carries a `*Settles:* DW-nn` bullet, with
   `preconditionSteps`, `groups`, a results table, and a claim set checked in
   both directions. The suite's own closing row prints *"both are manual: read
   them, do not run them"*. This record is the opposite kind of thing: the
   write-up of a run that already happened.
2. **The precedent is already set inside this phase.**
   `test/platform/panel-toggle-observation.md` is the same kind of artefact from
   the same probe family and is **not** a `_Procedure`; it appears in
   `runtime_checklists_test.dart` only inside that closing row's print, as a
   completed run that corrected the print's own text. Adding this record while
   its sibling stays out would invent a second convention.
3. **The structural assertions would not merely be unnecessary, they would
   fail.** `_stepsIn`, `_requiredBullets` and the both-directions `claims` check
   all read numbered steps carrying DW ids, and an observation record has
   neither. Nor does anything point at it: the `_procedures` guard exists because
   unconditionally-skipped `fail()` rows name a procedure by path and a skipped
   row cannot report that the path rotted. No skipped row names this record.

So `test/architecture/runtime_checklists_test.dart` is not edited by the plan
that produced this file, and is correctly absent from its `files_modified`.

## 7. Re-running it

```
export PATH=$PATH:/home/vscode/flutter/bin:/home/vscode/flutter/bin/cache/dart-sdk/bin
DISPLAY=:99 ./tool/uat/worker_gone_probe.sh --at <sha> --label <name>
```

Each run builds its own bundle from a fresh detached worktree, so a cold
`flutter build linux --release` of several minutes per run is expected rather
than a hang. The run prints its revision, the injection as a diff, the chosen
toplevel id, the daemon's own log lines for the Apply, and one `RESULT
rebind-worker-gone` line. Everything it writes that outlives the run — the window
captures, the daemon log, the injection diff — is in the output directory the
`SCREEN=` field names, and one of those captures is of the correction panel rather
than the settings screen: the gear that opens settings is overlaid on the panel,
so the shot taken before that click is a picture of the panel editor.

That directory is restricted to `0700` before any capture, because the daemon
seeds the editor from CLIPBOARD on show. `.claude/CLAUDE.md`'s Logging rule —
"Never log `input_text`, suggestion bodies, or clipboard content" — carries no
exemption for `tool/`; `/tmp` is world-traversable, so the restriction protects
the picture. The probe checks the selection's `TARGETS` and refuses when another
CLIPBOARD owner answers, even when its payload is newline-only, empty, or
non-text. A refusal does not alter that owner's selection. On an accepted run,
after all preflight checks, the probe takes ownership with an empty payload and
records only its own owner process for teardown.

The panel screenshot's empty-editor expectation rests on that checked selection
state, not on an unconditional construction guarantee. An unrelated client on a
shared display can change CLIPBOARD between the checks or before the panel opens;
use a dedicated Xvfb display for this probe. The run-scoped teardown likewise
signals only processes this run started.
