---
phase: 01-hotkey-truth
plan: 11
subsystem: testing
tags: [uat, x11, xev, panel-visibility, cap-14, oracle, g-01-13, bash]

# Dependency graph
requires:
  - phase: 01-hotkey-truth
    provides: "the G-01-13 diagnosis (01-UAT.md test 13, .planning/debug/hotkey-never-hides-panel.md) — the measured event stream this oracle is built to classify"
  - phase: 01-hotkey-truth
    provides: "the ffi X11 registrar from plan 01-02, without which the daemon does not own the grab and no route observes anything"
provides:
  - "tool/uat/panel_toggle_probe.sh — a route runner that classifies one stimulus at the daemon's real toplevel from a timestamped xev structure/focus stream, by counts and order, never from xwininfo Map State"
  - "A recorded fail-first run: the oracle classifies the unfixed 2026-09-04 bundle's press-at-a-visible-panel as VERDICT=FLICKER"
  - "A six-route pre-fix baseline with the post-fix value expected of each, so plan 01-12's run is a comparison rather than an assertion"
  - "Per-route FOCUS_BEFORE/FOCUS_AFTER measurements, and the measured correction to the focus-ownership expectation plan 01-12's discriminator rested on"
  - "The WINDOW result-line field, emitted from the start by every route, which plan 01-13's two slice-classified routes depend on"
affects: [01-12, 01-13, 01-14, phase-01-verification, cap-14, cap-1]

# Actuals (#2632) — same estimateTokens scale (chars/4 over the realized diff).
actuals:
  tokens: 4800
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Event-stream oracle: classify a display-server transition from counts and order inside a fixed settle window, not from a post-hoc state sample"
    - "Per-run mktemp XDG tree for a live daemon under test, torn down by an exit trap"
    - "Halt-with-a-named-reason as a distinct outcome from every route verdict"

key-files:
  created:
    - tool/uat/panel_toggle_probe.sh
  modified: []

key-decisions:
  - "The warm-up press IS a measurement, and routes that want the from-hidden press report that press rather than pressing twice"
  - "The toplevel filter needs _NET_WM_WINDOW_TYPE_NORMAL on top of the plan's _NET_WM_PID + Map State test, because the app class also matches GTK's 10x10 hidden group-leader window"
  - "The daemon pid is resolved by the executable each candidate process is running, not by the bracketed pattern, which also matches dbus-run-session's own command line"
  - "Toplevel resolution retries until it converges on the live daemon's pid, because a reaped daemon keeps its windows until X tears the connection down"
  - "The acceptance criterion about which routes move the focus was reported as failing rather than smoothed away — the harness reports what happened"

patterns-established:
  - "Result line: ROUTE <name> UNMAP=<n> MAP=<n> FIRST=<Unmap|Map|none> FOCUS_BEFORE=<id> FOCUS_AFTER=<id> WINDOW=<w> VERDICT=<v>, one space between fields, order fixed — 01-13's gates match on adjacent field pairs"
  - "A route that halts emits VERDICT=HALTED and the run continues, so one broken route cannot hide five good results"
  - "Empty xev output is a halt, never the NOTHING verdict — a silent daemon and a healthy no-op are different facts"

requirements-completed: []

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "The oracle exists and catches G-01-13: one press at a visible panel against the unfixed bundle classifies as FLICKER from the event stream"
    verification:
      - kind: integration
        ref: "DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh hide | grep -E '^ROUTE hide .*WINDOW=all .*VERDICT=FLICKER$'"
        status: pass
    human_judgment: false
  - id: D2
    description: "All six routes run under `all` against freshly started daemons, emitting nine ROUTE lines that every carry WINDOW=all, plus a SUMMARY block"
    verification:
      - kind: integration
        ref: "DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh all | grep -cE '^ROUTE [a-z0-9-]+ .*WINDOW=all .*VERDICT=' == 9; grep -E '^SUMMARY'"
        status: pass
    human_judgment: false
  - id: D3
    description: "The pre-fix baseline is recorded and reads exactly as the plan predicted: show=SHOW hide=FLICKER alternate=SHOW,FLICKER,FLICKER,FLICKER focus-steal=HIDE desktop-click=HIDE foreign-grab=HIDE"
    verification:
      - kind: integration
        ref: "/tmp/g0113-baseline-all.txt SUMMARY block, quoted verbatim below"
        status: pass
    human_judgment: false
  - id: D4
    description: "A run leaves nothing behind: no daemon, no foreign grabber, no xmessage, no temp tree, and nothing in lib/ or test/ was touched"
    verification:
      - kind: integration
        ref: "pgrep -f 'bundle/hotkey_grammar_correcto[r]' empty; ps for foreign_grabber/xmessage empty; ls -d /tmp/hgc-p.* empty; git status --short -- lib test empty"
        status: pass
      - kind: other
        ref: "dart analyze --fatal-infos"
        status: pass
    human_judgment: false
  - id: D5
    description: "Focus ownership is measured per route so 01-12's discriminator rests on measurement — and the measurement CONTRADICTS the plan's expectation of which routes move the focus, with a consequence for how 01-12 may read focus"
    verification:
      - kind: integration
        ref: "/tmp/g0113-baseline-all.txt FOCUS_BEFORE/FOCUS_AFTER pairs on all nine ROUTE lines"
        status: pass
    human_judgment: true
    rationale: "The numbers are measured, but the design consequence is a judgment a human or the 01-12 planner must take: a post-settle focus sample is circular on the foreign-grab route (the focus is foreign only BECAUSE the dismissal happened), so a focus-owner discriminator cannot be validated against that route's post-settle pair alone. Recorded as WINDOWS.md entry 22."

# Metrics
duration: 11 min
completed: 2026-09-10
status: complete
---

# Phase 01 Plan 11: The Toggle Oracle, Proved Failing First Summary

**A committed 519-line X-event-stream harness that classifies six panel-toggle routes from `UnmapNotify`/`MapNotify` counts and order, catches G-01-13's 8-16 ms flicker the Map State oracle cannot see, and records the pre-fix baseline `hide=FLICKER` against the unfixed 2026-09-04 bundle**

## Performance

- **Duration:** 11 min
- **Started:** 2026-09-10T13:37:25Z
- **Completed:** 2026-09-10T13:48:31Z
- **Tasks:** 2
- **Files modified:** 1 created, 0 modified

## Accomplishments

- `tool/uat/panel_toggle_probe.sh` exists and is committed: a route runner that starts the real release bundle under its own `mktemp` XDG tree, resolves the daemon's real toplevel, measures one stimulus from `xev -event structure -event focus` through a line timestamper, and classifies it by counts and order inside a fixed 1000 ms settle window — 60x the measured 8-16 ms flicker.
- The oracle **fails first**, on the record. Against the build that still carries the defect it classifies a press at a visible panel as `VERDICT=FLICKER`, which is the evidence that makes every green result plan 01-12 produces falsifiable.
- Six routes baselined, and the baseline came out **exactly** as the plan predicted — including the `alternate` route reproducing the reporter's "shows once, then never hides" as `SHOW, FLICKER, FLICKER, FLICKER`.
- `foreign-grab` isolates the defect's condition 1 on its own: a second X client's grab on `Ctrl+Shift+H` delivers only `FocusOut(NotifyGrab)` to the panel, the daemon receives no activation at all, and the panel unmaps with **no** re-map (`UNMAP=1 MAP=0`). The self-inflicted dismissal is now measured independently of the toggle.
- The two CAP-14 routes that must NOT change (`focus-steal`, `desktop-click`) are baselined as `HIDE`, so 01-12's fix can be checked for suppressing a real dismissal rather than only for suppressing the spurious one.
- Three real defects in the plan's own measured `<interfaces>` facts were found and fixed rather than worked around (see Deviations).

## Task Commits

1. **Task 1: The oracle — one press at a visible panel, classified from the event stream, and shown to fail first** — `8debfaa` (test)
2. **Task 2: The five remaining routes, and the pre-fix baseline for all six** — `e5de2ce` (test)

**Plan metadata:** see the `docs(01-11)` commit that carries this SUMMARY.

## Files Created/Modified

- `tool/uat/panel_toggle_probe.sh` — the live toggle oracle. Preflight (display, six tools, bundle, no pre-existing daemon holding the grab), per-run XDG tree, toplevel resolution, per-press `xev` measurement, classification, one `ROUTE` result line per press with the timestamped stream indented under it, and an exit trap that stops the daemon and every helper.

## The pre-fix baseline, quoted verbatim

Recorded 2026-09-10 with `DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh all` against
`build/linux/x64/release/bundle/hotkey_grammar_corrector` built 2026-09-04 07:51, on
`Xvfb :99 -screen 0 1440x900x24` + `openbox 3.6.1`. Full output in `/tmp/g0113-baseline-all.txt`;
the `hide`-only run in `/tmp/g0113-baseline-hide.txt`.

```
SUMMARY show=SHOW
SUMMARY hide=FLICKER
SUMMARY alternate=SHOW,FLICKER,FLICKER,FLICKER
SUMMARY focus-steal=HIDE
SUMMARY desktop-click=HIDE
SUMMARY foreign-grab=HIDE
```

The nine result lines behind that block, verbatim:

```
ROUTE show UNMAP=0 MAP=1 FIRST=Map FOCUS_BEFORE=2097439 FOCUS_AFTER=4194308 WINDOW=all VERDICT=SHOW
ROUTE hide UNMAP=1 MAP=1 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=4194308 WINDOW=all VERDICT=FLICKER
ROUTE alternate-1 UNMAP=0 MAP=1 FIRST=Map FOCUS_BEFORE=2097439 FOCUS_AFTER=4194308 WINDOW=all VERDICT=SHOW
ROUTE alternate-2 UNMAP=1 MAP=1 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=4194308 WINDOW=all VERDICT=FLICKER
ROUTE alternate-3 UNMAP=1 MAP=1 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=4194308 WINDOW=all VERDICT=FLICKER
ROUTE alternate-4 UNMAP=1 MAP=1 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=4194308 WINDOW=all VERDICT=FLICKER
ROUTE focus-steal UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=10485792 WINDOW=all VERDICT=HIDE
ROUTE desktop-click UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=all VERDICT=HIDE
ROUTE foreign-grab UNMAP=1 MAP=0 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=2097439 WINDOW=all VERDICT=HIDE
```

The fail-first line, on its own, is the one plan 01-12 must flip:

```
ROUTE hide UNMAP=1 MAP=1 FIRST=Unmap FOCUS_BEFORE=4194308 FOCUS_AFTER=4194308 WINDOW=all VERDICT=FLICKER
```

Its stream shows the two intents 8-16 ms apart, as diagnosed: `FocusOut mode=NotifyGrab` at
`.865`, `UnmapNotify` at `.868` (+3 ms), `MapNotify` at `.879` (+14 ms). `xwininfo` reads
`IsViewable` on both sides of that.

## What 01-12 must produce, route by route

| Route | Pre-fix (measured) | Expected after the 01-12 fix | Changes in 01-12? |
|---|---|---|---|
| `show` | `SHOW` | `SHOW` | **No.** A hidden panel has no focus to lose, so no `FocusOut(NotifyGrab)` is generated and this press has always worked. A change here is a regression. |
| `hide` | `FLICKER` | `HIDE` | **Yes — this is the fix.** The self-inflicted unmap must stop, leaving the toggle's own dismissal: `UNMAP=1 MAP=0`. |
| `alternate` | `SHOW,FLICKER,FLICKER,FLICKER` | `SHOW,HIDE,SHOW,HIDE` | **Yes.** This is the reporter's symptom, and its disappearance is CAP-14's toggle actually working across repeated presses. |
| `focus-steal` | `HIDE` | `HIDE` | **No.** CAP-14's focus-loss hide on a real second toplevel is healthy at HEAD (UAT test 14) and a fix that suppresses a spurious dismissal is one edit away from suppressing this real one. |
| `desktop-click` | `HIDE` | `HIDE` | **No.** Second CAP-14 route, measured at +0.1 ms in the diagnosis. Must stay `HIDE` with `FOCUS_AFTER` naming a non-daemon window. |
| `foreign-grab` | `HIDE` | `NOTHING` | **Yes.** The daemon receives no activation on this route, so after the fix the panel must not move at all. A post-fix `NOTHING` here is the fix working, not the harness failing — the script says so in a comment above the route. |

## Decisions Made

- **The warm-up press is a measurement, not a throwaway.** The plan requires a grab-ownership check ("the first press must move the panel") for every route, and separately requires `show` and `alternate-1` to be presses at a hidden panel. Pressing twice would have made those two routes measure a press at a *visible* panel. The warm-up's own measurement is therefore stashed and replayed as the route line where the from-hidden press is what the route is about.
- **`_NET_WM_WINDOW_TYPE_NORMAL` joins the toplevel filter.** See Deviations 1.
- **The daemon pid comes from `/proc/<pid>/exe`, not from the bracketed pattern.** See Deviations 2.
- **Toplevel resolution retries; the daemon-start wait does not watch windows.** See Deviations 3.
- **The failing acceptance criterion was reported, not engineered around.** The plan prohibits "any tolerance, retry or 'if it looks like it hid, call it hidden' smoothing", and that prohibition binds the harness's own acceptance criteria too. See Deviations 4.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The plan's toplevel filter yields two survivors, so the required "exactly one" halt fired every run**

- **Found during:** Task 1
- **Issue:** The `<interfaces>` block specifies keeping ids "whose `_NET_WM_PID` equals the daemon's pid and for which `xwininfo -id` reports a `Map State` line", then requiring exactly one survivor. Measured 2026-09-10: `xdotool search --class com.divertedriver.HotkeyGrammarCorrector` returns **two** windows that both pass that filter — `4194307` (the real 1280x720 toplevel, `WM_NAME` "Hotkey Grammar Corrector") and `4194305`, GTK's 10x10 hidden group-leader window, which carries the same `_NET_WM_PID` and which `xwininfo` reports a `Map State` for. Every run halted with `found 2`.
- **Fix:** Added a third filter step: the survivor must carry `_NET_WM_WINDOW_TYPE = _NET_WM_WINDOW_TYPE_NORMAL`. Measured: `4194307` has it, `4194305` has no `_NET_WM_WINDOW_TYPE` at all. `WM_STATE` was rejected as the discriminator because neither window has it while unmapped — openbox sets it on manage, and the panel starts hidden.
- **Files modified:** `tool/uat/panel_toggle_probe.sh`
- **Verification:** `hide` resolves `TOPLEVEL window=4194307 _NET_WM_PID=<pid>` and proceeds; the `found 2` halt is gone across every subsequent run.
- **Committed in:** `8debfaa` (Task 1 commit)

**2. [Rule 1 - Bug] `pgrep -f 'bundle/hotkey_grammar_correcto[r]'` matches two processes, not one**

- **Found during:** Task 1
- **Issue:** The launch recipe is `dbus-run-session -- ./build/.../bundle/hotkey_grammar_corrector`, so the bundle path is one of `dbus-run-session`'s own arguments and its command line matches the bracketed pattern too. Resolving "the daemon's pid" through that pattern returned `found 2: 7439 7444` and halted. `_NET_WM_PID` names only the app process, so matching against the launcher's pid would also have found zero windows.
- **Fix:** A `daemon_pids()` helper filters `pgrep` matches by `readlink -f /proc/<pid>/exe`, keeping only processes actually running the bundle. The bracketed pattern is retained for `pkill` in the teardown (where killing both is correct) and for the preflight "is a daemon already running" test, exactly as the plan mandates.
- **Files modified:** `tool/uat/panel_toggle_probe.sh`
- **Verification:** `resolve_toplevel` reports one pid on every route of the `all` run; six `TOPLEVEL` lines, each with a distinct pid.
- **Committed in:** `8debfaa` (Task 1 commit)

**3. [Rule 1 - Bug] A reaped daemon keeps its X windows, so route 5 of `all` resolved zero toplevels and halted**

- **Found during:** Task 2
- **Issue:** The first full `all` run halted on `desktop-click` with `expected exactly one toplevel for pid 11200, found 0 — candidates:` (empty list). Root cause: `start_daemon` waited for `xdotool search --class` to return non-empty, and between a daemon process being reaped and X tearing its connection down, the **previous** route's windows still exist and still carry that class. The wait therefore satisfied itself on a dead daemon's window, returned immediately, and `resolve_toplevel` ran before the new daemon had created anything. The count gate still read 9 (the halted route emits one `HALTED` line), which is precisely the "a broken route must not read as healthy" hazard the plan's prohibition names — the harness reported `HALTED` honestly, but the baseline would have been incomplete.
- **Fix:** Three changes. (a) `start_daemon` now waits for the app **process** (via `daemon_pids`), never for a window. (b) `resolve_toplevel` retries the whole pid-keyed resolution for up to 30 s, converging once the live daemon's `NORMAL` toplevel appears; more than one survivor still halts immediately, and zero after 30 s halts with the candidate list and the daemon log path. (c) `stop_daemon` additionally waits (bounded) for the class's windows to disappear from the display, so a dead route's toplevel cannot enter the next route's candidate list at all.
- **Files modified:** `tool/uat/panel_toggle_probe.sh`
- **Verification:** `all` completes with `RUN_EXIT=0`, nine `ROUTE` lines, zero `HALT` lines on stderr, and six distinct `TOPLEVEL` pids.
- **Committed in:** `e5de2ce` (Task 2 commit)

**4. [Rule 3 - Blocking] `stdbuf -oL` is required in front of `xev`, or the stream is lost when `xev` is stopped**

- **Found during:** Task 1
- **Issue:** `xev` block-buffers its stdout when it is a pipe. The measurement stops `xev` with a signal after the settle window, and a signal-killed process never flushes its stdio buffer — so short streams (every route here is well under 4 KB) would arrive empty, which the harness correctly halts on but which would have made the whole oracle unusable.
- **Fix:** `stdbuf -oL xev ...` forces line buffering, and `stdbuf` was added to the preflight's required-tool list so its absence is a named halt rather than a mysterious empty stream.
- **Files modified:** `tool/uat/panel_toggle_probe.sh`
- **Verification:** every route's stream is present and indented under its `ROUTE` line, with per-line timestamps that resolve the 3 ms unmap and 14 ms remap.
- **Committed in:** `8debfaa` (Task 1 commit)

### Acceptance criterion reported as FAILING (not fixed, deliberately)

**5. [Measured contradiction] Task 2's focus-ownership criterion does not hold, and the harness was not changed to make it hold**

- **Found during:** Task 2 verification
- **Criterion as written:** "Every route's FOCUS_BEFORE/FOCUS_AFTER pair is printed, and the two that moved the focus (`focus-steal`, `desktop-click`) are the only two where the pair differs."
- **Measured:** the pair differs on **four** route names, not two:
  - `show` `2097439 -> 4194308` (differs) — the panel was hidden, so it *gained* the focus when shown
  - `alternate-1` `2097439 -> 4194308` (differs) — same press, same reason
  - `focus-steal` `4194308 -> 10485792` (differs) — as predicted
  - `desktop-click` `4194308 -> 2097439` (differs) — as predicted, and `2097439` is openbox exactly as the `<interfaces>` table records
  - `foreign-grab` `4194308 -> 2097439` (**differs** — the plan predicted "unchanged")
  - identical only on `hide` and `alternate-2..4`, where the flicker returns the panel to visible and the focus with it
- **Why the plan expected otherwise:** the `<interfaces>` focus table records the foreign-grab row as `unchanged / unchanged / no`. That row was sampled while the grab was active; this harness samples at the fixed 1000 ms settle mark, by which time the panel has genuinely unmapped and openbox holds the focus. Both measurements are correct about different instants.
- **Why nothing was changed:** the criterion describes the *daemon's* behaviour, not the harness's. Making it pass would mean sampling focus at a different instant chosen to produce the predicted answer — the smoothing the plan's action block explicitly forbids. The first half of the criterion ("every route's pair is printed") holds; the second half is a wrong prediction, corrected by measurement.
- **Consequence for 01-12 — this is the load-bearing part:** a focus-owner discriminator validated against a **post-settle** focus sample is circular on the `foreign-grab` route, because the focus there is foreign only *because* the dismissal already happened. The discriminator 01-12 builds must key on something available at the moment the blur is handled (the X focus mode, or the registrar's knowledge that its own grab is active) rather than on where the focus ends up a second later. This is also why 01-13's two added routes classify from events after a specific moment via the `WINDOW` field instead of over the whole press.
- **Recorded as:** `.planning/WINDOWS.md` entry 22 (`kind: deviation`, `status: open`).

---

**Total deviations:** 4 auto-fixed (2 bugs, 2 blocking) + 1 acceptance criterion reported as failing with its consequence documented.
**Impact on plan:** All four auto-fixes were necessary to make the plan's own stated design runnable; none changed what the oracle reports or added tolerance to it. The plan's six predicted verdicts were reproduced exactly, so the deviations touched the plumbing and not the measurement. The fifth item is a correction to a plan expectation that plan 01-12 depends on, and it makes 01-12's job more precisely specified rather than less.

## Issues Encountered

- `Xvfb :99` and `openbox` were **not** running when this plan started, contrary to the `<interfaces>` claim that both were already up (they were, on 2026-09-05; this session is a fresh container). The precondition's own instruction covered it: both were started with the documented commands before Task 1 began.
- Nothing else. The three plumbing bugs above are recorded as deviations rather than issues because each was found by the harness halting with a named reason, which is the behaviour the plan's prohibition demanded.

## User Setup Required

None — no external service configuration required. The harness uses `xev`, `xdotool`, `xwininfo`, `xprop`, `python3`, `dbus-run-session` and `stdbuf`, all already present, and adds no entry to `pubspec.yaml` or `requirements.txt`.

## Threat Flags

None. The plan's four registered threats are all addressed as dispositioned: the daemon runs under a per-run `mktemp -d` XDG tree removed by the exit trap (T-01-55); the trap stops the daemon, the `xmessage` and the ctypes grabber on every path including halts, and a clean `pgrep`/`ps` after the run is verified (T-01-56); the harness prints the toplevel id it chose, that window's `_NET_WM_PID` and the raw timestamped stream under each verdict (T-01-57); the stream carries window ids, event names and X focus modes only, no clipboard content and no editor text (T-01-58, accepted).

## Next Phase Readiness

- **Ready for 01-12.** The oracle is committed, the pre-fix baseline is recorded, and the route-by-route table above states what 01-12 must change and what it must leave alone. `01-12` should re-run `DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh all` after its fix and diff the `SUMMARY` block against the one quoted here.
- **Ready for 01-13.** The `WINDOW` field is emitted by every route from the first commit, so 01-13's two slice-classified routes can be added without changing the result-line format that this baseline was recorded against.
- **One concern carried forward:** the focus-ownership correction in Deviation 5 constrains how 01-12 may implement its discriminator. It is filed as `WINDOWS.md` entry 22 and is not a blocker, but 01-12 should read it before choosing where the discriminator reads focus from.
- **Nothing in `lib/` or `test/` was touched**, `dart analyze --fatal-infos` reports "No issues found!", and the 983-row suite is untouched by this plan.

## Self-Check: PASSED

- `tool/uat/panel_toggle_probe.sh` exists on disk and is executable — FOUND
- `git log --oneline --all | grep 8debfaa` — FOUND
- `git log --oneline --all | grep e5de2ce` — FOUND
- Task 1 acceptance re-run: `^ROUTE hide .*WINDOW=all .*VERDICT=FLICKER$` — PASS
- Task 2 acceptance re-run: nine `ROUTE ... WINDOW=all ... VERDICT=` lines and a `SUMMARY` block — PASS (9)
- Task 2 acceptance, focus-pair clause — FAIL, reported as Deviation 5 with its consequence, not silently skipped
- Plan verification 1 (`bash -n`, executable) — PASS
- Plan verification 2 (`all` completes, nine lines + `SUMMARY`) — PASS
- Plan verification 3 (`hide` and `foreign-grab` both report a dismissal) — PASS
- Plan verification 4 (no daemon, no grabber surviving) — PASS
- Plan verification 5 (`dart analyze --fatal-infos` unaffected) — PASS, "No issues found!"

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-10*
