---
title: 'One exit path, two triggers: a tray Quit entry, and a window close that hides'
type: 'feature'
created: '2026-08-14'
status: 'done'
baseline_revision: '5be529490f7d82fac8c47625324ae3e2bccdc733'
final_revision: 'd39fc121e3812d10b34760acaab2c7c3a39e1cd9'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
warnings: ['oversized']
---

<intent-contract>

## Intent

**Problem:** The daemon can only be stopped by a signal. `TrayManagerTray._menu()` builds exactly two entries — an always-enabled "Open the panel" and, only while the hotkey is unavailable, a deliberately disabled statement line — and `TrayPort` declares three members, none of them a quit, so a tray-only user has no way out of a resident daemon (DW-114). Separately, nothing routes a window close into the ordered teardown, and `on_window_close` returns `_is_prevent_close` — false by default — so GTK destroys the toplevel and abandons whatever CAP-7 write is in flight (DW-12).

**Approach:** Give the daemon exactly **two exit triggers and one exit path**. `TrayPort` gains a quit-request stream beside `panelRequests`; the menu gains an always-enabled Quit entry; the composition root wires that stream to the same ordered `DaemonLifecycle.shutdown()` the SIGINT/SIGTERM/SIGHUP handlers reach, then `exit(0)`. Quit is immediate, with no confirmation — every correction is already in history (CAP-7) and copying is explicit (CAP-11), which is the reasoning the SPEC's Assumptions already use for a focus-loss hide. The window is deliberately **not** a third trigger: `setPreventClose(true)` plus a close arm that issues `PanelVisibility.hide()`, so the toplevel is never destroyed and a close means "put this away", the same intent CAP-14 gives a focus loss.

## Boundaries & Constraints

**Always:**
- Exactly one teardown: a tray Quit runs `DaemonLifecycle.shutdown()` — the same latched, per-step-bounded sequence a SIGTERM runs — and only then `exit(0)`. The `exit()` stays in `main.dart`; `DaemonLifecycle` must never end the process (a function that ends the process cannot be tested, and the teardown order is the part worth testing).
- The Quit entry is enabled in **both** hotkey states, like the open-panel entry: the tray is the surface that stays reachable when the hotkey is not (SPEC:117).
- Quit is immediate. No prompt, no confirmation step, no "are you sure".
- Every stream this change opens is closed on the teardown path, through the adapter's existing `_guard` shape.
- AD-1 confinement holds: `package:window_manager` stays in `lib/main.dart` and `lib/src/infrastructure/panel/window_manager_panel_window.dart`; `package:tray_manager` stays in `tray_manager_tray_icon.dart`.
- Logs carry `error_type` and nothing else, and go through the file's existing `_log` swallow.

**Block If:**
- `setPreventClose` cannot be placed on the startup path without weakening `hidden_window_test.dart`'s AD-8 ban to admit a call that *can* map the toplevel.
- Wiring the quit stream to the ordered teardown turns out to require `DaemonLifecycle` to call `exit()` itself.

**Never:**
- No confirmation dialog, no "quit anyway?" state, no delay before the teardown starts.
- No `windowManager.close()` / `destroy()` / `terminate()` anywhere — the daemon exits through `exit()` after `shutdown()`, and nothing else.
- Do not resolve DW-31's `minimize` half: `_reconcile`'s `_outstanding` guard stays exactly as it is for `show`, `hide`, `restore` and `minimize`. Only the `close` arm changes, and it stops routing through `_reconcile` entirely.
- Do not edit `_bmad-output/implementation-artifacts/deferred-work.md` (the orchestrator records resolution), and never hand-edit `SPEC.md`.
- Do not add or renumber steps in `test/platform/runtime-observation-checklist.md`, and do not touch `test/architecture/runtime_checklists_test.dart` — inserting a step renumbers every citation below it, and two prior sweep bundles deliberately left both files alone.
- Do not change the `PanelVisibility` port (`lib/src/domain/panel/panel_visibility.dart`): it is AD-8 verbatim.
- Do not widen the `PanelWindow` seam with a close/preventClose method.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Quit picked, hotkey available | Tray installed, menu pushed | Menu carries an enabled Quit entry; picking it emits on `quitRequests`; `DaemonLifecycle.shutdown()` runs its full ordered sequence, then `exit(0)` | No error expected |
| Quit picked, hotkey unavailable | `setHotkeyUnavailable(true)` pushed | Menu carries **three** entries — open-panel (enabled), the disabled statement line, Quit (enabled) — and Quit still emits | No error expected |
| Quit picked twice | First pick already draining | Second pick awaits the same latched `shutdown()` future rather than starting a second; a line states the daemon is already shutting down | Latch is `DaemonLifecycle.shutdown()`'s existing `_shutdown ??= _run()` |
| Open-panel picked | Menu pushed | `panelRequests` emits; `quitRequests` emits nothing | No error expected |
| The quit stream errors | Seam breaks its promise (AD-15 backstop) | Logged with `error_type` only; the subscription survives and a later pick still quits | Never ends the subscription — it is one of the daemon's two exit triggers |
| Tray disposed | `TrayManagerTray.dispose()` on the shutdown path | `quitRequests` is closed alongside `panelRequests`; a later pick emits nothing | Each close is guarded; a failure is a log line, never a daemon that cannot exit |
| Window close, panel visible | User activates the window-manager close control | `close` event arrives with the toplevel **still mapped**; the adapter issues a real `hide()`; the window unmaps, mirror reads false, `changes` emits false, daemon stays resident | A refused hide is logged with `error_type`; the daemon stays up |
| Window close, hide refused | `hide()` rejects | Logged; mirror already reads false (the mirror leads); no exception escapes into the zone | `unawaited(...catchError)`, the shape `_onBlur` already uses |
| Hotkey after a close | Panel closed, then hotkey pressed | Panel shows again — the toplevel was never destroyed, so it is still warm (CAP-1) | No error expected |

</intent-contract>

## Code Map

- `lib/src/domain/tray/tray_port.dart` -- the three-member port; gains `quitRequests`.
- `lib/src/infrastructure/tray/tray_manager_tray.dart` -- `_menu()` (:176-191) and `_onSelection` (:193-224), which accepts only `_openPanelKey`; `dispose()` (:138-149) closes the streams.
- `lib/src/infrastructure/tray/tray_menu_entry.dart` -- the `key`/`label`/`enabled` value the menu is built from. **No change needed.**
- `lib/main.dart` -- `_createHiddenWindow()` (:608-613) sets the window properties; `_installSignalHandlers` (:696-721) is the shape the quit handler mirrors; `_unresponsiveCallBudget` (:236) already bounds every teardown step (DW-20, landed).
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- `_onWindowEvent`'s `close` arm (:317-332) and `_onBlur` (:363-393).
- `test/architecture/hidden_window_test.dart` -- `_permittedWindowManagerCalls` (:380-384) allowlists the startup path's window_manager calls; the `containsAll` row (:184-210) pins the ones that carry behaviour.
- `test/architecture/composition_wiring_test.dart` -- source-scans `main.dart`, the one file no test can execute.
- `test/fakes/fake_tray_port.dart` -- the `TrayPort` fake used by four suites.
- `test/infrastructure/tray/tray_manager_tray_test.dart`, `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- the behavioural suites.
- `test/platform/tray_live_test.dart`, `test/platform/panel_visibility_live_test.dart` -- unconditionally skipped rows stating what this container cannot observe. `tray_live_test.dart` is listed in `_unpinnedLiveSuites`; `panel_visibility_live_test.dart` **is** pinned by `_pointers` and `_citations` (steps 5, 6, 7).

## Tasks & Acceptance

**Execution:**

1. `lib/src/domain/tray/tray_port.dart` -- add `Stream<void> get quitRequests`, documented as broadcast and as the tray's half of the daemon's two exit triggers (DW-114) -- the port carries no seam a quit could travel on today, so closing the gap widens the port as well as the menu.
2. `lib/src/infrastructure/tray/tray_manager_tray.dart` -- add `_quitKey`/`_quitLabel` constants, a broadcast `_quitRequests` controller, an always-enabled Quit entry **last** in `_menu()`, a `_quitRequests.add(null)` route in `_onSelection`, and a guarded `_quitRequests.close()` in `dispose()` -- rewrite `_onSelection`'s key test as a `switch` so the unknown-key and disabled-statement warnings stay exactly as they are.
3. `lib/main.dart` -- add `await windowManager.setPreventClose(true);` to `_createHiddenWindow()`, and an `_installQuitHandler({required TrayPort tray, required DaemonLifecycle lifecycle})` called immediately after `_installSignalHandlers(lifecycle)` -- the handler mirrors the signal watcher exactly: log if already stopping, `await lifecycle.shutdown()`, `exit(0)`, with an `onError` arm that logs and keeps the subscription alive.
4. `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- change the `close` arm from `_reconcile(false)` to a hide, extract the `unawaited(hide().catchError(...))` body `_onBlur` already has into a shared helper the two arms name, and rewrite the `close` arm's doc: the destroyed-toplevel caveat retires, and the story's `setPreventClose` ban is now spent. **The blur path's log line must still read `the window rejected the focus-loss hide`** — `window_manager_panel_visibility_test.dart:632` asserts `contains('focus-loss hide')`, so the shared helper takes the cause as a parameter rather than flattening the two messages into one.
5. `test/fakes/fake_tray_port.dart` -- add `quitRequests`, a `requestQuit()` driver, and close the controller in `dispose()`.
6. `test/infrastructure/tray/tray_manager_tray_test.dart` -- add rows for the Quit entry in both hotkey states, for the pick routing to `quitRequests` and not to `panelRequests`, for the open-panel pick emitting nothing on `quitRequests`, and for `dispose()` closing it.
7. `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- replace the `AD-8: a close moves the mirror` row: a close must now issue a real `hide` call against the window and leave `window.visible` false, not merely move the mirror. Add a row for a rejected close-hide being logged, and one proving a close leaves the adapter alive and a later show still works.
8. `test/architecture/hidden_window_test.dart` -- add `setPreventClose` to `_permittedWindowManagerCalls` with a comment stating it sets a plugin bool and makes no GTK call, and to the `containsAll` presence row -- the subset check can only forbid, and deleting this call silently restores a close that destroys the toplevel.
9. `test/architecture/composition_wiring_test.dart` -- add two rows: `DW-114` (the quit handler exists, is called with the tray and the lifecycle, sits after `_installSignalHandlers`, and its body reaches `lifecycle.shutdown()` and `exit(0)`) and `DW-12` (`setPreventClose(true)` is in `_createHiddenWindow`, before `runApp`).
10. `test/platform/tray_live_test.dart` -- extend the "what is owed on a real session" clause with the Quit entry actually stopping the daemon and clearing the indicator. Do not add step numbers; this suite is deliberately unpinned.
11. `test/platform/panel_visibility_live_test.dart` -- add a clause owing the close-is-a-hide claim: that a real window manager's close control produces the `close` event with `setPreventClose(true)` in effect and the toplevel survives. **Cite no step numbers and use no `step N` phrasing** — `_citations` pins the cited sequence as exactly 5, 6, 7.

**Acceptance Criteria:**

- Given a daemon whose hotkey bound successfully, when the tray menu is pushed, then it carries an always-enabled entry labelled `Quit` in addition to the open-panel entry.
- Given the hotkey is unavailable, when the tray menu is pushed, then the Quit entry is still present and still enabled, alongside the disabled statement line.
- Given a live daemon, when the user picks Quit, then `TrayPort.quitRequests` emits and the composition root runs `DaemonLifecycle.shutdown()`'s full ordered sequence before the process exits 0 — the same sequence a SIGTERM runs.
- Given a shutdown already draining, when the user picks Quit a second time, then no second teardown starts and the daemon still exits once.
- Given the panel is visible, when the window manager reports `close`, then the adapter issues a `hide` against the window, the window is left unmapped, `isVisible` reads false, `changes` emits false, and the process is still running.
- Given the panel was closed that way, when the hotkey is pressed, then the panel shows again — the toplevel was never destroyed.
- Given `dart analyze --fatal-infos`, when it runs over the changed tree, then it reports no issues.

## Spec Change Log

### 2026-08-14 — Review pass 1 (verification amendment only; no code re-derivation)

- **Triggering finding:** three of the four review layers independently found that the change leaves `test/platform/runtime-observation-checklist.md` stale. Group C is titled *The summon, the dismissal, and the echo*, so an operator completing it would reasonably believe the panel adapter's dismissal behaviour is settled — while DW-12's close-as-dismissal claim, the one thing in this change that can **only** be checked against a real window manager, appeared nowhere in the procedure. The existing tray bullet had likewise gone stale against `tray_live_test.dart`, which this change extended with the Quit claim.
- **What was amended:** the `## Verification` manual check that asserted an empty diff for the checklist. It was drawn too wide: it blocked an additive, zero-risk `## Not covered here` bullet along with the risky change the Never list actually targets. The Never list itself is unchanged and was not violated — it bans **adding or renumbering steps**, and none were added. The replacement check states the real constraint (prose-only, inside `## Not covered here`, no step or results-table edits, no step number cited, no `*Settles:*` line) and pins it with `runtime_checklists_test.dart`.
- **Known-bad state avoided:** a spurious HALT on `patch verification failed` for a two-bullet documentation fix, and — had the check simply been obeyed — an operator-facing procedure that silently under-reports what a completed run settles, which is the exact failure that section exists to prevent.
- **KEEP (must survive any re-derivation):** the numbered steps, the results table, the lettered groups and `runtime_checklists_test.dart` stay untouched — inserting a step renumbers every citation below it, and `panel_visibility_live_test.dart`'s skip reason must go on citing steps 5, 6 and 7 in that order and no others. `_dismiss` must keep taking the cause as a parameter so the blur line still reads `the window rejected the focus-loss hide`. The close arm must keep **no** `_outstanding` guard, and the row added in this pass is what now pins that.

## Review Triage Log

### 2026-08-14 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 0, medium 2, low 6)
- defer: 0
- reject: 9: (high 0, medium 3, low 6)
- addressed_findings:
  - `[medium]` `[patch]` The close arm's deliberate absence of an `_outstanding` guard was pinned by nothing — mutation-confirmed, since adding the guard left the whole panel suite green. Added a row emitting `close` while a `show` is parked; the mutation now fails exactly that row and nothing else.
  - `[medium]` `[patch]` `runtime-observation-checklist.md`'s `## Not covered here` had gone stale: added a DW-12 close-as-dismissal bullet routing to `panel_visibility_live_test.dart` and stating that group C's dismissal is the focus-loss one, and extended the tray bullet with DW-114's Quit claim. Prose only — no step added or renumbered, results table and `runtime_checklists_test.dart` untouched, suite still green.
  - `[low]` `[patch]` `FakeTrayPort.requestQuit()` had no callers anywhere — dead code (AGENTS.md §1) that read as coverage the tree does not have. Deleted; the getter and controller stay because the port requires them.
  - `[low]` `[patch]` The ellipsis guard matched only three ASCII full stops, so `Quit…` (U+2026) would have passed the assertion whose whole purpose is "an ellipsis promises a dialog". Now matches both spellings.
  - `[low]` `[patch]` `quitRequests`' documented broadcast guarantee was asserted nowhere, so a single-subscription controller would have passed every row. Added the two-independent-listeners row mirroring `panelRequests`'.
  - `[low]` `[patch]` The `setPreventClose` comment did not say the flag is global and permanent and so refuses a **session manager's** close too. Stated, along with why it is acceptable: a logout also delivers SIGHUP/SIGTERM, which the signal watchers cover.
  - `[low]` `[patch]` The `isShuttingDown` branch claimed parity with the repeat-signal branch; that holds only until teardown step 6 disposes the tray, after which repeat picks are silent. Comment narrowed to say so.
  - `[low]` `[patch]` `PanelWindow.events`' doc enumerated five event names and omitted `close`, which this change made load-bearing. Added, with the note that `setPreventClose(true)` means it arrives with the toplevel still mapped.

### 2026-08-14 — Review pass 2 (follow-up review of the completed run)

- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 0, medium 2, low 6)
- defer: 1: (high 0, medium 1, low 0)
- reject: 9: (high 0, medium 3, low 6)
- addressed_findings:
  - `[medium]` `[patch]` The close arm's *other* unguarded property — the deliberate absence of a `!_visible` guard — was pinned by nothing: all four close rows show the panel first, so inserting `if (!_visible) return;` into the shared `_dismiss` helper left the suite green (mutation-confirmed). Added a row that builds the stale-mirror-over-mapped-window state `_onBlur`'s own doc names as reachable, then emits `close`; the mutation now fails exactly that row and nothing else.
  - `[medium]` `[patch]` Nothing anywhere asserted that `close` reaches `PanelWindow.events`, although this change made that forwarding load-bearing: narrowing `WindowManagerPanelWindow.onWindowEvent` to drop `close` left both the binding-free gate and the channel-level suite green. Extended `test/platform/window_manager_panel_window_test.dart`'s event row to deliver and expect `close`; the mutation now fails it. `panel_window.dart`'s doc updated — the enumeration is no longer "the whole of the contract".
  - `[low]` `[patch]` The repeat-pick comment cited "teardown step 6" for the tray, while `DaemonLifecycle.shutdown()`'s doc — the thing a reader consults — numbers the tray step 5 (6 is only the raw `_step` call count). Now names the `closing the tray` step instead of an ordinal, and says why.
  - `[low]` `[patch]` The `isShuttingDown` line claimed the user "picked again", but `isShuttingDown` is true for *any* teardown — so a **first** pick landing during a `systemctl stop`, a logout or `_abort` printed a repeat that never happened. Reworded to state only what the flag supports.
  - `[low]` `[patch]` A first Quit pick wrote no line at all, leaving `DaemonLifecycle`'s bare `shutting down` — identical to a SIGTERM's — as the only trace of a user-initiated exit. Added the line; it is the first question asked when a resident daemon is found gone.
  - `[low]` `[patch]` `setPreventClose`'s comment justified a global, permanent refusal with "a logout also delivers SIGHUP", which does not hold for an XDG-autostart daemon with no controlling terminal — and this repo ships no `.service` unit. Narrowed to what is actually guaranteed (systemd scope stop → SIGTERM; terminal/X hangup → SIGHUP; otherwise the display connection drops), and states plainly that a close request alone does not reach the teardown, by design.
  - `[low]` `[patch]` The DW-12 wiring row bounded `_createHiddenWindow`'s body on `'\n}'` — the exact form the DW-114 row three lines above documents as wrong. Switched to `'\n}\n'` with the reason recorded, so a future named-parameter block cannot silently slice the body away and leave the `contains` inspecting a fragment.
  - `[low]` `[patch]` `_inventedKey` was `'open-settings'` — a plausible next menu entry, which is precisely the drift the constant was introduced to stop after `'quit'` became real. Changed to a key that cannot become one.
  - `[low]` `[patch]` `composition_wiring_test.dart`'s signal-handler row still titled the handlers "the only trigger for the ordered teardown", and repeated it in a `reason:` — false as of this change, and asserted three lines above the row that proves the opposite. Both restated as one of two triggers.

### 2026-08-14 — Review pass 3 (follow-up review of the completed run)

- intent_gap: 0
- bad_spec: 0
- patch: 7: (high 0, medium 3, low 4)
- defer: 2: (high 0, medium 1, low 1)
- reject: 11: (high 0, medium 3, low 8)
- addressed_findings:
  - `[medium]` `[patch]` The DW-12 close arm's central justification attributed the surviving toplevel to the wrong mechanism: `on_window_close` "emits `close` and *then* returns `_is_prevent_close`" guarantees nothing, because `_emit_event` is `fl_method_channel_invoke_method` (`window_manager_plugin.cc:959-965`) — an asynchronous channel invoke, so with the flag false GTK's default `delete-event` handler destroys the toplevel a full main-loop turn before Dart sees the event. The conclusion held only because of the `return TRUE` the comment did not credit. Corrected in all three places that carried the claim (`window_manager_panel_visibility.dart`, `composition_wiring_test.dart`, `window_manager_panel_visibility_test.dart`), each now naming `setPreventClose(true)` as the whole of the guarantee and pointing at the rows that hold it. Left alone: `main.dart` and `hidden_window_test.dart`, which already attributed it correctly.
  - `[medium]` `[patch]` The `isShuttingDown` branch — the largest block of reasoning in `_installQuitHandler`, and the implementation of the matrix's "Quit picked twice" row — was pinned by nothing: the DW-114 wiring row asserts the stream, the shutdown, the exit, their order, `onError:` and `error.runtimeType`, and never the branch. Deleting the whole if/else left `dart analyze` clean and every suite green. Added the assertion.
  - `[medium]` `[patch]` `close` reaching Dart through `WindowManagerPanelWindow.onWindowEvent` is load-bearing as of this change, and its only executing pin lives in `test/platform/`, which `.github/workflows/ci.yml` does not run. Adding an event-name filter to the forwarder passed the entire merge gate. Added `test/architecture/panel_event_forwarding_test.dart` — an in-gate source pin that the forwarder passes the raw name through and carries no name filter in any shape; mutation-confirmed, a `close` filter now fails exactly that row and nothing else in the architecture suite.
  - `[low]` `[patch]` The `onError` comment justified raw `stderr` with "this one has no `Logger` of its own to reach for", which is false — `_installQuitHandler`'s signature is this change's own, and `logger` is live at its call site. Restated as the choice it actually is: the two exit triggers are kept identical in what they leave behind, and the signal watchers are the ones that genuinely cannot reach a logger unhanded.
  - `[low]` `[patch]` The DW-114 row's forbidden-token scan banned the bare substring `'confirm'` over a body that is mostly comment prose, so writing "no confirmation step here" would fail a guard whose stated reason points at a comment. Now scanned over the comment-stripped code.
  - `[low]` `[patch]` `hidden_window_test.dart`'s "Both additions were mutation-verified" note named two pins while the paragraph above it now names three behaviour-carrying calls — and `composition_wiring_test.dart` asserted that mutation's result as established fact. Ran it: deleting `setPreventClose(true)` fails the presence row here plus the DW-12 wiring row, and nothing else. Note rewritten to cover all three.
  - `[low]` `[patch]` The presence row was titled "the four window-property calls" while the file doc counts three behaviour-carrying calls — `ensureInitialized` is plugin setup, not a window property. The change incremented a pre-existing off-by-one rather than fixing it; title and comment now state four calls, three of them property setters, and say why the two counts differ.

## Design Notes

**Where `setPreventClose` goes, and why `main.dart`.** It is a window *property*, set once, exactly like `setSkipTaskbar(true)` beside it — and unlike `show`/`hide`/`focus` it makes no GTK call at all: `set_prevent_close` assigns `self->_is_prevent_close` and returns (`window_manager-0.5.2/linux/window_manager_plugin.cc:70-77`). Putting it behind the `PanelWindow` seam would widen a seam whose whole purpose is the three toggle requests, and would move a startup-time property into the toggle's adapter. `hidden_window_test.dart`'s startup-path allowlist is the gate that has to be argued with, and the argument is the one above: this call cannot map or raise.

**Why the close arm hides rather than reconciles.** `on_window_close` emits `close` *and then* returns `_is_prevent_close` (`:967-971`), so with the flag set the event still arrives — but the toplevel is now **still mapped**. `_reconcile(false)` would therefore write a mirror that is a lie. The arm has to actually put the window away.

**No `_outstanding` guard on the close path.** `close` is a GTK `delete-event`; the adapter's only platform calls are `show`, `hide` and `focus`, so a close can never be an echo of ours. Skipping the guard is the direction DW-31 already decided for this event; DW-31's `minimize` half stays untouched.

**Menu order.** Quit goes last, after the conditional statement line: the statement explains why one would reach for the open-panel entry and belongs beside it, and a trailing Quit is what a desktop menu reads like.

Sketch of the two new pieces:

```dart
// tray_manager_tray.dart
void _onSelection(String key) {
  if (_disposed) return;
  switch (key) {
    case _openPanelKey: _panelRequests.add(null);
    case _quitKey:      _quitRequests.add(null);
    default:            _log(() => _logger.warning(/* the two existing arms */));
  }
}
```

```dart
// window_manager_panel_visibility.dart
case 'close':
  // DW-12: a close is a dismissal, not an exit. setPreventClose(true) means
  // the toplevel is still mapped when this arrives, so it has to be hidden.
  _dismiss('close');
```

## Verification

**Commands:**
- `dart analyze --fatal-infos` -- expected: no issues (`flutter_lints` reports at INFO, so the bare form is a weaker gate than AGENTS.md §6 asks for).
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: green, including the new tray, panel-visibility, `hidden_window_test.dart` and `composition_wiring_test.dart` rows, and the untouched `runtime_checklists_test.dart` rows.
- `flutter test test/composition test/ui` -- expected: green; these need a Flutter binding and are outside the scoped `dart test` command.
- `dart format --output=none --set-exit-if-changed lib test` -- expected: no reformatting needed.

**Manual checks:**
- `git diff -- _bmad-output/implementation-artifacts/deferred-work.md test/architecture/runtime_checklists_test.dart _bmad-output/specs/` -- expected: empty. All three are explicitly out of scope.
- `git diff -- test/platform/runtime-observation-checklist.md` -- expected: prose-only additions **inside `## Not covered here`**, with no numbered step added, renumbered or removed, no results-table row touched, no step number cited, and no `*Settles:*` line. Confirm with `dart test test/architecture/runtime_checklists_test.dart` -- expected: green. (Amended during review pass 1; see the Spec Change Log.)
- Read `test/platform/panel_visibility_live_test.dart`'s skip string and confirm it still cites steps 5, 6 and 7 and nothing else — `_citations` compares the cited sequence exactly.


## Auto Run Result

Status: done
Blocking condition: none

### Implemented change

A **follow-up review pass** over the already-landed change, not a re-implementation. No behaviour was re-derived and none changed: the daemon still has one exit path with two triggers — a tray `Quit` entry wired through `_installQuitHandler` to the same latched, per-step-bounded `DaemonLifecycle.shutdown()` a SIGTERM runs, then `exit(0)` (DW-114) — and a window close is still a dismissal, `setPreventClose(true)` plus a `close` arm issuing a real `hide()` through the shared `_dismiss(cause)` helper (DW-12).

What this pass changed is the reasoning that justifies that behaviour and the gates that hold it. One load-bearing causal claim was simply wrong and had propagated to three files; one branch and one plugin-to-Dart forwarding hop were shipping with no gate the merge command runs; and four comment or naming defects were corrected.

### Files changed

- `lib/main.dart` -- the `onError` comment's false "no `Logger` to reach for" justification replaced with the real reason the two exit triggers log alike.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- the `close` arm's justification now credits `setPreventClose(true)`'s `return TRUE` rather than the emit-before-return ordering, and names the rows that hold the flag.
- `test/architecture/panel_event_forwarding_test.dart` -- **new**: an in-gate source pin that `WindowManagerPanelWindow.onWindowEvent` forwards every event name unfiltered.
- `test/architecture/composition_wiring_test.dart` -- added the `isShuttingDown` pin; the forbidden-token scan now runs over comment-stripped code; the DW-12 comment's causal claim corrected.
- `test/architecture/hidden_window_test.dart` -- the mutation-verified note now covers all three pins and records this pass's run; the presence row's "four window-property calls" title corrected.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- the close row's comment corrected, and it now states that it assumes the mapped-toplevel premise rather than establishing it.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- two new entries appended. No existing entry modified, re-opened or rewritten, per the invocation.

### Review findings

7 patched (0 high, 3 medium, 4 low), 2 deferred, 11 rejected. Details in the Review Triage Log above.

Deferred: (1) the `## Not covered here` bullet this story added for DW-12 is registered in no pin, so deleting it leaves every row green — the fix is one phrase in `runtime_checklists_test.dart`, which the Never list bans touching; (2) both runtime claims the story owes trace only to always-skipped `fail()` reasons whose ledger ids are now closed, so nothing open requires anyone to observe them — registering them means new numbered steps and renumbering, the same reason the neighbouring DW-20 entry was filed rather than taken.

Rejected, with the reason: the `exit(0)`/`exit(1)` startup race (raised again by two lenses — already filed in the ledger by pass 2, so re-filing would duplicate); moving the quit stream into `DaemonLifecycle` so the AD-15 backstop becomes executable (a real asymmetry against `panelRequests`, but the intent names the composition root as where the wiring goes, and pass 2 adjudicated it); a `setPreventClose` ordering hazard between the adapter's construction (`main.dart:112`) and the flag (`:647`) — **checked and unreachable**: `linux/runner/my_application.cc` shows no toplevel, and `lifecycle.start()`, the only thing that lets a second launch map the window, runs at `:331`, after `_createHiddenWindow()`; an `onDone` arm on the quit subscription (the stream's completion *is* the normal teardown, so the proposed line would fire a false alarm on every clean exit); a try/catch around the `async` `onData` (total today because `shutdown()` guards every step, and identical in shape to the pre-existing signal path); coalescing repeated close-hides (bounded per event by `_requestTimeout` on a serialised chain, and re-introducing the guard class this change deliberately removed and now pins the absence of); routing a refused end-session request to the teardown (the comment already states this as a design decision, narrowed accurately in pass 2); pinning `quitCall` against `tray.install()` rather than `_finishStartup(` (an index comparison across a function declared far below is the meaningless question the DW-12 row itself warns about); looking tray menu entries up by identity rather than position (the `_menuWithoutStatement`/`_menuWithStatement` shape constants already fail on any inserted entry); and dropping the hard-coded `'Quit'` label (the acceptance criterion names the literal).

Follow-up review recommended: **true**. Patched severities: high 0, medium 3, low 4 -> score `3x3 + 1x4 = 13`, at or above the threshold of 5.

### Verification performed

- `dart analyze --fatal-infos` -- no issues found.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- `+889 ~2 -3`, then `+890 ~2 -2` on a re-run. The count is consistent with pass 2's `+890 ~2 -1` plus the one new architecture row. Every failure in both runs is inside `wayland_portal_global_hotkey_test.dart`, and on a **different set of rows each time** (A16/A19c/A19d, then A6/CAP-1, then A5/C2 running that file alone) — the pre-existing load-sensitive flake already open in the ledger. Nothing outside that file failed in any run, and this change touches no part of the hotkey ring.
- `flutter test test/composition test/ui` -- `+144`, all passed.
- `flutter test test/platform/window_manager_panel_window_test.dart` -- `+6`, green.
- `dart test test/architecture/runtime_checklists_test.dart` -- `+39`, green (the checklist was not touched this pass).
- `dart format --output=none --set-exit-if-changed lib test` -- 174 files, 0 changed.
- Manual checks: `deferred-work.md` was appended to only; `runtime_checklists_test.dart`, `test/platform/runtime-observation-checklist.md` and `_bmad-output/specs/` are untouched (empty diff); `panel_visibility_live_test.dart`'s skip string still cites steps 5, 6 and 7 and no others.
- Mutation-verified, both new gates, with files restored from scratchpad backups rather than `git checkout`: deleting `await windowManager.setPreventClose(true)` fails exactly the `hidden_window_test.dart` presence row and the `composition_wiring_test.dart` DW-12 row (`+44 ~1 -2`), and nothing else; adding an `if (eventName == 'close') return;` filter to `WindowManagerPanelWindow.onWindowEvent` fails exactly the new forwarding row across the whole architecture suite (`+224 ~1 -1`).

### Residual risks

- **The runtime half is still unobserved**, unchanged from passes 1 and 2, and now filed: no compositor and no StatusNotifier host exists in this container, so neither "picking Quit stops the daemon and clears the indicator" nor "a real close control delivers `close` with the toplevel still mapped" was observed. The premise behind DW-12 is still taken on the plugin source — which this pass at least re-read and corrected the reading of.
- **`test/platform/` is still outside the CI gate.** The new architecture row narrows what that costs for the `close` forwarding specifically, but every other `test/platform/` row still protects a local run rather than a merge. A CI-scope decision, not a defect this story exposed.
- **The startup exit-code race is written down but not fixed** — filed by pass 2, raised again by two lenses this pass.
- **A flaky suite still masks regressions in its own file.** `wayland_portal_global_hotkey_test.dart` fails a varying row on any tree, including standalone; nothing in this change touches the hotkey ring, but that file cannot currently be read as a gate.
- **The two new deferrals both require editing a file the intent bans touching.** Whoever picks them up needs the ban lifted first; they are not local edits.
