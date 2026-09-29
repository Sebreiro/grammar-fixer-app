---
phase: 01-hotkey-truth
plan: 21
subsystem: testing
tags: [bash, uat-probe, x11, xclip, privacy, file-permissions, process-isolation]

# Dependency graph
requires:
  - phase: 01-hotkey-truth
    provides: "01-17's live fault-injection probe (`tool/uat/worker_gone_probe.sh`) and its observation record `test/platform/worker-gone-observation.md`"
provides:
  - "A probe whose exit trap signals only processes this run launched, matched by the bundle path inside the throwaway worktree rather than by the application's name"
  - "A probe whose durable output directory is 0700 from the moment it exists, halting the run if it cannot be restricted"
  - "A preflight clipboard gate that REFUSES on a non-empty selection and clears only a selection it proved empty, so the panel every capture shows is empty by construction"
  - "The four pre-existing output directories under /tmp/worker-gone-probe-out/ restricted to 0700 without deleting the two 01-VERIFICATION.md cites as its proof-by-difference"
  - "An observation record whose re-run section states what the output directory holds, its mode, and the clipboard precondition"
affects: [phase-01 verification, any future live UAT probe in tool/uat/]

actuals:
  tokens: 12300
  tasks: 3
  commits: 3

tech-stack:
  added: [xclip]
  patterns:
    - "Teardown guarded by a did-this-run-create-it flag, with process matching anchored to a path this run built"
    - "Refuse-then-establish: a precondition on state the probe does not own is a named halt, never a mutation"

key-files:
  created: []
  modified:
    - tool/uat/worker_gone_probe.sh
    - test/platform/worker-gone-observation.md

key-decisions:
  - "The clipboard-owner global is named CLIPBOARD_OWNER_PID, declared empty in the mutable-global block and torn down from `cleanup` behind the same guard discipline as `stop_daemon`."
  - "xclip forks to serve the selection, so `$!` is not the surviving owner: the gate diffs the matching pids before and after and records only the pid that was not there before, so teardown can never signal a foreign xclip."
  - "The gear-step before-capture is KEPT, not removed — the empty-clipboard precondition plus 0700 makes it safe, and it is the mechanism that turns a click that changed nothing into a named halt."
  - "The four pre-existing output directories were RESTRICTED to 0700, never deleted: two are cited by full path in 01-VERIFICATION.md as the two halves of its proof-by-difference."
  - "`halt`'s `${OUT_DIR:-/tmp}` screenshot fallback was left exactly as it is — it is unreachable, and widening the task to it would have been scope creep on a plan about not writing user text to /tmp."

patterns-established:
  - "Guarded teardown: every signal a harness sends is gated on a per-run flag set at the moment the harness created the thing it is signalling."
  - "Anchored process matching: a harness matches the absolute path it built inside its own temp root, never the application's name."
  - "Restrict-don't-delete for evidence remediation: an exposure in an artifact another document cites is closed with a mode change, not an rm."

requirements-completed: []

coverage:
  - id: D1
    description: "A halt on any path leaves every process the probe did not start alive, and the preflight refusal about a foreign daemon no longer kills that daemon"
    verification:
      - kind: e2e
        ref: "decoy check — a foreign process whose command line contains a `bundle/hotkey_grammar_corrector` path survives `DISPLAY=:987 ./tool/uat/worker_gone_probe.sh --at HEAD` (DECOY_SURVIVED, probe_exit=2), run twice"
        status: pass
      - kind: other
        ref: "region-scoped gates on `stop_daemon`: 2 worktree-scoped process matches, 0 DAEMON_PAT references, DAEMON_STARTED present 3 times in non-comment lines"
        status: pass
    human_judgment: false
  - id: D2
    description: "The probe's durable output directory is 0700 from the moment it exists, and a run refuses rather than proceeding beside a non-empty clipboard"
    verification:
      - kind: other
        ref: "`grep -n 'mkdir -p \"$OUT_DIR\"' -A 2 | grep -c 'chmod 700 \"$OUT_DIR\"'` = 1; the chmod line's failure branch calls `die`; non-comment `chmod 700` count = 2"
        status: pass
      - kind: e2e
        ref: "refusal branch EXECUTED on Xvfb :88 + openbox with a seeded selection — `REFUSED rc=2 clipboard_mentions=1 selection=[secret]`"
        status: pass
      - kind: e2e
        ref: "full live run on Xvfb :99 + openbox at 1ff58eb — `stat -c %a` on the output directory = 700, `RESULT ... REFUSAL_CODE=workerGone ... VERDICT=REPORTED_UNAVAILABLE`, exit 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "No window capture the probe writes can contain the user's text"
    verification:
      - kind: automated_ui
        ref: "/tmp/worker-gone-probe-out/post-privacy-fix-1ff58eb-20260914104208/step-settings-gear-before.png — the panel capture from the live run, opened and read: the 'Your text' editor is empty, the three suggestion cards carry only their register labels"
        status: pass
    human_judgment: true
    rationale: "The final evidence is a picture judged by eye. It was opened and read during execution and shows an empty editor, but 'this capture carries no user text' is a visual judgment that belongs with a human at end-of-phase verification, not an assertion a command returns."
  - id: D4
    description: "The exposure earlier runs already left on disk is closed without destroying the record's own evidence"
    verification:
      - kind: other
        ref: "`find /tmp/worker-gone-probe-out -mindepth 1 -maxdepth 1 -type d -perm /077 | wc -l` = 0 (4 before); both files 01-VERIFICATION.md cites by full path still exist (CITED_EVIDENCE_INTACT)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The observation record states the output directory's contents, its mode and the clipboard precondition where the re-run command is published"
    verification:
      - kind: other
        ref: "§7-to-end greps: `0700` = 1, `clipboard` = 3 lines, `capture|screenshot` = 4 lines; `git diff --numstat -- test/architecture/runtime_checklists_test.dart` empty"
        status: pass
      - kind: unit
        ref: "flutter test --exclude-tags=live test/platform — All tests passed (+18 ~7)"
        status: pass
    human_judgment: false

duration: 9 min
completed: 2026-09-14
status: complete
---

# Phase 01 Plan 21: The closure artifact stops leaking and stops killing — Summary

**`worker_gone_probe.sh` now signals only the daemon it launched (matched by the worktree bundle path, behind a `DAEMON_STARTED` guard), writes its captures into a 0700 directory, and refuses to start beside a non-empty clipboard instead of clearing one it did not fill — proven by a decoy that survived a real halt, a seeded selection that survived a real refusal, and a full live run that came back `VERDICT=REPORTED_UNAVAILABLE` with `stat -c %a` = 700.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-09-14T17:34:14Z
- **Completed:** 2026-09-14T17:43:41Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- **Teardown is a no-op until this run launched something.** `DAEMON_STARTED=0` sits with the other per-run globals, becomes `1` on the statement immediately after the background launch assigns `DAEMON_SID`, and `stop_daemon`'s first statement is `[ "$DAEMON_STARTED" = 1 ] || return 0`. Both the `pkill -f` and the `pgrep -f` inside that function now name `"${WORKTREE}/${BUNDLE_REL}"`. The preflight refusal that tells the operator to stop a running daemon by hand is true for the first time.
- **The output directory is restricted the moment it exists.** `chmod 700 "$OUT_DIR" || die "could not restrict $OUT_DIR"` on the line after the `mkdir -p`, the same treatment `$XDG_ROOT/rt` already had one function below.
- **The panel the run photographs cannot carry the user's text.** A preflight gate reads the clipboard of `$DISPLAY`, `die`s with a named reason when it holds anything, and only once the read proved it empty takes ownership of an empty selection — recording the owner's pid for a guarded teardown. `xclip` joined the required-tool loop so a missing tool is a halt rather than a silently skipped gate.
- **The exposure is closed on disk as well as in the script.** The four directories the 11 September runs left under `/tmp/worker-gone-probe-out/` went from world-readable to 0700 without a single deletion.
- **The record publishes the reasoning with the command.** §7 now says what the output directory holds, that one capture is of the panel rather than the settings screen and why, that the directory is 0700 and why, and that the run refuses while the clipboard is non-empty — and refuses rather than clearing because the probe does not destroy state it did not create.

## Task Commits

1. **Task 1 (tracer): the teardown touches only what this run started** — `901e12e` (fix)
2. **Task 2: nothing the run leaves behind is readable, and nothing it captures can be the user's text** — `8afa492` (fix)
3. **Task 3: the record publishes the reasoning with the command** — `1ff58eb` (docs)

## Files Created/Modified

- `tool/uat/worker_gone_probe.sh` — `DAEMON_STARTED` + `CLIPBOARD_OWNER_PID` globals; guarded and worktree-scoped `stop_daemon`; guarded clipboard-owner teardown in `cleanup`; `xclip` in the required-tool loop; the preflight clipboard gate; `chmod 700 "$OUT_DIR"` with a `die` branch.
- `test/platform/worker-gone-observation.md` — §7's closing paragraph extended with the three facts, plus a paragraph carrying the mode, the reason for it, and the clipboard precondition.

## Decisions Made

- **The clipboard-owner global is `CLIPBOARD_OWNER_PID`** — declared empty beside `DAEMON_STARTED` in the mutable-global block, set only inside the preflight gate, and torn down from `cleanup` as `[ -n "$CLIPBOARD_OWNER_PID" ] && kill "$CLIPBOARD_OWNER_PID"`.
- **The owner pid is found by diffing, not by `$!`.** Measured here: `printf '' | xclip -selection clipboard -d :88 &` records pid 8384, which is dead one second later, while pid 8386 — xclip's own fork — is the process actually serving the selection. Recording `$!` would have made the teardown a no-op and left a selection owner behind on every run; pgrep'ing the pattern blindly would have made it able to kill a foreign xclip on the same display, which is the same defect as the unanchored `pkill` this plan removed. So the gate snapshots the matching pids before it takes ownership and records only the pid that was not there before.
- **`halt`'s `${OUT_DIR:-/tmp}` screenshot fallback was deliberately left alone.** It is unreachable: `halt` only takes a screenshot once `$TOPLEVEL` has been resolved, and `resolve_toplevel` runs long after `preflight` has assigned `OUT_DIR`. Widening the task to an unreachable branch would have been scope creep in a plan whose whole subject is what does reach `/tmp`.
- **The gear-step before-capture stays, and that is a trade rather than a clean removal.** `click_confirmed`'s first statement still photographs whatever is on screen, and at the gear step what is on screen is the correction panel — the live run's `step-settings-gear-before.png` is a picture of the "Your text" editor. It stays because it is the mechanism that turns a click that changed nothing into a named halt instead of a silent assumption; removing it would trade a privacy defect for a verification one. What changed is that the panel it shows is empty by construction (the clipboard gate) and unreadable by any other account (0700). The capture is defended by two independent properties rather than deleted.
- **Part C is a one-time operator remediation, not new script behaviour** (see below).

## Part C — the four pre-existing output directories: disposition

**This is scope the plan chose, not scope `gaps[0]`'s `missing:` bullets asked for.** Tasks 2A and 2B close the mechanism for runs from here on; they do nothing about the runs that already happened. Leaving those would have left the Core Value clause violated on disk at the moment this plan was marked complete.

- **What was done:** `find /tmp/worker-gone-probe-out -mindepth 1 -maxdepth 1 -type d -exec chmod 700 {} +`, run once, by hand.
- **Restricted, never deleted.** `pre-fix-4247446-20260911062323/settings-after-rebind.png` and `post-fix-2-49c5f9f-20260911062625/step-settings-gear-before.png` are cited by full path in 01-VERIFICATION.md as the two halves of its proof-by-difference. Deleting them would destroy the record's own evidence. Both verified present afterwards (`CITED_EVIDENCE_INTACT`).
- **Measured:** `find … -perm /077 | wc -l` = **4 before**, **0 after**. All four now `drwx------`.
- **`PROBE_OUT_DIR`** was unset on this host, so `/tmp` is the only root that needed remediating; no second root was found or treated.
- **The script was deliberately NOT taught to do this.** A run reaching back into its predecessors' output would break this plan's own prohibition — the probe never mutates state it did not create, the same rule that made the clipboard gate a refusal instead of a clear. The script owns the directory it creates; the operator owns the ones already there.
- **The parent `/tmp/worker-gone-probe-out` remains world-traversable**, per T-01-137's accepted disposition: only labels and timestamps are visible through it, and no capture, log or diff is reachable once every leaf is 0700.

## Verification results

| Check | Result |
|---|---|
| `bash -n tool/uat/worker_gone_probe.sh` | `SYNTAX_OK`, exit 0 |
| `DAEMON_STARTED` in non-comment lines | 3 (declaration, `start_daemon`, guard) |
| `stop_daemon` worktree-scoped `pkill`/`pgrep` pair | 2 |
| `DAEMON_PAT` inside `stop_daemon` | 0 (still correct and present in `preflight` and `daemon_pids`, both unedited) |
| Decoy isolation check (run twice) | `DECOY_SURVIVED pid=8055 probe_exit=2`, `DECOY_SURVIVED pid=10747 probe_exit=2` |
| `chmod 700 "$OUT_DIR"` adjacency / `die` branch | 1 / 1 |
| non-comment `chmod 700` count | 2 |
| `xclip` inside `preflight` (non-comment) | 5; the first sits above the dirty-tree gate's `status --porcelain` line |
| **Refusal branch, EXECUTED on `:88`** | **`REFUSED rc=2 clipboard_mentions=1 selection=[secret]`** |
| Empty-clipboard path, executed on `:88` | gate passed, took ownership, halted later at the dirty-tree gate, and cleanup left `owners after cleanup: []` with the selection unowned again |
| `find /tmp/worker-gone-probe-out … -perm /077 \| wc -l` | 0 (4 before) |
| Cited evidence files | `CITED_EVIDENCE_INTACT` |
| §7 greps (`0700` / `clipboard` / `capture\|screenshot`) | 1 / 3 / 4 |
| `git diff --numstat -- test/architecture/runtime_checklists_test.dart` | empty |
| `flutter test --exclude-tags=live test/platform` | All tests passed (+18 ~7) |
| Frozen port declarations, `02ccfef..HEAD` | empty diff — this plan touched no `lib/` file |
| Plans 01-01 … 01-20 and their SUMMARYs, `02ccfef..HEAD` | empty diff |

The display used for the refusal-branch run was **`:88`**, as the plan specified: `/tmp/.X11-unix` held `X0`–`X28` and `X99` at execution time, so `:88` was free and the run left the other displays alone.

**The full merge gate is deliberately not asserted green here.** This plan changes no Dart source; `test/platform` was run because Task 3 edits a file in that tree. 01-VERIFICATION.md `gaps[3]` measured the merge gate at 2 PASS / 5 FAIL over 7 runs, and plan 01-23 owns that ratio.

## The owed live observation — TAKEN

The plan named one end-of-phase human observation and said to record whether it was taken. **It was taken**, and it is the first run of this probe since the two defects were closed (01-VERIFICATION.md skipped running it deliberately, because running it would have reproduced them).

`Xvfb :99` and `openbox` were **not** up at execution start, so they were started for this run and left running. Command, at `HEAD` = `1ff58eb`:

```
RESULT rebind-worker-gone REV=1ff58eb INJECTED=yes BOUND=Ctrl+Shift+G REQUESTED=Ctrl+Shift+F9
  REFUSAL_CODE=workerGone LOG=refused
  SCREEN=/tmp/worker-gone-probe-out/post-privacy-fix-1ff58eb-20260914104208/settings-after-rebind.png
  VERDICT=REPORTED_UNAVAILABLE
```

- `stat -c %a /tmp/worker-gone-probe-out/post-privacy-fix-1ff58eb-20260914104208` → **`700`**. Every file inside it is `-rw-r--r--`, and unreachable by another account through the 0700 directory.
- The probe exited **0**. The clipboard gate passed on an unowned selection, took ownership of an empty one, and cleanup killed exactly that owner: afterwards `pgrep -c xclip` = 0, the `:99` clipboard reads back unowned (exit 1), and `pgrep -cf 'bundle/hotkey_grammar_correcto[r]'` = 0.
- `git worktree list` shows only `/workspace`; no `/tmp/worker-gone-probe.*` root survives; `git status --porcelain -uno -- lib/ test/ tool/` is empty. `assert_no_trace` still holds with both guards in place — the guard did not over-apply and leave the probe's own daemon or worktree behind (T-01-136).
- `step-settings-gear-before.png` from that run was opened during execution: it shows the correction panel with an **empty** "Your text" editor, an inactive Correct button, and the three suggestion cards carrying only `formal` / `casual` / `shorter`. That is the clipboard precondition working end to end. It is still listed as `human_judgment: true` in the coverage block, because the final step of that evidence is a picture read by eye.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `test/platform/worker-gone-observation.md` has no §8**

- **Found during:** Task 3
- **Issue:** The plan's action and acceptance criterion both ask for a sentence at "§8's closing line", following 01-VERIFICATION.md's `gaps[0].artifacts`, which names "§7 … and §8's closing line". The file has seven sections: `## 7. Re-running it` is the last heading (`:300`) and the file ends at `:313`. There is no §8 to edit.
- **Fix:** The sentence both documents describe — the one naming what outlives the run — is §7's closing sentence ("Everything it writes that outlives the run — the screenshot, the daemon log, the injection diff — is in the output directory the `SCREEN=` field names"). Fact 1 was folded into exactly that sentence: "the screenshot" became "the window captures", and the sentence now continues with which capture is of the panel and why. No section was invented, and no section was renumbered.
- **Files modified:** `test/platform/worker-gone-observation.md`
- **Verification:** §7-to-end greps all pass (`0700` = 1, `clipboard` = 3, `capture|screenshot` = 4); `flutter test --exclude-tags=live test/platform` passes.
- **Committed in:** `1ff58eb`

**2. [Rule 3 - Blocking] Two of Task 2's gate commands cannot match under this harness's `grep`**

- **Found during:** Task 2
- **Issue:** `grep` in the execution shell is **ugrep 7.8.4**, injected as a shell function by the harness's shell snapshot, and it treats `$` as an anchor everywhere in a basic regular expression. The plan's gates `grep -n 'mkdir -p "$OUT_DIR"' -A 2 …` and `grep -n 'chmod 700 "$OUT_DIR"' …` therefore match **nothing at all**, regardless of the file's contents — they would have reported `0` against a perfectly correct implementation, and `0` against a missing one. `printf 'x$Y' | grep -c 'x$Y'` returns `0` here. Task 1's equivalent gate was unaffected because it escapes its dollars (`\$\{WORKTREE\}`).
- **Fix:** Both gates were run against `/usr/bin/grep` (**GNU grep 3.11**, which is what an operator's own shell resolves; the ugrep shadowing is a harness artifact, not this host's `grep`). Command semantics are otherwise byte-identical to the plan's. Both returned **1**, the required value. One adjacent implementation change followed from actually being able to read the gate: the explanatory comment above the new `chmod` was written as two lines first, which put the `chmod` three lines below the `mkdir -p` and outside the `-A 2` window the gate asserts; it was shortened to one line so the restriction really is adjacent to the creation, which is the property the gate exists to protect.
- **Files modified:** `tool/uat/worker_gone_probe.sh` (comment shortened; no behaviour change)
- **Verification:** `/usr/bin/grep -n 'mkdir -p "$OUT_DIR"' -A 2 … | /usr/bin/grep -c 'chmod 700 "$OUT_DIR"'` = 1; `/usr/bin/grep -n 'chmod 700 "$OUT_DIR"' … | /usr/bin/grep -c 'die'` = 1.
- **Committed in:** `8afa492`

---

**Total deviations:** 2 auto-fixed (2 blocking).
**Impact on plan:** Neither changed what was built. The first re-targeted one sentence to the section that actually exists; the second changed which binary evaluated two gates and, in doing so, caught a real adjacency defect the broken gate would have hidden. No scope creep; no `missing:` bullet went unaddressed.

## Issues Encountered

- **xclip's self-fork.** The plan asked for "the pid of the process that then owns the empty selection", and the obvious `$!` is not it — xclip forks and the parent exits immediately, so a run would have recorded a dead pid and left the real owner behind forever. Resolved inside Task 2 with the before/after pid diff described under Decisions; verified twice on `:88` (owner killed, selection unowned afterwards) and once on `:99` during the live run.
- **A concurrent commit landed mid-plan.** `9aba184 docs(roadmap): merge phases 2-7 into a single phase 2` appeared on `feat/bootstrap-domain-ring` between this plan's start and its first commit, carrying `.planning/ROADMAP.md` and `.planning/STATE.md`. It is not this plan's work; both of this plan's code commits are single-file (`git show --stat` confirms), and the plan's `files_modified` set was not widened.

## User Setup Required

None — no external service configuration required. Note that `Xvfb :99` and `openbox` were started during execution for the owed live observation and were left running.

## Next Phase Readiness

- Both 🛑 BLOCKER rows against `tool/uat/worker_gone_probe.sh` in 01-VERIFICATION.md § Anti-Patterns Found are closed, and every one of the five `missing:` bullets across `gaps[0]` and `gaps[1]` maps to a satisfied acceptance criterion.
- The probe is, for the first time, safe to run for verification: a re-run is now a mode-700 directory, an empty captured panel, and a teardown that touches nothing it did not create. Re-verification of this phase can execute it rather than reason about it.
- Still open in this phase and owned elsewhere: `gaps[2]` (the five-subject prose site) by 01-22, `gaps[3]` (the 2/7 merge-gate ratio) by 01-23, and the DW-131 ledger entry by 01-24.

## Self-Check: PASSED

- `tool/uat/worker_gone_probe.sh` — FOUND
- `test/platform/worker-gone-observation.md` — FOUND
- `.planning/phases/01-hotkey-truth/01-21-SUMMARY.md` — FOUND
- Commits `901e12e`, `8afa492`, `1ff58eb` — all FOUND in `git log`
- All plan-level `<verification>` checks re-run and recorded in the table above; no criterion left unmeasured.

---
*Phase: 01-hotkey-truth*
*Completed: 2026-09-14*
