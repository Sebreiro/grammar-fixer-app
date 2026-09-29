---
title: 'X11 global hotkey adapter'
type: 'feature'
created: '2026-08-08'
status: 'done'
baseline_revision: '2baaef63aa4924def99fcbf017d47c82d3221813'
final_revision: 'c280eeb'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/deferred-work.md'
  - '{project-root}/lib/src/domain/hotkey/global_hotkey.dart'
  - '{project-root}/lib/src/domain/hotkey/hotkey_bind_outcome.dart'
  - '{project-root}/lib/src/domain/hotkey/hotkey_binding.dart'
  - '{project-root}/lib/src/infrastructure/hotkey/x11_global_hotkey.dart'
  - '{project-root}/lib/src/infrastructure/panel/panel_window.dart'
  - '{project-root}/lib/src/infrastructure/system/daemon_startup.dart'
  - '{project-root}/lib/main.dart'
warnings: ['oversized']
---

<intent-contract>

## Intent

**Problem:** `X11GlobalHotkey` is an honest stub: every `bind()` resolves to `HotkeyUnavailable` and `activations` never emits. Everything above it is built and proven against fakes — `PanelController`'s AD-8 toggle, `DaemonStartup.bindHotkey`, the tray's AD-12 statement, `SettingsController.changeHotkey` — and on an X11 session the whole of CAP-1's summon and CAP-12's X11 half currently reach nothing. Story 4 wired the *selection* of one adapter; this is the first story that puts a real key grab behind it.

**Approach:** Implement `X11GlobalHotkey` over `hotkey_manager` / `keybinder-3.0`, confined behind an infrastructure-private `HotkeyRegistrar` seam — the same shape stories 5 and 6 established for `PanelWindow` and `TrayIcon`, and for the same reason: `hotKeyManager` is a singleton behind method and event channels, so the outcome logic (what `bind()` reports, what a rebind releases first, what a press becomes) only stays in the binding-free `dart test` set if a fake can stand in for it. A pure-Dart `HotkeyKeyCatalogue` turns the domain's key label into the backend's request, and every path the backend can refuse resolves to `HotkeyUnavailable` rather than throwing. Two AD-conformance gaps in `hotkey_manager` are structural rather than fixable here; they are implemented around, stated, and filed with a concrete proposed replacement.

## Boundaries & Constraints

**Always:**
- AD-9: `package:hotkey_manager` is named by **exactly one** file under `lib/`. No `HotKey`, `HotKeyModifier`, `KeyboardKey`, GDK keyval or accelerator string appears above `lib/src/infrastructure/hotkey/`. The composition root still constructs exactly one adapter and never switches at runtime.
- AD-1, and the sharp form of it here: **`x11_global_hotkey.dart` must not acquire a Flutter import, directly or transitively.** `test/infrastructure/system/daemon_startup_test.dart` imports it and runs under `dart test`, which cannot resolve `dart:ui`. The vendor package is reachable only from the seam's implementation file.
- AD-10: `bind()` returns `HotkeyBound(HotkeyRegistration(effective: …, authority: BindingAuthority.application))` **only after the grab request completed without refusal**, and `effective` is what is actually in effect — the requested binding on success, and the still-live previous binding when a rebind was abandoned. Every other path returns `HotkeyUnavailable`.
- AD-12: `bind()` never throws and never rejects. A refused channel, a missing plugin, an unrepresentable key and a disposed adapter are all values.
- AD-8 / CAP-1: an activation reaches `activations` with nothing allocated, loaded or awaited on the path. `PanelController` is untouched.
- AD-4: `dispose()` releases the grab and closes the stream, is idempotent, and never throws.
- Consistency Conventions: adapters named for their technology, one public type per file, the house `_log` swallow on every recovery-path log call, and a caught error reduced to `error_type` — never its `toString()`.
- AGENTS.md §8: nothing is faked. A claim this container cannot observe is stated as unobserved and its test is unconditionally skipped with a `fail()` body.
- Every test outside `test/platform/` runs with no Flutter binding and cites its CAP or AD id.

**Block If:**
- Keeping `x11_global_hotkey.dart` Flutter-free turns out to require moving AD-9's display-server → adapter selection out of `DaemonStartup` and into `main.dart`'s body, where no test can reach it. Injecting the registrar into `DaemonStartup.begin` is the intended shape; if that fails, the fallback trades a mechanically-pinned AD-9 for a source scan and is not an unattended choice.
- The `hotkey_manager` channels turn out not to be reachable under `flutter test` — in particular if `HotKeyManager`'s singleton `EventChannel` subscription cannot be mocked — so the only evidence for the press route would be an unobservable claim.
- Honouring AD-10 or AD-12 turns out to require editing `HotkeyRegistration`, `BindingAuthority`, `HotkeyBinding` or `HotkeyBindOutcome`. Those are spine-verbatim (AD-9) or settled by story 3.

**Never:**
- No Wayland portal work (story 8), no settings screen (story 10), no panel widgets (story 9). `WaylandPortalGlobalHotkey` stays exactly as it is.
- No new dependency, no pubspec pin change, and **no forking or vendoring of `hotkey_manager`**.
- **No `dart:ffi` implementation in this story.** The two structural gaps below are reported and proposed, not built — see Design Notes for why an unattended run must not ship that surface.
- No fallback, cascade or retry between backends, and no automatic re-grab on a lost grab.
- Do not fix the other filed ledger entries riding on these files: DW-17 (the startup bind outcome never reaches the settings surface), the tray never being told about a rebind, `SettingsController`'s bind-before-write divergence and its mutation-generation race. They stay filed — note in the completion notes that this story is what makes the last two *live* rather than latent.
- No test that could pass in this container for anything needing a real X server, a real grab, or a real key press.

## I/O & Edge-Case Matrix

**A — the adapter, binding-free over a `HotkeyRegistrar` fake.**

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| A1 first bind (CAP-1, AD-10) | fresh adapter; `bind(Ctrl+Shift+G)` | the seam receives `release` — a no-op with nothing held — then exactly one `grab` carrying G's usage and `{control, shift}`; outcome is `HotkeyBound` with `effective == Ctrl+Shift+G` and `authority == application` | a rejecting seam is A5 |
| A2 rebind without restart (CAP-12) | after A1; `bind(Alt+Space)` | the seam sees **release then grab**, in that order; outcome carries `Alt+Space`, not the old combination | as A5 |
| A3 same binding twice | after A1; `bind(Ctrl+Shift+G)` again | still release-then-grab — no short-circuit | No error expected |
| A4 unrepresentable key (AD-12) | `bind(HotkeyBinding(modifiers: {control}, key: 'Compose'))` | **no seam call at all**; `HotkeyUnavailable` whose message names the key and the tray | not an error: the request was answerable without the backend |
| A5 the grab is refused (AD-12) | seam's grab throws | `HotkeyUnavailable`, never `HotkeyBound`; one error logged carrying `error_type` only | the exception never escapes `bind()` |
| A6 the release is refused mid-rebind (AD-10) | after A1; seam's release throws on `bind(Alt+Space)` | **no grab is issued**; outcome is `HotkeyBound` whose `effective` is the still-live `Ctrl+Shift+G` — what is actually in effect | one error logged; never throws |
| A7 a press (CAP-1) | grab in effect; the seam emits a press | `activations` emits exactly once; two independent listeners both receive it | No error expected |
| A8 a press after dispose | disposed adapter; the seam emits | nothing emitted; `activations` is closed | No error expected |
| A9 dispose (AD-4) | adapter with a grab in effect | the grab is released, the seam is disposed, `activations` closes; a second `dispose()` is a no-op | a rejecting release or seam dispose is logged and the remaining steps still run; never throws |
| A10 bind after dispose | disposed adapter; `bind(...)` | `HotkeyUnavailable`; **zero** seam calls | No error expected |
| A11 the seam's press stream errors | an error on the seam's stream | logged at error level, type only; the subscription survives and a later A7 still emits | AD-15 backstop, and **explicitly defensive** — the shipped seam cannot error its own controller |
| A12 no modifiers | `bind(HotkeyBinding(modifiers: {}, key: 'F12'))` | grabbed and reported like A1 — an empty modifier set is legal config (story 1) | No error expected |
| A13 the logger is the thing that broke | every path above, under `ThrowingLogger` | no unhandled zone error; `dispose()` still completes | the logger's own failure is the one sanctioned silent swallow |

**B — `HotkeyKeyCatalogue`, binding-free, and the serialization the dispatch requires be unit-tested with no skip.**

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| B1 letters, case-insensitively | `'G'`, `'g'` | both resolve to the same USB HID usage — config is hand-edited and GTK lowercases the accelerator anyway | No error expected |
| B2 the letter run's ends | `'A'`, `'Z'` | `0x00070004` and `0x0007001d` | No error expected |
| B3 the digit run, including its wrap | `'1'`, `'9'`, `'0'` | `0x0007001e`, `0x00070026`, `0x00070027` — `0` sits at the **end** of the HID run, not the start | No error expected |
| B4 the function run's ends | `'F1'`, `'F12'` | `0x0007003a` and `0x00070045` | No error expected |
| B5 named keys | `Space`, `Tab`, `Enter`, `Escape`, `Backspace`, `Insert`, `Delete`, `Home`, `End`, `PageUp`, `PageDown`, `ArrowUp/Down/Left/Right` | each resolves to its own usage | No error expected |
| B6 anything else | `''`, `'  '`, `'Compose'`, `'F25'`, `'AA'`, `'ctrl'` | null, which is what A4 turns into `HotkeyUnavailable` | No error expected |
| B7 no two labels collide | the whole catalogue | every usage is distinct | No error expected |
| B8 the modifier mapping is total | `HotkeyModifier.values` | all four map, and the mapping is an exhaustive `switch` so a fifth value would not compile | No error expected |

**C — the seam over `hotkey_manager`, binding-required, mocked channels, NOT skipped.**

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| C1 the grab reaches the plugin | `HotkeyGrab` for Ctrl+Shift+G | one `register` invocation whose `keyCode` is the **GDK keyval** `0x67` and whose `modifiers` are `['control', 'shift']` | No error expected |
| C2 every catalogue entry survives the round trip | each `HotkeyKeyCatalogue` label in turn | `keyCode` is non-null for all of them — the drift check between this catalogue and Flutter's own key tables, and the reason a wrong usage cannot ship quietly | No error expected |
| C2b an unmapped usage is refused, not sent | a hand-built `HotkeyGrab` whose `usbHidUsage` has no `PhysicalKeyboardKey` or no GDK keyval | the seam throws and **no** `register` invocation reaches the channel | a null `keyCode` would reach `fl_value_get_int` natively (fact 3), so refusing in Dart is the only safe answer |
| C3 a press comes back | an inbound `onKeyDown` event carrying the registered identifier | `presses` emits once | an event for an unknown identifier emits nothing |
| C4 a rebind releases first | grab, then a second grab | `unregister` for the first identifier is invoked **before** the second `register` | No error expected |
| C5 a refused channel propagates | `register` rejects | the rejection comes out of the seam, so the adapter can turn it into A5 | the seam does not swallow it |
| C6 seam dispose | `dispose()` | the live grab is unregistered, `presses` closes, and later calls invoke nothing | No error expected |

**D — a real desktop.** An actual X11 grab, CAP-1's sub-100 ms summon, and CAP-12's rebind taking effect without a restart. **Not observable here** — no compositor, no X server this process can reach, no session. One unconditionally skipped test with a `fail()` body and a reason naming exactly what is owed.

</intent-contract>

## Code Map

- `lib/src/domain/hotkey/global_hotkey.dart`, `hotkey_binding.dart`, `hotkey_bind_outcome.dart` -- the port and its three value types. **Read-only.** `HotkeyRegistration`/`BindingAuthority` are byte-identical to AD-9 and must stay so.
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` -- the stub this story replaces. It must stay Flutter-free (see Boundaries).
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` -- unchanged. Story 8's.
- `lib/src/infrastructure/panel/panel_window.dart`, `lib/src/infrastructure/tray/tray_icon.dart` -- the seam idiom to mirror: an infrastructure-private interface, one file naming the vendor package, a broadcast stream, a `_disposed` guard on every method, and the AGENTS.md §4.2 justification written on the interface.
- **`hotkey_manager 0.2.3`, the six facts that decide this design** (read in `~/.pub-cache/hosted/pub.dev/`, and each one verified rather than assumed):
  1. `hotkey_manager_linux-0.2.0/linux/hotkey_manager_linux_plugin.cc:95-99` — `keybinder_bind`'s `gboolean` is **discarded** and the handler answers `fl_value_new_bool(true)` unconditionally. **A failed grab reports success**, and no Dart code can tell. This is AD-10's one unsatisfiable clause.
  2. The same file, `:89-90` — the keybinder keystring is built **natively**, by `gtk_accelerator_name(keyval, mods)`. The adapter never produces it. Probed directly against GTK 3 here: Ctrl+Shift+G yields **`<Shift><Control>g`**, not AD-9's illustrative `<Ctrl><Shift>g` — different spelling *and* different order, and an uppercase `GDK_KEY_G` normalises to the same string.
  3. `hotkey_manager_platform_interface-0.2.0/lib/src/hotkey_manager_method_channel.dart:34-39` — `register` sends `'keyCode': hotKey.physicalKey.keyCode`, and `uni_platform-0.1.3`'s Linux branch resolves that through Flutter's `kGtkToLogicalKey` to a **GDK keyval**. It is `int?`: an unmapped key sends null into `fl_value_get_int`, and `HotKey.physicalKey` itself throws on a logical key with no physical twin. Both must be refused in Dart first.
  4. `hotkey_manager-0.2.3/lib/src/hotkey_manager.dart:7-13, 92-115` — `HotKeyManager` is a process-wide lazy singleton whose constructor subscribes to the `EventChannel` and adds a `HardwareKeyboard` handler, so touching it needs a binding; `register` awaits the platform call *before* mutating `_hotKeyList`, so a refusal leaves its bookkeeping clean.
  5. `uni_platform-0.1.3/lib/src/uni_platform.dart:9-14` — platform selection reads `dart:io`'s `Platform.operatingSystem`, **not** `defaultTargetPlatform`. So under `flutter test` on Linux the Linux branch runs and C1's keyval assertion is real, unlike the tray seam's `defaultTargetPlatform` trap story 6 hit.
  6. `hotkey_manager_linux-0.2.0/linux/CMakeLists.txt:45-54` — a missing `keybinder-3.0` is a **build** `FATAL_ERROR`, and `ldd` on the built bundle shows `libkeybinder-3.0.so.0` as a direct dependency of the daemon binary. keybinder-3.0 **is present in this container** (0.3.2, headers and shared library), correcting the dispatch's premise; `flutter build linux --debug` succeeds today.
- `lib/src/infrastructure/system/daemon_startup.dart` -- `_hotkeyFor(DisplayServer)` at line 237 constructs the adapter. It is pure `dart:io` on purpose and its test runs under `dart test`, so it must receive the registrar rather than build one.
- `lib/main.dart` -- `DaemonStartup.begin` at line 41; `openedTrayIcon`/`openedTray` at lines 70-77 are the precedent for holding a vendor seam in the `_abort`-visible scope.
- `lib/src/infrastructure/system/daemon_lifecycle.dart:206` -- already disposes the hotkey adapter as a teardown step. Unchanged.
- `test/infrastructure/hotkey/stub_hotkey_adapters_test.dart` -- drives both stubs through one shared suite. The X11 half stops being true here.
- `test/infrastructure/system/daemon_startup_test.dart`, `test/architecture/composition_wiring_test.dart` -- the two suites that pin AD-9's single-adapter selection and main.dart's overrides.
- `test/platform/tray_manager_tray_icon_test.dart` -- the mocked-channel idiom to copy, including the `expectNeverReached()`-in-`tearDown` discipline.
- `test/architecture/tray_confinement_test.dart` -- the AD-1 confinement-scan idiom to copy.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- append-only. This story closes nothing and files the findings below.

## Tasks & Acceptance

**Execution:**

*The pure-Dart serialization (matrix B)*
- `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart` -- create `HotkeyKeyCatalogue` with `static int? usbHidUsageFor(String label)` and `static Iterable<String> get labels` -- letters, digits and F-keys are **contiguous USB HID runs** and must be derived from their documented start usages with the range cited in a comment, not written out as 48 magic numbers; the named keys are an explicit map. Lookup trims and upper-cases the label. This is the AD-9 serialization, and it is the whole reason `bind()` can refuse a key without ever calling the backend.
- `lib/src/infrastructure/hotkey/hotkey_grab.dart` -- create `final class HotkeyGrab {Set<HotkeyModifier> modifiers; int usbHidUsage}` with value equality -- the plain value that crosses the seam, carrying only domain types, so no `HotKey` or keyval reaches the adapter (the `TrayMenuEntry` precedent, including story 6 pass 3's lesson that a hand-written value type gets an equality test).

*The seam (matrix C)*
- `lib/src/infrastructure/hotkey/hotkey_registrar.dart` -- create the infrastructure-private `HotkeyRegistrar`: `Future<void> grab(HotkeyGrab)`, `Future<void> release()`, `Stream<void> get presses` (broadcast), `Future<void> dispose()` -- document the AGENTS.md §4.2 justification the way `panel_window.dart` does, and state the two vendor facts callers must not re-derive: the keystring is built natively, and a refused grab is indistinguishable from a successful one. Name elides the doubled word (`HotkeyManagerRegistrar`, not `HotkeyManagerHotkeyRegistrar`); say so on the type so it does not read as a convention slip.
- `lib/src/infrastructure/hotkey/hotkey_manager_registrar.dart` -- create `HotkeyManagerRegistrar implements HotkeyRegistrar`, the **only** file under `lib/` naming `package:hotkey_manager` -- resolve `PhysicalKeyboardKey.findKeyByCode(grab.usbHidUsage)` and its `keyCode`, refusing (a thrown `StateError` the adapter catches) rather than sending a null keyval; map `HotkeyModifier` to `HotKeyModifier` in an exhaustive `switch`; register with a stable identifier and a `keyDownHandler` that pushes onto the broadcast `presses`; `release()` unregisters the held `HotKey` and forgets it; `dispose()` releases, closes `presses`, and guards every method with `_disposed`. Touch `hotKeyManager` only from `grab()`/`release()`, never from the constructor, so building this on a Wayland session costs nothing.

*The adapter (matrix A)*
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` -- rewrite over a `HotkeyRegistrar` and a `Logger`: catalogue lookup first (A4), then release-then-grab (A1-A3), with a refused release abandoning the rebind and reporting the still-live binding as `effective` (A6); `_disposed` guards on `bind()` and the press path; the press subscription forwarding onto the existing broadcast controller; `dispose()` releasing the grab and disposing the seam through guarded steps. Keep the class doc's shape and replace its "no backend behind it yet" paragraph. **No Flutter import.**

*Composition*
- `lib/src/infrastructure/system/daemon_startup.dart` -- add a required `HotkeyRegistrar registrar` parameter to `begin()` and pass it into `_hotkeyFor` -- AD-9's selection stays here, where a test can drive both environment branches, while the vendor object is built where vendor objects are built. `WaylandPortalGlobalHotkey` ignores it.
- `lib/main.dart` -- construct `HotkeyManagerRegistrar()`, hold it in the `_abort`-visible scope beside `openedTrayIcon`, and pass it to `DaemonStartup.begin` -- an aborted startup must dispose a seam that may already hold a grab. Note in the comment that this construction is inert (fact 4 above), unlike the tray seam's.

*Tests*
- `test/fakes/fake_hotkey_registrar.dart` -- create; records an **ordered sequence** of calls with their arguments (A2 and A6 rest on order, not on a set), with per-method error injection and an `emitPress`/`emitPressError` seam, and its `presses` wrapped in the house `CancelFailingStream` so A9's first guarded step is reachable on its failure path.
- `test/infrastructure/hotkey/hotkey_key_catalogue_test.dart` -- create; every B row, binding-free, **not skipped** — this is the serialization test the dispatch requires. Include B7's collision check over the whole catalogue and B8's totality over `HotkeyModifier.values`.
- `test/infrastructure/hotkey/x11_global_hotkey_test.dart` -- create; every A row, binding-free, with the CAP/AD id in each name.
- `test/infrastructure/hotkey/stub_hotkey_adapters_test.dart` -- narrow to `WaylandPortalGlobalHotkey` alone and say in the doc that the X11 half was replaced by a real backend rather than deleted -- the file's own doc promises exactly this ("the day either grows a real backend, its half of this suite is what says the degradation was replaced rather than merely renamed").
- `test/platform/hotkey_manager_registrar_test.dart` -- create; every C row over mocked `dev.leanflutter.plugins/hotkey_manager` and `…_event` channels, **not skipped**. Install the mock stream handler in `setUpAll` **before** anything touches `hotKeyManager` and keep one handler for the whole file: the singleton subscribes to the event channel exactly once per process (fact 4), so a per-test handler would bind only on the first row. `unregisterAll()` in `tearDown`, or the singleton's list leaks across rows.
- `test/platform/x11_hotkey_live_test.dart` -- create; one unconditionally skipped test with a `fail()` body whose reason names what is owed (matrix D) and what is missing here (no reachable X display, no session, no way to press a key) -- never written so it could pass in this container.
- `test/architecture/hotkey_confinement_test.dart` -- create; AD-1: exactly one file under `lib/` names `package:hotkey_manager`, no file under `lib/` names `package:uni_platform` or `package:hotkey_manager_platform_interface`, and no file under `lib/src/infrastructure/hotkey/` names `package:flutter/` except that one seam file -- the last row is what mechanically protects the binding-free `dart test` gate from a transitive Flutter import.
- `test/infrastructure/system/daemon_startup_test.dart` -- pass a `FakeHotkeyRegistrar` and keep both AD-9 environment rows asserting the adapter *type*; add a row that the registrar reaches the X11 adapter and that the Wayland branch builds without it.
- `test/architecture/composition_wiring_test.dart` -- add rows for the `HotkeyManagerRegistrar(` construction, its assignment into the abort-visible local, and its position relative to the not-the-daemon branch -- the same shape as the tray rows added by story 6 pass 3, which exist because the abort path's *producer* assignments were pinned by nothing.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- append the findings below, touching no existing entry: (1) `keybinder_bind`'s discarded result makes AD-10's "a failed grab must not report success" unsatisfiable through this package, with the proposed `dart:ffi` replacement and its own risk; (2) `libkeybinder-3.0.so.0` is a hard `DT_NEEDED` of the daemon binary, so a machine without it cannot start the daemon at all — which contradicts the spine's Operational envelope claim that each missing runtime dependency "never blocks startup"; (3) AD-9's `<Ctrl><Shift>g` is not the syntax the backend uses (`<Shift><Control>g`, built in C), a spine currency item alongside DW-2 and DW-7; (4) `handle_key_down` and `hkm_unregister` read an uninitialised `const char*` when their map lookup misses — undefined behaviour in a resident daemon.

**Acceptance Criteria:**
- Given an X11 environment and a registrar that accepts the grab, when `DaemonStartup.bindHotkey` runs, then the outcome is `HotkeyBound` with `authority == application` and `effective` equal to the configured combination, and the tray is told hotkeys are **available** — the first time either has been true (CAP-1, AD-10, AD-12). Observable binding-free through the existing `daemon_startup_test.dart` harness; the *live* form of this claim is matrix D and stays owed.
- Given a grab in effect, when `bind()` is called with a different combination, then the previous grab is released before the new one is requested and no restart is involved (CAP-12).
- Given the AD-1 gate, when the suite runs, then `package:hotkey_manager` is named by exactly one file under `lib/`, and `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` still resolves — proving `x11_global_hotkey.dart` took no transitive Flutter import.
- Given every way the backend can refuse, when each is driven, then `bind()` returns `HotkeyUnavailable` and never `HotkeyBound`, nothing throws out of the adapter, and `runZonedGuarded` captures no unhandled error.
- Given the completion notes, when the story is reported, then they state plainly that a `keybinder_bind` failure is reported to this adapter as success, that a missing `keybinder-3.0` prevents the daemon from starting rather than degrading it, that both are properties of the pinned package rather than of this code, and what the proposed replacement is — and they mark every runtime claim this container cannot observe as owed, naming the skipped test.

## Spec Change Log

## Review Triage Log

### 2026-08-08 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 15: (high 1, medium 6, low 8)
- defer: 4: (high 0, medium 1, low 3)
- reject: 6: (high 0, medium 0, low 6)
- addressed_findings:
  - `[high]` `[patch]` **Two overlapping `bind()` calls double-registered under the one fixed identifier and permanently leaked a key grab.** Neither the adapter nor the seam serialized, so the calls interleaved as release, release, grab, grab. A reviewer probe confirmed the consequence end to end: native `std::map::insert` does not overwrite, so keybinder held two bindings while `dispose()` issued exactly one `unregister` — the second combination stayed grabbed X-session-wide with a dead handler, and until then one press toggled the panel twice. That is precisely the double-binding failure the A6 design note exists to prevent, left open on the one path that reaches it, and reachable from `SettingsController.changeHotkey`, which has no in-flight guard of its own. `bind()` now chains onto the previous bind through a `_queue`, the idiom story 5 established for `WindowManagerPanelVisibility`. Mutation-verified.
  - `[medium]` `[patch]` A disposed `HotkeyManagerRegistrar` resolved `grab()` silently, so the adapter turned it into `HotkeyBound(effective: requested)` for a seam that was shut — the same defect shape this story files as DW-39, reproduced in the project's own code and pinned by a platform row as if intended. Both seam methods now throw `StateError`; the row asserts a rejection.
  - `[medium]` `[patch]` `dispose()` racing an in-flight `bind()` let a grab land after teardown with nothing to release it: `_disposed` was checked only at the top of `bind()`, and a SIGTERM during a settings rebind is enough. Fixed at both layers — the adapter re-checks after the grab await and releases what arrived, and the seam re-checks after `register` and undoes it, which is needed because otherwise the adapter's release is itself refused by the now-disposed seam and the grab leaks for real.
  - `[medium]` `[patch]` **The seven labels this story proved bind a key nobody can press were still reported as successfully bound.** `Space`, `Tab`, `Enter` and `F1`–`F4` reach keybinder as keypad/ISO/3270 variants (DW-43), and `bind()` answered `HotkeyBound` for them, so the tray would state hotkeys are available for a shortcut that can never fire. The spec's own Always list settles it: AD-10 says a failed grab must not report success and AD-12 says degrade visibly — a grab known to be dead is a failed grab. The catalogue still resolves them (matrix B4/B5) and now exposes them as `labelsThatBindTheWrongKey`; `bind()` refuses them before touching the backend, naming the key and the tray.
  - `[medium]` `[patch]` A refused `unregister` was armed nowhere, so three claims the seam's own doc makes — the rejection propagates, `_held` survives it, `dispose`'s `finally` still closes `presses` — were pinned by nothing, and both mutations passed every suite. A swallowing seam would have retired the whole A6 design silently.
  - `[medium]` `[patch]` Nothing pinned that a refused `register` leaves the seam holding nothing. Hoisting `_held = hotKey` above the await failed zero tests, and the consequence is not abstract: `HotKeyManager.unregister` has no membership check, so the next release would send an `unregister` the native map never received — landing on the uninitialised `const char*` this story files as DW-42, by way of the live A5-then-shutdown path.
  - `[medium]` `[patch]` The catalogue-versus-Flutter drift check covered 11 of 63 labels — the row written as the drift check asserted only that `keyCode` was non-null. Table position is decided per key (F1–F4 wrong, F5–F12 right), so a key-table reorder could silently rebind any of the other 52 with DW-39 guaranteeing it still reported success. The round-trip loop now asserts all 63 values and subsumes the seven-label row.
  - `[low]` `[patch]` Matrix row A8 was a false green: deleting the whole `_onPress` guard failed zero tests, because the fake's `emitPress()` no-ops on its own closed controller rather than the adapter filtering anything. The fake now delivers a press mid-teardown, between the subscription cancel and the seam close, so the adapter's guard is what must stop it.
  - `[low]` `[patch]` `meta` never reached the vendor enum in any test, while `HotKeyModifier.values.byName(...)` throws `ArgumentError` on an unknown name — a vendor rename would have surfaced to the user as "this session refused the global shortcut" through the blanket catch. A platform row now grabs with all four modifiers.
  - `[low]` `[patch]` `HotkeyGrab.modifiers` was a mutable `Set` inside `==`/`hashCode` with no defensive copy, in a type whose own doc explains why equality here is load-bearing. `Set.unmodifiable` in the constructor, plus the value-contract test the Execution task asked for and the first pass omitted — without it the mutation survived.
  - `[low]` `[patch]` The new abort step's rationale asserted an unreachable state: `_releaseWithoutLifecycle` runs only when `lifecycle == null`, which is strictly before the only caller of `bindHotkey`, so no grab can ever be held there. Both the `main.dart` comment and the wiring row told the next maintainer otherwise. Relabelled defensive, to the same standard as the tray's `else if` arm.
  - `[low]` `[patch]` The abort path disposed the registrar but never `startup.hotkey`, leaving the adapter's controller and subscription behind while the step's own comment claimed it leaves nothing behind — and disagreeing with `DaemonLifecycle.shutdown()`, which does dispose it. Now disposes the adapter first, then the registrar.
  - `[low]` `[patch]` The live test's skip reason cited "DW-9/DW-26 for the display half", but neither entry is about the hotkey, and nothing recorded that the real grab, CAP-1's summon and CAP-12's live rebind were never observed — the project's convention is that an owed runtime claim lives in the ledger, not in a string inside a skipped test. Citation corrected and DW-44 appended.
  - `[low]` `[patch]` The Flutter-confinement row's doc overclaimed transitive coverage; it scans only `lib/src/infrastructure/hotkey/`. Narrowed to what it checks, naming `ad1_import_rule_test.dart` as what covers the domain half.
  - `[low]` `[patch]` The "refused before the release" ordering claim was asserted on a fresh registrar, where the release is a no-op either way, so swapping the two lines failed zero tests. The row now takes a live grab first, so the guarantee has something to lose.

### 2026-08-08 — Review pass (follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 11: (high 1, medium 2, low 8)
- defer: 1: (high 0, medium 1, low 0)
- reject: 9: (high 0, medium 0, low 9)
- addressed_findings:
  - `[high]` `[patch]` **A rebind refused before the backend was touched reported the hotkey as inactive while the previous combination stayed grabbed and kept firing.** Both pre-backend refusals — an unrepresentable key and one of the seven DW-43 labels — returned `HotkeyUnavailable` from ahead of `_releaseBeforeRebinding()`, so nothing was released, `_effective` still held the old combination, and the message said "the hotkey is inactive". `SettingsController.changeHotkey` stores the new preference either way, so the settings screen and the tray would both show no shortcut while the old one opened the panel for the rest of the session — and a later abandoned rebind would report the combination the caller had just been told was gone. The matrix never enumerated a refusal arriving on a live grab (A4 is stated on a fresh adapter), and AD-10 settles it without inference: `effective` is what is actually in effect, which is what the sibling refused-release path already reports. Refusals now answer `HotkeyBound(previous)` when something is held, logged so the abandonment is not silent, and keep A4's message when nothing is. Two rows added; mutation-verified.
  - `[medium]` `[patch]` **The set of labels `bind()` refuses was pinned by nothing.** The platform row written as the drift check filtered the observed labels *by* `labelsThatBindTheWrongKey` and compared the result against that same set — its actual was a function of its expected — and the adapter row iterates the set itself, so a shrunken set is a shorter loop. Verified directly: removing `'F3'` failed **zero** tests in both gates (534/2 binding-free, 11/11 platform), after which `bind(Alt+F3)` answered `HotkeyBound` for a usage the same file records as reaching the plugin as `GDK_KEY_KP_F3` — the tray stating hotkeys are available for a shortcut nothing the user can type will fire. This is the defect the previous pass patched (a drift check covering 11 of 63 labels) re-created one level up. The platform row now derives the set from an observed-versus-pressed keyval table, and a binding-free row pins it by literal value so `dart test` catches a shrink too.
  - `[medium]` `[patch]` `dispose()` racing an in-flight `release()` sent a **second `unregister` for the one identifier**: `_held` is cleared only after the platform call resolves (so a refused unregister can be retried), and the adapter's `dispose()` is deliberately not queued behind `bind()`, so a SIGTERM during a settings rebind reaches the seam while the rebind's own unregister is parked. `HotKeyManager.unregister` has no membership check, so both reach `hkm_unregister`, whose `std::find_if` misses on the second and leaves `keybinder_unbind` reading the uninitialised `const char*` this story files as DW-42 — reached from a path this project controls rather than a vendor edge case. In-flight unregisters are now coalesced; pinned by a platform row that parks the channel call.
  - `[low]` `[patch]` The adapter's post-grab `_disposed` recheck was **unreachable against the shipped seam**, which rejects a grab it observes landing after its own teardown. So the accurate "already been shut down" message and its compensating release were dead code, and an ordinary stop signal overlapping a rebind was reported as "this session refused the global shortcut" with an error-level log — sending the user to inspect their compositor for something the daemon did to itself. The branch was verified only by `FakeHotkeyRegistrar`, which documents that it deliberately does not honour the seam's post-dispose contract. The catch now distinguishes the disposed case (no compensating release: the seam already undid its own registration and would refuse one); the resolving branch is kept, relabelled defensive, and both are now pinned by separate rows.
  - `[low]` `[patch]` The Flutter-confinement row scanned for `package:flutter/` only, so `import 'dart:ui';` in the hotkey directory passed the very row whose stated purpose is protecting the binding-free command — and `dart:ui` is the exact import its own reason names as what `dart test` cannot resolve. `package:flutter_test/` and `package:flutter_riverpod/` were open the same way, the latter because `ad1_import_rule_test.dart` explicitly exempts it. Extended to all four; verified by adding `dart:ui` to `hotkey_grab.dart`, which now fails the row.
  - `[low]` `[patch]` The seam-ordering wiring row compared two `indexOf` results with no `isNonNegative` guard, so it passed vacuously the moment either marker was renamed or removed — `-1` is less than anything. The AD-4 row thirty lines below guards both of its indices; this one now does too.
  - `[low]` `[patch]` `HotkeyRegistrar.grab`'s contract stated no precondition about the seven DW-43 labels, and no implementation filters them, so a second caller would re-offer shortcuts that can never fire. Stated on the interface, along with *why* the seam deliberately does not enforce it: the platform suite has to keep registering all sixty-three to observe the keyvals they actually reach the plugin as, and that observation is the only thing that would notice an upstream fix.
  - `[low]` `[patch]` `main.dart`'s `_abort` and `_releaseWithoutLifecycle` took the concrete `HotkeyManagerRegistrar`, so the one-file backend swap this story advertises throughout was in fact a three-signature edit. Both now take the seam interface.
  - `[low]` `[patch]` `HotkeyGrab.toString()` rendered an empty modifier set as `HotkeyGrab( 0x00070045)` — a stray leading space that reads as a dropped modifier — in a type whose stated reason to exist is legible failure messages, and a test pinned the malformed form as correct.
  - `[low]` `[patch]` The registrar was disposed on the abort path but **not by `DaemonLifecycle`**, which is handed only the adapter. On X11 the adapter disposes the seam and hid the omission; on Wayland the adapter never saw it, so the seam `main.dart` built was closed on the failure path and left open on the one that runs on SIGTERM — while the abort step's own comment justifies itself with the Wayland case. Bounded today (the seam is inert on Wayland and `exit(0)` follows), but the parity the diff asserts held on one branch only. The lifecycle now closes both, in the abort path's order, with an ordering row and an AD-15 row.
  - `[low]` `[patch]` Four comments justified their branch with a combination "held for the rest of the X session with a dead handler" on paths that cannot reach that state: every path that disposes the seam is followed by `exit(0)` or `exit(1)`, and the X server drops a disconnecting client's passive grabs. The same overclaim shape the previous pass relabelled on the abort step. Corrected to what the branches actually buy — the seam and the native map not disagreeing (DW-42) — and `grab()`'s post-dispose undo now swallows a failing undo so every disposed-mid-grab call rejects with the same `StateError` rather than sometimes pre-empting it with a vendor error.

## Design Notes

**`hotkey_manager` is usable on the pinned toolchain, and AD-conformant only in part. Both halves matter.** It resolves, compiles, links and builds on Flutter 3.44.8 / Dart 3.12.2 — `flutter build linux --debug` succeeds in this container, and `keybinder-3.0` is installed here (0.3.2), which the dispatch's premise had wrong. So the dispatch's stated test for replacing it — unusable on the pinned toolchain — is not met, and this story implements with it. But two of the ADs the dispatch names are structurally unsatisfiable through it, and neither is fixable in Dart:

1. **AD-10's "a failed grab must not report success."** `keybinder_bind` returns a `gboolean` the plugin throws away, answering `true` regardless. The commonest real failure — another client already holds the combination — therefore arrives at this adapter as success, and the settings screen will show a shortcut that does nothing. This is the same class of defect story 6 found in `tray_manager`'s `set_icon`, on a load-bearing AD.
2. **AD-12's "a keybinder-3.0 library missing at runtime must not stop the daemon starting."** The plugin links keybinder at build time and `ldd` shows `libkeybinder-3.0.so.0` as a direct dependency of the daemon binary, so on a machine without it the dynamic loader fails before `main()`. Nothing degrades; nothing starts. This is **pre-existing** — the dependency has been pinned and in `generated_plugins.cmake` since before this story — and this story neither causes nor worsens it.

**The proposed replacement, stated rather than built.** Both gaps close with `dart:ffi` over `libkeybinder-3.0.so.0`: `DynamicLibrary.open` at bind time makes a missing library a caught error and an honest `HotkeyUnavailable`; calling `keybinder_bind` directly makes its result readable; and the accelerator string then genuinely is built in Dart, which is what AD-9 describes. Under AD-9 and this story's seam that is **one file** — `hotkey_manager_registrar.dart` swapped for a `keybinder_registrar.dart`, with `X11GlobalHotkey` and everything above it untouched. It is not built here for a reason that should not be skipped past: keybinder calls GDK and installs an X11 event filter, so it must run on the GTK main thread, while Dart FFI calls run on the Flutter UI thread. Doing it safely means marshalling `keybinder_init`/`keybinder_bind` onto the main loop with `g_idle_add` and returning the result through a `NativeCallable.listener` — and **none of that is exercisable in this container**, which has no X display, so an unattended run would ship a large threading surface that no test here could touch. Filed with this reasoning, for a session that has a real desktop.

**Why the serialization is not a keybinder string.** AD-9 says this adapter "serializes `HotkeyBinding` to keybinder's own syntax — `<Ctrl><Shift>g`". It does not, and cannot: the plugin builds that string itself in C with `gtk_accelerator_name`, from the keyval and modifier names the adapter sends. Probed here, the real output is `<Shift><Control>g` — AD-9's illustration is wrong on spelling and on order. Computing a Dart copy would be a prediction of what the plugin does, used by nothing and able to drift into a *misleading* diagnostic, which AGENTS.md §1 rules out. So AD-9's intent is honoured exactly — the domain type is translated inside infrastructure and the backend's vocabulary never rises above it — while its letter is corrected in the ledger, the way stories 1, 2 and 4 corrected AD-16, the Stack table and AD-2/AD-9's members. The serialization that does exist, and that the dispatch requires be unit-tested with no skip, is `HotkeyKeyCatalogue` plus the modifier mapping: label → USB HID usage → (in the seam) GDK keyval, with everything outside the catalogue refused before the backend is touched.

**Why a refused release abandons the rebind (A6).** The alternative — release fails, grab anyway — leaves keybinder holding two bindings, so one press fires twice, the AD-8 toggle shows and immediately hides, and the panel appears never to open. Abandoning leaves the user's previous shortcut working, and AD-10 already has the vocabulary for saying so: `effective` is "what is actually in effect", which on that path is the old combination, not the requested one. This is the same distinction story 6 arrived at the hard way with `_rendered` versus the request — report what is true, not what was asked for.

**Why no short-circuit on an unchanged binding (A3).** Re-grabbing the same combination is cheap and idempotent, and story 6 spent two review passes on a same-value short-circuit that keyed off the *request* and so blocked every recovery. There is nothing to gain and a known failure mode to avoid.

## Verification

**Commands:**
- `dart analyze` -- expected: no issues (AGENTS.md §6 merge gate).
- `dart format --output=none --set-exit-if-changed lib test` -- expected: 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: all pass with **no new skips**. Baseline measured on this story's parent revision: **493 passed / 2 skipped**. This command is also the AD-1 gate: it fails to resolve at all if `x11_global_hotkey.dart` gains a transitive Flutter import.
- `flutter test` -- expected: all pass. Baseline: **529 passed / 5 skipped**. `x11_hotkey_live_test.dart` must report as **skipped**, never passed; `hotkey_manager_registrar_test.dart` must report as **passed**, never skipped.
- `flutter build linux --debug` -- expected: builds. Baseline: builds today.
- `ldd build/linux/x64/debug/bundle/hotkey_grammar_corrector | grep keybinder` -- expected: `libkeybinder-3.0.so.0`, which is the evidence for the AD-12 ledger entry rather than a pass/fail gate.

**Mutation gates** — apply each, run the binding-free suite, record how many tests fail, revert. **Any that fails zero tests means the property is unpinned and the test is what needs fixing.**
1. Return `HotkeyBound` before awaiting the seam's grab → A5 must fail.
2. Delete the release step from the rebind path → A2 must fail.
3. On a refused release, report the *requested* binding as `effective` → A6 must fail.
4. Drop the catalogue null-check in `bind()` → A4 must fail.
5. Shift the letter run's start usage by one → B2 must fail (C2 would still pass, which is exactly why B is the gate).
6. Delete the `_disposed` guard on `bind()` → A10 must fail.
7. Send a null `keyCode` instead of refusing an unmapped usage → C2b must fail (C2 would still pass, since every catalogue entry maps — which is why C2b is a separate row).

**Manual checks (if no CLI):**
- **Not observable here, and must be reported as such.** No X display this process can reach, no session, no way to press a key. The real grab, CAP-1's sub-100 ms summon, CAP-12's rebind taking effect live, and whether `keybinder_bind` actually succeeded are **not observed** by this story. They are pinned by the registrar fake, the mocked channels and the build — none of which is a runtime observation, and none may be reported as one.
- Confirm by inspection that no file above `lib/src/infrastructure/hotkey/` names a keyval, an accelerator string or a `HotKey`, and that no log line carries a caught error's `toString()`.


## Auto Run Result

Status: done
Blocking condition: none

### Summary of implemented change

A follow-up review pass over story 7's shipped diff (`2baaef6..HEAD`, 20 files, ~3,140 insertions). No new feature work: the story's implementation stands, and this pass hardened it. Four review layers ran in parallel with no prior conversation context (adversarial, edge-case, verification-gap, intent-alignment) and produced 21 distinct findings after deduplication — **0 intent_gap, 0 bad_spec**, 11 patched, 1 deferred, 9 rejected.

**One defect was user-visible and is the reason this pass mattered.** Both of `bind()`'s pre-backend refusals returned from *ahead* of the release step, so a rebind onto a key this build cannot register left the previous combination grabbed and firing while reporting `HotkeyUnavailable` — "the hotkey is inactive" — and `SettingsController.changeHotkey` writes the new preference regardless. The user's old shortcut would keep opening the panel all session with both surfaces showing none. The matrix has no row for a refusal arriving on a live grab (A4 is written on a fresh adapter), but AD-10 settles it without inference — `effective` is what is actually in effect — and the sibling refused-release path already answers exactly that way. Two independent reviewers reproduced it by probe before it was touched.

**Two more were properties pinned by tests that could not fail.** The set of labels `bind()` refuses (DW-43's seven) was tied to nothing: the row written as the drift check compared the set against a filtered subset of itself. I verified this directly rather than taking it on report — removing `'F3'` failed **zero** tests in both gates, after which `bind(Alt+F3)` reported success for a combination keybinder holds on `GDK_KEY_KP_F3`. And `dispose()` racing an in-flight `release()` sent two `unregister` calls for one identifier, walking straight into the uninitialised `const char*` this story itself files as DW-42.

The remaining eight are diagnostics, contract statements and test robustness: a dead branch that made an ordinary shutdown look like a refused grab, a confinement row blind to the one import its own reason names, an ordering row that passed vacuously, an unstated seam precondition, a concrete vendor type leaking into two teardown signatures, a malformed `toString`, a teardown-parity gap on the Wayland path, and four comments asserting a consequence their branch cannot reach.

### Files changed

**`lib/`**
- `src/infrastructure/hotkey/x11_global_hotkey.dart` — refusals route through a new `_refusedBeforeBackend`, which reports the still-live binding when a rebind is abandoned; the disposed case is distinguished inside the grab's catch; the resolving-seam branch relabelled defensive with an accurate consequence.
- `src/infrastructure/hotkey/hotkey_manager_registrar.dart` — in-flight `unregister` coalesced against DW-42; the post-dispose undo now always rejects with its `StateError`; comments corrected.
- `src/infrastructure/hotkey/hotkey_registrar.dart` — states the wrong-key precondition callers own, and why implementations deliberately do not enforce it.
- `src/infrastructure/hotkey/hotkey_grab.dart` — `toString()` no longer emits a stray space for a bare-key grab.
- `src/infrastructure/system/daemon_lifecycle.dart` — takes `closeHotkeyRegistrar` and releases the seam after the adapter, matching the abort path.
- `main.dart` — passes the seam into the lifecycle; both teardown helpers take `HotkeyRegistrar` rather than the vendor adapter.

**`test/`** — `hotkey_key_catalogue_test.dart` (refusal set pinned by literal), `x11_global_hotkey_test.dart` (two live-grab refusal rows, one rejecting-seam teardown row, corrected `toString` expectation), `hotkey_manager_registrar_test.dart` (derived wrong-key linkage, the DW-42 coalescing row, a channel-parking harness), `hotkey_confinement_test.dart` (four Flutter-reaching references), `composition_wiring_test.dart` (`isNonNegative` guards), `daemon_lifecycle_test.dart` (new step in four ordered lists, plus an ordering row and an AD-15 row).

**Ledger** — one new entry appended, touching nothing existing: `HotkeyModifier.meta` reaching keybinder as GDK's virtual `GDK_META_MASK` rather than the Mod4 a Super key produces — the modifier-axis twin of DW-43, unobservable without a real keymap.

### Review findings breakdown

Patched 11 (high 1, medium 2, low 8) — full detail in the Review Triage Log. Deferred 1 (medium): the `meta` modifier mask, which needs a real X session to settle and whose two candidate fixes an unattended run must not guess between.

Rejected 9, all low, with reasons: a second in-flight guard inside the seam (the adapter serializes and the interface now states the contract); the required registrar parameter forcing a `test/fakes/` import into `test/support/` (the spec prescribes that parameter, and a support entry point importing a fake is unremarkable); routing internal `StateError`s to their own user message (the one reachable case, disposal, is now distinguished — the rest is a vendor rename already covered by a platform row, and further branches would be unpinnable); the hard-coded wrong-key snapshot being detectable only outside the default runner (the actionable half is patched; the residue is what DW-43 records); guarding `_onKeyDown` on the identifier (C3's claim is satisfied and observed at the channel by the vendor's own routing, and the guard could not be made to fail a test); renaming `stub_hotkey_adapters_test.dart` (the spec's Tasks explicitly require keeping the file and documenting that the X11 half was replaced rather than deleted); refusing a bare-key empty-modifier grab (matrix A12 makes it legal on the intent's own authority, and the consequence is already filed); C2b's null-keyval condition being met by a catalogue-membership proxy (the keyval is computed inside `uni_platform`, which AD-1 puts out of reach, and the seam's doc already says so); and a token-level scan for accelerator strings above the seam (with no vendor import above it there is nothing to consume one, and a hex-literal scan would be noise).

**Follow-up review recommendation: `true`.** Patched this pass: high 1, medium 2, low 8 — a high-severity patch sets it `true` outright, and the score `3×2 + 1×8 = 14` clears the threshold of 5 independently.

### Verification performed

| Command | Outcome |
|---|---|
| `dart analyze` | no issues |
| `dart format --output=none --set-exit-if-changed lib test` | 129 files, 0 changed |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **540 passed / 2 skipped** (534/2 before this pass; spec baseline 493/2) — no new skips, and the command resolving at all is the AD-1 gate |
| `flutter test` | **588 passed / 6 skipped** (581/6 before this pass; spec baseline 529/5) |
| `flutter build linux --debug` | built |
| `ldd … \| grep keybinder` | `libkeybinder-3.0.so.0 => /lib/x86_64-linux-gnu/libkeybinder-3.0.so.0` |

`x11_hotkey_live_test.dart` re-confirmed **skipped, never passed**; `hotkey_manager_registrar_test.dart` re-confirmed **passed**, now 12 rows.

**Mutation gates** — the spec's seven re-run against the patched code to confirm none was unpinned by these edits, plus one per new patch. Failures per mutation: spec gates 1–7 → 15, 4, 12, 12, 9, 12, 12. New gates → refusal always reports inactive 10; drop `'F3'` from the refusal set 10 binding-free **and** 9 platform (**0 and 0 before this pass** — this is the gate that was missing); uncoalesced unregister non-zero; no disposed branch in the catch 4; `dart:ui` in the hotkey directory 1; `toString` stray space 12; no seam step in the lifecycle 7. Plus a robustness check on the wiring row: with its marker absent the row now fails rather than passing vacuously. **None fails zero.** The two doc-only patches (the seam precondition, the corrected comments) carry no gate, and are marked as such rather than counted.

### Not observed, and stated as unobserved

Unchanged from the story, and worth restating because this pass added nothing runtime. This container has no compositor, no session and no reachable X display. **That any of this works on a real desktop is still not observed**: not that keybinder accepts the combination, not that a press raises the panel inside CAP-1's budget, not that CAP-12's rebind is live without a restart, and — separately and unfixably, per DW-39 — not whether `keybinder_bind` succeeded at all. DW-44 carries those. The newly deferred `meta` finding is in the same category: it is a reasoned prediction from the GDK modifier semantics and the vendor's string mapping, **not** a measurement, and the ledger entry says so.

### Residual risks

1. **`bind()` answering `HotkeyBound` still does not mean the combination is held** (DW-39). Unchanged and unfixable through the pinned package.
2. **The abandoned-rebind surface now has two routes into it.** The previously filed entry — an abandoned rebind reporting a truthful `effective` with no failure signal until story 10 builds the screen that would show it — now covers the pre-backend refusal path as well, because that is the fix this pass applied. The existing entry was left untouched, as instructed; its scope is simply wider than when it was written, and story 10 should read it that way. The refusal is logged, so it is not invisible to an operator, only to the user.
3. **`HotkeyModifier.meta` may bind the wrong mask** (newly deferred). A user configuring Super+G could get Alt+G or nothing, reported as success by DW-39.
4. **Seven of the sixty-three labels remain unusable** (DW-43), now pinned from both directions so the set cannot silently drift.
5. **A daemon without `libkeybinder-3.0.so.0` does not start** (DW-40). Pre-existing, out of scope.
6. **`main()` remains reachable by no test** (DW-8/DW-24). This pass added two source-index guards to that surface and one lifecycle step that *is* behaviourally tested, which moves one claim off the source-scan surface and onto the tested one.
7. **The two doc-only patches are unpinned by construction.** The seam's wrong-key precondition and the corrected comments are prose; nothing fails if a later edit contradicts them. Stated rather than papered over with a test that would only assert its own text.
