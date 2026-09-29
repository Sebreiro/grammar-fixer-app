---
title: 'DW-36: an onDone backstop on the panel window event subscription'
type: 'bugfix'
created: '2026-08-14'
status: 'done'
baseline_revision: '55ce2ec'
final_revision: 'ef59f30'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: [oversized]
---

<intent-contract>

## Intent

**Problem:** `WindowManagerPanelVisibility`'s subscription to `PanelWindow.events` carries an `onError` backstop with an explicit rationale — "every later reconciliation depends on it" — and no `onDone`. If the stream *completes* while the adapter is live, reconciliation stops permanently and nothing is logged: the adapter goes on looking healthy while CAP-14's focus-loss hide, the external-hide correction and the `minimize` arm all quietly stop working.

**Approach:** Add the missing `onDone` arm in the same shape as the `onError` arm beside it — one log line through `_log`, stating the consequence rather than just the event. Pin it with a test row alongside the existing `AD-15: an event stream that errors` row, plus a row proving the ordinary teardown stays silent.

## Boundaries & Constraints

**Always:**
- Route the log through `_log(...)` so a broken logger cannot escape, exactly as every other emit in this file does.
- Keep the new arm structurally symmetric with `onError`: a backstop that logs and nothing more.
- Keep `test/infrastructure/panel/` binding-free — pure `dart test`, no Flutter binding (AGENTS.md §7).
- Keep `dart analyze` clean; no new `ignore` directives.

**Block If:**
- The fix appears to require changing the `PanelWindow` seam's contract or `dispose()`'s ordering.
- Adding the arm turns an existing test row red for any reason other than a newly expected log line.

**Never:**
- Do not add recovery, resubscription, retry, or a "stream is dead" flag — the decision is a log-only backstop.
- Do not change `_reconcile`, `_onBlur`, `_apply`, `_enqueue`, the mirror, or the queue.
- Do not change `onError`'s message, context, or behaviour, nor `dispose()`'s cancel-before-dispose ordering.
- Do not touch `lib/src/application/**` or any other adapter.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Stream closes under a live adapter | adapter constructed, not disposed; `events` completes | exactly one `error`-level log line naming the closed stream and the lost reconciliation | No error expected |
| Ordinary teardown | `dispose()` cancels the subscription, then disposes the window (which closes `events`) | nothing logged — a cancelled subscription receives no done event | No error expected |
| Stream errors (unchanged) | `events` emits an error | one `error` line with `{'error_type': ...}`; subscription survives and a following `show` still reconciles | No error expected |
| Logger throws while reporting the close | `events` completes; `Logger.error` throws | the throw is swallowed by `_log`; no async error escapes | Swallowed — the reporting channel is what broke |

</intent-contract>

## Code Map

- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- the only production edit: the constructor's `_window.events.listen(...)` at :47-58 has `onError` and no `onDone`.
- `lib/src/infrastructure/panel/panel_window.dart` -- the seam; its `dispose()` doc advertises "closes `events`", which is what makes this shape reachable by design rather than by accident.
- `test/fakes/fake_panel_window.dart` -- closes `_events` only inside `dispose()`; needs an affordance to close the stream while the adapter is still live.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- binding-free suite; holds the sibling `AD-15: an event stream that errors ...` row at :460 to mirror.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- DW-36 at :636-643; `status: open` with the 2026-08-14 decision this spec implements.

## Tasks & Acceptance

**Execution:**
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` -- add an `onDone` arm to the `_window.events.listen(...)` call, logging one `error` line through `_log`, and extend the adjoining AD-15 comment to cover completion as well as error -- the missing half of the backstop the comment's rationale already justifies.
- `test/fakes/fake_panel_window.dart` -- add a `closeEvents()` affordance that closes the events controller without disposing the window -- the adapter cancels before `dispose()` closes the stream, so a live-adapter close is otherwise unreachable from a test.
- `test/infrastructure/panel/window_manager_panel_visibility_test.dart` -- add the matrix's first two rows (stream closes under a live adapter; ordinary teardown logs nothing) next to the existing error row -- pins both the new line and the absence of a spurious one on shutdown. Matrix row 3 is the existing error row and stays as it is. Also add a row for matrix row 4: a logger whose `error` throws, asserting the stream close does not escape as an async error — use a local throwing `Logger` in this file rather than changing the shared `FakeLogger`.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- flip DW-36's `status: open` to resolved, citing the file, the arm added and the two test rows -- the ledger is the record of what is still owed.

**Acceptance Criteria:**
- Given a live `WindowManagerPanelVisibility` that has not been disposed, when the underlying `PanelWindow.events` stream completes, then exactly one `error`-level line is emitted naming the closed stream and the lost reconciliation.
- Given an adapter torn down the ordinary way, when `dispose()` runs to completion, then no stream-closed line is emitted, because the subscription is cancelled before the window closes `events`.
- Given the existing error and reconciliation rows, when the binding-free suite runs, then every one still passes unchanged.

## Spec Change Log

## Review Triage Log

### 2026-08-14 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 3: (high 0, medium 1, low 2)
- defer: 1: (high 0, medium 1, low 0)
- reject: 10: (high 0, medium 0, low 10)
- addressed_findings:
  - `[medium]` `[patch]` The throwing-logger row duplicated `test/fakes/throwing_logger.dart` as a file-local `_ThrowingLogger`, and asserted only that nothing escaped — so it stayed green when the `onDone` arm was deleted outright, pinning the `_log` guard but not the arm's existence. Switched to the shared `ThrowingLogger` and added an `attempts` assertion; deleting the arm now fails 2 rows instead of 1.
  - `[low]` `[patch]` The amended AD-15 comment stated the failure as live when the shipped seam cannot produce it, and did not record that the response is deliberately log-only. Qualified it in the house style already used at `x11_global_hotkey.dart:37-41` ("explicitly defensive"), naming why it is kept and that there is no resubscription, retry or dead-stream flag.
  - `[low]` `[patch]` `FakePanelWindow.closeEvents()` leaves the fake parking and releasing calls while `emitEvent` silently no-ops, so a future test driving a request past it would read a mute fake as an adapter defect. Documented the consequence on the method.

Deferred: the seven sibling AD-15 subscriptions that still guard `onError` only. Rejected (10): the `_disposed` guard on `onDone` and the "no degraded state after done" pair, both foreclosed by the intent's "one line, the same shape as the arm beside it"; the undocumented `dispose()` ordering coupling, now covered by the patched comment; and seven test-style points (asserting the adapter still answers presses after the close, filtering `logger.lines` by level, `context: isNull` freezing an absence, making `closeEvents` sync, the fake's doc naming adapter internals, and two review-process observations).

## Design Notes

The arm is deliberately unguarded by `_disposed`, matching `onError` beside it. On the ordinary path such a guard would be dead code — `dispose()` cancels the subscription before `_window.dispose()` closes the stream, and a cancelled subscription never receives done. The only way the line can appear during shutdown is if the cancel itself threw, which already logged its own failure; a second line there is honest, not noise.

The message states the consequence, not the bare event, because that is the whole difference from `onError`: an errored stream leaves a line and a live subscription, a completed one leaves a permanently dead adapter that still reports healthy. House style already writes consequences into log lines (`'global hotkeys are unavailable; the tray menu is the way in'`).

Shape, for reference — no context map, since there is no error to describe:

```dart
onDone: () => _log(
  () => _logger.error(
    'the panel window event stream closed; window events can no longer '
    'reconcile the panel visibility mirror',
  ),
),
```

## Verification

**Commands:**
- `/home/vscode/flutter/bin/dart analyze` -- expected: no issues found (`dart` is not on PATH in this container)
- `/home/vscode/flutter/bin/dart test test/infrastructure/panel/` -- expected: all rows pass, including the two new ones
- `/home/vscode/flutter/bin/dart test test/infrastructure/ test/application/ test/domain/` -- expected: the binding-free set stays green, confirming no fake change broke another suite

## Auto Run Result

Status: done

**Implemented change.** `WindowManagerPanelVisibility`'s subscription to `PanelWindow.events` now carries an `onDone` backstop beside its `onError` one, routed through `_log` like every other emit in the file. It logs a single `error` line — "the panel window event stream closed; window events can no longer reconcile the panel visibility mirror" — with no context map, stating the consequence rather than the event. Log-only by decision: no resubscription, retry or dead-stream flag, and the arm is deliberately unguarded by `_disposed` to match `onError`.

**Files changed.**
- [lib/src/infrastructure/panel/window_manager_panel_visibility.dart](../../lib/src/infrastructure/panel/window_manager_panel_visibility.dart) — the `onDone` arm, plus a comment paragraph qualifying it as explicitly defensive and log-only.
- [test/fakes/fake_panel_window.dart](../../test/fakes/fake_panel_window.dart) — `closeEvents()`, closing the events controller without disposing the window, and documenting that the fake emits nothing afterwards.
- [test/infrastructure/panel/window_manager_panel_visibility_test.dart](../../test/infrastructure/panel/window_manager_panel_visibility_test.dart) — three rows covering matrix rows 1, 2 and 4, the last using the shared `ThrowingLogger` and asserting its `attempts`.
- [_bmad-output/implementation-artifacts/deferred-work.md](deferred-work.md) — DW-36 closed with a resolution; one new deferred entry appended.

**Review findings.** 4 layers ran (adversarial, edge-case, verification-gap, intent-alignment). intent_gap 0, bad_spec 0, patch 3 (1 medium, 2 low), defer 1 (medium), reject 10. All three patches applied and re-verified — see the Review Triage Log. Follow-up review recommended: `true` (patched score 3×1 + 1×2 = 5).

**Verification.**
- `dart analyze` → No issues found.
- `dart test test/infrastructure/panel/` → 34/34 pass (31 before).
- Negative controls against the scoped panel suite, each reverted: deleting the `onDone` arm → 2 failures; bypassing `_log` → 1; moving the subscription cancel after `_window.dispose()` → 1. Scoped rather than full-suite deliberately, per DW-46.
- `dart test test/infrastructure/ test/application/ test/domain/` → **not green, and not made green here.** `wayland_portal_global_hotkey_test.dart` fails a varying subset run to run (observed 4, 4, 2 in isolation), reproduces on the untouched baseline, and imports nothing from the panel slice. This is DW-46, still open.

**Residual risks.**
- The arm is unreachable in the shipped daemon by construction: `main.dart` builds `WindowManagerPanelWindow` inline so nothing else holds it, and the adapter cancels before disposing it. It is a contract guard on the port, not a live-incident guard — pinned only by the fake.
- Log-only: a real close still leaves a permanently dead adapter answering from a mirror that can no longer be corrected. Nothing in-process learns about it.
- Seven sibling AD-15 subscriptions still guard `onError` only; deferred rather than adopted, since whether this is a rule or a one-site judgement is a design decision the intent does not carry.
- DW-46's flake means any verification claim drawn from a single full-suite run on this tree is unsound.
