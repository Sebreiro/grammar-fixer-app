---
phase: 01-hotkey-truth
plan: 25
subsystem: testing
tags: [x11, clipboard, xclip, xvfb, gap-closure, privacy]
gap_closure: true
gap_ids: [G-01-20]
requires:
  - phase: "01-21"
    provides: "WorkerGone live probe, run-scoped teardown, and 0700 capture output"
  - phase: "01-24"
    provides: "Phase 01 gap-closure record and accepted CI gate override"
provides:
  - "A TARGETS-based preflight refusal that preserves foreign CLIPBOARD ownership, including newline-only text and empty non-text targets"
  - "The probe's empty selection write moved after every preflight refusal, with a second ownership check immediately before it"
  - "A dedicated-X11 fail-first harness and an accurate operator re-run contract"
affects: [phase-01 verification, workerGone live observation]
actuals:
  tokens: 3593
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns:
    - "Use the exit status of CLIPBOARD TARGETS to detect an owner; payload contents are not an ownership predicate"
    - "Run the current tracked probe by absolute path from a disposable clean Git repository"
key-files:
  created:
    - test/platform/worker_gone_probe_preflight_test.sh
  modified:
    - tool/uat/worker_gone_probe.sh
    - test/platform/worker-gone-observation.md
key-decisions:
  - "The probe checks TARGETS before the source-tree gate and once more immediately before its sole empty-selection write. An owner detected at either point causes a named refusal."
  - "The regression harness uses an invalid revision in a clean scratch repository to stop before worktree creation and bundle building while exercising the real preflight."
patterns-established:
  - "A live safety harness proves old failure and new success using the same current file path, dedicated X server, and exact command."
requirements-completed: []
coverage:
  - id: D1
    description: "Foreign newline-only and empty image/png CLIPBOARD selections survive a named preflight refusal"
    verification:
      - kind: e2e
        ref: "bash test/platform/worker_gone_probe_preflight_test.sh#newline-only,non-text-owner"
        status: pass
    human_judgment: false
  - id: D2
    description: "An unowned selection receives no xclip write before a later preflight refusal, and the write is after every refusal path"
    verification:
      - kind: e2e
        ref: "bash test/platform/worker_gone_probe_preflight_test.sh#late-refusal"
        status: pass
    human_judgment: false
  - id: D3
    description: "The published re-run instructions distinguish foreign-owner refusal from accepted-run empty ownership and bound the screenshot expectation to a dedicated display"
    verification:
      - kind: other
        ref: "python3 §7 keyword check from 01-25-PLAN.md"
        status: pass
    human_judgment: true
    rationale: "The keyword check cannot judge whether an operator understands the display race and screenshot privacy boundary."
  - id: D4
    description: "The pre-existing 0700 output, scoped teardown, and workerGone result remain intact"
    verification:
      - kind: other
        ref: "git diff 8e5ac91..HEAD -- tool/uat/worker_gone_probe.sh test/platform/worker-gone-observation.md; bash -n tool/uat/worker_gone_probe.sh"
        status: pass
    human_judgment: true
    rationale: "The preflight-only harness does not repeat a full bundle run or capture; the prior 01-21 live observation remains the behavioral evidence."
duration: 6 min
completed: 2026-09-23
status: complete
---

# Phase 01 Plan 25: Preserve Foreign Clipboard Ownership in the WorkerGone Probe

**The probe now refuses on any foreign CLIPBOARD owner before altering the selection, and takes its own empty selection only after every preflight refusal path has passed.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-09-23T14:59:07Z
- **Completed:** 2026-09-23T15:05:00Z
- **Tasks:** 2 of 2
- **Files modified:** 3

## Accomplishments

- Added a real Xvfb/openbox harness that invokes the current probe by absolute path from a clean, disposable Git repository and records the fail-first counterexamples.
- Replaced the text-payload gate with two TARGETS ownership checks and moved the only empty-selection write after all preflight refusals.
- Corrected §7 of the operator record to describe foreign-owner refusal, accepted-run empty ownership, 0700 output, and the dedicated-display limit.

## Fail-first Evidence

The exact command before and after the probe edit was `bash test/platform/worker_gone_probe_preflight_test.sh`. Each case asserted its scratch repository was the Git root and had no tracked `lib/`, `test/`, or `tool/` edits; the absolute path resolved to `/workspace/tool/uat/worker_gone_probe.sh`. The invalid `--at invalid-preflight-revision` forced a bounded preflight exit before any worktree, injection, or build.

| Case | Before fix: RED | After fix: GREEN |
| --- | --- | --- |
| newline-only | `rc=2`, wrong `not a commit` halt; bytes `3 → 0`; TARGETS `TARGETS,UTF8_STRING → absent` | `rc=2`, named clipboard-owner refusal; bytes `3 → 3`; TARGETS `TARGETS,UTF8_STRING → TARGETS,UTF8_STRING` |
| non-text-owner | `rc=2`, wrong `not a commit` halt; default payload `0` bytes; TARGETS `TARGETS,image/png → absent` | `rc=2`, named clipboard-owner refusal; default payload `0` bytes; TARGETS `TARGETS,image/png → TARGETS,image/png` |
| late-refusal | `rc=2`, invalid-revision halt after one xclip write | `rc=2`, invalid-revision halt with zero xclip writes and no owner afterward |

The pre-fix run reported `0/3 cases passed`; the post-fix run reported `3 passed`. Missing prerequisites, wrong initial ownership, and an unexpected dirty-tree/build route are test errors. The harness stores no clipboard payload in the probe's durable evidence directory.

## Verification

- `bash -n tool/uat/worker_gone_probe.sh test/platform/worker_gone_probe_preflight_test.sh` — passed.
- `bash test/platform/worker_gone_probe_preflight_test.sh` — three cases passed on dedicated Xvfb servers.
- The plan's §7 Python check — `operator record checked`.
- `git diff --check` — passed.
- Scoped file review found no daemon production changes, CI changes, or edits to prior plans, summaries, or verification reports. The 0700 permission statement and run-scoped daemon/clipboard teardown remain in place.

## Task Commits

1. **Task 1, fail-first oracle:** `601448b` — `test(01-25): expose clipboard ownership loss in live probe`.
2. **Task 1, corrected preflight:** `4a07300` — `fix(01-25): preserve foreign clipboard ownership in probe`.
3. **Task 1, harness prerequisite and teardown refinement:** `e6892d1` — `test(01-25): check harness prerequisites and quiet teardown`.
4. **Task 2, operator record:** `7a0001d` — `docs(01-25): explain probe clipboard ownership contract`.

## Decisions Made

- TARGETS exit status defines ownership. Reading a default target and checking its shell string is insufficient for newline-only or empty non-text selections.
- The second check narrows the race during preflight; the operator record recommends a dedicated display because another client can change a shared display afterward.

## Deviations from Plan

None. The harness and correction followed the planned scope and fail-first sequence.

## Issues Encountered

The normal command sandbox could not create a namespace (`bwrap`); the approved command path ran the Xvfb cases. No required tool was missing. A full workerGone bundle/capture run was outside this gap plan; the prior 01-21 observation remains the evidence for that path.

## Next Phase Readiness

The clipboard-safety gap is ready for phase re-verification. The separate CI merge-gate gap was accepted by project maintainer override on 2026-09-23; its measured 7/8 result and residual flakes remain disclosed, and this plan makes no green-gate claim.

## Self-Check: PASSED

The three scoped files exist, all task acceptance checks passed, the four task commits are present, and the red-to-green X11 evidence is recorded above.
