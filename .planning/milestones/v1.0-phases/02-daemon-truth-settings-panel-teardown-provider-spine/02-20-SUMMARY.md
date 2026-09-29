---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 20
subsystem: architecture-documentation
tags: [hotkey, ad-9, ratification, architecture-spine, provenance]
requires:
  - phase: 01-hotkey-truth
    provides: Shipped HotkeyBinding defensive copy and Phase 1 AD-9/AD-11 hand-off ledger entries
  - phase: 02-daemon-truth-settings-panel-teardown-provider-spine
    provides: D-19 owner's 2026-09-24 ratification in 02-CONTEXT.md
provides:
  - Source-grounded D-19 decision and exact HotkeyBinding constructor replacement for the AD-9 generator
  - Complete Phase 1 AD-9 and AD-11 hand-off list for plan 02-21
affects: [02-21, ARCH-06]
actuals:
  tokens: 1319
  tasks: 2
  commits: 2
commits: 2
plan_head_before: 9257f9aee31b754b4f79ef777800bbb19f29b3a3
tech-stack:
  added: []
  patterns: [owner decision provenance retained across generated architecture updates]
key-files:
  created:
    - .planning/phases/02-daemon-truth-settings-panel-teardown-provider-spine/02-AD9-RATIFICATION.md
  modified: []
key-decisions:
  - D-19 on 2026-09-24 is the owner's ratification of the shipped non-const defensive-copy constructor; the 2026-09-02 orchestrator-only selection remains separately attributed.
  - Retain the existing effective-binding fields and carry the localized description through the already-ratified HotkeyStatus addition.
requirements-completed: []
requirements-pending-global: [ARCH-06]
coverage:
  - id: AD9-ratification-input
    description: The AD-9 generator receives the exact D-19-ratified constructor and its earlier orchestrator-only provenance.
    requirement: ARCH-06
    verification:
      - kind: other
        ref: rg checks for D-19, HotkeyBinding, orchestrator, human, and AD-9 in 02-AD9-RATIFICATION.md; source and spine comparison
        status: pass
    human_judgment: false
  - id: AD9-phase1-handoff
    description: The generator input lists current status, unavailable cause, effective binding and description, bind/change precedence, and conditional portal registration.
    requirement: ARCH-06
    verification:
      - kind: other
        ref: rg checks for D-19, current, cause, effective, and portal in 02-AD9-RATIFICATION.md; Phase 1 ledger comparison
        status: pass
    human_judgment: false
duration: 4min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 20: AD-9 Ratification Input Summary

**D-19 now supplies the owner authority for the shipped non-`const` `HotkeyBinding` defensive copy, and plan 02-21 has a source-grounded list of Phase 1 AD-9/AD-11 corrections to regenerate.**

## Performance

- **Started:** 2026-09-24T19:19:24Z
- **Completed:** 2026-09-24T19:23:00Z
- **Duration:** 4 minutes
- **Tasks:** 2
- **Files created:** 1 decision record

## Accomplishments

- Recorded D-19's 2026-09-24 owner ratification separately from plan 01-09's 2026-09-02 orchestrator-only `defensive-copy` answer. The record specifies the shipped initializer and the frozen AD-9 `const` line it replaces, while preserving AD-9's set equality rule and the honest finding that this was hardening rather than a live bug fix.
- Carried forward the Phase 1 ledger's operative 01-10 correction: synchronous `current` status, required unavailability cause, localized description without inventing a Wayland effective combination, bind/change precedence, and AD-11's conditional portal registration. The earlier prediction-form ledger entry remains cited with its provenance.
- Left the architecture spine, implementation, SPEC, and shared configuration unchanged. Plan 02-21 owns regeneration; ARCH-06 is still pending globally.

## Task Commits

1. **Task 1: Prepare the exact AD-9 ratification record** — `0e2a4fe` (`docs`).
2. **Task 2: Carry all Phase 1 AD-9 hand-off edits forward** — `0ac36fa` (`docs`).

## Verification

- Both plan `<verify>` `rg` checks passed, including every required D-19 and hand-off term.
- Compared `hotkey_binding.dart` against the frozen AD-9 constructor and compared the hand-off list against the Phase 1 ledger entries sourced from `01-01-PLAN.md` and `01-10-PLAN.md`.
- `git diff --check` passed before each task commit. This documentation-only plan changed no executable code; no Dart test was needed.

## Deviations from Plan

None. The record follows D-19 and does not claim ARCH-06 complete before generator plan 02-21 runs.

## Known Stubs

None in the created file.

## Threat Flags

None. The decision record introduces no endpoint, authentication path, file access, or schema change.

## Next Phase Readiness

Plan 02-21 can consume `02-AD9-RATIFICATION.md` to regenerate and reconcile the frozen spine. The decision is ratified; the regeneration and global ARCH-06 closure remain outstanding. Plan 02-19's external BMAD generator gate is independent and remains halted.

## Self-Check: PASSED

The ratification record and this summary exist; both task commits are present; the measured task-commit count from `plan_head_before` is two; the two plan verifications passed.
