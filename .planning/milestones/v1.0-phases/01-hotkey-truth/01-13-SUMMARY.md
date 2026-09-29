---
phase: 01-hotkey-truth
plan: 13
subsystem: testing
tags: [x11, xev, uat, panel-visibility, cap-14, cap-1, g-01-13, g-01-14, ad-18, openbox, xvfb]

# Dependency graph
requires:
  - phase: 01-11
    provides: "tool/uat/panel_toggle_probe.sh, its six routes, and the recorded pre-fix baseline this run is compared against"
  - phase: 01-12
    provides: "the KeyboardFocusWitness fix under measurement, and its own post-fix six-route run"
provides:
  - "steal-after-presses — UAT test 14's third focus route, with an event-confirmed PRESTEAL=mapped invariant"
  - "press-then-click ×3 — UAT test 14's fourth route, with the panel re-established between press and click"
  - "a windowed measurement path beside do_measure: one xev per route, sliced by the timestamper's epoch"
  - "test/platform/panel-toggle-observation.md — the committed observation record for G-01-13 and the G-01-14 re-test"
  - "the AD-18 clipboard-sentinel consequence, confirmed by hand with two screenshots"
  - "G-01-13 proved fixed by a difference against a recorded baseline, twice, on eight routes"
affects: [01-14, wayland-portal, arch-06, panel-geometry]

actuals:
  tokens: 7466      # chars/4 over the realized diff (29,864 chars across the two source files)
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A route that classifies a SLICE of one continuous event stream, scoped by the timestamper's epoch, rather than a fresh stream per stimulus"
    - "A pre-stimulus invariant asserted and PRINTED on the result line (PRESTEAL=mapped), so a reader can see it rather than assume it"
    - "A regression guard recorded as the absence of a symptom, explicitly not as evidence, when the mechanism it targets has never reproduced"
    - "Artifact provenance stated by the symbols inside the built snapshot, not by its mtime"

key-files:
  created:
    - test/platform/panel-toggle-observation.md
    - test/platform/evidence/panel-toggle-ad18-first-summon.png
    - test/platform/evidence/panel-toggle-ad18-second-summon.png
  modified:
    - tool/uat/panel_toggle_probe.sh

key-decisions:
  - "steal-after-presses asserts a mapped panel immediately before the steal and prints PRESTEAL=mapped, because post-fix the presses toggle and press parity — not the route — would otherwise decide whether there was a panel to dismiss"
  - "press-then-click re-establishes a mapped panel BETWEEN the press and the click and classifies only from WINDOW=post-click, because the press's own toggle would otherwise supply the unmap and the route would report HIDE while never testing the click"
  - "The two new routes are recorded as regression guards, never as evidence: no pre-fix baseline, and per UAT test 14's own HEAD evidence both would have read HIDE on the broken build too"
  - "foreign-grab's NOTHING is recorded as the pass AND as a deliberate behaviour change, in both registers, rather than one absorbing the other"
  - "Bundle freshness is established by three facts (no-op rebuild, libapp.so postdating the last lib/ commit with a clean tree, and X11KeyboardFocusWitness/_keyboardStillHere present in the AOT snapshot) because the launcher executable's mtime is a false signal — it holds no Dart code"
  - "The observation record is deliberately NOT registered in runtime_checklists_test.dart's _procedures: that list pins procedures owed to a real desktop, and this is the opposite kind of document"

patterns-established:
  - "One xev per route plus timestamp slicing, so a multi-step route can reach a state and then measure only its final stimulus"
  - "WINDOW= is preceded by an optional field slot, so a route with an invariant can make it an adjacent ordered pair on the result line without breaking the single-space field contract"

requirements-completed: []

coverage:
  - id: D1
    description: "G-01-13 is fixed, proved by a difference against 01-11's recorded baseline: hide FLICKER -> HIDE and alternate SHOW,FLICKER,FLICKER,FLICKER -> SHOW,HIDE,SHOW,HIDE"
    verification:
      - kind: e2e
        ref: "DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh all -> SUMMARY hide=HIDE, SUMMARY alternate=SHOW,HIDE,SHOW,HIDE (two consecutive clean runs, identical)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The two CAP-14 routes that were healthy before the fix are still healthy after it: a second toplevel taking focus and a desktop click both still dismiss"
    verification:
      - kind: e2e
        ref: "DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh all -> SUMMARY focus-steal=HIDE, SUMMARY desktop-click=HIDE (unchanged from the 01-11 baseline)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The deliberate behaviour change is measured and named as a change: a foreign client's global shortcut no longer dismisses the panel (foreign-grab HIDE -> NOTHING, focus unmoved on both sides)"
    verification:
      - kind: e2e
        ref: "DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh all -> ROUTE foreign-grab UNMAP=0 MAP=0 FOCUS_BEFORE=4194308 FOCUS_AFTER=4194308 VERDICT=NOTHING"
        status: pass
    human_judgment: false
  - id: D4
    description: "UAT test 14's gestures are re-run against the fixed build as a regression guard over 01-12's change to the recorded keyboard state, and a genuine focus loss still dismisses in each of them"
    verification:
      - kind: e2e
        ref: "DISPLAY=:99 ./tool/uat/panel_toggle_probe.sh all -> ROUTE steal-after-presses PRESTEAL=mapped WINDOW=post-steal VERDICT=HIDE; ROUTE press-then-click-1..3 WINDOW=post-click VERDICT=HIDE"
        status: pass
    human_judgment: false
  - id: D5
    description: "The run is committed as an observation record in the register the existing platform documents use, with what was measured separated from what was argued"
    verification:
      - kind: other
        ref: "test/platform/panel-toggle-observation.md exists; grep gates for panel_toggle_probe, foreign-grab and AD-18 pass; dart test --exclude-tags=live test/architecture is green (228 passed, 1 skipped)"
        status: pass
    human_judgment: true
    rationale: "Whether the six sections actually hold the honesty register — unobserved stated as unobserved, a regression guard not inflated into evidence, NOTHING named as the pass — is a reading of prose. grep can prove the strings are present and cannot prove the register is right."
  - id: D6
    description: "The AD-18 consequence is confirmed: a press at a visible panel now records a dismissal, so the next summon starts a fresh session and re-seeds the editor from the clipboard"
    verification:
      - kind: manual_procedural
        ref: "test/platform/evidence/panel-toggle-ad18-first-summon.png (editor reads ZZALPHA111) and panel-toggle-ad18-second-summon.png (editor reads QQBETA222 after a hide and a re-summon)"
        status: pass
    human_judgment: true
    rationale: "The evidence is text read off a screenshot. Plan 01-13 names this a human-check for exactly that reason, and workflow.human_verify_mode is end-of-phase."

# Metrics
duration: 35 min
completed: 2026-09-10
status: complete
---

# Phase 01 Plan 13: Prove G-01-13 Live Summary

**Eight routes, thirteen result lines, run twice on the fixed release bundle: `hide` FLICKER→HIDE, `alternate` SHOW,FLICKER,FLICKER,FLICKER→SHOW,HIDE,SHOW,HIDE, `foreign-grab` HIDE→NOTHING, and `show`/`focus-steal`/`desktop-click` exactly where they were — plus UAT test 14's two remaining gestures added as regression guards and the AD-18 clipboard sentinel re-seeding by hand.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-09-10T14:17:00Z (approximate — the first tool call, not a recorded mark)
- **Completed:** 2026-09-10T14:52:00Z
- **Tasks:** 2
- **Files modified:** 4 (1 modified, 3 created)

## Accomplishments

- **G-01-13 is proved fixed by a difference, not asserted by a pass.** Every one of 01-11's six baselined routes was re-run against the fixed bundle and compared against its recorded pre-fix verdict. The three that had to change did; the three that had to stay put did.
- **Two routes added for UAT test 14's `retest_after_fix`,** each built to defeat a trap in its own naive form — and each recorded as a regression guard rather than as evidence, because neither can discriminate the fix.
- **The deliberate behaviour change is named as a change.** `foreign-grab` reads `NOTHING`, with `FOCUS_BEFORE=FOCUS_AFTER=4194308`, and the record says in its own words that `NOTHING` is the pass here so a reader skimming for `HIDE` cannot mis-read it.
- **The AD-18 consequence is confirmed from the other side.** The summon after a hide now clears the panel and re-reads the clipboard: `ZZALPHA111` → `QQBETA222`, two screenshots committed. That is the reporter's original "clipboard sentinel not re-seeded" observation resolving, on an oracle that touches `xev` not at all.
- **Bundle provenance established by symbols, not mtime** — the one claim in a run like this that cannot be taken on trust (T-01-65).

## Task Commits

1. **Task 1: the two G-01-14 routes and the recorded run** — `4a6cb5e` (test)
2. **Task 2: the observation record and the AD-18 check** — `4a0e25c` (docs)

**Plan metadata:** see the `docs(01-13)` commit following this file.

## The measured result

Pre-fix values quoted from 01-11's recorded baseline, never re-derived:

| Route | Pre-fix (01-11) | Post-fix (this run) | Changed? |
| --- | --- | --- | --- |
| `show` | `SHOW` | `SHOW` | no |
| `hide` | **`FLICKER`** | **`HIDE`** | **yes** |
| `alternate` | **`SHOW,FLICKER,FLICKER,FLICKER`** | **`SHOW,HIDE,SHOW,HIDE`** | **yes** |
| `focus-steal` | `HIDE` | `HIDE` | no |
| `desktop-click` | `HIDE` | `HIDE` | no |
| `steal-after-presses` | *(no baseline — added here)* | `HIDE` | n/a |
| `press-then-click` ×3 | *(no baseline — added here)* | `HIDE,HIDE,HIDE` | n/a |
| `foreign-grab` | `HIDE` | **`NOTHING`** | **yes, deliberately** |

The two `SUMMARY` blocks side by side, as the plan's `<output>` asks:

```
# 01-11, PRE-FIX baseline            # 01-13, POST-FIX, both runs identical
SUMMARY show=SHOW                    SUMMARY show=SHOW
SUMMARY hide=FLICKER                 SUMMARY hide=HIDE
SUMMARY alternate=SHOW,FLICKER,      SUMMARY alternate=SHOW,HIDE,SHOW,HIDE
        FLICKER,FLICKER
SUMMARY focus-steal=HIDE             SUMMARY focus-steal=HIDE
SUMMARY desktop-click=HIDE           SUMMARY desktop-click=HIDE
                                     SUMMARY steal-after-presses=HIDE
                                     SUMMARY press-then-click=HIDE,HIDE,HIDE
SUMMARY foreign-grab=HIDE            SUMMARY foreign-grab=NOTHING
```

Thirteen `ROUTE` lines over eight routes on each run, no `FLICKER`, no
`UNCLASSIFIED`, no `HALTED`, and no classified window containing a `MapNotify`
where it contains an `UnmapNotify`. Two consecutive clean runs agreed on every
verdict; only window ids in the focus columns differ (a fresh `xmessage` per
run), and no verdict does.

## What the two new routes can and cannot carry

Stated here as well as in the record, because this is the claim most likely to be
overstated by a later reader:

- The `NotifyUngrab`/`_focused` mechanism UAT test 14's `retest_after_fix` names
  **has never reproduced in this container**. It was inferred from presses 1 and 3
  differing from 2 and 4, never observed.
- `steal-after-presses` and `press-then-click` have **no pre-fix baseline** — 01-11
  did not carry them.
- Per UAT test 14's **own HEAD evidence** the blur path was healthy on the broken
  build and all four of its routes dismissed, so a `HIDE` from these two
  **discriminates nothing**.
- They are therefore **regression guards over 01-12's move of the `_focused`
  clear**, not evidence that the mechanism was exercised. Worth having at that
  value and no more.

**A finding falls out of it.** The state test 14 worried about — a suppressed
focus-out at a still-mapped panel — is no longer reachable by that gesture at all,
because the press now hides the panel. `foreign-grab` is the only route that still
produces it, so composing `foreign-grab` with a click is the probe that would
exercise the mechanism if it ever reproduces. Filed as `WINDOWS.md` 28
(`unmet-truth`); the route was deliberately not added here.

## The AD-18 human-check result

**Pass.** With the panel hidden and `ZZALPHA111` on the clipboard, the summon
showed an editor reading `ZZALPHA111`. With `QQBETA222` then on the clipboard, a
press hid the panel (`Map State: IsUnMapped`) and the next press showed an editor
reading **`QQBETA222`**. Before the fix the second summon kept `ZZALPHA111`,
because the departure recorded was `focusLost` and
`correction_controller.dart:401` leaves `_dismissalStands` untouched for it
(verified in source: `PanelVisibilityState.focusLost => _dismissalStands`).

Screenshots: `test/platform/evidence/panel-toggle-ad18-first-summon.png` and
`panel-toggle-ad18-second-summon.png`. Sentinels only — no real user text ever
reached the clipboard or an artifact (T-01-67).

## Files Created/Modified

- `tool/uat/panel_toggle_probe.sh` — two routes, a windowed measurement path
  (`xev_start`/`slice_*`/`await_transition`/`press_for`/`ensure_mapped`/
  `measure_after`), an optional result-line field slot before `WINDOW=`, and
  `xev_stop` wired into both teardown paths.
- `test/platform/panel-toggle-observation.md` — the observation record: six
  sections, environment, provenance, both runs, the G-01-14 limits, the AD-18
  result, and what is not settled here.
- `test/platform/evidence/panel-toggle-ad18-{first,second}-summon.png` — the two
  AD-18 screenshots.

## Decisions Made

- **The new routes do not use `do_measure` or `warm_up`.** Both attach and then
  `pkill` an `xev` on the toplevel, which would tear down the long-lived stream a
  windowed route needs. Grab ownership is still established the way `warm_up`
  establishes it: each route's first press is *required* to map the panel and the
  route halts by name if it does not.
- **The classification slice is taken from the same mechanism, scoped.** The
  timestamper 01-11 put in front of `xev` is what makes the slice available; no
  second measurement mechanism was added.
- **`WINDOW=` gained a preceding optional field slot** rather than a new column
  order, so `PRESTEAL=mapped WINDOW=post-steal` is an adjacent ordered pair and
  every existing route's line is byte-identical to before.
- **The screenshots are committed** under `test/platform/evidence/`, beyond the
  plan's `files_modified` list, because the plan's own human-check says "attach
  both screenshots" and a record whose evidence lives in `/tmp` is not checkable
  (T-01-64).

## Deviations from Plan

None — plan executed exactly as written. No prohibition was reached: no route's
verdict differed from the expectation, so nothing had to be handed back, and no
harness or prediction was adjusted to make a route agree.

Worth stating explicitly because 01-12 warned about it: `foreign-grab` read
`NOTHING`, which is what 01-12 measured and what this plan's `<interfaces>`
expected. Had it read `HIDE` this plan would have stopped rather than reconciled.

## Issues Encountered

- **The bundle's launcher mtime is a false freshness signal.** The task
  precondition asks for a rebuild if the bundle's mtime predates the 01-12 commit,
  and `hotkey_grammar_corrector` is dated 2026-09-04 — it holds no Dart code and
  is not relinked by a Dart-only change. A `flutter build linux --release` was run
  anyway and was a no-op. Freshness was then established properly: the AOT
  snapshot `lib/libapp.so` (2026-09-10T14:21:40Z) postdates the last `lib/` commit
  (`791ddb9`, 14:11:16Z) with a clean tree, and `strings` on it finds
  `X11KeyboardFocusWitness`, `AbsentKeyboardFocusWitness` and `_keyboardStillHere`
  — symbols that did not exist before `dc6079b`. Later plans should check the
  snapshot, not the launcher.
- **A `pkill -f` in a helper script killed the calling shell, three times, before
  the cause was seen.** The script was created with a bash heredoc, so the bundle
  path inside it became part of the *calling* shell's command line — and the
  script's own `pkill -f 'bundle/hotkey_grammar_correcto[r]'` then matched that
  shell. Output was lost to buffering each time, which made it look like a hang.
  The fix: helper scripts kill their daemon by session id (`kill -TERM -- -$SID`),
  never by a `-f` pattern, and are written with a file-writing tool rather than a
  heredoc. `panel_toggle_probe.sh` is unaffected — its own pattern is bracketed
  and its callers do not embed the path.
- **`import -window <id>` hangs on an unmapped window.** The first AD-18 attempt
  wedged there for minutes. Replaced with `timeout 20 scrot -o`, which captures the
  whole 1440x900 screen and shows the panel in situ — better evidence anyway.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

**Ready for 01-14**, which owes the ledger filings. `WINDOWS.md` now carries entry
28 (`unmet-truth`) alongside 01-12's five: the foreign-grab behaviour change
(entry 24), T-01-59, T-01-60, the unobserved Wayland arm, and the
mutation-counting hazard.

Two things a later reader should not mistake:

- **`NOTHING` is the pass on `foreign-grab`.** Any future gate over that route
  must expect `NOTHING`, and a `HIDE` there is a regression, not a fix.
- **Nothing here observed Wayland.** There is no portal in this container; the
  Wayland arm is wired to a witness that never suppresses, so its behaviour is
  unchanged *by argument*. Section 6 of the record names that, plus the
  single-window-manager limit and the synthetic key events, in that register.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-10*

## Self-Check: PASSED

- `test/platform/panel-toggle-observation.md` — present on disk.
- `test/platform/evidence/panel-toggle-ad18-first-summon.png` — present on disk.
- `test/platform/evidence/panel-toggle-ad18-second-summon.png` — present on disk.
- `tool/uat/panel_toggle_probe.sh` — present on disk, `bash -n` clean.
- Commits `4a6cb5e`, `4a0e25c`, `71bf03a` — all present in `git log`.
- Task 1 `<verify>` re-run in full: exit 0, thirteen `ROUTE` lines, every gate matched.
- Task 2 `<verify>` re-run in full: grep gates pass, `dart test --exclude-tags=live test/architecture` green (228 passed, 1 skipped).
