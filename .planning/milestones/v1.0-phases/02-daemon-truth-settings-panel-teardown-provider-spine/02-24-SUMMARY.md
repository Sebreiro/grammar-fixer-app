---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 24
subsystem: documentation
tags: [ledger, stories, append-only]
requires:
  - phase: 02-21
    provides: Phase 2 architecture and story currency
provides:
  - In-place deferred-work closure instructions in five completed stories and their story-source file
  - Repository-wide disposition of ledger-deletion search candidates
affects: [02-25, 02-26, LEDGER-01]
actuals:
  tokens: 6861
  tasks: 2
  commits: 2
commits: 2
plan_head_before: c97fabb3052e6052c2ec3b257f533b415f439c91
tech-stack:
  added: []
  patterns: [retain ledger heading, date status transition, cite evidence in resolution]
key-files:
  created: [.planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-24-SUMMARY.md]
  modified:
    - _bmad-output/specs/spec-hotkey-grammar-corrector/stories.yaml
    - _bmad-output/specs/spec-hotkey-grammar-corrector/stories/1-config-store-app-paths-and-system-ports.md
    - _bmad-output/specs/spec-hotkey-grammar-corrector/stories/2-drift-history-persistence.md
    - _bmad-output/specs/spec-hotkey-grammar-corrector/stories/3-controller-failure-contract.md
    - _bmad-output/specs/spec-hotkey-grammar-corrector/stories/4-composition-root-and-riverpod-wiring.md
    - _bmad-output/specs/spec-hotkey-grammar-corrector/stories/11-packaging-and-sidecar-provisioning.md
    - .planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-24-PLAN.md
key-decisions:
  - Retain each closed deferred-work heading and historical text; set status to done with a date and add a resolution citing evidence.
  - Treat completed reviews and old plan results as history while correcting live story and story-source instructions.
patterns-established:
  - Ledger closure is a status transition and evidence-bearing resolution in the existing entry.
requirements-completed: [LEDGER-01]
duration: 8min
completed: 2026-09-26
status: complete
---

# Phase 02 Plan 24: Append-only Ledger Instructions Summary

Five story contracts and the source story list now direct maintainers to retain closed deferred-work entries, date their `status: done` transition, and add a `resolution:` citing evidence. Historical reviews describing past deletions remain intact.

## Performance

- **Started:** 2026-09-26T09:41:56Z
- **Completed:** 2026-09-26T09:49:00Z
- **Tasks:** 2
- **Files modified:** 7
- **Measured task commits:** 2 from `c97fabb3052e6052c2ec3b257f533b415f439c91`; realized diff 27,445 characters / 4 = 6,861 tokens.

## Accomplishments

- Replaced active deletion requirements in the controller, composition, config, persistence, and packaging stories, including Tasks, Acceptance, supporting file lists, and packaging verification.
- Corrected six live deletion directions in `stories.yaml`, the additional authoring source found by the repository sweep. Changed its unresolved persistence item to collect evidence on the same open entry.
- Reviewed tracked and untracked repository instruction candidates; no remaining live direction to delete a closed deferred-work entry was found.

## Task Commits

1. **Task 1: Controller and composition story instructions** — `8f5c8f5` (`docs`).
2. **Task 2: Remaining stories and repository sweep** — `0816a9e` (`docs`).

## Verification

- `git diff HEAD --check`: passed before each task commit; no whitespace errors.
- Task 1 `rg -n 'status: done|resolution:'` on stories 3 and 4: passed at the corrected Tasks and Acceptance lines.
- Task 2 ran the plan's `rg --hidden --no-ignore -l -i -U` search over the working tree with the stated cache/build exclusions, then reviewed candidate context. The follow-up search retained only historical, prohibitive, or unrelated matches listed below. A separate search of `.claude` and `.codex` instruction content found only append-only prohibitions outside generic GSD tooling.
- `rg -n 'remove each entry|remove the entry|delete the .*entry|no longer contains|entries are gone'` over the five stories and `stories.yaml`: no matches after the edits.
- `git diff --diff-filter=D --name-only` over both task commits: no tracked-file deletions. No product SPEC, spine, test, gate, CI, runtime artifact, or deferred-work entry was changed.

## Repository Sweep: Candidate Paths and Dispositions

The initial sweep used the exact Task 2 expression across the working tree, including untracked `.claude` and `.codex` instructions. The list below records every matched path. A match alone is not a live direction: the expression also catches prohibitions, historical accounts, and deletion of unrelated code or data.

### Corrected active instructions

| Path | Disposition |
|---|---|
| `_bmad-output/specs/spec-hotkey-grammar-corrector/stories.yaml` | Six live story-authoring directions corrected; added to plan ownership before editing. No remaining Phase 2 plan claims this file. |
| `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/1-config-store-app-paths-and-system-ports.md` | Live Tasks and Acceptance corrected; historical completion record retained. |
| `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/2-drift-history-persistence.md` | Live Tasks and Acceptance corrected; historical EOL investigation retained. |
| `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/3-controller-failure-contract.md` | Live Tasks corrected and ledger Acceptance added; historical triage and reviews retained. |
| `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/4-composition-root-and-riverpod-wiring.md` | Live Tasks and Acceptance corrected; historical deletion record retained. |
| `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/11-packaging-and-sidecar-provisioning.md` | Live Code Map, Tasks, Acceptance, and Verification corrected; historical reviews retained. |

### Current guidance already aligned with append-only closure

| Path | Disposition |
|---|---|
| `.claude/CLAUDE.md` | Explicit append-only rule and prohibition on entry deletion. |
| `.claude/commands/process-backlog.md` | Directs status and resolution updates; explicitly forbids entry deletion. |
| `.planning/PROJECT.md` | States the append-only rule; other deletion wording concerns removed milestone scope. |
| `.planning/REQUIREMENTS.md` | LEDGER-01 asks to stop deletion instructions. |
| `.planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-SPEC.md` | R26 requires retained headings and in-place closure. |
| `.planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-24-PLAN.md` | Current plan forbids deleting entries; ownership expanded for `stories.yaml`. |
| `.planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-25-PLAN.md` | Next plan requires preserving headings and recording status/resolution. |
| `.planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-26-PLAN.md` | Next plan requires preserving headings and recording status/resolution. |
| `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/5-clipboard-and-panel-visibility-adapters.md` | Live Tasks already close in place; deletion references describe the earlier error. |
| `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/6-tray-adapter.md` | Live Tasks already close in place; deletion references describe the earlier error or unrelated files. |
| `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/9-correction-panel-ui.md` | Prohibits deletion and leaves closure to another owner. |
| `_bmad-output/implementation-artifacts/deferred-work.md` | Header states append-only discipline; deletion references are historical evidence within entries. |

The separately checked `.claude/skills/bmad-loop-sweep/deferred-work-format.md` also explicitly forbids deleting a completed entry; it was not returned by the exact 200-character sweep expression.

### Historical plans, records, and research; no current deletion instruction

| Path | Disposition |
|---|---|
| `.planning/ROADMAP.md` | Historical scope and packaging decisions; no deferred-work deletion directive. |
| `.planning/STATE.md` | Historical decisions and issue notes; no deferred-work deletion directive. |
| `.planning/WINDOWS.md` | Historical defect records and resolutions. |
| `.planning/research/STACK.md` | Research on package removal, not ledger entry removal. |
| `.planning/research/PITFALLS.md` | Research on history-data deletion and test evidence, not deferred-work entry deletion. |
| `.planning/phases/01-hotkey-truth/01-01-PLAN.md` | Completed Phase 1 plan, historical. |
| `.planning/phases/01-hotkey-truth/01-02-PLAN.md` | Completed Phase 1 plan, historical. |
| `.planning/phases/01-hotkey-truth/01-06-PLAN.md` | Completed Phase 1 plan, historical. |
| `.planning/phases/01-hotkey-truth/01-07-PLAN.md` | Completed Phase 1 plan, historical. |
| `.planning/phases/01-hotkey-truth/01-10-PLAN.md` | Completed Phase 1 plan, historical. |
| `.planning/phases/01-hotkey-truth/01-14-PLAN.md` | Completed Phase 1 plan, historical. |
| `.planning/phases/01-hotkey-truth/01-20-PLAN.md` | Completed Phase 1 plan, historical. |
| `.planning/phases/01-hotkey-truth/01-24-PLAN.md` | Completed Phase 1 plan, historical. |
| `.planning/phases/01-hotkey-truth/01-01-SUMMARY.md` | Completed Phase 1 result, historical. |
| `.planning/phases/01-hotkey-truth/01-10-SUMMARY.md` | Completed Phase 1 result, historical. |
| `.planning/phases/01-hotkey-truth/01-14-SUMMARY.md` | Completed Phase 1 result, historical. |
| `.planning/phases/01-hotkey-truth/01-VERIFICATION.md` | Completed Phase 1 verification record. |
| `.planning/phases/01-hotkey-truth/01-SECURITY.md` | Completed Phase 1 security record. |
| `.planning/phases/01-hotkey-truth/01-RESEARCH.md` | Historical implementation research. |
| `.planning/phases/01-hotkey-truth/01-PATTERNS.md` | Historical codebase map. |
| `_bmad-output/implementation-artifacts/sweep-triage-20260814.json` | Archived triage data, not a live instruction. |
| `_bmad-output/implementation-artifacts/spec-dw-2-spine-currency-refresh.md` | Historical review/implementation account and a prohibition on editing the ledger in that run. |
| `_bmad-output/implementation-artifacts/spec-dw-9-runtime-observation-checklists.md` | Historical review and desktop-entry removal observations, not ledger deletion. |
| `_bmad-output/implementation-artifacts/spec-dw-19-daemon-startup-and-abort-path.md` | Historical source and review notes, not ledger deletion. |
| `_bmad-output/implementation-artifacts/spec-dw-30-panel-session-reason-and-marker.md` | Historical source and review notes, not ledger deletion. |
| `_bmad-output/implementation-artifacts/spec-dw-31-panel-window-event-reconciliation.md` | Historical source and review notes, not ledger deletion. |
| `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-currency-check-2026-08-14.md` | Frozen review report describing package removal. |
| `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-rubric-walker-2026-08-14-ad12-premise.md` | Frozen review report, not a ledger instruction. |
| `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/reviews/review-rubric-walker-2026-08-14-amendments.md` | Frozen review report, not a ledger instruction. |

### Unrelated source or generic GSD capability tooling

| Path | Disposition |
|---|---|
| `pubspec.yaml` | Comment concerns removal of the `drift_flutter` package. |
| `lib/src/infrastructure/hotkey/hotkey_registrar.dart` | Source code concerns hotkey cleanup, not deferred-work entries. |
| `test/architecture/runtime_checklists_test.dart` | Source code concerns checklist step removal, not deferred-work entries. |
| `.codex/gsd-core/templates/README.md` | Generic GSD template guidance, not the project deferred-work ledger. |
| `.codex/gsd-core/workflows/explore.md` | Generic GSD workflow, not a deferred-work closure instruction. |
| `.claude/gsd-core/workflows/explore.md` | Untracked mirror of the generic GSD workflow. |
| `.codex/gsd-core/bin/lib/artifacts.cjs` | Generic GSD artifact handling. |
| `.codex/gsd-core/bin/lib/broken-windows.cjs` | Generic GSD broken-windows ledger. |
| `.codex/gsd-core/bin/lib/capability-command-router.cjs` | Generic capability ledger tooling. |
| `.codex/gsd-core/bin/lib/capability-ledger.cjs` | Generic capability ledger tooling. |
| `.codex/gsd-core/bin/lib/capability-lifecycle.cjs` | Generic capability ledger tooling. |
| `.codex/gsd-core/bin/lib/capability-loader.cjs` | Generic capability ledger tooling. |
| `.codex/gsd-core/bin/lib/capability-lock.cjs` | Generic capability ledger tooling. |
| `.codex/gsd-core/bin/lib/loop-resolver.cjs` | Generic GSD loop handling. |
| `.claude/gsd-core/bin/lib/artifacts.cjs` | Untracked mirror of generic GSD artifact handling. |
| `.claude/gsd-core/bin/lib/broken-windows.cjs` | Untracked mirror of generic GSD broken-windows ledger. |
| `.claude/gsd-core/bin/lib/capability-command-router.cjs` | Untracked mirror of generic capability ledger tooling. |
| `.claude/gsd-core/bin/lib/capability-ledger.cjs` | Untracked mirror of generic capability ledger tooling. |
| `.claude/gsd-core/bin/lib/capability-lifecycle.cjs` | Untracked mirror of generic capability ledger tooling. |
| `.claude/gsd-core/bin/lib/capability-loader.cjs` | Untracked mirror of generic capability ledger tooling. |
| `.claude/gsd-core/bin/lib/capability-lock.cjs` | Untracked mirror of generic capability ledger tooling. |
| `.claude/gsd-core/bin/lib/loop-resolver.cjs` | Untracked mirror of generic GSD loop handling. |

## Decisions Made

- Extended plan ownership to `stories.yaml` after confirming no remaining Phase 2 plan claims that path, then corrected its six live directives.
- Left review and triage accounts unchanged so they continue to record why earlier deletions happened.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Corrected the source story list.**
- **Found during:** Task 2 repository sweep.
- **Issue:** Six live authoring directions in `stories.yaml` could regenerate deletion instructions after the five story files were fixed.
- **Fix:** Expanded 02-24 file ownership and changed each to a dated in-place closure with an evidence-bearing resolution; unresolved work stays in the same open entry.
- **Files modified:** `_bmad-output/specs/spec-hotkey-grammar-corrector/stories.yaml`, `02-24-PLAN.md`.
- **Commit:** `0816a9e`.

## Known Stubs

None introduced. The only placeholder matches in modified files were unchanged historical story-4 descriptions of the original scaffold.

## Self-Check: PASSED

All seven modified task files exist, and both task commits are present. The source inspection found no remaining live deferred-work deletion directive.
