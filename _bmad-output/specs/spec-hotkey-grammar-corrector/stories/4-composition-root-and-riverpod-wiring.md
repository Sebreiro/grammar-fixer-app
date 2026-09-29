---
title: 'Composition root and Riverpod wiring'
type: 'feature'
created: '2026-08-07'
status: 'done'
baseline_revision: '4e9db0b263e1f66f9be16190628ea9d66515405d'
final_revision: '881f61e4e9618b9c5417dd6ae641db4b9173811f'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/deferred-work.md'
  - '{project-root}/lib/main.dart'
  - '{project-root}/lib/src/domain/config/app_config.dart'
  - '{project-root}/lib/src/application/settings_controller.dart'
  - '{project-root}/lib/src/infrastructure/correction/provider_registry.dart'
  - '{project-root}/linux/runner/my_application.cc'
warnings: ['multiple-goals', 'oversized']
---

<intent-contract>

## Intent

**Problem:** `lib/main.dart` is still `void main() {}`. Three controllers, six adapters, a config store, a database and a singleton lock all exist and are proven against fakes, but nothing constructs them, so none of it runs in a process — every guard, every port and every AD in stories 1–3 is unexercised. Four deferred-work defects are blocked on exactly this: the generated Linux runner still shows a 1280×720 window on first frame (AD-8 says the panel is only ever shown by the toggle); the domain value types and both application states compare by identity, so no Riverpod `select` or `Stream.distinct` consumer can dedupe; `SettingsController`'s echo suppression rests on instance identity that `ConfigStore.changes` never promised; and `AppConfig.sidecarPath`/`interpreterPath` are a second, unread home for the AD-19 paths the registry actually reads out of `ProviderConfig.settings`.

**Approach:** Stand up the daemon. Declare the Riverpod provider graph in `lib/src/application/composition/` as un-overridden port seams (AD-17), have `main.dart` acquire the AD-14 lock, load config, detect the display server, construct exactly one hotkey adapter, resolve the single active `(CorrectionProvider, Preset)` pair through the existing registry (AD-5, AD-15), install those as `ProviderScope` overrides, and create the window once and leave it hidden (AD-8). Along the way: give the value types real equality, switch the echo check to `==`, and collapse the duplicated AD-19 path home down to the one the registry reads.

## Boundaries & Constraints

**Always:**
- AD-17 / AD-1 jointly: `lib/src/application/composition/**` may import only `dart:`, `package:flutter_riverpod/`, `application/` and `domain/` — never infrastructure. Every port a provider exposes is declared there as a seam that throws until overridden, and `main.dart` (outside `lib/src/`, so outside the AD-1 gate) supplies the concrete adapters as `ProviderScope` overrides. `test/architecture/ad1_import_rule_test.dart` must stay green with no change to its rules.
- AD-5: `main.dart` resolves exactly one `(CorrectionProvider, Preset)` pair and injects it. Nothing below the composition root selects a provider or receives a model id without its prompt.
- AD-15: provider selection stays the existing `ProviderRegistry` map lookup. No `switch (providerId)` anywhere.
- AD-9: the display server is read from `XDG_SESSION_TYPE`, falling back to a non-empty `WAYLAND_DISPLAY`; **exactly one** hotkey adapter is constructed at startup and there is no runtime switch. Detection is a pure function over an injected environment map.
- AD-8: the window is created once at startup and left hidden. Nothing on any show path allocates, loads, or awaits IO. Launching the daemon leaves no visible window.
- AD-14: the singleton lock is acquired before anything else is built. `alreadyRunning` signals the holder and exits 0; `unavailable` logs the lock's own warning and starts anyway.
- AD-13: `ConfigStore` stays the only reader of the config file, and a malformed file surfaces its warning through the `Logger` without failing startup.
- AD-19: the interpreter and sidecar paths reach the adapter from config and from nowhere else.
- Consistency Conventions: `.name` for enums, `Clock` for time, structured stderr lines through the one `Logger`, and never `input_text`, clipboard content or a suggestion body in a log line.
- Value equality is deep and collection-aware: sets compare as sets, maps as maps, lists in order — never by identity on the collection. `hashCode` agrees with `==` for every type given one.
- Every test other than the provider-graph tests runs with no Flutter binding, and cites its CAP or AD id.

**Block If:**
- Satisfying AD-17 (`application/composition/` *is* the composition root) cannot be done without `lib/src/application/**` importing `lib/src/infrastructure/**`. That is a direct AD-1/AD-17 collision and needs a spine renegotiation, not an unattended choice.
- Adding `operator==`/`hashCode` to a spine-verbatim declaration (AD-2's `Preset`, `Suggestion`, `CorrectionFailed`; AD-9's `HotkeyBinding`, `HotkeyRegistration`) turns out to require changing its declared **fields** or constructor. Adding members is in scope; rewriting a declaration is not.

**Never:**
- No real hotkey, clipboard, panel-visibility or tray backend — stories 5–8 own those. This story ships stubs behind the ports that report their unimplemented state honestly, and never reports a successful bind.
- No panel widgets and no settings widgets (stories 9, 10). The only widget here is the minimal hidden-window shell the daemon needs to exist.
- No `.desktop` files, no autostart, no sidecar provisioning, no installed-asset path derivation (story 11).
- No new dependency and no pubspec pin change.
- No retry, cascade or fallback between providers. A config naming a provider this build does not ship yields a modelled `providerUnavailable` failure on the first correction, never a second backend.
- Do not fix the other open ledger entries riding on these files: `SettingsController`'s mutation-generation race and unbounded `_ownWrites` growth, `PanelController`'s missing `_disposed` guards, the unbounded `Future.wait(_pendingSaves)`, corrupt-history recovery, history retention and file permissions, the `SqliteException` vendor-type escape. They stay filed.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Startup, lock free (AD-14) | No instance running | Lock `acquired`; graph built; window created and hidden; process stays resident | No error expected |
| Startup, lock held (AD-14) | A daemon already holds the address | The holder receives exactly one show request; the second process exits 0 without building a graph, a window, or a database | No error expected |
| Startup, lock unavailable (AD-14) | Bind and connect both fail | The lock's own warning reaches the `Logger`; startup continues | Never throws |
| Startup, malformed config (AD-13) | Unparseable `config.json` | Defaults become current; `ConfigLoadResult.warning` is logged at warning level; startup continues | Never throws |
| Display server, explicit (AD-9) | `XDG_SESSION_TYPE=wayland` / `=x11` | Wayland / X11 adapter respectively | No error expected |
| Display server, fallback (AD-9) | `XDG_SESSION_TYPE` unset or unrecognised, `WAYLAND_DISPLAY=wayland-0` | Wayland adapter | No error expected |
| Display server, neither (AD-9) | Both unset, or `WAYLAND_DISPLAY` empty | X11 adapter | No error expected |
| Active pair, valid (AD-5) | Config whose active preset names a shipped provider | The registry-built provider and that preset are the injected pair | No error expected |
| Active pair, unknown provider (AD-5, AD-19) | Active preset's `providerId` is in no registry entry | Startup completes; the injected provider emits exactly one `CorrectionFailed(providerUnavailable, …)` naming the unknown id and then closes | Error logged; never throws, never blocks startup |
| Active pair, dangling preset id | `activePresetId` names no preset (a `ConfigStore` contract breach) | The shipped default preset is used | Error logged naming the id; startup continues |
| Hotkey bind at startup (AD-12) | Either stub adapter | `bind()` resolves to `HotkeyUnavailable`; the tray port is told hotkeys are unavailable; the daemon stays up | No throw; one warning naming unavailability |
| Show request while resident (AD-14) | A second launch signals the holder | The holder fires `PanelVisibility.show()` without awaiting on the decision path | A rejected `show()` is logged, never thrown |
| Shutdown ordering | Daemon stops with a history write in flight | Lock subscription cancelled, then controllers disposed (pending save awaited), then container disposed, then hotkey, database, config store and lock closed — in that order | Each step logged on failure; shutdown always completes |
| Double dispose | `dispose()` called twice on any controller, or the container disposed after an explicit teardown | Second call is a no-op | Never throws |
| Equality, AppConfig | Two separately built configs with equal providers, presets, id and binding | `==` is true and `hashCode` matches | No error expected |
| Equality, modifier set order | `{control, shift}` vs `{shift, control}`, same key | `HotkeyBinding` `==` is true — set equality, not identity or order | No error expected |
| Equality, one field differs | Any of the above with one differing field (including a differing nested `Preset`, `ProviderConfig` setting, or `Suggestion`) | `==` is false | No error expected |
| Equality, states | `CorrectionState` with equal `suggestionTexts` maps; `SettingsState` with equal config, bind outcome and failure | `==` is true; a differing map entry or failure kind makes it false | No error expected |
| Dedupe consumer | Two successive equal `CorrectionState`s (and `SettingsState`s) through `Stream.distinct()` | One event, not two | No error expected |
| Echo suppression by value | This controller writes a config; the store emits an **equal but not identical** instance on `changes` | No second `SettingsState` is emitted — the write is recognised as its own | No error expected |
| External write | The store emits a config this controller never wrote | State updates to it, keeping the displayed failure and bind outcome | No error expected |
| AD-19 path home | Config JSON that still carries the old `sidecarPath` / `interpreterPath` keys | Loads successfully; the extra keys are ignored; the adapter's paths come from `ProviderConfig.settings` | Never throws, never falls back to defaults |

</intent-contract>

## Code Map

- `lib/main.dart` -- `void main() {}` today. Becomes the composition root: lock, config, database, active pair, display server, window, `ProviderScope` overrides, ordered shutdown.
- `lib/src/application/composition/` -- **new**; the Riverpod graph (AD-17). Port seams plus the controller providers built from them. May not import infrastructure.
- `lib/src/application/settings_controller.dart` -- `_ownWrites` is `Set<AppConfig>.identity()` at line 65 and `_onConfigChanged` removes from it at line 278; both switch to value equality.
- `lib/src/application/{correction,settings}_state.dart` -- the two states that need `==`/`hashCode`.
- `lib/src/domain/config/app_config.dart` -- gains equality; **loses** `sidecarPath` and `interpreterPath` (see Design Notes). `copyWith` shrinks with it.
- `lib/src/domain/config/provider_config.dart`, `correction/correction_record.dart`, `hotkey/hotkey_binding.dart` -- the ledger's three other equality targets.
- `lib/src/domain/correction/{preset,suggestion,correction_event}.dart`, `lib/src/domain/hotkey/{global_hotkey,hotkey_bind_outcome}.dart` -- AD-2/AD-9-verbatim declarations that need equality **because a target above contains them**; members added, fields untouched.
- `lib/src/infrastructure/config/json_config_store.dart` -- `_toJson` (line 234) and `_decode` (line 245) stop writing and reading the two removed keys. Unknown keys are already ignored on decode, which is what keeps existing files loading.
- `lib/src/infrastructure/config/default_app_config.dart` -- drops the two duplicated `AppConfig` fields; the provider settings map stays the one home. Also exposes the shipped `Preset` for the dangling-id backstop.
- `lib/src/infrastructure/correction/provider_registry.dart` -- unchanged; it already reads only `ProviderConfig.settings`. The lookup `main.dart` uses.
- `lib/src/infrastructure/system/single_instance_lock.dart` -- `acquire()` / `showRequests` / `release()` / `dispose()`, and `SingleInstanceStatus`.
- `lib/src/infrastructure/persistence/app_database.dart` -- `AppDatabase.file`; its background isolate is why shutdown must `close()` it.
- `lib/src/infrastructure/config/app_paths.dart` -- `AppPaths.fromEnvironment`, `configFile`, `databaseFile`, `runtimeDirectory`, `warning`.
- `linux/runner/my_application.cc` -- `first_frame_cb` (line 19) is the stock `gtk_widget_show` on the toplevel that AD-8 forbids.
- `test/fakes_smoke_test.dart`, `test/application/{settings_controller,controller_resilience}_test.dart`, `test/infrastructure/config/{json_config_store,default_app_config}_test.dart` -- every construction site of the two removed `AppConfig` fields.
- `test/architecture/ad1_import_rule_test.dart` -- the merge gate the new composition files must not trip.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- holds the four entries this story closes.

## Tasks & Acceptance

**Execution:**

*Value equality (ledger items 2 and 3)*
- `lib/src/domain/collection_equality.dart` -- create; `listEquals`, `setEquals`, `mapEquals` plus their hash helpers over `dart:core` only -- domain cannot import `package:collection` or `package:flutter/foundation.dart` (AD-1), so the helpers must be owned here and shared by both rings.
- `lib/src/domain/hotkey/hotkey_binding.dart`, `.../global_hotkey.dart`, `.../hotkey_bind_outcome.dart` -- add `operator==`/`hashCode` to `HotkeyBinding` (set equality on `modifiers`), `HotkeyRegistration`, `HotkeyBound` and `HotkeyUnavailable` -- `HotkeyBinding` is the ledger's named target and the other three are what `SettingsState` transitively contains.
- `lib/src/domain/correction/{preset,suggestion,correction_event,correction_record}.dart` -- add `operator==`/`hashCode` to `Preset`, `Suggestion`, `CorrectionFailed` and `CorrectionRecord` (list equality on `suggestions`) -- `CorrectionRecord` is the ledger's target and the first three are what it and `CorrectionState` contain. Leave `SuggestionDelta` and `CorrectionCompleted` alone: the ledger's rule is to add equality where a consumer needs it, and neither has one.
- `lib/src/domain/config/{provider_config,app_config}.dart` -- add `operator==`/`hashCode` (map equality on `providers` and `settings`, list equality on `presets`).
- `lib/src/application/{correction_state,settings_state}.dart` -- add `operator==`/`hashCode` to `CorrectionState` (map equality on `suggestionTexts`), `SettingsState` and `SettingsFailure`.
- `lib/src/application/settings_controller.dart` -- change `_ownWrites` from `Set<AppConfig>.identity()` to a value-equality `Set<AppConfig>` and update the doc comment, which currently justifies identity with "`AppConfig` defines no equality" -- `ConfigStore.changes` promises no instance identity, so identity silently stops suppressing the echo the moment an adapter rebuilds the value.

*AD-19 path home (ledger item 4)*
- `lib/src/domain/config/app_config.dart` -- delete the `sidecarPath` and `interpreterPath` fields, their constructor parameters and their `copyWith` entries -- they are read by nothing; see Design Notes for why deleting beats bridging.
- `lib/src/infrastructure/config/json_config_store.dart` -- stop encoding and decoding those two keys; unknown keys already decode silently, so a config file written by the story-1 build keeps loading.
- `lib/src/infrastructure/config/default_app_config.dart` -- drop the two `AppConfig` arguments, keep the two settings-map entries, and add a `static const Preset shippedPreset` the composition root can fall back to.
- `test/architecture/ad19_path_home_test.dart` -- create; assert that `AppConfig` declares no interpreter/sidecar path member, and that the only files under `lib/` naming the interpreter or sidecar settings keys are the adapter that owns them, the registry that reads them, and the default config that seeds them -- this is the test that fails if a second home is ever reintroduced.

*Composition root (AD-5, AD-9, AD-14, AD-15, AD-17)*
- `lib/src/infrastructure/hotkey/display_server.dart` -- create `DisplayServer` (enum plus `DisplayServer.fromEnvironment(Map<String, String>)`) implementing AD-9's `XDG_SESSION_TYPE`-then-`WAYLAND_DISPLAY` rule -- a pure function over an injected map is the only shape that is testable with no session.
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart`, `.../wayland_portal_global_hotkey.dart` -- create `X11GlobalHotkey` and `WaylandPortalGlobalHotkey` as stubs at their final paths: `activations` is a broadcast stream that never emits, `bind()` resolves to `HotkeyUnavailable` naming the story that will implement it, `dispose()` closes the stream -- AD-9 requires the *selection* to be real now; stories 7 and 8 fill in the bodies.
- `lib/src/infrastructure/panel/unimplemented_panel_visibility.dart`, `lib/src/infrastructure/clipboard/unimplemented_clipboard.dart`, `lib/src/infrastructure/tray/unimplemented_tray.dart` -- create honest placeholders behind `PanelVisibility`, `ClipboardPort` and `TrayPort` so the graph can be built -- named for what they are rather than squatting on stories 5 and 6's adapter names.
- `lib/src/infrastructure/correction/unconfigured_correction_provider.dart` -- create; emits exactly one `CorrectionFailed(providerUnavailable, message)` then closes -- AD-3's shape for "config names a provider this build does not ship", and the reason an unknown id cannot block startup (AD-19).
- `lib/src/infrastructure/correction/active_correction.dart` -- create `ActiveCorrection` with a static resolver taking the config, the registry and the `Logger` and returning the single `(provider, preset)` pair -- AD-5's resolution kept out of `main.dart`'s untestable body while staying composition-root code.
- `lib/src/application/composition/port_providers.dart` -- create the un-overridden seams: logger, clock, config store, clipboard, panel visibility, global hotkey, tray, correction repository, active correction provider, active preset. Each throws until overridden, with a message naming `main.dart` -- this file *is* the composition root's contract (AD-17), and throwing is what makes a missing override a startup failure rather than a silent null.
- `lib/src/application/composition/controller_providers.dart` -- create `correctionControllerProvider`, `panelControllerProvider` and `settingsControllerProvider`, each built from the seams above with `ref.onDispose` registered -- so no path leaks a controller, while `main.dart` still owns the ordered async teardown.
- `lib/src/application/panel_controller.dart` -- add `void showPanel()` beside `onHotkeyActivated()`, using the same non-awaiting `_fire` path -- AD-14's holder must *show*, not toggle, and story 6's tray needs the same call.
- `lib/src/ui/daemon_app.dart` -- create `DaemonApp`, a minimal `MaterialApp` shell -- the window has to have a root widget to exist; the panel replaces its home in story 9.
- `lib/main.dart` -- rewrite as the composition root: `WidgetsFlutterBinding.ensureInitialized()`, `AppPaths.fromEnvironment(Platform.environment)`, `StderrLogger` over `SystemClock`, `SingleInstanceLock.acquire()` (exit 0 on `alreadyRunning`), `JsonConfigStore.load()` with its warning logged, `AppDatabase.file` + `DriftCorrectionRepository`, `ActiveCorrection.resolve` over `ProviderRegistry`, one hotkey adapter from `DisplayServer`, `windowManager.ensureInitialized()` + `waitUntilReadyToShow` with **no** `show()`, `runApp(ProviderScope(overrides: …, child: DaemonApp()))`, the `showRequests` subscription, the startup `bind()` whose outcome reaches `TrayPort.setHotkeyUnavailable`, and the ordered shutdown -- split into named private functions, one job each (AGENTS.md §2).

*Hidden window (ledger item 1)*
- `linux/runner/my_application.cc` -- delete `first_frame_cb` and its `g_signal_connect_swapped`, leaving `gtk_widget_realize` in place, and comment why -- the window must be constructed and warm but never mapped (AD-8). Keep everything else stock.
- `test/architecture/hidden_window_test.dart` -- create; assert the runner shows no toplevel on first frame and that no file on the startup path calls `windowManager.show()` -- the runtime claim is not provable in this container (see Verification), so this pins the edit against silent reversion.

*Tests*
- `test/domain/value_equality_test.dart` -- create; cover every equality row of the matrix, including the modifier-set order case and one differing-field case per type.
- `test/application/state_equality_test.dart` -- create; `CorrectionState` and `SettingsState` equality plus the `Stream.distinct()` dedupe row.
- `test/application/settings_controller_test.dart` -- add the echo-by-value row (an equal but non-identical config emitted on `changes` produces no second state) and the external-write row; update the `AppConfig` construction site.
- `test/infrastructure/hotkey/display_server_test.dart` -- create; every AD-9 detection row.
- `test/infrastructure/correction/active_correction_test.dart` -- create; the valid, unknown-provider and dangling-preset rows, asserting the unknown-provider stream yields exactly one `CorrectionFailed(providerUnavailable, …)`.
- `test/composition/composition_root_test.dart` -- create (needs a Flutter binding, hence its own directory); over a `ProviderContainer.test` with every port overridden by its fake: each controller is constructed from the injected ports, the active pair reaches `CorrectionController`, reading a seam with no override throws, and disposing twice is a no-op.
- `test/fakes_smoke_test.dart`, `test/application/controller_resilience_test.dart`, `test/infrastructure/config/{json_config_store,default_app_config}_test.dart` -- update the `AppConfig` construction sites for the two removed fields; keep every existing assertion.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- retain the headings and historical text of the four entries this story closes (the linux-runner one, the domain value-equality one, the `CorrectionState`/`SettingsState` one, and the unbridged AD-19 path homes one); set each `status: done <date>` and add a `resolution:` citing the closing evidence. Leave every other entry untouched, and append new findings.

**Acceptance Criteria:**
- Given a fresh environment, when `main()` runs to the point of `runApp`, then exactly one hotkey adapter exists, one `(CorrectionProvider, Preset)` pair was resolved through `ProviderRegistry`, and no file under `lib/src/application/` imports infrastructure (AD-5, AD-9, AD-15, AD-17).
- Given a resident daemon and a second launch, when the second process starts, then it exits 0 without constructing a graph, a window or a database, and the holder receives exactly one show request (AD-14, CAP-1).
- Given the built Linux binary, when it is launched, then no window is mapped and the process stays resident (AD-8) — pinned as far as this container allows; see Verification.
- Given a shutdown with a history write in flight, when the daemon stops, then the pending write is awaited before `AppDatabase.close()`, the lock's show-request subscription is cancelled before the controllers are disposed, and the process exits (CAP-7).
- Given the deferred-work ledger, when the story completes, then the four named headings remain, each entry has `status: done <date>` and a `resolution:` citing the closing evidence, and every other entry remains unchanged.
- Given the full suite, when `dart analyze`, `dart format --set-exit-if-changed lib test`, the binding-free `dart test` run and `flutter test` all run, then all four pass, including `test/architecture/ad1_import_rule_test.dart` and every pre-existing suite (baseline: 296 passed, 1 skipped).

## Spec Change Log

## Review Triage Log

### 2026-08-07 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 1, medium 5, low 2)
- defer: 9: (high 0, medium 5, low 4)
- reject: 10: (high 0, medium 0, low 10)
- addressed_findings:
  - `[high]` `[patch]` The equality suite was vacuous for every type declared with `const` on both sides — Dart canonicalises identical constant expressions to one instance, so those rows compared an object with itself. Confirmed by mutation: neutering `Suggestion`, `HotkeyRegistration`, `HotkeyBound`, `HotkeyUnavailable` and `CorrectionFailed` to identity equality left **all 412 binding-free tests green**, and removing `Preset`'s `operator==`/`hashCode` entirely left `value_equality_test.dart` green. Rewrote `test/domain/value_equality_test.dart` and `test/application/state_equality_test.dart` to build both sides at runtime with no `const`, rebuilt the nested values in `_record()`/`_config()`/`_settingsState()` per call (a shared constant element makes a list or map comparison pass without consulting the element's own `==`), and routed every positive row through a new `test/support/value_equality.dart` helper whose `identical` guard fails loudly if a row ever collapses again. Re-verified: the same mutation now kills 9 tests in the domain suite and 6 in the state suite.
  - `[medium]` `[patch]` `test/architecture/hidden_window_test.dart`'s AD-8 mapping bans were receiver-bound substrings, and AD-8's runtime observation could not be made in this container (DW-9), so they were the whole pin. Confirmed by mutation: `await WindowManager.instance.show()` in `_createHiddenWindow` (the same call, since `windowManager` *is* `WindowManager.instance`) and `gtk_widget_set_visible(GTK_WIDGET(window), TRUE)` in the runner both passed all 7 tests. Inverted both to allowlists — the GTK functions the runner may call against `window`, and the `window_manager` methods the startup path may reach, whatever receiver spells them — added the missing GTK bans, and added a guard against aliasing `WindowManager.instance` to a local. Both mutations now fail 3 tests.
  - `[medium]` `[patch]` `test/architecture/composition_wiring_test.dart` asserted `contains('_installSignalHandlers(')`, which the function's own declaration satisfies, so deleting the call site left it green. Now matches the call site by regex and asserts it precedes `_finishStartup(`, which is the ordering `main.dart` says is deliberate. Mutation-verified.
  - `[medium]` `[patch]` `main.dart`'s `exit(0)` on the not-the-daemon branch was pinned by nothing — the AD-14 child-process row spawns `test/support/daemon_startup_child.dart`, which carries its own `exit(0)`, so it verifies a copy of the branch and never this one. Reverting it to `return` left every suite green, reinstating the exact regression DW-14 records as found in the implementation pass. Now asserted inside the branch. Mutation-verified.
  - `[medium]` `[patch]` `_overriddenSeams()` captured only the provider name to the left of `.overrideWithValue(`, so no value `main.dart` binds was asserted anywhere. Replacing `onShowRequest: graph.showPanel` with an empty closure (AD-14's whole payoff gone) and `globalHotkeyProvider.overrideWithValue(startup.hotkey)` with a fresh `X11GlobalHotkey()` (two adapters where AD-9 allows one) both left every suite green. Both arguments are now asserted. Mutation-verified.
  - `[medium]` `[patch]` Only the last step of startup was inside the abort guard: anything thrown between `DaemonStartup.begin` taking the AD-14 address and `_finishStartup` escaped `main` into an already-running GTK loop, leaving a process holding the singleton address with no graph, no window and no way in — verbatim the failure `_abort`'s doc says it exists to prevent. Extended the guard over the graph build, the container and the lifecycle; `_abort` now takes a nullable lifecycle and falls back to closing the database, the config store and the lock directly when the failure landed before one existed. Also made `DaemonStartup.begin` hand the address back if any step after `acquire()` throws. Pinned by a new source-scan assertion; the `begin` guard is defence in depth that nothing on today's path can trigger (`NativeDatabase.createInBackground` is lazy), which is stated rather than fabricated into a test.
  - `[low]` `[patch]` `ref.onDispose(controller.dispose)` type-checks against `void Function()` and discarded both the wait and any rejection, so a failing teardown on the container-only path became an unhandled async error instead of the log line every other teardown step produces. Now routed through `_disposeWith`, which logs the rejection against a logger captured at build time rather than read back off a disposing container.
  - `[low]` `[patch]` `_installSignalHandlers` watched SIGINT and SIGTERM only, while its own doc names "a logout" — a terminal close or X-session logout delivers SIGHUP, whose default disposition kills the process past the ordered teardown and abandons the CAP-7 write in flight. Added, and asserted.

## Design Notes

**AD-17 and AD-1 do not actually collide — the override seam is what reconciles them.** AD-17 puts the composition root in `application/composition/`; AD-1 forbids `application/` from importing `infrastructure/`, and `ad1_import_rule_test.dart` enforces it mechanically (it already whitelists `package:flutter_riverpod/`). The resolution is the standard Riverpod shape: the composition file declares *typed seams* over domain ports and throws until overridden, and `main.dart` — which lives outside `lib/src/` and so outside the gate — is the only place naming a concrete adapter. That is also exactly what AD-17's second sentence says main.dart is for. If this turns out not to hold, it is the Block If.

```dart
// lib/src/application/composition/port_providers.dart
final loggerProvider = Provider<Logger>(
  (ref) => throw UnimplementedError('main.dart must override loggerProvider'),
);
```

**Why the AD-19 duplicate home is deleted rather than bridged.** `grep` over `lib/` shows `AppConfig.sidecarPath` and `AppConfig.interpreterPath` are read by exactly one thing: the JSON codec that persists them. Nothing constructs a provider from them — `ProviderRegistry` reads `ProviderConfig.settings` and always has. So one home is live and the other is dead weight, and bridging would promote a dead field to a load-bearing one. It is also the home AD-15 argues for: `ProviderConfig.settings` is documented as opaque to the domain precisely so transport details stay inside the adapter, whereas `AppConfig.sidecarPath` puts one provider's process layout in a domain type every other provider would inherit meaninglessly. Story 1's Design Notes already chose that home for the timeout for the same reason. The pin is therefore a "no second home exists" test rather than a "the two agree" test — there is nothing left to drift.

**Equality is transitive, so it reaches further than the ledger names.** `AppConfig` cannot compare by value while its `List<Preset>` and `Map<String, ProviderConfig>` compare their elements by identity; the same is true of `CorrectionRecord`'s `List<Suggestion>`, `CorrectionState`'s `CorrectionFailed`, and `SettingsState`'s `HotkeyBindOutcome` → `HotkeyRegistration` → `HotkeyBinding`. `Preset`, `Suggestion`, `CorrectionFailed`, `HotkeyRegistration` and `HotkeyBinding` are all fixed verbatim by AD-2/AD-9. The ledger already settled how to handle that for `HotkeyBinding`: adding `operator==`/`hashCode` is an *addition*, not a change to the declared fields, so do it and record the spine's currency drift. The same reasoning applies unchanged to the others, and the completion notes must say so — AD-2's and AD-9's code blocks now have members the spine does not show.

**Set and map equality, not identity, and hashes that agree.** `HotkeyBinding.modifiers` is a `Set<HotkeyModifier>`, so `{control, shift}` must equal `{shift, control}`; `hashCode` therefore has to be order-independent (`Object.hashAllUnordered`), or two equal bindings land in different hash buckets and every `Set`/`Map` keyed by one silently breaks. Same for the two maps.

**The stubs are honest, not placeholders.** AGENTS.md §8 forbids faking behaviour; it does not forbid an adapter that reports it cannot do its job. `X11GlobalHotkey`/`WaylandPortalGlobalHotkey` resolve `bind()` to `HotkeyUnavailable`, which is precisely AD-12's modelled degradation and is what a wlroots user will see for real — so the tray's unavailable state gets wired and exercised now. They must never report a successful bind. The panel/clipboard/tray placeholders are named `Unimplemented*` rather than taking stories 5 and 6's adapter names, so nothing reads as implemented that is not.

**Shutdown order is the point of the sequence, not a detail.** `AppDatabase.file` uses `NativeDatabase.createInBackground`, whose isolate outlives `main` if it is never closed — a filed ledger entry proves a program that forgets `close()` never exits. So: cancel the lock's show-request subscription (nothing may reach a controller mid-teardown), await the three controller `dispose()`s (`CorrectionController` awaits pending saves for CAP-7), dispose the container, then `hotkey.dispose()`, `database.close()`, `configStore.close()`, `lock.dispose()`. Because the container's `onDispose` hooks also call `dispose()`, the controllers' `dispose()` must be idempotent — pin that with a test rather than assuming it.

**Which consumer proves the equality.** The ledger names Riverpod `select` and `Stream.distinct`. `select`'s payoff is rebuild scoping, which needs the widgets from stories 9 and 10, so the consumers provable *here* are `Stream.distinct()` over each state stream and `SettingsController`'s echo check — the latter being a real behaviour change, since `ConfigStore.changes` never promised instance identity and an adapter that rebuilds the value would silently stop suppressing its own echo.

## Verification

**Commands:**
- `dart analyze` -- expected: no issues (AGENTS.md §6 merge gate).
- `dart format --output=none --set-exit-if-changed lib test` -- expected: 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: all pass, proving every ring except the provider graph still needs no Flutter binding (AGENTS.md §7). Baseline on this story's parent revision: 296 passed, 1 skipped.
- `flutter test` -- expected: the whole suite including `test/composition/`, which needs a binding.
- `flutter build linux --debug` -- expected: succeeds, proving `main.dart`, `window_manager` and the edited GTK runner compile and link together.

**Manual checks (if no CLI):**
- **Launch sanity.** Run the built binary with a bounded `timeout` against this container's reachable X display (`DISPLAY=:10`), then kill it. Expected: the process stays resident for the whole window, its stderr carries the `StderrLogger` startup lines, and a second launch during that window exits 0 immediately (AD-14). Record the observed exit codes and log lines.
- **"No visible window" is not fully provable here.** The container has no `xwininfo`, `xdotool`, `wmctrl` or `xprop`, so nothing can enumerate mapped windows, and there is no compositor of its own. The claim is therefore pinned by `test/architecture/hidden_window_test.dart` (the runner maps no toplevel on first frame; nothing on the startup path calls `windowManager.show()`) plus the launch sanity above. State this limitation explicitly in the completion notes — do not claim a runtime observation that was not made, and do not mark a test as passing for a check that did not run.
- Confirm by inspection that `lib/src/application/composition/` contains no infrastructure import and that `main.dart` is the only file naming a concrete adapter class.

## Auto Run Result

Status: done
Blocking condition: none

### Summary of implemented change

The story's implementation pass (commit `4e9db0b`) stood up the daemon: `main.dart` as the composition root, the Riverpod graph under `lib/src/application/composition/`, `DaemonStartup`/`DaemonGraph`/`DaemonLifecycle` splitting the startup and teardown order into types a test can construct, AD-9 display-server detection with exactly one hotkey adapter, honest stubs behind the hotkey, clipboard, panel-visibility and tray ports, value equality across the domain and application value types, the AD-19 duplicate path home deleted, and the GTK runner's show-on-first-frame handler removed. All four deferred-work items the story was dispatched to close were closed.

This review pass applied 8 patches, all of them to the verification rather than the design, plus two correctness fixes in `main.dart` and `daemon_startup.dart`. The theme: the story's headline deliverable and its AD-8 claim were both pinned by tests that could not fail. Five of the types this story added equality to had zero effective coverage, and the two documented ways past the AD-8 source scan were both live.

### Files changed in this review pass

- `test/support/value_equality.dart` -- **new**; `expectSameValue`, whose `identical` guard is what stops an equality suite degrading into an identity check.
- `test/domain/value_equality_test.dart` -- rewritten to build both sides at runtime with no `const`, with per-call nested values so collection equality actually consults its elements.
- `test/application/state_equality_test.dart` -- same treatment for `CorrectionState`, `SettingsState` and their nested failure and bind-outcome values.
- `test/architecture/hidden_window_test.dart` -- the two AD-8 denylists inverted to allowlists, the GTK bans widened, and an anti-aliasing guard added.
- `test/architecture/composition_wiring_test.dart` -- four new assertions: the `showPanel` join, the hotkey override's *value*, the not-the-daemon `exit(0)`, and the abort guard's extent; the signal-handler check now matches a call rather than a declaration and pins its position.
- `lib/main.dart` -- the abort guard extended over all post-lock startup; `_abort` takes a nullable lifecycle with a direct-release fallback; SIGHUP added to the watched signals.
- `lib/src/infrastructure/system/daemon_startup.dart` -- `begin()` hands the AD-14 address back if any step after `acquire()` throws.
- `lib/src/application/composition/controller_providers.dart` -- `_disposeWith` replaces the three `ref.onDispose(controller.dispose)` registrations, so a rejecting teardown is logged rather than dropped.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- nine new entries, DW-16 through DW-24.

### Review findings breakdown

- **Patches applied: 8** (1 high, 5 medium, 2 low). Every one mutation-verified — the mutation applied, the gate run, the mutation reverted — except the `DaemonStartup.begin` guard, which nothing on today's path can trigger and which is stated as defence in depth rather than claimed as covered.
- **Deferred: 9** (5 medium, 4 low), filed as DW-16…DW-24. The medium ones are worth naming: the active pair is fixed at startup while `changeActivePreset` promises otherwise (DW-16); AD-12's settings half is unwired (DW-17); the tray is never installed while four user-facing strings promise a tray menu (DW-18); show requests arriving before `DaemonLifecycle.start()` are dropped (DW-19); and every exit path is now behind an un-timed teardown future (DW-20).
- **Rejected: 10.** Notably the `concurrency: 1` doubt, which one lens raised and another disproved empirically (setting `concurrency: 0` fails under both runners, so `flutter test` does read `dart_test.yaml`); the ledger delete-versus-mark-done objection, which the story's own dispatch instruction authorised and DW-13 already records; and `UnimplementedPanelVisibility.changes` being broadcast, which an existing ledger entry has story 5 closing in the other direction.

### Verification performed

| Command | Outcome |
|---|---|
| `dart analyze` | no issues |
| `dart format --output=none --set-exit-if-changed lib test` | 104 files, 0 changed |
| `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **419 passed, 2 skipped** (was 412/2 — the 7 new tests are this pass's guards) |
| `flutter test` | **437 passed, 3 skipped** (was 430/3) |
| `flutter build linux --debug` | built |

Mutation evidence for the patches, each applied and then reverted: neutering `Suggestion`/`HotkeyRegistration`/`HotkeyBound`/`HotkeyUnavailable`/`CorrectionFailed` equality went from **0 failures to 9**; `WindowManager.instance.show()` plus `gtk_widget_set_visible(window, TRUE)` from **0 to 3**; unwiring `onShowRequest`, reverting `exit(0)` to `return`, and deleting the `_installSignalHandlers` call each from **0 to 1**; and a no-op control mutation confirmed green, so the new assertions are not simply always-failing.

### Residual risks

- **AD-8's runtime claim is still unobserved** (DW-9). This pass made the static pin considerably harder to walk past — it is now an allowlist on both the GTK and Dart sides — but no window enumerator and no usable display exists in this container, so "launching the daemon leaves no visible window" remains proven by source inspection plus a successful `flutter build linux --debug`, not by observation. It is owed on a machine with a real session.
- **`main()` is still unexecutable by any test.** Six of this pass's assertions are source scans over `lib/main.dart`, the same idiom the implementation pass used. They are stronger than what they replaced, but a source scan pins text, not behaviour; DW-8 holds the general form of this.
- **The `DaemonStartup.begin` release-on-failure guard has no test**, because nothing on the current path throws there (`NativeDatabase.createInBackground` is lazy and `configStore.load()` is contractually non-throwing). It becomes load-bearing as stories 5+ add steps, and should get a test when an injectable failure exists.
- **`followup_review_recommended: true`** — a high-severity patched finding was fixed in this pass. The equality rewrite is broad and the follow-up should sanity-check that no equality row was weakened while being made non-`const`.
