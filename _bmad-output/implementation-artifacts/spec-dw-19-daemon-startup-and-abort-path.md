---
title: 'Complete the composition root startup and abort paths (DW-19, DW-21, DW-22, DW-37)'
type: 'bugfix'
created: '2026-08-14'
status: 'done'
baseline_revision: '91cfedcdbe07cb098d695cced1f829e2c56e6a92'
final_revision: '74e1443'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
warnings: [multiple-goals, oversized]
---

<intent-contract>

## Intent

**Problem:** Four 2026-08-14 ledger decisions each name a fix to the daemon's startup and abort paths that has not been made. A show request landing anywhere between `acquire()` and `lifecycle.start()` is dropped, so a launcher double-click raises nothing (DW-19: `single_instance_lock.dart:79-80` is a broadcast controller with no buffer and `:105` serves the moment the address is bound, while `main.dart:188` reaches `lifecycle.start()` only after `_createHiddenWindow()` and `runApp`). `FlutterError.onError` and `PlatformDispatcher.instance.onError` are installed nowhere, so the widget-tree half of `_abort`'s documented promise is unwired (DW-21). Nothing observes that the engine produced a frame, so CAP-1's "the window is warm before the first toggle" rests on `gtk_widget_realize` alone (DW-22). And `_releaseWithoutLifecycle` closes `PanelVisibility.changes` under a live `CorrectionController` and never disposes the controllers or the container, which is the inverse of the order `DaemonLifecycle.shutdown()` exists to guarantee (DW-37).

**Approach:** Take each decision's own named fix, in the file that decision names. `SingleInstanceLock` gains a pending-show flag the first subscriber to `showRequests` drains. `main.dart` installs both framework error handlers, routing to the Logger port by error type and never exiting; awaits the first frame between `runApp` and `lifecycle.start()`; and passes the nullable `DaemonGraph` into `_releaseWithoutLifecycle` so controllers and container come down first. Every claim that lives in `main.dart` — the one file no test can execute — is pinned by a source scan in `test/architecture/composition_wiring_test.dart`, the idiom that file already uses; the lock's fix is pinned behaviourally over real sockets.

## Boundaries & Constraints

**Always:**
- Each fix lands in the file its entry names: DW-19 in `single_instance_lock.dart`, DW-21/22/37 in `main.dart`. Nothing else under `lib/` changes.
- The buffer is a **flag, not a queue**: any number of launches arriving before the first subscriber raise the panel exactly once, and a request arriving while a subscriber is live is delivered and *not* also buffered.
- Both error handlers log `error.runtimeType` (plus `FlutterErrorDetails.library`, which is framework-authored) and nothing else — the Logger port forbids an exception's `toString()` — go through `main.dart`'s existing `_log` swallow, and never end the process.
- The first-frame await is bounded and log-and-continue: the spine's operational envelope says a missing dependency degrades one capability and never blocks startup, and this await sits ahead of `lifecycle.start()`, `tray.install()` and `bindHotkey`.
- `_releaseWithoutLifecycle`'s step list stays in `DaemonLifecycle.shutdown()`'s order: controllers, graph, panel adapter, tray, hotkey adapter, hotkey seam, database, config store, lock last. Each step stays independently guarded.
- Comments stating the superseded behaviour are corrected in the same edit: `main.dart`'s dropped-request trade paragraph above `lifecycle.start()`, and `_abort`'s closing "one caveat that branch does not cover" paragraph.
- Every new pin row is mutation-verified — reverting the edit it guards fails that row, and the pre-mutation baseline is 0 failures.

**Block If:**
- Any fix turns out to require editing `daemon_lifecycle.dart`'s step order. That order is the contract three other entries rest on and is not this bundle's to renegotiate.
- Evidence emerges that a session which produces no frame must be treated as a failed startup. That contradicts the operational envelope and is a decision the ledger does not carry.

**Never:**
- Restore a first-frame handler in `linux/runner/my_application.cc`, or edit anything under `linux/`. AD-8 exists to have that handler deleted, and a version that records readiness is one line from a version that shows the toplevel.
- Reopen story 5's decision to move `lifecycle.start()` after `runApp`; the widened window is the right trade and DW-19's buffer is what closes its cost.
- Let either error handler call `exit`, rethrow, present the error (`FlutterError.presentError`), or log a message body or stack trace.
- Refactor `_releaseWithoutLifecycle` and `DaemonLifecycle.shutdown()` into one shared teardown. The entry names a parameter, not a restructure.
- Edit `{implementation_artifacts}/deferred-work.md` — the orchestrator records resolution.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Launch during startup | Holder acquired, `showRequests` has no listener; a second launch sends `show-panel` | Second launch still resolves `alreadyRunning`; the first subscriber then receives exactly one event | No error expected |
| Several launches during startup | Three connections each send `show-panel`, no listener | The first subscriber receives exactly one event | No error expected |
| Launch while a subscriber is live | Listener attached, one `show-panel` | Delivered once; nothing is buffered, so a later second subscriber receives nothing | No error expected |
| Line lands after `dispose()` | Controller closed, flag may be set | Dropped; no add-after-close and no drain | Existing swallow preserved |
| Widget build throws | `FlutterError.onError` fires | One `logger.error` carrying `error_type` and `library`; the daemon stays up | Logger failure swallowed by `_log` |
| Uncaught async error | `PlatformDispatcher.instance.onError` fires | One `logger.error` carrying `error_type`; returns true, so the process continues | As above |
| Engine renders a frame | After `runApp` | `endOfFrame` completes and `lifecycle.start()` runs next | No error expected |
| No frame within the budget | Timer expires first | One `logger.warning` naming the budget; startup continues to `lifecycle.start()` | `TimeoutException` caught; never reaches `main`'s catch |
| `build()` throws mid-sequence | `lifecycle` null, graph non-null | Controllers then container are disposed first, then panel adapter, tray, hotkey pair, database, config store, lock; then `exit(1)` | Every step guarded and logged individually |
| Failure before the graph exists | Graph null | The two graph steps are absent; the remaining list is unchanged | As above |

</intent-contract>

## Code Map

- `lib/src/infrastructure/system/single_instance_lock.dart` -- DW-19. `_showRequests` (`:79-80`) is the bufferless broadcast controller; `_onConnection` (`:203-205`) is the one `add` site; `dispose()` (`:130`) closes it; `SingleInstanceStatus.acquired`'s doc (`:9-11`) and the `showRequests` getter doc (`:84-86`) both describe the stream and must stay true.
- `lib/main.dart` -- DW-21, DW-22, DW-37. `main` (`:39-153`) holds the abort-visible locals and the `try`; `_finishStartup` (`:157-241`) holds `runApp`, the stale trade paragraph and `lifecycle.start()`; `_abort` (`:289-317`) holds the doc and the null-lifecycle branch; `_releaseWithoutLifecycle` (`:323-374`) holds the step list; `_log` (`:471`) is the swallow both new handlers use.
- `lib/src/application/composition/daemon_graph.dart` -- unchanged. `disposeControllers()` and `dispose()` are the two callbacks the abort path gains; `build()` reads three providers in sequence, which is why a partial build leaves controllers behind.
- `lib/src/infrastructure/system/daemon_lifecycle.dart` -- unchanged. `_run()` (`:208-227`) is the canonical step order the abort path must mirror.
- `lib/src/domain/logger.dart` -- the contract that forbids logging an exception's `toString()`; both new handlers obey it.
- `test/infrastructure/system/single_instance_lock_test.dart` -- real-socket behaviour suite; `pathsFor`/`lockOn` are the helpers new rows reuse.
- `test/architecture/composition_wiring_test.dart` -- the source-scan pin suite for `main.dart`. `_mainSource()` strips comments, so no row may assert on doc text. Its `AD-18: main.dart builds the graph eagerly` row asserts `contains('..build()')` and **must be updated**: DW-37 splits that cascade.
- `test/infrastructure/system/daemon_startup_test.dart:308` -- subscribes to `lock.showRequests` after acquiring; must stay green.
- `linux/runner/my_application.cc:71` -- `gtk_widget_realize` with no `gtk_widget_show`: the reason the toplevel is never mapped, and the reason the frame await needs a bound.

## Tasks & Acceptance

**Execution:**
- `lib/src/infrastructure/system/single_instance_lock.dart` -- add a `bool _pendingShowRequest`; make `_showRequests` a `late final` broadcast controller whose `onListen` schedules a drain (justify the `late` in a comment: the initializer names an instance method); in `_onConnection`, add when `_showRequests.hasListener` and set the flag otherwise; drain in a microtask that re-checks `_pendingShowRequest`, `isClosed` and `hasListener` before emitting, so a subscriber's own `listen()` is not re-entered synchronously -- this is the whole of DW-19's fix, in the file the entry names.
- `lib/main.dart` (DW-21) -- add `_installErrorHandlers(Logger)` setting `FlutterError.onError` and `PlatformDispatcher.instance.onError` (returning `true`), each emitting one `logger.error` through `_log` with `error_type` (and `library` for the framework side); call it immediately after the logger is constructed; narrow `_abort`'s doc to what it actually guards now that the widget-tree half is wired -- a single failing build must not kill an all-day resident daemon.
- `lib/main.dart` (DW-22) -- add a bounded `await` on `WidgetsBinding.instance.endOfFrame` between `runApp` and `lifecycle.start()` in `_finishStartup`, with a named top-level budget constant of `Duration(seconds: 5)` and a `logger.warning` on expiry; rewrite the trade paragraph above `lifecycle.start()`, which currently states the dropped request as accepted and points at DW-19 -- CAP-1's warmth now rests on a rendered frame, and the extra frame's delay is safe only because DW-19's buffer lands in the same change.
- `lib/main.dart` (DW-37) -- hold `DaemonGraph? openedGraph` beside the other abort-visible locals, split the `DaemonGraph(...)..build()` cascade so the graph is captured *before* `build()` runs, pass it to `_releaseWithoutLifecycle`, and put `disposeControllers` and the container dispose at the head of that step list; replace `_abort`'s closing caveat paragraph, which says the container and controllers do not come back -- a cascade yields nothing to capture when `build()` throws, which is the exact path this entry is about.
- `test/infrastructure/system/single_instance_lock_test.dart` -- add the four DW-19 rows from the I/O matrix (buffered single request, several collapsing to one, a live subscriber not also buffering, a line after `dispose()` staying inert), each over real sockets like the existing rows -- the lock is the one half of this bundle a test can execute.
- `test/architecture/composition_wiring_test.dart` -- update the `..build()` row to pin the split (`openedGraph = graph;` before `graph.build();`, both present), and add rows for: both error handlers installed before `runApp`; the frame await between `runApp` and `lifecycle.start()` and inside a guard; `graph: openedGraph` reaching `_releaseWithoutLifecycle`; and the controller and container steps preceding the panel-adapter step -- source scanning is the only gate `main.dart` has.

**Acceptance Criteria:**
- Given a second launch whose `show-panel` line lands while nothing is subscribed, when a subscriber attaches afterwards, then it receives exactly one show request — the event `main.dart`'s already-pinned `onShowRequest: graph.showPanel` wiring turns into a raised panel. The panel itself is not reachable from a test in this container; the manual check below is what observes it.
- Given the shipped `main.dart`, when `dart test test/architecture/composition_wiring_test.dart` runs, then it passes and rows exist pinning each of the four edits named above.
- Given any one of those edits is reverted by hand, when that suite runs, then the rows that fail are exactly the rows naming the reverted edit, and no others — verified against a 0-failure baseline before each mutation.
- Given the CI gate command, when it runs after the change, then it is green and the pass/skip tally equals the pre-change baseline plus the rows added here.
- Given `dart analyze --fatal-infos`, when it runs, then it reports no issues.
- Given the daemon is launched against a display, when startup completes, then the log carries no first-frame warning and a second launch raises the panel; if the observation cannot be made here, it is recorded as unobserved with the reason rather than reported as met.

## Spec Change Log

No bad_spec loopback occurred. One correction was made to `## Tasks & Acceptance` during the review pass: acceptance criterion 3 required that a reverted edit fail "exactly one row", which is false by construction for the lock edit — four behavioural rows guard it. Reworded to "the rows that fail are exactly the rows naming the reverted edit, and no others". No code was re-derived; `<intent-contract>` was not touched.

## Review Triage Log

### 2026-08-14 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 0, medium 2, low 6)
- defer: 4
- reject: 6
- addressed_findings:
  - `[medium]` `[patch]` The first-frame await caught only `TimeoutException`, so any other error completing `endOfFrame` escaped into `main`'s `on Object catch`, ran `_abort` and exited 1 — the exact inverse of the contract the comment above it states, and unlike the tray guard forty lines below. A second `on Object catch (error)` clause now logs `error_type` through `_log` and continues; the DW-22 pin row asserts the fallback follows the timeout clause.
  - `[medium]` `[patch]` The DW-21 pin row did not pin the payload. Mutation-verified by a reviewer: swapping `details.exception.runtimeType.toString()` for `details.exception.toString()` and adding `'stack': stack.toString()` kept `dart analyze --fatal-infos` clean and all 220 architecture rows green — leaving `logger.dart`'s "never log an error's `toString()`" rule unguarded on the process's new catch-all channel, on a daemon that reads the clipboard. The row now pins `runtimeType.toString()` twice and bans `details.exception.toString()`, `details.toString()`, `details.stack`, `stack.toString()` and `exceptionAsString`; re-running the reviewer's exact leak now fails that row and only it.
  - `[low]` `[patch]` `FlutterError.onError` reported details the framework marks `silent`, which `dumpErrorToConsole` — the default it replaces — suppresses outside asserts. Early return added and pinned.
  - `[low]` `[patch]` `showRequests`' new doc claimed flatly that requests landing before anything listens "are not lost". False during teardown: `shutdown()` cancels the subscription at step 1 and disposes the lock ten steps later, so a line in that window sets a flag nothing drains. Scoped to the startup window, with the teardown case stated.
  - `[low]` `[patch]` `release()` left `_pendingShowRequest` set, so a request buffered in one holding period would replay to the first subscriber of the next — `acquire()` after `release()` is a shipped, tested path. Cleared in `release()`; a throwaway probe confirmed 0 replayed events where the unpatched form replayed 1.
  - `[low]` `[patch]` `_abort`'s new `[graph]` paragraph read as covering the whole partial build. It does not cover the controller whose own constructor throws: `ref.onDispose` registers only after the constructor returns and the graph's field is assigned only after `container.read` returns, so that controller's subscription is reachable by neither step. The residual and the `exit(1)` bounding it are now named.
  - `[low]` `[patch]` The after-dispose lock row was titled "neither delivered nor buffered for anyone", but a closed controller can never drain, so a flag-then-check implementation passed it identically. Renamed to what it pins, with the unpinned half stated outright.
  - `[low]` `[patch]` The DW-37 guard assertion used `endsWith('if (graph != null) ')`, asserting on exact emitted whitespace on a row whose claim is teardown order. Now a whitespace-tolerant regex; a control mutation rewrapping the guard onto two lines keeps it green. The neighbouring pre-existing `endsWith` row was left alone.

### 2026-08-14 — Review pass (follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 9: (high 1, medium 3, low 5)
- defer: 1
- reject: 11
- addressed_findings:
  - `[high]` `[patch]` `_abort`'s opening `logger.error` and `_releaseWithoutLifecycle`'s per-step `logger.error` were the only two logs in `main.dart` not routed through `_log` — and this bundle's own `PlatformDispatcher.onError` turned that from loud into silent: a throw from a broken stderr is now caught, logged and answered `true`, so `exit(1)` never runs and the process stays resident holding the AD-14 address with nothing behind it. Inside the step loop it is worse still: the throw escapes the `for`, skipping every later step including the one that hands the address back. Both wrapped in `_log`, and a new row pins that no bare `logger.` call survives anywhere between `_abort` and the container builder. Filed as a parked entry before this pass; taken here because this change is what made it silent.
  - `[medium]` `[patch]` The DW-22 row computed its `expiry` slice from `on TimeoutException` all the way to `lifecycle.start()`, spanning *both* catch clauses — so `contains('logger.warning(')` and `contains("'error_type'")` were each satisfied by a different clause and neither assertion could say which. The clauses are now sliced separately: the expiry pinned to `logger.warning` and `budget_ms`, the fallback to `logger.error` and `error.runtimeType.toString()` with the same forbidden-spelling loop `_installErrorHandlers` already carries. Mutation-verified: the reviewer's `error.toString()` leak now fails that row and only it.
  - `[medium]` `[patch]` The DW-37 row located its two teardown steps by label alone, so swapping the callables between the tuples — leaving both strings exactly in place — restored the very inversion DW-37 was filed to fix while the row stayed green. Demonstrated by a reviewer against the shipped tree. Both steps are now matched with their callables; that mutation fails the row and only it.
  - `[medium]` `[patch]` Nothing executed the premise of the new teardown steps: every teardown row in `daemon_graph_test.dart` ran against a fully built graph, so `disposeControllers()`/`dispose()` on a partially built one — the only state the abort path exists for — was asserted by source text alone. Two executed rows added, one breaking `build()` at its second read and one on a graph never built. The first observes *between* the two steps deliberately, because the container-dispose backstop behind them masks the claim: an earlier draft of this row survived the regression mutation and was rewritten until it did not.
  - `[low]` `[patch]` The `details.silent` early return was pinned by `contains('details.silent')`, which cannot tell the guard from its inverse; inverted, the handler drops every error the framework wants reported and logs only what it has already handled. Now pinned by its sense.
  - `[low]` `[patch]` `_firstFrameBudget` was pinned as a named constant but not as a number, so shrinking it to a millisecond left the await expiring on every launch with the suite green. Pinned as a range, so re-arguing the number stays allowed and voiding it does not.
  - `[low]` `[patch]` `_scheduleDrain`'s doc justified the microtask by a synchronous re-entry into `DaemonLifecycle.start()` that this controller cannot produce — `_showRequests` is a default `sync: false` broadcast controller, which never delivers from inside `add`. Corrected to the reason that holds (somewhere to put the cancel/dispose re-check), with the false hazard named as false so the next reader does not delete the re-check with it.
  - `[low]` `[patch]` `release()` clearing `_pendingShowRequest` — itself a patch from the previous pass, verified then by a throwaway probe — was asserted by nothing committed; deleting the line left the suite green. A row now buffers a request, releases, re-acquires and expects no replay.
  - `[low]` `[patch]` That clear was also not a barrier: `ServerSocket.close()` leaves already-accepted sockets live, so a peer still inside its handshake deadline could deliver after the clear and re-arm the flag for a holding period that had not begun — the exact replay the added comment claimed to prevent. `_recordShowRequest` now returns early when the address is not held. Confirmed real by mutation: dropping the guard fails the new row.
- Rejections of note: richer `FlutterErrorDetails` diagnostics and a stack trace (the intent fixes the payload at the type, which is the Logger port's own rule); a 5-second budget that expires on every launch (refuted by live measurement in the previous pass and by this pass's green frame await); `endOfFrame` not proving rasterization (the comment claims "built but never laid out or painted", which is what it does establish); the container constructed as an argument to `DaemonGraph` being unreachable on abort (a window of one non-throwing constructor, bounded by `exit(1)`, with nothing to release); `details.library` provenance and the "whole process" coverage claim (comment precision, no consequence); an age bound on the buffered request (the window is startup, measured at ~1.3 s); the drained panel racing the AD-11 portal dialog (both surfaces are wanted); an unbounded `peer.drain()` in the test helper (the runner's per-test timeout already names the row); and making the three-launch row concurrent (socket handlers run sequentially on the event loop either way, so the flag has no concurrency-sensitive state).

### 2026-08-14 — Review pass (second follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 6: (high 0, medium 0, low 6)
- defer: 2
- reject: 19
- addressed_findings:
  - `[low]` `[patch]` The I/O matrix requires the `FlutterError` handler to log `library` beside `error_type`, and nothing pinned it: `grep -rn "'library'" test/` returned no hits, so deleting the entry from `main.dart` left `dart analyze --fatal-infos` clean and all 44 rows green. Pinned in the DW-21 row; mutation-verified from a 0-failure baseline — dropping the entry now fails that row and only it.
  - `[low]` `[patch]` The `on Object` fallback on the frame await — itself a patch from the first pass — was justified by a mechanism the SDK does not have. `SchedulerBinding.endOfFrame` (`binding.dart:847-858`) only ever `complete()`s its completer; there is no `completeError` path, so a binding that cannot schedule a frame *hangs* and the timeout is what covers it. The clause is still right, for the synchronous half: reading the getter runs `scheduleFrame()`, which can throw before there is a future to await. Corrected in `main.dart` and in the two test comments that repeated the false version.
  - `[low]` `[patch]` The `details.silent` early return claimed to be "matching the default this replaces". It is not: `assertions.dart:1019` computes `reportError = isInDebugMode || !details.silent`, so the default honours the flag only in release and deliberately ignores it in debug. The divergence is now stated as a trade taken rather than glossed as parity, in `main.dart` and in the test row's comment.
  - `[low]` `[patch]` The `showRequests` doc excused the uncovered teardown window with "the launch that sent it will find the address free and become the daemon itself". It will not — the address stays bound until `shutdown()`'s step 11, so that launch was already told `alreadyRunning` and has exited 0. Rewritten to what the user sees (the click raises nothing and starts nothing; the *next* launch becomes the daemon) and to name the reordering that would close it as out of this class's reach. Raised independently by the adversarial and verification-gap lenses.
  - `[low]` `[patch]` `main.dart`'s replacement trade paragraph asserted flatly "Nothing arriving before this line is lost", while the lock's own doc names a teardown window where a line sets a flag nothing drains and `DaemonLifecycle.start()` after a shutdown is a no-op. Scoped to startup, with both loss windows named — the paragraph it replaced was scrupulous about stating its cost and the replacement had stopped being.
  - `[low]` `[patch]` `_abort`'s new swallow rationale said a throw there "no longer ends the isolate", implying it once did. It never did: an error escaping `main` does not end a Flutter process whose GTK loop is already running, so `exit(1)` was skipped before this bundle too — which is what the ledger entry on the same hole says. Corrected to the distinction that holds: the handler changed the reporting, not the residency.
- Rejections of note: the two framework handlers losing `dumpErrorToConsole`'s repeat suppression (the ErrorWidget a failed build installs does not rebuild per frame, so the flood premise does not hold); `PlatformDispatcher.onError` stopping SIGTERM from exiting (`DaemonLifecycle._step` swallows every step, so `shutdown()` cannot throw into that callback); the abort loop hanging on `disposeControllers`' unbounded `Future.wait(_pendingSaves)` (empty on a startup abort, and the step order is the one the intent requires mirrored); the frame await gating `tray.install()` and `bindHotkey` (the intent places it ahead of all three by name); banning stack traces and `presentError` too broadly and adding a `kDebugMode` passthrough (all three forbidden by the intent's Never list); the forbidden-token loops scanning comment prose and an unanchored `indexOf` producing a `RangeError` (both rest on comments being present — `_mainSource()` is `_stripComments(...)`); `late final _showRequests` risking a `LateInitializationError` (a `late final` *with* an initializer cannot throw one, and the stated reason — a field initializer cannot see `this` — is true); the stream having silently become first-listener-wins (its doc says so in the sentence above); and `endOfFrame` not proving rasterization (adjudicated in the first pass). Four further real findings were left unfiled because prior passes already filed them verbatim: DW-21's handlers executed by no test, the DW-19/DW-22 runtime claims in no committed procedure, the gate's missing 0-failure baseline, and `DaemonStartup.begin` sitting outside `main`'s guard.

## Design Notes

**Why the frame await is bounded.** `my_application.cc:71` realizes the view and never shows the toplevel (AD-8), and a live run in this container confirms the window stays `IsUnMapped`. An unbounded `await WidgetsBinding.instance.endOfFrame` on a session that never produces a begin-frame for an unmapped toplevel would leave the process holding the AD-14 address with no subscription, no tray and no hotkey — the exact state `_abort` exists to prevent, reached without a throw, so `_abort` never runs. The bound makes the two cases identical on every session that renders and merely honest on one that does not. **Stated assumption (AGENTS.md §9):** the ledger decision names the await but not a budget, so the budget is chosen here — 5 seconds, generous enough that no rendering session reaches it, short enough that a wedged one still gets a daemon — and it is a named constant so the number is argued with in one place.

**Why the drain is a microtask.** A broadcast controller registers the new subscription *before* it calls `onListen`, so adding inline would run the subscriber's handler synchronously inside `listen()` — re-entering `DaemonLifecycle.start()` before it has stored the subscription it is in the middle of creating. Microtasks drain before the event loop returns to socket I/O, so the buffered request still arrives ahead of any later one.

**Why the graph capture is split from the build.**

```dart
final graph = DaemonGraph(container: _container(...), logger: logger);
openedGraph = graph;   // before build(), because a cascade yields no value when it throws
graph.build();
```

`DaemonGraph(...)..build()` evaluates to the graph only if `build()` returns, so the partial-build failure DW-37 is about is precisely the case where the old shape captures nothing.

## Verification

**Commands:**
- `dart analyze --fatal-infos` -- expected: `No issues found!`
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` -- expected: green, tally equal to the baseline captured before the change plus the new rows.
- `dart test test/infrastructure/system/single_instance_lock_test.dart` -- expected: green, including the four new DW-19 rows.
- Mutation checks, one at a time, reverting by hand and restoring from a scratchpad copy rather than `git checkout --` (an uncommitted patch is what is under test): expected: each reverted edit fails exactly one row, from a 0-failure baseline. Quote every path passed to the runner — an unquoted shell variable is not word-split under `zsh`, which makes a scoped run silently run something else.

**Manual checks (if no CLI):**
- `flutter build linux --debug`, then launch the bundle under `Xvfb :99` with `XDG_RUNTIME_DIR` pointed at a scratch directory, and read stderr: expected: no first-frame warning line, and a second launch of the same bundle raises the panel (`xwininfo -name 'Hotkey Grammar Corrector'` reports the map state change). If the run cannot be completed here, record what blocked it and report the first-frame claim as unobserved.



## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A second follow-up review over the committed bundle (`dba41a2`), which the previous pass recommended. The four decisions stood again: no intent gap, no spec repair, no code re-derivation, and no finding that changed a control path. This pass converged on the one class the previous two kept finding — prose and pins that name a mechanism the mechanism does not have. Four comments were corrected against the SDK and the codebase rather than reworded (`endOfFrame` has no `completeError` path; `dumpErrorToConsole` honours `details.silent` only in release; a launch told `alreadyRunning` has already exited and does not come back for the address; an error escaping `main` never ended this process), one unqualified guarantee was scoped to the window it actually holds, and the one payload the I/O matrix requires but nothing pinned — `library` — is now pinned and mutation-verified. Six patches, all low, none behavioural.

The pass also spent two rounds distinguishing a gate failure from a regression. A row in the lock suite failed once under the full gate, sitting directly beside the `_recordShowRequest` rewrite; it is a pre-existing load-sensitive `pumpEventQueue` row, measured failing 5/10 under concurrent load in a detached worktree at the baseline revision with none of this bundle's code present. Deferred, not patched.

**Files changed**

- `lib/main.dart` — four comment corrections: the frame-await fallback's mechanism, the `details.silent` parity claim, the startup-only scope of the no-lost-request guarantee, and `_abort`'s residency-versus-reporting distinction.
- `lib/src/infrastructure/system/single_instance_lock.dart` — the `showRequests` teardown paragraph rewritten to what actually happens to the launch whose request is dropped.
- `test/architecture/composition_wiring_test.dart` — a new assertion pinning `'library': details.library` in the DW-21 row, and the two comments plus one reason string that repeated the false `endOfFrame` and `details.silent` claims.
- `_bmad-output/implementation-artifacts/deferred-work.md` — two new entries appended. No existing entry was edited, re-opened, reordered, or read for resolution.

**Review findings.** 6 patches applied (high 0, medium 0, low 6); 2 deferred; 19 rejected. Rejections are itemised in the triage-log entry with the evidence that killed each. Four real findings were left unfiled because prior passes had already filed them verbatim: DW-21's handlers executed by no test, the DW-19/DW-22 runtime claims registered in no committed procedure, the gate's missing 0-failure baseline, and `DaemonStartup.begin` outside `main`'s guard. One note for the orchestrator, unchanged from the previous pass and not acted on here: the parked entry describing the bare `logger.error` on the abort path is what the previous pass's high-severity patch resolved; its status is the orchestrator's to set.

**Follow-up review recommended: true.** Patched severities: high 0, medium 0, low 6. Score = 3 x 0 + 1 x 6 = 6, which is 5 or more. Worth reading against the trend: three passes have now returned 8, 9 and 6 findings, and severity has fallen from one high plus three mediums to none above low. Nothing in this pass touched a control path.

**Verification performed**

- `dart analyze --fatal-infos` — `No issues found!`
- `dart test "test/architecture/composition_wiring_test.dart" "test/infrastructure/system/single_instance_lock_test.dart"` — 44 pass / 1 skip, unchanged from the previous pass: the new `library` assertion is inside an existing row, so no row count moved.
- `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` — 856 pass / 2 skip / 1 fail. The failure is the deferred pre-existing flake below, not a regression; an earlier run of the same command in this pass gave 854 / 2 / 3 with different rows, which is the moving number the already-open gate-baseline entry describes.
- Mutation check from a 0-failure baseline, restoring `lib/main.dart` from a scratchpad copy rather than `git checkout --`, every path quoted: deleting `'library': details.library` fails the DW-21 row and only it (1 failure, named in the output).
- Flake attribution, measured on both trees: the failing row (`AD-14: release frees the address for the very lock that held it`) is 8/8 clean unloaded at HEAD and 8/8 clean unloaded in a detached worktree at baseline `91cfedc`; under ten concurrent runs it fails 7/10 at HEAD and 5/10 at the baseline, where none of this bundle's code exists. The worktree was removed and pruned afterwards.

**Residual risks**

- Unchanged from the previous passes: the 5-second budget is this bundle's number; both error handlers are still executed by no test; the gate still has no 0-failure baseline; the DW-19 and DW-22 live observations live in this document rather than in a re-runnable procedure; `DaemonStartup.begin` still sits outside `main`'s guard; and a controller whose own constructor throws after subscribing is reachable by neither teardown step, bounded by the `exit(1)` that follows.
- New, and deferred rather than taken: the two executed DW-37 rows added by the previous pass sit in `test/composition/`, which the CI gate excludes by design, so the strongest evidence the DW-37 fix has never runs on a merge check.
- The `details.silent` divergence from the framework default is now documented rather than closed: a debug session sees fewer framework-reported errors than `dumpErrorToConsole` would show it. Closing it needs a `kDebugMode` branch, which this bundle's intent does not carry.
- No live run was made in this pass. Nothing changed here touches a code path; five of the six patches are comments and the sixth is a test assertion.
