---
title: 'Why the window went away, three ways — and a session marker the state carries instead of infers'
type: 'feature'
created: '2026-08-20'
status: 'in-review'
baseline_revision: '916303fbd6fceaf2671034fbf764fb86cc0adda1'
final_revision: '348612b9b88098a42db2e9a8a67cc3b778ba35a3'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
warnings: ['oversized']
---

<intent-contract>

## Intent

**Problem:** `PanelVisibility` says only *whether* the panel is up, so nothing above it can tell the three ways it goes away apart. `changes` is a `Stream<bool>`, and `CorrectionController._onVisibilityChanged` starts a fresh AD-18 session on every `true` — `CorrectionState.empty` plus a clipboard re-seed. A user who types into the panel, iconifies it and restores it therefore gets their text replaced by the clipboard, and so does one whose panel took itself down on a focus loss (DW-30). The human's 2026-08-14 rule is three-way rather than two: a dismissal *to the tray icon* ends the session (text gone, clipboard re-seeded on the next summon), while a minimise *to the task bar* and a *loss of focus* do not (typed text survives the return). `FakePanelVisibility` cannot express any of that — it has `show`/`hide`/`loseFocus` and no restore concept — so the application ring cannot even test it. And because the controller never knows explicitly that a session began, `CorrectionState` has no marker for it: `isFreshSession => this == empty` (`correction_state.dart:84`) is a value comparison read by two consumers, `correction_panel.dart:214` (return the caret to the editor) and `daemon_home.dart:110` (return the window to the panel view) (DW-54).

**Approach:** Make the port carry *why*. `changes` emits a `PanelVisibilityState` — `shown`, `dismissed`, `iconified`, `focusLost` — and the adapter attributes every mirror move it already makes: `hide()` is `dismissed`, the `close` arm's real hide is `dismissed`, the focus-loss hide is `focusLost` by both its routes, the `minimize` arm is `iconified`, and `show`/`restore` are `shown`. `bool get isVisible`, `show()` and `hide()` are untouched, so AD-8's toggle is untouched. The session policy stays in the application ring: the controller remembers the departure it last saw and begins a session on `shown` only when that departure was a `dismissed`. Because it now knows a session began rather than emitting a value that looks like one, it stamps it — `CorrectionState.isFreshSession` becomes a real field, set on the state `_beginSession` emits and carried by nothing else, so its two consumers keep asking the same question and stop getting a `==` for an answer.

## Boundaries & Constraints

**Always:**
- **The three-way rule, exactly:** a `dismissed` departure ends the session — the next `shown` clears the state and re-seeds from the current clipboard (AD-18, CAP-2). An `iconified` or `focusLost` departure does not — the next `shown` emits nothing at all, so the panel keeps the text, the suggestions and the error it had. A controller that has never seen a departure begins a session on its first `shown`.
- **Everything the human's three names do not reach keeps today's meaning.** The `close` arm and an external `hide` event both put the panel where a `hide()` request would have put it, so both are `dismissed`. That is the status quo (`_dismiss('close')` already calls `hide()`), not a new reading.
- The session policy lives in `CorrectionController`. `PanelVisibilityState` is descriptive only: it says where the window went, never what that means for a session.
- `bool get isVisible`, `Future<void> show()` and `Future<void> hide()` keep their signatures and semantics: AD-8 requires the toggle to read a synchronous bool and never await, and `PanelController` must not change.
- `changes` stays broadcast, still emits **exactly** on a transition of `isVisible` in both directions, and still emits nothing for a `show()` at a visible panel or a `hide()` at a hidden one. Two departures in a row cannot both emit — the second finds the mirror already false.
- Every mirror move in the adapter is attributed at the site that makes it. No default, no inference: the compiler must force a departure to be named wherever `_setMirror` is called.
- `isFreshSession` is stamped, never derived. `copyWith` never carries it — a state built from another is not a session beginning — and it takes part in `==`/`hashCode`, which is what makes a hand-cleared editor stop looking like `empty` (DW-54).
- AD-4's three cancellations are unchanged: no departure cancels an in-flight correction, and a correction that completes while the panel is away is still persisted (CAP-7).
- The focus-loss log line stays `the window rejected the focus-loss hide` and the close line stays distinguishable from it — `window_manager_panel_visibility_test.dart` asserts `contains('focus-loss hide')`.
- AD-1 confinement holds: `package:window_manager` stays in `lib/main.dart` and `window_manager_panel_window.dart`. This change touches neither.
- Every behaviour change lands with a row that fails when the change is reverted. Mutation-verify each new gate with sources restored from scratchpad copies, never `git checkout --`, which would discard the patch under review.
- Where a doc comment in the touched files states the old behaviour as a cost or a defect, it is rewritten to state what is now true — including what is *not* fixed (see Design Notes).

**Block If:**
- Attributing a departure turns out to need a signal the `PanelWindow` seam does not carry, i.e. some route to a false mirror cannot be told apart from another without a new event or a query on that seam.
- Keeping the session across a return turns out to require the controller to re-read the clipboard, the window or the panel widget — the departure the controller remembers must be sufficient on its own.

**Never:**
- Do not add a conditional task-bar entry, a window size, a minimum size or a position, and do not touch `setSkipTaskbar`. That is the panel-window-geometry bundle (DW-50, DW-53, DW-61, DW-72), which this change is sequenced after and must not pre-empt.
- Do not widen the `PanelWindow` seam: no new event names, no queries, no typed callbacks.
- Do not edit anything under `_bmad-output/` — not `ARCHITECTURE-SPINE.md` (its AD-8 snippet still shows `Stream<bool>`), not `SPEC.md`, and not `deferred-work.md`. The orchestrator owns all three.
- Do not edit the numbered steps or the results table of `test/platform/runtime-observation-checklist.md`.
- No session counter, no session id and no second stream: one enum on the one stream, one bool on the state.
- Do not make a departure cancel a correction, clear the state eagerly on the way down, or emit on `changes` for a request that moves no window.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| A dismissal ends the session | panel up, user typed `mine`, clipboard now `theirs`; `hide()` then `show()` | `changes` emits `dismissed` then `shown`; the controller emits `empty` with `isFreshSession` true and re-seeds the editor to `theirs` | No error expected |
| A focus loss keeps it | panel up, user typed `mine`; the adapter's focus-loss hide, then `show()` | `changes` emits `focusLost` then `shown`; the controller emits **nothing**, the editor still holds `mine`, and the clipboard is not read | No error expected |
| A task-bar minimise keeps it | panel up, user typed `mine`; `minimize` window event, then `restore` | `changes` emits `iconified` then `shown`; the controller emits nothing and the editor still holds `mine` | No error expected |
| A believed pair during one of our requests | a request outstanding; `minimize` then `restore` (the DW-31 latch) | `iconified` then `shown`, and no session begins — the pair no longer discards what was typed | No error expected |
| The close control ends the session | panel up; `close` window event | the adapter issues a real hide and emits `dismissed`; the next `shown` begins a session | A refused hide logs `the window rejected the close hide` and nothing else |
| The first summon ever | freshly built controller, no departure seen | the first `shown` begins a session and seeds from the clipboard | No error expected |
| Suggestions survive a focus loss | completed correction on screen; focus-loss hide, then `show()` | the suggestions are still rendered; a `hide()`/`show()` instead clears them | No error expected |
| A hand-cleared editor is not a session | idle session, no suggestions; user selects all and deletes | the emitted state's `isFreshSession` is false and it is `!=` `CorrectionState.empty`; neither consumer acts | No error expected |
| An external unmap | nothing outstanding; `hide` window event | `dismissed` — the panel is where a request would have put it | No error expected |
| The stream breaks its contract | `changes` emits an error | the controller's AD-15 backstop logs it, the subscription survives, and the next `shown` still decides correctly | Log only, `error_type` and nothing else |

</intent-contract>

## Code Map

- `lib/src/domain/panel/panel_visibility.dart` -- the port. Holds `isVisible`, `changes`, `show()`, `hide()`; gains `PanelVisibilityState` beside them, the way `correction_event.dart` holds `CorrectionFailureKind` beside its family. Its `changes` doc also carries a false claim to correct: it says the panel widget and the controller are two independent subscribers, but the widget subscribes to `CorrectionController.changes` and `panel_controller.dart:64` says the port stream is deliberately not re-exposed — there is exactly one production subscriber.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- the only production implementation, 1067 lines of mechanism and doc. `_setMirror` (line 947) is the single write point; it is reached from `show()` (311), `hide()` (343), the `minimize` and latched-`restore` arms of `_onWindowEvent` (484), and `_reconcile` (731). `_dismiss` (934) has three call sites and two causes: the `close` arm (570) and the two focus-loss routes, `_onBlur` (814) and `_releaseDeferredBlur` (908).
- `lib/src/application/correction_controller.dart` -- `_onVisibilityChanged` (319) and `_beginSession` (337); `_seedFromClipboard`'s empty-clipboard guard (376) cites the old focus behaviour as its reason.
- `lib/src/application/correction_state.dart` -- `empty` (27), `isFreshSession` (84), `copyWith` (89), `==`/`hashCode` (114). `editorText`'s doc (33-35) still says "seeded from the clipboard on every show (CAP-2)".
- `lib/src/ui/panel/correction_panel.dart:214` and `lib/src/ui/daemon_home.dart:110` -- the two consumers. Both keep reading `state.isFreshSession`; neither changes behaviour. `daemon_home.dart:33-44` claims "every route in — hotkey, tray, second launch, window restore — ends at the panel" and `:50` says a fresh session begins on every `show()` of a hidden window; both stop being true here.
- `lib/src/ui/panel/original_text_pane.dart:7-8` -- says the editor is re-seeded "from the clipboard on every show". Same staleness, one more file.
- `lib/src/application/panel_controller.dart` -- reads `isVisible` and calls `show`/`hide`; must not change. It is also the proof that no tray route can produce a `dismissed`: the tray menu has open-panel and Quit only (`tray_manager_tray.dart:197-219`) and `showPanel()` never hides.
- `test/fakes/fake_panel_visibility.dart` -- the application ring's only view of the port.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- ~25 sites collecting `<bool>` from `changes`, plus the negative-control record; `test/infrastructure/panel/panel_visibility_broadcast_test.dart` and `test/application/panel_controller_test.dart:107` collect it too.
- `test/application/correction_controller_test.dart` -- `_Harness.show()`/`hide()` drive the fake; `test/application/state_equality_test.dart` owns `CorrectionState` equality.
- `test/platform/panel_visibility_live_test.dart` -- the bodyless owed-claims test whose skip reason enumerates what this container cannot observe. It books DW-12's close, DW-33's map-without-focus and DW-32's latched click-away, and mentions `minimize` only for the keyboard question.

## Tasks & Acceptance

**Execution:**
- `lib/src/domain/panel/panel_visibility.dart` -- add `enum PanelVisibilityState { shown, dismissed, iconified, focusLost }` with `bool get isVisible => this == shown`, and retype `changes` to `Stream<PanelVisibilityState>` -- the port is where "why" has to live. Document per member which gestures reach it, leading with the ones a user can actually perform today (`iconified` is a workspace switch or a show-desktop gesture now, and a task-bar minimise once the geometry bundle offers one), and never naming the tray menu as a route to `dismissed`. State `changes`' emission rule as **a transition of the state**, and correct the two-subscribers claim.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- give `_setMirror` the state instead of a bool, split a private `_hide(PanelVisibilityState)` out of `hide()` so the focus-loss route can differ from a requested one, and pass the departure through `_dismiss` alongside its existing log `cause` -- the cause is the operator's vocabulary and the departure is the session's; they are not the same fact.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- **make `_setMirror` report a departure that re-attributes an absence, not only one that moves the mirror**: when the mirror already reads false and a different departure is now the true one, the new departure is emitted and remembered. A repeat of the same departure emits nothing, and the `shown` side is untouched -- see Design Notes for why this is the fix and what it must not become.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- `assert(!departure.isVisible)` wherever a departure is taken (`_hide`, `_dismiss`, and `_setMirror`'s departure path), and correct `_setMirror`'s doc claim that "the compiler forces every route to be named" -- the compiler forces a value, not a valid one, and the mirror direction is inferred from it.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- rewrite the `minimize` arm's DW-30 paragraph, the `_setMirror` `_focused` passage that names a re-summon as "the DW-30 cost", and the class doc where they state the old behaviour -- a comment that still calls this a live defect is worse than none.
- `lib/src/application/correction_controller.dart` -- remember the last state `changes` reported, not only the last departure, so a duplicate `shown` from an out-of-contract adapter is inert rather than destructive; decide the session with an exhaustive `switch` **expression** over the remembered departure, so a member added later cannot inherit "the session survives" by falling into a grouped arm.
- `lib/src/application/correction_controller.dart` -- name the narrowing where CAP-2 is cited: the panel is pre-filled on the summon after a dismissal, and a return from an iconify or a focus loss keeps the session instead. Cite the authority (the human's rule of 2026-08-14 on DW-30) rather than leaving the only record in a test comment -- AGENTS.md requires a divergence from the SPEC to be said out loud.
- `lib/src/application/correction_state.dart` -- make `isFreshSession` a `final bool` defaulting to false, keep it out of `copyWith`, and add it to `==`/`hashCode`. **`empty` keeps the marker false and stays the controller's initial state; a separate `freshSession` constant carries the marker and is what `_beginSession` emits** -- "the daemon has never shown a panel" and "a session just began" must not be the same value, because `CorrectionPanel` reads `_controller.state` synchronously in `initState`. Rewrite the doc that defended the old imprecision, and the `editorText` doc that still says the editor is seeded on every show.
- `lib/src/ui/daemon_home.dart`, `lib/src/ui/panel/original_text_pane.dart` -- **doc-only** corrections: `daemon_home`'s route list no longer ends at the panel for a window-manager restore (a de-iconify raises no show request and now begins no session, so a restore with settings up stays on settings, which is where the user left it), and neither file may keep claiming a session begins on every show. Change no code in either file.
- `test/fakes/fake_panel_visibility.dart` -- emit `dismissed` from `hide()`, `focusLost` from `loseFocus()`, and add `minimize()`/`restore()`, with the same re-attribution rule as the adapter so the ring can compose two departures -- the ring cannot test a distinction its fake cannot express.
- `test/application/correction_controller_test.dart` -- cover every session row of the matrix through the fake, plus four rows the first pass left unpinned: a dismissal arriving *after* an iconify or a focus loss still ends the session; a correction still in flight across a survivable departure lands into the session that returns, and its `failed` twin, because the first acceptance criterion promises the error survives too; a duplicate `shown` begins no second session. Correct any existing test name or comment that overclaims (e.g. "every show re-seeds", or naming the tray as a way to dismiss), and route the focus-loss sites through one form rather than adding a helper nothing calls.
- `test/ui/panel/correction_panel_*_test.dart` (whichever harness fits) -- one row for where the caret is after a return that begins no session, driving the fake's `loseFocus()` then `show()`. The consumers change no behaviour, but the *user-visible* half of the intent ("typed text survives") is asserted only at the controller until a widget row stands behind it.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- retype the collected emissions and add attribution rows for `hide()`, the `close` arm, both focus-loss routes, the `minimize` arm, the latched `restore`, an external `hide`, **and the re-attribution rows: a `close` after a believed `minimize` reports `dismissed`, and a repeat of the same departure reports nothing.** Use one convention for naming the enum values in this file and the two other test files that collect them -- four bare library-level consts called `shown`/`dismissed`/`iconified`/`focusLost` in a 2900-line file is not one. Update the negative-control record, including a reading note wherever an entry names a line that moved from `hide()` into `_hide`.
- `test/infrastructure/panel/panel_visibility_broadcast_test.dart`, `test/application/panel_controller_test.dart` -- retype the collected emissions; the broadcast and transition-only claims are unchanged and must stay pinned.
- `test/application/state_equality_test.dart` -- pin that a hand-cleared idle state is `!=` `CorrectionState.freshSession`, that `empty` is not the fresh state either, and that `copyWith` never carries the marker -- this is DW-54's whole content at the state level.
- `test/platform/panel_visibility_live_test.dart` -- add one owed claim to the skip reason: that a real task-bar minimise, workspace switch and show-desktop gesture reach the adapter as a `window-state-event` carrying `minimize` rather than as a `hide`, and that a real dismissal reaches it as `hide` or `close`. The event *name* now decides whether the user's text survives, so the premise is no longer merely a mirror-accuracy question. Do not touch the numbered steps or the results table of `runtime-observation-checklist.md`.

**Acceptance Criteria:**
- Given a panel with text the user typed, when it goes away by a focus loss or an iconify and comes back, then the text, the suggestions and any error are exactly as they were and the clipboard was not read.
- Given a panel with text the user typed, when the user dismisses it with the hotkey or the close control and summons it again, then the editor holds the current clipboard text and the state is otherwise empty.
- Given a panel that went away by an iconify or a focus loss, when a real dismissal follows while it is still away, then that dismissal is what the next summon obeys — the session ends and the clipboard is re-read.
- Given a `minimize`/`restore` pair arriving while a request of ours is outstanding, when the pair completes, then the mirror reads true, `changes` reported `iconified` then `shown`, and no session began.
- Given the two `isFreshSession` consumers, when this change lands, then neither changes behaviour, both still act exactly once per session beginning, and any edit to either file is confined to doc comments.
- Given `dart analyze --fatal-infos`, when it runs over the change, then every `switch` over `PanelVisibilityState` is exhaustive with no default arm.

## Spec Change Log

### 2026-08-20 — review pass 1 (bad_spec)

**Triggering finding.** All four review layers independently found the same live defect: a departure that arrives while the mirror already reads false is never reported, because `_setMirror` early-returns when `isVisible` does not change. `show, focus, minimize, close` emits `[shown, iconified]` while the window genuinely unmaps, so the controller's remembered departure stays survivable and the summon after an explicit close restores the session the user just closed, with CAP-2's re-seed never running. Reproduced at both rings.

**Root cause, stated plainly.** The Boundaries clause inside `<intent-contract>` asserts that "two departures in a row cannot both emit — the second finds the mirror already false", and treats that as harmless. It is not harmless: under the three-way rule the *last* departure is what decides the next session, so a swallowed one inverts the human's answer on the one gesture DW-12 defines as a dismissal. That sentence is a **description that turned out to be false**, not a requirement the intent placed. It is inside the read-only block and has not been edited; the corrected mechanism is carried here and in Tasks, Design Notes and Verification, which supersede it. The binding half of the same clause — `changes` never emits for a request that moves nothing, and never lies — still holds: a re-attribution reports a real change of state, and a repeated departure emits nothing.

**What was amended.** Tasks gained the re-attribution rule, `assert(!departure.isVisible)` guards, remembering the last *state* rather than the last departure, an exhaustive switch expression for the policy, a separate `freshSession` constant so the controller's initial state is not value-identical to a session beginning, doc-only corrections in `daemon_home.dart` and `original_text_pane.dart`, a CAP-2 narrowing note with its authority, an owed platform claim in `panel_visibility_live_test.dart`, and four missing test rows (composed departures, an in-flight run and its `failed` twin across a survivable departure, a duplicate `shown`, and a widget row for the caret). Acceptance criteria gained the composed-departure rule and replaced "neither file is edited" with "neither changes behaviour, and any edit is confined to doc comments". Verification relaxed the two manual checks that forbade the doc-only and owed-claim edits, and gained gates for the new mechanism. Prose errors named for correction: the tray is not a route to `dismissed` (its menu is open-panel and Quit), `changes` has one production subscriber and not two, and a task-bar minimise is not a gesture a user can perform until the geometry bundle lands.

**Known-bad state avoided.** A shipped adapter where the user closes an iconified panel and the next summon hands back the session they closed — the mirror image of DW-30, arrived at through DW-30's own fix — plus a spec whose acceptance criteria forbid correcting the doc comments this change falsified.

**KEEP — these survived review and must survive re-derivation.**
- The port/policy split exactly as it was: a descriptive enum in the domain, the session rule in `CorrectionController`, `isVisible`/`show()`/`hide()` untouched, `PanelController` untouched.
- The adapter's attribution table for every mirror move it makes, and `_dismiss` carrying the log `cause` and the departure as two separate facts with the log strings unchanged.
- `_lastDeparture` initialised so the first summon is a session with no special case.
- `isFreshSession` as a stamped field, absent from `copyWith` in both directions and present in `==`/`hashCode`.
- The `DW-30: every departure is named where the mirror moves` adapter group, the `which returns begin a session` controller group, and the two DW-54 equality rows — all of them, extended rather than rewritten.
- The negative-control record's honest new entry, including its count and the rows it names.
- The Never list held throughout: no `_bmad-output/` edits, no seam widening, no session counter, no second stream, no eager clearing, no `setSkipTaskbar` or geometry change.
- The previous pass's full attempt is saved at `dw-30-panel-session-reason-and-marker-attempt.patch` beside this spec. Read it; do not apply it blind.

## Review Triage Log

### 2026-08-20 — Review pass

- intent_gap: 0
- bad_spec: 7: (high 0, medium 5, low 2)
- patch: 9: (high 0, medium 1, low 8)
- defer: 0
- reject: 2: (high 0, medium 0, low 2)
- addressed_findings:
  - `[medium]` `[bad_spec]` A departure arriving over an already-false mirror is swallowed, so a dismissal after an iconify or a focus loss never reaches the controller and the next summon restores the session the user closed — spec amended with the re-attribution rule, its acceptance criterion and its mutation gate.
  - `[medium]` `[bad_spec]` `daemon_home.dart`'s claim that every route in ends at the panel, and its "every `show()` of a hidden window begins a fresh session", are both falsified by this change while the spec's acceptance criteria forbade editing the file — amended to doc-only edits with behaviour frozen.
  - `[medium]` `[bad_spec]` Three more doc comments still state the two-way rule (`correction_state.dart`'s `editorText`, `daemon_home.dart:50`, `original_text_pane.dart:7-8`) — named individually in Tasks and the Code Map.
  - `[medium]` `[bad_spec]` The first acceptance criterion promises a surviving error, and no row pinned an in-flight or failed correction across a survivable departure — two rows added to Tasks.
  - `[medium]` `[bad_spec]` The event-name premise the whole attribution table rests on (which gesture arrives as `minimize` rather than `hide`) is asserted only against `FakePanelWindow` and booked as an owed claim nowhere; it now gates user data — an owed claim added to `panel_visibility_live_test.dart`, with the runtime checklist still out of scope.
  - `[low]` `[bad_spec]` The spec's own acceptance criterion and four pieces of prose named the tray menu as a route that dismisses the panel; the tray has open-panel and Quit only — corrected in the criterion and named for correction in the code.
  - `[low]` `[bad_spec]` The Tasks bullet said to set the marker on `empty`, making the controller's initial state value-identical to a session beginning at the one place a consumer reads the state outside the stream — a separate `freshSession` constant is now required.


### 2026-08-20 — Review pass 2

- intent_gap: 0
- bad_spec: 0
- patch: 13: (high 1, medium 3, low 9)
- defer: 2: (high 0, medium 1, low 1)
- reject: 6: (high 0, medium 0, low 6)
- addressed_findings:
  - `[high]` `[patch]` The `hide` event arm re-attributed a survivable departure to `dismissed`: a click-away emits `focusLost`, and when the platform hide is abandoned at the bound (DW-28) its late GTK `hide` echo passed the repeat guard and emitted `dismissed`, so the next summon discarded the typed text — DW-30's own defect through this change's door. Reproduced by two reviewers independently and again by the implementer before the fix. The arm is now gated on `_visible` exactly as the `minimize` arm is, which costs nothing because `window_manager` 0.5.2 raises `hide` only from the GTK widget signal an in-process `gtk_widget_hide` fires; pinned by a row in the DW-28 group and negative control 31.
  - `[medium]` `[patch]` The port doc contradicted itself — "nothing is reported for a `hide` at a hidden one" against "a different departure over an already-away panel is reported", where a close at an iconified panel takes the second path. Restated as three bullets, with the repeat guard named as the only sense in which the first clause holds.
  - `[medium]` `[patch]` "An external unmap" cannot reach this adapter as a `hide` event; the arm, the class doc's route lists, the port's `dismissed` member and the row's premise all said it could. Restated with the plugin citation as what it is: the echo of our own request.
  - `[medium]` `[patch]` AD-8's spine snippet still declares `Stream<bool> get changes` with nothing in the code recording it. A note above `PanelVisibility` now says so and that the correction is owed to the orchestrator, `_bmad-output/` being off-limits.
  - `[low]` `[patch]` The controller's rule depended on an invariant kept three `if (_visible)` guards away in the adapter: a survivable departure arriving after a real `dismissed` would have handed back the session the user closed. `_lastReported` became a `_dismissalStands` latch, still decided by an exhaustive switch expression, so the ring that owns the rule enforces it; the duplicate-`shown` property is preserved as the latch's consumption.
  - `[low]` `[patch]` `FakePanelVisibility`'s new already-away guard was pinned by nothing (measured 0) — given a row that asserts the fake's own emissions, with the reason it is asserted there rather than through the controller.
  - `[low]` `[patch]` The fake claimed to implement the port's transition rule "in the same shape the adapter implements it" while diverging on a refused `show()` — claim dropped, simplification named.
  - `[low]` `[patch]` The empty-clipboard guard's comment said the skipped emission "changes nothing"; `copyWith` drops the marker, so it would announce the session ending one round trip after it began. Reason corrected, and the stale-marker consequence recorded where it lives.
  - `[low]` `[patch]` The `empty`/`freshSession` split was justified by an `initState` behaviour `CorrectionPanel` does not have. Re-justified on value equality and the stale-marker case, in the state doc and the test comment that repeated it.
  - `[low]` `[patch]` `!departure.isVisible` was asserted three times on one value down one call chain — one assert now, at `_hide`'s boundary. The enum was not split: one enum on one stream stands.
  - `[low]` `[patch]` New rows cited DW ids where AGENTS.md §7 asks for the capability id — CAP ids added across all 14 new or renamed rows.
  - `[low]` `[patch]` `daemon_home_test.dart`'s note that deleting the `isFreshSession` guard "left the entire suite green" was falsified by the stamped marker; corrected against a re-measurement, and DW-54's hand-cleared-editor case pinned at the consumer surface.
  - `[low]` `[patch]` `daemon_home.dart`'s new claim that a window-manager restore is not a route that ends at the panel had no row — added, with a contrast half so it cannot pass by the view being inert.

### 2026-08-20 — Review pass 3

- intent_gap: 0
- bad_spec: 0
- patch: 13: (high 0, medium 4, low 9)
- defer: 3: (high 0, medium 3, low 0)
- reject: 8: (high 0, medium 0, low 8)
- addressed_findings:
  - `[medium]` `[patch]` The `iconified` arm of `_dismissalStandsAfter` was pinned by nothing: replacing it with a flat `false` left every suite green, so a regression there would silently hand back a session the user had closed by dismissing and then switching workspaces — the exact sequence the latch's own doc names. Measured before and after; the existing survivable-departure row is now parameterised over both `focusLost` and `iconified`, and the mutation fails the `iconified` row alone.
  - `[medium]` `[patch]` `daemon_home.dart`'s hotkey-draft paragraph still justified the draft discard as "the same rule AD-18 gives the panel", a parity DW-30 destroyed — the panel's text now survives a focus loss while the draft still dies on one — and still read "Filed for whoever decides", though DW-78 was decided on 2026-08-14 ("keep the draft") explicitly citing the human's DW-30 answer. Both halves corrected.
  - `[medium]` `[patch]` `_reportDeparture`'s and `_deferredBlur`'s docs both asserted that a `hide()` at a hidden panel never reaches the emitter — false whenever the standing departure is `focusLost` or `iconified`, which is precisely the re-attribution the `close` arm depends on. Restated to say when the repeat guard actually returns.
  - `[medium]` `[patch]` `iconified`'s doc did not hand off to the panel-window-geometry bundle. The human's rule ends a session on a minimise *to the tray* and keeps it on a minimise *to the task bar*; only the second is this member, and once DW-50/DW-53/DW-61/DW-72 make the task-bar entry conditional, a tray-minimise arriving as a GTK `minimize` would invert the rule with every row green. The requirement is now stated at the member.
  - `[low]` `[patch]` Negative control 27 recorded 5 failures; re-measured at 6 against a baseline confirmed green (80/80). The missed row is the DW-28 abandoned-focus-loss row control 31 also cites. Count and enumeration corrected.
  - `[low]` `[patch]` `daemon_home_test.dart`'s note claimed deleting the `isFreshSession` guard "fails exactly this row and nothing else"; re-measured at two rows — it also fails the DW-54 hand-cleared-editor row added thirty lines below in the same change. Corrected, with the note that the CI-scoped `dart test` command does not run `test/ui` at all.
  - `[low]` `[patch]` The `_deferredBlur = false` the `_setMirror`/`_reportDeparture` split left on the `shown` path was recorded nowhere and fails nothing (measured 0 against a green baseline), while the DW-30 reading note left control 10 ambiguous between two such lines. Recorded as negative control 32 with its own falsifiable reason.
  - `[low]` `[patch]` Six control entries name `hide()` and `_setMirror` as whole methods, but the reading notes covered only entries naming a *line* — and `hide()` no longer has a body for a line to be deleted from. Notes widened to cover method references, with control 32 named as the one entry that means `_setMirror` literally.
  - `[low]` `[patch]` `test/architecture/panel_event_forwarding_test.dart`'s arm list — written to be checked against the adapter — still said "`minimize` writes the mirror straight, guard or no guard", which is the mutation now pinned as negative control 30, and omitted the `hide` arm's new `_visible` condition. Both bullets corrected.
  - `[low]` `[patch]` `_dismissalStands`'s doc rested the adapter-side invariant on "three `if`s"; the blur leg is negative control 12 at 0 failures — the invariant is held there by `_focused`'s lifecycle, not by that clause. Restated as two pinned gates plus one field's lifecycle.
  - `[low]` `[patch]` The DW-54 equality row's reason claims `empty` and `freshSession` "differ in nothing but the marker" while asserting only `!=`, which stays true if the two constants drift in something else. Field-by-field parity now asserted, plus `freshSession.copyWith() == empty`; gated by a drift mutation that fails that row alone.
  - `[low]` `[patch]` `CorrectionState`'s constructor is public and the marker an ordinary named parameter, so any caller could stamp a completed or failed session as a session *beginning* — DW-54's conflation through the one door the type's doc claimed was shut. A constructor assert now enforces it over the const-evaluable fields, pinned by a row that fails when the assert is removed.
  - `[low]` `[patch]` `original_text_pane.dart`'s focusNode doc concluded "the behaviour is unchanged" about the settings remount path. True only while every show began a session; under the three-way rule a remount can now happen with no session behind it, making `autofocus` its own decision there rather than an echo of the session rule. Behaviour deliberately left as it is — the user is being handed the panel — and the doc now says which.

## Design Notes

Why an enum rather than a sealed family: the departures carry no payload, and the tests compare *lists of emissions* (`expect(emitted, [shown, dismissed])`). An enum gets value equality free; a sealed family would need `==`/`hashCode` written for no gain. AGENTS.md §6 wants exhaustive switches, which the enum gives.

Why the controller remembers the departure rather than the port announcing "this show begins a session": the port would then own AD-18, and the same adapter would have to be re-taught if the rule changed. The port states a fact about the window; the ring decides what it costs.

**The re-attribution rule, and its boundary.** `isVisible` is a two-valued mirror, but the stream is four-valued, so "nothing changed" and "the mirror did not move" stopped being the same question the moment the reason started deciding the session. A window that is already away can still have the *reason it is away* replaced — the user iconifies the panel and then closes it — and that replacement is a real change of state, so it is reported. Three boundaries keep this from becoming a chatty stream: a repeat of the same departure reports nothing, the `shown` side is untouched (`show()` at a visible panel still emits nothing at all), and no departure is invented where none was expressed. That is the whole of it; anything wider would break the emission rule the port has always had.

The guard the adapter needs is "have I already reported this?", not "did the mirror move?" — the mirror is what the guard used to stand in for, and the stand-in stopped fitting when the stream grew a third and fourth value. There is exactly one way to be up, so a `shown` over a true mirror is still nothing; there are three ways to be away, so a departure over a false mirror can still be news.

```dart
// correction_controller.dart — the whole policy
if (visibility == PanelVisibilityState.shown && _beginsSession(_lastReported)) {
  _beginSession();
}
_lastReported = visibility;

/// Whether a panel that went away this way comes back to a new session.
bool _beginsSession(PanelVisibilityState departure) => switch (departure) {
  PanelVisibilityState.dismissed => true,
  PanelVisibilityState.iconified => false,
  PanelVisibilityState.focusLost => false,
  // Not a departure: a duplicate `shown` is an adapter breaking the port's
  // contract, and the session already on screen is the one to keep.
  PanelVisibilityState.shown => false,
};
```

Remembering the last *reported* state rather than the last departure is what makes a duplicate `shown` inert, and the switch expression is what makes a fifth member a compile error rather than a silent vote for "the session survives". `_lastReported` starts at `dismissed`, which is what makes the first summon a session without a special case.

**What this does not fix, and must be written down where it lives.** `_setMirror`'s `_focused` passage names one route to a mirror reading false over a window that is mapped *and still focused*: a hide the window refused. The departure recorded there is `dismissed` — the user did ask — so the repairing press still starts a fresh session over text that never left the screen. That residual is correct under this rule rather than a leftover of the old one, and the comment must say so instead of continuing to call it "the DW-30 cost". The other case that passage names, an external `minimize`/`restore` whose focus-in beats the `restore`, is fixed: the departure is `iconified`, so the press returns the panel with its text.

**Two consequences of the rule that are the rule working, not defects.** A session that survives is *the whole session*, so a panel whose editor still holds only the clipboard seed comes back with that seed even if the user copied something else while away — the way out is a dismissal, which is the gesture that means "start again". And the caret comes back where the user left it, including in the suggestions region after a submit, because nothing was rebuilt. Both follow from "typed text survives the restore" and neither is this change's to re-decide; the widget row exists to make the second one visible rather than to change it.

Note also that a task-bar minimise is not reachable by a user today — `setSkipTaskbar(true)` is unconditional until the panel-window-geometry bundle lands. The `iconified` departure is still live now (a workspace switch or a show-desktop gesture iconifies), and the sequencing dependency is on the *gesture* being offered, not on this code. Documentation must lead with the reachable gestures for that reason.

## Verification

**Commands:**
- `dart analyze --fatal-infos` -- expected: no issues (`flutter_lints` reports at INFO, so the bare form is a weaker gate than AGENTS.md §6 asks for).
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: green. The baseline for this change is 913 passing, 2 skipped; any failure outside `wayland_portal_global_hotkey_test.dart`'s known load-sensitive flake is a real one.
- `flutter test test/composition test/ui` -- expected: green; these need a Flutter binding and are outside the scoped `dart test` command.
- `flutter test test/platform/window_manager_panel_window_test.dart` -- expected: green; the forwarder is untouched and this proves it.
- `dart test test/architecture/runtime_checklists_test.dart` -- expected: green; it guards the checklist and the live tests' skip strings, and one of those strings gains an owed claim.
- `dart format --output=none --set-exit-if-changed lib test` -- expected: no reformatting needed.

**Manual checks:**
- `git status --porcelain -- _bmad-output/` -- expected: only this spec and the saved attempt patch. Nothing under `_bmad-output/` is edited.
- `git diff -- test/platform/` -- expected: only `panel_visibility_live_test.dart`'s skip reason, gaining the owed event-name claim. No numbered step, no results-table row, no change to `runtime-observation-checklist.md`.
- `git diff -- lib/src/ui/panel/correction_panel.dart lib/src/ui/daemon_home.dart lib/src/ui/panel/original_text_pane.dart lib/src/application/panel_controller.dart` -- expected: doc-comment lines only, and nothing at all in `correction_panel.dart` or `panel_controller.dart`. Confirm by reading the diff, not by counting lines.
- Mutation-verify each gate, restoring sources from a scratchpad copy rather than `git checkout --`: (a) `_dismiss`'s focus-loss route made to pass `dismissed`; (b) the re-attribution removed so `_setMirror` early-returns whenever `isVisible` does not move; (c) the controller's session decision made unconditional so every `shown` begins a session; (d) `copyWith` made to carry `isFreshSession`; (e) `isFreshSession` removed from `==`; (f) `_lastReported` written only on departures, so a duplicate `shown` re-begins a session. Each must fail the rows that name it and nothing else. Confirm the baseline run is green first — a scope string that does not word-split makes every gate report the same fake count.

## Auto Run Result

Status: done
Blocking condition: none

### What this run did

A third, independent review pass over the committed DW-30/DW-54 change — no code was re-derived. Four review layers ran in parallel (adversarial, edge-case, verification-gap, intent-alignment) over the full diff since `916303f`. Thirteen findings were patched, three deferred to the ledger, eight rejected. No intent gap and no spec defect: the change implements the human's 2026-08-14 three-way rule as pass 1 adjudicated it.

The one substantive hole was a coverage gap at the ring this change is about. `_dismissalStandsAfter`'s `iconified` arm was pinned by nothing — replacing it with a flat `false` left all 943 dart rows and all 147 widget rows green — so a regression there would have handed back a session the user closed by dismissing the panel and then switching workspaces, the mirror image of DW-30 that the latch exists to prevent. The existing survivable-departure row is now parameterised over both survivable departures and the mutation fails the new one alone. Everything else was a false or unmeasured claim: two negative-control counts that did not reproduce, a guard recorded nowhere, two adapter docs asserting an emission path that is reachable, a doc justifying itself by a parity DW-30 destroyed, and a decided ledger entry still filed as an open question.

Note for the orchestrator: this pass began with the spec's entire committed `## Auto Run Result` section (67 lines) deleted in the working tree and nothing else modified — the same unexplained truncation seen twice on `spec-dw-31`. The truncated file was backed up to the scratchpad and restored with `git checkout HEAD --` before any work began.

### Files changed

- `lib/src/domain/panel/panel_visibility.dart` — `iconified` gains the hand-off the geometry bundle needs so a future tray-minimise cannot invert the human's rule.
- `lib/src/application/correction_controller.dart` — the latch doc's "three `if`s" restated as the two pinned gates plus `_focused`'s lifecycle, which is what actually holds the blur leg.
- `lib/src/application/correction_state.dart` — a constructor assert making "the marker belongs to `freshSession` and no other shape" enforced rather than merely documented.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` — `_reportDeparture` and `_deferredBlur` docs corrected: a `hide()` at a hidden panel returns at the repeat guard only when the standing departure is already `dismissed`.
- `lib/src/ui/daemon_home.dart` — the hotkey-draft paragraph: the AD-18 parity claim retired, DW-78 recorded as decided rather than filed.
- `lib/src/ui/panel/original_text_pane.dart` — the focusNode doc's "behaviour is unchanged" narrowed to what the three-way rule left true.
- `test/application/correction_controller_test.dart` — the survivable-departure row parameterised over `focusLost` and `iconified`.
- `test/application/state_equality_test.dart` — field-by-field parity between `empty` and `freshSession`, and a row pinning the new constructor assert.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` — control 27 corrected to 6 with the missed row named, control 32 added, reading notes widened to method references.
- `test/ui/daemon_home_test.dart` — the guard's measurement corrected to two rows, with the CI-scope caveat.
- `test/architecture/panel_event_forwarding_test.dart` — the `hide` and `minimize` arm descriptions brought back in line with the gates this change added.

### Review findings

Four layers, one pass. **0 intent_gap, 0 bad_spec, 13 patch (high 0, medium 4, low 9), 3 defer, 8 reject.** All 13 applied; see the Review Triage Log entry for pass 3 for each.

**Deferred — appended to `deferred-work.md` as new entries, per this run's invocation.** No existing entry was modified, re-opened or rewritten.

1. *CAP-2's success clause in `SPEC.md`, and AD-8's and AD-18's spine snippets, are falsified by the shipped code* and recorded only in Dart doc comments, `_bmad-output/` being off-limits to code work. The orchestrator's to regenerate. (medium)
2. *The gesture-to-event-name premise is assumed, not observed*, and now decides whether the user's typed text survives; it is booked in a skip string with no owner, and the checklist's numbered steps are DW-9's. (medium)
3. *An abandoned `hide` landing after a completed `show` is attributed `dismissed`* even when issued under a focus loss — the one door DW-30's own defect can still come through. Fixing it means attributing from the intent the call was issued under, a design change to the abandonment discipline. (medium)

Items 2 and 3 were deferred by the previous pass, whose invocation forbade ledger edits; they are filed now rather than raised anew.

**Rejected — eight, six of them re-litigating decisions the earlier passes already took on the record:** the `<intent-contract>` clause that "two departures in a row cannot both emit" (pass 1 adjudicated it a false description superseded by Tasks and Design Notes; the human's three-way rule governs); restoring the three `assert(!departure.isVisible)` sites (pass 2 reduced them to one at `_hide`'s boundary); introducing a `PanelDeparture` type or splitting the enum (pass 2: one enum on one stream); adding a guard and row for the sticky `isFreshSession` on the empty-clipboard path (documented, inert, and the proposed emission fix is rejected in the comment's own reasoning); renaming `copyWith` (the Always list mandates it drop the marker). Plus two new ones: making `_setMirror` switch exhaustively rather than dispatch on `isVisible` (speculative future-member hazard), and dropping `autofocus` from `original_text_pane` (the outcome — the caret in the editor when the user is handed the panel — is benign; only the doc claim needed fixing).

**Follow-up review recommended: true** — patched this pass: 0 high, 4 medium, 9 low; score `3x4 + 1x9 = 21`, at or above the threshold of 5.

### Verification

- `dart analyze --fatal-infos` — no issues.
- `dart format --output=none --set-exit-if-changed lib test` — 174 files, 0 changed.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` — 945 passing, 2 skipped (baseline 943/2; +2 from the new rows).
- `flutter test test/composition test/ui` — 147 passing.
- `flutter test test/platform/window_manager_panel_window_test.dart` — 6 passing.
- `dart test test/architecture/runtime_checklists_test.dart` — 39 passing.
- Mutation gates, five, each against a baseline confirmed green first and each restored from a scratchpad copy rather than `git checkout --`: (a) `iconified => false` in `_dismissalStandsAfter` — 0 failures before the new row, exactly the new `iconified` row after; (b) both focus-loss `_dismiss` calls passing `dismissed` — 6 failures, names captured, control 27 corrected; (c) the `isFreshSession` guard deleted from `DaemonHome` — 2 failures, both named; (d) `_deferredBlur = false` deleted from `_setMirror`'s `shown` path — 0 failures, recorded as control 32; (e) the new constructor assert removed, and `freshSession` drifted from `empty` in `suggestionTexts` — each fails its own row alone.
- Every patch confirmed present in the tree afterwards by grepping a short fragment of each, `dart format` rewrapping considered.
- Manual: nothing under `_bmad-output/` edited except this spec and the three new ledger entries; no existing ledger entry modified.

### Residual risks

- **The three deferred items are the live ones**, and the third is a reachable path to DW-30's own symptom: a click-away, a summon, then the abandoned hide's late echo discards the user's text. It is narrow — it needs the platform call to miss the DW-28 bound — but it is not hypothetical.
- **The governing documents still say the opposite of the code** on CAP-2, AD-18 and AD-8. Anyone reading spec-first will read the code as the bug until the orchestrator regenerates them.
- **`iconified` still has no user-reachable gesture** beyond a workspace switch or show-desktop, and the geometry bundle is where that changes. The hand-off is now written at the enum member, but it is a comment, not a gate.
- **The new constructor assert is debug-only**, as all Dart asserts are; it documents and pins the invariant but does not enforce it in a release daemon.
- **The negative-control record has now been wrong three times** across three passes (controls 20, 27, and the `daemon_home_test` note twice). Each was corrected against a re-measurement, but the pattern suggests the counts drift whenever rows are added near them rather than being re-taken.
- **The parity assertions added for `empty`/`freshSession` are partly redundant with the new constructor assert**, which rejects most drift at const evaluation; only `suggestionTexts` drift reaches the row itself.

### Residual artifacts

None. Every file in the reviewed diff is in the commit; `git status --porcelain` is empty afterwards.
