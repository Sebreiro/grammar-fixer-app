---
phase: 01-hotkey-truth
plan: 10
subsystem: docs
tags: [deferred-work, ledger, append-only, hotkey-10, arch-06, spine-reconciliation, hand-off]
status: complete

# Dependency graph
requires:
  - phase: 01-01
    provides: "The DW-89 packaging closure and the three entries 01-01 appended — including the Phase-7 AD-9 hand-off written in prediction form, which this plan confirms and corrects rather than rewrites"
  - phase: 01-02
    provides: "The measured removal of hotkey_manager/libkeybinder that makes HOTKEY-10's dissolution true of the tree rather than merely argued"
  - phase: 01-08
    provides: "The precedence rule and its reachability boundary, which FLAT-03's closure quotes"
  - phase: 01-09
    provides: "The defensive-copy answer and its explicit framing as orchestrator-selected, which FLAT-05's closure carries verbatim in substance"
provides:
  - "HOTKEY-10 closed as DISSOLVED with three measured findings, and with an explicit statement that no re-keying was invented because there is nothing left to key to"
  - "Eight further dated closures with file:line or measured-command evidence: DW-39, DW-40, DW-66, DW-71, FLAT-02, FLAT-03, FLAT-04, FLAT-05"
  - "Two supersessions stated in writing with both records intact: DW-39's route (X11 grab, not keybinder FFI) and DW-71's dissolved per-display-server difference"
  - "Seven new open entries carrying everything this phase found and deliberately did not do, including two the plan did not enumerate"
  - "A corrected Phase-7 (ARCH-06) AD-9/AD-11 hand-off: shipped names, current spine line numbers, and the fact that one of the four edits was orchestrator-selected rather than human-ratified"
  - "A recovered WINDOWS.md record that existed only as a rendered table row and would have been destroyed by the next table regeneration"
affects: [phase-07-arch-06-spine-reconciliation, phase-02-settings-tray, packaging-phase]

# Actuals (#2632) — estimateTokens scale (chars/4) over the realized diff, not a harness token count.
actuals:
  tokens: 12166
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Closing an append-only entry whose own decision: line the closure contradicts: state the supersession in words, give the reason, name which record is operative, and leave both texts byte-identical"
    - "Closing a requirement whose premise dissolved: record the dissolution with evidence and say explicitly that no substitute target was invented, so a later reader does not read the absence as an oversight"
    - "Correcting a prediction-form ledger entry by appending a confirmation entry that names the corrections, rather than editing the prediction"
    - "Locating ledger entries by unique content anchor with an assertion that the anchor matches exactly once, never by remembered line offset"

key-files:
  created:
    - .planning/phases/01-hotkey-truth/01-10-SUMMARY.md
  modified:
    - _bmad-output/implementation-artifacts/deferred-work.md
    - .planning/WINDOWS.md
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "HOTKEY-10 is closed as DISSOLVED, not implemented. Its premise — a re-measure trigger keyed to hotkey_manager_linux 0.2.0 — lost its subject when plan 01-02 deleted the facade. No re-keying target was invented; the plan's own prohibition forbids it and the closure says so in words."
  - "Seven new open entries were filed, not the plan's five. Two additions: the Phase-7 AD-9/AD-11 hand-off correction (required by the plan's own must_haves.truths, and load-bearing because 01-01's prediction-form entry is now wrong about edit 4) and the unbounded _closeSessionBeforeRebinding Close (which plan 01-05's SUMMARY explicitly asked 01-10 to file)."
  - "01-09's gate answer is recorded as ORCHESTRATOR-SELECTED and requiring human re-confirmation, in two places (FLAT-05's resolution and the AD-9 hand-off correction), and as a STATE.md blocker. It is nowhere recorded as a human ratification."
  - "FLAT-04's construction-site count is recorded as 13, measured 2026-09-02, against a sibling entry's 20 and against this plan's own action text saying 14. The sibling entry keeps its 20 untouched (append-only) and is corrected inside FLAT-04's resolution."
  - "The retired-measured-facts entry records where each of the four facts NOW LIVES rather than asserting they vanished — three survive in-tree or in DW-42's own resolution. An index that overstated the loss would be as misleading as no index."
  - "A pre-existing WINDOWS.md inconsistency was repaired non-destructively: plan 01-09's unrun-verify record existed only in the rendered table and not in the fenced JSON source of truth, so regenerating the table would have deleted it. It was re-filed as JSON id 19 with its original timestamp before the table was regenerated."

requirements-completed: [HOTKEY-10]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "HOTKEY-10 is closed with the finding that its premise dissolved, with evidence, and with no invented re-keying"
    requirement: "HOTKEY-10"
    verification:
      - kind: other
        ref: "grep -c 'hotkey_manager' pubspec.lock => 0 (the trigger's subject is not resolved at all)"
        status: pass
      - kind: other
        ref: "FLAT-11 region: grep -c '^  status: done' => 1 and grep -c '^  resolution:' => 1, both at the two-space indent"
        status: pass
      - kind: other
        ref: "resolution text names all three findings and cites pubspec.lock, the readelf/ldd/ls quartet from 01-02's coverage id D2, and the libgdk-3 DT_NEEDED measurement"
        status: pass
    human_judgment: false
  - id: D2
    description: "The ledger changes are append-only: only the nine status lines being replaced were deleted, and no entry, decision, reason, evidence or summary text was rewritten"
    verification:
      - kind: other
        ref: "git diff --numstat over the two commits => 53 insertions / 9 deletions; git diff | grep '^-[^-]' yields exactly nine lines, all 'status: open'"
        status: pass
      - kind: other
        ref: "status-line multiset diff against the pre-plan base: only the four canonical and five flat closures moved; every other status bucket byte-identical"
        status: pass
    human_judgment: false
  - id: D3
    description: "ARCHITECTURE-SPINE.md was not edited by this phase, and the amendments it owes are handed on precisely instead"
    verification:
      - kind: other
        ref: "git status --porcelain _bmad-output/planning-artifacts/ => empty; git diff --name-only over both commits => the ledger file only"
        status: pass
      - kind: other
        ref: "the spine still carries 6 hotkey_manager/libkeybinder mentions, which is why the amendment is filed rather than assumed done"
        status: pass
    human_judgment: false
  - id: D4
    description: "Two already-closed entries kept their pre-existing closures"
    verification:
      - kind: other
        ref: "DW-42 (ledger :803) and DW-43 (:813) both still read 'status: done 2026-08-14'"
        status: pass
    human_judgment: false
  - id: D5
    description: "The tree is unchanged: this plan is documentation-only, so the phase's measured baseline still holds"
    verification:
      - kind: other
        ref: "git diff --name-only over both commits touches zero .dart files; dart analyze --fatal-infos => No issues found!; dart test => 960 passed / 2 skipped; flutter test => 165 passed / 7 skipped; grep -r 'test(' test/ | wc -l => 983"
        status: pass
    human_judgment: false
  - id: D6
    description: "Every AD-9 declaration edit and AD-11 step 1 is recorded for Phase 7 with the shipped names and current spine addresses, and edit 4's non-ratification is unmistakable"
    verification:
      - kind: other
        ref: "ledger :1790-1794, the AD-9 hand-off correction entry; cross-checked against ARCHITECTURE-SPINE.md:246, :274-278, :280-300, :314 and against the shipped symbols at global_hotkey.dart:135, hotkey_bind_outcome.dart:51, hotkey_binding.dart:6-7"
        status: pass
    human_judgment: true
    rationale: "The addresses and names are mechanically verified, but whether the hand-off text is sufficient for a reconciler who was not present is a judgement no command here settles. Phase 7 is where that is tested."
---

# Phase 01 Plan 10: Ledger Closure Summary

**Nine ledger entries closed with dated, evidence-carrying resolutions — including HOTKEY-10, closed as *dissolved* rather than implemented because plan 01-02 removed the package its re-measure trigger was keyed to — plus seven new open entries carrying every amendment and defect this phase found and deliberately did not fix. Nine `status: open` lines were replaced and nothing else was deleted; `ARCHITECTURE-SPINE.md` was not touched.**

- **Duration:** ~38 min
- **Tasks:** 2 of 2
- **Commits:** 2 task commits + 1 metadata commit
- **Files changed by the tasks:** 1 (`_bmad-output/implementation-artifacts/deferred-work.md`)

---

## READ THIS FIRST — the three things a morning reader should check

1. **HOTKEY-10 is closed as dissolved, not as done work.** Its requirement text asked to re-key the envelope's `libkeybinder` hardness re-measure trigger. There is no longer a trigger, a package, or a claim to key it to. The closure says that in words, with evidence, and states that no substitute target was manufactured. If you disagree with closing a requirement this way, the entry to reopen is FLAT-11 at ledger line **1492-1496**.
2. **One AD-9 declaration edit in this phase was never seen by a human.** Plan 01-09's `defensive-copy` answer — dropping `const` from AD-9's declared `HotkeyBinding` constructor at `ARCHITECTURE-SPINE.md:246` — was selected by the orchestrator, not ratified. It is recorded as such at FLAT-05's resolution (ledger **1464-1465**), in the AD-9 hand-off correction entry (ledger **1790-1794**), and as a STATE.md blocker. **Phase 7 must not read plan 01-01's earlier "gated at the head of the plans that make them" as "ratified".**
3. **Seven new open entries were filed, where the plan's gates expected five.** That is a deliberate, declared overshoot, not a miscount — see *Deviations*, item 1. The plan's `grep -c '^  summary:'` gate is wrong by two.

---

## Accomplishments

### HOTKEY-10 — closed with the dissolution, and the envelope amendment filed

FLAT-11's resolution records three findings, each measured rather than argued:

1. **The trigger's subject left the tree.** The clause at `ARCHITECTURE-SPINE.md:584` says "Re-measure when the plugin version moves" about `hotkey_manager_linux 0.2.0`, which `pubspec.lock` recorded as `dependency: transitive`, reachable only through the `hotkey_manager 0.2.3` facade's `^0.2.0` constraint. Plan 01-02 (`6abf480`) deleted that facade, taking all five `hotkey_manager*` packages out of the lock together. Verified 2026-09-02: `grep -c 'hotkey_manager' pubspec.lock` → `0`.
2. **The claim the trigger guarded is retired.** `libkeybinder-3.0-0` left the runtime-dependency list outright rather than being demoted, and its replacement `libX11.so.6` is already an unconditional `DT_NEEDED` of `libgdk-3.so.0` on every host that can run the app at all — so no new hard dependency appears and none needs a trigger. Cited with plan 01-02's measured quartet (`readelf`, `ldd`, `ls bundle/lib/`, and `ldd` across every bundled `.so`), all taken on a release binary built eight seconds before the reading.
3. **No re-keying was invented, and the closure says so.** A test reading a resolved version out of `pubspec.lock` would read a line that no longer exists; restating the dependency structurally would restate one the build no longer has. The plan's own prohibition forbids manufacturing a target so the requirement has something to point at, and the resolution states the reasoning explicitly so a later reader does not read the absence as an oversight.

The spine amendment this implies is filed as its own open entry (ledger **1760-1764**), naming the envelope list at `:583`, the hardness paragraph and re-measure sentence at `:584`, the Stack row at `:442`, **three further falsified spine sentences the plan did not name** (`:300`, `:451`, `:498`), and the keybinder-route conditional that would change the amendment rather than delete it.

### Eight further closures, two of them stating a supersession

| Entry | Requirement | Ledger `status:` / `resolution:` | What the resolution does beyond citing the work |
|---|---|---|---|
| DW-39 | HOTKEY-01 | 773 / 774 | **States that the shipped route is not the route its own `decision:` line ratifies**, with both reasons: a `NativeCallable` cannot serve as a GLib `GSourceFunc` (no return value, wrong thread), so the `g_idle_add` marshalling that decision sketched does not compose; and the X11 route adds no runtime dependency. Records the measured `BadAccess`/`X_GrabKey` synchronous refusal under `XSetErrorHandler` + `XSync` and the live `Xvfb :77` REFUSED/HELD probe. Notes DW-42 and DW-43 were already closed 2026-08-14 and were not re-touched. Leaves DW-9's real-desktop checklist owed. |
| DW-40 | HOTKEY-02 | 783 / 784 | Closes on the measured quartet, not on assertion. Records that this entry's `decision:` had already corrected its own `reason:` about which ELF object carried the dependency, that the correction was re-confirmed, and that it mattered: plan 01-02's acceptance criterion #1 would have read `0` before the change too, so the phase's most severe defect was gated by a vacuous check until that plan substituted three non-vacuous ones. |
| DW-66 | HOTKEY-03 | 1137 / 1138 | Records **agreement with a standing decision** — the 2026-08-14 `decision:` already ratified rendering the localized description and rejected parsing it. Cites the three sources the description is carried from, that `effective` stays null with all three construction sites intact, and that nothing parses (`grep -nE 'split\(|RegExp\(|parse\('` matches nowhere). Leaves three human checks and the unexercised `ListShortcuts` branch owed. |
| DW-71 | HOTKEY-04 | 1184 / 1185 | Records agreement, then the two things that changed under it: the seven divergent labels were a vendor-package artefact (measured three ways) so **the per-display-server difference the `decision:` mentions no longer exists**, and the validation moved from Apply to **capture** (D-15), earlier than the decision says. Notes the set was *removed outright*, not emptied. Records the six live-observed checks and leaves the read-only-while-binding row and the unexercised `F1`-`F4` owed. |
| FLAT-02 | HOTKEY-06 | 1446 / 1447 | Cites the ratified names verbatim (`HotkeyStatus? get current`, `outcome`, `backendDescription`) and records the class of change — an addition leaving every declared field untouched — against the precedent at `global_hotkey.dart:50-54`. |
| FLAT-03 | HOTKEY-07 | 1452 / 1453 | Quotes the rule as written into the port doc and the `_backendChangeGeneration` guard. **Records the honest boundary**: the protocol-level inversion is unreachable on the shipped adapter (`:488`/`:519` both after the `await` at `:467`), the rule exists for the reachable rebind window and a future adapter, and on X11 the guard is structurally inert. Leaves the mid-`BindShortcuts` case owed. |
| FLAT-04 | HOTKEY-08 | 1458 / 1459 | Cites the ratified cause field and the final enum name. **Records the count correction: 13 real construction sites, measured**, against a sibling entry's 20 and this plan's own 14 — and records why a per-line grep was structurally unable to prove it. |
| FLAT-05 | HOTKEY-09 | 1464 / 1465 | Cites the shipped `Set<HotkeyModifier>.unmodifiable(...)` copy, **records in capitals that the option was orchestrator-selected and needs human re-confirmation**, keeps the honest scope ("this fixed no live defect"), and records the re-counted cost (50 `const` keywords across 17 files, 34 of them invisible to the grep). |

### Seven new open entries — everything found and not done

| # | Ledger bullet / summary | What it carries |
|---|---|---|
| 1 | 1760 / 1761 | The `ARCHITECTURE-SPINE.md` envelope + Stack amendment, with five falsified spine lines and the keybinder conditional |
| 2 | 1765 / 1766 | The portal app-id registration is never re-issued after a portal restart. `_registered` latches at `:697`, guard at `:586`, never reset; `grep -rc 'NameOwnerChanged' lib/` → **0**. Recorded as explicitly scoped out by 01-05, not overlooked, and bounded to unsandboxed builds only |
| 3 | 1770 / 1771 | AD-10's regime-display rule at `:620` is amended by D-03. Recorded as an amendment to a **user-ratified** decision, and as a judgement rather than a transcription, since the *consequence* of the regime is still on screen even though the *label* is not |
| 4 | 1775 / 1776 | AD-12's bind-path timeout stance is amended by D-17, **with the carve-out that preserves the original reason** — nothing is sent on any timeout path, so no dialog is withdrawn from under a user. Leaves the real-session behaviour owed |
| 5 | 1780 / 1781 | `_closeSessionBeforeRebinding`'s `Session.Close` is still unbounded, deliberately: bounding it would break the one-`Close`-in-flight invariant. **Filed at plan 01-05's explicit request** |
| 6 | 1785 / 1786 | The measured-facts index for the two deleted files, recording **where each of the four facts now lives** — two re-homed into `x11_key_grab_registrar.dart:44-69`, one still in-tree at `hotkey_key_catalogue.dart:8-12`, one carried in DW-42's own resolution |
| 7 | 1790 / 1791 | The Phase-7 AD-9/AD-11 hand-off **correction**: shipped names, current spine addresses, edit 4's wording corrected (`const` was *dropped*, not kept), and edit 4's non-ratification stated |

---

## Deviations from Plan

### 1. [Rule 2 — missing critical] Seven new entries filed, not five; two verify gates are consequently wrong by two

- **Found during:** Task 2, while checking the plan's `must_haves.truths` against the entries the plan's `<action>` enumerates.
- **Issue:** The plan's action text enumerates five new entries (one in Task 1, four in Task 2) and its verify gate requires `grep -c '^  summary:'` to be **exactly 4 higher** after Task 2 and 5 higher across the plan. Two owed items fall outside that enumeration:
  - The plan's own `must_haves.truths` requires *"Every AD-9 declaration edit this phase made is recorded in the ledger for Phase 7's spine reconciliation"*, and the orchestrator's brief states this plan owns that entry. Plan 01-01 **had already filed** such an entry (ledger 1741 pre-plan) — but in *prediction* form, before any code existed, and its edit-4 wording ("gains a defensively-copied or unmodifiable `modifiers` **behind its `const` constructor**") is now **false**, as is its implication that both fresh-ratification gates were answered by a human. Rewriting it is forbidden.
  - Plan 01-05's SUMMARY says in terms: *"Plan 01-10 has two entries to file, not one. The `NameOwnerChanged` re-registration defect the plan already names, and the unbounded rebind `Close`."*
- **Fix:** filed both as additional open entries (ledger 1780 and 1790). The correction entry names its corrections rather than editing the prediction.
- **Verification:** actual `^  summary:` delta is **+6 after Task 2, +7 across the plan** (111 → 118). Every other gate passes as written.
- **Why not fewer:** filing four would have satisfied a gate by losing owed work — the exact failure the append-only ledger exists to prevent.
- **Commit:** `12d8ac6`

### 2. [Observation, not a fix] FLAT-04's site count was stale in both directions; the measured figure is 13

- **Found during:** Task 2.
- **Issue:** The plan's action text instructs the resolution to *"Record the count correction: … the re-count this phase found **14** real construction sites, the other six being the declaration, two pattern matches and three unrelated `setHotkeyUnavailable` hits."* That 14 is itself stale: plan 01-04's SUMMARY reports **13**, because plan 01-03's atomic rebind swap collapsed one of `x11_global_hotkey.dart`'s refusal branches before 01-04 ran.
- **Fix:** re-measured 2026-09-02 rather than trusting either number. `grep -rn 'HotkeyUnavailable(' lib/` excluding `setHotkeyUnavailable` returns **16** occurrences; subtracting the declaration (`hotkey_bind_outcome.dart:86`) and two pattern matches (`hotkey_status_view.dart:86`, `settings_screen.dart:144`) gives **13** real construction sites. The resolution records 13 and names all three moved figures (20 / 14 / 13) so nobody reconciles them again.
- **The sibling entry keeping the 20 was not touched** — it is outside this plan's scope and the append-only rule covers it.
- **Commit:** `12d8ac6`

### 3. [Rule 3 — blocking] `.planning/WINDOWS.md` was internally inconsistent and would have destroyed a record from plan 01-09

- **Found during:** the SUMMARY step, when `gsd-tools windows append` refused with *"Ledger table … disagrees with the fenced JSON entries (the sole source of truth) for row id(s): 18."*
- **Issue:** plan 01-09 filed two ledger records but only one reached the fenced JSON. Row 18 of the *rendered table* held an `unrun-verify` ("HOTKEY-09's mutation guarantee is proven only in-process…") that **did not exist in the JSON at all**. The tool's own remedy — "discard the table edit and re-run the command so gsd-tools regenerates the table" — would have deleted that record permanently.
- **Fix:** re-filed the orphaned record into the JSON as id 19, preserving its text, kind, file and original `recorded_at`, with a note that it was recovered; corrected the frontmatter counts; regenerated the table from the JSON so all 19 rows render; then appended this plan's two deviations (ids 20, 21). **Nothing was deleted.** Both of plan 01-09's records now survive.
- **Verification:** `grep -c 'mutation guarantee is proven only in-process'` → 2 (JSON + table); ledger now 21 entries, table 21 rows, counts consistent, `windows append` succeeds.
- **Commit:** metadata commit.

**Total deviations:** 3 (1 scope addition under Rule 2, 1 measurement correction, 1 blocking-issue fix under Rule 3). **Impact:** two of the plan's ten verify gates report numbers other than the ones the plan predicted, both declared above with the corrected figures. No ledger content was lost in any of the three, and no code was touched.

---

## Substituted / augmented verification — declared, not reported as passes

Following this phase's carry-forward rule (single-line greps have been structurally inadequate five times), every gate was checked for sufficiency before a closure rested on it.

| Plan gate | Verdict | What was actually run |
|---|---|---|
| `awk 'NR>=1480 && NR<=1495' … \| grep -c '^  status: done'` | **Substituted** — the plan's line range is a stale snapshot and by Task 1 the entry had moved. | Located FLAT-11 by unique content anchor (`  summary: The envelope's re-measure trigger for the \`libkeybinder\` hardness claim`), asserted the anchor matches **exactly once**, then counted `^  status: done` and `^  resolution:` in a window around the *found* line. Both → 1. |
| `grep -c '^  summary:' …` must be exactly 4 higher | **FAILS as written; corrected figure declared.** | Actual +6 after Task 2, +7 across the plan (111 → 118). See Deviation 1. |
| `git diff --numstat` deletions ≤ 8 (Task 2) / ≤ 9 (plan) | **Pass, and strengthened.** A numstat count cannot show *which* lines went. | Additionally listed every removed line: `git diff \| grep '^-[^-]'` yields exactly nine lines across both commits, all of them `status: open`. Then compared the *multiset of every `status:` line* before and after: only the four canonical and five flat closures moved; every other status bucket is byte-identical. That is the check that actually proves append-only compliance. |
| `awk 'NR>=790 && NR<=830' … \| grep -c 'done 2026-08-14'` ≥ 2 | **Substituted** — the range had shifted by Task 1 and Task 2's own insertions. | Located DW-42 and DW-43 by heading and read their status lines directly: both `status: done 2026-08-14`, now at ledger 803 and 813. |
| `grep -c '^status: done'` at least 4 higher | **Pass.** | 65 → 69. |
| `git status --porcelain _bmad-output/planning-artifacts/` empty | **Pass, and strengthened.** | Also `git diff --name-only` over both task commits → the ledger file **only**, and `-- '*.dart'` → zero files. |
| `grep -c 'hotkey_manager' pubspec.lock` → 0 | **Pass.** Checked *before* the dissolution claim was written, as the threat register requires. | 0. |
| Suites and `test(` count unchanged | **Pass.** | Measured after Task 1: `dart analyze --fatal-infos` → *No issues found!*; `dart test` → **960 passed / 2 skipped**; `flutter test` → **165 passed / 7 skipped**; `grep -r 'test(' test/ \| wc -l` → **983**. All four match the phase baseline. Task 2 changed zero `.dart` files (verified by `git diff --name-only … -- '*.dart'`), so the measurement remains valid — stated this way rather than re-reported as a fresh run. |

**One gate the plan asked for that could not be run as an independent check:** the acceptance criterion `grep -A 2 '^### DW-39' -n` "shows the decision line still present and unmodified". A two-line window after the heading shows `origin:`, not `decision:` — the entry is 9 lines long. Checked properly instead: DW-39's `decision:` line is the second line after its new `status:`, and `git diff … | grep -c '^-decision:'` → **0** across both commits, alongside 0 for `^-reason:`, `^-evidence:` and `^-  summary:`. No `decision:`, `reason:`, `evidence:` or `summary:` line was removed anywhere in the file.

---

## Owed verifications, collected and left OWED

This plan closed no verification. Everything below stays owed and is recorded in the closure text of the entry it belongs to, in `.planning/WINDOWS.md`, or in a new open entry.

| Owed item | From | Where it now lives |
|---|---|---|
| The end-to-end refusal observed through the settings screen on a real session with a StatusNotifier host | 01-02 | DW-39's resolution; WINDOWS ids 1-2 |
| All three `HotkeyUnavailableCause` values observed live — `keyRefused` needs a second X client through a real Settings interaction; `noBackend` and `revoked` need real sessions | 01-04 | FLAT-04's resolution; WINDOWS |
| Real-session portal behaviour: a Flatpak bind with no `Register` on the wire; a dialog surviving after the app stops waiting; a late `Allow` producing a press plus `ShortcutsChanged` | 01-05 | new entry 1775; WINDOWS |
| `_closeSessionBeforeRebinding`'s `Close` is **still unbounded, deliberately** — bounding it breaks the one-`Close`-in-flight invariant | 01-05 | **new entry 1780** (filed at 01-05's request) |
| The `NameOwnerChanged` re-registration defect — **explicitly scoped out**, not fixed; `grep -rc 'NameOwnerChanged' lib/` → 0 | 01-05 / research Open Q4 | **new entry 1765** |
| Three human checks on the description rendering; `ListShortcuts` **unexercised** because the fake portal always sends a description | 01-06 | DW-66's resolution; WINDOWS |
| The read-only-while-binding row (an X11 grab resolves in microseconds and there is no portal here); `F1`-`F4` never exercised on a real X session | 01-07 | DW-71's resolution; WINDOWS |
| A mid-`BindShortcuts` compositor change (no portal here); on X11 the guard is structurally inert | 01-08 | FLAT-03's resolution; WINDOWS |
| HOTKEY-09's mutation guarantee proven only in-process | 01-09 | WINDOWS id **19** — recovered this plan; it existed only as a table row |
| **Nothing owed** | 01-09 (otherwise) | — |

### The two flagged assumptions, recorded at their true strength

- **A3 (AltGr surfaces as `altRight`/`altGraph`)** — **SETTLED** by plan 01-07's live observation against a real daemon on `Xvfb :78`, driven with `xdotool` and read off screenshots. Six of seven human checks were genuinely observed in that session.
- **A4 (a held X11 passive grab cannot be re-captured by the focused window)** — **MEASURED, WITH A STATED SCOPE LIMIT. Not "verified on a real desktop."** The orchestrator reproduced it 2026-09-02 against a private `Xvfb :78` with three X connections plus an ungrabbed control: while the grab is held, the focused window receives `Ctrl↓ Shift↓ Shift↑ Ctrl↑` and **never** the terminating keycode; the control and post-`XUngrabKey` cases both receive the full sequence. The measurement added a detail the plan did not anticipate — **it is not silence**, which is why the timeout heuristic was rejected and why 01-07's hint must precede the first keypress. **Scope limit: `Xvfb` with synthetic XTEST events, not a physical keyboard under a real window manager.** Grab arbitration is server-side so it should transfer, but real-desktop confirmation remains **owed**.

### Open product question, carried forward and NOT settled

Plan 01-07 narrowed two widget assertions from *"the requested combination appears nowhere on screen"* to *"nowhere in the read-out"*, because the capture control necessarily displays the combination it will request. **If the screen-wide invariant was intended, that needs a product answer.** This plan carries it forward unchanged; it is not a defect and it is not decided.

---

## Known Stubs

None. This plan modified one markdown ledger and the tracking files. No code, no placeholder, no unwired data source.

---

## Threat Flags

None. No new network endpoint, auth path, file-access pattern or schema change. The register's own `T-01-53` records resolution text as low-severity/accept: file:line evidence and command output only, no user text, credential or clipboard content.

The register's three `mitigate` dispositions were each carried:

- **T-01-50 (tampering, append-only contract)** — bounded by the nine-line deletion audit *and* by the status-line multiset diff, plus confirmation that DW-42 and DW-43 kept their original dates.
- **T-01-51 (repudiation, a resolution contradicting its own decision)** — both supersessions stated in words with the reason, both original texts byte-identical: DW-39's keybinder route and DW-71's per-display-server difference.
- **T-01-52 (repudiation, a fabricated closure)** — `grep -c 'hotkey_manager' pubspec.lock` was run **before** the dissolution claim was written, and the closure states that no re-keying was possible and why.
- **T-01-54 (a flat entry at the wrong indent)** — every flat closure and all seven new entries verified at exactly two spaces by indent-scoped counts, not by review.

---

## Files Created/Modified

- `_bmad-output/implementation-artifacts/deferred-work.md` — the only file the two tasks touched. 53 insertions, 9 deletions; 1749 → 1794 lines.
- `.planning/WINDOWS.md` — a recovered record (id 19), two new deviations (ids 20, 21), corrected counts, regenerated table.
- `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` — position, metrics, two decisions, one blocker, HOTKEY-10 marked complete.
- **Not touched:** `ARCHITECTURE-SPINE.md`, any `.dart` file, `pubspec.yaml`, `pubspec.lock`, DW-42, DW-43, and every ledger entry outside this plan's nine.

## Task Commits

1. **Task 1: Close HOTKEY-10 with the dissolution finding, and file the envelope amendment** — `cf1f518` (docs), 1 file, +7/−1
2. **Task 2: Close the phase's other eight entries, and file what this phase deliberately did not do** — `12d8ac6` (docs), 1 file, +46/−8

---

## Final ledger addresses for Phase 7

Line numbers **as of this commit** — they will move again as entries are closed. Locate by heading or by `summary:` opening words, never by these offsets.

**Closed by this plan:** DW-39 `766`/status `773` · DW-40 `777`/`783` · DW-66 `1131`/`1137` · DW-71 `1178`/`1184` · FLAT-02 `1443`/`1446` · FLAT-03 `1449`/`1452` · FLAT-04 `1455`/`1458` · FLAT-05 `1461`/`1464` · FLAT-11 `1492`/`1495`.

**New open entries (all `source_spec: .planning/phases/01-hotkey-truth/01-10-PLAN.md`):** `1760` envelope/Stack amendment · `1765` portal re-registration · `1770` AD-10 regime · `1775` AD-12 bind timeout · `1780` unbounded rebind `Close` · `1785` retired measured facts · `1790` AD-9/AD-11 hand-off correction.

**Read together with these three from plan 01-01:** `1736` the `status-type` ratification · `1741` the prediction-form AD-9 hand-off (**superseded on names, addresses and edit 4 by `1790`; both stand**) · `1746` the Flatpak sidecar cost.

## Next Phase Readiness

Phase 01 is complete: 10 plans, 10 summaries, all ten requirements closed. Ready for `/gsd-verify-work 01`.

**What Phase 7 (ARCH-06) inherits, in one place:** four AD-9 declaration edits (`ARCHITECTURE-SPINE.md:246`, `:274-278`, `:280-300`), AD-11 step 1 (`:314`), AD-10's regime rule (`:620`), AD-12's bind-timeout stance, and the envelope/Stack `hotkey_manager` removal (`:583-584`, `:442`, plus `:300`, `:451`, `:498`). **One of those — `:246` — still owes a human answer.**

## Two SDK-computed tracking values that disagree with the disk state — reported, not hand-corrected

Both came out of the sanctioned commands and are left exactly as the SDK wrote them:

- **`STATE.md` reads `Progress: [░░░░░░░░░░] 0%`** while `state.update-progress` itself reported `completed: 10, total: 10`. The bar appears to count phases verified rather than plans summarised, and Phase 01 is not verified yet — so 0% may well be right at project scope. Not hand-edited: the SDK owns that line.
- **`ROADMAP.md` row 231 reads `| 1. Hotkey Truth | 10/10 | In Progress|`** after `roadmap.update-plan-progress 01` reported `summary_count: 10`. The command did not promote the row to `Complete` with a date. Writing `Complete` by hand would assert a phase completion that verification has not granted, which is precisely the overstatement this plan exists to avoid. Left for `/gsd-verify-work 01` to promote.

Also on record, since the commit hygiene rules name them: `.planning/config.json` is left **uncommitted** (an unrelated orchestrator change), and `.claude/`, `.planning/state.json`, `.planning/milestone.lock`, `.planning/research/.cache/*` and the new `.gsd/dispatch-isolation-sentinel.json` (runtime harness state) are all left untracked.

## Self-Check: PASSED

- `[ -f .planning/phases/01-hotkey-truth/01-10-SUMMARY.md ]` → FOUND
- `[ -f _bmad-output/implementation-artifacts/deferred-work.md ]` → FOUND
- `git log --oneline --all | grep cf1f518` → FOUND
- `git log --oneline --all | grep 12d8ac6` → FOUND
- Nine closures located by unique content anchor, each `status: done 2026-09-02` with `resolution:` immediately beneath at the entry's own indent → VERIFIED
- Exactly nine deleted lines across both commits, all `status: open`; no other `status:` bucket changed → VERIFIED
- `git status --porcelain _bmad-output/planning-artifacts/` → empty → VERIFIED
