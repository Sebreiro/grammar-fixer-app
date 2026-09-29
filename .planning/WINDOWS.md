---
schema_version: 1
open_count: 35
waived_count: 1
fixed_count: 14
total_count: 50
last_updated: 2026-09-26T17:46:35.273Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 01 | unrun-verify | test/platform/runtime-observation-checklist.md |  | the end-to-end refusal observed through the settings screen on a real session (registrar layer proved live under Xvfb; UI layer not observable in this container) | open |  | 2026-09-01T16:57:42.658Z |  |
| 2 | 01 | unrun-verify | test/platform/runtime-observation-checklist.md |  | the daemon starting with libkeybinder absent, observed with a tray host (vacuously true under this route: the binary no longer references the library) | open |  | 2026-09-01T16:57:42.769Z |  |
| 3 | 01 | unrun-verify | test/platform/runtime-observation-checklist.md |  | D-10 observed through the settings screen on a real GUI session: with a working shortcut bound, applying a combination another application owns must show the old combination still in effect and the old shortcut must still open the panel (proved live at the adapter+seam layer under Xvfb :77; the GUI half needs a session this container lacks) | open |  | 2026-09-01T17:25:09.659Z |  |
| 4 | 01 | deviation | .planning/REQUIREMENTS.md | 51 | HOTKEY-01's text names the superseded dart:ffi keybinder registrar ('reads keybinder_bind's return value'); the human ratified the x11-ffi-isolate route in 01-01 and it is what shipped. The behaviour asked for is delivered and proved, the mechanism named was not built. Requirement text is human-owned so it was not edited by plans 01-02 or 01-03 | open |  | 2026-09-01T17:28:26.081Z |  |
| 5 | 01 | unrun-verify | lib/src/ui/settings/hotkey_status_view.dart |  | 01-04 human-check owed: the keyRefused sentence has not been read in a live GUI session (no GUI driver in the devcontainer; the only release bundle predates the task commits) | open |  | 2026-09-02T10:43:31.838Z |  |
| 6 | 01 | unrun-verify | lib/src/ui/settings/hotkey_status_view.dart |  | 01-04 human-check owed: the noBackend sentence has not been read in a live GUI session (no GUI driver in the devcontainer; the only release bundle predates the task commits) | open |  | 2026-09-02T10:43:31.952Z |  |
| 7 | 01 | unrun-verify | lib/src/ui/settings/hotkey_status_view.dart |  | 01-04 human-check owed: the revoked sentence has not been read in a live GUI session (no GUI driver in the devcontainer; the only release bundle predates the task commits) | open |  | 2026-09-02T10:43:32.063Z |  |
| 8 | 01 | unrun-verify | lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart |  | 01-05: real-session behaviour of the conditional Register branch and the bounded/abandoned waits is owed to a real Wayland session — no session bus, portal or compositor in this container | open |  | 2026-09-02T11:20:33.296Z |  |
| 9 | 01 | deviation | lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart |  | 01-05: _closeSessionBeforeRebinding's Session.Close is still unbounded on the bind path, deliberately — bounding it breaks the one-Close-in-flight-per-session invariant | open |  | 2026-09-02T11:20:33.419Z |  |
| 10 | 01 | unrun-verify | lib/src/ui/settings/hotkey_status_view.dart |  | 01-06 human-check owed: on a real GNOME/KDE session, that the settings screen shows the compositor's own wording (e.g. a German desktop's Strg+Umschalt+G) and that a rebind made in the desktop with the screen closed shows the new description on mount — no portal, session bus or compositor in this container | open |  | 2026-09-02T11:50:35.873Z |  |
| 11 | 01 | unrun-verify | lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart |  | 01-06: the ListShortcuts re-read is implemented and routed through _callThroughRequest but never exercised — the fake portal implements no ListShortcuts and always sends a trigger_description, so the only caller (a granted bind with no wording) never fires in the suite; first exercise owed to a session with a real portal | open |  | 2026-09-02T11:50:35.980Z |  |
| 12 | 01 | deviation | .planning/phases/01-hotkey-truth/01-06-PLAN.md |  | 01-06: two literal acceptance greps are structurally unpassable and were replaced by anchored substitutes — 'effective: null' counts 4 (three code sites plus one pre-existing doc mention) and the _boundLines 'preference' gate counts 3 lines inside the X11 branch the plan requires kept | open |  | 2026-09-02T11:50:36.085Z |  |
| 13 | 01 | unrun-verify | test/ui/settings/settings_screen_hotkey_test.dart |  | 01-07 human-check row 6: the capture control read-only while a bind is in flight, observed on a real session — not observable in this container (an X11 grab resolves synchronously and there is no portal to park a bind on); the automated rows drive it through a gated fake | open |  | 2026-09-02T22:13:12.430Z |  |
| 14 | 01 | unrun-verify | lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart |  | 01-07 backstop truth: that all seven dissolved labels (Space, Tab, Enter, F1-F4) now grab and FIRE correctly under a real window manager. Space/Tab were exercised live under Xvfb; F1-F4 were not exercised on any real X session | open |  | 2026-09-02T22:13:12.535Z |  |
| 15 | 01 | unrun-verify | test/application/settings_controller_test.dart |  | 01-08: the mid-rebind ShortcutsChanged scenario the HOTKEY-07 guard exists for is unobserved against a real compositor — no GlobalShortcuts portal in this container; the unit row proves the ordering against a fake only | open |  | 2026-09-02T22:30:13.821Z |  |
| 16 | 01 | deviation | lib/src/application/settings_state.dart | 104 | 01-08: acceptance criterion 'grep -c generation settings_state.dart prints 0' fails at baseline (prints 1) on a pre-existing doc sentence unrelated to this plan; substituted with an empty-diff check | open |  | 2026-09-02T22:30:13.928Z |  |
| 17 | 01 | deviation | test/application/settings_controller_test.dart |  | 01-08: acceptance criterion 'total test( count across test/ unchanged' not met (982 -> 983); one row added for the mid-flight discard, mutation-checked, no row deleted | open |  | 2026-09-02T22:30:14.034Z |  |
| 18 | 01 | deviation | .planning/phases/01-hotkey-truth/01-09-PLAN.md |  | 01-09: the plan's verify #4 (grep -rc 'const HotkeyBinding(' lib/ test/) is structurally insufficient — it printed clean while dart analyze still reported 40 errors, because 34 construction sites sat in IMPLICIT const contexts the literal string never matches. Recorded so a later plan editing a const-constructible domain type does not trust the same grep. No code defect; a verification-gap deviation. | open |  | 2026-09-02T22:39:48.542Z |  |
| 19 | 01 | unrun-verify | lib/src/domain/hotkey/hotkey_binding.dart |  | 01-09: HOTKEY-09's mutation guarantee is proven only in-process by test/domain/value_equality_test.dart; no real-desktop or runtime observation was made, and none was needed since no live defect existed. RECOVERED by plan 01-10: this record existed ONLY as a rendered table row (row 18) and was absent from the fenced JSON source of truth, so regenerating the table would have destroyed it. Re-filed here with its original recorded_at; nothing was deleted. | open |  | 2026-09-02T22:39:48.542Z |  |
| 20 | 01 | deviation | _bmad-output/implementation-artifacts/deferred-work.md |  | 01-10: the plan's verify gate 'grep -c "^  summary:" must be exactly 4 higher after Task 2' is wrong by two. Six new open entries were filed, not four: the plan's own must_haves.truths requires a Phase-7 record of every AD-9 declaration edit (01-01's hand-off entry was written in prediction form and its edit-4 wording is now false), and plan 01-05's SUMMARY explicitly asked 01-10 to file TWO entries from it (NameOwnerChanged plus the unbounded rebind Session.Close). Actual delta +6 after Task 2, +7 across the plan. Filing fewer would have lost owed work. No code defect; a declared verification substitution. | open |  | 2026-09-02T23:02:35.757Z |  |
| 21 | 01 | deviation | _bmad-output/implementation-artifacts/deferred-work.md |  | 01-10: FLAT-04's HotkeyUnavailable construction-site count was stale in BOTH directions. A sibling ledger entry says 20 (a 2026-08-14 grep LINE count); 01-10's own action text says 14; plan 01-04 measured 13 because 01-03's atomic rebind swap collapsed one branch first. Re-measured 2026-09-02: 16 'HotkeyUnavailable(' occurrences minus the declaration and two pattern matches = 13 real sites, all naming a cause. The sibling entry keeps its 20 (append-only) and is corrected inside FLAT-04's resolution instead. | open |  | 2026-09-02T23:02:35.866Z |  |
| 22 | 01 | deviation | tool/uat/panel_toggle_probe.sh |  | 01-11: Task 2's acceptance criterion 'the two that moved the focus (focus-steal, desktop-click) are the only two where the FOCUS_BEFORE/FOCUS_AFTER pair differs' does NOT hold as written. Measured 2026-09-10 in the all baseline: the pair differs on FOUR routes — show (2097439 -> 4194308), alternate-1 (same), focus-steal (4194308 -> 10485792), desktop-click (4194308 -> 2097439) AND foreign-grab (4194308 -> 2097439). It is identical only where the panel ended as it started: hide and alternate-2..4, where the flicker returns the panel to visible and the focus with it. The plan's expectation came from the <interfaces> focus table, which records foreign-grab as 'unchanged/unchanged/no' — that row was sampled before the dismissal landed, whereas this harness samples at the 1000 ms settle mark, by which time the panel has unmapped and openbox holds the focus. The harness was NOT changed to make the criterion pass (the plan forbids smoothing). Consequence for 01-12: a focus-owner discriminator read at a post-settle sample is circular on the foreign-grab route, because the focus is foreign only BECAUSE the dismissal happened. This is why 01-13's two added routes classify from events after a specific moment (the WINDOW field) rather than from the whole press. | open |  | 2026-09-10T13:48:52.536Z |  |
| 23 | 01 | deviation | .planning/phases/01-hotkey-truth/01-12-PLAN.md |  | 01-12: two read_first facts in the plan were stale and are corrected in place. (a) The plan says the suite's negative-control record 'currently reaches control 23'; it reached 32, and the record's own prose header said 'Thirty-one' while listing 32 — a prose count that drifted twice. Both are now counted from the artefact rather than carried. (b) The plan names three negative controls to measure; seven were measured (33-39), because its own <done> requires each of the nine new rows to fail when its mechanism is removed and three controls pin only five of them. No code defect; a plan-fact correction and an upward scope correction on verification only. | open |  | 2026-09-10T14:22:43.375Z |  |
| 24 | 01 | deviation | lib/src/infrastructure/panel/window_manager_panel_visibility.dart |  | 01-12: DELIBERATE BEHAVIOUR CHANGE, measured. A foreign client's global shortcut firing while the panel is up no longer dismisses the panel. Pre-fix the foreign-grab probe route classified HIDE; post-fix it classifies NOTHING with FOCUS_BEFORE=FOCUS_AFTER=4194308. The discriminator keys on whether the focus moved, and a foreign passive grab moves no focus, so it is indistinguishable from our own grab by construction — this is not a bug in the discriminator, it is the price of keying on the focus rather than on whose grab it was. Not dismissing is arguably the more correct answer (the panel gets the keyboard back), but it IS a change and it removes the diagnosis's smoking-gun control. Plan 01-13 measures it; plan 01-14 owes the deferred-work ledger entry. Filed here so the ship gate sees it even if 01-14 slips. | waived | Ratified by a human 2026-09-11 via /gsd-execute-phase 01 --gaps-only: the panel stays up when a foreign client's global shortcut fires. Nothing the user did moved the keyboard off the panel (focus measured 4194308 -> 4194308), so the panel still holds the keyboard and the user's in-progress edit; dismissing it would discard text the user never aimed at, against the core value that the daemon never loses the user's text. Accepted cost: the panel can sit over whatever that shortcut summoned. The alternative was declined on price, not merits — keying on whose grab it was is the direction plan 01-12 rejected as unfixably racy, so it is a different fix. Closed in the append-only ledger as DW-125 status: done 2026-09-11. | 2026-09-10T14:23:03.509Z | 2026-09-11T08:12:42.203Z |
| 25 | 01 | unrun-verify | lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart |  | 01-12: T-01-60 is accepted on REASONING, not on a measurement, and the witness doc says so in that register. XGetInputFocus is a synchronous round trip on the platform thread with no timeout — deliberately, since bounding it needs a timer and the plan forbids one anywhere on this path. The argument that it adds no new class of hang is that GDK already makes synchronous round trips to the same server on the same thread per frame, so an unresponsive server has stopped the daemon first. Nobody wedged an X server and observed it. T-01-59 (another client on the same display contriving a matching focus window id to suppress a genuine dismissal) is likewise accepted unmeasured. Both are owed to plan 01-14's ledger filing. | open |  | 2026-09-10T14:23:03.620Z |  |
| 26 | 01 | unrun-verify | lib/src/infrastructure/panel/absent_keyboard_focus_witness.dart |  | 01-12: the Wayland arm is unobserved on a real Wayland session. AbsentKeyboardFocusWitness never suppressing is pinned by a binding-free row driving the real null object through the real adapter, and its selection is pinned as text in composition_wiring_test.dart — but this container has no compositor and no GlobalShortcuts portal, so nobody has watched CAP-14's focus-loss hide still fire on a Wayland desktop after this change. Structurally the arm cannot differ (focusUnmoved is false unconditionally, which is the pre-seam behaviour), which is why this is an owed observation rather than a risk. | open |  | 2026-09-10T14:23:03.736Z |  |
| 27 | 01 | deviation | test/infrastructure/panel/window_manager_panel_visibility_test.dart |  | 01-12: MUTATION-GATE COUNTING HAZARD, found the hard way. 'dart test --reporter=compact \| grep -c "\\[E\\]"' reports 0 failures for EVERY mutation, because the compact reporter rewrites a single line with carriage returns so the failure markers never reach a line end. Control 33's first measurement came back 0 that way and was caught only because a 0 contradicted a row that had just been watched to fail; the true count is 3. Every count in controls 33-39 was re-taken from the JSON reporter's testDone events. Any later plan measuring negative controls must count from testDone, and must confirm the baseline reads 0 through the SAME counter first. | open |  | 2026-09-10T14:23:03.847Z |  |
| 28 | 01 | unmet-truth | test/platform/panel-toggle-observation.md |  | 01-13: the NotifyUngrab/_focused mechanism UAT test 14's retest_after_fix names is still UNREPRODUCED. Its two re-run routes (steal-after-presses, press-then-click) are regression guards only: no pre-fix baseline, and per test 14's own HEAD evidence both would have read HIDE on the broken build too, so a HIDE from them discriminates nothing. Post-fix the press now hides the panel, so the gesture that worried test 14 (a suppressed focus-out at a still-mapped panel) is no longer reachable by it at all; foreign-grab is the only route that still produces that state, and composing foreign-grab with a click is the probe that would exercise the mechanism if it ever reproduces. | open |  | 2026-09-10T14:49:56.622Z |  |
| 29 | 01 | deviation | test/architecture/runtime_checklists_test.dart |  | 01-14: one edit beyond the plan's table. The pinning suite's own run-output print claimed 'no compositor and no window manager' and that a bare display 'would supply none of the above' — both falsified by the 2026-09-04 Xvfb+openbox 3.6.1 session. Corrected in place, stated as a correction. No pin moved; the print carries no assertion. | open |  | 2026-09-10T15:10:00.774Z |  |
| 30 | 01 | unmet-truth | test/architecture/hidden_window_test.dart |  | 01-14: the SEVENTH pointer site was deliberately NOT audited. hidden_window_test.dart's AD-8 skip reason still says 'the host display is unreachable too' and that 'Xvfb supplies a bare X server with no window manager, so a synthetic display answers a question nobody asked' — the same premise DW-123 refutes. Left untouched because the file is outside plan 01-14's declared file set; routed to DW-123's open re-triage rather than edited as scope creep. | open |  | 2026-09-10T15:10:00.896Z |  |
| 31 | 01 | deviation | test/infrastructure/hotkey/x11_global_hotkey_test.dart |  | Deliberately RED row (plan 01-15 fail-first oracle): 'HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears the previous combination instead of reporting it as in effect' fails against the unfixed x11_global_hotkey.dart. Closed by plan 01-16. | fixed |  | 2026-09-11T12:49:14.325Z | 2026-09-11T13:02:19.507Z |
| 32 | 01 | deviation | test/infrastructure/hotkey/x11_global_hotkey_test.dart |  | 01-16: plan verify #4 and its matching acceptance criterion ('at least three rows NAME workerGone'; 'dart test --plain-name workerGone' reports fewer than 3) are NOT met literally and were SUBSTITUTED, not adjusted. The command reports +2, because 01-15's rebind cell is named 'a refusal whose backend is gone clears the previous combination instead of reporting it as in effect' and does not carry the literal token — a name 01-15 froze verbatim and 01-17's live probe matches on, so renaming it to satisfy the grep was refused. Substituted evidence: three DISTINCT test blocks arm HotkeyRefusalCode.workerGone (file lines 297, 597, 635 = the rebind cell, the first-bind cell, the recovery row), and 'dart test --plain-name CR-02' reports +7 all passing. The matrix is complete; the plan's mechanical proxy measured the row NAMES rather than what the rows drive. Needs a reviewer's blessing, not a code change. | open |  | 2026-09-11T13:02:37.345Z |  |
| 33 | 01 | deviation | tool/uat/worker_gone_probe.sh |  | 01-17: one of four probe runs HALTED at the warm-up step ('Ctrl+Shift+G did not map the panel within 10 s') and its cause is UNDIAGNOSED — that run's daemon log lived under the temp root the exit trap removes, so the evidence went with it. Commit 49c5f9f fixes that by writing the daemon log into the surviving output directory, so the next occurrence is diagnosable. Two candidates remain open: the startup XGrabKey was refused (the log would carry a startup keyRefused line), or the press was delivered and the panel did not map. It did not reproduce in the run before it nor in the two after it, and a halt is not a verdict — no reading was taken from it. Recorded in test/platform/worker-gone-observation.md section 3. | open |  | 2026-09-11T13:32:25.178Z |  |
| 34 | 01 | deviation | tool/uat/worker_gone_probe.sh |  | 01-17: the plan's task-1 step 5 says 'seed the config'; the probe instead lets the daemon write its own shipped defaults into the throwaway XDG tree and ASSERTS that hotkeyBinding reads Ctrl+Shift+G, halting by name if it does not. Reason: two of the shipped provider settings (interpreter and sidecar paths) are derived from the running host at startup, so a hand-built config would either duplicate that derivation or change what the daemon does at startup. The property the step exists to establish — the run starts from a genuinely held Ctrl+Shift+G grab — is measured rather than assumed, and is confirmed a second time by the warm-up press mapping the panel. | open |  | 2026-09-11T13:32:25.285Z |  |
| 35 | 01 | unrun-verify | lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart |  | 01-18 (WR-04): the allocate-before-publish reordering in _open and the nullptr belt in _readFocus ship with NO behavioural coverage. A calloc failure has no injection point through this seam — the class IS the seam, it owns its own allocator with no hook, and X11KeyboardFocusWitness needs a live X server to reach _open at all, which is why the whole file is driven by FakeKeyboardFocusWitness from the adapter's side and by nothing from its own. Acceptance was a source assertion (both calloc line numbers strictly below both publish line numbers, plus a nullptr comparison inside _readFocus) plus dart analyze plus both unchanged suites. The SIGSEGV was NOT reproduced: nobody starved this process's allocator. The plan (01-18 Task 2) explicitly prohibits manufacturing a row that hand-sets private state to make the branch 'covered'. Recorded so the absence of a runnable proof is visible at ship time rather than inferred from the diff. | open |  | 2026-09-11T13:47:11.651Z |  |
| 36 | 01 | deviation | test/platform/worker-gone-observation.md |  | Plan 01-21 Task 3 targeted a section 8 that does not exist; the sentence was folded into section 7's closing line instead | open |  | 2026-09-14T17:46:24.370Z |  |
| 37 | 01 | deviation | tool/uat/worker_gone_probe.sh |  | Two of plan 01-21's gate commands are unsatisfiable under the harness's ugrep (dollar treated as an anchor in BRE); run with /usr/bin/grep instead | open |  | 2026-09-14T17:46:24.482Z |  |
| 38 | 02 | deviation | lib/main.dart |  | 02-01 resolved: provider resolution required the outer composition root beyond the four listed application files | fixed |  | 2026-09-24T14:29:53.030Z | 2026-09-24T14:30:02.727Z |
| 39 | 02 | deviation | lib/src/ui/settings/preset_choice_list.dart |  | 02-01 resolved: live preset switching required updating the stale restart copy and its existing assertion | fixed |  | 2026-09-24T14:29:53.162Z | 2026-09-24T14:30:02.855Z |
| 40 | 02 | unmet-truth | lib/src/infrastructure/config/json_config_store.dart |  | 02-01 external config-file edits cannot refresh the active pair until JsonConfigStore emits live file changes | fixed |  | 2026-09-24T14:29:53.290Z | 2026-09-26T11:42:00.977Z |
| 41 | 02 | unmet-truth | lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart | 1501 | A refused Wayland session Close retains the old working shortcut without a typed refusal marker, so Settings and tray cannot show the temporary refusal note. | fixed |  | 2026-09-24T15:57:20.439Z | 2026-09-26T17:46:35.273Z |
| 42 | 02 | deviation | lib/src/ui/panel/suggestion_list.dart |  | Resolved: card feedback required passing status through SuggestionList | fixed |  | 2026-09-24T16:12:20.333Z | 2026-09-24T16:12:51.643Z |
| 43 | 02 | deviation | test/application/correction_controller_test.dart |  | Resolved: existing assertions updated for serialized copy order and invalid-text refusal | fixed |  | 2026-09-24T16:12:20.461Z | 2026-09-24T16:12:51.771Z |
| 44 | 02 | unmet-truth | lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart | 275 | Claude sidecar stderr read error is interpolated into structured logger context; 02-15 must log only its runtime type. | fixed |  | 2026-09-24T16:26:47.797Z | 2026-09-24T17:48:35.776Z |
| 45 | 02 | unmet-truth | lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart | 289 | Claude sidecar stdin write error is interpolated into structured logger context; 02-15 must log only its runtime type. | fixed |  | 2026-09-24T16:26:47.935Z | 2026-09-24T17:48:35.901Z |
| 46 | 02 | deviation | test/composition/daemon_graph_test.dart |  | 02-11 resolved: the existing teardown assertion now accounts for the Settings focus-loss visibility listener | fixed |  | 2026-09-24T17:30:00.845Z | 2026-09-24T17:30:08.255Z |
| 47 | 02 | deviation | lib/src/application/panel_controller.dart |  | 02-11 resolved: late focus-loss callbacks are ignored after output stream teardown | fixed |  | 2026-09-24T17:30:17.717Z | 2026-09-24T17:30:27.630Z |
| 48 | 02 | deviation | test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart |  | 02-15 updated existing raw-stderr and parser-error assertions to require safe redacted diagnostics | fixed |  | 2026-09-24T17:52:25.646Z | 2026-09-24T17:52:36.071Z |
| 49 | 02 | deviation | lib/src/infrastructure/correction/openai_compatible/openai_compatible_correction_provider.dart |  | 02-15 fixed paused-consumer propagation during HTTP connect and bounded comment-only SSE frames | fixed |  | 2026-09-24T17:52:25.773Z | 2026-09-24T17:52:36.192Z |
| 50 | 02 | stub | lib/src/application/settings_controller.dart | 179 | Without composition source resolver, Settings reports None configured; plan 02-18 injects the authoritative source lookup. | fixed |  | 2026-09-24T18:40:20.889Z | 2026-09-26T11:38:11.912Z |

````json
[
  {
    "id": 1,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "test/platform/runtime-observation-checklist.md",
    "line": null,
    "description": "the end-to-end refusal observed through the settings screen on a real session (registrar layer proved live under Xvfb; UI layer not observable in this container)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T16:57:42.658Z",
    "resolved_at": null
  },
  {
    "id": 2,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "test/platform/runtime-observation-checklist.md",
    "line": null,
    "description": "the daemon starting with libkeybinder absent, observed with a tray host (vacuously true under this route: the binary no longer references the library)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T16:57:42.769Z",
    "resolved_at": null
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "test/platform/runtime-observation-checklist.md",
    "line": null,
    "description": "D-10 observed through the settings screen on a real GUI session: with a working shortcut bound, applying a combination another application owns must show the old combination still in effect and the old shortcut must still open the panel (proved live at the adapter+seam layer under Xvfb :77; the GUI half needs a session this container lacks)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T17:25:09.659Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "01",
    "file": ".planning/REQUIREMENTS.md",
    "line": 51,
    "description": "HOTKEY-01's text names the superseded dart:ffi keybinder registrar ('reads keybinder_bind's return value'); the human ratified the x11-ffi-isolate route in 01-01 and it is what shipped. The behaviour asked for is delivered and proved, the mechanism named was not built. Requirement text is human-owned so it was not edited by plans 01-02 or 01-03",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T17:28:26.081Z",
    "resolved_at": null
  },
  {
    "id": 5,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/ui/settings/hotkey_status_view.dart",
    "line": null,
    "description": "01-04 human-check owed: the keyRefused sentence has not been read in a live GUI session (no GUI driver in the devcontainer; the only release bundle predates the task commits)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T10:43:31.838Z",
    "resolved_at": null
  },
  {
    "id": 6,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/ui/settings/hotkey_status_view.dart",
    "line": null,
    "description": "01-04 human-check owed: the noBackend sentence has not been read in a live GUI session (no GUI driver in the devcontainer; the only release bundle predates the task commits)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T10:43:31.952Z",
    "resolved_at": null
  },
  {
    "id": 7,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/ui/settings/hotkey_status_view.dart",
    "line": null,
    "description": "01-04 human-check owed: the revoked sentence has not been read in a live GUI session (no GUI driver in the devcontainer; the only release bundle predates the task commits)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T10:43:32.063Z",
    "resolved_at": null
  },
  {
    "id": 8,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart",
    "line": null,
    "description": "01-05: real-session behaviour of the conditional Register branch and the bounded/abandoned waits is owed to a real Wayland session — no session bus, portal or compositor in this container",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T11:20:33.296Z",
    "resolved_at": null
  },
  {
    "id": 9,
    "kind": "deviation",
    "phase": "01",
    "file": "lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart",
    "line": null,
    "description": "01-05: _closeSessionBeforeRebinding's Session.Close is still unbounded on the bind path, deliberately — bounding it breaks the one-Close-in-flight-per-session invariant",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T11:20:33.419Z",
    "resolved_at": null
  },
  {
    "id": 10,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/ui/settings/hotkey_status_view.dart",
    "line": null,
    "description": "01-06 human-check owed: on a real GNOME/KDE session, that the settings screen shows the compositor's own wording (e.g. a German desktop's Strg+Umschalt+G) and that a rebind made in the desktop with the screen closed shows the new description on mount — no portal, session bus or compositor in this container",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T11:50:35.873Z",
    "resolved_at": null
  },
  {
    "id": 11,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart",
    "line": null,
    "description": "01-06: the ListShortcuts re-read is implemented and routed through _callThroughRequest but never exercised — the fake portal implements no ListShortcuts and always sends a trigger_description, so the only caller (a granted bind with no wording) never fires in the suite; first exercise owed to a session with a real portal",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T11:50:35.980Z",
    "resolved_at": null
  },
  {
    "id": 12,
    "kind": "deviation",
    "phase": "01",
    "file": ".planning/phases/01-hotkey-truth/01-06-PLAN.md",
    "line": null,
    "description": "01-06: two literal acceptance greps are structurally unpassable and were replaced by anchored substitutes — 'effective: null' counts 4 (three code sites plus one pre-existing doc mention) and the _boundLines 'preference' gate counts 3 lines inside the X11 branch the plan requires kept",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T11:50:36.085Z",
    "resolved_at": null
  },
  {
    "id": 13,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "test/ui/settings/settings_screen_hotkey_test.dart",
    "line": null,
    "description": "01-07 human-check row 6: the capture control read-only while a bind is in flight, observed on a real session — not observable in this container (an X11 grab resolves synchronously and there is no portal to park a bind on); the automated rows drive it through a gated fake",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T22:13:12.430Z",
    "resolved_at": null
  },
  {
    "id": 14,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart",
    "line": null,
    "description": "01-07 backstop truth: that all seven dissolved labels (Space, Tab, Enter, F1-F4) now grab and FIRE correctly under a real window manager. Space/Tab were exercised live under Xvfb; F1-F4 were not exercised on any real X session",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T22:13:12.535Z",
    "resolved_at": null
  },
  {
    "id": 15,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "test/application/settings_controller_test.dart",
    "line": null,
    "description": "01-08: the mid-rebind ShortcutsChanged scenario the HOTKEY-07 guard exists for is unobserved against a real compositor — no GlobalShortcuts portal in this container; the unit row proves the ordering against a fake only",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T22:30:13.821Z",
    "resolved_at": null
  },
  {
    "id": 16,
    "kind": "deviation",
    "phase": "01",
    "file": "lib/src/application/settings_state.dart",
    "line": 104,
    "description": "01-08: acceptance criterion 'grep -c generation settings_state.dart prints 0' fails at baseline (prints 1) on a pre-existing doc sentence unrelated to this plan; substituted with an empty-diff check",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T22:30:13.928Z",
    "resolved_at": null
  },
  {
    "id": 17,
    "kind": "deviation",
    "phase": "01",
    "file": "test/application/settings_controller_test.dart",
    "line": null,
    "description": "01-08: acceptance criterion 'total test( count across test/ unchanged' not met (982 -> 983); one row added for the mid-flight discard, mutation-checked, no row deleted",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T22:30:14.034Z",
    "resolved_at": null
  },
  {
    "id": 18,
    "kind": "deviation",
    "phase": "01",
    "file": ".planning/phases/01-hotkey-truth/01-09-PLAN.md",
    "line": null,
    "description": "01-09: the plan's verify #4 (grep -rc 'const HotkeyBinding(' lib/ test/) is structurally insufficient — it printed clean while dart analyze still reported 40 errors, because 34 construction sites sat in IMPLICIT const contexts the literal string never matches. Recorded so a later plan editing a const-constructible domain type does not trust the same grep. No code defect; a verification-gap deviation.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T22:39:48.542Z",
    "resolved_at": null
  },
  {
    "id": 19,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/domain/hotkey/hotkey_binding.dart",
    "line": null,
    "description": "01-09: HOTKEY-09's mutation guarantee is proven only in-process by test/domain/value_equality_test.dart; no real-desktop or runtime observation was made, and none was needed since no live defect existed. RECOVERED by plan 01-10: this record existed ONLY as a rendered table row (row 18) and was absent from the fenced JSON source of truth, so regenerating the table would have destroyed it. Re-filed here with its original recorded_at; nothing was deleted.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T22:39:48.542Z",
    "resolved_at": null
  },
  {
    "id": 20,
    "kind": "deviation",
    "phase": "01",
    "file": "_bmad-output/implementation-artifacts/deferred-work.md",
    "line": null,
    "description": "01-10: the plan's verify gate 'grep -c \"^  summary:\" must be exactly 4 higher after Task 2' is wrong by two. Six new open entries were filed, not four: the plan's own must_haves.truths requires a Phase-7 record of every AD-9 declaration edit (01-01's hand-off entry was written in prediction form and its edit-4 wording is now false), and plan 01-05's SUMMARY explicitly asked 01-10 to file TWO entries from it (NameOwnerChanged plus the unbounded rebind Session.Close). Actual delta +6 after Task 2, +7 across the plan. Filing fewer would have lost owed work. No code defect; a declared verification substitution.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T23:02:35.757Z",
    "resolved_at": null
  },
  {
    "id": 21,
    "kind": "deviation",
    "phase": "01",
    "file": "_bmad-output/implementation-artifacts/deferred-work.md",
    "line": null,
    "description": "01-10: FLAT-04's HotkeyUnavailable construction-site count was stale in BOTH directions. A sibling ledger entry says 20 (a 2026-08-14 grep LINE count); 01-10's own action text says 14; plan 01-04 measured 13 because 01-03's atomic rebind swap collapsed one branch first. Re-measured 2026-09-02: 16 'HotkeyUnavailable(' occurrences minus the declaration and two pattern matches = 13 real sites, all naming a cause. The sibling entry keeps its 20 (append-only) and is corrected inside FLAT-04's resolution instead.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T23:02:35.866Z",
    "resolved_at": null
  },
  {
    "id": 22,
    "kind": "deviation",
    "phase": "01",
    "file": "tool/uat/panel_toggle_probe.sh",
    "line": null,
    "description": "01-11: Task 2's acceptance criterion 'the two that moved the focus (focus-steal, desktop-click) are the only two where the FOCUS_BEFORE/FOCUS_AFTER pair differs' does NOT hold as written. Measured 2026-09-10 in the all baseline: the pair differs on FOUR routes — show (2097439 -> 4194308), alternate-1 (same), focus-steal (4194308 -> 10485792), desktop-click (4194308 -> 2097439) AND foreign-grab (4194308 -> 2097439). It is identical only where the panel ended as it started: hide and alternate-2..4, where the flicker returns the panel to visible and the focus with it. The plan's expectation came from the <interfaces> focus table, which records foreign-grab as 'unchanged/unchanged/no' — that row was sampled before the dismissal landed, whereas this harness samples at the 1000 ms settle mark, by which time the panel has unmapped and openbox holds the focus. The harness was NOT changed to make the criterion pass (the plan forbids smoothing). Consequence for 01-12: a focus-owner discriminator read at a post-settle sample is circular on the foreign-grab route, because the focus is foreign only BECAUSE the dismissal happened. This is why 01-13's two added routes classify from events after a specific moment (the WINDOW field) rather than from the whole press.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-10T13:48:52.536Z",
    "resolved_at": null
  },
  {
    "id": 23,
    "kind": "deviation",
    "phase": "01",
    "file": ".planning/phases/01-hotkey-truth/01-12-PLAN.md",
    "line": null,
    "description": "01-12: two read_first facts in the plan were stale and are corrected in place. (a) The plan says the suite's negative-control record 'currently reaches control 23'; it reached 32, and the record's own prose header said 'Thirty-one' while listing 32 — a prose count that drifted twice. Both are now counted from the artefact rather than carried. (b) The plan names three negative controls to measure; seven were measured (33-39), because its own <done> requires each of the nine new rows to fail when its mechanism is removed and three controls pin only five of them. No code defect; a plan-fact correction and an upward scope correction on verification only.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-10T14:22:43.375Z",
    "resolved_at": null
  },
  {
    "id": 24,
    "kind": "deviation",
    "phase": "01",
    "file": "lib/src/infrastructure/panel/window_manager_panel_visibility.dart",
    "line": null,
    "description": "01-12: DELIBERATE BEHAVIOUR CHANGE, measured. A foreign client's global shortcut firing while the panel is up no longer dismisses the panel. Pre-fix the foreign-grab probe route classified HIDE; post-fix it classifies NOTHING with FOCUS_BEFORE=FOCUS_AFTER=4194308. The discriminator keys on whether the focus moved, and a foreign passive grab moves no focus, so it is indistinguishable from our own grab by construction — this is not a bug in the discriminator, it is the price of keying on the focus rather than on whose grab it was. Not dismissing is arguably the more correct answer (the panel gets the keyboard back), but it IS a change and it removes the diagnosis's smoking-gun control. Plan 01-13 measures it; plan 01-14 owes the deferred-work ledger entry. Filed here so the ship gate sees it even if 01-14 slips.",
    "status": "waived",
    "reason": "Ratified by a human 2026-09-11 via /gsd-execute-phase 01 --gaps-only: the panel stays up when a foreign client's global shortcut fires. Nothing the user did moved the keyboard off the panel (focus measured 4194308 -> 4194308), so the panel still holds the keyboard and the user's in-progress edit; dismissing it would discard text the user never aimed at, against the core value that the daemon never loses the user's text. Accepted cost: the panel can sit over whatever that shortcut summoned. The alternative was declined on price, not merits — keying on whose grab it was is the direction plan 01-12 rejected as unfixably racy, so it is a different fix. Closed in the append-only ledger as DW-125 status: done 2026-09-11.",
    "recorded_at": "2026-09-10T14:23:03.509Z",
    "resolved_at": "2026-09-11T08:12:42.203Z"
  },
  {
    "id": 25,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart",
    "line": null,
    "description": "01-12: T-01-60 is accepted on REASONING, not on a measurement, and the witness doc says so in that register. XGetInputFocus is a synchronous round trip on the platform thread with no timeout — deliberately, since bounding it needs a timer and the plan forbids one anywhere on this path. The argument that it adds no new class of hang is that GDK already makes synchronous round trips to the same server on the same thread per frame, so an unresponsive server has stopped the daemon first. Nobody wedged an X server and observed it. T-01-59 (another client on the same display contriving a matching focus window id to suppress a genuine dismissal) is likewise accepted unmeasured. Both are owed to plan 01-14's ledger filing.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-10T14:23:03.620Z",
    "resolved_at": null
  },
  {
    "id": 26,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/infrastructure/panel/absent_keyboard_focus_witness.dart",
    "line": null,
    "description": "01-12: the Wayland arm is unobserved on a real Wayland session. AbsentKeyboardFocusWitness never suppressing is pinned by a binding-free row driving the real null object through the real adapter, and its selection is pinned as text in composition_wiring_test.dart — but this container has no compositor and no GlobalShortcuts portal, so nobody has watched CAP-14's focus-loss hide still fire on a Wayland desktop after this change. Structurally the arm cannot differ (focusUnmoved is false unconditionally, which is the pre-seam behaviour), which is why this is an owed observation rather than a risk.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-10T14:23:03.736Z",
    "resolved_at": null
  },
  {
    "id": 27,
    "kind": "deviation",
    "phase": "01",
    "file": "test/infrastructure/panel/window_manager_panel_visibility_test.dart",
    "line": null,
    "description": "01-12: MUTATION-GATE COUNTING HAZARD, found the hard way. 'dart test --reporter=compact | grep -c \"\\[E\\]\"' reports 0 failures for EVERY mutation, because the compact reporter rewrites a single line with carriage returns so the failure markers never reach a line end. Control 33's first measurement came back 0 that way and was caught only because a 0 contradicted a row that had just been watched to fail; the true count is 3. Every count in controls 33-39 was re-taken from the JSON reporter's testDone events. Any later plan measuring negative controls must count from testDone, and must confirm the baseline reads 0 through the SAME counter first.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-10T14:23:03.847Z",
    "resolved_at": null
  },
  {
    "id": 28,
    "kind": "unmet-truth",
    "phase": "01",
    "file": "test/platform/panel-toggle-observation.md",
    "line": null,
    "description": "01-13: the NotifyUngrab/_focused mechanism UAT test 14's retest_after_fix names is still UNREPRODUCED. Its two re-run routes (steal-after-presses, press-then-click) are regression guards only: no pre-fix baseline, and per test 14's own HEAD evidence both would have read HIDE on the broken build too, so a HIDE from them discriminates nothing. Post-fix the press now hides the panel, so the gesture that worried test 14 (a suppressed focus-out at a still-mapped panel) is no longer reachable by it at all; foreign-grab is the only route that still produces that state, and composing foreign-grab with a click is the probe that would exercise the mechanism if it ever reproduces.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-10T14:49:56.622Z",
    "resolved_at": null
  },
  {
    "id": 29,
    "kind": "deviation",
    "phase": "01",
    "file": "test/architecture/runtime_checklists_test.dart",
    "line": null,
    "description": "01-14: one edit beyond the plan's table. The pinning suite's own run-output print claimed 'no compositor and no window manager' and that a bare display 'would supply none of the above' — both falsified by the 2026-09-04 Xvfb+openbox 3.6.1 session. Corrected in place, stated as a correction. No pin moved; the print carries no assertion.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-10T15:10:00.774Z",
    "resolved_at": null
  },
  {
    "id": 30,
    "kind": "unmet-truth",
    "phase": "01",
    "file": "test/architecture/hidden_window_test.dart",
    "line": null,
    "description": "01-14: the SEVENTH pointer site was deliberately NOT audited. hidden_window_test.dart's AD-8 skip reason still says 'the host display is unreachable too' and that 'Xvfb supplies a bare X server with no window manager, so a synthetic display answers a question nobody asked' — the same premise DW-123 refutes. Left untouched because the file is outside plan 01-14's declared file set; routed to DW-123's open re-triage rather than edited as scope creep.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-10T15:10:00.896Z",
    "resolved_at": null
  },
  {
    "id": 31,
    "kind": "deviation",
    "phase": "01",
    "file": "test/infrastructure/hotkey/x11_global_hotkey_test.dart",
    "line": null,
    "description": "Deliberately RED row (plan 01-15 fail-first oracle): 'HOTKEY-01, HOTKEY-08, CR-02: a refusal whose backend is gone clears the previous combination instead of reporting it as in effect' fails against the unfixed x11_global_hotkey.dart. Closed by plan 01-16.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-11T12:49:14.325Z",
    "resolved_at": "2026-09-11T13:02:19.507Z"
  },
  {
    "id": 32,
    "kind": "deviation",
    "phase": "01",
    "file": "test/infrastructure/hotkey/x11_global_hotkey_test.dart",
    "line": null,
    "description": "01-16: plan verify #4 and its matching acceptance criterion ('at least three rows NAME workerGone'; 'dart test --plain-name workerGone' reports fewer than 3) are NOT met literally and were SUBSTITUTED, not adjusted. The command reports +2, because 01-15's rebind cell is named 'a refusal whose backend is gone clears the previous combination instead of reporting it as in effect' and does not carry the literal token — a name 01-15 froze verbatim and 01-17's live probe matches on, so renaming it to satisfy the grep was refused. Substituted evidence: three DISTINCT test blocks arm HotkeyRefusalCode.workerGone (file lines 297, 597, 635 = the rebind cell, the first-bind cell, the recovery row), and 'dart test --plain-name CR-02' reports +7 all passing. The matrix is complete; the plan's mechanical proxy measured the row NAMES rather than what the rows drive. Needs a reviewer's blessing, not a code change.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T13:02:37.345Z",
    "resolved_at": null
  },
  {
    "id": 33,
    "kind": "deviation",
    "phase": "01",
    "file": "tool/uat/worker_gone_probe.sh",
    "line": null,
    "description": "01-17: one of four probe runs HALTED at the warm-up step ('Ctrl+Shift+G did not map the panel within 10 s') and its cause is UNDIAGNOSED — that run's daemon log lived under the temp root the exit trap removes, so the evidence went with it. Commit 49c5f9f fixes that by writing the daemon log into the surviving output directory, so the next occurrence is diagnosable. Two candidates remain open: the startup XGrabKey was refused (the log would carry a startup keyRefused line), or the press was delivered and the panel did not map. It did not reproduce in the run before it nor in the two after it, and a halt is not a verdict — no reading was taken from it. Recorded in test/platform/worker-gone-observation.md section 3.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T13:32:25.178Z",
    "resolved_at": null
  },
  {
    "id": 34,
    "kind": "deviation",
    "phase": "01",
    "file": "tool/uat/worker_gone_probe.sh",
    "line": null,
    "description": "01-17: the plan's task-1 step 5 says 'seed the config'; the probe instead lets the daemon write its own shipped defaults into the throwaway XDG tree and ASSERTS that hotkeyBinding reads Ctrl+Shift+G, halting by name if it does not. Reason: two of the shipped provider settings (interpreter and sidecar paths) are derived from the running host at startup, so a hand-built config would either duplicate that derivation or change what the daemon does at startup. The property the step exists to establish — the run starts from a genuinely held Ctrl+Shift+G grab — is measured rather than assumed, and is confirmed a second time by the warm-up press mapping the panel.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T13:32:25.285Z",
    "resolved_at": null
  },
  {
    "id": 35,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "lib/src/infrastructure/panel/x11_keyboard_focus_witness.dart",
    "line": null,
    "description": "01-18 (WR-04): the allocate-before-publish reordering in _open and the nullptr belt in _readFocus ship with NO behavioural coverage. A calloc failure has no injection point through this seam — the class IS the seam, it owns its own allocator with no hook, and X11KeyboardFocusWitness needs a live X server to reach _open at all, which is why the whole file is driven by FakeKeyboardFocusWitness from the adapter's side and by nothing from its own. Acceptance was a source assertion (both calloc line numbers strictly below both publish line numbers, plus a nullptr comparison inside _readFocus) plus dart analyze plus both unchanged suites. The SIGSEGV was NOT reproduced: nobody starved this process's allocator. The plan (01-18 Task 2) explicitly prohibits manufacturing a row that hand-sets private state to make the branch 'covered'. Recorded so the absence of a runnable proof is visible at ship time rather than inferred from the diff.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T13:47:11.651Z",
    "resolved_at": null
  },
  {
    "id": 36,
    "kind": "deviation",
    "phase": "01",
    "file": "test/platform/worker-gone-observation.md",
    "line": null,
    "description": "Plan 01-21 Task 3 targeted a section 8 that does not exist; the sentence was folded into section 7's closing line instead",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-14T17:46:24.370Z",
    "resolved_at": null
  },
  {
    "id": 37,
    "kind": "deviation",
    "phase": "01",
    "file": "tool/uat/worker_gone_probe.sh",
    "line": null,
    "description": "Two of plan 01-21's gate commands are unsatisfiable under the harness's ugrep (dollar treated as an anchor in BRE); run with /usr/bin/grep instead",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-14T17:46:24.482Z",
    "resolved_at": null
  },
  {
    "id": 38,
    "kind": "deviation",
    "phase": "02",
    "file": "lib/main.dart",
    "line": null,
    "description": "02-01 resolved: provider resolution required the outer composition root beyond the four listed application files",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T14:29:53.030Z",
    "resolved_at": "2026-09-24T14:30:02.727Z",
    "milestone": null
  },
  {
    "id": 39,
    "kind": "deviation",
    "phase": "02",
    "file": "lib/src/ui/settings/preset_choice_list.dart",
    "line": null,
    "description": "02-01 resolved: live preset switching required updating the stale restart copy and its existing assertion",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T14:29:53.162Z",
    "resolved_at": "2026-09-24T14:30:02.855Z",
    "milestone": null
  },
  {
    "id": 40,
    "kind": "unmet-truth",
    "phase": "02",
    "file": "lib/src/infrastructure/config/json_config_store.dart",
    "line": null,
    "description": "02-01 external config-file edits cannot refresh the active pair until JsonConfigStore emits live file changes",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T14:29:53.290Z",
    "resolved_at": "2026-09-26T11:42:00.977Z",
    "milestone": null
  },
  {
    "id": 41,
    "kind": "unmet-truth",
    "phase": "02",
    "file": "lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart",
    "line": 1501,
    "description": "A refused Wayland session Close retains the old working shortcut without a typed refusal marker, so Settings and tray cannot show the temporary refusal note.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T15:57:20.439Z",
    "resolved_at": "2026-09-26T17:46:35.273Z",
    "milestone": null
  },
  {
    "id": 42,
    "kind": "deviation",
    "phase": "02",
    "file": "lib/src/ui/panel/suggestion_list.dart",
    "line": null,
    "description": "Resolved: card feedback required passing status through SuggestionList",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T16:12:20.333Z",
    "resolved_at": "2026-09-24T16:12:51.643Z",
    "milestone": null
  },
  {
    "id": 43,
    "kind": "deviation",
    "phase": "02",
    "file": "test/application/correction_controller_test.dart",
    "line": null,
    "description": "Resolved: existing assertions updated for serialized copy order and invalid-text refusal",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T16:12:20.461Z",
    "resolved_at": "2026-09-24T16:12:51.771Z",
    "milestone": null
  },
  {
    "id": 44,
    "kind": "unmet-truth",
    "phase": "02",
    "file": "lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart",
    "line": 275,
    "description": "Claude sidecar stderr read error is interpolated into structured logger context; 02-15 must log only its runtime type.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T16:26:47.797Z",
    "resolved_at": "2026-09-24T17:48:35.776Z",
    "milestone": null
  },
  {
    "id": 45,
    "kind": "unmet-truth",
    "phase": "02",
    "file": "lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart",
    "line": 289,
    "description": "Claude sidecar stdin write error is interpolated into structured logger context; 02-15 must log only its runtime type.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T16:26:47.935Z",
    "resolved_at": "2026-09-24T17:48:35.901Z",
    "milestone": null
  },
  {
    "id": 46,
    "kind": "deviation",
    "phase": "02",
    "file": "test/composition/daemon_graph_test.dart",
    "line": null,
    "description": "02-11 resolved: the existing teardown assertion now accounts for the Settings focus-loss visibility listener",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T17:30:00.845Z",
    "resolved_at": "2026-09-24T17:30:08.255Z",
    "milestone": null
  },
  {
    "id": 47,
    "kind": "deviation",
    "phase": "02",
    "file": "lib/src/application/panel_controller.dart",
    "line": null,
    "description": "02-11 resolved: late focus-loss callbacks are ignored after output stream teardown",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T17:30:17.717Z",
    "resolved_at": "2026-09-24T17:30:27.630Z",
    "milestone": null
  },
  {
    "id": 48,
    "kind": "deviation",
    "phase": "02",
    "file": "test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart",
    "line": null,
    "description": "02-15 updated existing raw-stderr and parser-error assertions to require safe redacted diagnostics",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T17:52:25.646Z",
    "resolved_at": "2026-09-24T17:52:36.071Z",
    "milestone": null
  },
  {
    "id": 49,
    "kind": "deviation",
    "phase": "02",
    "file": "lib/src/infrastructure/correction/openai_compatible/openai_compatible_correction_provider.dart",
    "line": null,
    "description": "02-15 fixed paused-consumer propagation during HTTP connect and bounded comment-only SSE frames",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T17:52:25.773Z",
    "resolved_at": "2026-09-24T17:52:36.192Z",
    "milestone": null
  },
  {
    "id": 50,
    "kind": "stub",
    "phase": "02",
    "file": "lib/src/application/settings_controller.dart",
    "line": 179,
    "description": "Without composition source resolver, Settings reports None configured; plan 02-18 injects the authoritative source lookup.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-24T18:40:20.889Z",
    "resolved_at": "2026-09-26T11:38:11.912Z",
    "milestone": null
  }
]
````
