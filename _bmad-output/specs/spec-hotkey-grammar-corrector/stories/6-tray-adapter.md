---
title: 'Tray adapter'
type: 'feature'
created: '2026-08-08'
status: 'done'
baseline_revision: 'f9ba1e7bd3a39fbabbbcd20ba56d887a012f3fe9'
final_revision: 'f9d9d3e3679d194c327c87ab3206e9acc912656c'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/deferred-work.md'
  - '{project-root}/lib/src/domain/tray/tray_port.dart'
  - '{project-root}/lib/src/domain/hotkey/hotkey_bind_outcome.dart'
  - '{project-root}/lib/src/infrastructure/panel/panel_window.dart'
  - '{project-root}/lib/src/infrastructure/system/daemon_lifecycle.dart'
  - '{project-root}/lib/src/infrastructure/system/daemon_startup.dart'
  - '{project-root}/lib/main.dart'
warnings: ['oversized']
---

<intent-contract>

## Intent

**Problem:** `TrayPort` has existed since the domain ring was bootstrapped and nothing implements it: `UnimplementedTray` rejects every call, `install()` has no caller in `lib/`, and nothing subscribes to `panelRequests`. Meanwhile four shipped user-facing strings — both stub hotkey adapters, `DaemonStartup.requestBinding`, and `SettingsController._bind` — already tell the user that the hotkey is inactive but "the tray menu still opens the panel". On a wlroots compositor (Sway, Hyprland, Niri), which ships no GlobalShortcuts portal backend, that sentence is AD-12's whole fallback and it currently names an affordance that does not exist.

**Approach:** Implement `TrayManagerTray` behind `TrayPort` — a resident indicator whose menu opens the panel through `PanelController.showPanel()`, and which states hotkey unavailability on both of its visible surfaces (the icon image and a disabled menu line). `tray_manager` is confined to one infrastructure file behind a `TrayIcon` seam, mirroring the `PanelWindow` seam story 5 established, so the menu wiring and the state mapping stay unit-testable with no Flutter binding and no system tray. The composition root installs the tray before it requests the hotkey binding and routes tray panel requests through the same `DaemonLifecycle` handler AD-14's second-launch show requests already reach.

## Boundaries & Constraints

**Always:**
- AD-1: `package:tray_manager` is named by **exactly one** file under `lib/`, and `package:menu_base` by none — `tray_manager.dart` re-exports it, so importing it directly would also add an undeclared dependency (`depend_on_referenced_packages`). Nothing above infrastructure sees a `Menu`, a `MenuItem`, or a channel.
- AD-8: the tray's open-panel action reaches `PanelVisibility.show()` through the existing `PanelController.showPanel()`. The tray constructs no window and touches no `window_manager` API.
- AD-12: unavailability is **visible on the tray**, not merely accepted — and the open-panel entry stays enabled while it is shown, because the tray is the way in precisely when the hotkey is not.
- AD-12/spine Operational envelope: a missing dependency degrades one capability and **never blocks startup**. A tray that will not install is a logged error and a daemon that still runs.
- AD-14: the tray is the resident daemon's own icon. A second launch is signalled through the existing lock and raises this icon's panel; nothing here starts a second indicator.
- The `HotkeyUnavailable` state is read from `lib/src/domain/hotkey/hotkey_bind_outcome.dart` (story 3). Do not re-declare it, and do not widen `TrayPort` — `install` / `panelRequests` / `setHotkeyUnavailable` is the whole contract.
- Native ordering (`tray_manager-0.5.3/linux/tray_manager_plugin.cc`): `set_context_menu` and `set_title` dereference the `AppIndicator*` that `set_icon` creates. The icon is therefore always set before any menu is pushed, and no menu is pushed before `install()`.
- Never log clipboard-derived or suggestion text (Consistency Conventions); the tray sees neither, and must not acquire a reason to.

**Block If:**
- Satisfying AD-12's visible statement would require widening `TrayPort` or editing `PanelVisibility`/`PanelController`. Both are out of this story's authority; halt rather than edit a port.
- `tray_manager 0.5.3` turns out not to build or not to expose a click route on the pinned Flutter 3.44.8 / Dart 3.12.2. Say so and propose the replacement rather than leaking indicator semantics upward (the AD-9 precedent story 7 is given for `hotkey_manager`).

**Never:**
- No Quit/Settings/History menu entries. AD-12 names one action — open the panel — and a Quit item needs an exit path `DaemonLifecycle` does not expose (already filed as DW-12).
- No settings-screen work: AD-12's other consumer is story 10, and DW-17 (the discarded startup bind outcome) stays open.
- No real X11/Wayland/portal work, no tray screenshot, and **no test that fakes a passing result** for anything this container cannot observe: there is no compositor, no xdg-desktop-portal, no keybinder-3.0 and no StatusNotifier host here.
- Do not touch `lib/src/application/**` or `lib/src/domain/**`. The tray is infrastructure plus composition.
- Do not reword the four "the tray menu still opens the panel" strings — this story is what makes them true.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| A1 install, hotkey state unknown | fresh `TrayManagerTray`, `install()` | seam receives exactly `setIcon(<available icon>)` **then** `setMenu([open-panel: enabled])`, in that order; no unavailability entry | a rejecting seam propagates — the composition root is what guards it |
| A2 open the panel | installed; seam emits the open-panel entry's key | `panelRequests` emits exactly once | No error expected |
| A3 unknown selection key | seam emits a key no entry carries | nothing emitted on `panelRequests`; one warning logged | No error expected |
| A4 hotkeys unavailable | installed; `setHotkeyUnavailable(true)` | `setIcon(<unavailable icon>)` and `setMenu([open-panel: enabled, unavailable statement: disabled])` — both surfaces state it, and the way in stays enabled | a rejecting seam propagates |
| A5 hotkeys available again | after A4; `setHotkeyUnavailable(false)` | back to the available icon and a menu with no statement entry | as A4 |
| A6 same state twice | after A4; `setHotkeyUnavailable(true)` again | no seam call at all | No error expected |
| A7 state before install | fresh tray; `setHotkeyUnavailable(true)` then `install()` | the first makes **no** seam call; the `install()` then sets the unavailable icon and the statement menu | a menu pushed before the icon exists dereferences a null indicator natively — hence no call |
| A8 selection stream errors | installed; seam's `selections` adds an error | logged at error level (type only); the subscription survives and a later A2 selection still emits | AD-15 backstop |
| A9 dispose | installed tray; `dispose()` | the seam is disposed, `panelRequests` closes, and a later `install()`/`setHotkeyUnavailable()` makes no seam call | No error expected |
| A10 two listeners | two independent `panelRequests` subscriptions; one A2 selection | both receive it | the port documents the stream as broadcast |
| B1 icon reaches the plugin | `TrayManagerTrayIcon.setIcon('assets/tray/…png')` over a mocked `tray_manager` channel | exactly one `setIcon` invocation whose `iconPath` ends with the asset path | No error expected |
| B2 menu reaches the plugin | `setMenu([...])` | exactly one `setContextMenu` invocation carrying the labels and `disabled` flags, in order | No error expected |
| B3 click reaches Dart | an inbound `onTrayMenuItemClick` for an installed item | `selections` emits that entry's key | an id matching no installed item emits nothing |
| B4 seam dispose | `dispose()` | a `destroy` invocation, the listener deregistered from the `tray_manager` singleton, `selections` closed; later calls invoke nothing | No error expected |
| C1 tray request reaches the panel | lifecycle started; tray `panelRequests` emits | the same `onShowRequest` handler AD-14's socket request reaches; fired, never awaited (CAP-1) | No error expected |
| C2 tray request stream errors | lifecycle started; the tray stream adds an error | logged at error level naming the tray; the subscription survives for the next request | AD-15 backstop |
| C3 ordered teardown | `shutdown()` | the tray subscription is cancelled in step 1 alongside the show-request one; the tray closes after the panel visibility adapter and before the hotkey adapter | a rejecting close is logged and every later step still runs |
| C4 request after shutdown | `shutdown()` begun; tray emits | reaches nothing | No error expected |
| D1 a real desktop | a session with a StatusNotifier host | the icon appears, its menu opens the panel, and the unavailable state is visible on icon and menu | **Not observable here** — an unconditionally skipped test with a `fail()` body and an explicit reason |

</intent-contract>

## Code Map

- `lib/src/domain/tray/tray_port.dart` -- the port being implemented: `install()`, `panelRequests` (documented broadcast), `setHotkeyUnavailable(bool)`. **Read-only — no edit, no widening.**
- `lib/src/domain/hotkey/hotkey_bind_outcome.dart` -- `HotkeyUnavailable` (story 3). Consumed indirectly: `DaemonStartup.bindHotkey` already reduces the outcome to the `bool` this port takes. **Read-only.**
- `lib/src/infrastructure/panel/panel_window.dart`, `window_manager_panel_window.dart` -- the seam idiom to mirror exactly: an infrastructure-private interface, one file naming the vendor package, a broadcast event stream, a `_disposed` guard on every method.
- `lib/src/infrastructure/tray/unimplemented_tray.dart` -- **deleted** by this story, with `test/infrastructure/tray/unimplemented_tray_test.dart`.
- **`tray_manager 0.5.3`, the four facts that decide this design** (verified in `~/.pub-cache/hosted/pub.dev/tray_manager-0.5.3/`): the Linux handler implements only `destroy`, `setIcon`, `setTitle`, `setContextMenu` — **`setToolTip` is not implemented and would throw** (`linux/tray_manager_plugin.cc:152-171`). `set_context_menu` and `set_title` call `app_indicator_set_menu`/`app_indicator_set_label` with **no null check**, and only `set_icon` creates the indicator (`:105-129`), so icon-before-menu is a crash-avoidance rule, not a preference. Clicks arrive as one `onTrayMenuItemClick` channel call carrying the item `id`, dispatched to `MenuItem.onClick` *and* every `TrayListener` (`lib/src/tray_manager.dart:56-71`). `setIcon` joins `dirname(Platform.resolvedExecutable)` + `data/flutter_assets` + the given path (`:112-122`), so the argument is an **asset path**, and the asset must be declared in `pubspec.yaml`.
- `lib/src/infrastructure/system/daemon_lifecycle.dart` -- owns what a panel request reaches and the teardown order. Gains a second request stream and one close step; `start()`'s post-shutdown guard and the `_step`/`_log` idioms are already there.
- `lib/src/infrastructure/system/daemon_startup.dart` -- `bindHotkey(tray:)` already calls `setHotkeyUnavailable` and already guards it. **Unchanged**; it is the caller this story finally gives a real implementation.
- `lib/main.dart` -- `_container()` binds `trayProvider` to `const UnimplementedTray()` at line 66/249; `_finishStartup` is where install slots in, before `startup.bindHotkey`.
- `pubspec.yaml` -- `tray_manager: 0.5.3` is already pinned and `linux/flutter/generated_plugins.cmake` already lists it; `ayatana-appindicator3-0.1` is present in this container, so `flutter build linux --debug` links it. The `assets:` block gains one directory.
- `test/fakes/fake_tray_port.dart` -- the **application ring's** fake. Unchanged: it fakes the port, while this story's new fake fakes the seam beneath it.
- `test/architecture/hidden_window_test.dart` -- its startup-path scan covers all of `lib/` except `lib/src/infrastructure/panel/`, so any `window_manager` call added under `lib/src/infrastructure/tray/` fails it. That is the AD-8 "the tray must not construct a window" gate, already in place.
- `test/architecture/composition_wiring_test.dart` -- asserts every seam is overridden in `main.dart` and pins startup ordering by source index; the tray override value and two new ordering rows go here.
- `test/infrastructure/system/daemon_lifecycle_test.dart` -- the `_Harness` and the recorded-sequence ordering idiom the new rows extend.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- DW-18 ("the tray is never installed…") names story 6 as its closer and DW-11's tray third disappears with the deleted file. See Design Notes: close **in place**, never by deletion.

## Tasks & Acceptance

**Execution:**

- `assets/tray/hotkey-grammar-corrector.png`, `assets/tray/hotkey-grammar-corrector-hotkey-unavailable.png` -- add two 32×32 RGBA PNGs, the second visibly marked as degraded -- `setIcon` takes an asset path, so AD-12's icon half needs two real files; record in Design Notes how they were generated so they are reproducible rather than mysterious binaries.
- `pubspec.yaml` -- declare `assets/tray/` under `flutter: assets:` -- an undeclared asset is not in `flutter_assets`, so the indicator would be created with a path to nothing and show a broken icon with no error.
- `lib/src/infrastructure/tray/tray_menu_entry.dart` -- **new**; a `final class TrayMenuEntry {key, label, enabled}` with value equality -- the plain description the seam takes, so no `menu_base` type crosses it.
- `lib/src/infrastructure/tray/tray_icon.dart` -- **new**; the infrastructure-private seam `setIcon(String assetPath)`, `setMenu(List<TrayMenuEntry>)`, `Stream<String> get selections` (broadcast), `dispose()` -- document the icon-before-menu native rule on `setMenu`, and state the test need that justifies a single-implementation abstraction (AGENTS.md §4.2), as `panel_window.dart` does.
- `lib/src/infrastructure/tray/tray_manager_tray_icon.dart` -- **new**; the seam over `tray_manager`, the **only** file under `lib/` naming it -- import `package:tray_manager/tray_manager.dart` alone (it re-exports `menu_base`, so a direct `package:menu_base` import would be an undeclared dependency); mix in `TrayListener`, register in the constructor, translate entries to `Menu`/`MenuItem` preserving order and `disabled`, emit the clicked item's `key` on `selections`, and `dispose()` → `removeListener` + `destroy()` + close, with a `_disposed` guard on every method. Do not call `setToolTip`.
- `lib/src/infrastructure/tray/tray_manager_tray.dart` -- **new**; `TrayManagerTray implements TrayPort` -- holds the two icon asset paths as public constants, subscribes to `selections` in the constructor, maps the open-panel key onto a broadcast `panelRequests`, keeps `_installed` and `_hotkeyUnavailable` and pushes icon-then-menu only when installed and only when the state actually changed, logs an unknown key and a `selections` error through the house `_log` swallow, and no-ops after `dispose()`.
- `lib/src/infrastructure/tray/unimplemented_tray.dart` -- **delete**, with `test/infrastructure/tray/unimplemented_tray_test.dart` -- nothing may reference it once the real adapter is bound (story 5's precedent for the other two placeholders).
- `lib/src/infrastructure/system/daemon_lifecycle.dart` -- add a `trayRequests` stream constructor parameter and a `closeTray` step -- both subscriptions are cancelled in shutdown step 1 through one private helper that keeps their log messages distinct; `closeTray` runs after `closePanelVisibility` and before the hotkey. Update the class doc's numbered teardown list so it still describes what the method does.
- `lib/main.dart` -- construct `TrayManagerTray(icon: TrayManagerTrayIcon(), logger: logger)`, bind it to `trayProvider`, pass `trayRequests: tray.panelRequests` and `closeTray: tray.dispose` to the lifecycle, and `await` a **guarded** `tray.install()` in `_finishStartup` after `lifecycle.start()` and before `startup.bindHotkey` -- install failure is one logged error, never an aborted startup; hold the instance in the `_abort`-visible scope the way `openedPanelVisibility` is held, so an aborted startup still closes it.
- `test/fakes/fake_tray_icon.dart` -- **new**; a `TrayIcon` fake recording ordered calls with their arguments, with per-method error injection and an `emitSelection`/`emitSelectionError` seam -- the ordering is the assertion A1 and A7 rest on, so the fake records a sequence, not a set.
- `test/infrastructure/tray/tray_manager_tray_test.dart` -- **new**; binding-free (`package:test`), covering matrix rows A1–A10 with the CAP/AD id in each name, plus a group asserting both icon assets exist on disk and that `pubspec.yaml` declares their directory -- the asset rows are a real gate: nothing else would notice a renamed or unlisted PNG until a user saw a blank indicator.
- `test/platform/tray_manager_tray_icon_test.dart` -- **new**; binding-required, over a mocked `tray_manager` `MethodChannel`, covering B1–B4 -- **not skipped**: the channel is reachable headlessly, and this is the only place the seam's translation to `menu_base` and the click route are observed.
- `test/platform/tray_live_test.dart` -- **new**; one unconditionally skipped test with a `fail()` body and a reason naming what is missing here (no StatusNotifier host, no compositor, no reachable display) and what D1 owes -- never write it so it could pass in this container.
- `test/infrastructure/system/daemon_lifecycle_test.dart` -- extend the `_Harness` with a tray stream and a `closeTray` recorder and add rows C1–C4 -- the ordering rows must read the recorded sequence, so transposing two steps in `shutdown()` fails them.
- `test/architecture/composition_wiring_test.dart` -- add rows for the tray override value (`TrayManagerTray(`), the `trayRequests: tray.panelRequests` join, the `closeTray:` step, and `install(` appearing after `lifecycle.start()` and before `startup.bindHotkey(` -- source-index assertions, the idiom this file already uses for the AD-8 and AD-14 orderings.
- `test/architecture/tray_confinement_test.dart` -- **new**; AD-1: scan `lib/` and assert `package:tray_manager` is referenced by exactly `lib/src/infrastructure/tray/tray_manager_tray_icon.dart`, that `package:menu_base` is referenced by no file under `lib/`, and that no file under `lib/src/infrastructure/tray/` references `window_manager` -- the last half is AD-8's "the tray must not construct a window", stated where a reader looks for it.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- mark DW-18 and DW-11 `status: done` **in place** with a `resolution:` line each, touching no other entry -- see Design Notes for why this diverges from the dispatch's "closes no deferred-work item".

**Acceptance Criteria:**

- Given a daemon start, when `_finishStartup` runs, then `tray.install()` is awaited after `lifecycle.start()` and before `startup.bindHotkey(...)`, so the indicator exists before the first `setHotkeyUnavailable` pushes a menu.
- Given `tray.install()` rejects, when startup continues, then the daemon comes up anyway and the failure is logged at error level with the error type only.
- Given the AD-1 gate, when the suite runs, then `package:tray_manager` is named by exactly one file under `lib/`, `package:menu_base` by none, and no file under `lib/src/infrastructure/tray/` names `window_manager`.
- Given a wlroots session where the bind resolves to `HotkeyUnavailable`, when startup finishes, then both tray surfaces state it — the unavailable icon and a disabled menu line — while the open-panel entry stays enabled.
- Given the completion notes, when the story is reported, then every claim this container cannot observe (D1, and the indicator ever appearing on a panel) is stated as unobserved, with the skipped test named.

## Spec Change Log

## Review Triage Log

### 2026-08-08 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 17: (high 1, medium 3, low 13)
- defer: 6: (high 0, medium 2, low 4)
- reject: 4: (high 0, medium 0, low 4)
- addressed_findings:
  - `[high]` `[patch]` `setHotkeyUnavailable` committed `_hotkeyUnavailable` before `_push()` could fail, and the same-value short-circuit then blocked every retry — probe-confirmed to leave the icon swapped, the statement line absent, and no route back through the port, on exactly the session AD-12 exists for. The previous value is now restored on failure and rethrown, and the test whose *name* already claimed this property now checks its second half.
  - `[medium]` `[patch]` `install()` set `_installed = true` before the push landed, so an install dying at `setMenu` left a real indicator on screen with no menu and the follow-up `setHotkeyUnavailable(false)` short-circuited forever. Now set only after `_push()` completes.
  - `[medium]` `[patch]` The install guard's `logger.error(...)` bypassed `main.dart`'s own `_log` swallow, so a broken stderr turned "the tray is missing" into `exit(1)` — inverting the guard's stated purpose. Routed through `_log`.
  - `[medium]` `[patch]` The install guard was pinned by no test: deleting the try/catch left the whole suite green. `composition_wiring_test.dart` now asserts `try {` before and `on Object catch` after `tray.install()`, and that the log goes through `_log(`.
  - `[low]` `[patch]` `_raisePanel()` logged "for a second launch" for tray-originated failures, undoing one layer down the per-stream split introduced one layer up. A `source` label is now threaded through, with a test row per path asserting the other source is not named.
  - `[low]` `[patch]` `TrayManagerTrayIcon.dispose()` skipped `_selections.close()` when `destroy()` rejected, and `_disposed` made a retry a no-op — two of the three things its doc promises. Closed in a `finally`.
  - `[low]` `[patch]` The channel-level suite asserted nothing about the two methods the seam's doc singles out. It now asserts `setToolTip` and `setTitle` are never invoked, and that `setIcon` precedes `setContextMenu` at the channel.
  - `[low]` `[patch]` The asset gate checked existence and byte-inequality only. It now checks the PNG signature, the `IHDR` marker and 32×32 from the big-endian dimensions.
  - `[low]` `[patch]` `endsWith('if (tray != null) ')` pinned source formatting rather than the guard; replaced with a whitespace-tolerant regex.
  - `[low]` `[patch]` The lifecycle's tray AD-15 error branch is unreachable in production — `TrayManagerTray` absorbs seam errors and never errors `panelRequests`. Kept, and now documented as an explicitly defensive backstop in both the code and the test, so it does not read as evidence of a live path.
  - `[low]` `[patch]` `tray_live_test.dart`'s skip reason asserted a `flutter build linux --debug` result inside a body that never runs. Clause removed; the build claim lives in these completion notes instead.
  - `[low]` `[patch]` `TrayManagerTrayIcon()` was evaluated as a constructor argument, registering its singleton listener before `openedTray` existed — the window the new comment claimed to have closed. The icon is now constructed and held first, and the abort path closes exactly one of the two.
  - `[low]` `[patch]` The install-failure line asserted "reachable by hotkey" one line before the bind that decides whether a hotkey exists, producing two contradictory log lines on a wlroots session with no tray host. Reworded to state only what it knows.
  - `[low]` `[patch]` The menu label asserted "on this compositor" for all three producers of the unavailable state, two of which are not compositor facts. Reworded to state the unavailability and the remedy without the causal claim.
  - `[low]` `[patch]` `tray_icon.dart` described the bundle-path join unconditionally, which is only the non-sandboxed branch. Doc corrected to name both; the sandbox behaviour itself is deferred (packaging format is undecided).
  - `[low]` `[patch]` DW-18's resolution claimed the four user-facing strings are "now true" unconditionally; qualified to "whenever `install()` succeeds", with the logged-failure fallback named.
  - `[low]` `[patch]` AD-14's "does not start a second icon" rested entirely on an untested source ordering. A row now pins that `TrayManagerTrayIcon()` follows the not-the-daemon branch.

### 2026-08-08 — Review pass 2

- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 1, medium 1, low 6)
- defer: 4: (high 0, medium 2, low 2)
- reject: 6: (high 0, medium 0, low 6)
- addressed_findings:
  - `[high]` `[patch]` The adapter still recorded *requested* state where its guards needed *rendered* state — the same root cause pass 1 patched, surviving on both of the paths pass 1 did not close. Two shapes, one fix. (a) An `install()` refused at `setMenu` left `_installed = false` even though the native `set_icon` had already created the indicator and set it ACTIVE with an empty `gtk_menu_new()`: a visible tray icon that does nothing, permanently, while `main.dart` logs "there is no tray menu" — every later push suppressed by the A7 guard, with nothing to retry it. (b) A `setHotkeyUnavailable` refused at `setMenu` rolled the request flag back while the icon on screen had already swapped, and the same-value short-circuit then refused the opposite-direction call that would have corrected it — a working hotkey advertised as broken with no route back through the port. `_rendered` (`bool?`) now carries what the tray is actually showing, `null` meaning unknown; `_installed` is set the moment `setIcon` returns, because that native call is what creates the indicator. Both directions are probe-confirmed and mutation-verified, and the pre-existing A1/A6/A7 gates were re-run against the changed code.
  - `[medium]` `[patch]` The reviewed tree had the whole `## Auto Run Result` section deleted, taking with it the icon-generation script the spec's own Execution task and Design Notes require be recorded ("so they are reproducible rather than mysterious binaries"), the `flutter build linux --debug` evidence that pass 1 deliberately relocated there, and the unobserved-claims statement one acceptance criterion is written against. Restored and carried forward, with this pass's results merged in.
  - `[low]` `[patch]` `tray_icon.dart` claimed the bundle-join was "the branch this project ships **and the one its tests observe**". It is not observed: `TrayManager.setIcon` switches on `defaultTargetPlatform`, which `flutter test` forces to `TargetPlatform.android`, so the Linux sandbox check never runs under test — and `endsWith` was satisfied identically by the joined path and the sandbox passthrough. Doc corrected to say what is actually pinned, and the assertion strengthened with `contains('data/flutter_assets')`, which the passthrough branch would fail.
  - `[low]` `[patch]` `TrayManagerTray`'s `_log` swallow was executed by every row and exercised by none — the suite runs on `FakeLogger`, which never throws, so rewriting `_log` as `=> emit();` left analyze clean and the whole suite green. The house `ThrowingLogger` row now covers all four sites; two of them are stream callbacks where a throw becomes an uncaught zone error, and one is on the shutdown path where it would break `dispose()`'s documented promise never to throw.
  - `[low]` `[patch]` `dispose()`'s first guarded step was unreachable on its failure path: `FakeTrayIcon` armed `setIcon`/`setMenu`/`dispose` but its `selections` was a bare broadcast stream, so a rejecting subscription cancel could not be expressed. The fake now wraps it in the house `CancelFailingStream`, and a row asserts the two steps behind the cancel still run — the same shape pass 1 patched one layer down with a `finally`.
  - `[low]` `[patch]` The abort path's orphan-seam arm (`else if (trayIcon != null)`) — added by pass 1 precisely to close the window between the two constructors — was pinned by nothing; deleting the whole clause left analyze clean and 525 tests green. A row now pins the step, the `else`, and its position.
  - `[low]` `[patch]` The install-guard row searched for `try {` and `on Object catch` as two independent substrings, which any unrelated guard in that window would have satisfied between them. Replaced with one whitespace-tolerant regex spanning the guard and the call it wraps.
  - `[low]` `[patch]` The lifecycle's tray AD-15 branch was labelled "explicitly defensive" by pass 1; the adapter's unknown-key warning one layer down — unreachable for the same kind of reason, since `TrayManager` drops clicks whose id is not in its current menu and the only other entry is natively insensitive — was not. Now labelled the same way, so it does not read as evidence of a live path.

### 2026-08-08 — Review pass 3

- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 0, medium 2, low 6)
- defer: 7: (high 1, medium 3, low 3)
- reject: 6: (high 0, medium 0, low 6)
- addressed_findings:
  - `[medium]` `[patch]` The install guard's comment and log asserted a reach the guard does not have. `set_icon` never checks `app_indicator_new`'s result and answers `true` regardless (`tray_manager_plugin.cc:118-129`, read directly this pass), so a host-less session — the one AD-12 exists for — resolves `install()` and never enters the catch, while the comment named exactly that session as what the guard covers. The same log line also claimed "there is no tray menu", which is false on the `setIcon`-landed/`setMenu`-refused path the pass-2 `_rendered` split exists to recover from, and self-falsifying one await later when `bindHotkey`'s `setHotkeyUnavailable` re-pushes the menu. Both now state only what they know, and the undetectability itself is filed.
  - `[medium]` `[patch]` The abort path's *producer* half was pinned by nothing. Pass 2 added a row for the `if (tray != null)` / `else if (trayIcon != null)` clauses, but not for the two assignments that make either reachable — and Dart does not flag a nullable local that is read and never assigned. Both mutations were confirmed green this pass: inlining `TrayManagerTrayIcon()` into the `TrayManagerTray(...)` arguments (reopening precisely the window pass 1 closed) and deleting `openedTray = tray;` (which drops the port's own disposal). One regex now spans both constructors and the assignment between them; the deletion mutation fails it.
  - `[low]` `[patch]` The "two states use different images" gate compared *encoded bytes*. Both PNGs come from one generator whose only difference is a flag feeding `zlib.compress`, so two visually identical glyphs that deflated differently would have passed the only gate standing behind the icon half of AD-12. It now inflates the IDAT chunks and compares pixels — mutation-verified by rebuilding the unavailable icon from the available one's scanlines at a different compression level, which the old gate accepted and the new one rejects.
  - `[low]` `[patch]` The pubspec asset gate was an unanchored substring over the whole file, so `# - assets/tray/` satisfied it — the commented-out case being exactly the failure its own reason string describes. Now scoped to the `flutter:` block's `assets:` list and parsed as list items; mutation-verified by commenting the line out.
  - `[low]` `[patch]` `_onSelection` logged "a selection no menu entry carries" for `_hotkeyUnavailableKey`, which *is* an entry this adapter builds — merely disabled. The branch is reached for two different drifts with two different causes; it now names each, with a row asserting the statement-entry path does not report the other.
  - `[low]` `[patch]` `TrayMenuEntry`'s spec-mandated value equality was exercised by nothing — the only hand-written value type under `lib/src/` with no equality row, in a repo whose `test/support/value_equality.dart` exists because this degradation once went unnoticed across five domain types. Neutering `==`/`hashCode` to identity left analyze clean and the suite green; a new `tray_menu_entry_test.dart` routes the positive row through `expectSameValue` and pins each field, `enabled` included.
  - `[low]` `[patch]` `expectNeverReached()` — the helper whose doc claims it guards the two Linux methods "one line away from anyone editing this seam" — was called by hand in four of seven rows, omitting the click and disposed-seam paths. Moved to `tearDown` so no future row can forget it; mutation-verified by leaking a `setTitle` into the disposed-seam guard, which only a previously-uncovered row drives.
  - `[low]` `[patch]` The abort path's `else if (trayIcon != null)` arm was unreachable with the concrete types `main.dart` names — the only code between the two assignments is a constructor whose body is one `listen()` on a broadcast controller — while two sibling branches this story added carry explicit "defensive, not a live path" labels. Labelled to the same standard, so the pinning row does not read as evidence of a live failure mode.

## Design Notes

**Why a `TrayIcon` seam, given AGENTS.md §4.2 warns against a one-implementation abstraction.** The same justification `PanelWindow` carries, and the dispatch states it outright: "the port-level logic (menu wiring, state mapping) is still testable against a fake and must be tested." `trayManager` is a singleton behind a private method channel, reachable only through a mocked channel and therefore only with a Flutter binding — and the logic worth testing here (which entries exist, what a click maps to, when a menu is *not* pushed) is pure decision-making that AGENTS.md §7 wants in the binding-free set. The seam also confines `tray_manager` to one file, which is what makes AD-1 mechanically checkable.

**Two surfaces for one state, deliberately.** AD-12 says "the tray icon and settings screen state that global hotkeys are unavailable". Read narrowly that is the icon *image*; read as the tray surface it is the menu, which is the only place a sentence fits. Rather than pick a reading, do both: swap the icon and add a disabled menu line. The menu line carries the words a user can act on; the icon carries the state at a glance and closes the narrow reading. Neither is expensive — `setIcon` is idempotent and re-creates nothing (`app_indicator_set_status(ACTIVE)` + `set_icon_full`).

**The open-panel entry stays enabled while the statement is shown.** This is the whole point of AD-12: the tray is the way in *because* the hotkey is not. A greyed-out menu on the one compositor family that needs it would invert the rule.

**Why no menu is pushed before `install()` (row A7).** Not defensive style — a crash. `set_context_menu` calls `app_indicator_set_menu(indicator, …)` and `set_title` calls `app_indicator_set_label(indicator, …)`, neither with a null check, and `indicator` is created only by `set_icon`. `DaemonStartup.bindHotkey` calls `setHotkeyUnavailable` on the port and does not know about installation, so the adapter is where that rule has to live.

**Why the tray request joins `DaemonLifecycle` rather than `PanelController`.** AD-8 requires the tray's action to reach `PanelVisibility.show()`, which `PanelController.showPanel()` already does — and `DaemonLifecycle` already owns exactly this shape for AD-14's socket requests, including the fire-don't-await rule, the AD-15 stream-error backstop, the post-shutdown guard, and cancellation as teardown step 1. Injecting `TrayPort` into `PanelController` instead would put an infrastructure concern in the application ring for no behaviour the lifecycle does not already have. Keep the two request streams as separate named parameters, not one merged list: their log lines name different mechanisms, and an operator reading "the tray menu stream errored" learns something "a panel request stream errored" would hide.

**Closing DW-18 and DW-11 against the dispatch's "closes no deferred-work item".** DW-18's own text says the promise "becomes true when story 6 lands the tray", and DW-11's remaining third is the file this story deletes. Leaving them open would make the ledger say the tray is never installed while it is. They are marked `status: done` with a `resolution:` line **in place** — the append-only format contract, story 5's ratified KEEP, and DW-13, which records the delete-instead-of-mark instruction as the recurring upstream defect. No other entry is read or modified, and the divergence is reported in the completion notes rather than done quietly.

**How the icons were generated**, so they are reproducible rather than opaque binaries: a short `python3` script using only `zlib` and `struct` (no Pillow in this container) writing 32×32 RGBA PNGs — a rounded glyph for the available state and the same glyph desaturated with a corner warning marker for the unavailable one. Record the exact script in the completion notes.

## Verification

**Commands:**
- `dart analyze` -- expected: no issues.
- `dart format --output=none --set-exit-if-changed lib test` -- expected: 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: all pass with **no new skips**; baseline is 452 passed / 2 skipped.
- `flutter test` -- expected: all pass; baseline is 481 passed / 4 skipped. The new `test/platform/tray_live_test.dart` must report as **skipped**, never as passed.
- `flutter build linux --debug` -- expected: builds. `ayatana-appindicator3-0.1` is present here, so a tray_manager link failure would be a real regression rather than an environment gap.

**Mutation gates** — each must be shown to fail, then reverted:
- Reorder `install()` to push the menu before the icon → row A1 fails.
- Delete the `_installed` guard in `setHotkeyUnavailable` → row A7 fails.
- Delete the same-value short-circuit → row A6 fails.
- Make the open-panel entry disabled when hotkeys are unavailable → the AD-12 row fails.
- Delete `closeTray` from `shutdown()`, and transpose it with the panel-visibility step → row C3 fails in both directions.
- Move `tray.install()` after `startup.bindHotkey(` in `main.dart` → the composition-wiring ordering row fails.

**Manual checks (if no CLI):**
- D1 is **not observable here**: no StatusNotifier host, no compositor, no reachable X display. It is owed on a real session and must be reported as owed, not as verified.

## Auto Run Result

Status: done
Blocking condition: none

### Summary of implemented change

`TrayManagerTray` behind the existing `TrayPort`, with `tray_manager` confined to a single infrastructure file behind a `TrayIcon` seam — the same shape story 5 established for `PanelWindow`, and for the same reason: the logic worth testing (which entries exist, what a pick maps to, when a menu is deliberately *not* pushed) stays in `dart test`'s binding-free set. AD-12's degradation is stated on **both** tray surfaces — the icon swaps to a degraded asset and a disabled line carries the sentence — while the open-panel entry stays enabled, because the tray is the way in precisely when the hotkey is not. The composition root installs the tray after `lifecycle.start()` and before `startup.bindHotkey`, guarded so a session with no tray host degrades rather than refusing to start, and joins `tray.panelRequests` to the same `DaemonLifecycle` handler AD-14's second-launch requests already reach — which is `PanelController.showPanel()`, and so `PanelVisibility.show()` (AD-8). The four shipped strings promising "the tray menu still opens the panel" are untouched; this story is what makes them true.

### Files changed

**New — `lib/`**
- `src/infrastructure/tray/tray_menu_entry.dart` — the `{key, label, enabled}` value type the seam takes, so no `menu_base` type crosses it.
- `src/infrastructure/tray/tray_icon.dart` — the infrastructure-private seam, carrying the icon-before-menu native rule and the AGENTS.md §4.2 justification.
- `src/infrastructure/tray/tray_manager_tray_icon.dart` — the seam over `tray_manager`; the only file under `lib/` naming it.
- `src/infrastructure/tray/tray_manager_tray.dart` — the port: menu wiring, state mapping, the broadcast `panelRequests`.

**New — assets**
- `assets/tray/hotkey-grammar-corrector.png`, `assets/tray/hotkey-grammar-corrector-hotkey-unavailable.png` — 32×32 RGBA; the second desaturated with a warning corner.

**Modified — `lib/`**
- `main.dart` — the real tray bound to `trayProvider`, a guarded `install()`, the request and teardown joins, and both the icon and the adapter held in the abort-visible scope.
- `src/infrastructure/system/daemon_lifecycle.dart` — a second panel-request stream and a `closeTray` step, both request subscriptions cancelled in teardown step 1, each carrying its own source label.

**Deleted** — `src/infrastructure/tray/unimplemented_tray.dart` and its test.

**New/modified — `test/`** — `fake_tray_icon.dart` (records an ordered sequence, not a set), `tray_manager_tray_test.dart`, `tray_menu_entry_test.dart` (pass 3: the value contract), `tray_manager_tray_icon_test.dart` (mocked channel, not skipped), `tray_live_test.dart` (unconditionally skipped, `fail()` body), `tray_confinement_test.dart`, plus new rows in `daemon_lifecycle_test.dart` and `composition_wiring_test.dart`.

**Other** — `pubspec.yaml` declares `assets/tray/`; `deferred-work.md` closes DW-11 and DW-18 in place and gains thirteen new entries across the three passes.

### Review findings breakdown

Three review passes, four layers each (adversarial, edge-case, verification-gap, intent-alignment), all run in parallel with no prior conversation context. **0 intent_gap, 0 bad_spec across all three.** Pass 1: 17 patched (high 1, medium 3, low 13), 6 deferred, 4 rejected. Pass 2: 8 patched (high 1, medium 1, low 6), 4 deferred, 6 rejected. Pass 3: 8 patched (high 0, medium 2, low 6), 7 deferred, 6 rejected. Full detail in the Review Triage Log above.

**What pass 3 found, and why it is a different kind of finding.** Passes 1 and 2 chased one defect — the adapter recording intent as if it were effect — through the code. Pass 3 found no successor to it: the `_rendered` split held under adversarial probing, and the state machine's own gates were re-run against it. What pass 3 found instead is a layer of **claims the tree makes that its own machinery does not support**. The install guard's comment named a session it cannot detect; two asset gates checked encodings and substrings rather than the properties they were written for; the abort path's producer assignments, the helper guarding two crash-prone platform methods, and a spec-mandated value contract were each pinned by nothing and mutation-confirmed green. None changes what the daemon does on a working desktop; together they are most of what a reader would have trusted without checking.

**The one finding that is not fixable here, stated plainly.** `install()` **cannot fail** for the reason its guard exists. The Linux `set_icon` handler never checks `app_indicator_new`'s result and answers `true` unconditionally, so a session with no StatusNotifier host resolves the install, sets `_installed`/`_rendered`, logs nothing, and leaves the user with no icon and — on wlroots — no hotkey either. AD-12's "degradation is visible, never silent" premise is silent on its own primary failure mode. Detecting it needs a DBus `org.kde.StatusNotifierWatcher` name check, which the intent's Never list excludes and which this container could not verify either way. This pass patched the code and log so they stop implying the guard covers it, and filed the capability gap as deferred work.

**The load-bearing defect, and why it took two passes.** The adapter recorded *intent* as if it were *effect*. Pass 1 found it on the `setHotkeyUnavailable` path — the flag committed before the push that renders it could fail, with the same-value short-circuit then blocking every retry — and fixed that one path. Pass 2 found the identical root cause alive on the two paths pass 1 had not closed, and the fix pass 1 chose for `install()` was itself an instance of it: leaving `_installed = false` when a push died at `setMenu` treated "the menu was refused" as "no indicator exists", when the native `set_icon` had already created one and set it ACTIVE. The result was a visible tray icon that did nothing, permanently, while the daemon logged that there was no tray menu. The general fix is a second field: `_rendered` (`bool?`) is what the tray is *showing*, `null` when that is unknown, and every short-circuit now consults it rather than the request. `_installed` means "the indicator exists" and is set the moment `setIcon` returns.

Both pass-2 shapes were reproduced by a reviewer probe before being touched, and both are mutation-verified. The three pre-existing gates over the changed code (A1 icon-before-menu, A6 same-state, A7 state-before-install) were re-run against the rewrite and still fail on their mutations.

**Rejected in pass 3, with the reasons.** That the AD-8 chain (tray pick → `PanelVisibility.show()`) is asserted at three surfaces and executed end to end at none, and that `main()` is imported by no test — both pre-existing and already filed as DW-8/DW-24, and both re-raised as new. That the AD-1 gate is a stripped-source substring scan rather than a type-flow check — rejected with the same reason as pass 1. That the B-row channel tests mock a handler answering `true` and so pin argument encoding rather than plugin behaviour — that is what a channel test is, and it is the reading the spec's own B rows mandate. That the two reworded `daemon_lifecycle` log strings are elaboration beyond the stated Approach — they are not among the four protected strings, and the `source` label they carry was itself a pass-1 patch. That "teardown step 1 became two steps" is a reinterpretation — it is behaviourally stronger, since `_step` swallows and neither cancel can skip the other, and it is pinned in order (the *hang* variant of that concern was deferred, not rejected).

**Rejected across the earlier passes, with the reasons.** Pass 1: the literal-blind `_stripComments` helper; composition-root claims resting on source scans (pre-existing, DW-8/DW-24); the AD-1 gate being a substring scan rather than a type-flow check; and `test/platform/` sitting outside `dart test` (DW-29). Pass 2: reformatting the six appended ledger entries into the `### DW-nn` house shape (the bare `source_spec`/`summary`/`evidence` form is what the dev-auto workflow mandates for a deferred finding, and this dispatch explicitly forbids rewriting existing entries — the orchestrator owns their lifecycle); `DaemonLifecycle.start()`'s missing idempotence guard and the tray never hearing about a rebind (both already filed by pass 1); an `_installed` guard against a double `install()` (no consumer, and not a matrix row); and "no test renders either icon" (that is exactly what row D1 and the skipped live test already own).

One reviewer proposal was **declined rather than applied** in pass 1: skipping an unchanged `setMenu` to limit `menu_base`'s id churn. The only push that reaches the window in question is a genuine state change, which must re-push — the guard would have been dead code. The underlying vendor race is filed as deferred work instead.

**Follow-up review recommendation: `true`.** Patched this pass: high 0, medium 2, low 6 — the score `3x2 + 6 = 12` clears the threshold of 5. (Pass 2 was also `true`, on a high-severity patch.) Note what the score does *not* reflect: pass 3 found no defect in the shipped behaviour at all, and its two mediums are a misleading comment and an untested source assertion. The recommendation is honest arithmetic on this pass's patch counts, not evidence that the daemon is wrong.

### Verification performed

| Command | Outcome |
|---|---|
| `dart analyze` | no issues |
| `dart format --output=none --set-exit-if-changed lib test` | 118 files, 0 changed |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **493 passed / 2 skipped** (spec baseline 452/2; 485/2 after pass 1, 489/2 after pass 2) — no new skips |
| `flutter test` | **529 passed / 5 skipped** (spec baseline 481/4; 521/5 after pass 1, 525/5 after pass 2); the one skip this story added is `tray_live_test.dart`, re-confirmed **skipped, never passed** |
| `flutter build linux --debug` | built (`✓ Built build/linux/x64/debug/bundle/hotkey_grammar_corrector`); re-run this pass after the `lib/` edits |

The four rows pass 3 added are the whole of its +4: the disabled statement entry being logged as what it is, and the three `TrayMenuEntry` value rows. Pass 2's four were an install refused at `setMenu` being repairable, a swap refused at `setMenu` being repairable in the *opposite* direction, a rejecting subscription cancel not skipping the teardown behind it, and a `ThrowingLogger` row over all four of the adapter's log sites.

**Matrix audit** — all 21 rows (A1-A10, B1-B4, C1-C4, D1) trace to a named test that ran and passed. D1 is the one row whose *specified* expected output is an unconditionally skipped test with an explicit reason; that is what exists, and the runtime claim beneath it is reported as owed, never as verified.

**Mutation verification** — every gate was shown to fail before its fix and pass after, and reverted byte-exact. Pass 3's four new gates, each run against the shipped tree and reverted with `git status` clean afterwards: deleting `openedTray = tray;` from `main.dart` **-1** (the composition-wiring row; before this pass both this and the inlined-constructor shape were green); neutering `TrayMenuEntry.operator ==` to `return false` **-1**; rebuilding the unavailable icon from the *available* icon's inflated scanlines at a different compression level — byte-different, pixel-identical, the exact case the old gate accepted — **-1**; commenting out `- assets/tray/` in `pubspec.yaml` **-1** (the old substring gate passed this unchanged); and leaking a `trayManager.setTitle("")` into the seam's disposed guard **-1**, on a row that carried no `expectNeverReached()` before this pass. Pass 2's eight, each run against the shipped tree: short-circuiting on the request instead of on what was rendered **-1**; setting `_installed` only after the whole push lands **-1**; dropping the in-flight `_rendered` reset **-1**; a bare `_selections.cancel()` in place of the guarded step **-2**; `_log` emitting without its swallow **-1**; deleting the abort path's `else if (trayIcon != null)` clause **-1**; moving `await tray.install()` outside its guard **-1**. Pass 1's gates over the same code were re-run after the rewrite: menu-before-icon **+12 -10**, deleting the `_installed` guard **-2**, deleting the same-state short-circuit **-1**. Pass 1's other three gates (`closeTray` deleted and transposed, `install()` moved after `bindHotkey`) are over code pass 2 did not touch and were verified in that pass.

One mutation **survived** in pass 1 and is recorded because the fix matters: the first `_installed` row retried `install()`, which has no `_installed` guard, so both versions behaved identically; the row was rebuilt to fail the install at `setIcon` and assert the following `setHotkeyUnavailable` makes zero seam calls, which kills it.

### Not observed, and stated as unobserved

This container has no StatusNotifier/AppIndicator host, no compositor, no xdg-desktop-portal, no keybinder-3.0 and no reachable X display. **That an indicator ever appears is not observed by this story**, and neither is: the icon being drawn from the bundled asset path, a menu pick raising the panel end to end, or the degraded icon and the disabled statement line being legible to a user. What is proven instead: the state mapping against a `TrayIcon` fake, the translation to `menu_base` and the click route against a mocked `tray_manager` channel, the bundled assets, and the appindicator link. `test/platform/tray_live_test.dart` carries the owed claims and has a `fail()` body so it cannot pass here.

### Divergence from the dispatch, reported rather than done quietly

The dispatch says "This story closes no deferred-work item." **DW-18 and DW-11 were closed anyway** — DW-18's own text names story 6 as its closer and is titled "the tray is never installed", and DW-11's remaining third is the file this story deletes. Leaving them open would make the ledger assert something the code has made false. Both are marked `status: done` with a `resolution:` line **in place**, never deleted, on the authority of the ledger's append-only format contract, story 5's ratified KEEP, and DW-13 — which records the delete-instead-of-mark instruction as the recurring upstream defect. No other existing entry was read or modified; the ledger diff outside the six appended entries is 4 insertions / 2 deletions. Pass 3 appended its seven entries the same way — 28 insertions, **0 deletions**, verified on the diff — touching no existing entry's text or status, per this dispatch's instruction that the orchestrator owns their lifecycle.

### Residual risks

1. **`install()` succeeding is not evidence that a tray exists.** Established this pass by reading the plugin: `set_icon` returns `true` without checking `app_indicator_new`, so on a session with no StatusNotifier host the daemon believes the tray is installed and says nothing. On wlroots — where AD-12's fallback is the whole point — the user then has neither a hotkey nor an icon, and the log reports no fault. Filed, unfixable within this story's authority, and the reason the guard's comment and log line were reworded rather than left implying otherwise. This is the largest gap between what the story claims and what a user would get.
2. **The deferred entries are the honest edges of this change** — six from pass 1, four from pass 2, seven from pass 3. Pass 3's high one is the item above. Its mediums: a stop signal during `await tray.install()` racing `dispose()`, where `_push()` rechecks `_disposed` after neither await and a late `setIcon` can re-activate an indicator teardown already made passive; `_finishStartup` continuing to `bindHotkey` after a shutdown completed underneath it; and both tray icons being full-colour 32×32 bitmaps where Linux tray hosts expect symbolic recolourable icons — which would flatten away the amber marker that *is* the icon half of AD-12. The earlier passes' four mediums: the sandboxed-install icon branch (a Flatpak or Snap build draws no icon at all and `setIcon` still answers true, so nothing logs); the tray never being told about a hotkey rebind after startup, the mirror image of DW-17; `_abort`/`_releaseWithoutLifecycle` still logging through the bare logger, where a broken stderr defeats the abort path's own purpose; and the two contradictory log lines a wlroots session with no tray host produces, where the remedy needs authority this story does not have over `daemon_startup.dart`.
3. **The strongest legibility assertion in the suite is still a substring.** The menu row checks that the label contains "unavailable"; the asset gate now checks the PNG signature, the IHDR marker, 32x32 from the big-endian dimensions, and — as of pass 3 — that the two files differ in their *inflated pixels* rather than merely their compressed bytes. That closes the case where two identical glyphs re-compressed differently would have passed, but it still cannot see whether either image is legible, or whether a label a real menu truncates survives. Partially mitigated by inspection rather than by a test: both PNGs were rendered and looked at during pass 1 — a blue card with two text lines, and the same card in grey with an amber warning triangle — and they are legible and unmistakably different at 32 px. That is one human look, not a gate, and it says nothing about how either renders scaled or recoloured into a real panel's tray (see the icon-convention entry filed in pass 3).
4. **`main()` remains reachable by no test**, so the install ordering, the abort-path tray close and the AD-14 construction order are source-text and source-index assertions (pre-existing, DW-8/DW-24). This story added six to that surface across the three passes; the three that had no pin at all — the install guard, the orphan-seam arm, and (pass 3) the two `openedTrayIcon`/`openedTray` assignments the abort path's whole reachability rests on — now have one each. The install-guard row was tightened from two independent substring searches to a single regex spanning the guard and the call it wraps, and the assignment row is one regex spanning both constructors.
5. **`install()` gets one attempt, and it is unbounded.** A tray host that appears after the daemon leaves the tray absent for the session; a host that answers never stalls startup before the bind. Both filed, neither fixed — a retry policy and a timeout value are design decisions the intent does not carry, and neither failure is reproducible in this container.
6. **The rewrite makes a partial push repairable, not impossible.** `_rendered` guarantees that the *next* port call re-pushes; it does not itself retry. Between the failed push and that next call the tray can be showing a state no field claims — bounded in practice because `bindHotkey` follows `install()` immediately, and because the only production caller is that one startup path until story 10 adds a second.
7. **The story shipped with `warnings: ['oversized']`** and nothing here can be reverted independently.
8. **Three review passes converged on behaviour, not on claims.** Pass 3 found no successor to the defect passes 1 and 2 chased, and the state machine's gates were re-run against it — but it did find six places where the tree asserted something no test or mechanism backed, five of them mutation-confirmed green before the fix. The rate at which that class of finding is being discovered has not yet fallen, so `followup_review_recommended` is `true` on arithmetic *and* on judgement.

### Reproducing the icons

The spec requires the generator be recorded rather than shipping the binaries unexplained. `python3`, `zlib` and `struct` only — there is no Pillow in this container. Run from the repo root; the glyph is rendered at 8× and box-downsampled, which is where the anti-aliasing comes from.

**Verified reproducible**, not merely recorded: the script below was extracted from this file, run into a scratch directory, and both outputs matched the committed assets by `sha256sum` (`38c627fa…` and `ef8b778e…`). So a future reader can regenerate the binaries and confirm the ones in the tree are what this script produces.

```python
#!/usr/bin/env python3
import struct
import zlib

SIZE = 32
SS = 8

BLUE = (0x2F, 0x6F, 0xED)
BLUE_INK = (0xFF, 0xFF, 0xFF)
GREY = (0x6B, 0x72, 0x80)
GREY_INK = (0xD1, 0xD5, 0xDB)
AMBER = (0xF5, 0x9E, 0x0B)
AMBER_INK = (0x1F, 0x14, 0x00)


def in_rounded_rect(x, y, x0, y0, x1, y1, r):
    dx = max(x0 + r - x, 0.0, x - (x1 - r))
    dy = max(y0 + r - y, 0.0, y - (y1 - r))
    return dx * dx + dy * dy <= r * r


def in_triangle(x, y, a, b, c):
    def side(p, q):
        return (q[0] - p[0]) * (y - p[1]) - (q[1] - p[1]) * (x - p[0])
    s1, s2, s3 = side(a, b), side(b, c), side(c, a)
    return not ((s1 < 0 or s2 < 0 or s3 < 0) and (s1 > 0 or s2 > 0 or s3 > 0))


def glyph(x, y, body, ink):
    """The shared mark: a rounded card with two lines of text on it."""
    if in_rounded_rect(x, y, 7, 10, 25, 13, 1.5) or in_rounded_rect(x, y, 7, 16, 21, 19, 1.5):
        return ink + (255,)
    if in_rounded_rect(x, y, 3, 4, 29, 26, 5):
        return body + (255,)
    return None


def warning(x, y):
    """The degraded marker: an amber triangle with a bang, cut out of the card."""
    outer = ((24.5, 15.0), (17.0, 30.5), (32.0, 30.5))
    inner = ((24.5, 17.0), (19.0, 29.5), (30.0, 29.5))
    if in_rounded_rect(x, y, 23.6, 21.0, 25.4, 26.0, 0.9) or in_rounded_rect(x, y, 23.6, 27.2, 25.4, 29.0, 0.9):
        return AMBER_INK + (255,)
    if in_triangle(x, y, *inner):
        return AMBER + (255,)
    if in_triangle(x, y, *outer):
        return (0, 0, 0, 0)  # the gap that separates the marker from the card
    return None


def render(degraded):
    body, ink = (GREY, GREY_INK) if degraded else (BLUE, BLUE_INK)
    rows = []
    for py in range(SIZE):
        row = []
        for px in range(SIZE):
            r = g = b = a = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    x = px + (sx + 0.5) / SS
                    y = py + (sy + 0.5) / SS
                    pixel = glyph(x, y, body, ink)
                    if degraded:
                        marker = warning(x, y)
                        if marker is not None:
                            pixel = marker
                    if pixel is None:
                        continue
                    r += pixel[0] * pixel[3] / 255
                    g += pixel[1] * pixel[3] / 255
                    b += pixel[2] * pixel[3] / 255
                    a += pixel[3]
            samples = SS * SS
            alpha = a / samples
            if alpha == 0:
                row.append((0, 0, 0, 0))
                continue
            # Un-premultiply: the accumulators hold sum(colour * alpha / 255).
            scale = 255 / a
            row.append((min(255, round(r * scale)), min(255, round(g * scale)),
                        min(255, round(b * scale)), round(alpha)))
        rows.append(row)
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(v for pixel in row for v in pixel) for row in rows)

    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n"
                  + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
                  + chunk(b"IDAT", zlib.compress(raw, 9))
                  + chunk(b"IEND", b""))


write_png("assets/tray/hotkey-grammar-corrector.png", render(degraded=False))
write_png("assets/tray/hotkey-grammar-corrector-hotkey-unavailable.png", render(degraded=True))
```
