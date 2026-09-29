---
phase: 01-hotkey-truth
plan: 14
subsystem: testing
tags: [deferred-work, ledger, append-only, skip-prose, runtime-observation, cap-14, g-01-13, xvfb, openbox]

# Dependency graph
requires:
  - phase: 01-11
    provides: "the event-stream toggle oracle and the recorded pre-fix baseline the retirements are measured against"
  - phase: 01-12
    provides: "the fix whose closure, residuals and behaviour change this plan files, and its threat register (T-01-59, T-01-60)"
  - phase: 01-13
    provides: "test/platform/panel-toggle-observation.md — the committed runtime evidence every retired claim is retired against"
provides:
  - "DW-122 — the G-01-13 closure, with the AND-gate, the rejected reorder, file:line evidence and the DW-33 relationship stated"
  - "DW-123 — the refutation of the premise DW-9, DW-26 and DW-44 were closed under, filed without reopening any of them"
  - "DW-124 — the three residuals the fix accepts rather than closes, each with its threat id, plus the argued Wayland arm"
  - "DW-125 — the foreign-grab behaviour change, filed as awaiting a human's ratification"
  - "six skip reasons that no longer claim the panel's on-screen behaviour is unobservable here, each retirement carrying its evidence"
  - "a corrected run-output print in the suite that pins the skip prose"
affects: [arch-06, wayland-portal, ledger-01, phase-7-spine-reconciliation]

actuals:
  tokens: 6210
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A refutation of a closed entry's premise filed as a NEW entry that names it, never as an edit to its status line"
    - "Append-only measured with git diff --numstat's deletions column, and required additions > 0, so the gate cannot pass vacuously post-commit"
    - "A retired claim retired WITH its evidence — what was observed, when, against what, and the record file — never by deleting the sentence"

key-files:
  created: []
  modified:
    - _bmad-output/implementation-artifacts/deferred-work.md
    - test/platform/panel_visibility_live_test.dart
    - test/platform/correction_panel_live_test.dart
    - test/platform/x11_hotkey_live_test.dart
    - test/platform/settings_screen_live_test.dart
    - test/platform/tray_live_test.dart
    - test/platform/wayland_hotkey_live_test.dart
    - test/architecture/runtime_checklists_test.dart

key-decisions:
  - "DW-9, DW-26 and DW-44 are NOT reopened. Reopening is not the closing motion the append-only rule describes, and rewriting a closed entry's status is the violation DW-13 and DW-108 record. The refutation is DW-123, which names all three; a human may reverse that call."
  - "The four entries were appended at the end of the file rather than inserted after DW-121's block, so the diff is a single trailing hunk that cannot disturb an existing line"
  - "test/platform/desktop_entries_live_test.dart was left byte-identical — every claim in it is still true, and editing it to look busy would have replaced one false statement with another"
  - "No pin in runtime_checklists_test.dart moved. Every retirement preserved its file's pointer clause and its cited step numbers in order, because the checklist steps are still owed on a REAL desktop even where this container has now observed the claim"
  - "The seventh pointer site, test/architecture/hidden_window_test.dart, was deliberately NOT audited — it is outside this plan's declared file set, and its claim is routed to DW-123's open re-triage"

patterns-established:
  - "Where a new finding contradicts a closed entry's own text, the disagreement is stated in the new entry and both texts survive"
  - "A skip reason may only lose a claim this container has ACTUALLY observed; every claim still needing a StatusNotifier host, a GlobalShortcuts portal, a session bus or a login stays word for word"

requirements-completed: []

coverage:
  - id: D1
    description: "Four new ledger entries exist — DW-122 closed with a resolution, DW-123, DW-124 and DW-125 open — in Format 1 with every field at column 0"
    verification:
      - kind: other
        ref: "grep -c '^### DW-12[2-5]:' deferred-work.md == 4; awk-range read of each entry confirms status: done + resolution: on 122 and status: open on 123/124/125"
        status: pass
    human_judgment: false
  - id: D2
    description: "The append-only contract held: zero deleted lines and a non-zero addition count on the ledger, checked before the commit"
    verification:
      - kind: other
        ref: "git diff --numstat -- deferred-work.md -> 33 additions, 0 deletions (pre-commit); git diff --numstat 774caf4~1..HEAD -> 33 0 (post-commit confirmation); git diff --unified=0 shows one hunk, @@ -1793,0 +1794,33 @@"
        status: pass
    human_judgment: false
  - id: D3
    description: "DW-122 states the AND-gate in both halves, why a reorder-only fix was rejected, what was built, file:line evidence for the three edits, and the DW-33 relationship — and cites the observation record rather than asserting the behaviour"
    verification:
      - kind: other
        ref: "entry 122 | grep -q 'DW-33' && grep -q 'panel-toggle-observation' — both pass; the three edits cite window_manager_panel_visibility.dart:1048-1050, :1209 and daemon_startup.dart:123/:333/:190 + main.dart:136"
        status: pass
    human_judgment: true
    rationale: "That the reason reads as an argument a reader who was not here can follow — rather than as an assertion with citations attached — is a reading of prose. grep can prove DW-33 and the record are named; it cannot prove the two questions are described as standing beside each other rather than one replacing the other."
  - id: D4
    description: "DW-9, DW-26, DW-44 and DW-33 were not edited: no status line changed, no field text rewritten"
    verification:
      - kind: other
        ref: "the whole ledger diff is one trailing addition hunk at line 1793; none of the four entries' line ranges appear in it"
        status: pass
    human_judgment: false
  - id: D5
    description: "Six skip reasons retired exactly the claims this container has observed, each with its evidence and a pointer at the observation record; desktop_entries_live_test.dart untouched"
    verification:
      - kind: other
        ref: "grep gates pass: panel-toggle-observation in panel_visibility and correction_panel, StatusNotifier in tray, GlobalShortcuts in wayland_hotkey; git diff --stat shows desktop_entries_live_test.dart absent"
        status: pass
    human_judgment: true
    rationale: "Whether each edit removed exactly the false sentences and no more — and whether the surviving claims still read as owed rather than as forgotten — is a judgment about prose. The greps prove the load-bearing strings survive; they cannot prove the register is right. Every removed line was reviewed one by one against the plan's table."
  - id: D6
    description: "The pinning suite is green and no pointer clause or cited step number moved; the whole suite is green under both runners with nothing newly skipped"
    verification:
      - kind: unit
        ref: "dart test --exclude-tags=live test/architecture -> +228 ~1, runtime_checklists_test.dart included"
        status: pass
      - kind: unit
        ref: "dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart -> +974 ~2 (identical to 01-12's recorded baseline)"
        status: pass
      - kind: unit
        ref: "flutter test --exclude-tags=live test/ui test/platform test/composition -> +165 ~7 (identical to 01-12's recorded baseline)"
        status: pass
      - kind: other
        ref: "dart analyze --fatal-infos -> No issues found!"
        status: pass
    human_judgment: false
  - id: D7
    description: "DW-123's 'the three closed entries are not reopened' call is the right one"
    verification: []
    human_judgment: true
    rationale: "It is a ledger-discipline judgment with a defensible answer either way, taken by an unattended executor. Append-only says do not rewrite a closed status; a reader may reasonably hold that three entries closed on a premise now known false should be open work rather than a footnote. DW-123 states the call and says a human may reverse it."
  - id: D8
    description: "DW-125's behaviour change is acceptable product behaviour — a foreign client's global shortcut no longer dismisses the panel"
    verification: []
    human_judgment: true
    rationale: "Measured beyond doubt (foreign-grab HIDE -> NOTHING, focus unmoved on both sides) and unratified by anyone. It is a visible product behaviour on a desktop where the user has bound another application to a system-wide shortcut, and no test can decide whether it is wanted. WINDOWS.md 24 keeps it visible at ship time."

# Metrics
duration: 22 min
completed: 2026-09-10
status: complete
---

# Phase 01 Plan 14: Make the Record True Again Summary

**Four ledger entries appended with zero deleted lines — the G-01-13 closure with file:line evidence and its relationship to DW-33, the refutation of the "nothing is observable in this container" premise that DW-9, DW-26 and DW-44 were closed under (filed without reopening any of them), the three residuals the fix accepts, and the one behaviour it changed — plus six `test/platform/` skip reasons that stop claiming the panel's on-screen behaviour cannot be seen here, and one that was correctly left alone.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-09-10T14:48:00Z (approximate — the first tool call, not a recorded mark)
- **Completed:** 2026-09-10T15:10:16Z
- **Tasks:** 2
- **Files modified:** 8

## The number the plan asked for first

**The ledger diff's deleted-line count is ZERO.** Measured with `git diff --numstat` — not by grepping the diff for `^-`, because `- foo` diffs as `-- foo` and this file is full of markdown bullets — and measured **before** the commit, so the additions check could not pass vacuously:

```
ledger diff +33 -0
GATE PASS
```

Confirmed again at the commit level after the fact: `git diff --numstat 774caf4~1..HEAD -- deferred-work.md` reports `33  0`, and `git diff --unified=0` shows a single hunk, `@@ -1793,0 +1794,33 @@` — one trailing addition. Not one existing line was deleted, reformatted, re-wrapped or whitespace-fixed.

## The four new entries

| Entry | Status | What it carries |
| --- | --- | --- |
| **DW-122** | `done 2026-09-10` + `resolution:` | The defect and its fix. The AND-gate in both halves (the self-inflicted `FocusOut(NotifyGrab)` dismissal, and its winning the race against the toggle's own activation 8-16 ms later); why a reorder-only fix was rejected — a measured 4 ms margin, two async paths on the same queue with no ordering guarantee, and T-01-09 reopened by removing the 8 ms poll; what was built instead (the `KeyboardFocusWitness` seam and `XGetInputFocus`, which a grab does not disturb); and **file:line evidence for all three edits**. States the DW-33 relationship in its own words: DW-33 asks *did this window ever hold the keyboard?*, still runs first at `:1042-1047`, and is unchanged — the new question asks *has the keyboard actually gone anywhere?* Two distinct non-dismissals, neither subsuming the other. Cites `test/platform/panel-toggle-observation.md` as the runtime evidence rather than asserting the behaviour. |
| **DW-123** | `open` | The refuted premise. Names DW-9, DW-26, DW-44 and the seven `test/platform/*_live_test.dart` skip reasons, quotes each closure's own words, and records that their shared claim is false as of 2026-09-04 — with the measurement: `Xvfb :99` + `openbox 3.6.1` + the release bundle produced a real grab, a real mapped and focused panel, a real focus-loss hide, and a major CAP-14 defect no green row had found. States explicitly that the three are **not** reopened and why, and that a human may reverse that. |
| **DW-124** | `open` | What the fix accepts rather than closes, each with its threat id: a focus window id another client on the display could contrive (T-01-59, accepted — X11 offers no inter-client isolation and such a client can already read the panel and inject keys); a synchronous X round trip on the platform thread with no bound (T-01-60, accepted on an **argument, not a measurement** — nobody wedged an X server); and a host whose display server reports a focus that cannot be attributed, where the witness answers "cannot tell", the adapter dismisses as it always did, and G-01-13 therefore persists. The Wayland arm is here too: wired to the witness that never suppresses, so unchanged by argument and not by observation. |
| **DW-125** | `open` | The behaviour change, unratified — filed in the same register as plan 01-09's gate answer. A foreign client's global shortcut fired while the panel is up no longer dismisses it (`foreign-grab` `HIDE` -> `NOTHING`, `FOCUS_BEFORE=FOCUS_AFTER=4194308`). The argument for the new behaviour is stated; so is the fact that nobody has ratified it, and that restoring the old dismissal is a different fix rather than a small edit. |

Confirmed before writing that the highest canonical heading was still **DW-121** (the run of `### DW-` headings ends there; 01-13 appended nothing), so the ids start at 122. DW-9, DW-26, DW-44 and DW-33 were read in full and left untouched.

## The skip-text audit, file by file

### Changed (six)

| File | What was retired | What survived, and why |
| --- | --- | --- |
| `panel_visibility_live_test.dart` | "no reachable X display", and the argument that standing one up closed nothing because "a bare X server has no compositor" so there is "nothing on a synthetic display to observe them against". Both named as wrong, with the measurement, the environment, the date and the record. | DW-25's echo-ordering claim, DW-12's close-control claim, DW-33's map-without-focus claim, DW-32's click-back interleaving and DW-30's gesture-to-event-name premise — all byte-identical. The retirement adds what is *still* owed: one window manager on a synthetic server, every press from `xdotool` (XTEST) rather than a finger, so GNOME/Mutter and KDE/KWin are unmeasured and DW-9 stays open for them. |
| `correction_panel_live_test.dart` | The display half of "no compositor and no reachable X display …, so nothing about the panel *on screen* is seen", and **claim (2)** — marked `OBSERVED`. This is the sharp one the plan flagged: "that the focus-loss hide leaves it dismissed rather than flickering, with the panel never calling `hide()` itself" is G-01-13 stated in advance, in that sentence, by a row that could not run. The retirement says so, and says it is the single best piece of evidence in this repository that a bodyless skipped row is worth writing. | Claims (1) 100 ms timing, (3) real clipboard paste, (4) window geometry, (5) input method and keypad. The `(2)` label was kept so the later citation prose ("for claim (1) and for claim (2)") still resolves. |
| `x11_hotkey_live_test.dart` | "the host display cannot be reached either" and "Standing one up would produce a result about Xvfb" — refuted by naming what standing one up actually produced. | The CAP-1 100 ms budget and the CAP-12 live rebind, neither timed nor driven here; the existing keybinder/Xvfb self-correction; the "every claim below is about the session and not the display" reasoning, which is still the right shape for what it now covers. |
| `settings_screen_live_test.dart` | "no reachable X display". | No portal, no session bus, no compositor rebind, no screen reader — all still true, and the opening list now names the login and the assistive technology that actually are absent in the display's place. |
| `tray_live_test.dart` | "no Xvfb/xvfb-run to stand one up" and the companion "no reachable X display". | The row's whole subject: no StatusNotifier/AppIndicator host, no shell hosting one, no `xdg-desktop-portal`. The retirement states plainly that it changes nothing here — an X server with a bare window manager hosts no StatusNotifier item — so the claim is exactly as unobservable as it was. |
| `wayland_hotkey_live_test.dart` | "no way to press a key" — `xdotool`/XTEST drove the entire X11 toggle measurement. | No compositor, no portal, no GlobalShortcuts backend, no session bus. The retirement says why the press buys nothing on this path: with no backend there is no portal to accept a binding and nothing to deliver an `Activated` signal. |

### Deliberately NOT changed (one)

**`desktop_entries_live_test.dart` — byte-identical, and that is the finding rather than an omission.** Every claim in it was checked against the container: no login session (`/run/user/` is empty, `DBUS_SESSION_BUS_ADDRESS` unset), `desktop-file-validate` still **absent** (verified: not on `PATH`), no compositor, no portal, no GlobalShortcuts backend. All four AD-11/AD-14 claims need a real GNOME or KDE session and none of them turns on a display. Its "no `XDG_RUNTIME_DIR` holding a real daemon socket" clause is true at rest — the probe fabricated a throwaway one per route on purpose (T-01-55) and the session never supplied one. Editing it would have been editing to look busy, which the plan explicitly rules out.

### No pin moved

`test/architecture/runtime_checklists_test.dart`'s `_pointers`, `_citations` and `_Procedure.notCoveredHere` declarations are **unchanged**. Every edited file kept its pointer clause (`test/platform/runtime-observation-checklist.md`) and its cited step numbers in the exact order the citation declares them — `panel_visibility` 5, 6, 7; `correction_panel` 5, 6, 12, 13; `x11_hotkey` 8, 9, 10, 12; `settings_screen` 13, 10, 15. Preserving them was also the truthful choice, not just the safe one: those checklist steps are still owed on a *real* desktop even where this container has now observed the claim, so the clause still sends the reader to real work. New prose was written to avoid the token `step`/`steps` followed by a number, since `_citedStepOrderIn` parses exactly that out of the skip reason and an incidental "step 5" anywhere would have broken the order equality.

## Task Commits

1. **Task 1: four ledger entries** — `774caf4` (docs)
2. **Task 2: the skip-text audit** — `77e744c` (test)

**Plan metadata:** see the final `docs(01-14)` commit.

## Decisions Made

- **DW-9, DW-26 and DW-44 are not reopened.** Append-only says closing flips a status and adds a resolution; nothing in it describes a reverse motion, and rewriting a closed entry's status is exactly DW-13's and DW-108's recorded violation. The refutation is DW-123, which names all three and states the call out loud.
- **Appended at end of file, not inserted after DW-121.** DW-121 is the last canonical heading; flat `- source_spec:` entries follow it. Appending at EOF makes the diff a single trailing hunk that structurally cannot touch an existing line.
- **A retired claim keeps its evidence.** Every retirement says what was observed, when (2026-09-04 to 2026-09-10), against what (`Xvfb :99`, `openbox 3.6.1`, the release bundle) and where the record is. None was retired by deleting the sentence — that is how a claim gets forgotten, which is the failure these rows exist to prevent (T-01-69).
- **The corrections are stated, not silently applied.** Each edit follows the register `x11_hotkey_live_test.dart` already used for keybinder and Xvfb: the prose that was wrong is quoted and named as wrong.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] DW-123 was written without its `status:` line**

- **Found during:** Task 1 (running the task's own acceptance gate)
- **Issue:** The first append produced DW-123 with `origin:`, `location:`, `severity:` and `reason:` but no `status:` field. The gate caught it — the `for n in 123 124 125` loop failed — which is precisely what that gate is for. An entry with no `status:` is invisible to `bmad-loop sweep`, which treats an entry as open only when the first word of `status:` is exactly `open`, so the refutation would have been filed and then never scheduled.
- **Fix:** `status: open` inserted immediately beneath `reason:`, matching Format 1's field order. Two intermediate repair attempts mis-landed the line (once after `severity:`, once duplicating it); both were corrected in the uncommitted block before staging, so the committed diff is 33 clean additions with zero deletions.
- **Files modified:** `_bmad-output/implementation-artifacts/deferred-work.md`
- **Verification:** the full acceptance gate re-run to `GATE PASS`, and the committed diff re-measured at `33  0`.
- **Committed in:** `774caf4`

**2. [Rule 1 - Bug] One edit beyond the plan's table: the pinning suite's own run-output print was making the same false claim**

- **Found during:** Task 2 (reading `runtime_checklists_test.dart` before touching any skip reason)
- **Issue:** The suite that exists to stop these claims rotting was itself printing, on every green run: "this container has no session: no compositor and **no window manager**… (Xvfb, xvfb-run, xwininfo, xdotool and xprop are all installed, so a bare display could be stood up — **it would supply none of the above**)". `openbox 3.6.1` is installed, was stood up, and supplied exactly the window manager that clause denies. Leaving it would have finished an audit of false claims about this container by leaving the false claim in the file most likely to be read for the truth.
- **Fix:** the parenthetical rewritten in the same correction register as the skip reasons — the old wording quoted, named as wrong, the measurement and the record given, and the part that is still true ("what it still supplies none of is the list above") kept. `openbox` and `xev` added to the installed list. The `print` carries no assertion, so **no pin moved and no declaration changed**.
- **Files modified:** `test/architecture/runtime_checklists_test.dart`
- **Verification:** `dart test --exclude-tags=live test/architecture` -> `+228 ~1`, all passed.
- **Committed in:** `77e744c`
- **Filed:** `.planning/WINDOWS.md` as a `deviation`, because it is one edit outside the plan's declared table.

---

**Total deviations:** 2 auto-fixed (2 bugs — one a missing field caught by the task's own gate, one a false claim inside the guard itself).
**Impact on plan:** No prohibition was reached. Nothing was deleted from the ledger, no closed entry was edited, and no claim that still needs a real desktop session lost a word. Deviation 2 is the only edit outside the plan's table and it is filed as such.

## Issues Encountered

- **The seventh pointer site was left unaudited, deliberately.** `test/architecture/hidden_window_test.dart` is the seventh place `_pointers` covers, and its AD-8 skip reason still says "the host display is unreachable too" and that "Xvfb supplies a bare X server with no window manager, so a synthetic display answers a question nobody asked" — the same premise DW-123 refutes. It is **not** in this plan's `files_modified` and not in the plan's table, so editing it would have been scope creep on a file the plan never opened. Routed instead to DW-123's open re-triage and filed in `.planning/WINDOWS.md` as an `unmet-truth` so it is not lost.
- **The step-citation parser is a live hazard for prose edits.** `_citedStepOrderIn` extracts `step N` / `steps N and M` out of the skip reason and the pin asserts the sequence *in order*, so any new sentence containing "step" followed by a number would have failed a correct edit. Every retirement was written around that. It is worth knowing before the next plan opens one of these files.

## Known Stubs

None. Nothing was stubbed, and nothing was retired without a named observation behind it.

## Threat Flags

None. Both files this plan touches carry file paths, ledger ids and behavioural claims only — no user text, clipboard content or credential is reachable from either (T-01-72, accepted in the plan's register). The three `mitigate` rows are all implemented: T-01-68 by the `--numstat` deletions-plus-additions gate, T-01-69 by every retirement naming its observation and record, T-01-70 by the table-driven edit plus positive greps for the claims that must survive, and T-01-71 by preserving every pointer clause and citation rather than relaxing a pin.

## Broken-windows ledger

Two entries appended to `.planning/WINDOWS.md`, both `open`:

| # | Kind | What |
| --- | --- | --- |
| 29 | deviation | The one edit beyond the plan's table — the pinning suite's own run-output print, which was making the same false claim |
| 30 | unmet-truth | `hidden_window_test.dart`, the seventh pointer site, deliberately not audited; routed to DW-123 |

The four earlier filings this plan was owed are now discharged into the ledger: WINDOWS 22 (01-11's reported-rather-than-smoothed criterion, reconciled in 01-12's SUMMARY and cited by DW-122), WINDOWS 24 (the behaviour change -> **DW-125**), WINDOWS 25 and 26 (T-01-59, T-01-60 and the unobserved Wayland arm -> **DW-124**), and WINDOWS 28 (the unreproduced `NotifyUngrab`/`_focused` mechanism, which DW-124's third residual and the observation record's section 6 both carry). WINDOWS 27's counting hazard was honoured: no failure count anywhere in this plan came from the compact reporter — no mutation counting was needed, and the two suite runs are reported by their `+N ~M` totals.

## The two decisions a human may reverse

Flagged here because the plan requires it, and because both were taken by an unattended executor.

1. **DW-123's "not reopened" call.** DW-9, DW-26 and DW-44 still read `status: done 2026-08-14`, and the premise all three closed under is now known false. Append-only discipline says a closed entry's status is not rewritten, and DW-13 and DW-108 exist because that rule was broken twice — so the refutation was filed as a new entry naming all three. A human may hold that three entries closed on a false premise should be open work rather than a footnote, and DW-123 says so and says nothing forecloses it. If they are reopened, DW-123 is the record of why it was not done unilaterally.
2. **DW-125's behaviour change.** A foreign client's global shortcut no longer dismisses the panel. Measured beyond doubt, deliberate, and unratified. It is a visible product behaviour on any desktop where the user has bound another application to a system-wide shortcut, and restoring the old dismissal is a different fix rather than a small edit — the direction plan 01-12 rejected as unfixably racy.

## Verification

| Check | Result |
| --- | --- |
| `git diff --numstat` on the ledger, **before** the commit | `+33 -0` — zero deletions, non-zero additions |
| `git diff --unified=0` on the ledger | one hunk, `@@ -1793,0 +1794,33 @@` |
| DW-122 … DW-125 present, Format 1, fields at column 0 | 4 headings; `status: done` + `resolution:` on 122, `status: open` on 123/124/125 |
| DW-122 names DW-33 and `panel-toggle-observation` | both present |
| DW-123 names DW-9, DW-26 and DW-44 | all three present |
| DW-9 / DW-26 / DW-33 / DW-44 field lines in the diff | none |
| `dart analyze --fatal-infos` | `No issues found!` |
| `dart test --exclude-tags=live test/architecture` | `+228 ~1` — all passed, `runtime_checklists_test.dart` included |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | `+974 ~2` — all passed |
| `flutter test --exclude-tags=live test/ui test/platform test/composition` | `+165 ~7` — all passed |
| Skip counts vs 01-12's recorded baseline | identical (`~2` and `~7`); nothing newly skipped, nothing lost |
| `panel-toggle-observation` in `panel_visibility` and `correction_panel` | both present |
| `StatusNotifier` in `tray`, `GlobalShortcuts` in `wayland_hotkey` | both present |
| `desktop_entries_live_test.dart` in the diff | absent — untouched, as intended |
| `desktop-file-validate` on `PATH` | MISSING — that row's claim re-verified true |

Every removed line across the seven touched files was reviewed individually against the plan's table. All 46 removals are the intended false sentences or their immediate wrapping, re-added in the replacement text.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

**Phase 01's plans are complete: 14 of 14.** Ready for `/gsd-verify-work 01`.

**What Phase 7 / ARCH-06 inherits from this plan:** nothing new. No spine line was touched and no frozen declaration moved; DW-122 records explicitly that its fix owes no ratification because the witness stays out of `lib/src/domain/`.

**What is now owed, and to whom:**

- **A human**, on the two reversible calls above.
- **A real desktop session** (GNOME/Mutter, KDE/KWin, a physical keyboard), for everything the observation record's section 6 names and for the checklist steps every retirement still points at.
- **DW-123's re-triage** — the rest of the claims the two checklists carry, against a live session. Some of them plainly can be observed here now, and `hidden_window_test.dart`'s AD-8 skip reason is the first place to look.
- **DW-124's residuals** — one measurement (T-01-60, an actually-wedged X server) would close half that entry.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-10*

## Self-Check: PASSED

- `.planning/phases/01-hotkey-truth/01-14-SUMMARY.md` — FOUND
- `_bmad-output/implementation-artifacts/deferred-work.md` — FOUND
- `test/platform/panel_visibility_live_test.dart` — FOUND
- `test/platform/correction_panel_live_test.dart` — FOUND
- `774caf4` — FOUND
- `77e744c` — FOUND
