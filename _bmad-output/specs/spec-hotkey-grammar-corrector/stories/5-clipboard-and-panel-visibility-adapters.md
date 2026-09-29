---
title: 'Clipboard and panel visibility adapters'
type: 'feature'
created: '2026-08-07'
status: 'done'
baseline_revision: '3f6ffdc4c2d88ad30e403ba2a5d1a7c04b3faa07'
final_revision: '7d62345a3810ba80a2a0c6b1c3f7ee7eb05d8220'
review_loop_iteration: 1
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/deferred-work.md'
  - '{project-root}/lib/src/domain/panel/panel_visibility.dart'
  - '{project-root}/lib/src/domain/clipboard/clipboard_port.dart'
  - '{project-root}/lib/src/application/panel_controller.dart'
  - '{project-root}/lib/src/application/correction_controller.dart'
  - '{project-root}/lib/main.dart'
warnings: ['multiple-goals', 'oversized']
---

<intent-contract>

## Intent

**Problem:** The two ports the panel actually sits on have no backend. `UnimplementedPanelVisibility` reports `isVisible: false` forever and rejects every `show()`; `UnimplementedClipboard` rejects every read and write. So CAP-2's pre-fill, CAP-11's copy and CAP-14's toggle and focus-loss hide are wired end to end through the controllers and reach nothing. Two ledger items are blocked on exactly this adapter: AD-8's visibility mirror must flip **synchronously inside `show()`/`hide()`**, not only from window events, or a fast double hotkey press shows twice and never hides — a defect `FakePanelVisibility` cannot express, because it flips synchronously by construction; and `PanelVisibility.changes` never declared whether it is broadcast, while the panel widget (story 9) and `CorrectionController` will both need it, so a single-subscription adapter would throw on the second listener at startup.

**Approach:** Ship `SystemClipboard` over Flutter's own `Clipboard` service, and `WindowManagerPanelVisibility` over `window_manager`, both behind their existing domain ports, and install them at the composition root in place of the two placeholders. The visibility adapter owns an intent-first mirror: `show()`/`hide()` set it before their first await and emit on `changes`, and window events reconcile it only when no request of ours is outstanding — which is what makes a second press inside the window-manager round trip hide the panel instead of showing it again. `window_manager` is confined to one file behind an infrastructure-private `PanelWindow` seam so the mirror logic, including a simulated round-trip lag, is unit-testable with no Flutter binding.

## Boundaries & Constraints

**Always:**
- AD-8: `isVisible` is a synchronous in-process field and never an IPC query. The mirror is assigned **before the first `await`** in `show()` and `hide()`. Nothing on the show path allocates, loads, or awaits IO before the mirror is current, and `PanelController.onHotkeyActivated()` stays unchanged — the toggle must not learn about this fix.
- AD-8 / CAP-1: `show()` makes the window **visible and focused**. `window_manager`'s Linux `show` is `gtk_widget_show` alone and does not raise or focus, so a focus call is part of the contract, not polish.
- AD-8 / CAP-14: the adapter performs the focus-loss hide itself, from the window's blur event, and the mirror and `changes` reflect it like any other transition.
- AD-18: `changes` emits **exactly on a transition of `isVisible`**, in both directions and whatever caused it, because `CorrectionController` re-seeds a fresh session from the current clipboard on every `true` (CAP-2).
- AD-1: `window_manager` and Flutter's `Clipboard` stay inside `lib/src/infrastructure/`. `lib/src/domain/**` still imports only `dart:` libraries and `lib/src/application/**` still imports no infrastructure; `test/architecture/ad1_import_rule_test.dart` stays green with no change to its rules.
- The only permitted domain edit is documenting `PanelVisibility.changes` as broadcast (ledger item 2). No new port members, no changed signatures, no changes to `ClipboardPort`.
- Consistency Conventions: adapters named for their technology, one public type per file, structured stderr lines through the one `Logger`, and **never** a clipboard value, `input_text` or a suggestion body in a log line or an error message.
- AGENTS.md §8: no faked behaviour. A claim that is not observed in this container is stated as unobserved, and a test that cannot run here is `skip`ped with a reason rather than weakened until it passes.
- Every test outside `test/platform/` and `test/composition/` runs with no Flutter binding, and cites its CAP or AD id.

**Block If:**
- Making `changes` broadcast, or documenting it as such, turns out to require changing `PanelVisibility`'s declared members or signatures rather than adding a doc comment — that is a spine-verbatim AD-8 declaration and a wider domain edit than the ledger authorised.
- Satisfying CAP-14's focus-loss hide turns out to require a new member on `PanelVisibility` (a focus signal the application ring must consume). The dispatch authorises one doc edit and nothing more, so a second domain edit is a renegotiation, not an unattended choice.

**Never:**
- No tray adapter (story 6), no real hotkey backend (stories 7, 8), no panel or settings widgets (stories 9, 10). The window keeps `DaemonApp` as its root.
- No new dependency and no pubspec pin change. Flutter's `Clipboard` is already in the graph; `window_manager 0.5.2` is already pinned.
- No X11 primary selection, and nothing above the clipboard port may assume one exists — phase 2, and X11-only.
- Do not reach around `window_manager` to its raw method channel to shave a round trip, and do not add a `setPreventClose`/`WindowListener` close-path hook (DW-12) — both are separate deliberate decisions.
- Do not fix the other open ledger entries riding on these files: `PanelController`'s missing `_disposed` guards, the un-deduped clipboard-read warning (DW-11's sibling), DW-9's unobserved AD-8 runtime claim, DW-12's shutdown coverage, DW-16 through DW-24. They stay filed.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Toggle from hidden (CAP-1, AD-8) | Mirror false; `show()` called | `isVisible` is true **before** `show()`'s future completes; `changes` emits true once; the window is shown and then focused | A rejected window call leaves the mirror true and rejects the returned future |
| Toggle from visible (CAP-14) | Mirror true; `hide()` called | `isVisible` is false before the future completes; `changes` emits false once | As above, mirrored |
| **Fast double press** (AD-8, the ledger item) | A window whose show/hide round trip and event echo both lag; two toggle presses inside that lag | The panel ends **hidden**: press 1 reads false and shows, press 2 reads true and hides, and the late `show` echo does not resurrect it | No error expected |
| Own echo, single press | `show()` outstanding; the window's own `show` event arrives | Mirror unchanged, `changes` emits nothing further — the transition was already reported | No error expected |
| External change | No request outstanding; a `hide` event arrives (the window manager unmapped the window) | Mirror becomes false and `changes` emits false — this is the only case a window event moves the mirror | No error expected |
| Focus-loss hide (CAP-14) | Mirror true, no request outstanding; a `blur` event arrives | The adapter hides: mirror false, `changes` emits false, the window is hidden | A rejected hide is logged; the mirror stays false |
| Blur while hidden | Mirror false; a `blur` event arrives | Nothing happens — no hide call, no emission | No error expected |
| Blur during a show | A `show()` is outstanding; a `blur` event arrives | Ignored — a user cannot have dismissed a panel that is still being mapped | No error expected |
| Two listeners (ledger item 2) | Two independent subscriptions to `changes`, then a transition | Both receive it; neither subscription throws | Never throws `Bad state: Stream has already been listened to` |
| Late listener | A subscription attached after a transition | Receives only subsequent transitions; `isVisible` is the way to read the current value | No error expected |
| Adapter disposed | `dispose()` called, then a window event arrives | No emission, no window call; `changes` is closed; the window listener is deregistered | Never throws; a second `dispose()` is a no-op |
| Clipboard read, text present (CAP-2) | System clipboard holds `'hello'` | `readText()` resolves to `'hello'` | No error expected |
| Clipboard read, empty (CAP-2) | Clipboard holds no plain text | `readText()` resolves to null — absence is a modelled value | No error expected |
| Clipboard read denied (CAP-2) | The platform channel rejects | The rejection propagates as a failed future; `CorrectionController` already logs it and leaves the editor empty | Never returns null in place of a failed read |
| Clipboard write (CAP-11) | `writeText('corrected')` | Exactly that string reaches the system clipboard | A platform rejection propagates as a failed future |
| Daemon startup (AD-8) | `main()` runs to `runApp` | The real adapters are the bound overrides; nothing shows the window; shutdown disposes the visibility adapter before the graph's other adapters close | An adapter that fails to dispose is logged, and shutdown completes |

</intent-contract>

## Code Map

- `lib/src/domain/panel/panel_visibility.dart` -- AD-8's verbatim port. Receives **one doc edit only**: `changes` is documented as broadcast, matching `ConfigStore.changes`. Members and signatures untouched.
- `lib/src/domain/clipboard/clipboard_port.dart` -- unchanged. Its null contract ("empty or holds no plain text") is what the adapter must honour.
- **`window_manager 0.5.2`, the three behaviours that decide this design** (verified in `~/.pub-cache/hosted/pub.dev/window_manager-0.5.2/`): `show()` is `await isMinimized()` *then* `invokeMethod('show')` (`lib/src/window_manager.dart:209`) while `hide()` invokes immediately (`:221`) — so unserialised requests reach the platform out of order. Linux `show` is bare `gtk_widget_show` and `focus` is `gtk_window_present`, which **maps** a hidden toplevel (`linux/window_manager_plugin.cc:78`, `:95`). And `show`/`hide` are emitted by the Linux plugin (`:987`, `:993`) but have no typed `WindowListener` callback and no entry in the dispatch map (`lib/src/window_manager.dart:58-74`), so `onWindowEvent(String)` is the only route to them.
- `lib/src/infrastructure/panel/unimplemented_panel_visibility.dart`, `lib/src/infrastructure/clipboard/unimplemented_clipboard.dart` -- **deleted**; the placeholders this story replaces (DW-11's panel and clipboard halves).
- `test/infrastructure/panel/unimplemented_panel_visibility_test.dart`, `test/infrastructure/clipboard/unimplemented_clipboard_test.dart` -- deleted with them.
- `lib/main.dart` -- `_container()` binds `clipboardProvider` and `panelVisibilityProvider` to the two placeholders at lines 187 and 189; both become the real adapters. `_createHiddenWindow()` already calls `windowManager.ensureInitialized()`, which must happen before the adapter registers its listener.
- `lib/src/infrastructure/system/daemon_lifecycle.dart` -- the ordered teardown (`shutdown()`, lines 127–136). Gains one step for the visibility adapter, between the graph and the hotkey.
- `lib/src/application/panel_controller.dart` -- the AD-8 toggle. **Unchanged**: the fix belongs entirely to the adapter, and its `isVisible` doc comment's reason for not re-exposing `changes` ("the port does not declare its stream broadcast") stops being true.
- `lib/src/application/correction_controller.dart` -- the one live subscriber to `changes` today (line 49); AD-18's re-seed is what makes the emission contract load-bearing.
- `test/fakes/fake_panel_visibility.dart` -- flips synchronously and so cannot express the defect; its broadcast comment already says the port declaration is AD-8 verbatim. Left as the application ring's fake.
- `test/architecture/composition_wiring_test.dart` -- asserts every declared seam is overridden in `main.dart`; the two override *values* change under it.
- `test/architecture/hidden_window_test.dart` -- an **allowlist** of the `window_manager` methods the startup path may reach. Adding `show`/`hide`/`focus` calls to `lib/` will trip it unless the allowlist's scope is understood first.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- holds the two entries this story closes.

## Tasks & Acceptance

**Execution:**

*The domain doc edit (ledger item 2)*
- `lib/src/domain/panel/panel_visibility.dart` -- document `changes` as broadcast, in the same terms `ConfigStore.changes` uses, and say why: the panel widget (story 9) and `CorrectionController` are two independent consumers, so a single-subscription implementation would throw on the second listener at startup. Add nothing else.

*The panel-visibility adapter (ledger item 1 — the story's centre)*
- `lib/src/infrastructure/panel/panel_window.dart` -- create `PanelWindow`: `Future<void> show()`, `Future<void> hide()`, `Future<void> focus()`, `Stream<String> get events` (raw window event names), `Future<void> dispose()` -- an infrastructure-private seam whose only justification is the ledger's: the defect lives in the gap between a request and its echo, so a test must be able to *lengthen* that gap, which no mock of a singleton can do without a binding.
- `lib/src/infrastructure/panel/window_manager_panel_window.dart` -- create `WindowManagerPanelWindow implements PanelWindow, WindowListener`; register with `windowManager.addListener(this)`, push `onWindowEvent(name)` into a broadcast controller, deregister and close on `dispose()`. Note in the doc **why `onWindowEvent` and not typed callbacks**: `window_manager 0.5.2` emits `show` and `hide` from its Linux plugin but declares no `onWindowShow`/`onWindowHide` on `WindowListener` and no entry for them in its dispatch map, so the untyped hook is the only route to them.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- create `WindowManagerPanelVisibility implements PanelVisibility` over a `PanelWindow` and the `Logger`, using the three-part mechanism in Design Notes. `show()` and `hide()` assign the mirror and emit on `changes` **before their first await**, then enqueue the request. Requests are **serialised**, and a request whose intent the mirror no longer holds is **abandoned without touching the window** — issuing neither its `hide` nor its `show`-then-`focus`, since `focus()` maps a hidden window and would resurrect a panel a later press dismissed. Track outstanding requests; a `show`/`hide` window event moves the mirror **only when none is outstanding**. A `blur` event hides only when the mirror is true and nothing is outstanding (CAP-14). `minimize` sets the mirror false and `restore` sets it true -- `gtk_window_iconify` emits no GTK `hide` signal, so without this an iconified panel leaves the mirror claiming it is up and the next press is wasted. `changes` is broadcast and emits exactly on a transition. `show()` and `hide()` are **no-ops once disposed** (not only `_setMirror`), or a press landing in the teardown gap between the adapter closing and the hotkey adapter closing moves a real window whose mirror is frozen. `dispose()` deregisters, closes the stream, and is idempotent.
- `lib/src/infrastructure/clipboard/system_clipboard.dart` -- create `SystemClipboard implements ClipboardPort` over `package:flutter/services.dart`'s `Clipboard`: `readText()` is `(await Clipboard.getData(Clipboard.kTextPlain))?.text`, `writeText` is `Clipboard.setData(ClipboardData(text: text))` -- no new dependency, and no logging of either value.

*Composition (so the adapters have real backing)*
- `lib/main.dart` -- bind `clipboardProvider` to `SystemClipboard` and `panelVisibilityProvider` to `WindowManagerPanelVisibility` over a `WindowManagerPanelWindow`; delete the two placeholder imports; pass the adapter's `dispose` into `DaemonLifecycle`. Two ordering constraints, because this story is what makes the mapping path live: the adapter must be constructed before any window event can fire (its constructor is what registers the listener — do **not** justify this by `ensureInitialized()`, which on Linux answers a bare `true` and connects nothing); and the lifecycle's **show-request subscription must not be live before `runApp`**, or an AD-14 second launch arriving during startup maps an untitled, taskbar-listed, widget-tree-less window. Keep `_installSignalHandlers` where it is — its early position is separately pinned — and move only the subscription. Also dispose the adapter on `_abort`'s early branch, where `lifecycle` is null: it has already registered a window listener, which that method's doc currently denies.
- `lib/src/infrastructure/system/daemon_lifecycle.dart` -- add a required `closePanelVisibility` step, run after the graph is disposed and before the hotkey adapter -- the controllers must be gone before the window listener is torn down, or a late event reaches a disposed controller.
- `lib/src/infrastructure/panel/unimplemented_panel_visibility.dart`, `lib/src/infrastructure/clipboard/unimplemented_clipboard.dart` and their two tests -- delete; nothing references them once `main.dart` is rewired, and AGENTS.md §1 forbids leaving them.

*Tests*
- `test/fakes/fake_panel_window.dart` -- create the lag-modelling fake, which must model **window state as well as call order**: a `bool visible` that `show` and `focus` set true (`focus` is `gtk_window_present`) and `hide` sets false, an optional `isMinimized` pre-hop on `show` so a `hide` can overtake it, calls that park until the test releases them with any number in flight, and the event emitted on release before the future completes. A fake that records only call *names* is what let the reverted attempt pass with the panel still on screen -- recording names proves the mirror, and only window state proves the panel.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- create; every panel row of the I/O matrix. **Every row that ends in a settled window must assert `window.visible == visibility.isVisible`** — that single assertion is what makes this suite able to fail for the real defect. The load-bearing row: **two toggle presses driven through `PanelController` against a lagging window, settle everything, and assert the panel is hidden — mirror false, `window.visible` false, and the window never left mapped.** Run it twice, once with the `isMinimized` pre-hop enabled, since that variant reorders the platform calls rather than merely delaying them. Include the negative controls as a comment recording the mutations, not as extra tests. Pure Dart, no binding.
- `test/infrastructure/panel/panel_visibility_broadcast_test.dart` -- create; two independent listeners on one adapter both receive a transition, and a late listener misses the earlier one (ledger item 2).
- `test/platform/window_manager_panel_window_test.dart` -- create; drive the real `WindowManagerPanelWindow` through a mocked `window_manager` method channel: assert the **exact** call sequence for `show` (`['isMinimized', 'show']`, not a `contains`, so the pre-hop this design turns on is visible rather than filtered out of the assertion), that `hide` and `focus` invoke their methods, and that an inbound `onEvent` for `show`, `hide` and `blur` reaches `events`. This is the only thing that proves the untyped-`onWindowEvent` routing assumption, which the pure-Dart tests take on trust. Needs a binding, hence its own directory.
- `test/platform/system_clipboard_test.dart` -- create; the four clipboard rows over a mocked `SystemChannels.platform`: text present, no plain text, a rejected read, and a write carrying exactly the given string.
- `lib/src/application/panel_controller.dart` -- **doc only**: its `isVisible` comment says `changes` is not re-exposed because "the port does not declare its stream broadcast", which this story's domain edit makes false. Replace the reason with the real one (application-ring layering: the controller owns the toggle, not the stream) and change nothing else. The reverted attempt left this contradicting the port it sits on.
- `test/platform/panel_visibility_live_test.dart` -- create; one test, unconditionally `skip`ped with the reason that CAP-14's focus-loss hide and CAP-1's "visible and focused" need a real desktop session, which this container does not have (no compositor, no xdg-desktop-portal, no keybinder-3.0, no reachable X display — DW-9). It names the claim so it is owed rather than forgotten; it must never be written so it could pass here. The skip reason must **also** name the one assumption the `_outstanding` guard rests on and no test can check — that a request's own window echo arrives while that request is still in flight, rather than after its method-channel reply. Today that ordering is asserted only by the fake that was written to match it; if the real platform reverses it, a superseded `show` echo is believed and `changes` emits a spurious `true`, which under AD-18 is a cleared editor and a fresh clipboard read against a hidden panel. File it in the ledger alongside the runtime claims.
- `test/architecture/hidden_window_test.dart` -- extend the `window_manager` allowlist to admit the adapter's `show`/`hide`/`focus` while keeping the **startup path** ban intact: nothing `main.dart` reaches before `runApp` may show the window. State in the test's doc which file is now allowed to call `show` and why AD-8 is still enforced. Two shape requirements, both learned from story 4's review of this same file: assert the reached calls are a **subset** of the permitted set, never set equality — equality also *requires* every permitted call and turns a legitimate refactor red; and carry the anti-aliasing guard the file already has for `WindowManager.instance` across to any new scan, so `final wm = windowManager; wm.show();` cannot walk past it.
- `test/infrastructure/system/daemon_lifecycle_test.dart` -- the new step's position is right, but do not justify it with "a late window event must not reach a disposed controller": `CorrectionController.dispose()` cancels its own visibility subscription two steps earlier, so that hazard cannot occur. State the reason that does hold — the adapter must outlive every controller that can still call `show`/`hide` on it, and must close before the process exits.
- `test/architecture/composition_wiring_test.dart` -- assert the two new override *values* by name, the way this file already asserts the hotkey override's value, so swapping an adapter back to a placeholder fails a test.
- `test/composition/composition_root_test.dart`, `test/infrastructure/system/daemon_lifecycle_test.dart` -- update for the new lifecycle step and assert its position in the order by transposition, matching how the existing ordering assertions are pinned.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- mark the two entries this story closes with `status: done 2026-08-07` and a `resolution:` line **rather than deleting them** — DW-13 and its story-2 predecessor both record that the delete instruction is the recurring defect, and this story is where that stops. Append new findings.

**Acceptance Criteria:**
- Given a `PanelVisibility` whose window round trip lags, when the hotkey toggle fires twice inside that lag, then **both the mirror and the window** end hidden — no `show` and no `focus` reach a window the second press dismissed, and the late echo does not resurrect it (AD-8, CAP-14). Holds with and without `show()`'s `isMinimized` pre-hop, and the test fails if the mirror assignment moves after the await, if requests stop being serialised, or if a superseded request still issues its call.
- Given the shipped adapter, when two independent consumers subscribe to `changes`, then both receive every transition and neither subscription throws (AD-8, CAP-2 by way of AD-18).
- Given the daemon's built graph, when a correction session begins, then the clipboard text it seeds from came from the system clipboard rather than a placeholder, and no clipboard value appears in any log line (CAP-2, Consistency Conventions).
- Given the full suite, when `dart analyze`, `dart format --set-exit-if-changed lib test`, the binding-free `dart test` run and `flutter test` all run, then all four pass, including `test/architecture/ad1_import_rule_test.dart`, and no test asserts a runtime claim this container cannot observe (baseline: `dart test` 419 passed / 2 skipped; `flutter test` 437 passed / 3 skipped).
- Given the deferred-work ledger, when the story completes, then its two entries carry `status: done` with a resolution, every other entry is byte-identical, and `flutter build linux --debug` still succeeds.

## Spec Change Log

### 2026-08-08 — The prescribed mirror mechanism could not satisfy the matrix row it was written for

**Triggering finding.** `[high]` The fast double press — the single defect this story exists to close — left the panel **visible on screen** with `isVisible` reporting false. Confirmed empirically by a review probe that modelled window state: with the shipped mechanism the platform call order was `show, hide, focus` and the window ended mapped; with `windowManager.show()`'s `isMinimized` pre-hop modelled it was `hide, show, focus` and the window still ended mapped. Two independent mechanisms: `focus()` is `gtk_window_present`, which **maps a hidden toplevel**, so the trailing focus of a superseded request re-shows the panel; and `show()`'s pre-hop lets an unserialised later `hide()` overtake it. `[high]` No test could see either, because the prescribed fake recorded call *names* and no window state — so the whole suite, both mutation checks, and the four verification commands were green over a broken panel.

**What was amended.** All outside `<intent-contract>`; the I/O matrix row already said "The panel ends **hidden**" and was correct as written — it was the mechanism beneath it that could not deliver it.
- **Design Notes** — the single-mechanism explanation and its code snippet are replaced by the three that must hold together: the mirror leads, requests are serialised, and a superseded request is abandoned without touching the window. The snippet now shows the queue and the intent check.
- **Code Map** — the three `window_manager 0.5.2` behaviours that decide the design are now stated with file and line, so the next implementer does not have to rediscover that `focus` maps and `show` has a pre-hop.
- **Tasks** — the adapter task requires serialisation, abandonment of superseded requests, `minimize`/`restore` handling and post-dispose no-ops on `show`/`hide`; the fake task requires window state and an optional pre-hop; the test task requires `window.visible == visibility.isVisible` on every settled row and the double-press row run in both pre-hop modes; `main.dart` gains the show-subscription ordering and the `_abort` disposal; and the doc-accuracy fixes (`PanelController`, the lifecycle test's stated reason, the `ensureInitialized` rationale) are named.
- **Verification** — two mutations become four, and each is stated as a gate rather than a report.

**Known-bad state this avoids.** A daemon whose panel is on screen while every controller above it believes it is hidden: the next press hides it (looking correct by luck), the one after shows it again, and the mirror never self-corrects because the resurrecting `show` echo is discarded by the outstanding-request guard. That is the ledger's "shows twice and never hides", re-entered through the focus call — shipped with a green suite and a mutation record that certified the wrong thing.

**KEEP — these survived review and must survive re-derivation.**
- The `PanelWindow` seam, `WindowManagerPanelWindow`, and confining `window_manager` to that one file. The seam is what made the defect findable at all, and its `onWindowEvent`-only rationale is correct and verified.
- `SystemClipboard` over Flutter's `Clipboard` with no new dependency, and no logger on it at all, so no clipboard value can reach a log line by construction. All four clipboard rows passed.
- Setting the mirror before the first await, and the `_outstanding` guard on window events. Both are necessary and both were mutation-verified; they were merely not sufficient.
- Closing the two ledger entries **in place** with `status: done` and a `resolution:` line rather than deleting them (44 insertions, 0 deletions). This deliberately overrides the dispatch's "remove each entry when done" on the authority of the ledger's own append-only format contract and DW-13, which records that instruction as the recurring upstream defect. Keep it.
- The unconditionally skipped live test with a `fail()` body, the honest "not observed in this container" reporting, and the deferred entries recording what was consciously left.
- Deleting both `Unimplemented*` placeholders and their tests once nothing references them.

## Review Triage Log

### 2026-08-08 — Review pass (2)
- intent_gap: 0
- bad_spec: 0
- patch: 11: (high 0, medium 2, low 9)
- defer: 8: (high 0, medium 5, low 3)
- reject: 5: (high 0, medium 0, low 5)
- addressed_findings:
  - `[medium]` `[patch]` The AD-8 startup ban was walkable. `_aliasingFiles` matched only the assignment shape (`=\s*windowManager\s*[;,)]`), so `WindowManager get _wm => windowManager;` plus `await _wm.restore();` in `_createHiddenWindow()` — `gtk_window_deiconify` + `gtk_window_present`, which maps **and** raises the toplevel before `runApp` — passed all 13 tests in `hidden_window_test.dart`. Confirmed end to end by probe. The guard now flags any mention of the receiver not immediately followed by a member access, and `_windowManagerCalls` takes `\.{1,2}` so a cascade lands in the allowlist. All four evasion shapes (arrow getter, argument, cascade, list literal) now fail the suite.
  - `[medium]` `[patch]` The story's stated gate had two contradictory records of itself: the test file's mutation counts (13/2/4/3) and the ledger's (11/1/2/3) disagreed on three of four, and the ledger's "`_outstanding` guard deleted → 1" sat one test from the "fails zero tests" threshold. All four were re-run against the shipped tree with the exact edit stated for each — 13/2/3/3 — and recorded once, in the test file; the ledger's resolution now cites it instead of restating numbers.
  - `[low]` `[patch]` The `_outstanding` guard's coverage of `restore`, which the adapter's own doc calls load-bearing, was pinned by nothing: mutating the `restore` arm to `_setMirror(true)` past the guard failed zero tests (the wholesale guard-deletion mutation fails two, but both are `show`-echo rows). Added a row driving a `restore` echo while a show is outstanding with a hide queued behind it; the mutation now fails it.
  - `[low]` `[patch]` `windowManager.removeListener(this)` was required by no test — the "a disposed seam deregisters" row asserted only silence, which `_disposed` and the closed controller already guarantee. Deleting the call failed zero tests. The row now observes `windowManager.listeners` directly, before and after `dispose()`.
  - `[low]` `[patch]` `DaemonLifecycle.start()` had no shutdown guard, and this story is what made it reachable after `shutdown()` by moving `start()` after `runApp` while leaving the signal handlers early. A SIGTERM in that window ran the whole teardown and then subscribed to an already-released lock. Added `if (_shuttingDown) return;` with a row that shuts down, starts, and asserts no request reaches the panel.
  - `[low]` `[patch]` DW-25 declared the echo-ordering assumption checkable by nothing but `FakePanelWindow`; the plugin source settles it (`_emit_event` is called synchronously from `on_window_show`/`on_window_hide`, inside the `gtk_widget_show` the method handler itself invokes, so the event goes out before the reply — `window_manager_plugin.cc:959`, `:987`, `:993`). Entry downgraded to low with the citation, and the live test's skip reason corrected to owe only the last link.
  - `[low]` `[patch]` The double-press row's "run it twice" pre-hop variant executes an identical path in the shipped tree — the superseded request returns before touching the window, so the pre-hop is never entered and both runs issue `['hide']`. Recorded as a mutation-only discriminator instead of being presented as reordering coverage.
  - `[low]` `[patch]` Two architecture pins were weaker than they read: the test named "the **two** window-property calls" asserts three, and the `_abort` pin was a raw substring that checked neither the `panelVisibility != null` guard nor the step's position. Renamed, and the pin now asserts the guard and that the step precedes the address release.
  - `[low]` `[patch]` `_permittedAdapterCalls`' doc claimed a `restore` "has to be justified here first", but the permitted `show` reaches `restore` transitively (`window_manager.dart:209`). Doc now scopes the allowlist to direct calls and names the branch.
  - `[low]` `[patch]` The `close` arm's comment claimed a benefit it does not deliver: `on_window_close` returns `_is_prevent_close` (false by default) so GTK destroys the toplevel, and the next press is then spent showing a window that no longer exists rather than hiding one. Comment now states that the mirror is merely honest either way and that reachability after a close belongs to DW-12.
  - `[low]` `[patch]` `_abort`'s doc asserted "no controllers exist" on the no-lifecycle path — false when `DaemonGraph.build()` throws partway, which leaves subscribed controllers behind. This story's diff had rewritten that sentence and left the false half standing. Doc corrected; the teardown gap itself is filed as DW-37.

### 2026-08-08 — Review pass
- intent_gap: 0
- bad_spec: 4: (high 2, medium 2, low 0)
- patch: 9: (high 0, medium 0, low 9)
- defer: 4: (high 0, medium 2, low 2)
- reject: 4: (high 0, medium 0, low 4)
- addressed_findings:
  - `[high]` `[bad_spec]` The fast double press left the panel visible on screen with the mirror reading false — the defect the story exists to close, re-entered through `focus()` (`gtk_window_present` maps a hidden toplevel) and through `show()`'s `isMinimized` pre-hop letting an unserialised `hide()` overtake it. Confirmed by a window-state probe in both pre-hop modes. Design Notes and the adapter task now require serialisation plus abandonment of superseded requests.
  - `[high]` `[bad_spec]` The prescribed fake recorded call names and no window state, so no test in the suite could observe the above; the suite, both mutations and all four verification commands were green over a broken panel. The fake task now requires a modelled `visible` and an optional pre-hop, and every settled test row must assert `window.visible == visibility.isVisible`.
  - `[medium]` `[bad_spec]` `show()`/`hide()` carried no post-dispose guard (only `_setMirror` did), so a press landing in the teardown gap between the adapter closing and the hotkey adapter closing moved a real window whose mirror was frozen. The adapter task now requires the guard on the request path.
  - `[medium]` `[bad_spec]` `DaemonLifecycle..start()` subscribed the now-real mapping adapter to AD-14 show requests before `_prepareHiddenWindow` and `runApp`, so a second launch during startup could map an untitled, taskbar-listed, widget-tree-less window — a path only this story made live. The `main.dart` task now constrains where the subscription starts, while leaving the separately-pinned signal-handler position alone.

## Design Notes

**The mirror is intent-first — but a correct mirror is not a correct panel.** Three mechanisms have to hold together, and getting only the first is the trap this story fell into once already (see the Spec Change Log).

*One — the mirror leads.* The naive adapter sets the mirror from window events alone; the ledger names why that fails. The naive *fix* — set it on call **and** on every event — fails worse: the late `show` echo of a superseded request sets it true again. So an event is believed only while no request of ours is outstanding, which is the one case an event knows something the intent does not: the window manager acting on its own.

*Two — requests are serialised.* `windowManager.show()` is **not** one channel call: it awaits an `isMinimized()` hop and only then invokes `show`, while `hide()` invokes immediately. Two unserialised requests therefore reach the platform out of order — a `hide()` issued during a `show()` arrives **first**, and the show maps the window afterwards. This is a reordering point, not a latency point.

*Three — a superseded request is abandoned, not completed.* `show()` must also focus, because `window_manager`'s Linux `show` is `gtk_widget_show` alone and neither raises the window nor takes the keyboard, while CAP-1 asks for "visible **and** focused" and AD-8's port comment says "show + focus". But `focus()` is `gtk_window_present`, and **`gtk_window_present` maps a hidden toplevel**. So a trailing `focus()` belonging to a request a later press already superseded puts the panel back on screen with the mirror reading false.

Serialising and checking the intent at the moment the request runs is what satisfies all three at once:

```dart
// the shape, not the implementation
Future<void> show() { _setMirror(true); return _enqueue(true); }   // before any await
Future<void> hide() { _setMirror(false); return _enqueue(false); }

Future<void> _enqueue(bool intended) {
  final result = _queue.then((_) => _apply(intended));
  // The chain must survive a rejected request; the caller still sees the rejection.
  _queue = result.catchError((Object _) {});
  return result;
}

Future<void> _apply(bool intended) async {
  if (_disposed) return;
  if (_mirror != intended) return;   // a later press already superseded this one
  _outstanding += 1;
  try {
    if (!intended) return await _window.hide();
    await _window.show();
    await _window.focus();
  } finally {
    _outstanding -= 1;
  }
}
```

Trace the ledger's case: press 1 sets the mirror true and enqueues `true`; press 2 sets it false and enqueues `false`. `_apply(true)` finds `_mirror == false` and does nothing at all — no `show`, no `focus`, and so no echo either. `_apply(false)` hides. The window and the mirror both end hidden. **The acceptance test must assert the window's state, not only the mirror's** — asserting the mirror alone is what let the shipped-and-reverted attempt pass while the panel stayed on screen.

**Why the focus-loss hide lives in the adapter.** CAP-14 requires it and AD-8 names it among the window events the adapter keeps the mirror current from. The alternative — the application ring deciding it — needs a focus signal on `PanelVisibility`, which is a second domain edit and beyond what the dispatch authorised. So the binding constraints select the adapter uniquely; this is not a free choice, and it is why the Block If names the other reading rather than leaving it open.

**Why a `PanelWindow` seam at all.** AGENTS.md §4.2 warns against abstractions with no variance and no test need. The test need here is explicit and is the ledger's own instruction: the defect is a *timing* one, so a test has to widen the request-to-echo gap. `windowManager` is a singleton behind a private channel — reachable in tests only through a mocked channel, which needs a Flutter binding and cannot easily hold two requests open in a controlled order. One seam keeps the mirror logic in `dart test`'s binding-free set, where AGENTS.md §7 wants it, and confines `window_manager` to one file. The channel-level assumption the seam takes on trust — that `show`/`hide` reach Dart only through the untyped `onWindowEvent` — is then pinned by its own binding-requiring test rather than assumed.

**`changes` emits on transitions, not on calls.** `CorrectionController` starts a fresh session on every `true` (AD-18), so a duplicate emission is a duplicate clipboard read and a discarded editor. `hide()` on an already-hidden panel, or a `show` echo for a transition already reported, must emit nothing. The invariant is one emission per change of `isVisible`, whatever caused it.

## Verification

**Commands:**
- `dart analyze` -- expected: no issues (AGENTS.md §6 merge gate).
- `dart format --output=none --set-exit-if-changed lib test` -- expected: 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: all pass, proving the mirror logic needs no Flutter binding. Baseline on this story's parent revision: 419 passed, 2 skipped.
- `flutter test` -- expected: the whole suite including `test/platform/` and `test/composition/`. Baseline: 437 passed, 3 skipped; the new live-claim test must appear as **skipped**, never as passed.
- `flutter build linux --debug` -- expected: succeeds, proving the adapters, `window_manager` and the edited runner still compile and link.
- **Mutation checks, and they are the story's real gate.** Apply each, re-run the binding-free suite, record how many tests fail, and revert. **Any that fails zero tests means the defect is not actually closed and the test is the thing to fix.**
  1. Move the mirror assignment in `show()`/`hide()` from before the await to after it.
  2. Delete the `_outstanding > 0` guard in the event handler.
  3. **Delete the superseded-request check** (`if (_mirror != intended) return;`) so an abandoned request still issues its window calls. This is the mutation that reproduces the reverted attempt: it must fail the double-press row, and it will only do so if that row asserts the window's state and not just the mirror's.
  4. **Remove serialisation** so requests run concurrently. With the `isMinimized` pre-hop enabled this reorders the platform calls, and the double-press row must fail.

**Manual checks (if no CLI):**
- **Not observable here, and must be reported as such.** This container has no compositor, no keybinder-3.0, no xdg-desktop-portal and no reachable X display (DW-9 records that `:10` refuses authorization and there is no `Xvfb`). So "the panel becomes visible and focused", "it hides when it loses focus", and the real double-press timing are **not observed** by this story. They are pinned by the lagging-fake test, the channel-level test, and the build. Say so in the completion notes; do not restate a fake or a mock as a runtime observation.
- Confirm by inspection that `window_manager` is imported by exactly one file under `lib/` (`window_manager_panel_window.dart`) plus `main.dart`'s existing window setup, and that no clipboard value or panel text reaches a log line.

## Auto Run Result

Status: done
Blocking condition: none

**Implemented change.** `SystemClipboard` over Flutter's `Clipboard` and `WindowManagerPanelVisibility` over `window_manager`, both behind their existing domain ports, installed at the composition root in place of `UnimplementedClipboard` and `UnimplementedPanelVisibility`. The visibility adapter carries the three mechanisms AD-8 needs together: the mirror is assigned and `changes` emits before the first await of `show()`/`hide()`; requests are serialised through a queue; and a request whose intent the mirror no longer holds issues nothing at all, because `focus()` is `gtk_window_present` and maps a hidden toplevel. `window_manager` is confined to one file behind an infrastructure-private `PanelWindow` seam, which is what makes the round-trip lag modellable without a Flutter binding. Both deferred-work items the dispatch named are closed in place with `status: done` and a `resolution:` line: the synchronous mirror (item 1) and `PanelVisibility.changes` documented as broadcast with a broadcast implementation and a two-listener test (item 2, the single authorised domain edit).

**Files changed.** 23 files across the two commits from the baseline (`3f6ffdc` implementation, `7d62345` review pass):

- `lib/src/domain/panel/panel_visibility.dart` — `changes` documented as broadcast; members and signatures untouched.
- `lib/src/infrastructure/panel/panel_window.dart` — the seam: `show`/`hide`/`focus`/`events`/`dispose`.
- `lib/src/infrastructure/panel/window_manager_panel_window.dart` — the seam over `window_manager`, routing through the untyped `onWindowEvent` because 0.5.2 declares no typed `show`/`hide` callbacks.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` — the mirror, the queue, the superseded-request abandonment, the focus-loss hide, and the event reconciliation.
- `lib/src/infrastructure/clipboard/system_clipboard.dart` — two delegating lines, no logger, so no clipboard value can reach a log line by construction.
- `lib/main.dart` — the two real adapters bound; the AD-14 show subscription moved after `runApp`; the adapter disposed on the early-abort branch.
- `lib/src/infrastructure/system/daemon_lifecycle.dart` — the panel-visibility teardown step, and (review pass) the `start()` shutdown guard.
- `lib/src/application/panel_controller.dart` — doc only: the stale "the port does not declare its stream broadcast" reason replaced.
- Deleted: both `Unimplemented*` placeholders and their two tests.
- Tests: `fake_panel_window.dart` (models window state, not just call names), `window_manager_panel_visibility_test.dart`, `panel_visibility_broadcast_test.dart`, `system_clipboard_test.dart`, `window_manager_panel_window_test.dart`, `panel_visibility_live_test.dart` (unconditionally skipped), plus updates to `hidden_window_test.dart`, `composition_wiring_test.dart` and `daemon_lifecycle_test.dart`.

**Review findings.** Four layers ran in parallel (adversarial, edge-case, verification-gap, intent-alignment). 24 findings: 0 intent_gap, 0 bad_spec, 11 patched, 8 deferred, 5 rejected. Patched by severity: high 0, medium 2, low 9 — score `3×2 + 9 = 15`, so `followup_review_recommended: true`. Deferred as DW-30 through DW-37 (medium 5, low 3); DW-25 downgraded to low against plugin source.

The load-bearing patch: the AD-8 startup ban was walkable. `_aliasingFiles` matched only the assignment shape, so `WindowManager get _wm => windowManager;` plus `await _wm.restore();` in `_createHiddenWindow()` — which maps *and* raises the toplevel before `runApp` — passed all 13 tests. Confirmed end to end by probe, then closed and re-probed against four evasion shapes (arrow getter, argument, cascade, list literal), all of which now fail.

**Verification performed.**

- `dart analyze` — no issues.
- `dart format --output=none --set-exit-if-changed lib test` — 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` — 452 passed, 2 skipped (baseline 419/2).
- `flutter test` — 481 passed, 4 skipped (baseline 437/3). `panel_visibility_live_test.dart` reports as **skipped**, never passed.
- `flutter build linux --debug` — succeeds.
- **Mutation checks.** All four re-run against the shipped tree with the exact edit stated for each, because the two prior records disagreed on three of four: mirror-after-await **13**, `_outstanding` guard deleted **2**, both superseded-request checks deleted **3**, serialisation removed **3**. None fails zero tests. Three further probes each failed **zero** before this pass and **one** after the rows added for them: `restore` walking past the guard, `removeListener` deleted, and `start()`'s shutdown guard deleted.

**Not observed, and stated as unobserved.** This container has no compositor, no keybinder-3.0, no xdg-desktop-portal and no reachable X display. CAP-1's "visible and focused", CAP-14's focus-loss hide at runtime, and the real double-press timing are **not observed** by this story. They are pinned by the lagging fake, the channel-level test and the build — none of which is a runtime observation, and none is reported as one. Recorded as DW-9 and DW-26.

**Residual risks.**

- Five deferred entries are behavioural corners the intent's own I/O matrix prescribes (DW-30 through DW-33, DW-37). Each was implemented exactly as written; each is a boundary worth revisiting deliberately rather than a deviation. DW-32 and DW-33 are the two a user could notice: a blur during a raise of an already-visible panel is dropped rather than deferred, and a blur with no preceding focus dismisses a panel that never held the keyboard.
- The `wasEverVisible` assertion in the double-press row is stronger than the intent's own trace, and its strength comes from the fake always letting the second press overtake the first. At runtime that is a race the adapter does not control; the intent's requirement still holds either way.
- `main()` remains reachable by no test, so the composition assertions are source-text `contains` and index comparisons (pre-existing, DW-8/DW-24). This story added four more to that surface.
- The story shipped with `warnings: ['multiple-goals', 'oversized']` and nothing here can be reverted independently.

## Phase 02 disposition of frozen panel intent (2026-09-24)

The frozen I/O row at line 65 records the original story 5 intent and remains historical. Its unconditional “blur during a show is ignored” rule was widened by DW-32: when an already-visible, focused panel receives a blur during a second `show()`, `WindowManagerPanelVisibility._onBlur` latches it and `_releaseDeferredBlur` reconsiders it after the request settles. DW-33 also changed the premise for dismissal: a blur without a preceding focus does not hide a panel that never held the keyboard. See `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` (`_onBlur`, `_releaseDeferredBlur`) and `spec-dw-31-panel-window-event-reconciliation.md` (I/O matrix and Spec Change Log).

The residual-risk claim above that DW-30 through DW-33 were all “implemented exactly as written” is historical and false for DW-32 and DW-33 after that later work. This disposition preserves the approved intent and its review history while identifying the shipped behavior. The real-compositor behavior of those two cases remains **unobserved**; fake and channel rows do not establish a native-session result.
