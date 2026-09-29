---
title: 'Controller failure contract'
type: 'feature'
created: '2026-08-07'
status: 'done'
baseline_revision: 'e431b6ad041db64e198d50256bb885a0bfca5973'
final_revision: '2245668'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-application-layer-controllers.md'
  - '{project-root}/lib/src/application/correction_controller.dart'
  - '{project-root}/lib/src/application/panel_controller.dart'
  - '{project-root}/lib/src/application/settings_controller.dart'
  - '{project-root}/lib/src/domain/hotkey/global_hotkey.dart'
  - '{project-root}/lib/src/domain/logger.dart'
warnings: ['multiple-goals', 'oversized']
---

<intent-contract>

## Intent

**Problem:** Every port call inside the three application controllers assumes success. A rejected `CorrectionRepository.save`, a throwing `ClipboardPort.readText`, a rejected `ConfigStore.write`, a throwing `GlobalHotkey.bind`, a rejected `PanelVisibility.show`/`hide`, a rejected subscription `cancel()`, and an error on any subscribed port stream each become an unhandled async error or an exception nothing renders — in a daemon that must stay resident all day. Stories 1 and 2 turned those from theoretical into live: real file IO and real SQLite now sit behind three of those ports. Two contract decisions the controller spec left open ride on the same fix: a `CorrectionCompleted` carrying missing or duplicated registers is written to history as a successful correction that produced nothing, and an empty editor can be submitted, spawning a sidecar and writing a CAP-7 row with empty `input_text`.

**Approach:** Give the controllers a failure contract. Inject the `Logger` port into all three; declare the `HotkeyUnavailable` state AD-12 names as a domain value so a refused bind resolves rather than throws; add a modelled failure to `SettingsState`; guard every port call so a resident daemon survives it; and close the two open contract decisions in the controller, where they hold for every caller. Extend `test/fakes/` so each port can be told to throw or reject on demand, and prove the whole thing headless.

## Boundaries & Constraints

**Always:**
- Consistency Conventions "Errors": expected failures are modelled values; exceptions signal programmer error only. No `catch` that swallows silently — every caught failure reaches the `Logger` port, and every failure a *user* can act on reaches state.
- AD-3 defence in depth: the controller already defends one AD-3 breach (a second terminal event). A `CorrectionCompleted` whose suggestion registers are not exactly the set `SuggestionRegister.values` — missing, duplicated, or otherwise mismatched — is defended identically, and never reaches `CorrectionRepository.save` as a completed record.
- AD-7 stays intact: still exactly one `save` per terminal event, still `CorrectionController` as its sole caller. A save that fails still counts as that correction's one attempt — never retried, never re-issued.
- AD-12: a failed hotkey registration resolves to a `HotkeyUnavailable` state, never an exception. It is a domain value, additive alongside the spine-verbatim `HotkeyRegistration`.
- AD-13: an unwritable config never takes the daemon down. A rejected `ConfigStore.write` leaves `ConfigStore` as the single owner of the value (state never claims a config the store did not accept), surfaces a failure on `SettingsState`, and does not rethrow.
- AD-15 is respected, not relocated: adapters keep owning vendor-error translation. Every controller-side guard added here is a *backstop against a port implementation that breaks its contract*, and each is commented as such.
- AD-8 is untouched: `PanelController.onHotkeyActivated()` still awaits nothing before deciding. Failure handling attaches to the fired future; it never introduces an `await` on the decision path.
- AD-1 stays green: new domain files import only `dart:`; `lib/src/application/**` still reaches only `dart:`, Riverpod, `application/` and `domain/`.
- Logging discipline (Consistency Conventions): no log message and no log context value ever carries `input_text`, editor text, clipboard content, or a suggestion body. Log ids, kinds, latencies, and the failure's own text.
- Every scenario in the matrix below is headless — `dart test`, no Flutter binding, no real desktop, no real sidecar. Failure injection lives on the existing `test/fakes/`, so every future consumer of those fakes inherits it.
- Test names read as behaviour and cite the CAP or AD id they defend (AGENTS.md §7).

**Block If:**
- Declaring `HotkeyUnavailable` as a modelled bind outcome turns out to require changing `HotkeyRegistration`, `HotkeyBinding`, `BindingAuthority`, or `CorrectionEvent` — those are spine-verbatim (AD-2, AD-9) and cannot be rewritten unattended. Adding a new sealed type beside them, and widening `GlobalHotkey.bind`'s return type to it, is in scope; editing the existing declarations is not.
- Closing any matrix row would require the controller to retry, cascade, or fall back over a failed port call (AGENTS.md §8 rules that out).

**Never:**
- No composition root, no `main.dart` wiring, no Riverpod, no `TrayPort` wiring — the tray's AD-12 surface (`TrayPort.setHotkeyUnavailable`) already exists in the domain and belongs to the composition-root story, which consumes the state this story declares.
- No UI widgets: the empty-submit guard goes in the controller and nowhere else in this story.
- No new port methods beyond widening `GlobalHotkey.bind`'s return type; no `delete`/`prune` on `CorrectionRepository`; no file watching on `ConfigStore`.
- No retry, backoff, cascade, or fallback on any failed port call.
- No new package dependency, no pubspec pin change.
- Do not fix the other open ledger entries riding on these files (value equality for state objects, `FakeCorrectionRepository.recent` ordering, the `SqliteException` vendor-type escape, corrupt-history recovery). They stay filed.

## I/O & Edge-Case Matrix

**Part A — the controller spec's 13 rows, with Error Handling filled in.** Expected Output follows `spec-application-layer-controllers.md`; CAP-2 and D-18 updated the session and hotkey rows in both records after the original error-column derivation. The last column replaced the original "N/A" cells.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Toggle shows (CAP-1) | Hotkey activation, panel hidden | `show()` called; decision path awaits nothing | A rejected `show()` is logged at error level; nothing is thrown and no `await` enters the decision path |
| Second press hides (CAP-14) | Hotkey activation, panel visible | `hide()` called, not re-shown | A rejected `hide()` is logged at error level; the toggle stays usable on the next press |
| Re-seed after dismissal (CAP-2, AD-18) | Show; dismiss; clipboard changes; show | New session seeded from current readable clipboard; iconify/focus-loss returns preserve the prior session without a read; empty/non-text clipboard seeds `''` | A throwing `readText()` is logged at warning level and the editor stays `''`; the session still starts and stays usable |
| Run + stream (CAP-5) | `submit()` then deltas | Per-register accumulated text grows per delta | A `correct()` that throws synchronously instead of returning a stream becomes `CorrectionFailed(providerError, …)` on the normal terminal path |
| Completion replaces deltas (AD-3) | Deltas ≠ final suggestions, then `CorrectionCompleted` | State shows the completed suggestions verbatim; one record saved, outcome `completed` | A `CorrectionCompleted` whose registers ≠ `SuggestionRegister.values` becomes `CorrectionFailed(malformedResponse, …)`; the record saved is `failed`, never `completed` |
| Failure inline (CAP-13) | Terminal `CorrectionFailed` | State carries kind + message for inline render; one record saved, outcome `failed` | Unchanged (failure is modelled state, never a throw); a rejected `save` of that record is logged and leaves the rendered failure intact |
| Retry replays captured text (CAP-13, AD-18) | `editText('a')`; `submit()`; `editText('b')`; `retry()` | Provider called again with `'a'`; in-flight run cancelled | A rejected subscription `cancel()` is logged at error level and the retry still starts |
| New submit cancels (AD-4) | `submit()` while a run is in flight | First run's subscription cancelled; no record saved for it | Same cancel guard; a rejected cancel never leaves the new run unstarted |
| Hide does not cancel (AD-4, CAP-7) | Hide mid-stream, then terminal event | Run not cancelled; record persisted; suggestions dropped on next re-seed | A rejected `save` for that late record is logged; the fresh session's state is untouched either way |
| Shutdown cancels (AD-4) | `dispose()` mid-stream | Subscription cancelled; nothing saved; no state change after | `dispose()` never rethrows: a rejected cancel, a rejected pending save, and a rejected stream-subscription cancel are each logged and shutdown still completes |
| Hotkey change writes through (CAP-12, AD-13) | `changeHotkey(binding)` | `bind()` requested; structured effective binding written via `ConfigStore.write` when reported, submitted binding retained as a restart seed when a bound backend reports no structured effective, or prior binding retained on unavailability; outcome surfaced in state | A rejected `write` leaves `state.config` as the store's unchanged `current`, sets `SettingsState.failure` (`configWriteFailed`), logs an error, and does not rethrow |
| Advisory on Wayland (AD-10) | Fake `bind()` returns `compositor` authority + different effective | State shows advisory authority and the effective binding, not the request | A `HotkeyUnavailable` outcome lands in state as that value (AD-12); a `bind()` that *throws* is caught, logged, and lands as `HotkeyUnavailable` plus `SettingsState.failure` (`hotkeyBindFailed`) |
| Preset switch writes through (CAP-8) | `changeActivePreset(id)` | `copyWith(activePresetId)` written via `ConfigStore.write` | Identical to the hotkey-change row: unchanged config in state, `failure` set, logged, no rethrow |

**Part B — new scenarios this story adds.**

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Empty submit guarded | Editor is `''` (or only whitespace); `submit()` | No provider call, no `save`, no state emission; status stays `idle` | Not a failure: one info log line naming the guard, no text in it |
| Retry after a guarded submit | Guarded `submit()`, then `retry()` | Still nothing: `submittedText` was never set | No error expected |
| Duplicated register | `CorrectionCompleted([formal, formal, casual])` | `CorrectionFailed(malformedResponse, …)` in state; one record saved, outcome `failed`, `failureKind` `malformedResponse`, zero suggestions | Error logged naming the register mismatch — counts only, never suggestion text |
| Missing register | `CorrectionCompleted([formal, casual])` | Same as above | Same |
| Well-formed completion | `CorrectionCompleted` with all three registers, any order | Accepted; record saved `completed` with all three | No error expected |
| History write rejects | Repository `save` returns a rejected future, completed correction | State stays `CorrectionStatus.completed` with its suggestions — the correction succeeded, only its record did not | Error logged with preset/provider/outcome/latency; no input text, no suggestions; `dispose()` still completes |
| Clipboard read throws | `readText()` throws on a show after dismissal | Editor `''`, status `idle`, session usable | Warning logged; the exception never escapes |
| Provider throws on call | `correct()` throws before returning a stream | Exactly one terminal: `CorrectionFailed(providerError, …)`; one `failed` record saved | Error logged; treated as the AD-3 breach it is |
| Visibility stream errors | `PanelVisibility.changes` emits an error | Controller stays live: a later show after dismissal still starts a fresh session | Error logged; no unhandled async error |
| Activations stream errors | `GlobalHotkey.activations` emits an error | `PanelController` stays live: the next press still toggles | Error logged; no unhandled async error |
| Config stream errors | `ConfigStore.changes` emits an error | `SettingsController` stays live: a later external write still reaches state | Error logged; no unhandled async error |
| Bind unavailable (AD-12) | `bind()` resolves to `HotkeyUnavailable` | `SettingsState` carries the `HotkeyUnavailable` outcome; config retains the prior binding as a restart seed (D-18) | No throw anywhere; one warning log naming unavailability |
| Recovery after a failure | Failing write, then a write that succeeds | `SettingsState.failure` is null again and `config` reflects the new value | No error expected |
| Nothing sensitive is logged | Every failure path above, with distinctive editor text and suggestion bodies | — | No logged message or context value contains the submitted text, the clipboard text, or any suggestion body |

</intent-contract>

## Code Map

- `lib/src/domain/hotkey/global_hotkey.dart` -- holds the spine-verbatim `HotkeyRegistration` + `BindingAuthority` (**do not edit those declarations**) and the `GlobalHotkey` port whose `bind` return type widens here.
- `lib/src/domain/hotkey/hotkey_bind_outcome.dart` -- **new**; the sealed `HotkeyBindOutcome` = `HotkeyBound` | `HotkeyUnavailable` that AD-12 names.
- `lib/src/domain/logger.dart` -- the port injected into all three controllers; its doc already forbids logging clipboard-derived payloads.
- `lib/src/application/correction_controller.dart` -- five guarded port paths (`readText`, `correct`, subscription `cancel`, `save`, the visibility stream) plus the two closed contract decisions.
- `lib/src/application/correction_state.dart` -- read-only reference; a failed *save* deliberately produces no state change (see Design Notes).
- `lib/src/application/panel_controller.dart` -- guarded `show`/`hide` and the activations stream, without touching AD-8's synchronous decision path.
- `lib/src/application/settings_controller.dart` -- `bind` outcome handling, guarded `write`, guarded config stream, failure clearing.
- `lib/src/application/settings_state.dart` -- the `hotkeyRegistration` field becomes the sealed bind outcome, plus the new modelled `SettingsFailure`.
- `test/fakes/fake_clipboard_port.dart`, `fake_correction_repository.dart`, `fake_config_store.dart`, `fake_global_hotkey.dart`, `fake_panel_visibility.dart`, `fake_correction_provider.dart` -- failure injection added to each.
- `test/fakes/fake_logger.dart` -- already records level/message/context; the assertions read it as-is.
- `test/application/{correction,panel,settings}_controller_test.dart` -- existing suites; their harnesses gain the `Logger`, and `_SlowBindHotkey` in the settings suite follows the widened `bind` signature.
- `test/fakes_smoke_test.dart` -- constructs `FakeGlobalHotkey`; must still compile and pass.
- `test/architecture/ad1_import_rule_test.dart` -- the AD-1 merge gate the new domain file must not trip.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- holds the three entries this story closes.

## Tasks & Acceptance

**Execution:**
- `lib/src/domain/hotkey/hotkey_bind_outcome.dart` -- create the sealed `HotkeyBindOutcome` with `HotkeyBound(HotkeyRegistration registration)` and `HotkeyUnavailable({required String message})` -- AD-12's state must be a value the port can return, and the spine-verbatim `HotkeyRegistration` cannot be extended (it is `final class`).
- `lib/src/domain/hotkey/global_hotkey.dart` -- widen `bind` to `Future<HotkeyBindOutcome> bind(HotkeyBinding binding)` and document that unavailability is reported as a value, never a rejection -- the only edit; `HotkeyRegistration` and `BindingAuthority` stay byte-identical to AD-9.
- `lib/src/application/settings_state.dart` -- replace `hotkeyRegistration` with `HotkeyBindOutcome? hotkeyBindOutcome`; add `SettingsFailure` (`enum SettingsFailureKind { configWriteFailed, hotkeyBindFailed }` + message) as a nullable field, following `correction_state.dart`'s shape of one state class plus its small companions in one file.
- `lib/src/application/settings_controller.dart` -- take a `Logger`; handle both `HotkeyBindOutcome` arms; catch a throwing `bind` into `HotkeyUnavailable` + `hotkeyBindFailed`; catch a rejected `write` into `configWriteFailed` without rethrowing; add `onError` to the config subscription; clear `failure` on the next successful mutation.
- `lib/src/application/panel_controller.dart` -- take a `Logger`; attach failure handling to the fired `show()`/`hide()` futures without awaiting them; add `onError` to the activations subscription; guard `dispose()`.
- `lib/src/application/correction_controller.dart` -- take a `Logger`; guard `readText`, the `correct()` call itself, every subscription `cancel()`, and `save`; add `onError` to the visibility subscription; make `dispose()` non-throwing; add the empty-submit guard and the AD-3 register-set check (see Design Notes for both decisions).
- `test/fakes/fake_clipboard_port.dart` -- add `readError` / `writeError`; when set, the method throws it after the existing `readGate` -- a real clipboard read is display-server IPC and can fail.
- `test/fakes/fake_correction_repository.dart` -- add `saveError`; when set, `save` returns a rejected future (rejected, not a synchronous throw, matching `DriftCorrectionRepository.save`'s shape).
- `test/fakes/fake_config_store.dart` -- add `writeError` (write rejects, `current` unchanged, no `changes` emission) and a way to push an error onto `changes`.
- `test/fakes/fake_global_hotkey.dart` -- rework `onBind` to the widened return type, add `bindError` for the contract-breaking throw, and a way to push an error onto `activations`.
- `test/fakes/fake_panel_visibility.dart` -- add `showError` / `hideError` and a way to push an error onto `changes`.
- `test/fakes/fake_correction_provider.dart` -- add `correctError` so `correct()` throws instead of returning a stream.
- `test/application/correction_controller_test.dart` -- extend the harness with the `FakeLogger`; add a group per Part B row that touches this controller, plus the "nothing sensitive is logged" assertion.
- `test/application/panel_controller_test.dart` -- add the rejected `show`/`hide` and activations-error rows.
- `test/application/settings_controller_test.dart` -- update `_SlowBindHotkey` to the widened signature; add the write-rejection, bind-unavailable, bind-throws, config-stream-error, and failure-recovery rows.
- `test/application/controller_resilience_test.dart` -- **new**; run each controller's full lifecycle inside `runZonedGuarded` with every fake failing, asserting the captured unhandled-error list is empty -- the guards are only worth having if nothing escapes the zone, and no per-scenario assertion proves that.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- retain the headings and historical text of the three entries this story closes; set each `status: done <date>` and add a `resolution:` citing the closing evidence. Leave every other entry untouched, and append any new finding.

**Acceptance Criteria:**
- Given every fake port set to fail, when each controller is driven through show → edit → submit → terminal → retry → dispose, then `runZonedGuarded` captures zero unhandled errors and no call rethrows to the caller (CAP-1's daemon stays resident).
- Given a completed correction whose `save` rejects, when the terminal event lands, then state is `CorrectionStatus.completed` with the completed suggestions, exactly one `save` attempt was made, and `dispose()` completes without throwing (CAP-7 loses the record; the panel does not lie about the correction).
- Given a `CorrectionCompleted` missing a register, when it arrives, then no record with outcome `completed` is ever saved for that run and the panel shows an inline failure with a working Retry (AD-3, CAP-13).
- Given the deferred-work ledger, when this story closes its three entries, then all three headings remain, each has `status: done <date>` and a `resolution:` citing the closing evidence, and every other entry remains unchanged.
- Given `dart analyze`, `dart test` and `dart format --set-exit-if-changed lib test`, when all three run, then all pass — including `test/architecture/ad1_import_rule_test.dart` and every pre-existing suite.
- Given the story's completion notes, when it finishes, then they state what each of the controller spec's 13 "N/A" rows now does, which `CorrectionFailureKind` a register mismatch maps to and why, and that the panel-UI story should additionally disable the Correct action on an empty editor.

## Spec Change Log

## Review Triage Log

### 2026-08-07 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 13: (high 1, medium 2, low 10)
- defer: 5: (high 0, medium 2, low 3)
- reject: 6: (high 0, medium 1, low 5)
- addressed_findings:
  - `[high]` `[patch]` **The controllers stringified caught errors into `Logger` context, and that provably leaked the user's clipboard text.** `_save` logged `{'error': '$error'}`; behind that port `DriftCorrectionRepository` binds `input_text` and every suggestion body as statement parameters, and `package:sqlite3 3.5.1`'s `SqliteException.toString()` appends `Causing statement: … , parameters: …` for an *execution*-stage failure. Reproduced directly with a `BEFORE INSERT … RAISE(ABORT)` trigger: the caught error stringified to `… parameters: 1, MY-PRIVATE-CLIPBOARD-SECRET, p, q, m, 5, completed, null`. That breaks `Logger`'s own doc, the spine's Logging convention, and this story's Always list, in a daemon logging to stderr all day. Every context site in all three controllers now passes `_errorContext(error)` → `{'error_type': error.runtimeType.toString()}` and nothing else from the error object; the port doc records the mechanism. The "nothing sensitive reaches the log" test injected only hand-written `StateError`s, so it could never have caught this — it now injects an `_EchoingError` whose `toString()` embeds the secret, on both the clipboard and save paths. Mutation-verified: restoring `'error': '$error'` fails that test.
  - `[medium]` `[patch]` Three `dispose()` guards were unreachable from the suite. The Part A "Shutdown cancels (AD-4)" row names "a rejected stream-subscription cancel", but `FakePanelVisibility.changes`, `FakeConfigStore.changes` and `FakeGlobalHotkey.activations` are plain `StreamController`s whose `cancel()` cannot reject, so all three guards mutated away green. Added `test/fakes/cancel_failing_stream.dart` (a `StreamView` whose subscription rejects on cancel — a broadcast controller's `onCancel` throw goes to the zone, not the `cancel()` future, so the controllers' own hooks could not express it) and one `dispose()` test per controller. Each mutation-verified.
  - `[medium]` `[patch]` `_write`'s `on Object` swallowed the store's validation rejection into `configWriteFailed`. `JsonConfigStore.write` throws `ArgumentError.value` for a cross-field-invalid config *before any I/O*, so a dangling `activePresetId` was reported to the user as "the config write failed" when nothing was ever written and the value itself was refused. Added `SettingsFailureKind.configRejected`, caught ahead of the generic arm, still without rethrowing (AD-13 holds); `FakeConfigStore.rejects` mirrors the real store's pre-I/O throw.
  - `[low]` `[patch]` `_registerMismatch`'s `distinct.length == suggestions.length` clause was unpinned — every AD-3 test supplied too *few* distinct registers, so weakening it to `distinct.length == expected` passed the suite while letting `[formal, casual, shorter, formal]` through as `completed` (with `_textsOf` silently keeping the last copy). Added that case; mutation-verified.
  - `[low]` `[patch]` `PanelController._fire`'s outer `try`/`catch` — the AD-15 backstop against a non-`async` adapter — had no producer, since both fake methods are `async` and can only reject. Added `_SynchronouslyThrowingVisibility` and a test.
  - `[low]` `[patch]` `failure: writeFailure ?? bindFailure` was executed but unasserted: every settings test failed exactly one port, and the resilience test that fails both asserts only that nothing escaped, so flipping the operands passed. Added a both-ports-fail test.
  - `[low]` `[patch]` `_onConfigChanged` was the one transition still using `copyWith`, which `SettingsState` documents as unable to clear `failure`. Now builds state directly, with the decision written down: an external config edit does not retire a failure the user's own change earned.
  - `[low]` `[patch]` `HotkeyUnavailable(message: '$error')` broke the domain type's own doc ("in terms a user can act on") and duplicated one raw exception string into two rendered fields. `HotkeyUnavailable.message` is now a user sentence; the raw detail stays in `SettingsFailure.message`.
  - `[low]` `[patch]` The empty-submit guard returns before `_cancelRun()`, so a blank `submit()` mid-stream no longer cancels the running correction — pre-diff every submit did. The behaviour is right; it was undocumented and untested. Documented on `submit`, plus a test that the in-flight run survives to its terminal event.
  - `[low]` `[patch]` The malformed-register failure rendered "the provider returned 1 suggestions covering 1 of 3 registers" into CAP-13's inline panel error, plural bug included. User sentence in `CorrectionFailed.message`; counts stay in the log context.
  - `[low]` `[patch]` `initialBindOutcome` — the only seam for seeding a startup bind result, and newly typed by this story — had zero call sites and zero tests. Added one.
  - `[low]` `[patch]` The source spec's Error Handling column is still `N/A` for 12 of 13 rows and the entry naming it as root cause was removed, leaving the contract untracked. Filed as ledger entry DW-5 rather than edited: that spec is `status: done` with its matrix inside `<frozen-after-approval>`. DW-5 also records that the Intent's "11 of 13" is actually 12.
  - `[low]` `[patch]` DW-2, DW-3 and DW-4 carried no `status:` field while DW-1 does, and the canonical format makes it the field the triage sweep partitions on. Added `status: open` to all four new entries.

### 2026-08-07 — Review pass (follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 13: (high 0, medium 6, low 7)
- defer: 5: (high 1, medium 3, low 1)
- reject: 8: (high 0, medium 2, low 6)
- addressed_findings:
  - `[medium]` `[patch]` **The previous pass's leak fix moved raw error strings out of the log and into rendered state, where nothing asserted on them.** Three new sites set `SettingsFailure.message: '$error'` and one new site built `'the provider could not start a correction: $error'` into `CorrectionFailed.message` — CAP-13's inline panel text. Probed: the settings surface rendered `FileSystemException: Cannot open file, path = '/home/…/config.json' (OS Error: Permission denied…)`, and the panel rendered `ProcessException: spawn failed, args: [--text, <the submitted text>]`. `SettingsFailure`'s own doc calls it "a failure the user can act on"; a comment one file over called it "the developer-facing half" — a contradiction this diff introduced. Resolved in favour of the type's doc: each `SettingsFailureKind` and the provider-throw failure now carry a fixed user sentence, and the raw error reaches nothing (the type still reaches the log via `_errorContext`). Mutation-verified: restoring either shape fails the new tests. The pre-existing stream-error twin was filed, not patched.
  - `[medium]` `[patch]` A successful `changeActivePreset` retired a `hotkeyBindFailed` the user's hotkey change had earned, while the shortcut was still dead. This contradicts the principle the same file states at `_onConfigChanged` ("clearing the banner here would report success for a mutation that never happened"), applied inconsistently. A mutation now clears only failures it could itself have fixed. Mutation-verified. The concurrent variant — a parked slow bind clearing a preset's write failure — needs a generation guard and was deferred with the underlying race.
  - `[medium]` `[patch]` `hotkeyBindOutcome`'s carry-forward through the two transitions this story rewrote from `copyWith` to direct construction was pinned by nothing: substituting `null` in either `changeActivePreset` or `_onConfigChanged` left the full suite green. AD-12's `HotkeyUnavailable` — the whole point of the new domain value — silently vanished from the surface after any preset switch or external config edit. All five existing assertions fired immediately after `changeHotkey`, so none survived a following transition. Added a test that drives both transitions; both mutations now die.
  - `[medium]` `[patch]` The previous pass claimed the `_errorContext` leak guard was "mutation-verified" in "all three controllers"; it was verified in one. Adding `'error': '$error'` back to the settings or panel copy left the suite green — the leak test constructs only a `CorrectionController` harness. Added an echoing-error leak test to both suites; both mutations now die.
  - `[medium]` `[patch]` `dispose()`'s `await Future.wait(_pendingSaves)` — documented as "shutdown waits for them: CAP-7 retains every correction, including one that terminates as the daemon exits" — was pinned by nothing: deleting the wait, or the tracking entirely, left the suite green. The existing test asserts only that `dispose()` *completes*, which cannot distinguish waiting from never waiting. Added `FakeCorrectionRepository.saveGate` and a test that holds a write open across shutdown.
  - `[medium]` `[patch]` Every guard added by this story recovers by calling `_logger` unguarded, making the `Logger` the one port whose failure re-creates what the guards exist to prevent. Probed with a logger that throws (a daemon whose stderr became a broken pipe): `dispose()` **rethrew** and an unhandled zone error fired — breaking both the code's own "never rethrows" doc and the story's headline acceptance criterion. `controller_resilience_test.dart` could never catch it: it injects only `FakeLogger`, which cannot throw. Every recovery-path log now goes through a `_log(...)` helper that swallows the logger's own failure — the one sanctioned silent swallow, since the reporting channel is what broke — plus a `ThrowingLogger` fake and one test per controller. Mutation-verified: removing the swallow fails all three.
  - `[low]` `[patch]` The resilience suite's logging assertion was vacuous: `expect(logger.lines, isNotEmpty)` is satisfied by any one of the five guarded failures the correction case drives, so four could stop reporting and stay green. Replaced with named per-guard assertions in all three cases. That immediately exposed a second gap: the panel case set `hideError` but never reached the hide arm, because a panel whose `show()` always fails is never visible and every press took the show branch. Scenario reordered so both arms and the cancel guard actually run.
  - `[low]` `[patch]` `PanelController` logged a failed `hide()` under whichever action string it was handed, unpinned: `_fire(_visibility.hide, 'show')` survived, so an operator reading stderr would see the wrong call named. The hide test asserted only the line's level.
  - `[low]` `[patch]` The malformed-register message told the user "some of the three variants are missing" for both shapes `_registerMismatch` fires on — including the full set plus a duplicate, where nothing is missing and the response was over-complete. The previous pass rewrote this message to be user-facing and replaced a pluralisation bug with a factual one; the test for that exact input asserted only status/outcome/kind. Now one sentence true of both shapes, pinned.
  - `[low]` `[patch]` The clipboard-read guard logged before checking `_sessionToken`/`_disposed`, so a read failing for a session already replaced was warned about against the session that replaced it, and one resolving after shutdown logged anyway. Check moved ahead of the warning. (The first version of this test did not reach the catch at all and the mutation survived; the test was rebuilt around a superseded *failing* read and now kills it.)
  - `[low]` `[patch]` The log-context field sets the matrix rows name ("Error logged with preset/provider/outcome/latency", "counts only") were unpinned — every relevant test asserted the line's level and nothing about its context, so all three context maps could be gutted. Added key assertions for the save and register-mismatch lines.
  - `[low]` `[patch]` `SettingsState.copyWith` was dead on arrival: this story added a `failure` parameter to it and then removed its last caller, leaving an API whose only remaining purpose was to re-arm the bug the previous pass had just removed (`failure ?? this.failure` cannot clear). Deleted; the reasoning moved onto the field's doc.
  - `[low]` `[patch]` The first pass's Verification claimed `grep -rn "'$error'" lib/src/application lib/src/domain` returned nothing after the leak fix. It returned three matches when written, and the pattern could not have matched the two `': $error'` interpolations in `correction_controller.dart` regardless — six sites survived a claim that the class was closed. Four were patched in this pass and the pre-existing fifth filed; the claim is now annotated in place rather than deleted, since it is the record of what the first pass believed. **Process note:** this pass initially rejected the finding as citing text absent from the spec. It was absent from the *working tree* — the file arrived with its whole `## Auto Run Result` section deleted, and this pass read that copy while the reviewers read the committed revision. The section has been restored, with the first and follow-up passes nested under it.

### 2026-08-07 — Review pass (third)

- intent_gap: 0
- bad_spec: 0
- patch: 15: (high 0, medium 4, low 11)
- defer: 4: (high 0, medium 3, low 1)
- reject: 10: (high 0, medium 1, low 9)
- addressed_findings:
  - `[medium]` `[patch]` **`PanelController` read `PanelVisibility.isVisible` unguarded, on the decision path of every press** — the one port call in the layer outside any guard, and the story's headline acceptance criterion is that `runZonedGuarded` captures zero unhandled errors. Probed: a mirror that throws propagated straight to a direct caller, and from the activations stream produced **two unhandled zone errors and zero log lines** (the error is raised inside `onData`, so the constructor's `onError` never sees it). `FakePanelVisibility` had no seam for it, so the resilience suite's "every port it calls fails" claim could not reach it. Added `_visibleNow()` with the same AD-15 reasoning as `_fire`, assuming hidden (the user pressed the hotkey because they want the panel, and CAP-14's second press re-hides once the mirror answers), plus `isVisibleError` on the fake, three tests, and coverage in the resilience suite. Mutation-verified.
  - `[medium]` `[patch]` `CorrectionController._onVisibilityChanged` had no `_disposed` guard, and this story's own `_cancel` swallow is what made that reachable: a refused visibility cancel leaves the subscription live (as `cancel_failing_stream.dart` documents), so a later show began a session and issued clipboard IPC — display-server IPC from a controller already torn down. Guarded; mutation-verified.
  - `[medium]` `[patch]` `SettingsController` had no post-dispose guard at all, while a ledger entry filed by the previous pass cites its `_changes.isClosed` as the guarded counter-example to `PanelController`'s gap. `_changes.isClosed` suppresses only the *emission*: `_setState` assigned `_state` before reaching it, and both mutations performed their full port IO first. Probed: `await dispose()` then `changeActivePreset` produced a real `ConfigStore.write` and a `GlobalHotkey.bind`, with the getter reporting post-shutdown state. Guarded at both mutations and inside `_setState`; two tests, including a bind that resolves after shutdown (AD-11 makes a seconds-long portal dialog normal, so the entry guard cannot catch that one). Both mutation-verified. The ledger claim is now true rather than edited, since the invocation forbids rewriting existing entries.
  - `[medium]` `[patch]` A successful mutation retired a failure the *other* mutation earned, in both directions. The previous pass added `_survivingBindFailure` for one of three `SettingsFailureKind` values; the two config kinds were left, and `changeHotkey` had no filter at all. Probed both ways: a failed preset switch then a successful hotkey change cleared the banner while the preset was still unwritten, and the reverse. The kind alone cannot carry the rule — a failed write of *either* mutation produces the same `configWriteFailed` — so ownership is now tracked explicitly (`_failedMutation` + `_resolveFailure`, replacing `_survivingBindFailure`), and a mutation clears only a failure it could itself have fixed. Three tests; mutation-verified.
  - `[low]` `[patch]` The AD-12 unavailability warning logged `{'reason': outcome.message}` — adapter-authored free text, and the only context value in three controllers not reduced to a type. The shape an adapter would plausibly build it from is `'$error'`, which is exactly what this controller itself shipped before the previous pass patched it out. Now logs the outcome type; the message still reaches the surface, where it is contractually a user sentence. A leak test now drives the `HotkeyUnavailable` *value* arm, which no test did — every settings leak assertion drove the `bindError` *throw* arm.
  - `[low]` `[patch]` `_log`'s and `_errorContext`'s doc summaries were swapped in `correction_controller.dart` — the site both sibling controllers explicitly redirect readers to as canonical, so every reader of the pattern landed on a summary describing the other function.
  - `[low]` `[patch]` The `CorrectionController` class doc claimed "every port call here is guarded" while the constructor subscribes to `PanelVisibility.changes` unguarded. Qualified rather than guarded, with the reason written down: construction happens once at the composition root, where an adapter that cannot hand over its stream is a startup failure and should be one.
  - `[low]` `[patch]` The correction suite kept a byte-identical private `_EchoingError` beside `test/fakes/echoing_error.dart`, the shared fake the previous pass extracted from it and wired into the other two suites. Migrated, so a future strengthening of the double applies to the controller whose leak started the thread.
  - `[low]` `[patch]` **The previous pass verified `_log` and `_errorContext` by mutating the shared helpers; the call sites were a weaker property and were unpinned.** Re-derived per site: the `_log` swallow was killed at 10 of 17 sites and the `_errorContext` reduction at 8 of 14, so a single site could bypass either with the suite green — including `dispose()` rethrowing on the exact broken-stderr scenario the swallow was written for. Added throwing-logger cases reaching every remaining site in all three suites. Now **17 of 17** and **14 of 14**, each mutated individually against a confirmed-green baseline.
  - `[low]` `[patch]` The settings leak test could not detect its own leak on the refusal path: `FakeConfigStore`'s `ArgumentError.value(config, …)` stringifies to `Instance of 'AppConfig'`, so stringifying it into the log context leaked nothing a test could see. Added `EchoingArgumentError` and `FakeConfigStore.rejectError`; that site now kills its mutation. Same class on the correction side, where the leak test injected a plain `StateError` on the provider-throw path.
  - `[low]` `[patch]` The resilience suite's "every port it calls fails" scenarios never armed a rejected cancel for two of three controllers, and `_finish`'s terminal-event cancel — the one of three cancel sites no test reached, and under AD-19 the sidecar's process-group kill — was unreachable everywhere. Armed in all three scenarios, plus a targeted test; mutation-verified.
  - `[low]` `[patch]` `_cancel`'s `$what` label was unpinned: hardcoding it to one subscription left the suite green, so an operator could read "the panel visibility subscription" when the sidecar kill refused. This is the same defect the previous pass found and fixed for `PanelController`'s `$action` and left standing in the sibling. Three call sites now assert their own label.
  - `[low]` `[patch]` The lost-history-row log context asserted its *keys* via `containsAll`, so every value could be wrong: `outcome` could report `completed` for a failed record and `preset_id` another correction's. Now asserted by value, with the clock advanced so the latency is not a degenerate zero.
  - `[low]` `[patch]` Four messages were pinned by level or by a negative only, and could each be emptied with the suite green: `HotkeyUnavailable.message` (AD-12's tray and settings-screen explanation), the AD-12 warning's message and context, and the empty-submit info line — the only thing telling an operator why a Correct press did nothing.
  - `[low]` `[patch]` The `_disposed` half of the clipboard-read staleness check was unpinned — the previous pass rebuilt that test around a superseded *session*, which exercises the token half only. Added the shutdown twin.

## Design Notes

**Why `HotkeyBindOutcome` rather than a rejected `bind()`.** The Consistency Conventions "Errors" row names `HotkeyUnavailable` as a *modelled value*, alongside `CorrectionEvent` and `HotkeyRegistration`. AD-9 fixes `HotkeyRegistration` as a `final class`, so it cannot be extended, and `Future<HotkeyRegistration>` has no arm for "no binding exists at all" — `effective: null` is already documented as "the backend cannot report it", a different thing. Widening the return type is therefore the only shape that satisfies AD-12 without rewriting a spine-verbatim declaration. This diverges from AD-9's verbatim `bind` line; record it in the ledger rather than hand-editing the spine, as stories 1 and 2 did for AD-16 and the Stack table. The `SettingsController` still catches a *throwing* `bind` — that is an AD-15 breach by the adapter, and the same class of defence as the existing `onError`/`onDone` handlers that catch an AD-3-breaking provider.

**Which `CorrectionFailureKind` a register mismatch maps to, and where the check lives.** Put the check in the controller and map it to `malformedResponse`. AD-15 gives the adapter failure translation for *vendor* errors — a missing executable, a refused connection, a 401 — and the shipped adapter already owns the primary version of this check: `RegisterTaggedStreamParser` emits `CorrectionFailed(malformedResponse, …)` for missing or extra tags. What AD-15 does not cover is a provider that satisfies its own transport contract and still breaks AD-3's structural guarantee; any provider can commit that, and the controller is the last point before a `completed` row reaches CAP-7 history. So the controller check is a backstop, not a relocation of AD-15: it maps to `malformedResponse` precisely so a controller-detected breach is indistinguishable in history from the adapter-detected one — the response's *shape* was wrong either way, and analytics over `failure_kind` should not have to know which layer noticed.

**The empty-submit guard tests `trim()`, but submits untrimmed text.** An all-whitespace editor produces exactly the useless sidecar spawn and empty-ish CAP-7 row the ledger entry describes, so the guard is `text.trim().isEmpty`. What gets sent when the guard passes is the user's text verbatim — the guard decides *whether* to run, never *what* to send (CAP-3). `retry()` needs no guard: it replays `submittedText`, which the guard prevents from ever being set to an empty value.

**A failed `save` produces no panel state.** `CorrectionState.failure` is CAP-13's inline error with a Retry, and it means *the correction failed*. A correction that completed and whose history row was lost did not fail — showing an inline error with a Retry would invite the user to re-run a correction that already succeeded, and would burn a second sidecar process. So the loss is an operator concern: it goes to the `Logger`, and the record is not re-issued (AD-7 allows exactly one `save` per terminal event). The corresponding *user-facing* failure, `SettingsState.failure`, exists because a settings write that silently does nothing is a user-visible lie about what CAP-8 and CAP-12 promise.

**A `HotkeyUnavailable` bind retains the prior configured binding.** D-18 makes a structured effective binding authoritative when the backend reports one. An unavailable result means no shortcut remains held and keeps the previous configured value as the restart seed; it does not write a refused request. An X11 rebind refused while the old shortcut still works reports `HotkeyBound` with that old effective binding and refusal feedback. A bound portal result without a structured effective value keeps the submitted binding only as a restart seed, while the screen uses the portal's localized description to report what is active.

**Guarding without awaiting (AD-8).** `PanelController.onHotkeyActivated()` must not `await` before deciding. Attaching a handler to the returned future is not awaiting it — the handler is registered synchronously and the method returns immediately, so CAP-1's 100 ms path is unchanged. The existing "two synchronous `onHotkeyActivated()` calls show then hide" test is what pins this; it must keep passing untouched.

## Verification

**Commands:**
- `dart analyze` -- expected: no issues (AGENTS.md §6 merge gate).
- `dart test` -- expected: all suites pass — the new resilience suite, the extended controller suites, `test/architecture/ad1_import_rule_test.dart`, and every pre-existing infrastructure suite. **Pre-change baseline: 225 passed / 2 skipped**, measured on this story's baseline revision. Note a *pre-existing* flake, unrelated to this story: `single_instance_lock_test.dart`'s "a peer whose line lands after dispose is dropped" failed once under full-suite concurrency and passed on five consecutive isolated runs. If it fails, re-run that file alone before treating it as a regression, and file it rather than fixing it here.
- `dart format --set-exit-if-changed lib test` -- expected: no reformatting needed.
- `grep -rn 'HotkeyRegistration\|BindingAuthority' lib/src/domain/hotkey/global_hotkey.dart` -- expected: both declarations byte-identical to ARCHITECTURE-SPINE.md AD-9.


## Auto Run Result

### 2026-08-07 — First pass

Status: done

**Summary.** The three application controllers now have a failure contract. Every port call inside them is guarded, the `Logger` port is injected into all three, AD-12's `HotkeyUnavailable` is declared as a domain value so a refused bind resolves rather than throws, `SettingsState` carries a modelled failure, and the two contract decisions the controller spec left open — the AD-3 register-set check and the empty-submit guard — are closed in the controller, where they hold for every caller. `test/fakes/` gained failure injection on every port, so future consumers inherit it.

### Completion notes

**What each of the controller spec's 13 "N/A" Error Handling rows now does.** (The Intent said 11 of 13; the file actually has 12 — the CAP-13 row already read "Failure is modelled state, never a throw". Filed as DW-5.)

1. *Toggle shows (CAP-1)* — a rejected `show()` is logged at error level with the error's type only; nothing throws, and the handler is attached to the fired future so AD-8's decision path still awaits nothing.
2. *Second press hides (CAP-14)* — same guard on `hide()`; the toggle stays usable on the next press.
3. *Re-seed on every show (CAP-2, AD-18)* — a throwing `readText()` is logged at warning level and the editor stays `''`. CAP-2's pre-fill is a convenience; the session stays usable.
4. *Run + stream (CAP-5)* — a `correct()` that throws instead of returning a stream takes the normal terminal path as `CorrectionFailed(providerError, …)`, so it is rendered inline and recorded like any other failure.
5. *Completion replaces deltas (AD-3)* — a `CorrectionCompleted` whose registers are not exactly `SuggestionRegister.values` becomes `CorrectionFailed(malformedResponse, …)`; the record written is `failed`, never `completed`.
6. *Failure inline (CAP-13)* — unchanged as modelled state, and a rejected `save` of that record is logged without disturbing the rendered failure or its Retry.
7. *Retry replays captured text (CAP-13, AD-18)* — a rejected subscription `cancel()` is logged and the retry still starts.
8. *New submit cancels (AD-4)* — same cancel guard; a rejected cancel never leaves the new run unstarted.
9. *Hide does not cancel (AD-4, CAP-7)* — a rejected `save` for the late record is logged; the fresh session's state is untouched either way.
10. *Shutdown cancels (AD-4)* — `dispose()` never rethrows: a rejected run cancel, a rejected pending save, and a rejected stream-subscription cancel are each logged and shutdown still completes.
11. *Hotkey change writes through (CAP-12, AD-13)* — a rejected `write` leaves `state.config` as the store's unchanged `current`, sets `SettingsState.failure`, logs, and does not rethrow. A config the store *refuses* as invalid (an `ArgumentError` thrown before any I/O) is reported as `configRejected`, distinct from `configWriteFailed`, so the surface does not claim a write failed when none was attempted.
12. *Advisory on Wayland (AD-10)* — a `HotkeyUnavailable` outcome lands in state as that value with a user-facing message; a `bind()` that *throws* is caught, logged, and lands as `HotkeyUnavailable` plus `hotkeyBindFailed`. The requested binding is still written as the preference either way.
13. *Preset switch writes through (CAP-8)* — identical to row 11, including the `configRejected` split.

**CAP-2 and D-18 supersession (2026-09-26).** The 2026-08-07 completion notes in items 3 and 12 record the old every-show and requested-preference contracts. Generated product SPEC CAP-2 now makes only the first summon and a summon after dismissal new sessions; iconified or focus-lost returns preserve the existing session without a clipboard read. The owner later chose one effective config value: `SettingsController.changeHotkey` writes a structured effective binding when reported, keeps the submitted value only as a restart seed for a bound result without structured read-back, and retains the previous configured binding on unavailability. The Part A and Part B matrices and active Design Note above reflect those decisions. The old completion text remains here as dated provenance, not a current instruction.

**Which `CorrectionFailureKind` a register mismatch maps to, and why.** `malformedResponse`, checked in the controller. AD-15 gives the adapter failure translation for *vendor* errors — a missing executable, a refused connection, a 401 — and the shipped adapter already owns the primary form of this check: `RegisterTaggedStreamParser` emits `CorrectionFailed(malformedResponse, …)` for missing or extra tags. What AD-15 does not cover is a provider that keeps its own transport contract and still breaks AD-3's structural guarantee; any provider can do that, and the controller is the last point before a `completed` row reaches CAP-7 history. So the controller check is a backstop, not a relocation of AD-15 — and it maps to `malformedResponse` precisely so a controller-detected breach is indistinguishable in history from an adapter-detected one. The response's *shape* was wrong either way, and analytics over `failure_kind` should not have to know which layer noticed. The rationale is written into `correction_controller.dart` at the check itself.

**The empty-submit guard is in the controller, and the panel UI story should additionally disable the action.** The invariant lives in `submit()` (`text.trim().isEmpty`), so it holds for every caller including a future keyboard shortcut or tray action; what gets sent when the guard passes is the user's text verbatim. The panel should *also* render the Correct action disabled while the editor trims to empty — a UI affordance on top of the invariant, not instead of it, so the user is not offered an action that silently does nothing. Filed as DW-3.

**Files changed:**
- `lib/src/domain/hotkey/hotkey_bind_outcome.dart` — **new**; sealed `HotkeyBindOutcome` = `HotkeyBound` | `HotkeyUnavailable`, the AD-12 value.
- `lib/src/domain/hotkey/global_hotkey.dart` — `bind` widened to return it, documented as never rejecting; `HotkeyRegistration` and `BindingAuthority` left byte-identical to AD-9.
- `lib/src/domain/logger.dart` — the port doc now states that a caught error's `toString()` may carry bound statement parameters, so only its type may be logged.
- `lib/src/application/correction_controller.dart` — `Logger` injected; `readText`, `correct()`, every subscription `cancel()`, `save` and the visibility stream guarded; non-throwing `dispose()`; empty-submit guard; AD-3 register-set check.
- `lib/src/application/panel_controller.dart` — `Logger` injected; `show`/`hide` failures handled on the fired future without touching AD-8's decision path; activations `onError`; guarded `dispose()`.
- `lib/src/application/settings_controller.dart` — `Logger` injected; both bind arms; a throwing `bind` caught into `HotkeyUnavailable`; write failure and write *rejection* modelled separately without rethrowing; config-stream `onError`; failure cleared by the next successful mutation.
- `lib/src/application/settings_state.dart` — `hotkeyRegistration` → `HotkeyBindOutcome? hotkeyBindOutcome`; new `SettingsFailure` + `SettingsFailureKind`.
- `test/fakes/*.dart` — failure injection on all six port fakes, plus `cancel_failing_stream.dart` so a port stream's `cancel()` can reject.
- `test/application/{correction,panel,settings}_controller_test.dart` — harnesses take the `FakeLogger`; every matrix row covered.
- `test/application/controller_resilience_test.dart` — **new**; each controller's whole lifecycle under `runZonedGuarded` with every port it calls failing.
- `_bmad-output/implementation-artifacts/deferred-work.md` — the three entries this story closes removed; DW-2 … DW-5 and five review defers appended.

**Review findings breakdown.** patch 13 (1 high, 2 medium, 10 low); defer 5 (2 medium, 3 low); reject 6; intent_gap 0; bad_spec 0.

Rejected rather than acted on, with the reason:
- *A circular import between `hotkey_bind_outcome.dart` and `global_hotkey.dart`.* Dart resolves it, and the proposed remedy — splitting `HotkeyRegistration`/`BindingAuthority` into their own file — moves types the spine's Structural Seed explicitly places in `global_hotkey.dart`, deepening the divergence DW-2 already records.
- *Deleting three ledger entries without tombstones breaks the file's append-only rule.* True, but the removal was directed by the invocation intent, and the ledger already carries an entry filing that contradiction against the orchestrator.
- *`_bind` needs a timeout so a portal that never answers cannot hang `changeHotkey`.* The controller spec's own Design Notes treat `bind()` sitting on a portal dialog "for seconds" as normal (AD-11); a timeout would cancel a dialog the user is still using, and no adapter exists yet to hang.
- *`FakeClipboardPort.writeError` is dead scaffolding.* The intent asked for every fake to be tellable to throw on demand; that is the instruction, not an oversight.
- *`fakes_smoke_test.dart` never calls `bind()`, so the Code Map overclaims it as a gate.* It gates compilation of the widened signature, which is what the Code Map says it does.
- *The story's completion-notes acceptance criterion is unmet.* It is met by this section; the reviewer read the file mid-run.

**Follow-up review recommendation:** `true`. Patched this pass: high 1, medium 2, low 10 — a high-severity patch sets it `true` outright, and the score `3×2 + 1×10 = 16` clears the threshold of 5 independently.

**Verification performed:**
- `dart analyze` — No issues found.
- `dart test` — 265 passed, 2 skipped (baseline 225/2, so +40). Includes `test/architecture/ad1_import_rule_test.dart` and every pre-existing suite.
- `dart format --set-exit-if-changed lib test` — 69 files, 0 changed.
- `grep -rn 'HotkeyRegistration\|BindingAuthority' lib/src/domain/hotkey/global_hotkey.dart` — both declarations byte-identical to AD-9.
- Independent probe of the high-severity finding: a `BEFORE INSERT … RAISE(ABORT)` trigger on `corrections` made `DriftCorrectionRepository.save` reject with an error whose `toString()` contained the record's `input_text` verbatim. Re-checked after the fix: `grep -rn "'\$error'" lib/src/application lib/src/domain` returns nothing. **[Corrected by the follow-up pass: this was false when written — that grep returned three matches, all `SettingsFailure(message: '$error')`, and the pattern was in any case too narrow to match the two `': $error'` interpolations in `correction_controller.dart`. Six sites survived. The follow-up pass fixed four of them and filed the remaining pre-existing one; see below.]**
- Matrix test audit: every Part A and Part B row traced to a named test that ran and passed. Three rows were reported unmet on the first audit (the rejected subscription `cancel()` clauses) and were closed by an implementation loopback before review, then a fourth clause (rejected cancel on the *port stream* subscriptions, as opposed to the provider's event stream) was closed during patching.

**Residual risks:**
- The `Logger` leak class is closed at the controller boundary, not at its source. AD-15's last rule — the adapter owns its failure translation and no vendor type escapes the port — is still unmet by `DriftCorrectionRepository`, which lets `SqliteException` through `CorrectionRepository`; that entry stays open in the ledger. The controllers are now safe by construction (they log only `runtimeType`), but any *new* caller of that port inherits the hazard.
- Five findings were deferred rather than fixed: AD-12's unwired tray half, the unbounded `Future.wait(_pendingSaves)` in `dispose()`, the register check counting registers but not content, `PanelController`'s missing post-dispose guard, and the un-deduped clipboard warning. The last four are only reachable once the composition root makes the daemon actually resident.
- `lib/main.dart` is still `void main() {}`, so none of this runs in a real process yet. Every guard is proven against fakes; the first real exercise is story 4.
- The pre-existing flake noted in Verification (`single_instance_lock_test.dart` under full-suite concurrency) did not reappear in any of this run's suite executions.

### 2026-08-07 — Follow-up review pass

Status: done

**Summary.** Follow-up review pass over the story's committed change (`e431b6a..97dc66a`). No intent gap and no spec defect: the failure contract as built matches the intent's reading. Four review layers ran in parallel (adversarial, edge-case, verification-gap, intent-alignment); 26 distinct findings survived deduplication. Thirteen were patched, five deferred, eight rejected. The patches fall into three clusters: raw exception strings that the previous pass's leak fix had relocated from the log into *rendered state*; guards whose recovery path called an unguarded `Logger`, which re-created the unhandled errors the guards exist to prevent; and six mutation-weak tests, including two the previous pass's triage log had claimed were mutation-verified.

**Files changed.**

- `lib/src/application/correction_controller.dart` — user sentence instead of the raw error in the new provider-throw failure; malformed-register message made true of both mismatch shapes; clipboard-read staleness check moved ahead of its warning; every log call routed through the new `_log` swallow.
- `lib/src/application/panel_controller.dart` — same `_log` swallow on all three log sites.
- `lib/src/application/settings_controller.dart` — a user sentence per `SettingsFailureKind` instead of `'$error'`; a successful mutation now clears only failures it could itself have fixed (`_survivingBindFailure`); same `_log` swallow.
- `lib/src/application/settings_state.dart` — dead `copyWith` deleted, its reasoning moved onto the `failure` field's doc.
- `test/fakes/throwing_logger.dart` — **new**; a `Logger` whose every method throws, standing in for a daemon whose stderr became a broken pipe.
- `test/fakes/echoing_error.dart` — **new**; the shared error whose `toString()` carries its payload, so a leak test can tell a logged *type* from a stringified error.
- `test/fakes/fake_correction_repository.dart` — `saveGate`, so a test can hold a history write open across `dispose()`.
- `test/application/correction_controller_test.dart` — shutdown-waits-for-a-pending-write; superseded clipboard read is not reported; rendered-message and log-context assertions; throwing-logger case.
- `test/application/settings_controller_test.dart` — bind-outcome carry-forward across both rewritten transitions; a preset switch does not retire a hotkey failure; every rendered failure is a sentence; leak test; log-context assertion; throwing-logger case.
- `test/application/panel_controller_test.dart` — hide failure names `hide`; leak test; throwing-logger case.
- `test/application/controller_resilience_test.dart` — named per-guard log assertions replacing the vacuous `isNotEmpty`; panel scenario reordered so the hide arm and the cancel guard are actually reached.
- `_bmad-output/implementation-artifacts/deferred-work.md` — five new entries appended; no existing entry touched.

**Review findings breakdown.** 13 patches applied (0 high, 6 medium, 7 low). 5 deferred (1 high, 3 medium, 1 low): the `SettingsController` mutation-generation race (pre-existing, verified against `e431b6a`); `PanelController`'s missing `_disposed` guard on the stream path; `_write`'s `on ArgumentError` swallowing programmer errors as `configRejected`; the pre-existing stream-error message that still renders a raw error; and the WM-latency double-press race. 8 rejected, the notable ones being a request to add `status:` to existing ledger entries (the invocation forbids modifying them), a proposal to hoist `_errorContext` into a shared helper with a grep-based architecture gate (the testable half was addressed instead), and four intent-alignment items describing divergences the story had already documented and filed.

**Follow-up review recommendation:** `true`. Patched: 0 high, 6 medium, 7 low → score `3×6 + 1×7 = 25`, at or above the threshold of 5.

**Verification performed.**

- `dart analyze` — no issues.
- `dart test` — **282 passed / 2 skipped** (265/2 before this pass, 225/2 at the story's baseline). The pre-existing `single_instance_lock_test.dart` flake did not reproduce.
- `dart format --set-exit-if-changed lib test` — clean.
- `grep -rn 'HotkeyRegistration\|BindingAuthority' lib/src/domain/hotkey/global_hotkey.dart` — both declarations still byte-identical to AD-9.
- **Mutation verification** — every patch was pinned by reverting it on a scratch copy and confirming the suite goes red: the `_log` swallow (all three controllers), both raw-`$error` shapes, the surviving bind failure, both `hotkeyBindOutcome` carry-forwards, the pending-save wait, the clipboard staleness check, the malformed-register wording, the `hide` action string, and the settings and panel `_errorContext` guards. Twelve of twelve killed. One test (the superseded clipboard read) failed to kill its mutation on the first attempt, was found not to reach the guarded branch at all, and was rebuilt until it did.

**Residual risks.**

- The `_log` swallow is a real silent catch. It is bounded to the logger's own failure, and the `ThrowingLogger` tests assert the guards still *attempt* to report, but a logger failing in production leaves no trace by construction.
- The deferred `SettingsController` race is `high` severity and unfixed: overlapping hotkey changes still resolve last-completion-wins, writing the superseded combination to config. It is pre-existing and needs a generation guard, which is a design decision outside this story's failure contract.
- The whole contract remains unreachable in a running process: `lib/main.dart` is still `void main() {}`, `StderrLogger` has no caller outside its own test, and `GlobalHotkey`/`PanelVisibility`/`ClipboardPort` have no implementations — so every guard here is proven against fakes only. The composition-root story is what will first exercise them for real.

### 2026-08-07 — Review pass (third)

Status: done

**Summary.** Third review pass over the story's committed change (`e431b6a..f02286b`). No intent gap and no spec defect. Four layers ran in parallel (adversarial, edge-case, verification-gap, intent-alignment); 33 findings survived deduplication — 15 patched, 4 deferred, 10 rejected. The patches fall into two clusters. The first is **four real post-shutdown and cross-mutation defects**, each reproduced by probe before it was touched: an unguarded `isVisible` that put two unhandled errors per press into the daemon's zone, a torn-down correction controller still issuing clipboard IPC, a torn-down settings controller still writing the config file and binding hotkeys, and a settings banner that cleared while the user's change remained unsaved. The second is the **per-site half of the previous pass's own verification claims**: `_log` and `_errorContext` were verified by mutating the shared helper, which is a weaker property than the sites adopting them — 7 of 17 swallow sites and 6 of 14 context sites could each be bypassed individually with the suite green.

One reported finding was **rejected after being partly implemented**: a post-shutdown `CorrectionRepository.save`. A guard was written for it, then mutation testing showed the guard unkillable. A direct probe established why — a `StreamController` whose `onCancel` throws still cancels the subscription and delivers nothing further — so the defect does not reproduce and the guard was dead defence. Both were removed and replaced with a test that pins the invariant `dispose()` actually relies on.

**Files changed.**

- `lib/src/application/panel_controller.dart` — `_visibleNow()` guards the visibility mirror on the decision path.
- `lib/src/application/correction_controller.dart` — `_disposed` guard on the visibility-event path; class doc qualified to exclude construction; `_log`/`_errorContext` doc summaries unswapped; `dispose()` records why the terminal-event path needs no guard.
- `lib/src/application/settings_controller.dart` — `_disposed` guard on both mutations and in `_setState`; `_failedMutation` + `_resolveFailure` replace `_survivingBindFailure`; the AD-12 warning logs the outcome type instead of the adapter's message.
- `test/fakes/fake_panel_visibility.dart` — `isVisibleError`, the seam the mirror guard needs.
- `test/fakes/fake_clipboard_port.dart` — `readCalls`, the only observable for a session that should never have begun.
- `test/fakes/fake_config_store.dart` — `rejectError`, so the refusal path can carry a payload a leak test can see.
- `test/fakes/echoing_error.dart` — `EchoingArgumentError`, the `ArgumentError` shape of the echoing double.
- `test/application/panel_controller_test.dart` — mirror guard, direct and via the activations stream; leak and throwing-logger cases extended to the mirror and the teardown; the cancel line's message asserted.
- `test/application/correction_controller_test.dart` — post-shutdown visibility event; the `_finish` cancel guard; per-subscription cancel labels; lost-history context by value; empty-submit message; the shutdown half of the clipboard staleness check; a second throwing-logger case for the four sites the first never reached; leak test extended to the stream and cancel paths; migrated to the shared `EchoingError`.
- `test/application/settings_controller_test.dart` — failure ownership in both directions plus its own clearing case; post-dispose mutations; a bind resolving after shutdown; the AD-12 warning's message and context; `HotkeyUnavailable.message` non-empty; a second throwing-logger case; leak test extended to the teardown and given an error the refusal path can actually leak.
- `test/application/controller_resilience_test.dart` — rejected cancels armed in all three scenarios, the mirror failure added to the panel case, and every new guard named in the per-guard log assertions.
- `_bmad-output/implementation-artifacts/deferred-work.md` — four new entries appended; no existing entry read, modified, or re-opened.

**Review findings breakdown.** 15 patches applied (0 high, 4 medium, 11 low). 4 deferred (3 medium, 1 low): the bind-before-write divergence, the unbounded `_ownWrites` growth, `_save`'s over-broad catch as the twin of the already-filed `_write` one, and an unconfirmed second suite flake. 10 rejected, the substantive ones being the post-shutdown save (probed, does not reproduce), a request to add `status:` to existing ledger entries (the invocation forbids touching them, and step-04 prescribes the bullet format the sweep migrates), guarding the constructors' port calls (a startup failure should be one), and five intent-alignment items describing divergences the story had already documented and filed.

**Follow-up review recommendation:** `true`. Patched: 0 high, 4 medium, 11 low → score `3×4 + 1×11 = 23`, at or above the threshold of 5.

**Verification performed.**

- `dart analyze` — no issues.
- `dart test` — **296 passed / 2 skipped** (282/2 before this pass, 225/2 at the story's baseline), stable across **9 consecutive full-suite runs**. Neither flake reported by a review lens reproduced — not the documented `single_instance_lock_test.dart` one, nor the newly alleged `claude_agent_sdk_correction_provider_test.dart` one, which is filed as unconfirmed.
- `dart format --set-exit-if-changed lib test` — 71 files, 0 changed.
- **Mutation verification.** Every patch was pinned by mutating it and confirming the suite goes red, each run against a confirmed-green baseline and any contaminated result re-run — a lens reported that the repo's known flake had given it two false "killed" verdicts, so single-run evidence was treated as inadmissible. Ten targeted guard mutations killed (the mirror guard, both `_disposed` guards, `_setState`, the failure-ownership rule, the AD-12 log context, the empty-submit message, the `$what` label, and two lost-history context values), plus a **full per-site battery: 17 of 17 `_log` swallow sites and 14 of 14 `_errorContext` sites**, mutated one at a time. Two batteries were run twice after test-side fixes, and one intermediate result was discarded as contaminated by a compile error. The one mutation that survived everything — the post-shutdown terminal-event guard — was investigated rather than papered over, and the code it defended was deleted.

**Residual risks.**

- The four deferred entries are unfixed, and three are `medium`. The bind-before-write divergence is the one a user could actually notice: the shortcut changes for the session, the surface says nothing was saved, and the change is gone at the next launch.
- The mid-shutdown window — a run terminating while `dispose()`'s cancel is still in flight, which CAP-7 promises to retain — is reasoned about in `dispose()`'s comment and covered by the pending-write test, but the exact interleaving is not pinned by a test of its own; it needs a cancel that can be parked, which no fake currently offers.
- Unchanged from the previous passes: the `_log` swallow is a real silent catch, bounded to the logger's own failure; and none of this runs in a real process yet — `lib/main.dart` is still `void main() {}`, and `GlobalHotkey`, `PanelVisibility` and `ClipboardPort` still have no implementations, so every guard here is proven against fakes only. Three of the seven port calls the Intent names by method have no adapter at all, so for those the failure shape defended and the failure shape tested share one author.
