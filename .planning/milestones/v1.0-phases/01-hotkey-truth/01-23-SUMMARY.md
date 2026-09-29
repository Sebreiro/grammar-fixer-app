---
phase: 01-hotkey-truth
plan: 23
subsystem: test-harness
tags: [flakiness, dbus, test-infrastructure, gap-closure, measurement]
gap_closure: true
gap_ids: [G-01-19]
requires:
  - "01-21, 01-22 (wave 1) — this plan's measurement is only meaningful on the final tree with nothing else competing for the CPU"
provides:
  - "An ordered D-Bus delivery barrier in FakeGlobalShortcutsPortal, replacing a fixed event-loop-turn count as the thing every portal-suite row synchronises on"
  - "test/platform/merge-gate-flakiness-observation.md — the merge gate's measured pass ratio over 10 + 3 serial runs, the diagnosis, and every residual named with its frequency"
affects:
  - "Every claim in this phase's record whose sole proof was a green run of the scoped command"
  - "Plan 01-24, which files DW-131 citing the observation record's numbers"
tech-stack:
  added: []
  patterns:
    - "Ordered round trip as a test barrier: use a protocol's own message-ordering guarantee instead of a count of event-loop turns whenever a test waits on a real socket"
key-files:
  created:
    - test/platform/merge-gate-flakiness-observation.md
  modified:
    - test/support/fake_global_shortcuts_portal.dart
    - test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart
key-decisions:
  - "The barrier lives on the fake's emit side (FakeGlobalShortcutsPortal._emitSettled), not in the suite's _settle() helper: all five emit* methods inherit it in one place, and the emit side is the only side that can order both halves of the trip."
  - "Ordered round trip rather than condition-with-deadline, because the rows that assert an ABSENCE have no condition to wait for; delivery having happened is a fact they can be measured against."
  - "_settle() is kept at pumpEventQueue(times: 50), unchanged in behaviour and re-documented: it is now an in-process drain of the listener callback, which machine load cannot stretch."
  - "The 10/10 ratio is recorded as a ratio, not as 'the gate is green'; the two AD-14 abstract-socket suites are filed as residuals with the arithmetic showing ten runs cannot distinguish 'fixed' from 'not sampled' at 1/7."
requirements-completed: []
metrics:
  duration: "26 min"
  completed: "2026-09-14"
  tasks: 2
  files: 3
actuals:
  tokens: 38750
  tasks: 2
  commits: 2
coverage:
  - deliverable: "The portal suite's rows synchronise on something that does not depend on how busy the machine is"
    verification:
      - kind: command
        ref: "contended oracle: one busy loop per core, 5 serial runs of test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart — 5/5 failed before the change, 0/5 after"
        status: pass
      - kind: command
        ref: "dart test test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart (uncontended) — All tests passed, 71 rows"
        status: pass
    human_judgment: false
  - deliverable: "Nothing was skipped, retried, loosened or deleted to reach green"
    verification:
      - kind: command
        ref: "grep -c 'expect(' = 237 (baseline 237); grep -c 'test(' = 69 (baseline 69); retry/skip grep = 0; git diff --numstat over dart_test.yaml and the adapter = empty"
        status: pass
    human_judgment: false
  - deliverable: "The merge gate has a measured pass rate with the runs behind it written down"
    verification:
      - kind: command
        ref: "10 serial runs of the binding-free scoped command (10 PASS / 0 FAIL) and 3 of the Flutter-bound half (3 PASS / 0 FAIL), each row recorded in test/platform/merge-gate-flakiness-observation.md §4"
        status: pass
    human_judgment: false
  - deliverable: "The diagnosis names ONE shared mechanism, with evidence gathered in this run"
    verification:
      - kind: command
        ref: "instrumented row counting event-loop turns to delivery: 2,2,2,3,2,2 idle vs 255,2,2,2,2,2 under contention, against _settle()'s budget of 50"
        status: pass
    human_judgment: false
status: complete
---

# Phase 1 Plan 23: Merge-Gate Flakiness — Diagnosis, Ordered Barrier, Measured Ratio Summary

The portal suite's rows waited on a fixed count of event-loop turns for a signal
crossing a real unix socket; that count is a function of machine load, so the
barrier was replaced with a D-Bus ordered round trip on the fake's emit side, and
the merge gate's pass rate was then measured as a ratio over 10 + 3 serial runs
instead of read off one exit code.

**Duration:** 26 min (2026-09-14T17:53:51Z → 2026-09-14T18:20:11Z)
**Tasks:** 2 of 2
**Files:** 3 (1 created, 2 modified)
**Commits:** `9eb8a47`, `3feab6d`

## Accomplishments

### Task 1 — one diagnosis, one barrier, proven by a reproduction that fails first (`9eb8a47`)

**The reproduction, and its pre-change failure count.** Option (a) from the plan
— the single file under artificial CPU contention, one busy-loop subshell per
core (16 here), the file run five times — reproduced immediately and hard:

```
PRECHANGE_CONTENDED_FAILS=5/5
```

**Five out of five**, with 2–4 distinct rows failing per run and the set varying
between runs, exactly as the verification described for the full suite. The
number is non-zero, so option (b) — five serial runs of the full scoped command —
was not needed as a fallback oracle; it was nonetheless run once before the
change as a sanity check and once after (green both times), and the full 10-run
measurement in Task 2 covers it properly.

The failing rows under contention were `A5 CAP-12: a rebind closes the old
session…`, `A6 AD-10: a Session.Close refused mid-rebind…` and `D-17: an
abandoned dialog leaves its session tracked…` — overlapping but not identical
with the verification's five, which is itself evidence: the rows that fail are
whichever ones happen to be sampled while the machine is busy, not a fixed set.

**The diagnosis: ONE shared mechanism.** `_settle()` was
`pumpEventQueue(times: 50)` — the barrier all 36 direct call sites and 26
`_bindAndSettle` call sites in that file wait on. `pumpEventQueue` yields event
loop **turns**, not time, and fifty turns of an empty queue consume no wall
clock; what the rows wait for is a real round trip over a real unix socket. The
hypothesis in `gaps[3].missing` (*"an un-awaited signal round trip rather than
five independent bugs"*) was **confirmed by instrumentation rather than adopted**:
a row was temporarily instrumented to pump one turn at a time and count until the
activation landed.

| Condition | Turns until delivery, six consecutive emits |
|---|---|
| Idle machine | 2, 2, 2, 3, 2, 2 |
| One busy loop per core | **255**, 2, 2, 2, 2, 2 |

Two turns idle; 255 — five times the budget — under load. One correction to the
verification's wording: the round trip is not un-awaited by mistake, it is waited
for with a barrier that cannot express the wait. Corroborating evidence: every
observed failure has the identical shape, `Expected: an object with length of
<1> / Actual: []` — a row asserting on a list the signal never reached, never a
wrong value.

**The three alternatives, ruled out** — and one measurement disposes of all
three, because the instrumented reproduction runs a single row in a fresh process
with one fake and no predecessor:

| Alternative | Result |
|---|---|
| Temp-directory collision between fakes (`createTempSync` with a shared prefix) | **Ruled out.** `createTempSync` is a `mkdtemp`: the prefix is shared, the directory is not, and a real collision surfaces as a bind/connect error rather than a silently missing signal. Reproduced with exactly one fake alive. |
| Teardown returning before the bus is closed, so a previous row's client still delivers | **Ruled out.** That produces *extra* deliveries; every observed failure is *too few* (`[]`). Reproduced with no previous row. |
| Cross-row state on the fake's `calls` list | **Ruled out.** `calls` is an instance field of a fake each row stands up fresh, and no observed failure asserts on it. Reproduced with a fresh instance. |

**The fix, in exactly one place.** `FakeGlobalShortcutsPortal._emitSettled` — the
emit side, so all five `emit*` methods inherit it:

```dart
Future<void> _emitSettled({
  required DBusClient from,
  required DBusObjectPath path,
  required String interface,
  required String name,
  required List<DBusValue> values,
}) async
```

with a private helper `Iterable<RecordingBusClient> get _synchronisableClients`
(clients that are neither closed nor unconnected — `clientForNoBus()`'s client
has no bus name, so waiting on it would wait forever rather than fail).

**Shape: ordered, not timed**, built from two D-Bus ordering guarantees:

* **before** the emit, every live client pings the bus — a `DBusSignalStream`'s
  `AddMatch` goes out on that client's own connection ahead of the ping, and the
  bus reads one connection in order, so a bus that answered has already applied
  the match rule (this is the half `_bindAndSettle`'s own doc reasoned about);
* **after** the emit, the sender pings every live client — signal and ping travel
  the same sender → bus → client path in that order, and `DBusClient` dispatches
  messages into its signal streams in the order it reads them, so a client that
  answered has already handed the signal to its listeners.

**How the absence-asserting rows are served.** They are the constraint that
decided the shape. `A17 CAP-1: a press for another session … reaches nobody` and
`C2 AD-11: a ShortcutsChanged this build cannot read pushes nothing at all` have
no condition to wait for, so a condition-with-deadline barrier cannot serve them
— it would degrade to a timeout and back to "a race made rarer". An ordered round
trip gives them the fact they actually need: *delivery has happened, and nothing
arrived*. `from` is a parameter for the same reason ordering is per connection —
`emitActivatedFromImpostor` emits from a different client, and pinging from the
fake's own would order against the wrong stream.

One supporting change: `RecordingBusClient` keeps the barrier's `Ping` out of
`methodCalls`/`matchRuleCalls`, because that trip is the harness synchronising,
not the adapter calling anything, and `A18 AD-11` reads that list. Safe because
the adapter issues no `Ping` at all — `grep -in ping` on
`wayland_portal_global_hotkey.dart` hits only "mapping" and "stopping".

`_settle()` is **unchanged in behaviour** (still `pumpEventQueue(times: 50)`) and
re-documented as what it now is: an in-process drain of the listener callback,
load-independent. Not raised, not lowered.

**Post-change result of the same reproduction:** `CONTENDED_FAILS=0/5` over five
consecutive repetitions. 5/5 → 0/5 on the identical command.

### Task 2 — the gate's real pass rate, measured and written down (`3feab6d`)

`test/platform/merge-gate-flakiness-observation.md` (372 lines), the third
member of the family with `panel-toggle-observation.md` and
`worker-gone-observation.md`, in the same register and with the same seven-section
shape.

| Half of the gate | Runs | Ratio | Per-run outcome |
|---|---|---|---|
| Binding-free (`dart test --exclude-tags=live …`) | 10 serial | **10 PASS / 0 FAIL** | exit 0 every run, `982 passed / 2 skipped`, 57–58 s each |
| Flutter-bound (`flutter test --exclude-tags=live test/ui test/platform test/composition`) | 3 serial | **3 PASS / 0 FAIL** | exit 0 every run, `165 passed / 7 skipped`, 25–26 s each |

The Flutter-bound figure matches the verification's own (165/7, 2 of 2 runs)
exactly — that half was never the problem.

The record quotes both commands verbatim and answers the agreement question:
`.planning/config.json`'s `workflow.test_command` and `.github/workflows/ci.yml`
agree argument-for-argument on the binding-free half; they differ on scope, with
the config chaining the Flutter-bound half that `ci.yml` deliberately omits (its
own comment: *"Adding it is a decision about gate cost, not an oversight"*).
`ci.yml` additionally runs `dart analyze --fatal-infos` and
`tool/provision_sidecar.sh` first; `.venv-sidecar` was present for every run here,
so no row skipped for a missing sidecar and the two skips are the `live`-tagged
rows the tag excludes.

**Host conditions are stated, and the contended numbers are kept separate.**
16-core devcontainer, serial runs, load average 2.7–3.3 with the agent session
and an idle `Xvfb :99` + `openbox` left by an earlier plan resident — stated as
the honest floor rather than claimed as zero. Section 3's contended 5/5 → 0/5 is
under its own heading with an explicit sentence that it is a different
measurement and must not be read as the pass rate.

**Residuals named with frequency**, in the record's §5: both AD-14
abstract-socket suites (`single_instance_lock_test.dart`,
`daemon_startup_test.dart`), each observed failing once in the verification's
seven runs (≈1/7), neither failing in this run's ten — with the arithmetic
spelled out (at p = 1/7, ten clean runs happen about 21 % of the time, so this
sample is entirely consistent with the defect being exactly as present as it
was). Plus: ten runs cannot see anything rarer than ~1/10; `ci.yml` has still
never executed on a real runner; and a 10/10 here does not retroactively make the
phase's earlier single-run claims into evidence.

`01-VERIFICATION.md` was **not** edited and `runtime_checklists_test.dart` was
**not** edited; §7 gives the three `worker-gone-observation.md` §6 reasons checked
against this record rather than copied.

## Deviations from Plan

None — plan executed exactly as written. No deviation rule was invoked: no bug
was found outside the diagnosed mechanism, no missing critical functionality, no
blocker, and nothing architectural. The plan's escape hatch for a diagnosis that
implicates production code was not needed — `lib/` is untouched.

## Verification Results

| Check | Result |
|---|---|
| `dart analyze --fatal-infos` | **No issues found!** |
| Contended reproduction, post-change | `CONTENDED_FAILS=0/5` (pre-change `5/5`, non-zero as required) |
| `grep -c 'expect('` on the portal suite | **237** (baseline 237) |
| `grep -c 'test('` on the portal suite | **69** (baseline 69) |
| Retry/skip grep across the suite and the fake | **0** |
| `git diff --numstat` — `dart_test.yaml`, the portal adapter | **empty** |
| `git diff --numstat` — the four frozen port declarations | **empty** |
| `git diff --numstat` — `runtime_checklists_test.dart`, `01-VERIFICATION.md` | **empty** |
| `git diff --numstat` — plans/summaries `01-0*`, `01-1*`, `01-20-*` | **empty** |
| Portal suite alone | `All tests passed!`, 71 rows |
| Observation record: run rows / ratio / `--exclude-tags=live` / AD-14 suites named | 13 / 10 / 5 / 4 hits — all above their thresholds |
| `flutter test --exclude-tags=live test/platform` after the record was added | `All tests passed!` |

**Grep note (inherited from wave 1):** every count above was taken with
`/usr/bin/grep` (GNU grep 3.11), not the `ugrep 7.8.4` shell function that
shadows `grep` in this harness. Loops were run under `bash -c`, not zsh, so
`$pids` word-splits as intended and the busy loops were really started and really
killed — a gate that reports a number for the wrong reason is not a proof.

## Ratio outcome, stated plainly

**The gate measured 10 PASS / 0 FAIL over 10 runs and 3 PASS / 0 FAIL over 3.**
That is recorded as the ratio it is, not as "the suite is green". What it does
**not** establish:

- The two AD-14 abstract-socket suites are **not** shown to be fixed. Their
  mechanism (one abstract-namespace socket bind per process; `concurrency: 1`
  reaches across suites, not within one) is untouched by this work, and ten runs
  cannot distinguish "fixed" from "not sampled" at a one-in-seven rate. Handed to
  **plan 01-24** by name, for DW-131.
- `gaps[3].missing`'s third bullet — the ledger entry — is 01-24's work and is
  not done here.

## Known Stubs

None. No placeholder, empty-value or TODO was introduced; the change is a test
harness barrier and a measurement record, both fully wired.

## Threat Flags

None. No new network endpoint, auth path, file-access pattern or schema change.
T-01-146 (the record quoting host-revealing failure output) was dispositioned
`accept` in the plan and remains correct: the record quotes only row names,
summary lines and turn counts — no user text is reachable from any row in the
portal suite, which drives a fake portal on a temp-directory bus over synthetic
shortcut ids.

## Issues Encountered

None.

## Next Phase Readiness

`gaps[3]`'s first two `missing:` bullets are satisfied. Plan 01-24 is next and is
the one that files the ledger entry citing
`test/platform/merge-gate-flakiness-observation.md`'s measured numbers — which
are 10/10 and 3/3, with both AD-14 socket suites outstanding as residuals.

## Self-Check: PASSED

- `test/platform/merge-gate-flakiness-observation.md` — FOUND
- `test/support/fake_global_shortcuts_portal.dart` — FOUND
- `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart` — FOUND
- commit `9eb8a47` — FOUND
- commit `3feab6d` — FOUND
