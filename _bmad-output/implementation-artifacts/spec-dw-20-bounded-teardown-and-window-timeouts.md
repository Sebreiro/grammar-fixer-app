---
title: 'Bounded teardown steps and window requests, under one stated policy'
type: 'bugfix'
created: '2026-08-14'
status: 'done'
baseline_revision: 'ae97e87'
final_revision: '8f7c8d4'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
warnings: ['oversized']
---

<intent-contract>

## Intent

**Problem:** Two awaits in the daemon can hang forever. `DaemonLifecycle._step` wraps `await run()` in try/catch, which does nothing for a step that never *completes* — `_disposeControllers` reaches `CorrectionController.dispose()`'s unbounded `Future.wait(_pendingSaves)` and `_closeDatabase` awaits drift's background isolate — so every `exit(0)`/`exit(1)` in the process sits behind one un-timed future (DW-20). `WindowManagerPanelVisibility._enqueue` chains each request onto `_queue` with no bound, so one window call that never settles parks the whole chain and the panel stops responding until restart (DW-28).

**Approach:** State **one** policy — how long a single platform call may hold the daemon before it is abandoned — at the composition root, and pass it to both places rather than letting each invent a number. A teardown step that exceeds it is logged by name and the remaining steps still run, so shutdown always reaches its exit. A window request that exceeds it is logged, abandoned, and the queue advances so the next press is served. `PanelVisibility.show`/`hide` then state what a resolved future means, which is also the contract half DW-35 was closed against.

## Boundaries & Constraints

**Always:**
- One policy value, defined once, referenced by both call sites. Both constructor parameters are **required**, so no site can silently acquire a second default.
- The bound is per teardown step and per window call, never a total deadline: `_step` continues to the next step after a stalled one, and `shutdown()` still completes.
- Only *our own* expiry is reported as a timeout. Use `.timeout(bound, onTimeout: ...)` with a local flag — never `on TimeoutException`, which would misreport a `TimeoutException` thrown by the step's own internals (e.g. `SingleInstanceLock.handshakeTimeout`) as this bound firing.
- A rejected call keeps its current behaviour: the error still reaches the caller in the panel adapter, and is still logged as `'$what failed'` in `_step`.
- Every new log line goes through the existing `_log` wrapper, so a broken logger cannot escape onto the teardown path.
- An abandoned future is *not* cancelled — Dart has no such thing. The bound stops the daemon waiting; it does not stop the underlying call.

**Block If:** the shipped budget cannot be a single value because one of the two sites demonstrably needs a different one — that reopens the policy question these two entries were bundled to answer once.

**Never:**
- No total/whole-teardown deadline, no retry, no cancellation token, no `Future.delayed` anywhere.
- Do not bound `main.dart`'s `_releaseWithoutLifecycle` loop, `WindowManagerPanelVisibility.dispose()`'s `_guard` steps, or `CorrectionController.dispose()`'s `Future.wait`. Same shape, different entries — out of scope here. (The lifecycle's own bound already covers the adapter's `dispose()`, because that runs *as* a step.)
- Do not change `dispose()`'s existing behaviour of abandoning the queue tail — DW-28 records that as intended; only its documentation changes.
- No signature change to `PanelVisibility` (AD-8 is verbatim); documentation only.
- Do not touch the deferred-work ledger.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Teardown step stalls | a `_step` whose `run()` never completes | after the bound: one `error` line naming that step, then the remaining steps run and `shutdown()` completes | log only; shutdown never rethrows |
| Teardown step throws | `run()` rejects | unchanged: `'$what failed'` with `error_type` | existing catch |
| Teardown step is quick | `run()` completes inside the bound | no timeout line | No error expected |
| Window call stalls | `_window.show()`/`hide()`/`focus()` never settles | after the bound: one `error` line naming the call and the bound; the request is abandoned; the caller's future **resolves**; `_queue` advances | log only |
| Stalled show | `_window.show()` stalls | `focus()` is never issued — no second call against an unresponsive window, and `gtk_window_present` must not map a window whose show was abandoned | log only |
| Window call rejects | `showError`/`hideError` armed | unchanged: the rejection reaches the caller and the chain survives it | caller's `catchError` |
| Logger throws while reporting either timeout | a `Logger.error` that throws | nothing escapes; teardown/queue proceed | swallowed by `_log` |

</intent-contract>

## Code Map

- `lib/main.dart` -- composition root; holds the policy constant beside the existing `_firstFrameBudget` (`:186`) and wires both constructors (`:112`, `:135`).
- `lib/src/infrastructure/system/daemon_lifecycle.dart` -- `_step` (`:245`) and the eleven calls it guards (`:212-226`).
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- `_enqueue` (`:141`), `_apply` (`:147`), and the `_outstanding` counter the mirror's reconciliation guard reads.
- `lib/src/domain/panel/panel_visibility.dart` -- the AD-8 port whose `show`/`hide` docs gain the contract statement.
- `test/infrastructure/system/daemon_lifecycle_test.dart` -- `_Harness` (`:596`) constructs the lifecycle; add the bound there.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- three construction sites (`:57`, `:241`, `:519`); `FakePanelWindow` parks every call until `settle()`, so "never settles" is simply never settling it.
- `test/infrastructure/panel/panel_visibility_broadcast_test.dart` -- fourth construction site (`:23`).
- `test/architecture/composition_wiring_test.dart` -- reads `main.dart` as text; the natural home for the "one policy, two sites" assertion.
- `test/fakes/throwing_logger.dart` -- the shared `ThrowingLogger` for the logger-throws rows.

## Tasks & Acceptance

**Execution:**
- `lib/main.dart` -- add a documented top-level `const Duration _unresponsiveCallBudget = Duration(seconds: 5);` next to `_firstFrameBudget`, and pass it to both constructors -- one policy, stated where the app is wired, so neither adapter carries a private default. Doc the reasoning: ten steps bound the whole teardown at 50 s (a unit with a shorter `TimeoutStopSec` still `SIGKILL`s first), and 5 s of an unresponsive panel beats the current forever.
- `lib/src/infrastructure/system/daemon_lifecycle.dart` -- add a required `Duration stepTimeout` field; in `_step`, run `await run().timeout(_stepTimeout, onTimeout: () { timedOut = true; })` and, when the flag is set, log one `error` naming the step and the bound (`context`: `timeout_ms`) -- a step that never completes must not be able to stop the exit. Extend `shutdown()`'s doc: the guarantee is now "never throws **and** always finishes", and an abandoned step's work may still be running when the process exits.
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- add a required `Duration requestTimeout` field and a private `Future<bool> _answered(String call, Future<void> Function() issue)` helper that awaits under the bound, logs and returns `false` on expiry; use it for `hide`, `show` and `focus` in `_apply`, returning early when a call did not answer -- the whole request is abandoned at the first stalled call, the existing `finally` restores `_outstanding`, and `_queue` advances. Document the fourth mechanism in the class doc: a bounded call, and why a late-landing abandoned call is repaired by the ordinary event reconciliation.
- `lib/src/domain/panel/panel_visibility.dart` -- state on `show()`/`hide()` that a resolved future means the request was accepted and has left the queue, **not** that the window moved: it may have been superseded by a later request, abandoned at disposal, or abandoned when the window did not answer within the implementation's bound. `isVisible`/`changes` are where the intent is observable (DW-35's contract half).
- `test/infrastructure/system/daemon_lifecycle_test.dart` -- pass a short bound from `_Harness`; add rows for the stalled-step, quick-step and throwing-logger scenarios in the matrix, asserting the recorded step sequence proves the remaining steps ran.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- pass a short bound at all three sites; add rows for every window-side matrix scenario plus the queue-advance and mirror-reconciliation ACs below.
- `test/infrastructure/panel/panel_visibility_broadcast_test.dart` -- pass the bound at its construction site.
- `test/architecture/composition_wiring_test.dart` -- assert `main.dart` hands the *same* named constant to both constructors -- the only place "one policy rather than two" is checkable.

**Acceptance Criteria:**
- Given a teardown step that never completes, when `shutdown()` runs, then it completes, every later step still ran in order, and exactly one `error` line names the stalled step.
- Given a request whose window call never settles, when a later `show()`/`hide()` is issued, then that later request is applied once the bound elapses — the panel keeps responding without a restart.
- Given a request abandoned at the bound, when the window later emits an event, then the mirror reconciles it — `_outstanding` returned to zero rather than freezing reconciliation for good.
- Given a superseded request, a disposal-abandoned request and a timed-out request, when each caller awaits its future, then all three resolve rather than throw — the uniform outcome the port now documents.
- Given the shipped composition root, when both adapters are constructed, then both receive the same policy constant.

## Spec Change Log

No entries: the review pass produced no `bad_spec` finding, so the spec was never amended and the code was never re-derived. The one factual correction — "ten" to "eleven" `_step` calls in the Code Map — is recorded in the triage entry below.

## Review Triage Log

### 2026-08-14 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 9: (high 0, medium 4, low 5)
- defer: 1: (high 0, medium 1, low 0)
- reject: 8: (high 0, medium 0, low 8)
- addressed_findings:
  - `[medium]` `[patch]` The `hide` and `focus` bounds were unverified — reverting either `_answered(...)` call site to a bare `await` left the whole scoped suite green (mutation-confirmed by the reviewer, re-confirmed independently here). Added a stalled-`hide` row and a stalled-`focus` row, each asserting the log's `call`/`timeout_ms` context; the focus row also asserts that a later window event still moves the mirror.
  - `[medium]` `[patch]` The class doc claimed the ordinary reconciliation repairs a late-landing abandoned call, unconditionally. It does not: `_reconcile` returns early while `_outstanding > 0`, so an echo landing during a later request is swallowed. Mechanism four now states that bounding a chain link surrenders serialisation and states the condition under which the repair holds; `_apply` gained the invariant that every await must go through `_answered`.
  - `[medium]` `[patch]` Added a row pinning the surrendered-serialisation behaviour itself (two calls outstanding, the abandoned `show` released during the later `hide`, the swallowed echo and the state that follows) — previously only the benign FIFO ordering was exercised.
  - `[medium]` `[patch]` The 1 s test bound governed every pre-existing row, so a loaded machine could silently turn a row that must never reach the bound into an abandonment that still passed. Ordinary rows now run under an unreachable 5-minute bound; the short bound survives only where reaching it is the behaviour under test. No new dependency.
  - `[low]` `[patch]` The policy doc's arithmetic was wrong: `_run()` issues eleven `_step` calls, not ten (55 s worst case, not 50 s), and the panel side can spend the bound twice in one `show` request. Restated against the step list so it cannot go stale; the Code Map above was corrected in the same pass.
  - `[low]` `[patch]` `shutdown()`'s "always finishes" over-claimed: the bound is armed after `run()` is invoked, so it covers a step whose future never completes, not a step that blocks the isolate. The doc now names that residual.
  - `[low]` `[patch]` The port doc's "only a window that refuses the call rejects" is false past the bound — `Future.timeout` drops the source's later completion, so a late refusal is reported as an abandonment. Sentence qualified.
  - `[low]` `[patch]` Nothing pinned the mirror after an abandonment (inserting `_setMirror(!intended)` stayed green). Added the assertion that the intent stands, matching the existing rejected-show row.
  - `[low]` `[patch]` The wiring guard did not guard: `(?!\s*_unresponsiveCallBudget)` is a prefix check that accepts `_unresponsiveCallBudget * 2`, and the flat `1..30` range admitted a value its own comment ruled out. The argument is now compared whole, and the ceiling is derived from the step count read out of the lifecycle source against systemd's 90 s default.

Deferred (1, medium): `main.dart`'s `_releaseWithoutLifecycle` loop awaits `graph.disposeControllers`, `panelVisibility.dispose` and `startup.database.close` unbounded, so the pre-lifecycle abort path can still hang before `exit(1)` — the same shape this change bounded on the other teardown path, and the loop's own doc promises "a database that will not close must not stop the address going back". Pre-existing and not caused by this change; `graph.disposeControllers` was added to that loop by the immediately preceding commit (`ae97e87`, DW-37). **Not appended to the deferred-work ledger**: this run was invoked with an explicit instruction not to edit the ledger, so it is reported to the orchestrator here instead.

Rejected (8, all low): reverting the mirror after an abandoned `show`/`hide` (contradicts the tested convention that a failed request leaves the intent standing, which the rejection path already establishes); issuing a compensating `hide()` after an abandoned `focus` (invents a recovery policy the intent does not state); asserting a positive `Duration` at both constructors (defensive code with no live path, and the wiring row already pins the shipped value); adding `'step': what` to `_step`'s log context (the message already names the step, and it would change the pre-existing rejection arm too); adopting `package:fake_async` (a new dependency; the exposure was removed instead); demanding evidence for "a lost write costs one correction" (SQLite's recovery bounds it to the uncommitted write); and two spec-hygiene notes about `status:` and the `oversized` warning, which are this workflow's own bookkeeping rather than defects.

### 2026-08-14 — Review pass (follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 11: (high 0, medium 3, low 8)
- defer: 2: (high 0, medium 1, low 1)
- reject: 8: (high 0, medium 0, low 8)
- addressed_findings:
  - `[medium]` `[patch]` The class doc claimed the `_outstanding` guard "keeps the late `show` echo of a superseded request from resurrecting the panel". It does not, and cannot: a *superseded* request issues no call at all, while an *abandoned* one leaves `_outstanding` at zero, so its late `show` is believed like any window-manager event — the mirror goes back to true, `changes` emits a second `true`, and `CorrectionController` starts a fresh session (AD-18). Mechanism four now states which echoes the guard covers and names the residual: the dismissed panel comes back, the mirror is honest about the window rather than about the last intent, and no compensating `hide` is invented. Pinned by a new row (abandoned `show` → completed `hide` → late map lands → `[true, false, true]`), which needed an out-of-order `FakePanelWindow.releaseCall` to pose at all.
  - `[medium]` `[patch]` The mirror after an abandonment was pinned on the `show` arm only — mutation-confirmed by the reviewer and re-confirmed here: `_setMirror(true)` on the unanswered-`hide` branch and `_setMirror(false)` on the unanswered-`focus` branch each left the whole scoped suite green. Both rows now assert the mirror and the `changes` transitions, and both mutations fail exactly their own row.
  - `[medium]` `[patch]` A call or step abandoned at the bound and *then* rejecting was exercised by nothing on either side: every rejection row runs under an unreachable bound, every abandonment row parks a call that is never released. The absorption is a property of `Future.timeout` keeping its handler on the source, not of anything this code states, and the obvious rewrites (`Future.any` + `Future.delayed`, a hand-rolled completer) turn a late refusal into an unhandled error on the exit path. One row per side now pins it. Both are mutation-confirmed against the hand-rolled-completer rewrite. The daemon row also documents why its completer is built *inside* the guarded zone: absorption is zone-sensitive, and a completer made outside reports on the harness rather than on `_step`.
  - `[low]` `[patch]` The policy doc's panel-side arithmetic was wrong about the case it names: the early return added in the same change means a window that answers *nothing* costs one budget per press, not two — only a window that answers the map and stalls the focus spends it twice. Restated, and the doc now also says what each side actually budgets, since the teardown side bounds a composite step rather than a single platform call.
  - `[low]` `[patch]` The 90 s ceiling was argued against a supervisor this project does not ship: there is no `.service` unit anywhere in the repo, and the daemon installs as an XDG autostart entry. `main.dart` and the wiring row now state that 90 s is systemd's stock default used as a reference, and that a desktop session's logout grace can be shorter — an argument for the worst case being low, not for it being affordable.
  - `[low]` `[patch]` The wiring guard permitted exactly the outcome it exists to reject: `lessThanOrEqualTo(90)` admits the SIGKILL instant itself, and the step product is not the whole stop. Now compared strictly against the grace less a reserved quarter for signal delivery, reaching `shutdown()`, and the exit flush.
  - `[low]` `[patch]` `_teardownStepCount()` regex-counted `await _step(` across the whole file — which picks up `_step`'s own declaration (12 rather than 11) and misses any step invoked through a helper, in a loop, or wrapped onto the next line by `dart format`. Now brace-scoped to `_run()`'s body and matched on the call, verified to yield 11 against a file-wide 12.
  - `[low]` `[patch]` `_apply`'s hide arm discarded `_answered`'s answer while every other arm branched on it — the one site where a later call gets appended without anyone noticing the guard was never there, which is precisely what the invariant comment above the method warns about. Now branched on.
  - `[low]` `[patch]` `_raisePanel` had no shutdown guard, and the bound made that newly reachable: an abandoned step 1 leaves both panel-request subscriptions delivering while steps 2 to 11 run, so a press landing there would map a window as the process heads for `exit(0)`. Guarded the way `start()` already is, and pinned by a row that keeps the subscription live through an uncancellable stream.
  - `[low]` `[patch]` `shutdown()`'s numbered ordering rationale went stale where it matters most: step 6's "closing it before step 2 would strand the write step 2 is waiting for" is exactly what an abandoned step 2 plus a continuing step 9 does, and the trade paragraph blamed process exit rather than a later step in the same sequence. The ordering is now stated as a best-effort sequence once a step is abandoned, with that case named.
  - `[low]` `[patch]` `_onBlur`'s guard comment ("a user cannot have dismissed a panel that is still being mapped") is no longer true after an abandonment. Qualified, with the reason the race is left standing rather than suppressed.

Deferred (2): both appended to the deferred-work ledger as new entries — (medium) `main.dart`'s `_releaseWithoutLifecycle` loop is still unbounded, so the pre-lifecycle abort path can hang before `exit(1)`; out of scope on this spec's own Never list, and the first pass could not file it because that run was instructed not to touch the ledger. (low) The shipped 5 s value has never been exercised against a real window manager or a real stop signal, and `runtime-observation-checklist.md` has no step for it.

Rejected (8, all low): tracking abandoned-but-in-flight calls so `_reconcile` distrusts their echoes (it would make the mirror claim `false` for a window that genuinely mapped — a lying mirror is worse than the resurrection, and the suite rejects the design: applied as a mutation it fails three rows); a consecutive-failure latch that stops re-issuing to a known-unresponsive window (a recovery policy the intent does not state, and per-press logging is what its matrix describes); closing DW-28's "never drained on dispose" half (the intent forbids changing `dispose()`'s tail behaviour); `assert(timeout > Duration.zero)` at both constructors (no live path, and weighed and rejected in the previous pass); rewriting the stall rows onto `fake_async` — the previous pass's stated reason was inaccurate, since `fake_async` is already in `pubspec.lock` transitively, but adding a declared dev dependency and rewriting eight rows is a project decision, and the exact-count assertions the reviewer flagged are deliberate: they turn a loaded-machine false pass into a loud failure; surfacing a post-bound rejection as its own log line (new reporting policy, and there is no caller left to tell); in-flight calls accumulating one per bound during a long hang (bounded by press rate, and the uncancellable-call residual the intent accepts); and two notes about this workflow's own bookkeeping mid-run — the ledger reading `done` while the spec read `in-review`, and the `Auto Run Result` section being absent from the working tree — both of which this pass's own finalize resolves.

### 2026-08-14 — Review pass (second follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 6: (high 0, medium 2, low 4)
- defer: 2: (high 0, medium 0, low 2)
- reject: 13: (high 0, medium 0, low 13)
- addressed_findings:
  - `[medium]` `[patch]` `_teardownStepCount()` could not see a step reached through a helper, and its own comment claimed the opposite — that matching on `_step(` rather than `await _step(` is what stops it "missing a step invoked through a helper". Scoping to `_run()`'s body puts another method's body out of reach of *any* pattern, and the count only ever comes out low, which loosens the ceiling instead of failing. Mutation-confirmed by the reviewer and re-confirmed here: extracting the three store-closing steps into a `_closeStores()` helper left the whole scoped suite green. The scoped count is now checked against the file-wide one (every `_step(` must be the declaration or a call inside `_run()`), the comment states what each half actually buys, and the same mutation now fails exactly the budget row.
  - `[medium]` `[patch]` The class doc's "what is preserved is … the mirror tells the truth about the window" is falsified by the adapter's own adjacent test row: `show()` writes the mirror before the call, so a window that answers *nothing* leaves it `true` over a toplevel that never mapped, with no event coming to reconcile it — and the abandoned-show row three tests away asserts exactly that state. Qualified to hold only from the moment the window says anything, with the dead-window floor named: an AD-18 session against a panel that never appeared, and two presses per attempt while the window manager stays wedged.
  - `[low]` `[patch]` `_apply`'s focus arm discarded `_answered`'s answer while the hide arm twenty lines above carries a comment calling that exact practice the trap — and focus is the *last* call, so it is the arm a fifth round trip would be appended after. Branched on, with the reason stated where it is now strongest.
  - `[low]` `[patch]` Mechanism four's residual named only the abandoned `show`. All three calls land the same way: an abandoned `focus` is `gtk_window_present`, so it re-maps a dismissed panel *and* takes the keyboard, and an abandoned `hide` landing after a completed `show` unmaps a panel the user just asked for, discarding the typed edit on the next re-seed. Both stated in the doc and pinned by a row each — neither path was posed before, because the existing focus and hide stall rows park their call and never release it. Both new rows fail under a `_reconcile` that stops believing window events.
  - `[low]` `[patch]` `_onBlur`'s new comment claimed "the mirror ends up honest about the window either way" — unconditional, where mechanism four forty lines above was careful to state its condition. If the racing focus-loss `hide` is itself abandoned, the late map's echo lands while that hide still has `_outstanding` up and `_reconcile` swallows it, leaving the mirror `false` over a mapped window. Qualified, with the double-abandonment precondition named.
  - `[low]` `[patch]` The harness's `/// Built lazily so a test can replace a callback before the lifecycle captures it.` was orphaned onto the new `showRequests` field, leaving `late final DaemonLifecycle lifecycle` undocumented — the field whose laziness is what makes `stepTimeout`, `loggerPort` and `showRequests` assignable at all. Moved back, and extended to name the three fields that now depend on it.

Deferred (2, both low, both appended to the ledger as new entries): (1) the `_releaseWithoutLifecycle` entry filed last pass claims the non-adoption "is now actively pinned by `composition_wiring_test.dart`'s budget row" — it is not, because that row's `hasLength(2)` matches the constructor argument names `requestTimeout:`/`stepTimeout:`, not the `.timeout(...)` a bounded loop would use; mutation-confirmed by the reviewer, who bounded the loop and left the wiring suite green. Filed as a correction rather than edited in, because this run was instructed to append new entries only. (2) The stall rows spend real time (~14 s across the two groups after this pass) in the two directories whose sibling suites the ledger already records as load-sensitive, and the spec's Verification section calls the scoped command "expected: all green" — the reviewer measured 13 failures under parallel load against a clean serial run, and this pass's own gate runs moved from the previously recorded 1/3/2 failures to 5.

Rejected (13, all low): the flat `- source_spec:` ledger form being invisible to the orchestrator's `### DW-<n>:` parser (real, but it is the format step-04 itself mandates, and the ledger header already files it as a separate known defect); late-rejection absorption being zone-conditional (the pass-2 triage already recorded the zone sensitivity, and the reviewer's escape reproduction turns on where the *harness* builds its completer); adding `'step': what` to `_step`'s timeout context (rejected in pass 1 with a stated reason, and the matrix asks only that the line name the step, which it does); logging `_raisePanel`'s shutdown drop (a new reporting policy the intent does not state, same class as two already-rejected log-policy findings); the Spec Change Log claiming no amendment while `_raisePanel`'s guard shipped (this workflow's own bookkeeping, rejected in both prior passes); the ceiling being argued against systemd's 90 s (already stated in the test comment itself and already filed in the ledger); `hasLength(2)` pinning the non-adoption of the `_releaseWithoutLifecycle` fix (**factually wrong** — disproved by the mutation behind deferral 1, and raised by two lenses independently); the frontmatter contradictions and `followup_review_recommended` being carried by nothing (this pass's own finalize resolves the first, and this run *is* the second); DW-28 reading `done` with its dispose-tail half unclosed (that entry's own `decision:` line records what was taken, and this run must not edit existing entries); the step-vs-platform-call unit mismatch and the panel spending the budget twice per press (both already documented in `main.dart` by pass 2); platform claims discharged against fakes and the synchronous-body residual (already named in `_step`'s and `shutdown()`'s docs, and already filed as the runtime-observation entry); and `_releaseWithoutLifecycle` itself (already filed last pass).

## Design Notes

Why `onTimeout` rather than catching `TimeoutException`: the callback fires only for *our* bound, so a `TimeoutException` from inside a step or a window seam is still reported as that step's failure rather than being relabelled as this policy firing.

```dart
Future<bool> _answered(String call, Future<void> Function() issue) async {
  var answered = true;
  await issue().timeout(_requestTimeout, onTimeout: () {
    answered = false;
  });
  if (!answered) {
    _log(() => _logger.error(
      'the window did not answer $call within '
      '${_requestTimeout.inMilliseconds} ms; the request was abandoned',
      context: {'call': call, 'timeout_ms': _requestTimeout.inMilliseconds},
    ));
  }
  return answered;
}
```

`_apply` then reads `if (!await _answered('show', _window.show)) return;`, leaving the existing supersession and disposal re-checks untouched between the two halves of a show.

## Verification

**Commands:**
- `dart analyze --fatal-infos` -- expected: no issues.
- `dart test --exclude-tags=live test/infrastructure/panel/ test/infrastructure/system/ test/architecture/composition_wiring_test.dart` -- expected: all green. Scoped deliberately: DW-46 records that the full suite flakes across suite boundaries, so a full-suite red is uninformative here.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- the binding-free gate CI runs (`.github/workflows/ci.yml:103`); expected: no *new* failures versus the same command on a stashed tree. DW-46's known cross-suite flake (`wayland_portal_global_hotkey_test.dart`) is the baseline, not a regression. `test/composition/` and `test/ui/` need a Flutter binding and are out of this command by design.
- Mutation checks, each applied then reverted, run against the scoped command above with the literal paths spelled out (no shell variables — an unquoted scope silently reports a fake count): delete `.timeout(...)` from `_step` -- expected: the stalled-step row hangs or fails; delete it from `_answered` -- expected: the queue-advance row fails; make `_answered` always return `true` -- expected: the stalled-show row fails on an issued `focus`; drop the `!` from `_apply`'s early return -- expected: the abandonment rows fail. A row that stays green under its mutation is vacuous and must be rewritten.



## Auto Run Result

Status: done

**Summary.** DW-20 and DW-28 remain resolved under one policy: `lib/main.dart` states `_unresponsiveCallBudget = Duration(seconds: 5)` — how long a single platform call may hold the daemon before it is abandoned — and hands it to both adapters as required parameters. `DaemonLifecycle._step` runs each teardown step under that bound, logs the step that exceeds it by name, continues the remaining steps and always reaches `exit(0)`/`exit(1)`. `WindowManagerPanelVisibility` issues every queued window call through `_answered` under the same bound, so an unanswered call is logged, the request abandoned, and the queue advances.

This third, independent pass changed no behaviour of the bound. It changed one test guard that did not guard, one code arm that violated an invariant the same method declares, and three documented claims that were false — plus two residual states the bound creates that nothing named or pinned.

**Files changed this pass.**
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` — `_apply`'s focus arm now branches on `_answered`'s answer like every other arm; mechanism four states that all three calls land late, not just `show`, and qualifies the mirror-truth guarantee with the dead-window floor; `_onBlur`'s "honest either way" gained its missing condition.
- `test/architecture/composition_wiring_test.dart` — `_teardownStepCount()` now cross-checks its `_run()`-scoped count against the file-wide one, so a step extracted into a helper fails the budget row instead of silently loosening the ceiling.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` — two rows pinning the abandoned-`focus` and abandoned-`hide` late landings.
- `test/infrastructure/system/daemon_lifecycle_test.dart` — the harness's lazy-construction contract moved back onto the field it documents.
- `_bmad-output/implementation-artifacts/deferred-work.md` — two new entries appended; no existing entry touched (10 insertions, 0 deletions).
- `lib/main.dart`, `lib/src/infrastructure/system/daemon_lifecycle.dart`, `lib/src/domain/panel/panel_visibility.dart`, `test/fakes/fake_panel_window.dart`, `test/infrastructure/panel/panel_visibility_broadcast_test.dart` — unchanged this pass.

**Review findings.** 6 patches applied (2 medium, 4 low), 2 deferred (both low, both filed in the ledger as new entries), 13 rejected (all low). No intent gaps, no spec defects, no loopbacks. Follow-up review recommended: **true** — patched severities were 0 high, 2 medium, 4 low, scoring 3×2 + 4 = 10, at or above the threshold of 5.

**Verification.**
- `dart analyze --fatal-infos` — no issues. `dart format lib test` — 0 changed after the pass's own reformat.
- `dart test --exclude-tags=live test/infrastructure/panel/ test/infrastructure/system/ test/architecture/composition_wiring_test.dart` — 155 passed, 1 skipped (153 before this pass; the two new rows).
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` (CI's binding-free gate) — run three times: 5 failures on the run whose counts were captured (874 passed, 2 skipped). **Every failure was in `wayland_portal_global_hotkey_test.dart` or `daemon_startup_test.dart`** — DW-46's and spec-dw-19's known load-sensitive families, neither in this change's diff. The count is up from the 1/3/2 the previous pass recorded, which is the substance of this pass's second deferral rather than a regression in the code under review.
- Mutation checks, each applied to the shipped tree, run, and reverted from a scratchpad backup (never `git checkout --`, which would discard the patch under review), with literal paths spelled out:
  - extract `closing the history database`, `closing the config store` and `releasing the single-instance lock` into a `_closeStores()` helper called from `_run()` — now fails **exactly** the `DW-20, DW-28: one unresponsive-call budget` row. The reviewer confirmed this same mutation left the suite green before the patch.
  - `_reconcile`'s guard weakened to `if (_outstanding >= 0) return;` — fails both new rows alongside the existing resurrection and reconciliation rows, so neither new row is vacuous.

**Residual risks.**
- An abandoned step or window call is **not** cancelled — Dart cannot stop it — so its work may still be in flight at `exit()`, and an abandoned step 2 can be torn out from under by step 9 closing the database. Both source docs say so; it is the trade the entries chose.
- A window that answers *nothing* leaves the mirror `true` over a toplevel that never mapped, with no event coming to reconcile it: an AD-18 session against a panel that never appeared, and two presses per attempt while the window manager stays wedged. Newly documented this pass; it is the floor the bound trades for.
- All three abandoned calls can land late. `show` and `focus` re-map a dismissed panel (focus also takes the keyboard); `hide` unmaps one the user just asked for, discarding the typed edit on the next re-seed. Documented and pinned this pass; no compensating call is issued, because that would be a recovery policy nobody has decided on.
- The shipped 5 s value has never been exercised against a real window manager or a real stop signal, and the 90 s ceiling it is argued against belongs to a supervisor this project does not ship. Filed in the ledger last pass.
- `main.dart`'s `_releaseWithoutLifecycle` remains unbounded. Filed last pass; this pass files a correction to that entry's overstated blocker.
- The binding-free gate has no zero-failure baseline, and this change's real-time stall rows measurably widen the window. Filed this pass.
