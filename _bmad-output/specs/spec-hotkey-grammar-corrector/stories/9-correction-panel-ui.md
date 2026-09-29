---
title: 'Correction panel UI'
type: 'feature'
created: '2026-08-11'
status: 'done'
baseline_revision: 'a81802a1587d5fc4e920e1e2019846fd5616c108'
final_revision: 'e3033fc'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md'
  - '{project-root}/lib/src/application/correction_controller.dart'
  - '{project-root}/lib/src/application/correction_state.dart'
  - '{project-root}/lib/src/application/composition/controller_providers.dart'
  - '{project-root}/lib/src/application/composition/port_providers.dart'
  - '{project-root}/lib/src/ui/daemon_app.dart'
warnings: ['oversized']
---

<intent-contract>

## Intent

**Problem:** Every port, controller and adapter behind the panel now runs in a real daemon, and there is still no panel: `DaemonApp`'s home is a `SizedBox.shrink()`. Eight capabilities have no surface at all — the clipboard pre-fill (CAP-2), the micro-editor (CAP-3), the three labelled register variants and their 1/2/3 keys (CAP-4), the streaming partials (CAP-5), the original beside the variants (CAP-10), the per-suggestion copy (CAP-11), the inline error with Retry (CAP-13), and CAP-14's stay-open-after-copy half. The empty-submit invariant story 3 put in the controller also still has no affordance: the user can press an action that logs one line and does nothing (DW-3).

**Approach:** Build `lib/src/ui/panel/` over the existing `CorrectionController` — the panel reads its state and calls its methods, and owns nothing but its own ephemeral UI (a text field, focus nodes, scroll positions). Two members the house rules force *out* of the widgets are added to the controller and its state: selection (the "State mutation" convention makes the controller the single owner of a surface's state, and AD-18's clear-on-show then comes free) and the copy action (AGENTS.md §3 forbids clipboard access inside a widget class). Everything the panel promises is proven headless with `flutter test`.

## Boundaries & Constraints

**Always:**
- AD-1: `lib/src/ui/**` imports `application/`, `domain/` read-only types, and Flutter — never `infrastructure/`. This is the first ring the AD-1 gate does not check; it gains a third rule here.
- AD-6: the panel's top-to-bottom order **is** `SuggestionRegister.values`, and the selecting key **is** `SuggestionRegister.values.indexOf(r) + 1`. Neither the count, the order nor the labels may be written out by hand; the labels derive from `.name`.
- AD-2: `SuggestionRegister`, `Suggestion`, `CorrectionEvent` and `CorrectionFailureKind` are read as they are. The panel does not reshape them and does not add a UI-side mirror of them.
- AD-3: partials render per register as the controller accumulates them (deltas arrive in any order and interleaved), and `CorrectionCompleted` **replaces** whatever was accumulated. Nothing copyable or selectable is ever taken from a partial — see Design Notes.
- AD-18: the controller already re-seeds on every show; the panel must render that re-seed rather than holding its own copy of the text. Retry replays the captured `submittedText`. The panel stays open after a copy and every variant stays copyable. Selection highlights and never copies.
- AD-4: no widget path cancels an in-flight correction. The panel has no close control and never calls `PanelVisibility.show()`/`hide()` — AD-8's toggle owns visibility, and the window the widgets live in is shown and hidden underneath them.
- Consistency Conventions "State mutation": immutable state with `copyWith`, one controller per surface, widgets mutate only their own ephemeral UI concerns.
- AGENTS.md §3 and §6: one public type per file, `build()` pure and cheap, named widget classes rather than `_buildFoo()` helpers, every controller/subscription/focus node disposed, no `!`, no `late` as a lifecycle workaround, exhaustive switches over the sealed types.
- Story 3's failure contract extends to the two new controller members: the clipboard write is guarded, its failure reaches the `Logger` through the existing `_log` swallow with `_errorContext` (type only), and no log line or context value ever carries editor text, clipboard content or a suggestion body.
- CAP-13 is inline: the error replaces the empty or half-streamed suggestions inside the panel, with a Retry beside it. No `SnackBar`, no `showDialog`, no second window — anywhere in this story.
- CAP-10 holds at a small surface: the original and at least one variant are both readable without either being scrolled out of view.
- Every test name cites the CAP or AD id it defends. Widget tests are headless (`flutter test`); the controller-level additions are also covered binding-free (`dart test`).

**Block If:**
- Delivering CAP-4's 1/2/3, CAP-11's copy or CAP-5's partials would require editing `SuggestionRegister`, `Suggestion`, `CorrectionEvent` or `CorrectionFailureKind` — those are AD-2 verbatim and cannot be rewritten unattended. Reading them, and adding state *beside* them in the application ring, is in scope.
- Resolving DW-30 (a `restore`-sourced `true` re-seeds and so discards what the user typed) or DW-35 (`show()`'s future cannot say whether the window moved) would require editing the `PanelVisibility` port. Both are domain renegotiations. This story **decides them deliberately without editing the port** (Design Notes) and records the decision; if a decision here turns out to need the port widened, that is the halt.
- The delegated keyboard decisions (focus order, the digit shortcuts' scope, a submit accelerator) cannot be made without contradicting a SPEC line.

**Never:**
- No settings surface (story 10), no tray wiring, no hotkey code, no prompt or preset wording (SPEC puts output-quality tuning out of scope).
- No window geometry and no new `window_manager` call anywhere: `test/architecture/hidden_window_test.dart` gates the startup path and the adapter's call allowlist, and panel window sizing is neither this story's nor that test's to change. File it instead.
- No toast, snackbar, dialog, tooltip-as-error or second route for any message this story renders.
- No new package dependency and no pubspec change.
- No `Escape`-to-hide and no UI-initiated visibility call of any kind.
- No diff view, no history view, no analytics — SPEC non-goals, and "it was easy while I was in there" is explicitly ruled out.
- Do not delete or close any deferred-work entry. Append new ones, including the resolvability of DW-3, as story 3 did with DW-4.
- No change to `PanelController`, `SettingsController`, `SettingsState` or any existing controller behaviour beyond the two additive members named in Tasks.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Re-seed renders (CAP-2, AD-18) | Clipboard holds `'i has went'`; visibility goes true | The editor shows `'i has went'`; no correction runs | A clipboard read that throws leaves the editor empty and the panel usable (controller guard, already covered) |
| Editing reaches the controller (CAP-3) | User types into the editor | `CorrectionController.state.editorText` is what was typed; a later submit sends exactly that | No error expected |
| A second show replaces the editor (AD-18) | Text typed, hide, clipboard changes, show | The editor shows the *new* clipboard text; no suggestion, error or selection survives | No error expected |
| Correct is disabled while blank (DW-3, CAP-3) | Editor empty, or only spaces/newlines | The Correct action is disabled; pressing it is impossible and the provider is never called | Not a failure: the controller's invariant still holds for every other caller |
| Partials render as they arrive (CAP-5) | Deltas for `shorter`, then `formal`, then `shorter` again | Each register's row shows its own concatenation, in `SuggestionRegister.values` order | No error expected |
| Completed replaces partials (AD-3, CAP-4) | Deltas, then a `CorrectionCompleted` with different text | Every row shows the completed text; nothing from the deltas remains | A completed event with a malformed register set never reaches the panel as suggestions (controller guard) |
| Order and keys come from the enum (AD-6, CAP-4) | A completed correction | Row *n* is `SuggestionRegister.values[n]`, and its key hint reads `indexOf + 1` | A register with no digit key (index ≥ 9) renders with no key hint rather than a wrong one |
| Digit selects, never copies (CAP-4, AD-18) | Completed; suggestions focused; `2` pressed | The second row is highlighted; the clipboard is untouched | No error expected |
| Digits are inert in the editor (CAP-3) | Editor focused; `2` typed | `'2'` is inserted into the text; no row is highlighted | No error expected |
| Digits are inert while running (AD-3) | Streaming partials; `1` pressed | Nothing is highlighted — there is nothing authoritative to select | No error expected |
| Copy places exactly that text (CAP-11) | Completed; the `casual` row's copy button pressed | `ClipboardPort.writeText` receives the `casual` suggestion's completed text, once | A rejected write logs at error level (type only) and shows one inline notice; the panel stays open |
| Every variant stays copyable (CAP-14, AD-18) | Copy `formal`, then copy `shorter` | Both writes happen, in that order; the panel is still showing all three and is never hidden | A failed first copy does not disable the second |
| Copy is unavailable while running (AD-3) | Streaming partials | No copy button is enabled — a partial is not the record of truth | No error expected |
| Inline error replaces partials (CAP-13) | Deltas, then `CorrectionFailed` | The message renders inside the panel with a Retry beside it; the half-streamed rows are gone; no dialog or snackbar exists in the tree | The message is the failure's own text; nothing else is rendered from it |
| Retry replays the captured text (CAP-13, AD-18) | Type `'a'`, submit, type `'b'`, fail, press Retry | The provider is called a second time with `'a'` | No error expected |
| Original and a variant together (CAP-10) | A long original and long suggestions on a 480×360 surface | The editor and the first variant are both on screen with non-zero height; neither is scrolled out of view; no overflow is reported | A surface too small to satisfy it must fail the test, not silently clip |
| Selection survives typing, dies with the session (AD-18) | Select row 2, then type in the editor; then a new show | The highlight persists through typing; it is gone after the show | No error expected |

</intent-contract>

## Code Map

- `lib/src/ui/daemon_app.dart` -- the `SizedBox.shrink()` home this story replaces with the panel; its doc's "the panel replaces this home in its own story" is that promise.
- `lib/src/ui/panel/` -- **new**; every widget in this story. The spine's Structural Seed reserves it for "original + 3 variants + inline error".
- `lib/src/application/correction_controller.dart` -- the surface's owner. Read `submit`, `retry`, `editText`, `state`, `changes`; add `selectSuggestion` and `copySuggestion` beside them, guarded the way every other port call in the file is (`_log`, `_errorContext`).
- `lib/src/application/correction_state.dart` -- gains `selectedRegister` and `copyFailure`; `copyWith`'s "cannot clear" doc covers both, so the transitions that drop them keep building state directly.
- `lib/src/application/composition/controller_providers.dart`, `port_providers.dart` -- the seams the panel reads the controller through, and the seven overrides a widget test has to supply.
- `lib/src/domain/correction/suggestion_register.dart` -- AD-6's order and key mapping; `.name` is the label source.
- `lib/src/domain/correction/correction_event.dart` -- `CorrectionFailed.message` is CAP-13's inline text; the panel renders it and adds nothing.
- `lib/src/domain/clipboard/clipboard_port.dart` -- `writeText` is CAP-11's destination, reached only through the controller.
- `test/fakes/fake_clipboard_port.dart`, `fake_correction_provider.dart`, `fake_panel_visibility.dart`, `fake_correction_repository.dart`, `fake_clock.dart`, `fake_logger.dart` -- the fakes a widget test overrides the port seams with; `FakeCorrectionProvider.manual()` is what makes streaming and failure timing the test's to drive.
- `test/architecture/ad1_import_rule_test.dart` -- two ring rules today; the `ui` rule goes in beside them.
- `test/application/correction_controller_test.dart`, `test/application/state_equality_test.dart` -- where the two new members and the two new state fields are covered binding-free.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- DW-3 (this story's follow-through), DW-30 and DW-35 (decided here, port untouched), DW-29 (`test/ui/` lands in the same `flutter test`-only position as `test/platform/`).

## Tasks & Acceptance

**Execution:**
- `lib/src/application/correction_state.dart` -- add `SuggestionRegister? selectedRegister` (AD-18's highlight, never a copy) and `String? copyFailure` (a rejected CAP-11 write, kept out of `failure` because that field is CAP-13's *correction* error and its assert ties it to `status`); extend `copyWith`, `==` and `hashCode` -- a state consumer that cannot see the highlight cannot render it, and identity equality would make every dedupe pointless.
- `lib/src/application/correction_controller.dart` -- add `void selectSuggestion(SuggestionRegister)`: a no-op unless the session is `completed` and that register has text, so nothing selectable can come from a partial (AD-3); add `Future<void> copySuggestion(SuggestionRegister)`: writes exactly that register's completed text through `ClipboardPort.writeText`, clears any previous `copyFailure` on success and sets a user sentence on rejection, guarded and logged type-only, never throwing -- CAP-11 must not be a silent lie, and AGENTS.md §3 keeps the clipboard out of the widgets.
- `lib/src/ui/panel/correction_panel.dart` -- **new** `CorrectionPanel`: reads the controller off the graph, renders its `state` and `changes`, and owns the `Shortcuts`/`Actions` for the digit keys and the submit accelerator -- one surface, one owner.
- `lib/src/ui/panel/original_text_pane.dart` -- **new** `OriginalTextPane`: the CAP-3 micro-editor (its own `TextEditingController` and `FocusNode`, synced from `state.editorText` without stealing the caret) and the Correct action, disabled while the text trims to empty (DW-3).
- `lib/src/ui/panel/suggestion_list.dart` -- **new** `SuggestionList`: one card per `SuggestionRegister.values`, in that order, in its own scrollable so CAP-10 holds.
- `lib/src/ui/panel/suggestion_card.dart` -- **new** `SuggestionCard`: the key hint from `indexOf + 1`, the label from `.name`, the register's text (partial while running, authoritative once completed), the copy button, and the selected highlight.
- `lib/src/ui/panel/correction_error_notice.dart` -- **new** `CorrectionErrorNotice`: CAP-13's inline message plus Retry, rendered in place of the variants.
- `lib/src/ui/daemon_app.dart` -- make `CorrectionPanel` the home and give the app a theme; update the doc, which currently promises exactly this.
- `test/architecture/ad1_import_rule_test.dart` -- add "AD-1: `lib/src/ui/**` never imports infrastructure", with the same checker-level positive and negative cases the other two rules have -- the ring gate is mechanical or it is nothing (AD-1).
- `test/ui/panel_harness.dart` -- **new**; pumps `DaemonApp` inside a `ProviderScope` overriding all seven port seams with the existing fakes, and exposes them plus a small `pumpSession()` that drives the visibility fake -- every widget test in this story starts from the same wiring.
- `test/ui/panel/correction_panel_editor_test.dart` -- **new**; the re-seed, typing, the second show, the disabled Correct action, the submit accelerator, and where focus is at each step.
- `test/ui/panel/correction_panel_streaming_test.dart` -- **new**; interleaved and out-of-order partials, the completed replacement, and the AD-6 order derived from the enum rather than asserted per name.
- `test/ui/panel/correction_panel_selection_and_copy_test.dart` -- **new**; digits highlight and never copy, digits inert in the editor and while running, per-suggestion copy text, both-variants-copyable with the panel still open, copy unavailable while running, and the rejected-write notice.
- `test/ui/panel/correction_panel_error_test.dart` -- **new**; the inline error replacing half-streamed rows, the absence of any dialog or snackbar in the tree, and Retry replaying the captured text.
- `test/ui/panel/correction_panel_layout_test.dart` -- **new**; CAP-10 at a small surface with long text, asserting both rects and no overflow.
- `test/application/correction_controller_test.dart` -- add the `selectSuggestion`/`copySuggestion` rows binding-free: the partial-state no-ops, the exact text written, the failure guard, and that nothing sensitive reaches the log.
- `test/application/state_equality_test.dart` -- add rows for the two new fields, following the file's existing `expectSameValue` convention.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- append: DW-3 is resolvable (the affordance shipped), the DW-30 and DW-35 decisions with their reasoning, the panel window geometry gap, and anything review turns up. Do not edit or remove existing entries.

**Acceptance Criteria:**
- Given the daemon's provider graph with fake ports, when the panel is pumped and a session is driven from show through typing, submit, partials, completion, selection and two copies, then every assertion above holds in one headless `flutter test` run with no skipped widget test.
- Given `SuggestionRegister` were reordered or extended, when the panel renders, then the row order and the key digits follow the enum without a source edit — proven by deriving both from `SuggestionRegister.values` in the tests rather than by naming `formal`, `casual`, `shorter` positionally.
- Given `dart analyze`, the binding-free `dart test` command, `flutter test`, `dart format --set-exit-if-changed lib test` and `flutter build linux --debug`, when all five run, then all pass, `test/architecture/ad1_import_rule_test.dart` is green with its new third rule, and no pre-existing test regresses.
- Given the story's completion notes, when it finishes, then they state the keyboard-focus order and digit-shortcut scope that were chosen, the DW-30 and DW-35 decisions, why selection and copy live in the controller, and what was **not** observed here for want of a display.

## Spec Change Log

## Review Triage Log

### 2026-08-11 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 24: (high 1, medium 7, low 16)
- defer: 1: (high 0, medium 0, low 1)
- reject: 4: (high 0, medium 0, low 4)
- addressed_findings:
  - `[high]` `[patch]` **The panel never focused the editor after the first summon, and swallowed the first keystroke.** `autofocus: true` fires once when the `TextField` mounts, and AD-8 keeps the tree built for the daemon's life — so after any session that submitted, focus was still parked on the suggestions region. Probed independently by three layers: on the second show `editor.hasFocus == false`, and a key sent without a click left `editorText` unchanged, with the digit shortcuts live but `selectSuggestion` a no-op in `idle`. That falsified the panel's own doc comment, this story's keyboard design note and CAP-1's "visible **and** focused" for the ordinary summon → correct → copy → hide → summon flow. The panel now owns the editor's `FocusNode` and re-requests it when a session resets; the second-show test asserts focus and that a keystroke with no tap reaches the controller. Mutation-verified.
  - `[medium]` `[patch]` A stale clipboard write reported the wrong verdict, in both directions: `copySuggestion`'s only guard was the *session* token, which cannot order two copies inside one session, and no copy button is disabled while a write is in flight. Probed: a slow failing copy resolving after a fast successful one left a false "could not be copied" notice over a clipboard holding the good text; the reverse cleared the notice while the clipboard held a different variant — the exact silent lie `copyFailure` was added to prevent. A per-copy token now decides whose outcome renders. Two rows, both orders.
  - `[medium]` `[patch]` The same guard was per session rather than per run, so a rejection landing after a `submit()` painted its notice onto the *new* run and `_onCompleted`'s `copyWith` carried it into the new completed state — a copy failure beside variants the user never tried to copy. `_startRun`'s dropping of `copyFailure` was also unpinned (preserving it left the suite green), while the sibling property for the highlight did have a test. The copy token is now invalidated by a new run and a new session; both rows added.
  - `[medium]` `[patch]` **The new AD-1 ui rule could not fail on what its own docstring said it existed to fail on.** The import checker allowlisted every `package:flutter/` URI, so `services.dart` was permitted: probed by adding `Clipboard.setData(...)` and a raw `SystemChannels.platform.invokeMethod('Clipboard.setData', …)` to the panel, and separately a ui widget holding `const MethodChannel(...)` and `dart:io` `File`/`Platform` — `dart analyze` clean and all 17 AD-1 rows green in both cases, with the story's `grep` empty. A widget could bypass `ClipboardPort`, the controller, the failure notice and the logging convention with the gate reporting success. A symbol-level rule over `lib/src/ui/**` now bans `MethodChannel`, `EventChannel`, `SystemChannels`, `Clipboard.`, `clipboardProvider` and `panelVisibilityProvider` (the last for AD-4/AD-8, which the import surface also cannot see), with four checker self-tests; the docstring now claims only what the code checks.
  - `[medium]` `[patch]` `CorrectionStatus.running` was never rendered — between the submit and the first delta the panel was byte-identical to a fresh idle session, in the one state CAP-1's panel guarantees the user sits in. A user seeing nothing presses Correct again, which under AD-4 cancels and restarts the run they were waiting for. Added a real progress affordance (not placeholder text, which the SPEC forbids), present from submit through the deltas and gone at either terminal event.
  - `[medium]` `[patch]` The `1`/`2`/`3` hint was printed unconditionally while `selectSuggestion` no-ops unless the session completed and the register has text — DW-3's "an action that silently does nothing" re-created for selection while being fixed for submit and copy. The hint is now dimmed whenever its key would do nothing, driven by the same predicate as the copy button.
  - `[medium]` `[patch]` `Ctrl+Enter` stayed live in the suggestions region, so pressing it there cancelled a completed correction and re-ran it, discarding the answer, the highlight and any notice, with no test. The accelerator is now scoped to the editor subtree, the way the digit shortcuts are scoped to the suggestions region.
  - `[medium]` `[patch]` `_canCorrect` short-circuited ahead of `submit()`, making the controller's empty-editor invariant unreachable from the UI and pinning the two `trim()` predicates to agree by nothing — against the intent's "on top of it, not instead of it". `_correct()` now always calls `submit()`; the disabled button is the affordance and the controller's guard is the invariant, with a row asserting the accelerator on a blank editor reaches the controller's own info line.
  - `[low]` `[patch]` The copy buttons had no tooltip or semantic label — three visually identical unlabeled buttons, so CAP-11's "each suggestion has its own button" was unusable non-visually — and the CAP-13 test's `Tooltip findsNothing` turned the fix into a test regression. Tooltips added; that assertion removed with a note that CAP-13 names a toast, a dialog and a separate window, not a tooltip. The SnackBar/Dialog/AlertDialog assertions stay.
  - `[low]` `[patch]` The `copyFailure` notice had no live region and sat between the two `Expanded` panes, so its arrival re-flowed CAP-10's split at the window size nobody has measured (DW-50). Wrapped in a live region and moved inside the suggestions region; a layout row asserts the editor's rect is unchanged by the notice.
  - `[low]` `[patch]` There was no way to deselect: the same digit twice left the highlight and `copyWith` cannot clear it, so a mis-hit was unrecoverable for the session (and DW-52 records that a pointer cannot select at all). The digit now toggles.
  - `[low]` `[patch]` The panel's cross-ring `changes` subscription had no `onError`/`onDone`, while `CorrectionController` installs exactly that backstop for `PanelVisibility.changes` and documents why. Both arms added with the decision written down. Honest limit: only `onDone` has a regression guard — nothing can push an error onto the controller's own broadcast stream without a seam this story did not add.
  - `[low]` `[patch]` The CAP-10 layout test bounded the label and hint on both edges but never bounded the variant *text*'s bottom, and `getRect` is global — so a built-but-scrolled child satisfied the file's headline claim. Now measured as a visible band.
  - `[low]` `[patch]` `FakeClipboardPort` awaited `writeGate` before reading `writeError`, so a gated write's outcome was whatever the field held at completion time and two concurrent writes could not be given different outcomes — which is why the copy-ordering defect shipped unpinned. Both are captured at call time now.
  - `[low]` `[patch]` `DaemonApp` shipped the DEBUG ribbon into the `--debug` artifact the acceptance criteria require, painted over a small panel, and was light-only so the panel flashed white over a dark desktop on every summon. Banner off, dark scheme added, `themeMode: ThemeMode.system`.
  - `[low]` `[patch]` `CorrectionErrorNotice` put an `Expanded` in its own `Column`, so it threw at layout outside a bounded-height parent with the precondition written nowhere. Rebuilt so it no longer needs one, pinned by a row pumping it in an unbounded parent.
  - `[low]` `[patch]` RenderFlex overflow below ~220 px of height, probe-confirmed (clean at 480×240, 0.8 px over at 220, 8.8 px at 200, failing outright smaller), and nothing sets a window size or minimum size, so a user can resize into it. A documented minimum-height floor now splits at or above it and scrolls as a whole below it; two rows at 480×160, for the variants and for the inline error.
  - `[low]` `[patch]` A whitespace-only variant was copyable and selectable: both gates used `text.isEmpty` while `submit()` uses `trim().isEmpty`, so `'   \n '` rendered an enabled button, wrote whitespace over the user's clipboard and accepted its digit. Both gates now trim.
  - `[low]` `[patch]` Numpad digits selected nothing, since the activators came only from the digit row. `numpad1`..`numpad9` were checked in `keyboard_key.g.dart` to be contiguous the way `digit1`..`digit9` are, and a second activator per slot was added. Stated limit: with Num Lock off the keypad reports navigation keys, which the test key simulator does not model.
  - `[low]` `[patch]` CAP-4's highlight was never asserted as *rendered* — deleting the card's `color:` line left all 34 widget rows and all 79 controller/equality rows green, because every "highlight" assertion read the parameter the panel passed in. A rendered-colour row now kills that mutation.
  - `[low]` `[patch]` `_clearCopyFailure`'s hand-enumerated state rebuild was unpinned: dropping `selectedRegister` from it was green, and the only sequence that catches it — select, failed copy, successful copy — was in no test. Added; mutation-verified.
  - `[low]` `[patch]` The controller's own empty-text guard was unpinned: removing it was green, because the empty-variant test asserts `IconButton.onPressed`, which the card decides for itself, and the selection path has no widget-side fallback. Two controller rows added, for copy and for select.
  - `[low]` `[patch]` Nothing recorded what a real desktop still owes this story. `test/platform/correction_panel_live_test.dart` follows the form stories 5–8 used — a `fail()` body, an unconditional skip, and an explicit reason naming the five owed claims. It reports as skipped, never as passed.
  - `[low]` `[patch]` Ledger entries earned by this pass appended (DW-53 … DW-55), with no existing entry edited or closed.

### 2026-08-11 — Follow-up review pass

- intent_gap: 0
- bad_spec: 0
- patch: 12: (high 0, medium 6, low 6)
- defer: 3: (high 0, medium 2, low 1)
- reject: 12: (high 0, medium 2, low 10)
- addressed_findings:
  - `[medium]` `[patch]` **`minimumPanelHeight` claimed CAP-10 at a height where the original was a 7-pixel sliver.** The floor was measured against "no overflow", not against "both readable": probed at 480×240 the editor's flex share is **7.2 px**, and the class doc asserted CAP-10 holds at and above it. The floor is now 300 — probe-measured as where the editor first clears one full line of its 16 px text (7.2 px at 240, 15.2 at 260, 23.2 at 280, 31.2 at 300) — the doc says what was measured against which claim, and a new layout row asserts CAP-10's visible bands at *exactly* the floor rather than only at 480×360. Mutation-verified: reverting the constant to 240 fails that row.
  - `[medium]` `[patch]` **Key auto-repeat was not excluded from either shortcut map.** `SingleActivator.includeRepeats` defaults to `true`, and this story made selection a *toggle*, so a held digit flipped the highlight once per repeat event and settled on the release's parity. Both maps are now `includeRepeats: false`. The digit row is mutation-verified. The accelerator's row had to be rewritten mid-pass: asserted on a submitted run it was vacuous, because a submit hands focus to the variants and the accelerator is scoped to the editor subtree, so the repeats were already out of scope — it now asserts on a blank editor, where focus stays put, that one held press produces exactly one refusal line instead of four. That version is mutation-verified.
  - `[medium]` `[patch]` **The new AD-1 ui rule waved every `dart:` URI through, so the `dart:io` half of the bypass the last pass reported closing was still open.** `_landsOutsideRings` returns "not a violation" for any `dart:` import and `_uiBannedSymbols` named no `dart:io` symbol, so a widget could `Process.run('wl-copy', …)` past the port, the controller's guard, the failure notice and the type-only logging with every AD-1 row green. `dart:io` and `dart:ffi` are now violations for the ui ring, with a checker self-test. Separately, the symbol denylist protected only the two seams someone had thought of: the remaining seven port providers are banned, and a new mechanical row asserts that **every** provider declared in `port_providers.dart` is either banned or listed in `_uiSanctionedProviders` with a reason — so a seam added by a later story fails the gate instead of being silently reachable. Both mutation-verified.
  - `[medium]` `[patch]` The panel had a documented height floor and no width floor at all: probed at 480→120 the card's `Row` overflows by 65 px on each of three cards, with the copy button clipped out of reach, and nothing sizes the toplevel (DW-50). Every layout row used width 480. The variant label is now `Flexible` and ellipsised — the label gives way, the copy button stays on screen — pinned by a row at 160 px that also taps the button and asserts the write. Mutation-verified.
  - `[medium]` `[patch]` A digit could highlight a card scrolled out of the variants viewport — CAP-4's only answer, painted below the fold. Selecting now brings its card into view. Fixing it exposed a second defect: the variants were a lazy `ListView`, which does not build a child below the fold at all, so the card being scrolled to had no context to scroll to; the list is a scroll view over a `Column` now, which is the right shape for three compile-time-fixed registers. Mutation-verified, and the story's declared gate 9 re-run against the new shape still fails all six layout rows.
  - `[medium]` `[patch]` The two clearing transitions rebuild `CorrectionState` field by field, and only four of the seven fields were pinned: dropping `editorText` or `submittedText` from that rebuild left the whole suite green. A deselect or a failed-then-successful copy would therefore overwrite the draft in the `TextField` the user is typing in (the pane syncs from `editorText`) and silently turn a later Retry into a no-op. Two controller rows added; each mutation now fails two of them.
  - `[low]` `[patch]` The copy-failure notice was a compile-time constant, so a second rejected copy produced an `==`-equal state: the live region had nothing to re-announce and a `distinct()` consumer would drop it. The notice names its register now — which also tells the user which variant they still do not have. Mutation-verified. Honest limit: two failures on the *same* register are still the same state.
  - `[low]` `[patch]` `_copyToken`'s doc said "what is suppressed is only the verdict", while the code returns before the log call as well. The behaviour is right — it is story 3's contract for a superseded clipboard *read*, which two existing rows pin with their reasons — so the doc was corrected to claim what the code does rather than the code changed to match the doc.
  - `[low]` `[patch]` The copy buttons' semantic labels were unpinned: deleting the `tooltip:` line left the suite green, so the fix that made CAP-11's three identical icons distinguishable non-visually could regress unnoticed. A semantics row now asserts the label per register. Mutation-verified.
  - `[low]` `[patch]` The `copyFailure` notice's live region was unpinned for the same reason — every test read the notice as text or as a rect. A semantics row asserts the flag. Mutation-verified.
  - `[low]` `[patch]` `DaemonApp`'s banner suppression and dark scheme were unpinned; dropping all three properties was green, which would put the DEBUG ribbon back in the `--debug` artifact the acceptance criteria build and make the panel the one bright window on a dark desktop. `test/ui/daemon_app_test.dart` added. Mutation-verified for the banner and for `darkTheme`; stated in the row itself that `themeMode` cannot be pinned, because `ThemeMode.system` is also `MaterialApp`'s own default.
  - `[low]` `[patch]` The below-floor layout row's headline claim rested on `expect(find.byType(Scrollable), findsWidgets)`, which the variants' own scroll view satisfies at every surface size — the row survived deleting the panel's outer scroll view. It now measures the panel's own viewport: `maxScrollExtent > 0` at 480×160 and `== 0` at the floor. Mutation-verified (replacing the outer scroll view with a non-scrolling box fails three rows).

### 2026-08-11 — Follow-up review pass 2

- intent_gap: 0
- bad_spec: 0
- patch: 16: (high 0, medium 8, low 8)
- defer: 0
- reject: 11: (high 0, medium 0, low 11)
- addressed_findings:
  - `[medium]` `[patch]` **The AD-1 ui gate had three more open doors, each reached with all 24 rows green.** (1) The denylist named `MethodChannel`, `EventChannel` and `SystemChannels`, so `BasicMessageChannel('flutter/platform', …).send(…)` and `WidgetsBinding.instance.defaultBinaryMessenger.send(…)` both reached the system clipboard from a widget, past `ClipboardPort`, the controller's guard, the failure notice and the type-only logging — the same bypass the two previous passes each reported closing, on its third and fourth route. `MessageChannel`, `BinaryMessenger` and `ServicesBinding` are now banned as substrings, so `BasicMessageChannel`, `OptionalMethodChannel` and `defaultBinaryMessenger` are all covered, with self-tests for each route. Probe-confirmed before and after.
  - `[medium]` `[patch]` **The seam-classification row could not see a seam declared any way but one.** It discovered seams with `^final (\w+Provider) =`, while the repo's own scanner uses a looser pattern — so `final sneakySeam = Provider<Clock>(…)` or `final Provider<Clock> typedSeam = …` was discovered by nothing, classified by nothing, and readable from a widget with the row passing on an empty `unclassified` list. That row exists precisely so "a seam added by a later story fails the gate", which it did not. Discovery is now every top-level `final` in `port_providers.dart` — whose own library doc says it holds "one typed seam per port, and nothing else" — pinned by a seam count so a narrowing fails loudly, with three discovery self-tests. Both probes now fail the gate.
  - `[medium]` `[patch]` **CAP-13's inline failure was not announced, while the smaller copy notice was.** `getSemantics(...).isLiveRegion` was false for the message that *replaces the variants*: a screen-reader user was told when a copy failed and not when the correction did, left in front of a panel whose answer vanished silently. The previous pass's own stated principle — "a notice assistive tech never reads is as good as no notice at all" — had been applied to the lesser of the two. Live region added, row added, mutation-verified.
  - `[medium]` `[patch]` **The progress affordance was unlabelled and unannounced**, so the "running looks like idle" fix shipped for sighted users only: the trap it existed to close — pressing Correct again, which under AD-4 cancels the run being waited for — stayed fully open for everyone else. `semanticsLabel: 'correcting'` plus a live region; a row asserts both. Mutation-verified.
  - `[medium]` `[patch]` A copy failure at a narrow surface overflowed the region it was reported in: probe-measured at 120×300 — *at* the documented floor — clean until the write is rejected, then `A RenderFlex overflowed by 23 pixels`. The notice was the one child there whose height grows as the width shrinks, and the previous pass's width work stopped at 160. It is now bounded to half the variants region and scrolls inside it, pinned by a row at 120 px that drives a rejected copy. Mutation-verified.
  - `[medium]` `[patch]` **A digit key could scroll the user's own text off the top of the panel.** `Scrollable.ensureVisible` walks *every* scrollable ancestor, and below the height floor the panel itself is one — so the scroll-into-view added last pass moved the editor's rect from y=32 to y=-95 on one keypress, with no way back and the offset surviving into the next session. CAP-10 defeated by CAP-4's own key. `SuggestionList` now owns a `ScrollController` and scrolls only its own position; a row at 480×160 asserts the editor's rect is unchanged by a selection. Mutation-verified.
  - `[medium]` `[patch]` **The height floor ignored `MediaQuery.textScaler`, so it certified CAP-10 where the original could not show one line.** DW-58 filed this and predicted an overflow; two layers reproduced it and there is none — the editor's share silently shrinks instead: 31.2 px at 1.0×, 23.2 at 1.5×, 15.2 at 2.0×, against lines of 16, 24 and 32 px, so the guarantee fails from roughly 1.45× up and GNOME's large-text range is 1.25–1.5×. `minimumPanelHeightFor(TextScaler)` scales the floor with the text — cheaper than the intrinsics rework DW-58 assumed — the doc says what was measured at which scale, and a row asserts a full line at 1.5×. Mutation-verified.
  - `[medium]` `[patch]` The stale-clipboard-read guard was pinned by nothing: deleting `if (token != _sessionToken) return;` failed **zero** of 760 tests, because `FakeClipboardPort.readText` resolved its answer *after* its gate, so two overlapping reads could not be given different content and the stale one happened to return the right thing. What that hides is user-visible: copy, summon (the read parks on IPC), hide, clear the clipboard, summon again — the late read pastes the previous session's clipboard into the field the user is typing in. The fake now captures at call time, as `writeText` already did; a row expresses the sequence. Deleting the guard now fails two rows.
  - `[low]` `[patch]` The comment stripper deleted everything after `//` wherever it appeared, string literals included, so any banned call sharing a line with a URL was invisible to the whole gate — `final u = 'https://x'; Clipboard.setData(…);` passed while the identical call alone on a line failed. Replaced with a scanner that knows where a literal ends (raw prefix, triple quotes, escapes) and leaves literals intact, which is what the symbol scan documents wanting. Self-test added.
  - `[low]` `[patch]` `Ctrl+NumpadEnter` did nothing, in a story that gave every selection slot a keypad twin on the stated grounds that "a user with a keypad expects it to work too". The keypad's Enter is a different logical key; both are now activators. Mutation-verified.
  - `[low]` `[patch]` The submit accelerator was advertised nowhere on screen, on a surface whose premise is that it is driven from the keyboard — while the selection keys get a hint that dims itself when dead. The Correct action now names it (`Correct (Ctrl+Enter)`), pinned by a row.
  - `[low]` `[patch]` An empty clipboard made the re-seed emit a state equal to `CorrectionState.empty` — which is the panel's *only* signal that a session just began — so one IPC round-trip after a show the panel requested editor focus a second time, pulling it back from wherever the user had moved it. DW-54 accepted the inference on the stated grounds that this case was harmless; it was not. The seed no longer emits when there is nothing to pre-fill. Mutation-verified.
  - `[low]` `[patch]` `copySuggestion`'s post-shutdown guard was unpinned: deleting `_disposed ||` failed nothing, while the same property for `submit()` has had a row since story 3. With it gone, a Copy pressed during the shutdown window issues a write into an adapter the ordered teardown is closing. Row added, mutation-verified. The sibling arm in `selectSuggestion` turned out to be redundant by construction — `_setState` already refuses after shutdown, so no test can distinguish it; rather than add a row that cannot fail, the code now says so.
  - `[low]` `[patch]` The panel's own logger swallow — the ui-ring instance of the guard all three controllers carry — was the only one with no `ThrowingLogger` row: deleting its `try`/`on Object` left every widget test green. The daemon runs `StderrLogger`, whose sink a closed parent terminal turns into a broken pipe, and this report fires from a stream callback, so the throw would land in the daemon's zone at shutdown. `PanelHarness` can now install a failing logger; row added, mutation-verified.
  - `[low]` `[patch]` The panel binds its controller once and the comment asserted the provider's value "never changes" — true of today's graph, not of the type: `correctionControllerProvider` watches two seams that story 10 may make mutable, which would leave the panel bound to a disposed controller with `_onStateStreamClosed` (written for shutdown) as its only handler. Not pre-solved, because a path nothing can trigger is a path no test can pin — this pass removed several such properties rather than adding one. The doc now states the condition and DW-62 records it.
  - `[low]` `[patch]` Ledger entries earned by this pass appended (DW-60 … DW-63), including a correction to two stale test counts filed as its own entry rather than by editing the originals. No existing entry edited, re-opened or closed.

## Design Notes

**Why selection and copy are in the controller, not the widgets.** The "State mutation" row makes one controller the owner of a surface's state, and AGENTS.md §3 forbids clipboard access inside a widget class. Selection in the controller also buys AD-18 for free: `_beginSession` already builds `CorrectionState.empty`, so a highlight cannot outlive a show, and `_onFailed`/`_startRun` build state directly, so it cannot outlive a failure or a new run either. A widget-local highlight would need its own listener to reproduce all three, and would be unreachable from `dart test`.

**Nothing selectable or copyable comes from a partial.** AD-3 calls deltas "a progressive-rendering optimisation, never the record of truth". A copy button live during streaming would put text on the clipboard that `CorrectionCompleted` is about to replace — the user would paste a half-sentence that the panel no longer shows. So partials render (CAP-5) and neither the digit keys nor the copy buttons act until the session is `completed`. This is a stricter reading than CAP-4 and CAP-11 require, and it is the only one AD-3 permits.

**The keyboard, which the spine's Deferred section hands to this story.** Focus starts on the editor, so a summoned panel can be typed into immediately. The digit keys are scoped to the suggestions region: with the editor focused, `2` is text (CAP-3 would otherwise be broken by CAP-4), and submitting moves focus to the suggestions so `1`/`2`/`3` work the moment there is something to select. The submit accelerator is `Ctrl+Enter`, because the editor is multi-line and `Enter` belongs to it. There is no `Escape`: CAP-14 gives the panel a focus-loss hide and a toggle, and a UI-initiated `hide()` would put a visibility call in the ui ring.

**Deriving the digit key from AD-6 without hardcoding it.** `SuggestionRegister.values.indexOf(r) + 1` is the number; the key is `LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + index)`, which holds because those ids are the characters `'1'`–`'9'`. A register at index ≥ 9 has no digit key, so it renders with no key hint rather than a wrong one — the honest degradation for an enum that grows past the keyboard.

**DW-30, decided rather than deferred again.** A `restore`-sourced `true` re-seeds the session and so discards what the user typed. The panel keeps that behaviour: AD-18 says *every* `show()` starts a fresh session re-seeded from the current clipboard, and the panel cannot tell the two `true`s apart without a distinction the port does not carry. Nothing in this story narrows it; the decision is recorded in the ledger so the next reader sees a choice, not an oversight.

**DW-35, closed by construction.** The panel never awaits `show()`. The window is mapped and unmapped underneath a widget tree that is always built (AD-8), so the panel has no render decision to make and never needs to know whether the window moved. The entry stays open for whoever does need it.

**A rejected copy is not a correction failure.** `CorrectionState.failure` is CAP-13's inline error with a Retry, and its assert ties it to `status == failed`. A clipboard write that fails did not fail the correction — offering a Retry would re-run a correction that already succeeded, which is exactly the reasoning story 3 wrote down for a lost history row. So the copy failure is its own short notice beside the variants, cleared on the next copy.

**A widget test has to pump before it drives visibility.** `correctionControllerProvider` is lazy, and the controller's constructor is what subscribes to `PanelVisibility.changes`. A `show()` issued before the first pump reaches nobody. The harness's `pumpSession()` exists so no test gets that wrong twice.

## Verification

**Commands:**
- `dart analyze` -- expected: no issues (AGENTS.md §6 merge gate).
- `dart format --output=none --set-exit-if-changed lib test` -- expected: 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: all pass, **no new skips**. Baseline measured on this story's parent revision: **616 passed / 2 skipped**. This is also the AD-1 gate: it fails to resolve if the application or domain ring gains a Flutter import, and it is where the controller-level additions run.
- `flutter test` -- expected: all pass. Baseline: **664 passed / 7 skipped**. Every new `test/ui/` test must **pass**, not skip: nothing in this story needs a display.
- `flutter build linux --debug` -- expected: builds.
- `grep -rn "infrastructure" lib/src/ui/` -- expected: no import matches (AD-1's ui row).

**Mutation gates** — apply each, run `flutter test`, record how many tests fail, revert. **Any that fails zero tests means the property is unpinned and the test is what needs fixing.**
1. Render `SuggestionRegister.values.reversed` -- the AD-6 order test must fail.
2. Hardcode the key hint on every card to `1` -- the AD-6 key-mapping test must fail for at least two registers.
3. Make `copySuggestion` also set `selectedRegister`, and `selectSuggestion` also copy -- the AD-18 "copy is never implicit in selection" tests must fail.
4. Copy `state.suggestionTexts` before the completed replacement (i.e. enable copy while running) -- the CAP-11 exact-text and copy-disabled-while-running tests must fail.
5. Keep the half-streamed rows visible alongside the inline error -- the CAP-13 replacement test must fail.
6. Make Retry send `state.editorText` instead of the captured text -- the CAP-13/AD-18 replay test must fail.
7. Enable the Correct action on a whitespace-only editor -- the DW-3 test must fail.
8. Put the digit shortcuts on the whole panel rather than the suggestions region -- the "digits are inert in the editor" test must fail.
9. Replace the two scrollable panes with one outer scroll -- the CAP-10 layout test must fail.
10. Swallow the clipboard write's rejection without a notice -- the copy-failure test must fail.

**Manual checks (if no CLI):**
- **Not observable here, and must be reported as such.** This container has no compositor and no reachable X display (DW-9, DW-26), so nothing about the panel *on screen* is observed: not that it appears within CAP-1's 100 ms, not that it takes keyboard focus, not that the focus-loss hide leaves it dismissed, not that the real system clipboard receives a copy, and not how the layout looks at the window's actual size. A headless widget test is a test of the widget tree, not a runtime observation of a desktop, and may not be reported as one.
- Confirm by inspection that no file under `lib/src/ui/` names an adapter, a plugin, a `window_manager` call or a `MethodChannel`, and that no log line added here carries a caught error's `toString()`.



## Auto Run Result

### 2026-08-11 — Follow-up review pass

Status: done

**Summary.** A second review pass over the same diff (baseline `a81802a`, which is what the story's `baseline_revision` still names, so this pass reviewed the panel whole rather than only the previous pass's patches). Four layers ran in parallel — adversarial, edge-case, verification-gap and intent-alignment — and produced 27 distinct findings after dedup. Twelve were patched, three deferred, twelve rejected; no intent gap and no spec defect, so no code was reverted and the spec's `<intent-contract>` is untouched. The load-bearing finds were a floor that certified CAP-10 at a height where the original rendered as a 7-pixel sliver, key auto-repeat reaching a toggle, a `dart:io`-shaped hole in the AD-1 ui gate that the previous pass believed it had closed, an unconstrained width axis, a digit that could highlight a card below the fold, and a hand-enumerated state rebuild whose draft-carrying half no test pinned. Every claim above was reproduced before it was patched — by probe (the layout measurements) or by mutation (the unpinned properties) — and every patch was mutation-verified afterwards.

### Completion notes

**The keyboard, which the spine's Deferred section leaves to this story.** Focus starts in the editor and returns there at the start of every session — an explicit focus request on session reset, not `autofocus`, which fires once in a tree AD-8 never rebuilds. The digit shortcuts are scoped to the suggestions region, so `2` in the editor stays text, and submitting hands focus to the variants so `1`/`2`/`3` work the moment there is something authoritative to select. Each slot answers to its digit-row key and its keypad twin, and as of this pass neither map accepts key *repeats*: selection is a toggle and `submit()` cancels before it restarts, so a held key would have flickered the highlight or killed and re-spawned a run. `Ctrl+Enter` submits and is scoped to the editor subtree, because `Enter` belongs to a multi-line editor and a panel-wide accelerator cancelled a correction the user was about to copy. There is no `Escape` and no UI-initiated visibility call anywhere. What the keyboard still owes is DW-57: the activators are *logical* keys, so on a non-QWERTY layout the un-dimmed `1`/`2`/`3` hint promises a keystroke that selects nothing.

**Nothing selectable or copyable comes from a partial.** AD-3 calls deltas "a progressive-rendering optimisation, never the record of truth", so a copy taken from one would put text on the clipboard that `CorrectionCompleted` is about to replace. Partials render; the digits and the copy buttons act only on a completed session with non-whitespace text, and the key hint is dimmed whenever its key would do nothing.

**DW-30 is decided, not deferred again.** A `restore`-sourced `true` still re-seeds the session and so discards what the user typed. AD-18 says *every* `show()` starts a fresh session from the current clipboard, and the panel cannot tell the two `true`s apart without a distinction `PanelVisibility` does not carry. Recorded as DW-48; the port was not edited.

**DW-35 is closed by construction for the panel.** The panel never awaits `show()`: the window is mapped and unmapped underneath a widget tree that is always built, so there is no render decision to gate on whether the window moved. The entry stays open for its next caller (DW-49).

**Why selection and copy live in the controller.** The Consistency Conventions "State mutation" row makes one controller the owner of a surface's state, which is also what gives AD-18's three clearings for free — `_beginSession`, `_startRun` and `_onFailed` already build state directly, so a highlight cannot outlive a show, a new run or a failure. AGENTS.md §3 forbids clipboard access inside a widget class, so the copy action is a controller method with the same guard, `_log` swallow and type-only logging as every other port call there. That the two capabilities' behaviour now sits one ring inward of where the spine's Capability→Architecture map places them is filed as DW-56 rather than hand-edited into the spine.

**Files changed in this pass:**
- `lib/src/ui/panel/correction_panel.dart` — the height floor raised to 300 with the measurement and the claim it was measured against written down; `includeRepeats: false` on both shortcut maps, each with its reason.
- `lib/src/ui/panel/suggestion_card.dart` — the variant label is `Flexible` and ellipsised, so a narrow window gives up the label rather than the copy button.
- `lib/src/ui/panel/suggestion_list.dart` — stateful; brings a newly selected card into view after the frame that highlighted it, and is a scroll view over a `Column` rather than a lazy `ListView`, which never built the card there was to scroll to.
- `lib/src/application/correction_controller.dart` — the copy-failure notice names its register; `_copyToken`'s doc corrected to say that a superseded write's log line is suppressed too, which is story 3's contract for a superseded clipboard read.
- `test/architecture/ad1_import_rule_test.dart` — `dart:io`/`dart:ffi` are violations for the ui ring; the remaining seven port seams are banned; a new mechanical row fails whenever `port_providers.dart` declares a provider that is neither banned nor explicitly sanctioned.
- `test/ui/daemon_app_test.dart` — **new**; the debug ribbon, the dark scheme and the panel as the app's home.
- `test/ui/panel/correction_panel_layout_test.dart` — CAP-10 asserted at exactly the floor; a 160 px-wide row; the vacuous `Scrollable` check replaced by the panel viewport's own scroll extent.
- `test/ui/panel/correction_panel_selection_and_copy_test.dart` — held-digit repeat, scroll-into-view, the per-register copy label, the notice's live region, and two variants' distinct notices.
- `test/ui/panel/correction_panel_editor_test.dart` — the held accelerator, asserted where the repeats can actually reach it.
- `test/application/correction_controller_test.dart` — the draft and the submitted text carried through both clearing transitions; each variant's rejected copy as its own notice.
- `_bmad-output/implementation-artifacts/deferred-work.md` — DW-57, DW-58, DW-59 appended; no existing entry edited, re-opened or closed.

**Review findings breakdown.** patch 12 (0 high, 6 medium, 6 low); defer 3 (2 medium, 1 low → DW-57 the non-QWERTY digit keys, DW-58 the floor's text-scale blindness, DW-59 a successful copy rendering nothing); reject 12; intent_gap 0; bad_spec 0.

Rejected rather than acted on, with the reason:
- *The panel reads `loggerProvider` and writes to stderr from the ui ring, against AGENTS.md §3.* §3 bars network calls, database writes, clipboard access and prompt building from a widget class — not a log line. Routing it inward would need a third public member on `CorrectionController`, which this story's Never list forbids. The seam is now explicitly sanctioned in the AD-1 gate with that reasoning, so it is a recorded decision rather than an omission.
- *`register_key_slot.dart` holds public functions and no public type.* §3 bans more than one public type per file, not zero; already judged the same way last pass.
- *The panel's `onError` arm on the controller's state stream is unreachable dead code.* It is the AD-15 backstop the controller installs for the symmetric case, and its unpinnability is already written down.
- *The copy button's tooltip should disappear while it is disabled, as the key hint dims.* A disabled button is announced as disabled; the label identifies which control it is. The hint dims because a bare `1` has no disabled state to announce.
- *Focus should move to the variants on completion rather than on submit.* The alternative steals the caret at the moment the answer lands, from a user who may have started a new draft. The documented choice stands; the progress affordance is what tells them the run is live.
- *Replace the hand-enumerated clearing rebuild with a sentinel-based `copyWith`.* A state-shape renegotiation across every existing transition; the two rows added this pass close the failure mode it was raised for.
- *The copy notice needs a dismiss control.* It is cleared by the next successful copy, a new run or a new session, and until then it is true.
- *`_onStateChanged` fires twice per show when the clipboard is empty.* Two requests for the same focus node and one redundant rebuild, with no user-visible consequence; the inference itself is DW-54.
- *The "`2` typed in the editor becomes text" half of the CAP-3 matrix row is asserted nowhere.* Correct, and not assertable here: key events do not reach a `TextField`'s input connection in a headless test, which is why the row asserts the half that is reachable (no variant is highlighted) and the live test owes a real keyboard.
- *DW-51 and DW-53 count 28 and 34 widget rows against 54 in the tree.* Correcting them means editing existing ledger entries, which this invocation forbids; the current count is recorded here instead.
- *The ui symbol checker does not strip string literals, so a user-facing sentence containing `Clipboard.` would trip an architecture test.* Deliberate strictness — the checker's own docstring calls a match "a conversation worth having rather than a hole worth leaving".
- *Invert the provider ban into a regex allowlist over every `*Provider` identifier.* Folded into the mechanical classification row instead, which gets the same future-proofing without the false positives a bare identifier regex produces on local names.

**Follow-up review recommendation:** `true`. Patched this pass: high 0, medium 6, low 6 — score `3×6 + 1×6 = 24`, well clear of the threshold of 5.

**Verification performed** (all after the patches, on the final tree):
- `dart analyze` — No issues found.
- `dart format --output=none --set-exit-if-changed lib test` — 149 files, 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` — **653 passed, 2 skipped** (previous pass 648/2, so +5 with no new skips: 3 controller rows and 2 architecture rows).
- `flutter test` — **760 passed, 8 skipped** (previous pass 746/8, so +14 rows and no new skips).
- `flutter build linux --debug` — built.
- `grep -rn "infrastructure" lib/src/ui/` — no matches.
- Mutation gates, each applied alone against a confirmed-green baseline and reverted: floor 300→240 (1 fail), `Flexible`→pass-through (1), digit `includeRepeats` back to default (1), accelerator `includeRepeats` back to default (1), drop `ensureVisible` (1), drop the copy tooltip (1), drop `liveRegion` (1), drop `editorText` from the clearing rebuild (2), drop `submittedText` from it (2, line-targeted so the sibling call site was untouched), notice back to a constant sentence (1), drop the debug-banner suppression (1), drop `darkTheme` (1), outer scroll view → non-scrolling box (3), stop checking the forbidden `dart:` set (1), forget one port seam in the ban list (1). Two negative results are recorded honestly above rather than papered over: `themeMode: ThemeMode.system` cannot be pinned because it is `MaterialApp`'s own default, and the accelerator-repeat row was vacuous in its first form and was rewritten until it bit.
- The story's own declared gates re-run where this pass could have affected them: gate 1 (`values.reversed`) 1 fail, gate 2 (hint hardcoded to `1`) 1 fail, gate 9 (variants lose their own scroll pane) 6 fails — so replacing the lazy `ListView` with a scroll view over a `Column` did not weaken the CAP-10 gate.

**Residual risks:**
- **Nothing about the panel on screen was observed.** No compositor and no reachable X display here (DW-9, DW-26), so every layout measurement in this pass — including the 7.2 px probe that condemned the old floor and the 300 that replaced it — is a measurement of a widget tree at a surface size the test chose, not of a window a user dragged. `test/platform/correction_panel_live_test.dart` is what keeps those claims owed rather than forgotten.
- The height floor is still a widget-side fallback for a toplevel nothing sizes (DW-50, DW-53), and it is blind to system text scaling (DW-58). The width axis is now graceful rather than floored: the label ellipsises, but no minimum width is enforced anywhere.
- A successful copy still renders nothing (DW-59), and two overlapping copies still reach the clipboard in whatever order the platform applied them (DW-55).
- The digit keys are logical, so a non-QWERTY user gets an un-dimmed hint that does nothing (DW-57) — the one finding this pass deferred that a user can actually hit.
- Two failed copies of the *same* variant remain one state, so the live region announces only the first.
- `_setSelectionAndNotice` still enumerates seven fields by hand; all seven are pinned now, but the next field added to `CorrectionState` will not be until someone adds a row for it.

**Residual artifacts.** The working tree this pass was dispatched into had the first pass's `## Auto Run Result` section already deleted (63 lines, uncommitted, not this pass's doing). That deletion is inside the reviewed diff and is therefore committed with it; the completion notes the story's fourth acceptance criterion asks for are carried forward above rather than restored verbatim.

### 2026-08-11 — Follow-up review pass 3

Status: done

**Summary.** A third review pass over the same diff (baseline `a81802a`, so the panel was reviewed whole rather than only the previous pass's patches). Four layers ran in parallel — adversarial, edge-case, verification-gap and intent-alignment — producing 27 distinct findings after dedup: 16 patched, 0 deferred, 11 rejected. No intent gap and no spec defect, so no code was reverted and the `<intent-contract>` is untouched. The load-bearing finds were two more routes past the AD-1 ui gate (`BasicMessageChannel` and the binary messenger) plus a comment-stripper hole and a seam-discovery regex that between them made the gate's newest row unable to fail on what it was written for; a digit key that scrolled the user's own text off the top of the panel; a height floor that certified CAP-10 at text scales where the original could not show a line; CAP-13's inline failure and the progress affordance both being invisible to assistive tech while the smaller copy notice was not; and a stale-clipboard-read guard that no test could fail because the fake could not express two overlapping reads. Every claim was reproduced before it was patched — by probe or by mutation — and every patch is mutation-verified afterwards, each new row failing when and only when its property is broken.

**Files changed in this pass:**
- `lib/src/ui/panel/correction_panel.dart` — `minimumPanelHeightFor(TextScaler)` and the floor applied from it; the progress affordance labelled and announced; the copy-failure notice bounded to half its region and scrollable, with the live region moved onto the text node itself; `numpadEnter` as a second submit activator; the controller-binding and floor docs corrected to claim what the code does.
- `lib/src/ui/panel/suggestion_list.dart` — its own `ScrollController`, disposed, so bringing a card into view scrolls this list and not the panel around it.
- `lib/src/ui/panel/correction_error_notice.dart` — CAP-13's message in a live region.
- `lib/src/ui/panel/original_text_pane.dart` — the Correct action names its accelerator.
- `lib/src/application/correction_controller.dart` — the re-seed no longer emits when there is nothing to pre-fill; a note that `selectSuggestion`'s post-shutdown arm is redundant by construction while `copySuggestion`'s is not.
- `test/architecture/ad1_import_rule_test.dart` — three more banned symbols, a literal-aware comment stripper, top-level-`final` seam discovery pinned by a count, and six new checker self-tests.
- `test/fakes/fake_clipboard_port.dart` — `readText` captures its answer at call time, as `writeText` already did.
- `test/ui/panel_harness.dart` — an optional installed `Logger`, so a widget test can make the logger itself fail.
- `test/application/correction_controller_test.dart`, `test/ui/panel/correction_panel_{editor,streaming,error,layout}_test.dart` — 15 new rows for the properties above.
- `_bmad-output/implementation-artifacts/deferred-work.md` — DW-60 … DW-63 appended; nothing existing edited.

**Verification.** `dart analyze`: no issues. `dart format --output=none --set-exit-if-changed lib test`: 149 files, 0 changed. `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart`: **660 passed / 2 skipped** (653/2 before this pass; +7 rows, no new skips). `flutter test`: **775 passed / 8 skipped** (760/8 before; +15 rows, every new `test/ui/` row passes rather than skipping). `flutter build linux --debug`: builds. `grep -rn "infrastructure" lib/src/ui/`: no matches. The spec's mutation gates 9 and 10 were re-run against the changed scroll structure and the changed notice — they still fail 10 and 5 rows respectively.

**Residual risks.**
- The AD-1 ui gate is a substring denylist over source text. Three consecutive passes have each found a way past it; this pass closed four routes and DW-60 records that the shape of the mechanism, not the length of the list, is the thing that keeps failing.
- Nothing here was observed on a desktop. This container has no compositor and no reachable X display, so the panel appearing, taking keyboard focus, the focus-loss hide, the real system clipboard, and the layout at the window's actual size remain unobserved — `test/platform/correction_panel_live_test.dart` still reports skipped and names the owed claims. The text-scale floor is measured in a headless surface too.
- The floor remains a widget-side stand-in for a window constraint nothing sets (DW-50, DW-53, DW-61), and the copy-failure notice is now bounded to half the variants region, which is a chosen proportion rather than a measured one.
- DW-57 (the un-dimmed 1/2/3 hint on a non-QWERTY layout) and DW-59 (a successful copy renders nothing) remain open and user-reachable; both are keyboard-model and affordance decisions with more than one defensible answer.
- `selectSuggestion`'s post-shutdown guard is unpinnable by construction and is documented as such rather than covered.

**Follow-up review recommendation:** `true`. Patched this pass: 0 high, 8 medium, 8 low → 3×8 + 1×8 = 32, at or above the threshold of 5.

**Residual artifacts.** The previous pass's `## Auto Run Result` section was found deleted in the working tree at the start of this run, by something outside it — the same pattern that pass recorded. It was restored from `HEAD` rather than committed as a deletion, so the record of all three passes is intact above.
