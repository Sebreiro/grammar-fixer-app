---
description: Work the deferred-work backlog from the 2026-08-14 sweep triage — close what is resolved, ask the human every open question, then build the bundles.
---

# Process the deferred-work backlog

You are working through the deferred-work ledger using a triage partition that
has already been produced and verified against the code. **Do not re-run
triage** and do not invoke `bmad-loop`.

## Inputs

- Partition: `_bmad-output/implementation-artifacts/sweep-triage-20260814.json`
- Ledger: `_bmad-output/implementation-artifacts/deferred-work.md`
- Project rules: `AGENTS.md` — read it before writing any code.

The partition covers all 89 open entries exactly once:
20 bundles (50 entries) · 24 decisions · 10 skip · 5 already resolved · 0 blocked.

## The prime directive

**Ask the human about every uncertainty. Never guess a product decision.**

This backlog is full of genuine contract questions, not just mechanics. When
anything is ambiguous — which behaviour is wanted, whether a frozen spec block
may be renegotiated, how far a fix should reach — stop and ask with
`AskUserQuestion`, giving concrete options and your recommendation. It is
always better to ask than to invent an answer. Batch related questions so the
human answers 2–4 at a time rather than one per turn.

Never write evidence you have not verified. A file:line or a commit hash, or
nothing.

## Phase 1 — close the free 15 (no code, no questions)

For each entry in `already_resolved` and `skip`:

1. Re-verify the recorded evidence still holds by reading the cited file:line.
   If it does not, say so and move the entry to a question for the human
   instead of closing it.
2. Set the ledger entry's `status:` to `done 2026-08-14` and add a
   `resolution:` line carrying the partition's evidence/reason.
3. Never delete an entry. The ledger is append-only; closing means flipping
   `status:` and adding `resolution:`.

Commit as `docs(deferred-work): close 15 entries verified resolved or superseded`.

## Phase 2 — the 24 decisions

Work through `decisions` in the partition. Each carries a `question`,
`context`, and 2–4 `options`, each option with a `label`, an `effect`
(`build` / `close` / `keep-open`) and an `intent`.

For each batch of 2–4:

1. Present the question with its options via `AskUserQuestion`, including the
   context that makes the trade-off legible and your own recommendation.
2. Record the answer in the ledger on that entry, directly after `status:`:
   `decision: 2026-08-14 <chosen label> — <detail>`
3. Apply the effect:
   - `close` → `status: done 2026-08-14` plus a `resolution:` line.
   - `keep-open` → leave `status: open`; the decision line is the record.
   - `build` → leave `status: open` and collect the option's `intent` into a
     build list for Phase 3.

Several decisions gate bundle work, so finish this phase before Phase 3.
Commit the decisions as one commit.

## Phase 3 — the 20 bundles

Order: cheapest first so the human sees the shape early. Suggested start —
`config-warning-error-typing` (1 entry), `clipboard-absence-not-failure` (1),
`explicit-fresh-session-marker` (1), `copy-success-affordance` (1). Leave
`ffi-keybinder-hotkey-registrar` (a full dart:ffi rewrite of the X11 hotkey
path) and `spine-currency-refresh` (7 entries) until the human has seen a few
land.

For each bundle, **one bundle per fresh context**:

1. Invoke `bmad-quick-dev` with the bundle's `intent` verbatim as the request.
   The intent already carries verified file:line evidence — do not re-derive it.
2. Gate before committing:
   ```sh
   export PATH="$PATH:/home/vscode/flutter/bin"
   flutter analyze
   flutter test
   ```
   Both must be green. Report failures verbatim; never describe a red gate as
   passing.
3. Close that bundle's `dw_ids` in the ledger — `status: done 2026-08-14` plus
   a `resolution:` line naming what was built.
4. Commit the bundle on its own: `fix(<area>): <bundle name>` with the DW ids
   in the body.
5. Report progress and stop for the human's go-ahead before the next bundle.

## Rules

- One commit per phase or per bundle. Never one giant commit.
- Never mark an entry done without a `resolution:` line.
- Never edit `<frozen-after-approval>` spec blocks without an explicit human
  answer authorising it — that is always a question, never an assumption.
- If a bundle turns out to need a decision nobody has made, stop and ask.
- Do not run `bmad-loop`; the CLI's own pending-decision list will go stale as
  you record answers in the ledger, and that is expected.
