# GSD Workflow: Idea → Questions → Unattended Build

How to take an idea through GSD Core (`@opengsd/gsd-core`) so that the human
input happens up front and the implementation runs without anyone watching.

The pipeline is:

```
idea ──► /gsd-explore or /gsd-new-milestone ──► phases in ROADMAP.md
      ──► /gsd-spec-phase N  (WHAT)  ──► SPEC.md
      ──► /gsd-discuss-phase N (HOW) ──► CONTEXT.md
      ──► /gsd-autonomous            ──► plan → execute → review → verify, per phase
```

Everything lives under `.planning/`. Run `/gsd-next` at any time to see where
you are and what the next sensible command is.

---

## 1. Create and brainstorm the idea, split it into tasks

### Small or medium idea inside the current milestone

```
/gsd-explore <describe your idea in a sentence or two>
```

- Socratic conversation, one question at a time, 2–5 exchanges.
- Offers a quick research pass when a factual question comes up.
- At the end it proposes what to capture. Choose **New phase** to queue it as
  work, **Requirement** to add REQ-IDs to `REQUIREMENTS.md`, or **Todo** /
  **Seed** / **Note** for things that are not ready to build.
- Nothing is written until you pick outputs.

Urgent work that must land between existing phases:

```
/gsd-phase --insert <after-phase-number> <description>
```

This creates a decimal phase (for example 2.1) that autonomous mode picks up
on its next pass through the roadmap.

### Large idea, or a fresh batch of features

```
/gsd-new-milestone "<milestone name>"
```

- Asks "what do you want to build next" and probes until the scope is clear.
- Optionally spawns four parallel researchers on the domain.
- Scopes requirements into v1 / v2 / out-of-scope.
- A roadmapper splits the work into phases with success criteria.
- You approve the roadmap once. That approval is the last mandatory human step
  before the unattended run.

Do not start a new milestone while one is in progress; finish or archive the
current one first (`/gsd-complete-milestone`).

### One-off task, no roadmap entry

```
/gsd-quick --full "<task>"
```

Plans, executes, reviews and verifies a single task with atomic commits and
STATE.md tracking, without touching the roadmap. Drop `--full` when you know
exactly what to do and want the shortest path.

---

## 2. Ask the questions once, up front

Two commands, two different questions. Run them in this order for each phase
you want the machine to build later.

### `/gsd-spec-phase N` — WHAT must this phase deliver?

```
/gsd-spec-phase 3
```

- Interview of up to six rounds.
- Scores ambiguity after each round on four dimensions: goal, boundary,
  constraints, acceptance criteria.
- Stops when ambiguity ≤ 0.20 and every dimension meets its minimum.
- Writes `.planning/phases/NN-name/NN-SPEC.md` with falsifiable requirements.
- `--auto` skips the interview when the roadmap is already clear enough.

Use it when the phase goal is vague, contested, or missing success criteria.

### `/gsd-discuss-phase N` — HOW should this phase work?

```
/gsd-discuss-phase 3
/gsd-discuss-phase 3 --batch      # 2–5 related questions at a time
/gsd-discuss-phase 3 --auto       # Claude picks the recommended answer everywhere
```

- Finds the gray areas the planner would otherwise guess at and asks you to
  decide each one.
- Picks up an existing SPEC.md automatically, so it starts from settled scope.
- Writes `.planning/phases/NN-name/NN-CONTEXT.md` with locked decisions, what
  is left to Claude's discretion, and deferred ideas. The planner reads this
  file directly.

Use it when scope is clear but several reasonable implementations exist.

### Which one matters for hands-off runs

`/gsd-autonomous` checks only for CONTEXT.md. A phase with CONTEXT.md skips
the per-phase discuss pause. A phase with only SPEC.md still pauses. So:

- Spend your interactive time on `/gsd-spec-phase`. Getting the "what" right is
  what stops an unattended run from building the wrong thing.
- Then either run `/gsd-discuss-phase N` yourself, or let the runner
  auto-answer it (see step 3). Discuss decisions are safe to delegate: the
  recommended defaults follow codebase conventions, and the plan-checker and
  verifier catch most misjudgments.

Ask business questions, not technical ones, when you are in discuss-phase:
frame each gray area as observable product behaviour.

---

## 3. Run phases without a human in the loop

### One-time config

Edit `.planning/config.json`:

| Key | Value | Effect |
|---|---|---|
| `mode` | `"yolo"` | auto-approves confirmations instead of asking |
| `workflow.skip_discuss` | `true` | no per-phase discuss pause; roadmap goal becomes the spec when CONTEXT.md is missing |
| `workflow.auto_advance` | `true` | manual plan/execute commands chain forward on their own |
| `workflow.human_verify_mode` | `"end-of-phase"` | human checks are batched into a UAT file instead of halting mid-plan |

Leave `skip_discuss` at `false` if you prefer to run `/gsd-discuss-phase` by
hand for every queued phase before launching; either way removes the pause.

### Launch

```
/gsd-autonomous                 # every remaining phase in the milestone
/gsd-autonomous --only 3        # one phase
/gsd-autonomous --from 3 --to 5 # a range
/gsd-autonomous --interactive   # discuss inline with you, plan+execute unattended
```

Per phase the runner does: discuss (or skip), plan with plan-checker, execute
with verifier, code review plus automatic fixes. It re-reads the roadmap after
each phase so inserted phases are picked up. When every phase is done it runs
the milestone audit, completion and cleanup.

### What still stops the run

| Stop | Why | What to do |
|---|---|---|
| Discuss prompt | no CONTEXT.md and `skip_discuss` is false | pre-run discuss-phase, or set `skip_discuss: true` |
| "Validate now or continue?" | verifier needs a human check | pick continue; run `/gsd-verify-work N` later |
| "Replan or continue?" | verifier found gaps | pick fix to replan automatically |
| Blocker menu: fix / skip / stop | a step produced no output or failed | fix and retry; stops after 3 failures |
| `blocking-human` checkpoint | irreversible decision, missing secret, unmet precondition | cannot be bypassed in any mode; answer it |
| Reversibility gate | planner flagged a one-way-door decision | pass `--no-reversibility-gates` to plan-phase, or answer it |

### Resume and review afterwards

```
/gsd-next                       # where am I, what is next
/gsd-autonomous --from N        # resume after a stop
/gsd-verify-work N              # walk through the batched human checks for a phase
/gsd-progress                   # progress report and routing
```

---

## Project-specific notes

- Success criteria in this roadmap deliberately name human gates (AD-9
  accessor, packaging format, `CorrectionFailureKind`). Those become
  `blocking-human` checkpoints and will stop an unattended run. That is
  correct behaviour, not a bug.
- `test_command` in `.planning/config.json` already excludes `live`-tagged
  tests. Keep it that way in unattended sessions: the live sidecar test spawns
  a nested Claude session that kills the outer one.
- Headless spawned sessions hang on the bypass-permissions dialog unless the
  skip setting is set in the Claude Code config.
- Full command reference: `/gsd-help --full`. One topic: `/gsd-help autonomous`.
