---
phase: 01-hotkey-truth
plan: 17
subsystem: testing
tags: [x11, hotkey, workerGone, CR-02, live-probe, uat, xvfb, observation]

# Dependency graph
requires:
  - phase: 01-hotkey-truth
    provides: "01-15's fail-first workerGone oracle and the frozen row name; 01-16's cause-decides arm (commit b421a9c) and the revision before it (4247446); 01-11/01-13's live-probe house shape in tool/uat/panel_toggle_probe.sh"
provides:
  - "tool/uat/worker_gone_probe.sh — a reproducible live probe that builds a real release bundle from a detached git worktree at a caller-named revision, kills the X11 key-grab worker isolate for real mid-rebind, drives the real settings screen, and emits one machine-readable RESULT line"
  - "A before/after pair of recorded runs: the defect reproduced live at 4247446 (LOG=abandoned, VERDICT=REPORTED_IN_EFFECT) and the fix observed live at 23ad817 and 49c5f9f (LOG=refused, VERDICT=REPORTED_UNAVAILABLE)"
  - "test/platform/evidence/worker-gone-rebind-sentence-pair.png — the settings screen as rendered after a real worker death mid-rebind on the fixed build"
  - "test/platform/worker-gone-observation.md — the dated record: the contrivance named first, the pair, the environment, and what the run does not settle"
  - "A directly observed instance of the stranded passive grab: the post-fix daemon's own shutdown log carries two 5000 ms abandonment lines for the hotkey adapter and the grab release"
affects: [01-20, phase-02, phase-05, hotkey, x11, settings]

# Actuals (#2632) — chars/4 over the text files actually changed (45,482 chars).
# The committed PNG (49,875 bytes, binary) is deliberately not counted on this scale.
actuals:
  tokens: 11371
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Injection-in-a-throwaway-worktree: a source-level fault injection is applied only inside a detached `git worktree` under a named temp root, built there, and removed on every path including halts — so the developer's tree is provably untouched and the probe's own leak is distinguishable from work in progress"
    - "Name the contrivance in the result line, the record and the SUMMARY: INJECTED=yes is a field, the diff is printed under every RESULT line, and the fidelity claim is stated in the 'what changed is why, not what' register"
    - "Confirm every GUI step or halt by name: in a container with no OCR and no accessibility bridge, a click is confirmed by the pixels it changed on the window, and a step that changed nothing halts naming the step, the window id and the screenshot"

key-files:
  created:
    - tool/uat/worker_gone_probe.sh
    - test/platform/worker-gone-observation.md
    - test/platform/evidence/worker-gone-rebind-sentence-pair.png
  modified:
    - .planning/WINDOWS.md

key-decisions:
  - "The pre-fix revision was resolved from history, not guessed: `git log --oneline -- lib/src/infrastructure/hotkey/x11_global_hotkey.dart` names b421a9c as 01-16's fix, and its parent 4247446 is what the pre-fix run builds. No HEAD~n arithmetic, which a later commit would invalidate."
  - "VERDICT is classified from the daemon log alone; the screen is recorded, not classified. An OCR verdict would be a second oracle with a second failure mode, and the point of the record is that a human reads the sentence."
  - "The config is asserted rather than hand-seeded: the shipped defaults derive two provider settings from the running host, so a hand-built config would either duplicate that derivation or change what the daemon does at startup. Filed as WINDOWS entry 34."
  - "The one halted run is reported as a halt, not folded into the pair and not dropped. Its cause is undiagnosed because that run's daemon log was destroyed with the temp root — the defect commit 49c5f9f then fixed."
  - "test/architecture/runtime_checklists_test.dart is NOT edited: all three reasons the plan states were checked against the tree and all three still hold."

patterns-established:
  - "A halt must not destroy its own evidence: anything a reader needs to act on a halt (the daemon log, the injection diff, the screenshot) is written outside the directory the exit trap removes."
  - "Proof by difference over assertion: the same probe, the same injected code, the same refusal code at both revisions, and only the answer changes — so the run measures the fix rather than the harness."

requirements-completed: [HOTKEY-01, HOTKEY-08]
# Declared because the plan declares them. This is the LAST of the three plans
# (01-15, 01-16, 01-17) declaring both, so the shared-ID gate should release them
# here.

coverage:
  - id: D1
    description: "The workerGone rebind arm is reached FOR REAL on the fixed build — a real release bundle, a real worker isolate that really dies mid-grab, a real _failPending, a real HotkeyRegistrarRefusal crossing the real seam — and the probe reports REFUSAL_CODE=workerGone LOG=refused VERDICT=REPORTED_UNAVAILABLE"
    requirement: "HOTKEY-01"
    verification:
      - kind: e2e
        ref: "DISPLAY=:99 ./tool/uat/worker_gone_probe.sh --at HEAD  →  RESULT rebind-worker-gone REV=23ad817 … VERDICT=REPORTED_UNAVAILABLE"
        status: pass
      - kind: e2e
        ref: "DISPLAY=:99 ./tool/uat/worker_gone_probe.sh --at HEAD --label post-fix-2  →  RESULT rebind-worker-gone REV=49c5f9f … VERDICT=REPORTED_UNAVAILABLE (every field but REV, SCREEN and the timestamps identical to the run above)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Proof by difference: the same probe at 4247446 — the revision that provably predates 01-16's lib/ commit — reaches the same arm with the same refusal code and reads the FALSE report, LOG=abandoned VERDICT=REPORTED_IN_EFFECT, with the screen naming Ctrl+Shift+G as in effect"
    requirement: "HOTKEY-08"
    verification:
      - kind: e2e
        ref: "DISPLAY=:99 ./tool/uat/worker_gone_probe.sh --at 4247446 --label pre-fix  →  RESULT rebind-worker-gone REV=4247446 REFUSAL_CODE=workerGone LOG=abandoned VERDICT=REPORTED_IN_EFFECT"
        status: pass
      - kind: other
        ref: "git log --oneline -- lib/src/infrastructure/hotkey/x11_global_hotkey.dart | head -1  →  b421a9c; git rev-parse b421a9c^  →  4247446"
        status: pass
    human_judgment: false
  - id: D3
    description: "The settings screen as rendered after a real worker death mid-rebind, committed as an image and transcribed verbatim in the record — the noBackend cause line, the registrar's own sentence, the tray named exactly once, and no 'In effect:' line at all"
    requirement: "HOTKEY-01"
    verification:
      - kind: automated_ui
        ref: "test/platform/evidence/worker-gone-rebind-sentence-pair.png (captured by the 49c5f9f run; compare -metric AE against the 23ad817 run's capture  →  0 differing pixels)"
        status: pass
    human_judgment: true
    rationale: "The plan's <human-check> and the whole point of the artefact: a human reads the two sentences off the image and confirms the transcription in test/platform/worker-gone-observation.md matches word for word, that the previous combination is NOT presented as in effect, and that the tray is named exactly once (AD-12). The executor read the PNG and confirms all four clauses; a classifier cannot, and the mode for this phase harvests <human-check> at end of phase."
  - id: D4
    description: "The developer's source trees are provably untouched by all four runs, and no worktree under the probe's own temp root survives"
    verification:
      - kind: other
        ref: "git status --porcelain -uno -- lib/ test/ tool/  →  empty after every run; git worktree list --porcelain | grep worker-gone-probe  →  empty; ls -d /tmp/worker-gone-probe.*  →  no matches; pgrep -f 'bundle/hotkey_grammar_correcto[r]'  →  empty"
        status: pass
    human_judgment: false
  - id: D5
    description: "Adding a shell script, a markdown file and a PNG moved neither suite: the three gate commands are byte-for-byte the result they were after 01-16"
    verification:
      - kind: other
        ref: "dart analyze --fatal-infos  →  'No issues found!'"
        status: pass
      - kind: integration
        ref: "dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart  →  +981 ~2, All tests passed"
        status: pass
      - kind: integration
        ref: "flutter test test/ui test/platform test/composition  →  +165 ~7, All tests passed"
        status: pass
      - kind: other
        ref: "git status --porcelain -- test/architecture/runtime_checklists_test.dart  →  empty (this plan does not edit that file)"
        status: pass
    human_judgment: false
  - id: D6
    description: "One of four runs halted at the warm-up step and its cause is undiagnosed — reported rather than dropped, and filed as WINDOWS entry 33"
    verification: []
    human_judgment: true
    rationale: "A loose end in a new tool, not a shipped deliverable. A halt is not a verdict and no reading was taken from it, but a reviewer should decide whether an undiagnosed 1-in-4 warm-up halt is acceptable in a probe that will be re-run by later phases. The evidence that would settle it is now preserved (commit 49c5f9f), so the next occurrence is diagnosable."

# Metrics
duration: 31 min
completed: 2026-09-11
status: complete
---

# Phase 01 Plan 17: Kill the Worker for Real and Read the Screen Summary

**A live probe that builds a real release bundle from a throwaway git worktree, kills the X11 key-grab worker isolate mid-rebind for real, and reads the settings screen on both sides of 01-16's fix: `LOG=abandoned VERDICT=REPORTED_IN_EFFECT` at `4247446`, `LOG=refused VERDICT=REPORTED_UNAVAILABLE` at HEAD, with the one contrived link quoted as a diff.**

## Performance

- **Duration:** 31 min
- **Started:** 2026-09-11T13:07:00Z (dispatch, immediately after 01-16's final commit at 13:06:11Z)
- **Completed:** 2026-09-11T13:38:00Z
- **Tasks:** 2
- **Files created:** 3 (one shell script, one markdown record, one PNG)
- **Live probe runs:** 4 (three verdicts, one halt), each building its own release bundle

## Accomplishments

- **Closed the evidence-tier requirement 01-VERIFICATION.md `gaps[0]` set.** That gap is explicit that its finding was *"code inspection plus a zero-coverage finding, NOT an observed runtime failure — nobody killed the worker mid-grab and watched the screen"*, and that *"the closure plan should include the observation, not just the patch"*. The worker has now been killed mid-grab and the screen has been watched, at two revisions.
- **Reproduced the defect live against a build that provably predates the fix.** `4247446` is the parent of 01-16's `lib/` commit `b421a9c`, resolved from `git log` rather than guessed, and the probe there reads `REFUSAL_CODE=workerGone LOG=abandoned VERDICT=REPORTED_IN_EFFECT` with the screen rendering **"In effect: Ctrl+Shift+G"** for a grab whose worker is dead.
- **Observed the fix live, twice, from clean starts.** `23ad817` and `49c5f9f` (byte-identical `lib/`) both read `LOG=refused VERDICT=REPORTED_UNAVAILABLE`, and their screen captures are byte-identical to each other — `compare -metric AE` reports **0** differing pixels.
- **Drove the whole chain with no fake anywhere on it:** the GTK embedder, the real settings widget, `SettingsController`, `X11GlobalHotkey`'s catch arm, `X11KeyGrabRegistrar`, a real worker isolate, `libX11.so.6`, a real X server, and back out to a rendered sentence.
- **Named the one contrivance everywhere it could be read** — in the `INJECTED=yes` field of the result line, as a printed `git diff` under every result line, in the record's section 2, and here — together with the genuine finding it rests on: the `workerGone` arm is **reachable in production and unreachable from outside the process**.
- **Left the developer's tree provably untouched.** Four runs, each applying a source-level fault injection, and `git status --porcelain -uno -- lib/ test/ tool/` printed nothing before and after every one of them.
- **Turned up a directly observed instance of the stranded passive grab**, which until now was argued from the source: the post-fix daemon's own shutdown log carries `"disposing the hotkey adapter did not finish within 5000 ms; it was abandoned…"` and `"releasing the global hotkey grab did not finish within 5000 ms; it was abandoned…"`. The daemon cannot release what the dead isolate holds.

## Task Commits

1. **Task 1 (tracer): the probe** — `d98293a` (test)
2. **Task 1 follow-up: the probe's own two defects, found by running it** — `49c5f9f` (fix)
3. **Task 2: the before/after pair, the screenshot and the record** — `4045366` (docs)

**Plan metadata:** see the `docs(01-17)` commit that carries this file.

## The before/after pair, verbatim

```
RESULT rebind-worker-gone REV=4247446 INJECTED=yes BOUND=Ctrl+Shift+G REQUESTED=Ctrl+Shift+F9 REFUSAL_CODE=workerGone LOG=abandoned SCREEN=/tmp/worker-gone-probe-out/pre-fix-4247446-20260911062323/settings-after-rebind.png VERDICT=REPORTED_IN_EFFECT
  {"timestamp":1789133029653,"level":"error","message":"the X11 key grab was refused, so the rebind was abandoned and the previous combination is still in effect","context":{"error_type":"HotkeyRegistrarRefusal","refusal_code":"workerGone"}}
```

```
RESULT rebind-worker-gone REV=49c5f9f INJECTED=yes BOUND=Ctrl+Shift+G REQUESTED=Ctrl+Shift+F9 REFUSAL_CODE=workerGone LOG=refused SCREEN=/tmp/worker-gone-probe-out/post-fix-2-49c5f9f-20260911062625/settings-after-rebind.png VERDICT=REPORTED_UNAVAILABLE
  {"timestamp":1789133211177,"level":"error","message":"the X11 key grab was refused","context":{"error_type":"HotkeyRegistrarRefusal","refusal_code":"workerGone"}}
  {"timestamp":1789133211177,"level":"warning","message":"global hotkeys are unavailable on this backend","context":{"outcome":"HotkeyUnavailable"}}
```

The first post-fix run (`REV=23ad817`, `SCREEN=/tmp/worker-gone-probe-out/post-fix-23ad817-20260911062051/…`) is identical to the second on every other field.

`REFUSAL_CODE=workerGone` on **both** sides is what makes this a proof by difference: the same injected code reaches the same arm at both revisions, and only the answer changes.

## The injection, quoted

One hunk, one file, asserted by the probe and printed under every result line:

```diff
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
```

**What the injection changes is WHY the worker died, not WHAT the code did about it** — UAT test 1's register for the client-starvation technique, applied here. Everything after the isolate's death is the shipped chain: `Isolate.spawn`'s `onError`/`onExit` port, `_onWorkerMessage`'s default arm, `_failPending`, `_refusalFor`'s `workerGone` mapping, the real refusal crossing the real seam, `X11GlobalHotkey`'s catch arm, `_causeOf`, `_recordStatus`, `SettingsController`, `HotkeyStatusView`, GTK and a real X server.

The injection is necessary rather than convenient, and the reason is itself a finding: `_X11Worker.handle` carries no `on Object` guard and `Isolate.spawn` defaults to `errorsAreFatal: true`, so a throw on the grab path really is fatal — but every throw the worker can take today is already guarded into a modelled refusal (`_openBindings` catches the whole `_X11Bindings` construction; `_openDisplay` reads a null pointer as a value). **The arm is reachable in production and unreachable from outside the process.**

## The two rendered screen lines, transcribed

From `test/platform/evidence/worker-gone-rebind-sentence-pair.png` (post-fix run at `49c5f9f`):

```
"This desktop provides no global shortcuts, so no combination can be registered here."
"the X11 hotkey worker stopped before answering, so no global shortcut is registered — the tray menu still opens the panel"
"Whether this app or your desktop would own the shortcut is not known until one is registered."
```

The second line is the **registrar's own** sentence (`x11_key_grab_registrar.dart:281-284`) carried through verbatim. **The tray is named exactly once across the pair** (AD-12) — only in the second line, because `_causeLine`'s three sentences deliberately never mention it. The field label has changed from "Shortcut" to "Shortcut to request" (null authority — nothing is claimed about who would own it), and **no "In effect:" line appears at all**.

The pre-fix screen, for contrast, says three things at once: *"In effect: Ctrl+Shift+G"*, *"That differs from your preference, Ctrl+Shift+F9."*, and — in the capture field's standing hint — *"Your current shortcut, Ctrl+Shift+F9, cannot be pressed into this box: while it is registered it goes to this app instead of to this window"*. Neither combination is registered.

## What this observation does NOT settle

Restated here so it is not left only in the record. Each item is named with the phase or gate that owns it, and **this run closes none of them**:

1. **The stranded passive grab** — killing the isolate does not close the X socket it opened, so the server keeps the grab and keeps swallowing the combination for every other application until the process exits. Now *observed* (two 5000 ms abandonment lines on the shutdown path) rather than argued, and still not released. **Phase 5 (CR-01 / WR-01 / CR-03 / WR-02)**; plan 01-20 files it as T-01-76's accepted residual.
2. **The `noBackend` cause line overstates for a dead worker** — the desktop does provide global shortcuts; this daemon's worker died. That text is `hotkey_status_view`'s and belongs to **WR-06 / SETTINGS-09 (FLAT-16), Phase 2**. Deliberately not edited here.
3. **The Wayland arm** is untouched and unobservable in this container (no portal binary, no `.service` file, no backend, no session bus). **Both `behavior_unverified_items`** in 01-VERIFICATION.md stand unchanged.
4. **The seven UAT rows recorded `result: skipped`** on 2026-09-11 by human decision — tests 2 (Wayland `revoked` half), 4, 5, 6, 7, 11 and 12 — each still owed for the reason recorded against it.
5. **One window manager only** (`openbox 3.6.1` on `Xvfb`; GNOME/Mutter and KDE/KWin unmeasured) and **every press synthetic** (`xdotool key`, i.e. `XTestFakeKeyEvent`, not a physical key). The same two limits §6 of the panel-toggle record already states.

## Decisions Made

- **The pre-fix revision was resolved, not guessed.** `git log --oneline -- lib/src/infrastructure/hotkey/x11_global_hotkey.dart` names `b421a9c`; its parent is `4247446`. No `HEAD~n` arithmetic, which a later commit would invalidate.
- **`VERDICT` is classified from the daemon log alone.** The screen is recorded, not classified: an OCR verdict would be a second oracle with a second failure mode, and this container has no OCR anyway.
- **GUI steps are confirmed by the pixels they change.** With no OCR and no accessibility bridge available, a click that changes nothing on the window is a click that did not land, and each step halts naming the step, the click position and the change it failed to produce. The end of the chain is confirmed independently by the daemon's own log line for the Apply, so a missed Apply cannot pass as a verdict.
- **The probe asserts the config rather than seeding it** (WINDOWS 34, below).
- **`test/architecture/runtime_checklists_test.dart` is not edited.** All three reasons the plan gives were checked against the tree and all three hold: `_procedures` holds step-numbered manual procedures with `*Settles:* DW-nn` bullets and a closing print that says *"both are manual: read them, do not run them"*; `panel-toggle-observation.md` is the same kind of artefact and is deliberately not registered; and the structural assertions (`_stepsIn`, `_requiredBullets`, the both-directions `claims` check) would fail on an observation record, with no skipped row pointing at it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The probe destroyed its own halt evidence**
- **Found during:** Task 2 (the second post-fix run halted at the warm-up)
- **Issue:** the daemon log was written under the `mktemp` temp root that the exit trap removes, so the one artefact a reader needs to act on a halt went with it. The same applied to the injection diff.
- **Fix:** both are now written into the run's output directory, which survives.
- **Files modified:** `tool/uat/worker_gone_probe.sh`
- **Verification:** the next post-fix run's output directory carries `daemon.log` and `injection.diff`; the shutdown-timeout finding in section 5 above comes directly from that log.
- **Committed in:** `49c5f9f`

**2. [Rule 1 - Bug] The exit assertion misreported a preflight refusal as the probe's own leak**
- **Found during:** Task 2 (a run refused because the probe's own source was being edited)
- **Issue:** `assert_no_trace` ran on the preflight-halt path too, so a run correctly refused *because* the source trees were dirty then printed `!!! PROBE LEFT A TRACE` naming the developer's work in progress — the exact confusion the assertion exists to prevent.
- **Fix:** the tracked-file half of the assertion now runs only once the preflight gate has proved the trees were clean to begin with.
- **Files modified:** `tool/uat/worker_gone_probe.sh`
- **Verification:** re-run; the preflight refusal now prints only its own named reason.
- **Committed in:** `49c5f9f`

### Substituted, not auto-fixed

**3. Task 1 step 5: "seed the config" → assert the config**
The probe lets the daemon write its own shipped defaults into the throwaway XDG tree and then **asserts** that `hotkeyBinding` reads `Ctrl+Shift+G`, halting by name if it does not. Two of the shipped provider settings (the interpreter and sidecar paths) are derived from the running host at startup, so a hand-built config would either duplicate that derivation or change what the daemon does at startup — and an invalid one would silently fall back to those same defaults, making the seed a no-op that looked like a control. The property the step exists to establish (the run starts from a genuinely held `Ctrl+Shift+G`) is measured twice instead: once from the written config and once by the warm-up press actually mapping the panel. Filed as `.planning/WINDOWS.md` entry **34**.

---

**Total deviations:** 2 auto-fixed (2 bugs, both in this plan's own new tool) + 1 substitution reported rather than engineered away.
**Impact on plan:** none on scope. No production code was touched by this plan at all (`git diff --numstat d98293a^..HEAD -- lib/` is empty); both auto-fixes are in the probe, and the second of them produced the shutdown-timeout observation the record now carries.

## Issues Encountered

- **One run in four halted at the warm-up step and its cause is undiagnosed.** *"Ctrl+Shift+G did not map the panel within 10 s (Map State is still IsUnMapped) — the daemon does not own the grab, so nothing this run observed could be trusted."* A halt is not a verdict; no reading was taken from it, and it is not in the pair. It did not reproduce in the run before it nor in the two after it. Its evidence was destroyed with the temp root (deviation 1 above), so the two candidate causes both remain open: the startup `XGrabKey` was refused, or the press was delivered and the panel did not map. The next occurrence is diagnosable because the log now survives. Filed as `.planning/WINDOWS.md` entry **33**.
- **A cold `flutter build linux --release` per run is the probe's dominant cost** — roughly two to four minutes each, four times. That is inherent to building at a caller-named revision from a fresh worktree and is printed as a progress line so a reader does not mistake it for a hang.

## Known Stubs

None. Nothing in this plan renders placeholder data, and no component was left unwired. The probe has no tolerance path, no retry and no smoothing: every field of the result line is measured, and everything it cannot establish is a halt with a named reason.

## Threat Flags

None new. The plan's own register (T-01-80 … T-01-85) is unchanged by execution, and each mitigation was exercised rather than assumed:

- **T-01-80** (the injection reaching the developer's tree) — the preflight gate refused a run for real when the tree was dirty, and `git status --porcelain -uno -- lib/ test/ tool/` was empty after every run.
- **T-01-81** (a real daemon run overwriting the developer's config or history) — every run used a per-run `mktemp` XDG tree; the real `XDG_CONFIG_HOME` was never touched.
- **T-01-82** (leaked daemon or worktree) — `pgrep` empty and `git worktree list` free of any `worker-gone-probe.` path after every run, halts included.
- **T-01-83** (the committed screenshot) — accepted as planned: the settings screen of a daemon started in a throwaway tree. No clipboard content, editor text or suggestion body is on it; **no correction is ever submitted by the probe, so AD-19's Python sidecar is never spawned**.
- **T-01-85** (a stale bundle) — each run asserts its AOT snapshot is newer than the worktree that produced it, and the launcher's own mtime is explicitly not used as the signal.

No new network endpoint, auth path, file access pattern or schema change. No package-manager install.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **G-01-15 is closed on the evidence tier the verification demanded**: the defect and the fix are both observed live, at two named revisions, with the contrivance quoted rather than described.
- **HOTKEY-01 and HOTKEY-08** are declared by 01-15, 01-16 and this plan; this is the last of the three, so the shared-ID gate should release them here.
- **Owed to plan 01-20 (ledger), not filed here:** T-01-76's stranded passive grab — now with a directly observed symptom (two 5000 ms shutdown abandonments) it can cite — and T-01-78's `noBackend` cause-line overstatement for Phase 2 / WR-06.
- **Owed to a reviewer:** `.planning/WINDOWS.md` entries **33** (the undiagnosed halt) and **34** (the config substitution), plus 01-16's still-open entry **32**, which this plan deliberately did not touch.
- **The probe is re-runnable by later phases** at any revision: `DISPLAY=:99 ./tool/uat/worker_gone_probe.sh --at <sha> --label <name>`. Phase 5's worker-lifecycle work has a ready-made oracle for the arm it is about to change.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-11*

## Self-Check: PASSED

- `tool/uat/worker_gone_probe.sh` — FOUND on disk
- `test/platform/worker-gone-observation.md` — FOUND on disk
- `test/platform/evidence/worker-gone-rebind-sentence-pair.png` — FOUND on disk
- `.planning/phases/01-hotkey-truth/01-17-SUMMARY.md` — FOUND on disk
- Commit `d98293a` (Task 1) — FOUND in `git log --oneline --all`
- Commit `49c5f9f` (Task 1 follow-up) — FOUND in `git log --oneline --all`
- Commit `4045366` (Task 2) — FOUND in `git log --oneline --all`
- Commit `97a8924` (plan metadata) — FOUND in `git log --oneline --all`
- `.planning/WINDOWS.md` entries **33** and **34** filed `open`; entry **32** (01-16's) left untouched
