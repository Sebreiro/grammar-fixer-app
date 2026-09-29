---
phase: 01-hotkey-truth
reviewed: 2026-09-14T15:20:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - tool/uat/worker_gone_probe.sh
  - lib/src/ui/settings/hotkey_capture_field.dart
  - test/support/fake_global_shortcuts_portal.dart
  - test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart
  - test/platform/worker-gone-observation.md
  - test/platform/merge-gate-flakiness-observation.md
  - _bmad-output/implementation-artifacts/deferred-work.md
findings:
  critical: 1
  warning: 7
  info: 5
  total: 13
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-09-14T15:20:00Z
**Depth:** standard
**Files Reviewed:** 7 (the `--gaps-only` set, `git diff 4c38d44..HEAD` over the paths plans 01-21 … 01-24 changed)
**Status:** issues_found

## Summary

Scope is the four gap-closure plans only, at the user's direction. Everything else in
phase 01 was reviewed on 2026-09-11 and is untouched here. `deferred-work.md` is
append-only, so only the new `DW-131` entry was read, and only for accuracy against what
it cites.

### The prior report's three findings, adjudicated against the tree

| Prior finding | Verdict |
| --- | --- |
| **CR-01** — the exit trap SIGTERMs a daemon it did not start | **Closed for the daemon**, and correctly. `DAEMON_STARTED=0` is initialised at `:63`, set at `:372` immediately after the background launch (before the readiness loop, which is the right place), and `stop_daemon`'s first statement is `[ "$DAEMON_STARTED" = 1 ] || return 0`. `stop_daemon` has exactly one caller (`cleanup`), so the guard covers every teardown path. `pkill`/`pgrep` are anchored to `"${WORKTREE}/${BUNDLE_REL}"`, and `WORKTREE` is set in `preflight` from a `mktemp -d` root before anything can set `DAEMON_STARTED=1`, so the pattern is never the degenerate `/build/linux/...`. The surviving `pgrep -f "$DAEMON_PAT"` at `:249` is a preflight *check*, not teardown, and the `[r]` bracket still keeps it off the running shell. **But the same class of defect was reintroduced at smaller scale in the new clipboard code — see WR-02.** |
| **CR-02** — world-readable captures of the clipboard-seeded panel editor under `/tmp` | **Half closed.** The `0700` half is done (`:262`, with a `die` on failure) and the four directories the prior report named have been remediated out of band: `ls -ld /tmp/worker-gone-probe-out/*` now reports `drwx------` for all five, including the three from 2026-09-11. The second half — "nothing is captured while the panel is up" — was **not** implemented; it was replaced by a preflight clipboard gate, which is a legitimate alternative design but **does not hold**: see CR-01 below. The probe still photographs the clipboard-seeded panel editor; the whole privacy claim now rests on a gate that a newline-only clipboard walks straight through. |
| **WR-03** — `hotkey_capture_field.dart:61` still said "five-subject" | **Closed.** `HotkeyCaptureRefusal` has exactly four values (`levelThreeModifier`, `modifierOnly`, `noModifier`, `keyNotRegistrable`) and `verdictFor` has four `HotkeyCaptureRefused(` return sites. `grep -rniE "five[ -](subject\|thing)" lib/ test/` returns zero hits. This is the only change in the set with no defect of its own. |

### On 01-23's barrier, which is the largest change in the set

**The barrier is genuinely ordered, not a disguised timeout, and I traced it rather than
taking the doc's word.** In `package:dbus` 0.7.14: `_DBusRemoteClient._processMessages`
(`dbus_server.dart:170-191`) reads one message and calls `server._processMessage(this, m)`
**without awaiting**, and `_processMessage`'s first block (`dbus_server.dart:541-551`)
forwards to every matching client *synchronously, before any `await`* — so the bus writes
the signal to a client's socket before the later ping. On the receiving side
`DBusClient._processMessages` (`dbus_client.dart:944-964`) reads one message per iteration
and `_processSignal` (`:1045`) adds to the signal-stream controllers synchronously, while
`_processMethodCall` (the Ping) is `async` and replies a microtask later. Both halves of
`_emitSettled`'s stated argument hold. `_settle()` is correctly left alone.

**Measured, not assumed.** I reproduced the oracle: 16 busy-loop subshells (one per core),
five serial runs of the portal suite → **5 PASS / 0 FAIL** (7 s each, vs. 4.4 s idle, so
the load was real). The binding-free merge-gate half → `982 passed / 2 skipped`, exit 0.
`dart analyze lib test` → *No issues found*. `dart format --set-exit-if-changed` over the
three changed Dart files → 0 changed. `expect(` 237 → 237 and `test(` 69 → 69 across the
change, as the observation record claims.

**The absence-asserting rows do not pass vacuously as a result of the barrier** — with
delivery now ordered, a row that emits from the impostor and asserts an empty list is
measuring the adapter's (or the bus's) rejection rather than a signal that never arrived.
The one exception is already documented in the suite's own voice at `:1770-1775` ("A20
above emits after `dispose()` has returned, so the client is already closed and the signal
never reaches the adapter at all"); `_synchronisableClients`' doc names the same exclusion
honestly. No new finding there.

**Key concerns in what was added.** All of the serious ones are in
`tool/uat/worker_gone_probe.sh`, and they cluster on the new clipboard gate: it is the
load-bearing half of the privacy fix, it destroys state it proves nothing about, it runs
before the cheap refusals that would have stopped the run, and its teardown reaches for a
pid it derived from an all-users `pgrep` in a 0.5 s window. Separately, the probe's leak
assertion is advisory: I verified empirically that `assert_no_trace`'s `return 1` does not
change the script's exit status, so a run that leaves the injected `throw` in a tracked
`lib/` file still exits 0.

---

## Narrative Findings (AI reviewer)

### Critical Issues

#### CR-01: the clipboard emptiness gate is defeated by command substitution, so the probe seizes and destroys a clipboard it never proved was empty

**File:** `tool/uat/worker_gone_probe.sh:212-224`
**Issue:** the gate's own comment states the contract it is there to keep — *"clearing a
selection the probe did not fill would destroy the user's text, which is the clause this
gate exists to protect — so refuse first, and clear only once the read has proved there
was nothing there to destroy."* The read cannot prove that:

```bash
clip=$(xclip -selection clipboard -o -d "$DISPLAY" 2>/dev/null) || clip=""
if [ -n "$clip" ]; then
  die "the clipboard of $DISPLAY is not empty — ..."
fi
```

`$(...)` strips **all** trailing newlines. A clipboard whose content is only newlines — or
any text that reduces to the empty string once trailing whitespace is stripped — reads
back as `""`, `[ -n "$clip" ]` is false, and the next four lines take ownership of the
selection away from its owner and hand it to a `printf ''`. The original content is then
unrecoverable: X selection ownership is exclusive, and `cleanup` later kills the new owner
too, leaving the selection unowned.

**Reproduced on a throwaway `Xvfb`:**

```
TARGETS: TARGETS UTF8_STRING        # the selection is owned, and offers text
clip len=0
GATE PASSES -> newline-only clipboard would be seized and destroyed
```

with `printf '\n\n\n' | xclip -selection clipboard` as the owner. The gate reports empty
against a selection that demonstrably holds three bytes of the user's text.

The predicate is also the wrong one in principle. What the run needs to know is *"does
anything own this selection"*, and `-n "$clip"` answers *"is the default target's payload
non-empty after the shell mangled it"*. Those differ for every owner whose payload is
whitespace, and for any owner offering only a target `xclip -o` declines to convert.

This matters more than a dev-tool bug normally would, because CR-02's privacy fix was
rewritten to rest entirely on this gate. `worker-gone-observation.md:320-321` now tells the
next operator that *"the panel it captures is empty by construction"* — it is not; it is
empty whenever this predicate happens to be right. And the destroyed content is exactly
what `.claude/CLAUDE.md`'s Core Value names: the daemon "never loses, corrupts, or leaks
the user's text".

**Fix:** gate on ownership, not on the payload, and byte-count rather than shell-string the
payload if you also want the content check. Both are cheap:

```bash
  # Ownership, not emptiness: `$(...)` strips trailing newlines, so a selection
  # holding only newlines reads back as the empty string and the payload test
  # says "nothing here" about text the probe is one line away from destroying.
  # `-t TARGETS` answers the question actually being asked — is anything holding
  # this selection — and answers it for an owner offering any target at all.
  if xclip -selection clipboard -o -t TARGETS -d "$DISPLAY" >/dev/null 2>&1; then
    die "the clipboard of $DISPLAY is owned by another client — this probe raises a panel seeded from the clipboard and captures it, so it will not run while anything holds the selection; clear it yourself, or give the probe a display it has to itself"
  fi
```

---

### Warnings

#### WR-01: the seizure runs before the preflight refusals, so a run that refuses to do anything has already taken the user's selection

**File:** `tool/uat/worker_gone_probe.sh:212-224` (the gate) against `:236-241` (dirty
tree), `:245-246` (bad revision), `:249-251` (a daemon is already up), `:253-254`
(`mktemp`)
**Issue:** the clipboard block is the *first* destructive statement in `preflight`, and
four `die`s follow it. A developer who runs the probe with a daemon already up — the exact
case CR-01 of the prior report was written about — now gets a halt that tells them to stop
the daemon by hand, **after** the probe has already taken the clipboard selection from
whatever owned it, and `cleanup` then kills the probe's own `xclip`, leaving the selection
unowned where an application had it a moment earlier.

This is the ordering discipline the file already applies elsewhere: `stop_daemon`'s new
comment reasons explicitly about not acting on the refusal path, and `assert_no_trace` has
`SOURCE_TREES_WERE_CLEAN` for the same reason. The clipboard block did not inherit it.

**Fix:** move the whole block to the end of `preflight`, after the last `die` — the emptiness
*check* can stay where it is (it is read-only and refusing early is good), but the
`printf '' | xclip …` seizure must be the last thing `preflight` does:

```bash
  # Last, after every refusal above: taking the selection is destructive, and a
  # run that is about to refuse must not have changed anything first.
  owners=" $(pgrep -u "$(id -u)" -f "xclip -selection clipboard -d $DISPLAY" 2>/dev/null | tr '\n' ' ') "
  printf '' | xclip -selection clipboard -d "$DISPLAY" >/dev/null 2>&1 &
  ...
```

#### WR-02: `CLIPBOARD_OWNER_PID` can name a process this run did not start, which the exit trap then signals

**File:** `tool/uat/worker_gone_probe.sh:217-224` (derivation), `:119` (`kill` in
`cleanup`)
**Issue:** three separate defects in one eight-line block, all of the class CR-01 was
raised about:

1. **All users, not this one.** `pgrep -f` without `-u` matches every process on the host.
   Any `xclip -selection clipboard -d :99` that starts inside the 0.5 s `sleep` window is
   not in the `owners` snapshot, so the `case` treats it as new and adopts it. `cleanup`
   then `kill`s it. For a second probe run, or for the developer's own `xclip` on the same
   display, that succeeds.
2. **Last-wins loses pids.** The loop assigns `CLIPBOARD_OWNER_PID` on every new match and
   keeps only the last. If more than one new pid is present at the 0.5 s mark (xclip forks
   to serve the selection, which the comment itself notes), the others are never killed and
   outlive the run holding the selection — and `assert_no_trace` does not look for them.
3. **A fixed 0.5 s is the only synchronisation, and the outcome is never checked.** On a
   loaded machine `xclip` may not have claimed the selection yet; `CLIPBOARD_OWNER_PID`
   stays empty, nothing is cleaned up, and the run proceeds with the clipboard in an
   unknown state while `worker-gone-observation.md` asserts it is empty by construction.

**Fix:** scope the match to this uid, keep every new pid, and assert that the seizure
landed instead of sleeping on it.

```bash
  CLIPBOARD_OWNER_PIDS=""
  owners=" $(pgrep -u "$(id -u)" -f "xclip -selection clipboard -d $DISPLAY" 2>/dev/null | tr '\n' ' ') "
  printf '' | xclip -selection clipboard -d "$DISPLAY" >/dev/null 2>&1 &
  local i=0
  # Poll for ownership rather than sleeping on it: what this needs to know is
  # that the selection is now ours, and a fixed delay answers a different
  # question on a loaded machine than it does on an idle one.
  while [ "$i" -lt 100 ]; do
    xclip -selection clipboard -o -t TARGETS -d "$DISPLAY" >/dev/null 2>&1 && break
    i=$((i + 1)); sleep 0.1
  done
  [ "$i" -lt 100 ] || die "the probe could not take the clipboard of $DISPLAY"
  for owner in $(pgrep -u "$(id -u)" -f "xclip -selection clipboard -d $DISPLAY" 2>/dev/null); do
    case "$owners" in *" $owner "*) ;; *) CLIPBOARD_OWNER_PIDS="$CLIPBOARD_OWNER_PIDS $owner" ;; esac
  done
```

with `cleanup` looping over `$CLIPBOARD_OWNER_PIDS`.

#### WR-03: `assert_no_trace` cannot fail the run — a probe that leaves the injected `throw` in `lib/` still exits 0

**File:** `tool/uat/worker_gone_probe.sh:134-169` (`assert_no_trace`), `:115-131`
(`cleanup`), `:169` (`trap cleanup EXIT`), `:631-632` (`main`'s exits)
**Issue:** `assert_no_trace` ends in `return 1` on a leak, and it is the last command of
`cleanup`, which is the `EXIT` trap. In bash, an `EXIT` trap that returns without calling
`exit` does not change the shell's exit status. Verified directly:

```
$ bash traptest.sh; echo "script exit status = $?"
ok
cleanup ran
!!! PROBE LEFT A TRACE
script exit status = 0
```

So the three things the assertion exists to catch — a tracked file under `lib/`/`test/`/
`tool/` still carrying the injected `throw StateError('worker_gone_probe.sh injected worker
death…')`, a surviving `worker-gone-probe.` worktree, a surviving temp root — are reported
on stderr and then contradicted by `exit 0` and a `RESULT … VERDICT=REPORTED_*` line. The
file's own comment says *"A probe that leaks a patched worktree is worse than a probe that
does not run"*; anything reading the exit code (a wrapper, CI, an agent loop) cannot tell.
The `git worktree remove --force` at `:122` runs before this, so the reachable case is
teardown failing, which is precisely when the assertion matters.

**Fix:** make the trap exit with a distinct status when it found something.

```bash
cleanup() {
  local status=$?
  stop_daemon
  ...
  # A leak is a verdict about the run, so it has to reach the exit code: an
  # EXIT trap that merely returns leaves `$?` as it was, and a wrapper reading
  # only the status would ship the injected throw.
  assert_no_trace || exit 4
  exit "$status"
}
```

#### WR-04: the probe defaults to the inherited `DISPLAY`, and the new gate makes that destructive on a real desktop

**File:** `tool/uat/worker_gone_probe.sh:49` (`export DISPLAY="${DISPLAY:-:99}"`) against
the new `:212-224`
**Issue:** `:99` is only a fallback; a developer with `DISPLAY=:0` runs the probe against
their live session. Before this change that meant XTEST keystrokes and window captures on
the real desktop — bad, but non-destructive of persistent state. It now also means the
probe takes their clipboard selection (CR-01 shows the gate will not always stop it) and
kills the owner at teardown. The halt text at `:215` advises *"give the probe a display it
has to itself"*, but nothing enforces it, and the advice is only reachable on the path
where the gate already refused.

**Fix:** refuse a display this run does not own, rather than advising it.

```bash
# Not `${DISPLAY:-:99}`: inheriting the operator's display points a run that
# injects keystrokes, photographs windows and takes the clipboard selection at
# their live session. The probe needs a throwaway server; say so.
: "${PROBE_DISPLAY:=}"
[ -n "$PROBE_DISPLAY" ] || die "set PROBE_DISPLAY to a throwaway X display (e.g. PROBE_DISPLAY=:99 with Xvfb :99 …); this probe injects keys, captures windows and takes the clipboard, and must not be pointed at a session you are using"
export DISPLAY="$PROBE_DISPLAY"
```

#### WR-05: the new observation record names a file path that does not exist — the same path DW-131 was written to correct

**File:** `test/platform/merge-gate-flakiness-observation.md:277`
**Issue:** §5's first residual reads:

```markdown
1. **`test/architecture/single_instance_lock_test.dart` — "AD-14: release frees
   the address for the very lock that held it". …
```

`find test -name single_instance_lock_test.dart` returns exactly one path, and it is
`test/infrastructure/system/single_instance_lock_test.dart`. DW-131 — filed by 01-24 in the
same pass, and whose `location:` field points *at this very file* — closes with a paragraph
titled "One disagreement with an existing record" that exists solely to correct this path
slip in `01-VERIFICATION.md`, and gets it right in its own `location:`. The record the
ledger defers to therefore repeats the error the ledger entry corrects, in the one section
a reader chasing a residual will open. §5.2's sibling bullet, two lines below, uses the
correct `test/infrastructure/system/` prefix for `daemon_startup_test.dart`, so this is an
isolated slip rather than a convention.

**Fix:** `test/infrastructure/system/single_instance_lock_test.dart` at `:277`. (DW-131 is
append-only and is correct as written; only the observation record needs the edit.)

#### WR-06: `worker-gone-observation.md` claims the probe does not clear the selection, and that the captured panel is empty by construction — neither is true of the code

**File:** `test/platform/worker-gone-observation.md:318-321`
**Issue:** two claims in the new paragraph outrun the implementation:

> *"For the same reason the run refuses to start while the clipboard of its display holds
> anything: it halts in the preflight with a named reason, so the panel it captures is
> empty by construction. It refuses rather than clearing the selection itself, because
> content the probe did not put there is the user's text, and this probe does not destroy
> state it did not create."*

The probe **does** clear the selection — `worker_gone_probe.sh:218` runs
`printf '' | xclip -selection clipboard -d "$DISPLAY" &` on every run that gets past the
gate, taking ownership from whatever held it. And "empty by construction" is exactly as
strong as the gate, which CR-01 shows admits a newline-only clipboard. This is the document
§7 publishes re-run instructions in, so the next operator inherits both claims.

**Fix:** state what the code does, and bound the guarantee:

```markdown
The run refuses to start while another client owns the clipboard of its display —
it halts in the preflight with a named reason — and then takes the selection
itself with an empty payload, so the panel it captures holds nothing. It refuses
before it takes, because content the probe did not put there is the user's text.
```

#### WR-07: the barrier's `Ping` exclusion keys on the method name alone, so the oracle AD-11's step-4 row reads depends on an ungated grep

**File:** `test/support/fake_global_shortcuts_portal.dart:853-872`
**Issue:** `RecordingBusClient.callMethod` now skips `methodCalls`/`matchRuleCalls`
recording for `name == 'Ping'`, with no interface test. The justification is a grep, quoted
in the comment, that the adapter issues no `Ping`. That grep is not asserted anywhere, so
the day a portal or bus method named `Ping` enters the adapter, the call vanishes from
`methodCalls` — which is the list AD-11's "step 4 comes **last**" row reads, and its whole
subject is call order. A silently-shortened list does not fail that row, it passes it.

The correct predicate is free, and it is the one the comment is actually reasoning about:
the barrier's ping is `org.freedesktop.DBus.Peer.Ping` (`dbus_client.dart:580-587`), and
nothing else is.

**Fix:**

```dart
    // Keyed on the Peer interface, not on the bare name: the exclusion is for
    // the harness's own round trip, and a portal method that happened to be
    // called `Ping` would otherwise vanish from the list AD-11's
    // step-4-comes-last row reads — silently passing it rather than failing it.
    if (interface == 'org.freedesktop.DBus.Peer' && name == 'Ping') {
      return super.callMethod(/* … */);
    }
```

---

### Info

#### IN-01: DW-131's `_settle()` call-site counts are line counts, not call sites

**File:** `_bmad-output/implementation-artifacts/deferred-work.md` (DW-131, `reason:` §2);
same numbers at `test/platform/merge-gate-flakiness-observation.md:75-77`
**Issue:** "36 direct call sites in that one file plus 26 more through `_bindAndSettle`".
Measured with `/usr/bin/grep`: 36 is the count of *lines* containing `_settle()`, one of
which is the declaration at `:2293` and one of which is the call inside `_bindAndSettle` at
`:2307` — so 34 direct call sites in rows. `_bindAndSettle` has 26 occurrences, one of
which is its own declaration at `:2302` — so 25 call sites. The conclusion is unaffected;
the numbers are the entry's own evidence, and the entry is otherwise scrupulous about
distinguishing a count from a sample.
**Fix:** 34 and 25, in both places. (The ledger is append-only — this is noted for whoever
next cites DW-131, not as an edit to it.)

#### IN-02: DW-131 cites the replacement `_settle()` doc as `:2285-2292`; it is `:2276-2292`

**File:** `_bmad-output/implementation-artifacts/deferred-work.md` (DW-131, `location:`)
**Issue:** the doc comment opens at `:2276` (`/// Drains what is left once the bus has
already delivered.`). The cited range names only its last eight lines, omitting the
sentence that states what `_settle()` now is. Every other anchor in that `location:` field
checks out exactly — `_emitSettled` at `:351`, the five `emit*` at `:387`, `:412`, `:434`,
`:457`, `:472`, `_settle()` at `:2293`, `_bindAndSettle` at `:2302`, the four rows at
`:387`, `:1363`, `:1559`, `:1686`, `dart_test.yaml:11-26` and `:27` — which is why the one
that does not stands out.
**Fix:** `:2276-2292` when the anchor is next re-derived.

#### IN-03: §7's "its one ledger reference is DW-15" is not what the file contains

**File:** `test/platform/merge-gate-flakiness-observation.md:366-370`
**Issue:** `grep -o "DW-[0-9]*"` over the file returns `DW-15` **and** `DW-129` (cited in
§5.5 for the don't-overwrite-an-earlier-record rule). The structural argument for staying
out of `_procedures` survives untouched — neither reference is attached to a numbered step
— but the sentence as written is checkable and false.
**Fix:** "its ledger references are DW-15 and DW-129, neither attached to a numbered step".

#### IN-04: no `umask`, so everything the probe writes is `0644` and protected only by the directory mode

**File:** `tool/uat/worker_gone_probe.sh:260-262`, `:362` (`DAEMON_LOG`), `:458`
(`shot_window`)
**Issue:** `chmod 700 "$OUT_DIR"` is the single control. Measured on this host, the files
inside are `-rw-r--r--` — unreadable to other accounts today only because the containing
directory is `0700`. One relaxed mode, one `PROBE_OUT_DIR` pointed at a shared path whose
leaf already exists, or one `cp -r` of the evidence, and the window captures of the panel
editor are world-readable again. Defence in depth here is one line.
**Fix:** `umask 077` at the top of `preflight`, before `mkdir -p "$OUT_DIR"`, keeping the
`chmod` as the explicit statement of intent.

#### IN-05: `_synchronisableClients` is a lazy view over a mutable list, iterated across `await` points

**File:** `test/support/fake_global_shortcuts_portal.dart:379-381`, consumed at `:359-369`
**Issue:** the getter returns `_clients.where(...)` — a lazy `Iterable` over the live
`List`. Both loops in `_emitSettled` `await` inside the iteration, so any code that adds a
client while the barrier is open throws `ConcurrentModificationError` out of an `emit*`
call. Not reachable today (no `beforeBindShortcuts`/`beforeSessionClose` hook creates a
client, and the suite is green), but the hooks exist precisely so a row can run arbitrary
code inside a handler, and `beforeSessionClose` already calls `emitActivated()` from inside
one at `:1791-1794`.
**Fix:** snapshot once — `final clients = _synchronisableClients.toList();` — and use it for
both loops, which also makes the two halves provably symmetric about the same client set.

---

_Reviewed: 2026-09-14T15:20:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

## 2026-09-23 Incremental Review — Plan 01-25

**Scope:** `tool/uat/worker_gone_probe.sh`, `test/platform/worker_gone_probe_preflight_test.sh`, and `test/platform/worker-gone-observation.md`, changed since the preceding review at `c63db14`. This addendum preserves that review's original findings and evidence above.

**New findings:** None at standard depth. The new harness runs the current probe by absolute path from a clean scratch Git repository on three dedicated Xvfb displays. It rejects the invalid-revision halt for both owned cases, checks the exact newline bytes and `image/png` TARGETS after refusal, and logs any xclip write before a later refusal. The preflight checks TARGETS early and immediately before its sole write; source inspection found no `die` path after that write. `bash -n` and all three X11 cases passed.

**Adjudicated prior findings:** CR-01, WR-01, and WR-06 are closed by the TARGETS gate, moving the write after preflight refusals, and correcting §7. The test reproduces the old loss before the fix and preserves both selections afterward. The 0700 output restriction and existing teardown path were unchanged. This addendum does not claim the prior review's other warnings or information findings were fixed; in particular, WR-02's PID discovery concern and WR-03's advisory leak assertion remain outside plan 01-25.

**Limit:** The harness stops on an invalid revision before building a bundle or taking screenshots. The prior workerGone live observation remains the evidence for that path. A client on a shared display can change ownership after the last check; §7 now instructs operators to use a dedicated display.
