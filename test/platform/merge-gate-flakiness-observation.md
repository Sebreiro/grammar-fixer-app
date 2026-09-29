# Merge-gate flakiness observation — G-01-19, the portal suite's timed barrier

**This file is a record of measurements that were made, not a procedure for ones
that are owed.** It is the third member of a family with
`test/platform/panel-toggle-observation.md` and
`test/platform/worker-gone-observation.md`, and is filed the same way:
`test/platform/runtime-observation-checklist.md` and
`test/platform/desktop-session-checklist.md` are the opposite kind of document —
manual procedures, pinned in `test/architecture/runtime_checklists_test.dart`'s
`_procedures` list because unconditionally skipped rows point at them by path.
**This file is deliberately not added to that list**, and section 7 says why in
its own voice rather than leaving the absence to be inferred.

**Date of the runs:** 2026-09-14.
**Gap this settles:** G-01-19 — `01-VERIFICATION.md` `gaps[3]`, the entry whose
`truth:` reads *"The gates this phase's record rests on actually pass"*. Its
first two `missing:` bullets are what this record and the change it describes
answer: diagnose the portal suite's nondeterminism, and *"establish the real pass
rate before any claim of a green gate is recorded again: run the scoped command
N≥10 times and record the ratio, not one exit code."* The third bullet — the
ledger entry — is plan 01-24's, and it cites this file.

**Plan:** `.planning/phases/01-hotkey-truth/01-23-PLAN.md`.

---

## 1. What was wrong

The CI merge-gate command was not reliably green, and nobody had measured it.
`01-VERIFICATION.md` ran the exact scoped command seven times, serially, with
nothing else running, and recorded **2 PASS / 5 FAIL**. Every failure was a
*different* set of rows:

| Verification run | Failures | Rows |
|---|---|---|
| A | 1 | `wayland_portal_global_hotkey_test.dart` — "A5 CAP-12: a rebind closes the old session…" |
| B | 3 | the same file's "A16 CAP-1: a press reaches every listener exactly once", plus `single_instance_lock_test.dart` "AD-14: release frees the address…" |
| C | 2 | "A5 CAP-12…" and "A19d AD-11: a ShortcutsChanged this build cannot read…" |
| D | 1 | "C2 AD-11, AD-12: a shortcut the desktop no longer holds…" |
| E | 1 | `daemon_startup_test.dart` "AD-14, CAP-1: the holder receives exactly one show request" |

At least five distinct rows in the portal suite, none reproducibly, and that file
passed 5/5 when run alone — which is why every single-file check had missed it.
`dart_test.yaml`'s `concurrency: 1` was already in force, so this was not the
cross-suite collision that setting's 15-line comment was written to fix; it was
intra-file nondeterminism the setting does not reach.

**This was PRE-EXISTING, not introduced by the gap-closure set.** None of the
three files named above appears in `git diff --name-only 52cebe8..HEAD` as
measured by that verification at HEAD `307f7f2`. It was nonetheless adjudicated
against phase 1 rather than deferred, because "the suite is green" is the sole
proof offered for several of the phase's verified truths, and every such record
was one draw from a distribution that failed about two runs in three: the prior
verification recorded `974 passed / 2 skipped, exit 0` as a measurement, and the
brief for the re-verification quoted `982 passed / 2 skipped`. The report's own
conclusion: *"Nothing else in this report should be read as certain about a truth
whose only proof is a single green run."*

## 2. The diagnosis

**One shared mechanism, and it is the barrier the rows synchronise on, not five
independent bugs.**

`_settle()` in `wayland_portal_global_hotkey_test.dart` was
`pumpEventQueue(times: 50)`. It is the barrier every observed-failing row waits
on — 36 direct call sites in that one file, plus 26 more through
`_bindAndSettle`, which calls it. `pumpEventQueue` yields a fixed number of
event-loop **turns**, not an interval of time, and fifty turns of an otherwise
empty queue complete in microseconds and consume no wall clock. What the rows are
waiting for is a real round trip over a real unix socket: emit on the fake
portal's service client, through `package:dbus`'s in-process bus, into the
adapter's client, dispatched to a stream listener. Whether the kernel has
delivered those bytes within fifty turns is a function of how busy the machine
is — which is exactly the difference between running the file alone and running
it after nine hundred other rows.

**The hypothesis was tested, not adopted.** A row was instrumented temporarily to
count how many event-loop turns actually elapse between `emitActivated()` and the
activation reaching the listener, pumping one turn at a time until it landed:

| Condition | Turns until delivery, six consecutive emits |
|---|---|
| Idle machine | 2, 2, 2, 3, 2, 2 |
| One busy-loop subshell per core (16 cores) | **255**, 2, 2, 2, 2, 2 |

Two turns when the machine is quiet; 255 — five times the budget `_settle()`
gives — when it is not. That is the mechanism, measured rather than argued, and
it explains the shape of every failure without exception: each one is an
`Expected: an object with length of <1> / Actual: []`, a row asserting on a list
the signal never reached, never a wrong value.

`01-VERIFICATION.md`'s own hypothesis — *"the varying rows share the fake D-Bus
client and its signal delivery, which suggests an un-awaited signal round trip
rather than five independent bugs"* — is **confirmed**, with one correction: the
round trip is not un-awaited by mistake, it is waited for with a barrier that
cannot express the wait.

### The three alternatives, ruled out

Each was considered explicitly, and one measurement disposes of all three: the
instrumented reproduction above runs **a single row, in a fresh process, with one
fake portal and no predecessor**, and it still took 255 turns. A cause that needs
a second fake, a previous row or accumulated state cannot produce a failure in
that setting.

1. **Temp-directory collision between fakes.** `FakeGlobalShortcutsPortal.start`
   calls `Directory.systemTemp.createTempSync('fake-portal-bus-')`, and that is a
   `mkdtemp`: the prefix is shared, the directory is not. A genuine collision
   would surface as a bind or connect error, not as a signal that silently fails
   to arrive. **Ruled out** — and reproduced with exactly one fake alive.
2. **A teardown returning before the bus is actually closed, so a previous row's
   client is still delivering.** That failure mode produces *extra* deliveries,
   and every observed failure is an assertion of *too few* — `[]` where one was
   expected. **Ruled out** — and reproduced with no previous row.
3. **Cross-row state on the fake's `calls` list.** `calls` is an instance field
   of a fake that each row stands up fresh, and not one of the observed failures
   asserts on it; they assert on activation lists and binding-change lists.
   **Ruled out** — and reproduced with a fresh instance.

## 3. The change

The barrier moved to the emit side and stopped being a count.
`FakeGlobalShortcutsPortal._emitSettled` is now the single place it lives, and
all five `emit*` methods (`emitActivated`, `emitActivatedFromImpostor`,
`emitMalformedShortcutsChanged`, `emitTruncatedSignal`, `emitShortcutsChanged`)
route through it. It is built from two D-Bus **ordering** guarantees, so it does
not get slower or less reliable as the machine gets busier:

* **Before the emit**, every live client pings the bus. A `DBusSignalStream`'s
  `AddMatch` goes out on that client's own connection before the ping does, and
  the bus reads one connection in order — so a bus that has answered the ping has
  already applied the match rule. This is the half `_bindAndSettle`'s own doc was
  reasoning about one abstraction below where it bit.
* **After the emit**, the sender pings every live client. The signal and the ping
  travel the same sender → bus → client path in that order, and a `DBusClient`
  dispatches the messages it reads into its signal streams in the order it reads
  them — so a client that has answered the ping has already handed the signal to
  whoever is listening.

An ordered round trip rather than a condition wait, because the rows that assert
an **absence** — "a press for another session reaches nobody", "a
`ShortcutsChanged` this build cannot read pushes nothing at all" — have no
condition to wait for. Delivery having *happened* is a fact those rows can be
measured against; a condition becoming true is not. A fixed-count pump was almost
certainly chosen because of them, and the replacement had to serve them too.

`_settle()` itself is unchanged in behaviour and re-documented as what it now is:
an in-process drain of the listener callback and whatever the adapter does inside
it, which no amount of machine load can stretch. `RecordingBusClient` keeps the
barrier's own `Ping` out of `methodCalls` so it cannot appear in the list AD-11's
step-4-comes-last row reads; the adapter issues no `Ping` of any kind, so nothing
real is hidden by that.

**Nothing was weakened to get there.** `expect(` in the portal suite: 237 before,
237 after. `test(`: 69 before, 69 after. Retry annotations and skips across the
suite and the fake: 0 before, 0 after. `git diff --numstat` over `dart_test.yaml`
and `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`: empty. No
production code was touched by this work at all.

### The reproduction, before and after

The oracle is the portal suite run **under artificial CPU contention** — one
busy-loop subshell per core from `nproc` (16 here), the file run five times, the
loops killed afterwards:

```bash
export PATH=$PATH:/home/vscode/flutter/bin:/home/vscode/flutter/bin/cache/dart-sdk/bin
pids=""; for i in $(seq "$(nproc)"); do (while :; do :; done) & pids="$pids $!"; done
fails=0
for r in 1 2 3 4 5; do
  dart test test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart 2>&1 \
    | tail -1 | grep -q 'All tests passed' || fails=$((fails+1))
done
kill $pids 2>/dev/null; echo "CONTENDED_FAILS=$fails/5"
```

| | Runs that failed | Failing rows seen |
|---|---|---|
| Before the change | **5 / 5** | 2–4 rows per run, varying: "A5 CAP-12: a rebind closes the old session…", "A6 AD-10: a `Session.Close` refused mid-rebind…", "D-17: an abandoned dialog leaves its session tracked…" |
| After the change | **0 / 5** | none |

The pre-change count is non-zero, so the post-change zero is evidence rather
than a gate that was always going to print zero. **These are numbers taken under
deliberate contention and they are not the pass rate** — section 4 is the pass
rate, and the two must not be read as the same measurement.

## 4. The measurement

### What was measured, quoted verbatim

The binding-free half, which is what `.github/workflows/ci.yml`'s final step
runs:

```
dart test --exclude-tags=live
test/application test/architecture test/domain test/infrastructure
test/fakes_smoke_test.dart
```

The Flutter-bound half:

```
flutter test --exclude-tags=live test/ui test/platform test/composition
```

**Do the two sources agree?** On the binding-free half, yes, verbatim:
`.planning/config.json`'s `workflow.test_command` and `ci.yml`'s last step are
the same command, argument for argument. They differ on scope, deliberately and
in the direction of the config being the larger gate: `workflow.test_command`
chains ` && flutter test --exclude-tags=live test/ui test/platform
test/composition` after it, while `ci.yml` omits the Flutter-bound half
altogether and says so in a comment — *"it carries every `test/ui` and
`test/platform` row, needs the Flutter tool rather than the Dart SDK alone, and
is slower by an order of magnitude. Adding it is a decision about gate cost, not
an oversight."* `ci.yml` also runs `dart analyze --fatal-infos` and
`tool/provision_sidecar.sh` ahead of the suite, which the config's
`workflow.build_command` carries separately. Both halves are measured below, so
this record covers the whole merge gate rather than only the half that was
failing.

### Binding-free half — 10 serial runs

| Run | Exit | Summary line | Failing rows |
|---|---|---|---|
| 1 | 0 | `00:57 +982 ~2: All tests passed!` | — |
| 2 | 0 | `00:58 +982 ~2: All tests passed!` | — |
| 3 | 0 | `00:57 +982 ~2: All tests passed!` | — |
| 4 | 0 | `00:57 +982 ~2: All tests passed!` | — |
| 5 | 0 | `00:57 +982 ~2: All tests passed!` | — |
| 6 | 0 | `00:57 +982 ~2: All tests passed!` | — |
| 7 | 0 | `00:57 +982 ~2: All tests passed!` | — |
| 8 | 0 | `00:57 +982 ~2: All tests passed!` | — |
| 9 | 0 | `00:58 +982 ~2: All tests passed!` | — |
| 10 | 0 | `00:58 +982 ~2: All tests passed!` | — |

**Ratio: 10 PASS / 0 FAIL over 10 runs.** 982 passed, 2 skipped every time; the
two skips are the `live`-tagged rows the tag excludes, and `.venv-sidecar` was
present for every run, so no row skipped for a missing sidecar. Wall clock 57–58
seconds per run.

### Flutter-bound half — 3 serial runs

| Run | Exit | Summary line | Failing rows |
|---|---|---|---|
| 1 | 0 | `00:25 +165 ~7: All tests passed!` | — |
| 2 | 0 | `00:25 +165 ~7: All tests passed!` | — |
| 3 | 0 | `00:26 +165 ~7: All tests passed!` | — |

**Ratio: 3 PASS / 0 FAIL over 3 runs.** 165 passed, 7 skipped — the same figure
`01-VERIFICATION.md` recorded for this half over its own 2 of 2 runs, so this
half is unchanged and was never the problem.

### Host conditions

Stated because the same command measures a different thing on a different
machine, and because section 3's contended numbers are emphatically *not* this
measurement.

* Linux devcontainer, 16 logical cores (`nproc`), Dart 3.12.2 / Flutter 3.44.8
  from `/home/vscode/flutter`.
* Runs were **serial** — one at a time, never parallelised; a parallel loop would
  measure contention, which is the opposite of what this number is for.
* Load average during the batch: 2.7–3.3, and that floor is honest rather than
  ideal. The agent session driving the runs (`claude`/`node`, 2–4 % CPU) was
  resident throughout, and an `Xvfb :99` plus `openbox` left running by an
  earlier plan in this phase were present and idle. Nothing else was started, no
  build ran beside the suite, and no busy loops were alive during section 4's
  runs.
* `dart_test.yaml`'s `concurrency: 1` was in force, untouched by this work.

## 5. What this does NOT settle

**A 10/10 is a result, not a proof of a fixed gate.** It is recorded as the
ratio it is, and the following are named with their observed frequency rather
than absorbed into it.

1. **`test/architecture/single_instance_lock_test.dart` — "AD-14: release frees
   the address for the very lock that held it". Observed failing once in the
   verification's seven full-suite runs (≈1/7). It did not fail in any of this
   run's ten.**
2. **`test/infrastructure/system/daemon_startup_test.dart` — "AD-14, CAP-1: the
   holder receives exactly one show request". Observed failing once in the
   verification's seven full-suite runs (≈1/7). It did not fail in any of this
   run's ten.**

   Their mechanism is a different one from section 2's and is untouched by this
   change: the Dart VM allows exactly one abstract-namespace unix socket bind per
   *process*, and both files bind one because AD-14's singleton is the thing they
   exist to test. `dart_test.yaml`'s comment describes that hazard and cites
   DW-15; `concurrency: 1` addresses it **across** suites, not **within** one.

   **Ten runs cannot distinguish "fixed" from "not sampled" at a one-in-seven
   rate.** At p = 1/7 per run, ten clean runs are an unremarkable outcome — the
   probability of seeing none is roughly 0.21, so this sample is entirely
   consistent with the defect being exactly as present as it was. Reading these
   two rows as fixed because they did not appear here would be the same reasoning
   error that produced this whole gap: treating a sample as a measurement. They
   are residuals, they are filed as residuals, and plan 01-24 carries them into
   the deferred-work ledger.
3. **Ten runs is the floor the verification asked for, not a statement about
   rare events generally.** Anything failing at less than roughly one run in ten
   is invisible to this sample by construction.
4. **This says nothing about GitHub Actions.** `ci.yml` has still never executed
   — its own header says so. These numbers are from one Linux devcontainer, and
   a runner is a different machine with different load, which is precisely the
   variable section 2 identified as the one that mattered.
5. **It does not vindicate the phase's earlier single-run claims.** Those
   remain single draws from a distribution that was failing about two runs in
   three when they were taken. What this record establishes is that the gate has
   a measured pass rate from 2026-09-14 forward; it does not retroactively make a
   lucky exit code into evidence. `01-VERIFICATION.md` is deliberately not edited
   to match — a later finding is filed beside the earlier text, never written
   over it, which is the rule that report's own `gaps_closed` note about DW-129
   sets for this phase.

## 6. Re-running it

Measure the same thing, the same way. **Serially**, and on a machine that is not
doing anything else.

```bash
export PATH=$PATH:/home/vscode/flutter/bin:/home/vscode/flutter/bin/cache/dart-sdk/bin

# The binding-free half — the exact command .github/workflows/ci.yml runs.
for r in $(seq 10); do
  out=$(dart test --exclude-tags=live \
    test/application test/architecture test/domain test/infrastructure \
    test/fakes_smoke_test.dart 2>&1)
  echo "RUN $r exit=$? | $(echo "$out" | tail -1)"
  echo "$out" | grep -E '\[E\]' | head -6
done

# The Flutter-bound half.
for r in $(seq 3); do
  out=$(flutter test --exclude-tags=live test/ui test/platform test/composition 2>&1)
  echo "RUN $r exit=$? | $(echo "$out" | tail -1)"
done
```

Budget roughly 12–15 minutes for the first loop and 2 minutes for the second.
Record the ratio whatever it is, with the per-run outcomes and the host
conditions beside it. Section 3's contended loop is a *different* measurement and
belongs under its own heading; do not merge the two.

## 7. Why this file is NOT added to `runtime_checklists_test.dart`'s `_procedures`

It is not added, and these are the three reasons `worker-gone-observation.md` §6
gives, checked against *this* record rather than copied:

1. **`_procedures` holds manual procedures.** Each entry there is a
   step-numbered instruction sheet whose every step carries a `*Settles:* DW-nn`
   bullet, with `preconditionSteps`, `groups`, a results table and a claim set
   checked in both directions; the suite's own closing row prints *"both are
   manual: read them, do not run them"*. This record is the opposite kind of
   thing — the write-up of runs that already happened, whose section 6 is a
   re-run recipe for a machine rather than a procedure for a person.
2. **The precedent is already set twice inside this phase.**
   `panel-toggle-observation.md` and `worker-gone-observation.md` are the same
   kind of artefact and neither is a `_Procedure`. Adding this third one while
   its two siblings stay out would invent a second convention for one file.
3. **The structural assertions would not merely be unnecessary, they would
   fail.** `_stepsIn`, `_requiredBullets` and the both-directions `claims` check
   all read numbered steps carrying DW ids, and this record has neither — its
   numbered sections are prose headings, not steps, and its one ledger reference
   is DW-15, cited as the *mechanism* of a residual rather than as a step's
   settlement. Nor does anything point at it: the `_procedures` guard exists
   because unconditionally-skipped `fail()` rows name a procedure by path and a
   skipped row cannot report that the path rotted. No skipped row names this
   record.

So `test/architecture/runtime_checklists_test.dart` is not edited by the plan
that produced this file, and is correctly absent from its `files_modified`.
