---
title: 'Settings UI'
type: 'feature'
created: '2026-08-11'
status: 'done'
baseline_revision: 'dae6d04937c1a7faf269e17a66a879e017e153d0'
final_revision: '307b79d'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md'
  - '{project-root}/_bmad-output/implementation-artifacts/deferred-work.md'
  - '{project-root}/lib/src/application/settings_controller.dart'
  - '{project-root}/lib/src/application/settings_state.dart'
  - '{project-root}/lib/src/domain/hotkey/global_hotkey.dart'
  - '{project-root}/lib/src/domain/hotkey/hotkey_bind_outcome.dart'
  - '{project-root}/lib/src/ui/panel/correction_panel.dart'
  - '{project-root}/test/ui/panel_harness.dart'
  - '{project-root}/test/architecture/ad1_import_rule_test.dart'
warnings: ['oversized']
---

<intent-contract>

## Intent

**Problem:** `SettingsController` has been live since story 3 and has **no caller**: `changeHotkey` and `changeActivePreset` are reachable from nothing, so CAP-8's in-app half ("switch the active provider and preset from either surface") and CAP-12's settings surface do not exist. Worse for the ADs this story is bound by: the daemon now really binds a hotkey (stories 7 and 8), and the *authority* it comes back with — `application` on X11, `compositor` on Wayland — is rendered nowhere, so the SPEC's Ratified Divergence (in-app settings **authoritative on X11, advisory on Wayland**) is invisible to the user, AD-12's "the settings screen states hotkeys are unavailable" has no screen, and AD-11's `ShortcutsChanged` subscription still terminates in a log line because the `GlobalHotkey` port has no way to push a compositor-side rebind upward.

**Approach:** Build `lib/src/ui/settings/` over the existing `SettingsController` — every mutation is one of its two methods, so AD-13's write-through and AD-5's "the composition root resolves the pair" hold by construction. Three seams below it are added because AD-10 cannot be honoured without them: one **additive member** on the `GlobalHotkey` port carrying backend-initiated changes (the Wayland adapter's `ShortcutsChanged` gets somewhere to go), a `SettingsController` subscription to it, and a hand-off of the startup bind outcome so the screen states the regime from the first frame rather than only after the user edits something. Everything the screen promises is proven headless with `flutter test`.

## Boundaries & Constraints

**Always:**
- **AD-10, the whole of it.** The screen renders the **returned** `HotkeyBindOutcome`, never the requested binding. `authority == application` → the field is the binding, and the screen says in-app settings are authoritative here. `authority == compositor` → the field is presented as a **preference** and the screen says the desktop chooses. `effective == null` → the screen says the backend cannot report the combination in effect; it must **not** fall back to showing the request as if it were effective. A `ShortcutsChanged` reaching the port updates the screen with no user action.
- **The SPEC's Ratified Divergence is the behaviour contract.** The active regime is stated on screen alongside the effective combination. The hotkey must never be presented as app-owned on both display servers.
- **AD-13 / AGENTS.md §8.** Every mutation goes through `SettingsController` → `ConfigStore`. No widget opens the config file, and no widget holds settings that the config file does not.
- **AD-5.** The screen chooses a **preset** (`changeActivePreset`) and never a provider: a preset carries its `providerId`, and the composition root resolves the pair. The screen may *display* which provider and model a preset names.
- **AD-12.** `HotkeyUnavailable` is stated on the screen in the outcome's own words — the second consumer AD-12 names, beside the tray.
- **AD-1.** `lib/src/ui/**` imports `application/`, read-only `domain/` types and Flutter only. `test/architecture/ad1_import_rule_test.dart`'s ui rules — the import rule, the banned-symbol scan and the mechanical port-seam classification — must stay green **unweakened**: `configStoreProvider` and `globalHotkeyProvider` are banned for exactly this story's temptation, and the answer is the controller, not a new sanction.
- **`HotkeyBinding` compares with `==`** (story 4 added it, and `hotkey_binding.dart`'s doc names this consumer). Do not re-add equality, and do not compare bindings field by field.
- Consistency Conventions "State mutation": immutable state, one controller per surface, widgets own only ephemeral UI (a `TextEditingController`, focus nodes, an in-flight flag, which view is showing).
- AGENTS.md §3 and §6: one public type per file, `build()` pure and cheap, named widget classes over `_buildFoo()`, every controller/subscription/focus node disposed, no `!`, no `late` as a lifecycle workaround, **exhaustive switches** over `HotkeyBindOutcome` and `BindingAuthority`.
- The house guard idiom on every new port-touching path: the `_log` swallow, `_errorContext` reducing a caught error to `error_type`, and **no log line carrying user text or a config value**.
- Every test cites the CAP or AD id it defends. The widget tests and the controller tests **run headless and must not be skipped**; only a claim needing a real desktop is skipped, unconditionally, with a `fail()` body and an explicit reason (AGENTS.md §8, and the form stories 5–9 used).

**Block If:**
- Honouring AD-10 turns out to require changing the **declared fields** of `HotkeyRegistration`, `HotkeyBinding` or the cases of `HotkeyBindOutcome`. Those are spine-verbatim (AD-9). Adding a *member* to the `GlobalHotkey` port is in scope and is recorded the way story 4 recorded value equality — in the ledger and the Spec Change Log, never by hand-editing the spine.
- Making the screen reachable turns out to require a `window_manager` call, a second toplevel, a dialog/route that takes focus away from the panel window, or any `PanelVisibility` call from the ui ring (AD-4, AD-8, and `hidden_window_test.dart`'s allowlist).
- A curated list of offerable key labels turns out to be required. The vocabulary lives in `HotkeyKeyCatalogue` (infrastructure, so AD-1 puts it out of reach) and the seven labels that bind on Wayland but are refused on X11 are an **open product decision** already filed. Presenting a per-display-server key list is not this story's to settle.

**Never:**
- No editing of `ProviderConfig`, interpreter/sidecar paths, API keys or prompt text; no adding, renaming or deleting presets or providers (AD-15 keeps transport detail inside its adapter, and the SPEC puts prompt tuning out of scope).
- No tray work: no `TrayPort` widening, no `setHotkeyUnavailable` call from the settings path, no menu entry. The tray's half of AD-12 already ships; the "a settings rebind never reaches the tray" gap stays filed.
- No fix for the filed `SettingsController` concurrency and ordering entries — the mutation-generation race and the bind-before-write divergence. This story makes both **reachable**; it narrows the user-reachable half by disabling the controls while a mutation is in flight and files the rest, rather than re-architecting the controller unattended.
- No change to panel *behaviour*, layout or its measured height floor, and no weakening of story 9's layout, focus, selection or copy assertions. A finder that becomes ambiguous is narrowed to the panel; an assertion is never relaxed.
- No `Escape`-to-hide, no close control for the window, no visibility call anywhere in the ui ring.
- No new package dependency and no pubspec change.
- No analytics, no history view, no diff view (SPEC non-goals), and no "while I was in there".
- Do not edit, close or re-open any existing deferred-work entry. Append only.

## I/O & Edge-Case Matrix

**A — the settings screen, headless `flutter test` over fake ports. NOT skipped.**

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| A1 X11 regime (AD-10, Ratified Divergence) | `bind()` → `HotkeyBound(effective: Ctrl+Shift+G, authority: application)` | the effective combination is rendered as `Ctrl+Shift+G`; the screen states that this app owns the shortcut and settings here are authoritative | No error expected |
| A2 Wayland regime (AD-10, AD-11) | `HotkeyBound(effective: Alt+Space, authority: compositor)` | the field is labelled a **preference**; the screen states the desktop chooses the combination and that what is shown is what is in effect | No error expected |
| A3 the backend cannot report it (AD-10) | `HotkeyBound(effective: null, authority: compositor)` | the screen says the combination in effect cannot be reported by this backend; **the requested binding is not presented as effective anywhere** | No error expected |
| A4 the compositor chose something else (AD-10, story 4's `==`) | config holds `Ctrl+Shift+G`; outcome carries `effective: Meta+F1` | both are shown and distinguished: the preference *and* the combination actually in effect, compared with `==` | No error expected |
| A5 the compositor honoured the request | config and `effective` are equal by `==` (different `Set` iteration order) | one combination is presented as both, with no "differs from your preference" claim | No error expected |
| A6 no backend at all (AD-12) | `HotkeyUnavailable(message: …)` | the screen states global hotkeys are unavailable, in the outcome's own message, and says the tray still opens the panel; the hotkey field stays usable so the user can fix and retry | No error expected |
| A7 nothing attempted yet | `hotkeyBindOutcome == null` | the screen says no binding has been requested yet — never a regime, never an effective combination | No error expected |
| A8 a compositor rebind (AD-10, AD-11) | the port emits a changed outcome while the screen is showing | the rendered combination and regime update with no user action | a malformed emission cannot reach the screen: the port's type is a value |
| A9 the compositor dropped the shortcut (AD-11, AD-12) | the port emits `HotkeyUnavailable` | the screen switches to the unavailable statement | No error expected |
| A10 changing the hotkey (CAP-12, AD-13) | modifiers `{control, shift}`, key `G`, Apply | `changeHotkey(HotkeyBinding({control, shift}, 'G'))` is called exactly once; the store holds the new `hotkeyBinding`; the screen renders the **returned** outcome | No error expected |
| A11 an empty key (AD-13) | key field blank or whitespace, Apply | Apply is disabled and the controller is never called — the store refuses an empty key, and offering the action would be DW-3's silent no-op again | not a failure |
| A12 a write that fails (AD-13) | `ConfigStore.write` rejects | the failure's own sentence is rendered in a live region; the rendered config is still the store's `current`, never the attempted value | the message is the failure's; nothing else is built from it |
| A13 a value the store refuses | `write` throws `ArgumentError` | the `configRejected` sentence renders and nothing was saved | as A12 |
| A14 the backend throws (AD-12) | `bind()` rejects | the screen shows both halves the controller produces — the unavailable statement and the failure sentence — and stays usable | nothing escapes to the zone |
| A15 changing the preset (CAP-8, AD-5) | three presets in config, a second one picked | `changeActivePreset(<that id>)` is called once; config's `activePresetId` is the picked one; each option shows its provider id and model; **no provider is selected by the screen** | No error expected |
| A16 the restart caveat (CAP-8) | a preset switch lands | the screen states that the running daemon keeps serving the previous pair until it restarts — the composition root resolves the pair once (AD-5) | not a failure; a lie would be worse |
| A17 no double submit | Apply pressed twice without awaiting; and a preset picked twice | the controller is called once per user act, and the controls are disabled while a mutation is in flight | a mutation that fails re-enables them |
| A18 an external config edit (AD-13) | `ConfigStore.changes` emits a config written elsewhere | the screen re-renders the new value; a displayed failure is **not** retired by somebody else's write | No error expected |
| A19 the logger is the thing that broke | every path above under `ThrowingLogger` | no unhandled zone error; the screen still renders | the swallow is the one sanctioned silence |
| A20 teardown | the screen unmounted | its subscription is cancelled and its controllers and focus nodes disposed; no state is set after unmount | No error expected |

**B — reachability and the view switch, headless. NOT skipped.**

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| B1 opening settings | the panel showing; the settings affordance activated | the settings screen is showing and the panel is not; no `PanelVisibility` call is made | No error expected |
| B2 going back | settings showing; Back activated | the panel is showing again, with the session's editor text and suggestions intact — they live in `CorrectionController`, not in the widget | No error expected |
| B3 a summon returns to the panel (CAP-1, AD-18) | settings showing; a new session begins (a show) | the panel is showing; a summoned window never presents the settings screen | No error expected |
| B4 the affordance is keyboard reachable and labelled | the panel showing | the affordance has a semantic label naming what it opens | No error expected |
| B5 story 9's panel is untouched | the whole story-9 widget suite | every row passes unweakened, including the layout rows and the height floor | a regression is a defect in this story, not a number to adjust |

**C — the port and the adapters, binding-free `dart test`. NOT skipped.**

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| C1 the Wayland adapter pushes a rebind (AD-11) | bound session; `ShortcutsChanged` still holding `toggle-panel` | one `HotkeyBound(HotkeyRegistration(effective: null, authority: compositor))` is emitted on the new member, and the existing info line is unchanged | a signal for another session emits nothing |
| C2 the Wayland adapter reports a drop (AD-11, AD-12) | `ShortcutsChanged` whose list no longer holds the id | one `HotkeyUnavailable` is emitted, whose message says the desktop no longer holds the shortcut | an unreadable payload emits **nothing** — what the compositor holds is unknown, and claiming either way is the misreport A19c already forbids |
| C3 dispose (AD-4) | a disposed Wayland adapter | the new stream is closed, a later signal emits nothing, and `dispose()` is still idempotent and never throws | never throws |
| C4 the X11 adapter (AD-9) | any X11 adapter | the member is an empty stream that closes: nothing outside this app changes a keybinder grab, and a rebind through `bind()` already answers with its own return value | No error expected |
| C5 the controller subscribes (AD-10) | a port emission of each shape | `SettingsState.hotkeyBindOutcome` follows it and `changes` emits; a displayed `failure` is preserved — an external rebind says nothing about whether the user's mutation landed | a stream error is logged type-only and the subscription survives (the AD-15 backstop the config subscription already has) |
| C6 the startup outcome reaches the surface (AD-12) | the startup bind resolved to `HotkeyUnavailable` before any UI exists | `SettingsState.hotkeyBindOutcome` is that outcome, so the screen states unavailability from its first frame instead of "nothing attempted" | after `dispose()` it is a no-op |
| C7 nothing leaks upward (AD-9) | the whole tree | no portal interface, trigger string, `DBus` type or plugin name appears above `lib/src/infrastructure/hotkey/`; the existing confinement rows stay green | No error expected |

**D — a real desktop.** The screen on a real display; an X11 rebind taking effect without a restart; a real portal dialog; a compositor-side rebind producing `ShortcutsChanged`; the config file on disk changing under a real `ConfigStore`. **Not observable here** — no compositor, no X display, no `xdg-desktop-portal`, no session bus, no keybinder. One unconditionally skipped test with a `fail()` body naming exactly what is owed.

</intent-contract>

## Code Map

- `lib/src/application/settings_controller.dart` -- the surface's owner and the only mutation path. Read `changeHotkey`, `changeActivePreset`, `state`, `changes`; add the port subscription and the startup hand-off beside them, guarded exactly like the existing `_configChanges` (`onError` → `_log` → `_errorContext`).
- `lib/src/application/settings_state.dart` -- what the screen renders. `hotkeyBindOutcome`'s doc already spells out the authoritative/advisory split; no new field is needed. Deliberately has no `copyWith` — build state directly and say what each transition keeps.
- `lib/src/domain/hotkey/global_hotkey.dart` -- the port and `HotkeyRegistration`/`BindingAuthority`. Gains **one** member for backend-initiated changes; fields untouched.
- `lib/src/domain/hotkey/hotkey_bind_outcome.dart` -- `HotkeyBound` / `HotkeyUnavailable`; the sealed pair the new member carries, so a drop and a rebind are one type.
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` -- `_onShortcutsChanged` (~line 811) has all three branches already and logs; it gains the emission. Its class doc's "pushing it upward needs a port surface that does not exist" is the sentence this story retires.
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` -- the other implementation; an empty stream with the reason written down.
- `lib/src/infrastructure/system/daemon_startup.dart` -- `bindHotkey` returns the outcome `main.dart` discards; **read-only** here.
- `lib/src/application/composition/daemon_graph.dart`, `lib/main.dart` -- `graph.build()` runs long before `startup.bindHotkey(tray: tray)`, which is why the outcome needs a hand-off rather than a constructor argument (the ordering DW-17 names).
- `lib/src/ui/daemon_app.dart` -- `home:` is the panel today; it becomes the view switch. Keep the banner suppression and both themes — `test/ui/daemon_app_test.dart` pins them.
- `lib/src/ui/panel/correction_panel.dart` -- read for the ui-ring house style: the `initState` snapshot-then-subscribe, the `onError`/`onDone` arms, the `_report` swallow, and `state == CorrectionState.empty` as the fresh-session signal.
- `lib/src/application/correction_state.dart` -- that signal's one home, once this story needs it in a second widget.
- `test/ui/panel_harness.dart` -- the harness idiom: `ProviderContainer.test`, seams overridden with fakes, `DaemonApp` pumped rather than the widget. It overrides seven seams and leaves `configStore`/`globalHotkey`/`tray` throwing; the settings harness needs the first two.
- `test/fakes/fake_config_store.dart`, `test/fakes/fake_global_hotkey.dart` -- the two fakes the screen needs. `FakeGlobalHotkey.onBind` already scripts every AD-10 shape; it gains an emitter for the new member.
- `test/application/settings_controller_test.dart` -- where C5 and C6 land, binding-free.
- `test/architecture/ad1_import_rule_test.dart` -- the ui gate. `_knownPortSeamCount` is 10 and no seam is added, so the classification row and `_uiSanctionedProviders` (`loggerProvider` only) must both stay as they are.
- `test/architecture/hotkey_confinement_test.dart` -- C7's rows.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- append-only. Read DW-17 and the entries on `effective: null`, `ShortcutsChanged` having nowhere to go, the preset-switch restart gap, the bind-before-write divergence, the mutation-generation race, and the seven divergent key labels: this story is the surface every one of them names, and each is either honoured on screen or re-filed with what changed.

## Tasks & Acceptance

**Execution:**

*The seam AD-10 needs*
- `lib/src/domain/hotkey/global_hotkey.dart` -- add `Stream<HotkeyBindOutcome> get bindingChanges` to the port: emissions the **backend** originates, never an answer to a call this app made (`bind()` already answers those). Document that it is broadcast, that a compositor-side rebind and a compositor-side drop are the two things it carries, and that adding it is a member-level addition to an AD-9-verbatim declaration, recorded rather than hand-edited into the spine.
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` -- emit on `_onShortcutsChanged`: `HotkeyBound(HotkeyRegistration(effective: null, authority: compositor))` when the id is still held, `HotkeyUnavailable` with a message naming the desktop's removal when it is not, and **nothing** when the payload could not be read. Close the controller in `dispose()` and keep it idempotent. `effective` stays null by measurement — the portal returns only a localized `trigger_description` — and nothing parses that string back into a binding.
- `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` -- implement the member as an empty stream, with the reason: an X11 grab is changed only by this app, through `bind()`, whose return value is already the report.

*The controller*
- `lib/src/application/settings_controller.dart` -- subscribe to `bindingChanges` in the constructor (with the same `onError` backstop as `_configChanges`), setting `hotkeyBindOutcome` and **preserving `failure`**; cancel it in `dispose()` beside the config subscription, each guarded independently. Add `void applyStartupOutcome(HotkeyBindOutcome)` for the outcome that resolves before any surface exists — a no-op after `dispose()`, and documented as startup-only.
- `lib/src/application/composition/daemon_graph.dart`, `lib/main.dart` -- pass `startup.bindHotkey`'s result to the settings controller through the graph, so AD-12's settings half is true from the first frame. `main.dart` stays thin: one call, no new decision.

*The screen*
- `lib/src/ui/settings/settings_screen.dart` -- **new** `SettingsScreen`: reads `settingsControllerProvider`, snapshots `state` then subscribes to `changes` (both arms, and the ui-ring `_log` swallow), renders the sections in a scroll view so it survives the small unsized window story 9 documented, and owns the in-flight flag that disables the controls (A17).
- `lib/src/ui/settings/hotkey_preference_field.dart` -- **new**: the editable combination — one toggle per `HotkeyModifier.values` (never a hand-written list) and a key field — labelled *preference* when the authority is the compositor and *shortcut* when it is this app, with Apply disabled while the key trims to empty (A11).
- `lib/src/ui/settings/hotkey_status_view.dart` -- **new**: the AD-10 read-out. An exhaustive switch over `HotkeyBindOutcome` and `BindingAuthority` producing the regime sentence, the effective combination, the "this backend cannot report it" sentence for a null `effective`, the differs-from-your-preference note (compared with `==`), and AD-12's unavailability statement.
- `lib/src/ui/settings/hotkey_binding_label.dart` -- **new**: one home for rendering a `HotkeyBinding` as text, in a fixed modifier order so `{shift, control}` and `{control, shift}` read identically.
- `lib/src/ui/settings/preset_choice_list.dart` -- **new**: one option per `config.presets`, each showing its id, provider id and model, calling `changeActivePreset`, plus CAP-8's restart caveat (A16). Selects a preset, never a provider (AD-5).
- `lib/src/ui/settings/settings_failure_notice.dart` -- **new**: `SettingsFailure.message` in a live region, so the one thing that tells the user their change did not land is not sighted-only — the lesson story 9 paid for twice.
- `lib/src/ui/daemon_home.dart` -- **new** `DaemonHome`: shows the panel or the settings screen, with the settings affordance as an **overlay** rather than a row in the panel — the panel's height floor and every layout row it carries are measured, and chrome above it would move all of them. Returns to the panel when a fresh session begins (B3), subscribing to the controller the panel already exposes.
- `lib/src/application/correction_state.dart` -- add the fresh-session predicate as a named getter and use it in both widgets; two copies of `state == CorrectionState.empty` is one inference with two homes.
- `lib/src/ui/daemon_app.dart` -- `home:` becomes `DaemonHome`; the doc's "the panel is the home" sentence updated. Theme and banner properties untouched.

*Tests*
- `test/fakes/fake_global_hotkey.dart` -- add an emitter for `bindingChanges` (and close it in `dispose()`), so A8, A9 and C5 are drivable; keep `onBind` as the AD-10 script it already is.
- `test/ui/settings_harness.dart` -- **new**; pumps `DaemonApp` over `ProviderContainer.test` with the config store, the hotkey and the panel's seams overridden, exposes the fakes, and offers one helper that opens the settings view — so no test re-derives the pump order the panel harness documents.
- `test/ui/settings/settings_screen_hotkey_test.dart` -- **new**; A1–A6, A8, A9, A10, A11, A14, plus A7.
- `test/ui/settings/settings_screen_config_test.dart` -- **new**; A12, A13, A15, A16, A17, A18, A19, A20.
- `test/ui/daemon_home_test.dart` -- **new**; B1–B4.
- `test/application/settings_controller_test.dart` -- add C5 and C6 rows binding-free, following the file's existing conventions.
- `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart` -- extend the A19 rows with C1, C2 and C3; the unreadable-payload row must assert **no** emission.
- `test/infrastructure/hotkey/x11_global_hotkey_test.dart` -- C4.
- `test/composition/daemon_graph_test.dart` -- the startup hand-off reaching the settings controller, and being harmless when the graph was never built.
- `test/platform/settings_screen_live_test.dart` -- **new**; one unconditionally skipped test with a `fail()` body naming matrix D and what is missing here.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- append, editing nothing: what DW-17 and the two `ShortcutsChanged`/`effective: null` entries now look like after this story (what was closed by construction and what is still owed — a Wayland `effective` is still never a combination); that the mutation-generation race and the bind-before-write divergence are now user-reachable and only narrowed here; whether a settings rebind should reach the tray; the preset-switch restart requirement now that it is stated on screen; the un-curated key field and the seven divergent labels; and anything review turns up.

**Acceptance Criteria:**
- Given the daemon's provider graph with fake ports, when the settings screen is pumped and driven through each `BindingAuthority`, a null `effective`, an unavailable backend, a backend-initiated change, a hotkey change and a preset switch, then every matrix A and B row holds in one headless `flutter test` run with **no skipped widget test**.
- Given a reader of the screen on either display server, when they look at the hotkey section, then it says which regime is active and what is in effect — and on Wayland it never claims the app set the combination, which is the SPEC's Ratified Divergence rendered rather than restated.
- Given `dart analyze`, the binding-free `dart test` command, `flutter test`, `dart format --set-exit-if-changed lib test` and `flutter build linux --debug`, when all five run, then all pass with **no new skips**, no pre-existing test regresses, and the AD-1 ui gate and the hotkey confinement gate are green without their lists being loosened.
- Given the story's completion notes, when it finishes, then they state what the new port member does and does not buy (a Wayland `effective` is still null), how the screen is reached and why the affordance is an overlay, which filed entries this story honoured on screen versus merely narrowed, and what was **not** observed here for want of a desktop.

## Spec Change Log

## Review Triage Log

### 2026-08-11 — Review pass (follow-up 2)

- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 0, medium 1, low 7)
- defer: 2: (high 0, medium 2, low 0)
- reject: 6
- addressed_findings:
  - `[medium]` `[patch]` **The half-body cap put the clipping back one level down, on the notice it was protecting.** The previous pass hoisted the failure notice out of the scroll view so it could not render off-screen, then capped the notice band at half the body so the notices could not eat the controls — both correct, and together they made the band itself scroll with no sign that anything is below the fold. The pending notice was first, so the failure notice was the one past the cap: measured at 420x160, **zero** of its 80px was inside the visible band. That is the retry path specifically — a mutation reissued after a failure carries the failure forward, so both notices are up exactly when the user has been told to try again and the reason has just disappeared. The failure is first in the band now; the pending notice restates what the disabled controls already show. The row asserts the visible intersection rather than containment, because at 420x160 the band is 52px and the notice is 80px: it genuinely does not fit and scrolls inside its own band, which is the cap working. Gate: 1.
  - `[low]` `[patch]` The offered-key architecture scan guarded one of the two ways this screen can name a bad key. It asked "is one of DW-43's seven named here?" and never "is the named label registerable at all?" — but `X11GlobalHotkey._bind` refuses on `usbHidUsageFor(label) == null` **first**, and `XdgShortcutTrigger.labels` is held equal to the catalogue's, so a suggestion like `PrintScreen` or `F13` is refused on both display servers and produces the same `HotkeyUnavailable` the seven do. Mutation-confirmed: swapping the helper text to offer `PrintScreen` left the architecture suite and `flutter test` green. Absence is checkable in prose; membership is not, so the offers are now a named `offeredKeyExamples` list the row reads and resolves against the catalogue. The shipped examples were correct by luck of what is in `_namedKeys`, not because anything checked. Gate: 1.
  - `[low]` `[patch]` That same scan could stop looking, silently, for the second time. `_stripComments` ran before `_stringLiterals` and did not respect literals, so a `//` or `/*` *inside* a string deleted to the end of the line — `'see https://x for labels, e.g. Space'` strips to `'see https:` and the offer after it went unscanned. This is the escaped-quote failure from the other direction, and the previous pass's fix did not generalise because the two-pass shape was the cause. One pass now, tracking which construct it is inside, with interpolations stepped over by brace depth and triple-quoted strings consumed whole; three self-test cases added. Gate: 1.
  - `[low]` `[patch]` **`DaemonHome`'s two subscription cancels were pinned by nothing** — mutation-confirmed independently for each: deleting either left all 859 rows green. The AD-4 teardown row unmounted with the *panel* showing, where `_returnToPanel`'s `if (!_showingSettings) return;` swallows both signals, so no `setState` was reachable on either path. This is the same blind spot the previous pass fixed for the `isFreshSession` guard — a row naming a property while standing where the property cannot bite — left in place on the teardown row beside it. The row opens settings first and drives each signal separately. Gates: 2 (one per cancel).
  - `[low]` `[patch]` The AD-12 wiring gate the previous pass rewrote had false positives in the direction that gets a gate deleted: keying the local's declaration on `(?:final|var)\s+(?:\w+\s+)?` accepted only an untyped local or a single bare word of type, so `final HotkeyBindOutcome? outcome = …` (the `?` is not `\w`), `late final …` and a qualified type all read as "no hand-off" and would have failed a correct `main.dart` — on the line pinning AD-12's whole settings half. The matcher keys on the assignment target now, and is extracted so it can be self-tested: six correct spellings must pass, three disconnected ones must fail. Gate: 1.
  - `[low]` `[patch]` The unavailable read-out's second sentence narrated the implementation to the user: "This report does not say which of this app and your desktop would own the shortcut, so neither is claimed here" — on the one screen somebody reaches because their hotkey stopped working. Reworded to describe their system. The property it exists for (no regime claimed, stated rather than silent) and its row are unchanged.
  - `[low]` `[patch]` `_NoModifierCaution` was the only widget this story added without a const constructor, so it reallocated on every keystroke — the field calls `setState` on every `onChanged`. AGENTS.md §3/§6 house style, cited throughout this story for exactly this class of rule.
  - `[low]` `[patch]` `original_text_pane.dart` justified the panel owning focus with "this tree is never rebuilt (AD-8)", a premise this story made false: returning from settings unmounts and remounts the pane. The behaviour is unchanged and correct — `autofocus` fires on each mount — but the stated reason was stale, and a reader would have trusted it.
  - `[medium]` `[defer]` DW-84: an X11 hotkey refused *before* the backend is still written to config. The refusal is permanent for this build, and the honest half hides it — the old grab survives, so the screen shows a working hotkey beside the new preference and the next launch has no hotkey at all. The bind-before-write ordering is what DW-68 already owes and what this story's Never list ruled out re-architecting.
  - `[medium]` `[defer]` DW-85: a mutation resolving after the screen is unmounted reports its failure to nobody. Apply, get summoned away by your own hotkey (the path this story built), write fails — nothing is said until the user happens to reopen settings. Every candidate fix is a product decision or crosses a Never (the tray).
  - **Rejected 6**, three of them refuted against the code rather than judged. A reviewer reported that a refused rebind erases a still-live hotkey from the screen: `_refusedBeforeBackend` returns `HotkeyBound(effective: <still-live binding>)` whenever a combination is held and `HotkeyUnavailable` only when none is, so the regime and the effective combination are both preserved. A second reported that `applyStartupOutcome`'s seed rule keeps the older fact, because `ShortcutsChanged` is subscribed inside `bind()`: the subscription is established on the success path one synchronous line before the return, so at startup a failed bind has no subscription to emit through and a successful one carries the identical value — the seed keeps the newer fact, as documented. A third reported `_showRequests.close()` as an unguarded teardown that could strand shutdown; a broadcast `StreamController`'s `close()` does not surface subscriber errors on `done`, so it cannot reject. The remaining three: three unranked live regions (no demonstrated failure, unobservable without a screen reader, and the "fix" is an ordering claim nothing can verify here); `_beginMutation`'s disposed arm not logging (a mutation issued during shutdown is a non-event the file documents); and an unbounded-constraint guard on `noticeCeiling` (the screen has one call site, inside a `Scaffold` body).

### 2026-08-11 — Review pass (follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 14: (high 0, medium 5, low 9)
- defer: 2: (high 0, medium 1, low 1)
- reject: 5
- addressed_findings:
  - `[medium]` `[patch]` **The unavailable read-out asserted two things that are false on the very paths this story made reachable.** `_unavailableLines` wrapped every `HotkeyUnavailable` in "Global shortcuts are unavailable on this desktop." and "No backend answered…", but that state has four origins and only one is a desktop with no portal. Checked against the shipped messages: an X11 backend refusing one key label answers `the key "Tab" is not one this build can register…` — a working backend that answered — and the compositor drop this story newly delivers answers `your desktop no longer holds this shortcut…` from a working portal. So on a GNOME session where the user removed the shortcut, the screen blamed the whole desktop and denied that anything had answered, twice over. Both invented sentences are gone; the adapter's message is rendered alone beside one sentence that claims only what the outcome carries. The neutrality the previous pass added is kept — no regime is claimed — and the rows that pinned the false text now assert its absence with the reason. Gate: 2.
  - `[medium]` `[patch]` **Apply would grab a bare key system-wide with no warning.** Probe-confirmed: deselecting all four modifier chips left Apply enabled and issued the bind. A bare printable key is captured everywhere once bound and stops reaching every other app — including this screen's own key field, which is what makes it awkward to undo where it was caused. Not refused, because a bare `F12` is a legitimate combination and separating the two needs `HotkeyKeyCatalogue`, which AD-1 puts out of the ui ring's reach and whose curation this story's Block If explicitly does not settle. The cost is now stated before Apply, in its own semantics node, and withdrawn the moment a modifier is back. Gate: 1.
  - `[medium]` `[patch]` **Both notices up on a short window took the entire body.** Probe-confirmed at 420x160: the `Expanded` holding the status view, the hotkey field and the preset list resolved to **zero** height — every control unreachable — plus a 28px `RenderFlex` overflow, and 58px at 90. Hoisting the notices out of the scroll view (the previous pass's fix, and correct) had made them fixed-height siblings of the only flexible child, and nothing sizes this toplevel. The band is now capped at half the body and scrolls inside itself, so the notices stay visible and the controls always keep the other half. Gate: 1.
  - `[medium]` `[patch]` **The AD-12 wiring gate could not see the wiring.** It asserted that `graph.applyStartupBindOutcome(` appears and that `startup.bindHotkey(` appears once — two facts that say nothing about the value passing between them. Confirmed: rewriting the hand-off to pass a literal `HotkeyUnavailable` and await the bind separately satisfied both, kept `dart analyze` clean and the suite green, and would have shipped a settings screen stating a fabricated sentence for the daemon's life while the tray reported the truth. It now asserts the argument, accepting the composed call however `dart format` wraps it *and* the two-statement form that names a local — the false positive the previous pass was avoiding is checked for too, and does not occur. Gates: 1 (disconnected spelling fails), 0 by design (correct two-statement spelling passes).
  - `[medium]` `[patch]` **`DaemonHome`'s fresh-session guard was pinned by nothing.** Mutation-confirmed independently: deleting `if (!state.isFreshSession) return;` left the whole suite green. The row that names the property drives a session update with the *panel* already showing, where the guarded call is a no-op either way. Without the guard any streaming delta, completion or copy failure tears the settings screen down mid-edit. A row now opens settings and then emits a non-fresh update. Gate: 1.
  - `[low]` `[patch]` `SettingsState.mutationInFlight` was an optional parameter defaulting to `false`, so two mutations released the slot by *omitting* it — the exact trap the neighbouring `failure` doc says must not be re-armed. Now required, with both unlocks stated at their call sites; behaviour and emission counts unchanged deliberately.
  - `[low]` `[patch]` `_currentConfig`'s silence rested on reasoning that does not hold. It argued every caller had already been through `_writeChange`, but that reads `current` once, at the start — a store that starts throwing *after* the write lands reaches the render read having reported nothing, and the user is shown their pre-write value with no failure and no log line. Logged type-only, with a row driving exactly that ordering through a new `onWriteComplete` seam on the fake. Gates: the existing row's line count, and 1 new.
  - `[low]` `[patch]` A store whose `current` breaks was reported to the user as an unwritable config file, sending them to `chmod` something that is fine — the same wrong-cause misdirection the `configRejected` branch exists to avoid. Reworded to name what actually failed.
  - `[low]` `[patch]` `SettingsController.initialBindOutcome` was reachable from nothing in `lib/`, exercised by one test, and contradicted `applyStartupOutcome`'s own doc ("a constructor argument therefore cannot carry it"). Worse, it was a second seeding path with the opposite precedence rule — assignment against seed — so any future use of it would have turned every real hand-off into a refused no-op. Deleted; the row rewritten through `applyStartupOutcome`, which is now the only seam.
  - `[low]` `[patch]` The failure notice was the only live region on the screen without `container: true`, on the one sentence that reports a change the user asked for and did not get. Added — and its gate **fails zero rows**, measured, so it says so in code rather than looking guarded, exactly as `HotkeyStatusView` does for the same property. The flag and the label landing on one node *is* now pinned, by a new row targeting the notice's own semantics node.
  - `[low]` `[patch]` The offered-key architecture scan — the only automated guard against the screen recommending a label X11 refuses — was defeated by a single escaped apostrophe: with no `\.` alternative the first literal ended early and the unpaired quote desynchronised every literal after it, so the scan passed by having stopped looking. Fixed, with an escaped-quote case added to the checker's self-tests. Gate: 1.
  - `[low]` `[patch]` `_endMutation`'s doc named an invariant a dispose-mid-mutation violates: `_setState` refuses after `dispose()`, so neither the terminal state nor the fallback lands and `mutationInFlight` stays true. Unreachable today (shutdown unmaps the window and nothing reads `state` after), so the doc now states the exception rather than the code growing a second writer beside the one place that decides transitions.
  - `[low]` `[patch]` `HotkeyPreferenceField`'s `didUpdateWidget` re-seed guard was pinned by nothing — the only row reaching it drives the branch *past* it. Without the guard, any rebuild that leaves the stored binding alone (a `bindingChanges` emission, a mutation going in flight, an external write to a different setting) snaps a half-typed combination back. A row now types a draft, drives an unrelated config write, and asserts the draft survives — with the control that a real binding change is still followed. Gate: 1.
  - `[low]` `[patch]` DW-83 appended: `PanelController.showRequests` is a public application-ring member the previous pass added and recorded only in this log, so a reader auditing this story's seams against its three-seam Approach would count five and find no ledger entry for two of them. Nothing is owed technically — it is pinned by four rows — and the entry is the missing record.
  - `[medium]` `[defer]` DW-81: the hotkey pressed while settings is showing takes the AD-8 hide arm, so the window vanishes and the panel needs a second press. Consistent with CAP-14's toggle contract and nothing is lost, but it is the most likely way out of settings for a hotkey-summoned surface, and both reviewers who raised it rated the intent genuinely ambiguous — a product call, not one to make unattended.
  - `[low]` `[defer]` DW-82: A6's "the tray menu still opens the panel" clause now depends entirely on every adapter remembering to end its sentence with it. Every shipped message does, measured, and the widget's doc states the cost — but the A6 row proves it only for the fixture it hard-codes.
  - **Rejected 5**, three of them measured rather than assumed. Two reviewers reported that a `bindingChanges` emission arriving mid-mutation is clobbered by `changeHotkey`'s terminal write: real, but the bind's answer resolves *after* the emission and so is the newer fact, and `changeActivePreset` already carries state forward — the ordering DW-76 leaves open is the interleaving, not this. The settings affordance was reported as a ~40x40 target occluding the panel's full-width editor: **it does not reproduce** — measured 34x32 with a 25x4px overlap at the field's top edge, and the class doc already states the cost honestly. A guard disabling Apply on an unchanged binding would break A6's "the hotkey field stays usable so the user can fix and retry", which the X11 adapter documents as its recovery path. The remaining two (the tray/settings divergence, and the `_ownWrites` multiplicity) are already DW-79 and DW-77.

### 2026-08-11 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 20: (high 0, medium 7, low 13)
- defer: 2: (high 0, medium 1, low 1)
- reject: 0
- addressed_findings:
  - `[medium]` `[patch]` **The in-flight gate was on the widget, and this story's own two exits from the screen destroyed it.** Probe-confirmed: Apply → Back → affordance → Apply produced `bindCalls=2, writes=2` with the first bind still parked on the portal dialog, and a summon reached the same place — so the story's claim, and DW-68's stated narrowing, were both false, and the last-completion-wins race was user-causable from this screen in three taps. The state moved to `SettingsController` (`mutationInFlight`, refused rather than queued, logged without a config value) with the screen keeping only the affordance; rows added for Back→reopen and summon→reopen, a controller-level refusal row and a frames row. Four gates bite (3/3/2/1). DW-76 appended recording that DW-68 overstated the narrowing and what is now closed versus still open — a config file edited on disk, or a second surface, can still interleave. DW-68 itself untouched.
  - `[medium]` `[patch]` **A show of an already-visible window never came back to the panel**, because `PanelVisibility.changes` emits only on a transition and the return path was keyed on a fresh session. Probe-confirmed: with settings up, `showPanel()` left `panel=0 settings=1 visible=true` — so AD-14's second launch and AD-12's tray "open the panel" raised a window still showing settings, while `HotkeyStatusView` was printing "the tray menu still opens the panel" on that very screen. `PanelController` gained a broadcast `showRequests`, emitted where the show is already fired so nothing on CAP-1's path awaits, and `DaemonHome` returns on it or on a fresh session through one idempotent path. The reason this survived is closed too: the harness now builds all three controllers as `DaemonGraph.build()` does, and B3 is driven through `hotkey.press()` rather than the visibility fake. Three gates bite (1/4/4).
  - `[medium]` `[patch]` **One screen spelled the same four modifiers two ways**, including the spelling its own code calls wrong: the chips rendered raw enum names (`control`, `meta`) while the read-out two lines above rendered `Ctrl`, `Super` — and `hotkey_binding_label.dart`'s doc argues that "the Super key is labelled `Meta` on no Linux keyboard anyone ships". `hotkeyModifierLabel` is exported and used by both; the rows that pinned the lowercase forms were pinning the defect and now assert the real labels, with a new row driving every modifier through chip *and* read-out. Two gates bite (5/3).
  - `[medium]` `[patch]` **Nothing on screen said a mutation was in flight.** Probe-confirmed: while a bind sits on a portal dialog — seconds, by AD-11's design — every control was disabled and the status block still read "No shortcut has been requested yet", which is the same defect story 9 patched for the panel when running looked like idle. A real pending affordance now renders from the controller's flag, announced rather than sighted-only, and gone at the terminal event. Gate: 1.
  - `[medium]` `[patch]` **AD-10's status read-out was announced by a flag no test observed.** Deleting `liveRegion: true` failed zero of 106 ui rows, on the one sentence that changes with no user action. Now pinned by a row asserting the flag and a non-empty label in both multi-line states. One reviewer claim did **not** reproduce and is recorded as measured rather than repeated: the annotation merges into an ancestor that carries all three sentences, so `isLiveRegion` was already true in every state. `container: true` was added so the property belongs to this widget rather than to its neighbours, and its own gate fails zero rows — said so in the code instead of leaving it looking guarded.
  - `[medium]` `[patch]` **The key field recommended a key the app then refuses.** The helper text offered `Space`, which `HotkeyKeyCatalogue.labelsThatBindTheWrongKey` records as binding the wrong key on X11 — the display server where this screen is *authoritative*, so following the screen's own suggestion returns `HotkeyUnavailable`. Examples changed to labels both display servers accept, plus an architecture row that scans string literals under `lib/src/ui/settings/` against that list (derived from the catalogue, with checker self-tests), because AD-1 keeps the ui ring from reading it directly. Gate: 1.
  - `[medium]` `[patch]` **The unavailable state read as app-owned.** With no authority to report, the field fell back to the same "Shortcut to request" label the never-attempted state uses and no regime sentence printed — so on a wlroots session, AD-12's headline case, the screen never said in-app settings are advisory there and its label implied the app owns the shortcut, which is the one thing the SPEC's Ratified Divergence forbids. The screen cannot name the display server (that signal is infrastructure, AD-1) and none was invented: the state is now neutral about ownership and says plainly that no backend answered, so which regime applies is not known here. Gate: 1.
  - `[low]` `[patch]` The unavailable branch appended "The tray menu still opens the panel." after adapter messages that all already end with that clause, so it rendered twice. Removed; A6 now drives the verbatim adapter message and asserts the clause appears once. Gate: 1.
  - `[low]` `[patch]` `applyStartupOutcome` overwrote unconditionally, while the Wayland adapter subscribes to `ShortcutsChanged` *inside* `bind()` — so a compositor-originated outcome landing before the hand-off lost to the older startup value with no later event to correct it. It is a seed now, applied only while nothing is known, and it logs when it declines. Gate: 1.
  - `[low]` `[patch]` `_mutate` had no `finally` while its comment claimed nothing could leave the screen stuck, and `changeHotkey` read `ConfigStore.current` outside every guard — one adapter breach would have disabled every control for good plus an unhandled zone error. The write now refuses rather than deriving from stale state, the render read is guarded, and the body has its `finally`. Gate: 2, with the `finally`'s own arm declared unpinned in code.
  - `[low]` `[patch]` `DaemonGraph` dropped the startup outcome silently when `build()` never ran, in a codebase that logs every other swallow. Logged, type-only. Gate: 1.
  - `[low]` `[patch]` The AD-12 hand-off was pinned by one formatting-sensitive source substring. Rewritten as two formatting-independent facts — the hand-off exists, and there is exactly one `bindHotkey` call — after the `indexOf` ordering form was found to reject an equally correct two-statement spelling. Gates: 1 and 1.
  - `[low]` `[patch]` `hotkey_status_view.dart` rendered two contradictory sentences for `HotkeyBound(effective: null, authority: application)` — no shipped adapter produces it, but the widget accepts any outcome. Regime and combination are now chosen together. Gate: 1.
  - `[low]` `[patch]` Tapping the already-active preset issued a full mutation and a config write, so a failed write reported "your settings could not be saved" for a change nobody made. Guarded, with a control row proving a non-active preset stays retryable after a failure. Gate: 1.
  - `[low]` `[patch]` The failure notice sat inside the scroll view, so on a window short enough to scroll (nothing sizes the toplevel) the only report that a change did not land rendered off screen. Hoisted out; a row scrolls to the bottom and then fails a write. Gate: 1. Fixing it also surfaced a silently missed tap the new position introduced, now `ensureVisible`d.
  - `[low]` `[patch]` The tab-traversal bound was a magic `12` coupled to the panel's focusable count, with a message that named nothing. Derived (it stops when focus cycles) and the failure now lists the trail.
  - `[low]` `[patch]` The A19 row rebuilt the harness inside the test body, so teardown disposed only the second and the first `FakeConfigStore`'s controller leaked. One live harness per row, disposed before it is swapped.
  - `[low]` `[patch]` The two A18 rows were titled as though they covered a config file edited on disk, which nothing watches in production. Renamed to name the `ConfigStore.changes` fan-out they actually pin.
  - `[low]` `[patch]` An unapplied hotkey draft is discarded by every view swap — probe-confirmed. The behaviour is kept, because AD-18 makes every show start fresh, but the class doc justified the swap with "the panel's content survives because it lives in the controller" and was silent about the asymmetry. Stated, and DW-78 filed for whoever decides the field should keep its draft.
  - `[low]` `[patch]` DW-77 appended: refusing overlapping mutations makes the counted-echo multiplicity in `SettingsController._ownWrites` unreachable from outside the class. Kept rather than simplified — a queueing decision would make it load-bearing again — and the row that drove it was rewritten to the sequential property rather than left asserting a scenario that can no longer occur.

## Design Notes

**Why the port gains a member, and why that is not a spine edit.** AD-10 says "subscribe to `ShortcutsChanged` so a rebind made in the compositor updates the UI". `GlobalHotkey` exposes `activations`, `bind` and `dispose`; `bind`'s answer only ever describes a call this app made, so there is *no* path from the compositor to the surface, and the Wayland adapter's handler has said so in a comment since story 8. Story 8's Never list ruled the edit out and filed it for "the settings-screen story", which is this one. It is typed `Stream<HotkeyBindOutcome>` rather than `Stream<HotkeyRegistration>` because the signal carries two different facts — the desktop rebound the shortcut, and the desktop no longer holds it — and the sealed pair already models exactly that, so AD-12's degradation reaches the screen through the same value the initial bind uses. Fields stay verbatim; a member is the same class of addition story 4 made when it gave these types value equality, recorded in the ledger and the Spec Change Log rather than by editing `ARCHITECTURE-SPINE.md`.

**A null `effective` is a sentence, not a fallback.** On Wayland the portal returns a localized `trigger_description` and no machine-readable trigger, so `effective` is null on every real bind — measured in story 8, not omitted. The screen therefore says the backend cannot report the combination in effect. It must not print the request there instead: that is precisely the "settings UI claiming it set a hotkey the compositor actually chose" AD-10 exists to prevent, and it is why this story does not parse the description either.

**Why the effective/preference comparison is the screen's job.** Two filed entries — the X11 rebind whose release was refused, and its Wayland twin — describe an outcome that is accurate field by field and silent about the user's request: `HotkeyBound` carrying the *previous* combination. Both were filed with the same note, that the fix is "a controller-side comparison … decisions for the surface that renders them". The surface exists now, so it renders both values and says when they differ, using `HotkeyBinding`'s `==` (which is set-based, so modifier order cannot fake a difference). Nothing about the outcome type changes.

**Why the settings affordance is an overlay and the view is a swap.** Story 9's panel carries a measured height floor and six layout rows; a toolbar or an extra button row above or inside it moves every rect those rows assert and would put a maintainer in the position of "adjusting" a constant that was measured against CAP-10. An overlaid affordance in the panel's empty top-right corner changes no constraint. The two views swap rather than stack, because everything the panel holds lives in `CorrectionController` — unmounting it costs nothing, and remounting is also what brings the caret back to the editor.

**Why a fresh session returns to the panel.** CAP-1 promises that the hotkey summons the *correction panel*; a window that comes up showing settings breaks it. `_beginSession` emits `CorrectionState.empty` synchronously on every show and nothing else builds that value, which is the same signal the panel already uses to bring focus back — so it becomes a named getter used by both, rather than the same inference written twice.

**Why the key is a field and not a menu.** The list of key labels this app can bind lives in `HotkeyKeyCatalogue`, in infrastructure, which AD-1 puts out of the ui ring's reach; copying it into a widget would give one vocabulary two homes. Seven of those labels also bind the wrong key on X11 while working on Wayland — filed, and explicitly named a product decision this story's intent does not carry. So the field takes the label, the store validates that it is non-empty, and the *adapter's* answer is what the screen reports: an unbindable label comes back `HotkeyUnavailable` on X11 and as a dropped preference on Wayland, both of which A6 and A2 already render honestly.

**What disabling the controls does and does not fix.** The filed mutation-generation race is real and this story makes it reachable: `bind()` can sit on a portal dialog for seconds. Disabling Apply and the preset list while a mutation is in flight removes the case a user can actually cause. It does **not** close the entry — a config file edited on disk, or a second surface, can still interleave — and the completion notes must say so rather than implying the race is gone.

## Verification

**Commands:**
- `dart analyze` -- expected: no issues (AGENTS.md §6 merge gate).
- `dart format --output=none --set-exit-if-changed lib test` -- expected: 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: all pass, **no new skips**. Baseline measured on this story's parent revision (`dae6d04`): **660 passed / 2 skipped**. This is also the AD-1 gate: it fails to resolve if the application or domain ring gains a Flutter import.
- `flutter test` -- expected: all pass. Baseline: **775 passed / 8 skipped**. Every new `test/ui/` row must **pass**; only `test/platform/settings_screen_live_test.dart` may skip.
- `flutter build linux --debug` -- expected: builds.
- `grep -rn "infrastructure" lib/src/ui/` -- expected: no import matches (AD-1's ui row).

**Mutation gates** — apply each alone against a green tree, run the suite, record how many rows fail, revert. **A gate that fails zero rows means the property is unpinned and the test is what needs fixing.**
1. Render `config.hotkeyBinding` instead of the outcome's `effective` -- A1, A3 and A4 must fail.
2. Print the requested binding when `effective` is null -- A3 must fail.
3. Report `authority: application` unconditionally -- A2 and the Ratified Divergence row must fail.
4. Make the Wayland `ShortcutsChanged` handler emit on the unreadable-payload branch too -- C2 must fail.
5. Emit `HotkeyBound` instead of `HotkeyUnavailable` when the id is no longer held -- C2 and A9 must fail.
6. Drop the `bindingChanges` subscription from `SettingsController` -- A8, A9 and C5 must fail.
7. Have that subscription clear `failure` -- C5's preservation row must fail.
8. Drop `applyStartupOutcome`'s call site -- C6 must fail.
9. Enable Apply on a whitespace-only key -- A11 must fail.
10. Have the screen keep rendering the attempted config after a refused write -- A12 must fail.
11. Have `changeActivePreset` be called with a provider id instead of a preset id -- A15 must fail.
12. Leave the settings view showing when a fresh session begins -- B3 must fail.
13. Leave the controls enabled while a mutation is in flight -- A17 must fail.

**Manual checks (if no CLI):**
- **Not observable here, and must be reported as such.** This container has no compositor, no X display, no `xdg-desktop-portal` and no session bus, so nothing about this screen *on a desktop* is observed: not that it renders legibly at the window's real size, not that an X11 rebind takes effect without a restart, not that a real portal dialog appears, not that a compositor-side rebind produces `ShortcutsChanged`, and not that the config file on disk changes under a real `ConfigStore`. A headless widget test is a test of a widget tree, not a runtime observation of a desktop, and may not be reported as one.
- Confirm by inspection that no file under `lib/src/ui/` names an adapter, a plugin, a `MethodChannel`, `ConfigStore` or `GlobalHotkey`, and that no log line added here carries a caught error's `toString()`, a config value or the user's key choice.



## Auto Run Result

Status: done
Blocking condition: none

### Summary of implemented change

A second follow-up review pass over the same diff (`dae6d04..HEAD` plus the working tree), run because the previous pass set `followup_review_recommended: true`. No code was re-derived: **0 intent gaps, 0 spec defects**, so the `<intent-contract>` is untouched and nothing was reverted. Four layers ran in parallel with no prior conversation context — adversarial, edge-case, verification-gap and intent-alignment. 8 findings patched, 2 deferred, 6 rejected.

One patch changes what a user sees, and it is a defect the previous pass created while fixing its predecessor. Hoisting the failure notice out of the scroll view was right; capping the notice band at half the body so the notices could not eat the controls was also right; together they made the band itself scroll with nothing to indicate anything is below the fold, and the pending notice was in front. Measured at 420x160: **zero** of the failure notice's 80px was inside the visible band. That is the retry path specifically — a reissued mutation carries the failure forward — so both notices are up exactly when the user has been told to try again and the reason has just vanished. The failure takes the top of the band now.

Three more closed holes in the verification rather than the code, all mutation-confirmed before being believed. `DaemonHome`'s two subscription cancels were pinned by nothing: deleting either left all 859 rows green, because the teardown row unmounted with the panel showing, where the guarded call is a no-op either way — the same blind spot the previous pass fixed one row over and left here. The offered-key architecture scan guarded one of the two ways this screen can name a bad key, so offering `PrintScreen` — refused by both display servers — passed it green. And that scan could stop looking silently for a second time, because comments were stripped in a first pass that did not respect string literals.

Three reviewer findings were **refuted against the code rather than judged**: a refused rebind does not erase a still-live hotkey (`_refusedBeforeBackend` returns the still-live binding), `applyStartupOutcome`'s seed rule does keep the newer fact (the `ShortcutsChanged` subscription is established on the success path, one synchronous line before `bind()` returns), and a broadcast controller's `close()` cannot reject.

### Files changed

**Production**
- `lib/src/ui/settings/settings_screen.dart` — the failure notice takes the top of the capped notice band.
- `lib/src/ui/settings/hotkey_preference_field.dart` — `offeredKeyExamples` named so a gate can resolve it against the catalogue; `_NoModifierCaution` given its const constructor.
- `lib/src/ui/settings/hotkey_status_view.dart` — the unavailable read-out's second sentence describes the user's system rather than the report.
- `lib/src/ui/panel/original_text_pane.dart` — the focus doc's premise corrected; this story made the pane remountable.

**Tests**
- `test/architecture/hotkey_confinement_test.dart` — single-pass literal scanner (comments, interpolations, triple quotes) with three new self-tests, plus the positive half of the offered-key gate.
- `test/architecture/composition_wiring_test.dart` — the AD-12 hand-off matcher extracted and keyed on the assignment target, with nine self-test spellings.
- `test/ui/daemon_home_test.dart` — the AD-4 teardown row opens settings first and drives each signal separately.
- `test/ui/settings/settings_screen_config_test.dart` — the failure notice's visibility inside the band with both notices up.
- `test/ui/settings/settings_screen_hotkey_test.dart` — the reworded sentence.
- `_bmad-output/implementation-artifacts/deferred-work.md` — DW-84 and DW-85 appended; **16 additions, 0 deletions**, no existing entry edited, re-opened or closed.

### Review findings breakdown

**Patched 8** (high 0, medium 1, low 7). Five carry a mutation gate and each was run and bit: the notice order (1 row), the unregisterable offered key (1), the two-pass literal scan (1), each `DaemonHome` cancel (1 each, run separately), and the syntax-keyed wiring matcher (1). The remaining three are a reworded sentence, a const constructor and a corrected doc premise, none of which asserts a property a gate could measure.

**Deferred 2.** (medium) DW-84, an X11 hotkey refused before the backend is still written to config, so a session that keeps working hides a next launch with none. (medium) DW-85, a mutation resolving after the screen is unmounted reports its failure to nobody — on the summon path this story built.

**Rejected 6**, three refuted by reading the code as described above; the other three are an unverifiable live-region ordering claim, a shutdown-path log line, and an unbounded-constraint guard for a screen with one bounded call site.

**Follow-up review recommended: true.** Counting only this pass's `patch` findings: high 0, medium 1, low 7 — score `3x1 + 1x7 = 10`, at or above the threshold of 5. The honest read of that number is that it is falling (24 last pass, 10 now) and that its composition changed: one user-visible defect this time rather than three, and it was a defect the previous pass introduced while fixing its own predecessor, which is the signal worth acting on. The notice band has now been edited by three consecutive passes.

### Verification performed

All five commands from `## Verification`, plus the AD-1 grep:
- `dart analyze` — no issues.
- `dart format --output=none --set-exit-if-changed lib test` — 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` — **690 passed / 2 skipped** (spec baseline 660/2; 688/2 entering this pass; +2 rows, no new skips).
- `flutter test` — **862 passed / 9 skipped** (859/9 entering this pass; +3 rows, no new skips, every new `test/ui/` row passes).
- `flutter build linux --debug` — builds.
- `grep -rn "infrastructure" lib/src/ui/` — no matches.

### Residual risks

**Nothing about this screen on a desktop was observed, and none of the above may be read as if it were.** This container has no compositor, no X display, no `xdg-desktop-portal` and no session bus. The notice-band fix in particular is measured against a widget tree at a chosen surface size, not a toplevel a user dragged — DW-50 still records that nobody has looked at this window at its real size, and this is the third consecutive pass to change that band's layout on the strength of a probe. The two new entries are both real user-facing gaps left open by design: DW-84 means an X11 user can store a hotkey that works this session and not the next, and DW-85 means a failed mutation on the summon path is reported nowhere. The offered-key gate now covers both refusal shapes, but only for labels the widget *names*; the field itself stays un-curated, which is DW-71.
