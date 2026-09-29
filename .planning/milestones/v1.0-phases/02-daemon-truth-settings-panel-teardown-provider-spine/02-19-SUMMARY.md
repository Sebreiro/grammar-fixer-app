---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 19
subsystem: contract-reconciliation
tags: [bmad, contracts, panel, clipboard, provenance]
requires:
  - phase: 02-04
    provides: panel and controller behavior
  - phase: 02-12
    provides: panel event reconciliation
provides:
  - Human-approved controller matrix error handling aligned with story 3
  - CAP-2 success re-derived from the append-only BMAD decision log
  - Story 5 disposition of DW-32 and DW-33 against shipped panel behavior
  - Checklist policy disposition with native claims still unobserved
  - Append-only CAP-2 decision and source proposal
affects: [ARCH-01, PANEL-09, PANEL-11, PANEL-17]
actuals:
  tokens: 4032
  tasks: 2
  commits: 10
commits: 10
plan_head_before: 7708c99c0f7a296882daf443c5c5c17838707af7
tech-stack:
  added: []
  patterns: [frozen-intent disposition outside intent block, BMAD memlog decision of record]
key-files:
  created:
    - .planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-19-BMAD-UPDATE-PROPOSAL.md
  modified:
    - _bmad-output/specs/spec-hotkey-grammar-corrector/.memlog.md
    - _bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md
    - _bmad-output/implementation-artifacts/spec-application-layer-controllers.md
    - _bmad-output/specs/spec-hotkey-grammar-corrector/stories/5-clipboard-and-panel-visibility-adapters.md
    - _bmad-output/implementation-artifacts/spec-dw-9-runtime-observation-checklists.md
key-decisions:
  - Prior checklist renumbering restrictions were scoped to their sweep bundles and do not permanently exempt native claims.
  - CAP-2 derivation must describe fresh seeding only after dismissal; an iconify or focus-loss return keeps the session.
requirements-completed: [ARCH-01, PANEL-09, PANEL-11]
requirements-pending: [PANEL-17]
duration: 18min plus 2026-09-26 continuation
completed: 2026-09-26
status: complete
---

# Phase 02 Plan 19: Contract Reconciliation Summary

**The approved controller error contract and CAP-2 success clause now describe the shipped daemon, alongside the panel-intent and checklist dispositions.**

## Accomplishments

- Appended a disposition outside story 5's frozen intent block. It cites `WindowManagerPanelVisibility._onBlur` and `_releaseDeferredBlur`: a blur during a second show is deferred, and a blur without preceding focus does not dismiss the panel. The old “implemented exactly as written” claim is explicitly historical for DW-32/DW-33.
- Appended a checklist disposition that withdraws the standing interpretation of the renumbering bans in the DW-114 and DW-31 sweep records. DW-12 and DW-32/DW-33 remain unobserved on a native desktop, and no checklist step, test, gate, CI rule, or runtime observation was added.
- Appended the CAP-2 decision through the local `memlog.py append` command and recorded a source update proposal. `correction_controller.dart` and its CAP-2 rows support fresh clipboard seeding after dismissal, session preservation after iconify or focus loss, and a usable empty editor after absent or failed clipboard reads.
- With the owner's explicit frozen-block renegotiation, Codex ran the local `bmad-quick-dev` setup and re-derived the matrix's 13 Error Handling cells from story 3. The installed `bmad-create-story` route only creates stories, so its plan reference could not update this completed quick-dev artifact. The first three columns, row order, and CAP/AD references remain byte-identical. The artifact's Spec Change Log records the owner approval, source, prior wording recoverable in git, and the narrow scope.
- Codex ran the local `bmad-spec` update operation against the existing append-only decision. Only CAP-2's success clause changed in generated `SPEC.md`; all other content, capability IDs, and companions remain byte-identical. The required coherence and preservation verdicts were appended through `memlog.py`.

## Task Commits

1. **Task 2: Record panel-intent and checklist dispositions** — `b57e662` (`docs`). The commit also preserved Task 1's local memlog decision and blocked-generator proposal.
2. **Task 1: Reconcile the 13 controller rows and regenerate CAP-2** — `2892226` (`docs`). This is the approved local Codex derivation, not an external Claude run.

The frontmatter `commits: 10` is the measured `7708c99..2892226` range required by the GSD ledger. This shared-root range includes unrelated 02-20 and architecture-proposal commits while 02-19 was halted; the two commits above are the task commits for this plan. It also includes three 02-19 blocker/summary metadata commits.

## Verification

- `git diff --check` passed for the changed documentation before commit.
- `rg` located DW-32, DW-33, and unobserved labels in both dispositions.
- Source inspection confirmed the panel's `_onBlur` and `_releaseDeferredBlur` paths and the correction controller's seeding paths. This was source verification, not a native runtime observation.
- A local structural comparison confirmed 13/13 matrix scenario/input/output triples unchanged and 13/13 Error Handling cells equal to story 3's Part A. A separate comparison confirmed that CAP-2's success sentence is the only SPEC change, with all CAP IDs and companions preserved.
- `git diff --check` and the plan's `rg` probe passed. `dart analyze --fatal-infos` reported no issues. Existing Dart tests passed (982, 2 skipped) and existing Flutter tests passed (165, 7 skipped). No test, gate, CI rule, or native runtime observation was added.

## Resolved Generator Blocker

The controller source matrix had 12 `N/A` Error Handling cells inside `<frozen-after-approval>`. Story 3's 13 corresponding rows are at `stories/3-controller-failure-contract.md:63-75`. The product `SPEC.md` said CAP-2 always opened pre-filled, while the shipped controller seeds a new session only after dismissal. This is now reconciled by the owner's explicit approval of the proposed frozen-block revision and Codex's local BMAD derivation.

An authenticated `claude -p --bare` invocation of `bmad-create-story` with `Read,Edit,Write,Bash` was rejected by automatic approval review. The stated reason was that it could export private project documentation and provenance to an external SaaS destination while granting write access; the local task authorization did not authorize that external execution. No alternate external invocation was attempted. The frozen source and generated SPEC remain blocked until an approved BMAD generator environment is available.

### Authorized generator retry (2026-09-24)

The user subsequently approved the authenticated external BMAD run, including project-document egress and Read/Edit/Write/Bash access. The retry used the same controller-source scope and passed the root pin before each CLI attempt:

1. `timeout 180 claude -p --bare --allowedTools 'Read,Edit,Write,Bash'` with the `/bmad-create-story` prompt returned `Unknown command: /bmad-create-story` (exit 0, with no edits). An earlier argument-form attempt returned `Input must be provided either through stdin or as a prompt argument when using --print` (exit 1, with no edits).
2. The installed `bmad-create-story/SKILL.md` was named directly in the prompt to invoke its workflow. `timeout 180 claude -p --bare --allowedTools 'Read,Edit,Write,Bash' -- '<direct SKILL.md update prompt>'` returned `Not logged in · Please run /login` (exit 1); bare mode cannot use the existing OAuth login.
3. With the same scoped direct skill prompt and existing OAuth login, `timeout 180 claude -p --allowedTools 'Read,Edit,Write,Bash' -- '<direct SKILL.md update prompt>'` returned `Your organization has disabled Claude subscription access for Claude Code · Use an Anthropic API key instead, or ask your admin to enable access` (exit 1). This is an authentication/organization gate, not a second automatic approval rejection.

Those external attempts reached no edit. On 2026-09-26 the user corrected the route to Codex running the installed local BMAD instructions. Codex did so without an Anthropic API key or external CLI. The controller matrix and product SPEC are now updated. The architecture spine remains for plan 02-21.

## Deviations from Plan

- The plan named `bmad-create-story` as the controller update path, but that installed skill is creation-only and this artifact is owned by `bmad-quick-dev`. After explicit owner renegotiation, Codex used the local owning frozen-block protocol and recorded the exception in the Spec Change Log.
- Task 2 was completed independently. Historical review text was preserved, with appended dispositions superseding stale interpretations.

## Deferred Issues

- PANEL-17's CAP-2 half is complete here; its AD-8/AD-18 architecture-spine snippets remain owned by 02-21, so the requirement stays pending until that plan completes.
- DW-12 and DW-32/DW-33 native behavior remains unobserved. This plan did not schedule runtime observation.

## Self-Check: PASSED

- All five named source artifacts exist; commits `b57e662` and `2892226` are present.
- The approved controller matrix and generated CAP-2 clause pass the preservation checks. This plan has `status: complete`; PANEL-17 stays pending for its separate architecture-spine half.
