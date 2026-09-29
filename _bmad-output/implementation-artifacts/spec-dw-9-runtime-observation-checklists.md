---
title: 'Runtime observation checklists for the claims this container cannot observe'
type: 'chore'
created: '2026-08-14'
status: 'done'
baseline_revision: '45713783498eaf7f2e9e056a324140978ba13246'
final_revision: 'db803bc'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
warnings: [oversized]
---

<intent-contract>

## Intent

**Problem:** Five ledger entries (DW-9, DW-25, DW-26, DW-44, DW-87) each owe a runtime observation that this container cannot make — there is no compositor, no `xdg-desktop-portal`, no session bus and no reachable X display — and today the only record of what is owed is prose scattered across six skipped `fail()` rows, which tells nobody standing at a real desktop what to actually do.

**Approach:** Commit two manual procedures under `test/platform/`: one session checklist enumerating every claim the enumerated entries owe with an expected result per step, and one desktop-entries procedure covering DW-87's four facts. Pin both by an architecture test so a rename or a dropped claim fails a run, and point each skipped row at the procedure that carries its claim.

## Boundaries & Constraints

**Always:**
- Every step states a concrete action and an expected result a reader can compare against, plus the DW id it settles.
- Both procedures are prose-and-checkbox Markdown a human executes; nothing in them runs unattended.
- The checklists carry only claims the enumerated entries own; a claim the enumeration does not name is listed under an explicit "Not covered here" heading rather than silently absorbed.
- Existing skip-reason prose is extended by pointer clauses, never rewritten or shortened.
- The pinning test uses `package:test` (not `flutter_test`), so it runs under the CI gate's `dart test --exclude-tags=live`.

**Block If:**
- Closing a step would require choosing a panel size, a position, or a `meta`-modifier remedy — those are decisions the observation exists to inform, not to make. Record the observable; do not pick.

**Never:**
- Build a headless harness, an `Xvfb` shim, or any automated substitute for a real session. Three stories have tried; this container has no display to stand up.
- Edit `{implementation_artifacts}/deferred-work.md` — the orchestrator records resolution.
- Change production code under `lib/`, `linux/`, or `tool/`. This is documentation plus one pin test.
- Give any skipped `fail()` row a passing body, or weaken a skip so it could report a claim as met from here.
- Add tray claims (`test/platform/tray_live_test.dart`) to either checklist — they belong to an entry outside this bundle.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Both procedures present and complete | Tree as committed | Pin row passes; run output names both procedure paths | No error expected |
| A procedure is renamed or deleted | `runtime-observation-checklist.md` missing | Pin row fails naming the missing path | Failure reason states which procedure vanished |
| A claim is dropped from a procedure | `DW-25` no longer appears in the session checklist | Pin row fails naming the absent id | Failure reason lists the ids expected and the ids found |
| A skipped row loses its pointer | `x11_hotkey_live_test.dart` no longer names its checklist | Pin row fails naming that suite | Failure reason states which suite lost its pointer |

</intent-contract>

## Code Map

- `test/platform/runtime-observation-checklist.md` -- NEW. The one session procedure: DW-9 startup/residency/second-launch, DW-26 visible-and-focused plus focus-loss hide, DW-25 echo ordering into Dart, DW-44/DW-39 real grab, 100 ms summon, live rebind, GTK-main-thread marshalling, DW-50/DW-72 geometry and settings affordance.
- `test/platform/desktop-session-checklist.md` -- NEW. DW-87's four desktop facts: install the entries, press the hotkey, log out and back in, launch a second copy by hand.
- `test/architecture/runtime_checklists_test.dart` -- NEW. Pins both procedures' existence, the DW ids each must name, and the pointer clause in each skipped row. Prints the two paths so a green run says where the owed work is written down.
- `test/architecture/hidden_window_test.dart:283-298` -- the DW-9 skipped row; gains a pointer clause.
- `test/platform/panel_visibility_live_test.dart` -- DW-25/DW-26 skipped row; gains a pointer clause, and its stale "no keybinder-3.0" claim is corrected (`pkg-config --modversion keybinder-3.0` answers 0.3.2 here — story 7 disproved it by measurement).
- `test/platform/x11_hotkey_live_test.dart` -- DW-44 skipped row; gains a pointer clause.
- `test/platform/correction_panel_live_test.dart` -- carries the DW-50 geometry claim; gains a pointer clause.
- `test/platform/settings_screen_live_test.dart` -- carries the DW-72 affordance claim; gains a pointer clause.
- `test/platform/desktop_entries_live_test.dart` -- DW-87 skipped row; gains a pointer clause to the desktop procedure.
- `test/architecture/desktop_entries_test.dart:570-603` -- the house pattern this follows (print the owed claims, assert the pointed-at file exists); its print block gains the desktop procedure's path.
- `lib/src/infrastructure/system/single_instance_lock.dart` -- source for the second-launch expected result (holder is signalled, the launch exits 0; the address derives from `XDG_RUNTIME_DIR`, never from `Exec`).
- `tool/install_desktop_entries.sh` -- the install step of the desktop procedure, including `--exec`.

## Tasks & Acceptance

**Execution:**
- `test/platform/runtime-observation-checklist.md` -- write the session procedure: a preamble stating it is manual, and stating directly the rule that an unobserved claim is recorded as unobserved (do **not** cite "AGENTS.md §8" for it — §8 is "Never do this" and carries no such rule; no section does), prerequisites (a real X11 session for the grab rows, a GNOME/Wayland session for the portal rows, `flutter build linux --debug` and the resulting binary path), then numbered steps grouped A–E, each with action, expected result, DW id, and what to write down when it diverges; close with a "Not covered here" heading naming `tray_live_test.dart` and a results-recording template -- one procedure rather than a second harness, per DW-9's 2026-08-14 decision.
- `test/platform/desktop-session-checklist.md` -- write DW-87's four-fact procedure: install via `tool/install_desktop_entries.sh --exec <built binary>`, confirm the compositor associates the registered app id with the installed entry, confirm the bind survives *because of* it (the observable is that removing the file discards the bind — a bind that works either way proves nothing), log out and back in for autostart, then launch a second copy by hand -- the runtime half `desktop_entries_test.dart` can only check as bytes.
- `test/architecture/runtime_checklists_test.dart` -- add the pin rows from the I/O matrix and a `print` naming both procedure paths -- mirrors `desktop_entries_test.dart`'s existing "make the gap visible where the green is" row.
- `test/architecture/hidden_window_test.dart`, `test/platform/{panel_visibility,x11_hotkey,correction_panel,settings_screen,desktop_entries}_live_test.dart` -- append a pointer clause naming the procedure that carries each row's claims, and in `panel_visibility_live_test.dart` only, correct the stale "no keybinder-3.0" clause -- a reader who hits a skipped row finds the procedure instead of prose alone.

**Acceptance Criteria:**
- Given a reader at a real Linux desktop with only this repo, when they open `test/platform/runtime-observation-checklist.md`, then every claim DW-9, DW-25, DW-26, DW-44 and DW-87's siblings owe appears as a numbered step with an expected result and the DW id it settles.
- Given the session checklist, when a reader looks for tray claims, then a "Not covered here" heading names `test/platform/tray_live_test.dart` and states that its claims belong to another entry.
- Given the suite, when `dart test test/architecture/runtime_checklists_test.dart` runs, then it passes and its output names both procedure paths.
- Given either procedure is renamed, a DW id is dropped from it, or a skipped row loses its pointer clause, when the suite runs, then that pin row fails naming the specific path, id, or suite.
- Given the six skipped rows, when the suite runs, then each still fails-by-`skip` exactly as before and none has gained a body.
- Given `dart test --exclude-tags=live` and `flutter test test/platform test/ui`, when run after the change, then the pass/skip counts match the pre-change baseline plus the new pin rows.

## Spec Change Log

No bad_spec loopback occurred. One correction was made to the `## Verification` section during step 3: it named the bare `dart test --exclude-tags=live`, which cannot run in this repo at all — its glob reaches the `test/platform` suites that import `flutter_test` and the compiler fails to load 68 files. Replaced with the scoped form `.github/workflows/ci.yml:102-105` actually runs, plus the baseline tally to compare against.

## Review Triage Log

### 2026-08-14 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 25: (high 0, medium 10, low 15)
- defer: 3
- reject: 5
- addressed_findings:
  - `[medium]` `[patch]` Both new procedures, the new print row, and the `hidden_window_test.dart` / `panel_visibility` / `x11_hotkey` skip reasons asserted the container has no `Xvfb`/`xvfb-run` and no window enumerators, and that "there is nothing to automate against". Measured: `Xvfb`, `xvfb-run`, `xwininfo`, `xdotool` and `xprop` are all present; only `wmctrl` and `desktop-file-validate` are absent. Corrected everywhere to the ground the ledger's own DW-87 decision uses — a display can be stood up here, a *session* cannot — so the refusal to build a harness now rests on a true premise. No harness built; the intent forbids one.
  - `[medium]` `[patch]` `test/architecture/desktop_entries_test.dart` was the seventh pointer site and was absent from `_pointers` while its new const's doc comment claimed to be pinned; now pinned by value against `_desktopChecklist.path`.
  - `[medium]` `[patch]` The "names the claims" rows were satisfied by each procedure's own header line alone, so every step could be deleted and they would stay green. Now scoped to per-step `*Settles:*` lines, plus a row asserting no step lacks one.
  - `[medium]` `[patch]` The pointer rows matched the whole file source while their failure text promised the skip reason; the `skip:` argument is now extracted and matched.
  - `[medium]` `[patch]` Step numbers — the load-bearing half of every pointer clause — were pinned nowhere. A `_citations` table now pins each cited number against the procedure's step headings and against the id that step's `*Settles:*` line carries.
  - `[medium]` `[patch]` `settings_screen_live_test.dart` claimed accessibility (its claim 6) was named under "Not covered here"; it was not. Bullet added.
  - `[medium]` `[patch]` The desktop checklist's portal steps 2–3 had no Wayland gate, so an X11 run would manufacture a false "AD-11's premise does not hold" finding. Gated, and every step in both procedures gained an `*Applies to:*` line.
  - `[medium]` `[patch]` Step 3 moved a live desktop entry out of the operator's real session with no mandatory restore, and cleanup never mentioned the displaced copy. Now a named backup directory, a non-optional restore with an abort instruction, and a cleanup that restores first.
  - `[medium]` `[patch]` The session checklist mutated a desktop shortcut, the app binding, the config file and the text scale with no "Cleaning up" section. Added.
  - `[medium]` `[patch]` The prerequisites contradicted themselves on Wayland versus X11 enumerators. Resolved per step.
  - `[low]` `[patch]` Fifteen further corrections: the 100 ms half routed to step 12; step 2's window-title grep matching both spellings the code sets; the logout count; step 9's two halves given their own recording block; the `risks.md` path; a "no daemon already running" guard on step 1; step 9's desktop-level binding released before step 10; step 12's warm-sample ordering against the restarts in steps 9–11; step 14's reseeded binding; the surviving "no keybinder" claim in `settings_screen_live_test.dart`; the misquoted CI gate in the pin suite's doc comment; the hardcoded DW list beside an interpolated one; `int.tryParse` and authored existence checks in the pin test; DW-53 named under "Not covered here"; and step 13 extended to observe the settings screen at the measured geometry.

### 2026-08-14 — Review pass (follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 27: (high 2, medium 20, low 5)
- defer: 3
- reject: 9
- addressed_findings:
  - `[high]` `[patch]` Every `pgrep -a hotkey_grammar_corrector` in both procedures (7 sites) can never match anything: Linux truncates a process name to 15 characters and the name is 24, so `pgrep` prints a warning and exits 1. Verified in-container. Session step 1's "must print nothing" guard therefore always passed, and desktop steps 4 and 5's "finds exactly **one** process" was unsatisfiable — an operator on a healthy machine would have recorded a false autostart failure against DW-87 fact 3. All sites now use the truncated `pgrep -a hotkey_grammar_`, with a prerequisites note explaining why it must not be "corrected" back.
  - `[high]` `[patch]` `pkill -f hotkey_grammar_corrector` (4 sites, one of them session step 1's very first instruction) kills the operator's own tooling: `-f` matches whole command lines and `pubspec.yaml`'s package name makes the clone directory `hotkey_grammar_corrector`, so every editor, `dart test` and shell in the repo carries the string. Reproduced — the command killed the shell that ran it. All sites now use `pkill hotkey_grammar_`, which matches the process name only.
  - `[medium]` `[patch]` Desktop step 3 hardcoded `~/.local/share` where step 1 installs under `${XDG_DATA_HOME:-…}`. With `XDG_DATA_HOME` set the `mv` fails, the entry is never removed, the panel appears at 3.4, and the step's own text tells the reader to record "AD-11's premise does not hold" — the exact false finding the Wayland gate was added to prevent, reached by another route. Now expanded consistently, with a mandatory post-`mv` confirmation that the removal (the actual observable) happened.
  - `[medium]` `[patch]` Session step 14 said "start the daemon" without stopping the one step 12 leaves resident for an hour. AD-14's lock makes that a no-op that signals the running process, which still holds steps 10–11's rebind in memory (AD-13: nothing watches the config), so Ctrl+Shift+G does nothing and DW-50's placement is recorded as a false negative. Now opens with a stop-and-confirm and says why.
  - `[medium]` `[patch]` Group D left the hotkey rebound and steps 11, 12 and 13 named no combination to press — step 14, three steps later, is what restores the shipped one. Step 11 also said "repeat step 10's rebind", which after one iteration rebinds Ctrl+Alt+Y to itself. Now alternates two combinations and each later step says to press whichever is currently bound.
  - `[medium]` `[patch]` The prerequisites contradicted the per-step `*Applies to:*` lines: step 5 was listed X11-only while its own line says both, group B's only step is marked both, and steps 13/15/16 each supply a Wayland substitution. A Wayland operator would have skipped three of the seven claims. Rewritten to claim only what is true (group D is X11-only because keybinder grabs on X) and to name the per-step line as authoritative.
  - `[medium]` `[patch]` Desktop step 4 required "the tray indicator is present" on the GNOME **Wayland** session its own prerequisites mandate, where stock GNOME hosts no StatusNotifier without the AppIndicator extension — so a healthy daemon produces a DW-87 fact-3 divergence caused by GNOME. Demoted to optional evidence and removed from the failure taxonomy.
  - `[medium]` `[patch]` Desktop step 2 had no "nothing already running" guard, immediately after step 1 installs an autostart entry; the lock would have had the operator inspecting a process they did not start. Guard added.
  - `[medium]` `[patch]` The session checklist's "Not covered here" described DW-53 as "owned outside this bundle. Do not record it as settled", implying it is owed; it was closed on 2026-08-14 alongside DW-50. Corrected to say it is closed and that a run neither settles nor reopens it.
  - `[medium]` `[patch]` Step 7 (DW-25) can only **falsify** the echo ordering — "the panel ends hidden" is equally what a run where the race never occurred looks like — yet the results table offered a plain yes/no and one pass would have read as confirmation. Now requires ten repetitions on both the `xdotool` and manual paths, and the table records "not reproduced in N attempts" rather than a tick.
  - `[medium]` `[patch]` The pin suite's claim check was a subset check on DW ids, so any step whose id another step also settles could be deleted while green. Mutation-confirmed for session steps 14 and 16 and desktop step 1. Each procedure now pins its full step-number set.
  - `[medium]` `[patch]` Nothing asserted the six rows still have `fail()` bodies, though the spec's Never list and AC #5 both rest on it. Mutation-confirmed: replacing a body with a passing one left all rows green, and CI never executes those suites. A row per suite now asserts the `fail(` call and exactly one `skip:`.
  - `[medium]` `[patch]` The "Not covered here" heading was pinned nowhere, though four skip reasons route claims to it by name and it is the mechanism the scope rule uses. Mutation-confirmed: deleting the whole section left all rows green. Now pinned per procedure, including the specific artifacts each must keep naming.
  - `[medium]` `[patch]` `_skipReasonIn` fell back to the rest of the file when its `\n  );` terminator was absent — silently widening every pointer match into the whole-file `contains` its doc comment says it avoids. Widening never turns a row red; it now returns empty so the row fails instead.
  - `[medium]` `[patch]` `_ledgerIdsIn` counted a **negated** id: desktop step 1's "Not itself one of DW-87's four facts" registered as settling DW-87, so the whole desktop procedure was satisfiable by the one step that settles nothing. An explicit `none` marker now opens the disclaiming form; mutation-confirmed by stripping DW-87 from steps 2–5.
  - `[medium]` `[patch]` `_expandStepList` treated `-`, `–` and `—` as range operators, so a reworded `step 12 — the 100 ms budget` would have parsed as steps 12 through 100. Two existing clauses sit one em dash away from this. Dashes dropped as separators (no clause needs them; `to` is unambiguous), and descending ranges now keep both endpoints instead of swallowing one.
  - `[medium]` `[patch]` `_stepsIn` merged duplicate step numbers via `putIfAbsent`, so inserting a step without renumbering — the precise drift the citation table exists to catch — passed silently. Duplicates now fail their own row.
  - `[medium]` `[patch]` `_stepsIn` read only the first line of a `*Settles:*` bullet; the desktop procedure already has a wrapped one, and any reflow would have dropped an id. Continuation lines are now accumulated.
  - `[medium]` `[patch]` Claim checking was one-directional, so a step could absorb a claim the enumeration does not own — the containment rule the intent states. Now checked both ways.
  - `[medium]` `[patch]` The `desktop_entries_test.dart` constant was matched with a raw regex while the six pointer rows join adjacent literals first, so a longer filename plus `dart format` would report drift that a correct rename did not cause. Now joined the same way.
  - `[medium]` `[patch]` The run-output print listed DW-39 among the claims the session procedure carries, but its step 11 applies only to a `dart:ffi` keybinder registrar that no build in the tree has. The print now states that a completed run does not settle it.
  - `[medium]` `[patch]` Roughly 25 step references *inside* the two procedures (prerequisites, group preambles, cleanup, "Not covered here", the results tables) were pinned by nothing, though the suite's own doc comment names renumbering as the fastest kind of rot. A row now resolves every internal reference against the procedure's steps.
  - `[low]` `[patch]` Session cleanup items 2 and 3 undid each other — rebind through the settings screen, then restore the config backup over it. Reordered into one action with the restore first; the item count and its confirmation line corrected from four to three.
  - `[low]` `[patch]` The desktop checklist's emergency restore ran `mv` without `update-desktop-database`, unlike step 3.5's — and that path runs after an abandoned run, exactly when a stale cache is the failure mode step 3 studies. Refresh added, and every cleanup path now expands `XDG_DATA_HOME`/`XDG_CONFIG_HOME` instead of carrying a caveat about them.
  - `[low]` `[patch]` Both new procedures opened by citing "AGENTS.md §8" for the rule that an unobserved claim is stated as unobserved. §8 is "Never do this" and carries no such rule; no section does. Both now state the principle directly. The six pre-existing suites that carry the same false citation are deferred — repo-wide.
  - `[low]` `[patch]` The `meta`-modifier claim parked in DW-44's own entry — the third of the three hazards the intent's Block If names by hand — was neither a step nor an exclusion. Added under "Not covered here" as deliberately absent, since closing it would mean picking a remedy.
  - `[low]` `[patch]` The Verification section required the gate's failure count to "stay at exactly one". Measured over nine runs, it is non-deterministic between 0 and 4 and never was one reliably — `dart_test.yaml` sets `concurrency: 1`, so any row-count change reshuffles the ordering DW-46's flake depends on. Replaced with the criterion that actually discriminates: the row total must reconcile to 838, every failure must be in one of DW-46's two named suites, and no `test/architecture` row may fail. Applied as a patch rather than a bad_spec loopback because no code follows from it — the criterion was wrong, the implementation was not.

### 2026-08-14 — Review pass (third)

- intent_gap: 0
- bad_spec: 0
- patch: 33: (high 4, medium 22, low 7)
- defer: 2
- reject: 5
- addressed_findings:
  - `[high]` `[patch]` The two rows guarding the six skipped `fail()` bodies were whole-file substring searches, so they could not tell a live unconditionally-skipped row from a neutered one. Three mutations proved it, each leaving all rows green and `dart analyze --fatal-infos` clean: block-commenting the entire DW-9 row out of `hidden_window_test.dart`; replacing a body with `expect(true, isTrue)` while `// fail(` survived in a comment; and putting the skip behind `bool.fromEnvironment` so the row runs and *passes* when the variable is set — that last one reported DW-87's four unobserved facts as met. Comments are now stripped before every check, the `skip:` argument must be a plain string literal, and `fail(` is resolved inside the enclosing `test(` call rather than anywhere in the file (`hidden_window_test.dart` holds fourteen rows against one `fail(`, so the whole-file form was one unrelated `fail()` away from vacuous).
  - `[high]` `[patch]` Session step 7 — the DW-25 echo-ordering step, the one the previous pass singled out for falsification discipline — was inverted. Its action started from a summoned (visible) panel and pressed the hotkey twice; `onHotkeyActivated` is a strict toggle over a mirror that `show`/`hide` set synchronously before enqueueing, so the pair is hide-then-show and a healthy build ends **visible**, while `*Expected:*` said "ends hidden, on all ten". An operator on a sound machine would have recorded ten divergences on a step whose own text says a single divergence is decisive. Worse, the superseded request was the *hide*, and the step's own rationale is about a superseded **show**. Now starts from a confirmed-hidden panel, states why the starting state decides which direction is exercised, and moves the tell to a fresh-session or clipboard line logged after the panel is down — the editor's contents cannot serve, because AD-18 clears on every legitimate show.
  - `[high]` `[patch]` Session step 13 told the operator "nothing predicts a number here — no code sets a size, a minimum size or a position", and "*If it diverges:* there is nothing to diverge from". `linux/runner/my_application.cc:50` calls `gtk_window_set_default_size(window, 1280, 720)` unconditionally, and nothing on the Dart side overrides it. The one measurement DW-50 waits for was framed as having no prediction, and the most informative possible result — "it is still the Flutter template default" — was the one the step suppressed. Corrected in the step and in the same false clause in `correction_panel_live_test.dart` and `settings_screen_live_test.dart`; the ledger's own DW-50 body carries it too and is deferred.
  - `[high]` `[patch]` Neither procedure mentioned that on Wayland every daemon start raises a portal grant dialog the user must accept, that a dismissed one logs "the compositor did not grant the global shortcut" and leaves the hotkey inactive, or that the combination is the **compositor's** choice — `preferred_trigger` is a hint and the effective combination reads back null by measurement, so the settings screen cannot show it. Both procedures nonetheless told the reader to press "whatever combination the settings screen shows". Desktop step 3.4's expected result is "the panel does not appear", which a dismissed dialog, a refused grant and a wrong keypress all satisfy — so DW-87 fact 2 could be recorded as confirmed on evidence showing nothing. Added to both prerequisites and to step 3's failure taxonomy.
  - `[medium]` `[patch]` Nothing asserted a step still had an `*Action:*`, an `*Expected:*` or an `*Applies to:*` bullet, though the intent's first Always constraint and AC #1 rest on the first two and the prerequisites name the third as authoritative. Mutation-confirmed green: deleting step 5's whole `*Expected:*` bullet, and deleting desktop step 3's `**Wayland only**` gate — the gate the previous pass added specifically so an X11 operator would not manufacture a false "AD-11's premise does not hold". A row now pins all four bullets per step, plus the checkbox.
  - `[medium]` `[patch]` The `*Settles:* none` marker was defeated by the line wrap that kept it passing. `_stepsIn` re-parsed each continuation line as if it were line one, so desktop step 1's wrapped disclaimer ("not itself one of DW-87's four facts") registered as *settling* DW-87 — meaning the whole desktop procedure's claim set was satisfied by the one step that settles nothing. The bullet is now joined before it is read. Fixing it exposed the other half: with the leak closed, the `unattributed` row correctly reported step 1 as carrying no id, so precondition steps are now declared explicitly (`preconditionSteps`) and must still open with `none` — the marker is the difference between "settles nothing on purpose" and "lost its attribution", and an empty set cannot tell them apart. Both directions mutation-gated: a pure reflow onto one line no longer reddens the suite, and a negated id on a continuation line no longer counts.
  - `[medium]` `[patch]` The results tables — the artifact the operator fills in and hands to whoever closes the entries — were pinned by nothing. Mutation-confirmed green: pointing a row at a nonexistent step 99, and reattributing step 5's focus observation from DW-26 to DW-9. A row now asserts one table row per step, no duplicates, and (where the column carries ids) agreement with each step's `*Settles:*` line. The previous pass's triage log claimed the tables were already covered; they were not, because their cells are bare numbers in `|` columns that the prose-oriented parser never saw.
  - `[medium]` `[patch]` The `_citations` check was set-based, so a clause that kept the same step numbers while swapping which claim each one is cited *for* passed — the exact failure the row's own reason promises to catch ("the clause reads correctly and sends the reader to the wrong observation"). Mutation-confirmed on `settings_screen_live_test.dart`. Now compares the ordered sequence, relying on Dart map literals preserving insertion order; the declaration for that suite was reordered to the order its clause actually cites (13, 10, 15 — not ascending).
  - `[medium]` `[patch]` The lettered group headings A–E were pinned nowhere, though two skip reasons navigate by letter and group D's preamble is where the X11-only constraint for the grab steps lives. Mutation-confirmed: dropping the letter from `## D. The real grab` left every row green and stranded both clauses.
  - `[medium]` `[patch]` The "Not covered here" phrase set missed the two bullets three skip clauses route claims to by name — the Wayland-portal bullet (also the session procedure's only mention of `wayland_hotkey_live_test.dart`) and the AD-13 config-watching bullet. Deleting either left the suite green while `settings_screen_live_test.dart` went on asserting its claims (3), (4) and (5) are "named there". The bare substrings `clipboard` and `meta` were also replaced with distinctive phrases; `meta` matched any word containing it.
  - `[medium]` `[patch]` Internal cross-references were checked for existence only. Step 16 — the 1.5x-text-scale repeat, and DW-72's only scaled measurement — says "repeat steps 13 and 15"; rewriting that to "13 and 14" sent the operator to redo the placement step instead of the affordance measurement and stayed green. A row now resolves that reference against what the cited steps actually settle.
  - `[medium]` `[patch]` Two of the eight skipped live suites (`tray_live_test.dart`, `wayland_hotkey_live_test.dart`) were guarded by nothing, and nothing enumerated the directory, so the next live suite added would inherit the same silence. A row now globs `test/platform/*_live_test.dart` and requires every file to be either pinned or listed in `_unpinnedLiveSuites` with a stated reason.
  - `[medium]` `[patch]` Three step-ordering hazards, each verified against production code, where one step left state that made the next record a false observation. Step 4 leaves the panel on screen and step 5 then presses the toggle, hiding it — `HELLO` lands underneath and produces exactly the "on screen but does not hold the keyboard" signature step 5 tells the reader to record as a DW-26 divergence. Step 2's divergence note summons the panel and never dismisses it, and the second launch routes to the non-toggling `showPanel()`, so step 4's only observable is satisfied by a panel already up and no transition is witnessed. Desktop step 3 moved a live desktop entry out of the operator's real session at 3.3 even when 3.1 showed no working bind — all cost, no observation. Each step now opens with the state it requires, and the two whose symptom is indistinguishable from the real defect say so.
  - `[medium]` `[patch]` The prerequisites asked for one config backup and step 14 took a second into the same unnamed slot, while cleanup restored "the" backup and promised "there is nothing further to do" — leaving the machine on steps 10–11's rebind while reporting itself restored. Now two named destinations (`config.json.pre-run`, `config.json.step14`), a slot for each in the recording template, and a cleanup that names the pre-run one.
  - `[medium]` `[patch]` Step 12 was gated three incompatible ways: group D's preamble said "X11 only, every step", the prerequisites said "an X11 session for group D (steps 8 to 12)", and step 12's own `*Applies to:*` said the claim is owed on Wayland too — with the prerequisites declaring the per-step line authoritative. Resolved in favour of the claim: steps 8–11 are X11-only because keybinder grabs on X, step 12 is the latency budget and runs on either session type. Its "check it in the settings screen" advice is now X11-only, since the Wayland effective combination reads back null.
  - `[medium]` `[patch]` Nothing had the operator check that Ctrl+Shift+G was free at the desktop level before starting, though steps 5 and 8 fail silently under such a conflict and step 9 deliberately creates one. Step 9's teardown also only removed "the binding you just added", destroying any pre-existing shortcut. Both fixed.
  - `[medium]` `[patch]` A relative `XDG_DATA_HOME` split the installer from the checklist: `tool/install_desktop_entries.sh`'s `xdg_root` ignores a relative value per the XDG specification and warns, while the steps' `${XDG_DATA_HOME:-$HOME/.local/share}` expansions honour it. Measured. Consequences ran from cleanup silently removing nothing — leaving the autostart entry it exists to prevent — to step 3.3's removal confirmation passing for the wrong reason. Now a prerequisite requiring both variables to be absolute or unset, and step 1 records the three paths from the installer's own `wrote …` lines.
  - `[medium]` `[patch]` `XDG_RUNTIME_DIR` scoping was never checked, though `AppPaths._runtimeDirectory` derives the AD-14 lock address from it. Session step 4 and desktop step 5 both launch "from a second terminal" with no requirement that it belong to the graphical session; an `ssh` or detached `tmux` terminal computes a different address, both processes bind, and the operator records the exact signature of the AD-14 failure the step exists to catch. Both steps now require and record the value, and both divergence notes rule it out first.
  - `[medium]` `[patch]` Step 12's primary suggested method, `ffmpeg -f x11grab`, captures only the screen and so cannot timestamp the key press that starts the interval — a stop with no start, on a step that explicitly requires "the method used to get them". Now either an on-screen press marker (`xev`/`xinput test-xi2`) or the phone-camera path.
  - `[medium]` `[patch]` Step 2's grep pattern `hotkey.grammar.corrector` missed a third title spelling. On the header-bar branch the runner calls `gtk_header_bar_set_title` and never `gtk_window_set_title`, so GTK falls back to the application name, which `g_set_prgname(APPLICATION_ID)` set to `com.divertedriver.HotkeyGrammarCorrector` — and the pattern requires a character between the words. Verified by measurement. That is precisely the case the step is looking for (a startup that never reached Dart), and "no match at all" is its documented pass condition. Now `hotkey.?grammar.?corrector`, with all three spellings and their branches named.
  - `[medium]` `[patch]` `desktop_entries_test.dart`'s print block and `desktop_entries_live_test.dart`'s skip reason both still stated DW-87 fact 3 as "autostart starts the daemon, tray present and hotkey live", while the procedure they advertise demotes the tray to optional evidence — stock GNOME Wayland hosts no StatusNotifier without the AppIndicator extension, so a healthy daemon shows none. Both brought into line.
  - `[medium]` `[patch]` The spec's Verification criterion checked `passed + failed` only, which cannot see a skipped row disappear: with the DW-9 row commented out the gate measured `+825 ~1 -13`, reconciling to the declared total exactly. The criterion now includes the skip count (`~2`) and adds `dart test test/architecture/hidden_window_test.dart` (`+13 ~1`), the only listed command whose scope contains that row — CI runs no `flutter test` at all.
  - `[medium]` `[patch]` Neither procedure contained a single checkbox, against the intent's explicit "prose-and-checkbox Markdown a human executes". A 16-step procedure spanning a login session had no way for a reader to track position. One progress checkbox per step in both files, pinned.
  - `[low]` `[patch]` `(steps 12–16)` resolved to step 12 alone, because dashes are deliberately not range separators — so a reference the suite's own doc comment claims to resolve was half-checked. Reworded to `steps 12 to 16`, the form the parser documents.
  - `[low]` `[patch]` The existence row's failure reason counted only skip reasons, telling a developer chasing a rename that "1 skipped row(s) name it" when three pinned places do. `_pointersTo` now counts the sibling procedure's "Not covered here" route and the `desktop_entries_test.dart` constant as well.
  - `[low]` `[patch]` The repository paths the procedures cite — the installer an operator is told to run, the suites their claims came from, the sibling procedure — were asserted to exist nowhere, which is the same rot the skip reasons had before this file existed. A row now resolves every cited `test/`, `lib/`, `tool/` and `docs/` path.
  - `[low]` `[patch]` `wmctrl` was offered as "an equivalent substitute" enumerator, but it lists `_NET_CLIENT_LIST` and reports no map state, so it cannot distinguish an unmapped toplevel from an absent one — the entire distinction step 2 turns on, where "no match" is the pass condition. Now excluded for step 2 and kept for the window lists in steps 13 and 15.
  - `[low]` `[patch]` Desktop step 4 folded an AD-8 observation ("no window is on screen") into a step whose `*Settles:*` line names only DW-87, while the same file's "Not covered here" routes DW-9's startup claims to the other procedure — the containment rule violated inside one file, invisible to a check that reads `*Settles:*` lines only. Reframed as part of "the daemon came up correctly", with the mapped-window question attributed where it belongs.
  - `[low]` `[patch]` The spec's own Execution task still instructed a future implementer to cite "AGENTS.md §8" for the unobserved-claim rule — the citation the previous pass removed from both procedures as false, and whose six pre-existing instances are a deferred entry. Dropped, with the reason stated inline so it is not re-added.
  - `[low]` `[patch]` The Verification section's failure range said "non-deterministic between 0 and 4"; measured across eleven runs it is 0 to 5. Corrected, and the section now states what it consequently does **not** verify: an unbounded number of failures inside the two DW-46 suites is tolerated, and those two own AD-11's portal handshake and AD-14's lock — the behaviours the desktop procedure exists to observe — so a real regression there satisfies the criterion.

## Design Notes

The intent's language "beside `test/platform/`" is resolved as *inside* it, because DW-87's own decision says "committed next to `test/platform/desktop_entries_live_test.dart`" and that file is in `test/platform/`. Markdown in a test directory is inert to both `dart test` and `flutter test`, so nothing collects them.

Two procedures rather than one because DW-87's four facts need a *login cycle* and a second physical launch — a different session shape from the display-and-grab rows, which run inside one login. Splitting them keeps each runnable start to finish.

The pin test is what keeps a documentation change from rotting silently: `desktop_entries_test.dart` already established the pattern of printing what is unobserved and asserting the pointed-at file exists, and this reuses it rather than inventing a second convention.

## Verification

**Commands:**
- `dart test test/architecture/runtime_checklists_test.dart` -- expected: all rows pass; output names both procedure paths.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: **the row total** reconciles to the pre-change total plus exactly the new pin rows. This scoped form is the command `.github/workflows/ci.yml` runs; the bare `dart test --exclude-tags=live` cannot run in this repo at all, because its glob reaches the `test/platform` suites that import `flutter_test` and the compiler fails to load 68 files. Baseline on `4571378` is 808 rows (`+807 ~2 -1`).

  Check the **total and the skip count**, not the failure count. An earlier revision of this section said the `-1` "must stay at exactly one"; that criterion is false and was never met. The failing rows are `wayland_portal_global_hotkey_test.dart` and `single_instance_lock_test.dart` — the two suites DW-46 names — and the count is non-deterministic run to run because `dart_test.yaml` sets `concurrency: 1` and any change in row count reshuffles the single-process ordering. Measured across passes: `0, 1, 1, 2, 2, 2, 3, 3, 3, 4, 5` failures, including fully green runs. So: **`passed + failed` must equal 847** (808 + 39 pin rows), **the skip count must be exactly `~2`**, every failure must be in one of those two DW-46 suites, and no `test/architecture` row may fail. Current measurement: `+845 ~2 -2`.

  The skip count is part of the criterion because the total alone cannot see a skipped row disappear: commenting out the DW-9 row in `hidden_window_test.dart` measured `+825 ~1 -13`, whose `passed + failed` still reconciled to the declared total exactly. `~` is what moves.
- `dart test test/architecture/hidden_window_test.dart` -- expected: `+13 ~1`. That `~1` is the DW-9 skipped row, and this is the only command in this section whose scope contains it (the five other skipped rows are under `flutter test test/platform`, which the CI gate does not run at all). Without this row, no listed command observes the sixth skipped row directly.

  **What this section does not verify.** "Every failure must be in one of those two DW-46 suites" tolerates any number of failures inside them, and a failing row still counts toward the total — so a genuine regression in `wayland_portal_global_hotkey_test.dart` (AD-11's portal handshake) or `single_instance_lock_test.dart` (AD-14's lock) satisfies both halves of the criterion and is indistinguishable from the flake until DW-46 is fixed. Those are precisely the behaviours the desktop procedure's steps 2, 3 and 5 exist to observe.
- `flutter test test/platform test/ui` -- expected: unchanged pass/skip counts; the six skipped rows still skip and none passes.
- `dart analyze` -- expected: no new diagnostics.
- `pkg-config --modversion keybinder-3.0` -- expected: `0.3.2`, confirming the skip-reason correction is a fact rather than a guess.

**Manual checks (if no CLI):**
- Each numbered step in both procedures states an action AND an expected result; no step ends at "check that it works".
- No step instructs the reader to choose a panel size, position, or `meta` remedy — only to record what is observed.



## Auto Run Result

Status: done
Blocking condition: none

### Summary

A third review pass over the committed DW-9 bundle, and the first to find defects that would have made a real run produce false findings. 33 patches, 4 of them high. The pin suite grew from 30 rows to 39 and now catches ten mutations it previously let through — including the two the intent's Never list names by hand: a skipped row given a passing body (which, with the skip put behind an environment variable, reported DW-87's four unobserved facts as *met*), and a whole skipped row commented out. On the procedure side, the DW-25 step was exercising the opposite of the race it exists to falsify, the DW-50 geometry step told the operator there was nothing to predict when the runner sets 1280x720, and neither procedure mentioned that a Wayland run needs a portal grant dialog accepted and cannot read its own bound combination.

### Files changed

- `test/architecture/runtime_checklists_test.dart` -- 30 rows to 39. Comment-stripping before every liveness check, `skip:` argument-shape checking, `fail(` bounded to the enclosing `test(` call. New rows pin each step's four bullets and its checkbox, the results tables against the steps, the lettered groups A–E, the paths the procedures cite, step 16's load-bearing reference, and the completeness of the live-suite roster. Parser fixes: `*Settles:*` bullets are joined before they are read (closing the `none` leak in both directions), precondition steps are declared and must say `none`, citation checking became order-sensitive, and step expansion returns citation order.
- `test/platform/runtime-observation-checklist.md` -- step 7 rewritten around a hidden start with the toggle semantics stated and the tell corrected; step 13 given the 1280x720 prediction and told to flag it; a portal-grant prerequisite; steps 2, 4 and 5 given the starting state they require; step 2's grep pattern corrected to the third title spelling; two named config backups; the step 12 gate resolved and its stopwatch given a visible zero; a pre-run check that Ctrl+Shift+G is free; `wmctrl` excluded for step 2; one en-dash range reworded; 16 progress checkboxes.
- `test/platform/desktop-session-checklist.md` -- a portal-grant prerequisite and an absolute-XDG prerequisite; step 1 records the installer's own paths; step 3.1 given a hard abort so 3.3 cannot run against a bind that never worked, and its divergence taxonomy given the three states that mimic the expected result; step 4's AD-8 sentence reattributed; step 5 given terminal-scoping requirements for the AD-14 lock; 5 progress checkboxes.
- `test/architecture/desktop_entries_test.dart` -- the printed DW-87 fact 3 no longer requires a tray indicator.
- `test/platform/desktop_entries_live_test.dart` -- the same tray correction in its skip reason.
- `test/platform/correction_panel_live_test.dart`, `test/platform/settings_screen_live_test.dart` -- the "no code sets a size" premise corrected to name the runner's 1280x720 default.
- `_bmad-output/implementation-artifacts/spec-dw-9-runtime-observation-checklists.md` -- Verification criterion given the skip count and a sixth-row command, its failure range corrected and its blind spot stated; the false AGENTS.md §8 instruction dropped from the Execution task; triage log and this section.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- two new entries appended, per the invocation's instruction. No existing entry was read for status, modified, re-opened or rewritten; the diff is 10 insertions and 0 deletions.

### Review findings

33 patches applied (high 4, medium 22, low 7). 0 intent gaps, 0 spec defects. 2 deferred. 5 rejected.

Deferred (appended as new ledger entries): the five entries DW-9, DW-25, DW-26, DW-44 and DW-87 are all recorded `done`/`resolved by sweep bundle` while the observations they own were never made, so nothing open requires anyone to execute either procedure and the six pointer clauses now cite closed ids; and DW-50's own entry rests on the "nothing sets a size" premise this pass measured false. Both require editing existing ledger entries, which the invocation and the spec's Never list both reserve.

Rejected, and why. (1) `review_loop_iteration: 0` was reported as inconsistent with two logged review passes; the field counts bad_spec loopbacks, of which there have been none, so 0 is correct. (2) That the procedures absorb DW-39, DW-50 and DW-72 beyond the five-entry enumeration; the spec's own Code Map assigns those steps deliberately and DW-9's decision names them, so there is one defensible reading, not a gap. (3) That four skip reasons were rewritten rather than extended, against Always #4; adjudicated in the first pass, and the direction strengthens the skips rather than weakening them — a false premise was replaced with a measured one. (4) That the pin suite's depth couples routine editorial edits to a Dart change; that coupling is the mechanism the intent's Approach asks for ("so a rename or a dropped claim fails a run"). (5) That the Block If should be asserted by a row; asserting the absence of a decision is not expressible as a check, and the spec's manual-checks bullet already covers it.

### Follow-up review

`followup_review_recommended: true`. Patched severities: high 4, medium 22, low 7. Any high-severity patch sets it true regardless of the score, which is 3 × 22 + 1 × 7 = 73, far above the threshold of 5.

### Verification performed

- `dart test test/architecture/runtime_checklists_test.dart` -- `+39`, all pass; run output names both procedure paths and still discloses DW-39's half-reachability.
- Mutation gates, run against a verified passing baseline and restored from scratchpad copies rather than `git checkout --` (the working tree carried an uncommitted spec edit throughout). All fourteen behaved correctly: the whole skipped row block-commented out; a passing body with `// fail(` in a comment and a `bool.fromEnvironment` skip; a `*Settles:* none` bullet reflowed onto one line (must **not** redden — it did before this pass); a negated `DW-53` on a continuation line (must not count as settled); a deleted `*Expected:*` bullet; a deleted `**Wayland only**` gate; a results row pointing at step 99; a results row reattributed to the wrong entry; a group heading stripped of its letter; a deleted progress checkbox; a renamed installer path; a new unaccounted `*_live_test.dart`; step 16 repeating the wrong measurement; and the deleted "Wayland portal" not-covered bullet.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` (the CI gate's command), two runs -- `+845 ~2 -2` and `+843 ~2 -4`. Total reconciles to 847 both times (808 baseline + 39 pin rows) with `~2` both times. Every failing row was in `wayland_portal_global_hotkey_test.dart`, one of the two suites DW-46 names; no `test/architecture` row failed.
- `dart test test/architecture/hidden_window_test.dart` -- `+13 ~1`, the sixth skipped row observed directly.
- `flutter test test/platform test/ui` -- `+152 ~7`, identical to the recorded baseline. The six skipped rows still skip and each still has its `fail()` body.
- `dart analyze --fatal-infos` -- No issues found. `dart format --set-exit-if-changed lib test tool` -- reformatted the pin suite once, then idempotent at 0 changed; the suite re-verified at `+39` afterwards.
- Code claims re-measured rather than inferred: `onHotkeyActivated` is a strict toggle and `show`/`hide` set the mirror synchronously before enqueueing (step 7's parity); `gtk_window_set_default_size(window, 1280, 720)` at `my_application.cc:50` with the header-bar branch never calling `gtk_window_set_title` (steps 13 and 2); `effective: null` documented as "by measurement" and the "did not grant" log line present (the portal prerequisite); the installer's `xdg_root` ignoring and warning on a relative value (the XDG prerequisite); and `grep -iE 'hotkey.grammar.corrector'` failing to match the app-id spelling while `hotkey.?grammar.?corrector` matches all three. `pkg-config --modversion keybinder-3.0` -- `0.3.2`.

### Residual risks

- Neither procedure has been executed. Nothing here observes anything; the value is entirely contingent on someone running them on a real session — and after this pass, on the ledger regaining an open entry that asks them to. That is the first deferred item and it is the one that matters.
- Step 11 (DW-39, GTK main-thread marshalling) remains unreachable on every build in the tree, and is disclosed as such in the run output.
- The `_citations` and `_internalCitations` tables are authored. Order-sensitivity closes the demonstrated reassignment mutation, but which claim a step is invoked *for* is still a human judgement, and a wrong-but-consistently-declared mapping would pass.
- The gate's failure count stays non-deterministic between 0 and 5 because of DW-46. The criterion now discriminates on the row total, the skip count and the identity of the failing suites, but a genuine regression inside those two suites is still indistinguishable from the flake — and the Verification section now says so rather than implying otherwise.
- The `*Applies to:*` and `*Expected:*` rows assert that the bullets exist, not that their contents are right. A step can still carry an expected result that is wrong, which is what three of this pass's four high-severity findings were.
- Verification of the CI gate could not be run more than twice within the available time budget; the reconciliation held on both runs and on the two the previous pass recorded, but the failure set was sampled rather than enumerated exhaustively.

### Residual artifacts

None. `git status --porcelain` was clean of anything outside the reviewed diff after the final mutation gate.

## Phase 02 checklist policy disposition (2026-09-24)

The “do not add or renumber steps” clauses in `spec-dw-114-single-exit-path-tray-quit.md` and `spec-dw-31-panel-window-event-reconciliation.md` governed those sweep bundles. They are historical scope constraints, not a standing ban on later checklist maintenance. Their use as a permanent reason to leave the DW-12 close claim and the DW-32/DW-33 focus claims outside numbered observation steps is withdrawn. A later, separately scoped checklist revision may renumber steps and update every citation, results row, and pin together. This disposition adds no step, gate, CI rule, or runtime observation.

The DW-12 close claim and DW-32/DW-33 focus claims remain **unobserved on a native desktop**. `test/platform/runtime-observation-checklist.md` currently routes them under “Not covered here”; that route records the gap and does not settle it. The shipped panel behavior is described by `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` (`_onWindowEvent`, `_onBlur`, `_releaseDeferredBlur`) and `spec-dw-31-panel-window-event-reconciliation.md`'s I/O matrix; no native result is inferred from those sources.
