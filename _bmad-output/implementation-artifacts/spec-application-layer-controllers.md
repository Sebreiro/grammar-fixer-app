---
title: 'Application layer: panel, correction, and settings controllers'
type: 'feature'
created: '2026-08-06'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'a0cf53c'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The domain ring and its fakes exist, but nothing orchestrates them: no toggle behind the hotkey (CAP-1/CAP-14), no run/stream/retry/persist pipeline (CAP-2/3/5/7/13), no settings write-through (CAP-8/CAP-12).

**Approach:** Three plain-Dart controllers in `lib/src/application/`, ports injected via constructor (AD-17-compatible; Riverpod exposure lands with the composition slice), behaviour-tested against the existing fakes. Spine AD numbering is used throughout (the requesting prompt's "AD-13 sole saver" / "AD-14 write-through" are the spine's AD-7 rule / AD-13).

## Boundaries & Constraints

**Always:**
- Ports arrive via constructor only; no Riverpod import, no `ref`, no service locator. Tests run under `dart test` with no Flutter binding and no ProviderContainer.
- Immutable state objects with `copyWith`; each controller exposes a `state` getter plus a broadcast `Stream` of changes (spine Consistency Conventions).
- AD-8: `PanelController.onHotkeyActivated()` reads `isVisible` synchronously; nothing on the decision path awaits.
- AD-18: a show after dismissal starts a fresh session — re-seed from the *current* clipboard and clear suggestions/error/submitted text. A return after iconification or focus loss preserves the session without a clipboard read. `submit()` captures the editor's exact text; `retry()` replays it, never current editor content.
- AD-3: `CorrectionCompleted.suggestions` is authoritative and replaces text accumulated from deltas.
- AD-4: exactly three things cancel an in-flight correction — `retry()`, a new `submit()`, `dispose()` (daemon shutdown). Hiding never cancels; a correction finishing while hidden (or after a re-show) is still persisted, but only the current session's events touch visible state.
- AD-7 rule: `CorrectionController` is the sole caller of `CorrectionRepository.save` — once per correction, at the terminal event, timestamps from the `Clock` port. Cancelled runs have no terminal event and save nothing.
- AD-13: every settings mutation goes through `ConfigStore.write` with a `copyWith`-derived `AppConfig`; no re-validation (the store is the single validation point).
- AD-10: `SettingsController` surfaces the `HotkeyRegistration` returned by `bind()` — authority (`application` = authoritative / `compositor` = advisory) plus effective binding — never the request as if it were in effect. Config persists a structured effective binding when reported; a bound result without one keeps the submitted binding as a restart seed, and an unavailable result retains the prior configured binding.
- AD-5: one injected `(CorrectionProvider, Preset)` pair; no provider selection below the composition root.
- Test names read as behaviour and cite CAP ids (AGENTS.md §7).

**Ask First:**
- Any change to files under `lib/src/domain/**` (spine-fixed declarations).
- Any new package dependency.

**Never:**
- No adapters, no Python sidecar, no drift tables, no UI widgets, no `application/composition/` Riverpod wiring (later slices).
- No fallback/cascade behaviour, no fake perceived speed (AGENTS.md §8).
- Compositor-side rebind reflection (`ShortcutsChanged`): the `GlobalHotkey` port exposes no registration-change stream, so this lands with the Wayland adapter slice — do not extend the port now.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Toggle shows (CAP-1) | Hotkey activation, panel hidden | `show()` called; decision path awaits nothing | A rejected `show()` is logged at error level; nothing is thrown and no `await` enters the decision path |
| Second press hides (CAP-14) | Hotkey activation, panel visible | `hide()` called, not re-shown | A rejected `hide()` is logged at error level; the toggle stays usable on the next press |
| Re-seed after dismissal (CAP-2, AD-18) | Show; dismiss; clipboard changes; show | New session seeded from current readable clipboard; iconify/focus-loss returns preserve the prior session without a read; empty/non-text clipboard seeds `''` | A throwing `readText()` is logged at warning level and the editor stays `''`; the session still starts and stays usable |
| Run + stream (CAP-5) | `submit(text)` then deltas | Per-register accumulated text grows per delta | A `correct()` that throws synchronously instead of returning a stream becomes `CorrectionFailed(providerError, …)` on the normal terminal path |
| Completion replaces deltas (AD-3) | Deltas whose concatenation ≠ final suggestions, then `CorrectionCompleted` | State shows the completed suggestions verbatim; one record saved, outcome `completed` | A `CorrectionCompleted` whose registers ≠ `SuggestionRegister.values` becomes `CorrectionFailed(malformedResponse, …)`; the record saved is `failed`, never `completed` |
| Failure inline (CAP-13) | Terminal `CorrectionFailed` | State carries kind + message for inline render; one record saved, outcome `failed`, no suggestions | Unchanged (failure is modelled state, never a throw); a rejected `save` of that record is logged and leaves the rendered failure intact |
| Retry replays captured text (CAP-13, AD-18) | `submit(a)`; editor later holds `b`; `retry()` | Provider called again with `a`; in-flight run (if any) cancelled | A rejected subscription `cancel()` is logged at error level and the retry still starts |
| New submit cancels (AD-4) | `submit(b)` while run in flight | First run's subscription cancelled; no record saved for it | Same cancel guard; a rejected cancel never leaves the new run unstarted |
| Hide does not cancel (AD-4, CAP-7) | Hide mid-stream, then terminal event | Run not cancelled; record persisted; suggestions dropped from state on next re-seed | A rejected `save` for that late record is logged; the fresh session's state is untouched either way |
| Shutdown cancels (AD-4) | `dispose()` mid-stream | Subscription cancelled; nothing saved; no state change after | `dispose()` never rethrows: a rejected cancel, a rejected pending save, and a rejected stream-subscription cancel are each logged and shutdown still completes |
| Hotkey change writes through (CAP-12, AD-13) | `changeHotkey(binding)` | `bind()` requested; structured effective binding written via `ConfigStore.write` when reported, submitted binding retained as a restart seed when a bound backend reports no structured effective, or prior binding retained on unavailability; outcome surfaced in state | A rejected `write` leaves `state.config` as the store's unchanged `current`, sets `SettingsState.failure` (`configWriteFailed`), logs an error, and does not rethrow |
| Advisory on Wayland (AD-10) | Fake `bind()` returns `compositor` authority + different effective | State shows advisory authority and the effective binding, not the request | A `HotkeyUnavailable` outcome lands in state as that value (AD-12); a `bind()` that *throws* is caught, logged, and lands as `HotkeyUnavailable` plus `SettingsState.failure` (`hotkeyBindFailed`) |
| Preset switch writes through (CAP-8) | `changeActivePreset(id)` | `copyWith(activePresetId)` written via `ConfigStore.write` | Identical to the hotkey-change row: unchanged config in state, `failure` set, logged, no rethrow |

</frozen-after-approval>

## Code Map

- `lib/src/domain/**` — all ports and value types (read-only; AD-2 fixed).
- [`panel_controller.dart`](../../lib/src/application/panel_controller.dart) — **new**; AD-8 toggle, subscribes to `GlobalHotkey.activations`.
- [`correction_state.dart`](../../lib/src/application/correction_state.dart) — **new**; `CorrectionState` + `CorrectionStatus`, the panel's whole observable session.
- [`correction_controller.dart`](../../lib/src/application/correction_controller.dart) — **new**; session/run/retry/persist, subscribes to `PanelVisibility.changes` for the AD-18 re-seed.
- [`settings_state.dart`](../../lib/src/application/settings_state.dart) — **new**; config + `HotkeyRegistration` for the settings surface.
- [`settings_controller.dart`](../../lib/src/application/settings_controller.dart) — **new**; write-through + `BindingAuthority` surfacing.
- [`fake_correction_provider.dart`](../../test/fakes/fake_correction_provider.dart) — manual-run mode added; scripted mode kept for `fakes_smoke_test.dart`.
- [`fake_clipboard_port.dart`](../../test/fakes/fake_clipboard_port.dart) — optional read gate, so tests can act while a seed is in flight.
- [`analysis_options.yaml`](../../analysis_options.yaml) — `unawaited_futures` enabled (review finding).
- [`ad1_import_rule_test.dart`](../../test/architecture/ad1_import_rule_test.dart) — AD-1 gate extended to the application ring, which exists for the first time in this slice.
- `test/application/*_test.dart` — **new**; one behavioural suite per controller.

## Tasks & Acceptance

**Execution:**
- [x] `test/fakes/fake_correction_provider.dart` — add manual-run mode with per-run cancellation flag — mid-flight cancel/hide scenarios need event timing control.
- [x] `lib/src/application/panel_controller.dart` — AD-8 toggle exactly as the spine sketch; constructor takes `PanelVisibility` + `GlobalHotkey`; `dispose()` cancels the activations subscription.
- [x] `lib/src/application/correction_controller.dart` — session state machine per the matrix; constructor takes `ClipboardPort`, `CorrectionProvider`, `Preset`, `CorrectionRepository`, `Clock`, `PanelVisibility`.
- [x] `lib/src/application/settings_controller.dart` — constructor takes `ConfigStore`, `GlobalHotkey`, optional initial `HotkeyRegistration`; `changeHotkey` + `changeActivePreset`.
- [x] `test/application/panel_controller_test.dart`, `correction_controller_test.dart`, `settings_controller_test.dart` — every matrix row, CAP ids in names, fakes only.
- [x] `test/architecture/ad1_import_rule_test.dart` — extend the AD-1 gate: `lib/src/application/**` may reference only `dart:`, Riverpod, and paths inside `application/` or `domain/`.
- [x] Review round 1 patches — provider-stream `onError`/`onDone` terminals, subscription cancelled at the terminal event (AD-19 process-group kill), shutdown guards and pending-save wait, late-clipboard-seed guard, settings write derived from `ConfigStore.current` with own-write echo suppression, `CorrectionState` failure assert, self-package URIs in the AD-1 gate, `unawaited_futures` lint.

**Acceptance Criteria:**
- Given the fakes only, when `dart test` runs without a Flutter binding, then all suites (35 existing + new) pass and the AD-1 gate stays green.
- Given a completed correction, when the terminal event arrives, then `CorrectionRepository.save` was called exactly once for that run — and zero times for a cancelled run.
- Given two synchronous `onHotkeyActivated()` calls from hidden, when no microtask runs between them, then the panel was shown then hidden (proves the synchronous decision path).
- Given a correction still in flight from a previous session, when it completes after the panel re-seeded, then the record is persisted and the fresh session's state is untouched.

## Spec Change Log

- **2026-09-26: Human-approved CAP-2/AD-18 session reconciliation.** The owner approved re-deriving product SPEC CAP-2 from the shipped session rule, and generated `SPEC.md` now says a summon after dismissal seeds current readable clipboard while iconified or focus-lost returns preserve the session. The controller's AD-18 constraint and CAP-2 matrix row are re-derived to that same behavior; `CorrectionController._onVisibilityChanged` and its existing CAP-2 cases supply the code evidence. This supersedes the original every-show wording, recoverable in git. The row's failure handling, all other matrix rows, and unrelated controller intent remain unchanged. Story 3's derived CAP-2 row was updated with it.
- **2026-09-26: Human-approved D-18 effective-binding renegotiation.** The owner chose to replace a configured preference with the compositor-reported effective combination rather than persist both. Phase 02 plan 02-02 implemented that decision in `SettingsController.changeHotkey`: a structured effective value is written, a bound result without one uses the submitted value as a restart seed, and an unavailable result retains the previous configured value. This supersedes the frozen block's original requested-binding rule in the AD-10 constraint and hotkey matrix row. Their former text remains in git history. The scenario, input, failure column, other 12 matrix rows, and all unrelated controller intent remain unchanged. Story 3's derived matrix and unavailable-bind row were updated from the same decision.
- **2026-09-26: Human-approved controller error-contract renegotiation.** The owner approved the committed `02-19-BMAD-UPDATE-PROPOSAL.md` and directed Codex to run the local BMAD workflow. The installed `bmad-create-story` path creates new stories and has no update route for this completed `bmad-quick-dev` artifact, so the artifact's owning frozen-block protocol governs this narrow revision. Only the 13 Error Handling cells were re-derived from story 3's Part A matrix; the 12 historical `N/A` cells and CAP-13 wording remain recoverable in git. Scenario, input, expected output, row order, and CAP/AD references are preserved. The known-bad state was a frozen matrix that falsely left guarded controller failures unspecified; story 3's completed implementation note and current controller code are the evidence. KEEP: no change to the controller intent or to other frozen columns.
- **Submit shape refined during implementation.** The frozen matrix writes the Retry row as `submit(a)`; editor later holds `b`. Making "the editor later holds `b`" observable requires the controller to own the editor's text, so the API is `editText(String)` + `submit()` rather than `submit(String)`. The frozen intent is unchanged and now actually testable: `editText('a'); submit(); editText('b'); retry()` re-sends `'a'`. Avoided known-bad state: a `submit(text)`-only API leaves the "not the edited text" half of CAP-13's invariant unobservable, so the test would pass vacuously.

## Design Notes

- Controllers are plain Dart; the composition slice later wraps them in Riverpod providers (AD-17). Keeping Riverpod out of these files keeps `dart test` binding-free.
- Each run and each panel session carries a monotonic token. Terminal events always persist; state mutation is guarded by "is this token current" — that one mechanism yields AD-4's hide-does-not-cancel and AD-18's drop-on-re-seed without special cases.
- `createdAtMillis` is taken at `submit`, `latencyMs` = terminal − submit, both from `Clock`.
- The clipboard read on show is async; the seed lands via a token-guarded state emission (a stale read never seeds a newer session). Nothing on `PanelController`'s path awaits it (AD-8 untouched).
- `PanelController` keeps no visibility state of its own — AD-8 makes the port the synchronous mirror, and a second copy would be a second source of truth. It exposes `isVisible` / `visibilityChanges` as pass-throughs so widgets stay inside the application ring.
- `SettingsController` subscribes to `ConfigStore.changes` so an external write reaches the surface, and drops the echo of its own write by identity — the store re-emits the very instance it was handed.

## Verification

**Commands:**
- `export PATH="$PATH:/home/vscode/flutter/bin" && flutter analyze` — expected: no issues.
- `export PATH="$PATH:/home/vscode/flutter/bin" && flutter test` — expected: all tests pass (35 existing + new).
- `export PATH="$PATH:/home/vscode/flutter/bin" && dart test test/application` — expected: new suites pass with no Flutter binding.

## Suggested Review Order

**The toggle (AD-8, CAP-1/CAP-14)**

- The whole toggle: reads the synchronous mirror, awaits nothing on the show path
  [`panel_controller.dart:31`](../../lib/src/application/panel_controller.dart#L31)

- Why the visibility stream is deliberately not re-exposed — the port declares no flavour
  [`panel_controller.dart:21`](../../lib/src/application/panel_controller.dart#L21)

**Session and run lifecycle — the load-bearing mechanism**

- Entry point: the two tokens that make hide-doesn't-cancel and drop-on-re-seed fall out
  [`correction_controller.dart:16`](../../lib/src/application/correction_controller.dart#L16)

- A show after dismissal starts a fresh session; the seed lands token-guarded and asynchronously
  [`correction_controller.dart:113`](../../lib/src/application/correction_controller.dart#L113)

- The seed yields to text the user typed while the clipboard read was in flight
  [`correction_controller.dart:122`](../../lib/src/application/correction_controller.dart#L122)

- Hiding returns early — the one place AD-4's third-rail rule is written down
  [`correction_controller.dart:104`](../../lib/src/application/correction_controller.dart#L104)

- Capture at submit, replay at retry; both cancel the in-flight run first
  [`correction_controller.dart:74`](../../lib/src/application/correction_controller.dart#L74)

**Provider boundary and history (AD-3, AD-7, AD-19)**

- `onError`/`onDone` terminals: a provider that breaks AD-3 must not strand the panel
  [`correction_controller.dart:151`](../../lib/src/application/correction_controller.dart#L151)

- Persist first, then update state only if current — the exactly-once terminal path
  [`correction_controller.dart:214`](../../lib/src/application/correction_controller.dart#L214)

- The sole `save` call, tracked so shutdown cannot drop the last record
  [`correction_controller.dart:253`](../../lib/src/application/correction_controller.dart#L253)

- Terminal teardown cancels rather than drops — AD-19's process-group kill runs in `onCancel`
  [`correction_controller.dart:291`](../../lib/src/application/correction_controller.dart#L291)

**Settings write-through (AD-10, AD-13)**

- Registration in, structured effective binding persisted when available: the X11-authoritative / Wayland-advisory split
  [`settings_controller.dart:56`](../../lib/src/application/settings_controller.dart#L56)

- Writes derive from the store's current value, so a concurrent change is not clobbered
  [`settings_controller.dart:83`](../../lib/src/application/settings_controller.dart#L83)

- Echo suppression, marked before the write because the store emits inside it
  [`settings_controller.dart:96`](../../lib/src/application/settings_controller.dart#L96)

**Supporting**

- State shape and the failure⇔failed invariant, asserted as `CorrectionRecord` does
  [`correction_state.dart:12`](../../lib/src/application/correction_state.dart#L12)

- What the settings surface renders, and what `authority` means to it
  [`settings_state.dart:5`](../../lib/src/application/settings_state.dart#L5)

- Manual-run provider fake: event timing and cancellation under the test's control
  [`fake_correction_provider.dart:47`](../../test/fakes/fake_correction_provider.dart#L47)

- The AD-1 gate extended to the application ring
  [`ad1_import_rule_test.dart:44`](../../test/architecture/ad1_import_rule_test.dart#L44)
