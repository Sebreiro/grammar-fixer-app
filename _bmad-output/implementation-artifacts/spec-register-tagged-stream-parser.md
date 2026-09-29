---
title: 'RegisterTaggedStreamParser with full unit tests'
type: 'feature'
created: '2026-08-06'
status: 'done'
review_loop_iteration: 0
baseline_commit: '88754ee70fc598e14458771f4ef0277f3e744ce7'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Claude Agent SDK sidecar (AD-19) forwards raw model text; nothing yet turns the `FORMAL:`/`CASUAL:`/`SHORTER:` tagged stream into the `CorrectionEvent`s that CAP-5's progressive rendering and CAP-4's three registers require.

**Approach:** Implement `RegisterTaggedStreamParser` (AD-16) as pure Dart on the daemon side of the sidecar boundary: text-chunk stream in, `SuggestionDelta` events plus exactly one terminal event out — unit-tested on plain strings with no process or Flutter binding (AGENTS.md §7).

## Boundaries & Constraints

**Always:**
- Pure Dart: imports only `dart:` core and `lib/src/domain/**` types. Lives in the infrastructure ring per the spine's Structural Seed.
- AD-3 stream discipline: zero or more `SuggestionDelta`, then exactly one `CorrectionCompleted` **or** `CorrectionFailed`, then close. Never throws across the boundary; no event after the terminal.
- `SuggestionDelta.textDelta` is an incremental fragment, never cumulative. Tag text and line terminators are never part of a delta.
- `CorrectionCompleted.suggestions` carries exactly one `Suggestion` per `SuggestionRegister` value, in enum declaration order, text trimmed — authoritative over accumulated deltas (AD-3).
- Tags are recognized only at the start of a line (or of the stream); chunks may split anywhere, including mid-tag, so held-back text must never leak into deltas nor be lost.
- Format violations terminate with `CorrectionFailed(malformedResponse, message)`; the message names what was violated. The parser emits **only** `malformedResponse` for format problems — other kinds belong to the adapter (AD-15).
- Test names cite CAP-4 / CAP-5 and read as behaviour (AGENTS.md §7).

**Ask First:**
- Any change to files under `lib/src/domain/**` (AD-2 declarations are fixed).
- Tolerating model preamble before the first tag instead of failing (relaxes the matrix below).

**Never:**
- No process spawning, NDJSON decoding, or sidecar protocol handling — that is the adapter's job (AD-19); the parser sees only decoded text chunks.
- No retry policy, no prompt assembly, no persistence.
- No leniency for out-of-order or repeated tags: `FORMAL → CASUAL → SHORTER` exactly once each, in that order (AD-16).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path, one chunk (CAP-4) | `"FORMAL: a\nCASUAL: b\nSHORTER: c"` | Deltas for each register, then `CorrectionCompleted` with 3 suggestions in enum order | N/A |
| Tag split mid-word across chunks (CAP-5) | `"FORM"`, `"AL: Hel"`, `"lo\nCASU"`, `"AL: ..."` … | Same events as unsplit input; `"CASU"` after a newline is held, never emitted as a formal delta | N/A |
| Register missing | Stream ends; `SHORTER:` never appeared | No `CorrectionCompleted` | `malformedResponse` naming the missing register |
| Extra / out-of-order / repeated tag | Any non-whitespace line where it isn't the next expected tag (incl. a fourth tag after `SHORTER:`) | Terminal failure immediately on detection | `malformedResponse` |
| Empty stream | Zero chunks, or whitespace only | No deltas | `malformedResponse` |
| Text before first tag | Non-whitespace before `FORMAL:` | Fail as soon as the text can no longer be a tag prefix | `malformedResponse` |
| Empty register text | `"FORMAL:\n…"` | Valid: empty-string suggestion for that register | N/A |
| Input stream errors mid-parse | Source stream emits an error | Terminal `CorrectionFailed(providerError)`; never a thrown error | Sole non-format case: the fault is transport |
| Cancellation (AD-4) | Subscription cancelled mid-stream | Input subscription cancelled; no further events | N/A |

</frozen-after-approval>

## Code Map

- `lib/src/domain/correction/correction_event.dart` — event types + `CorrectionFailureKind` (AD-2, read-only).
- `lib/src/domain/correction/suggestion.dart`, `suggestion_register.dart` — `Suggestion`, `SuggestionRegister` enum order (read-only).
- `lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart` — **new**; the seed reserves exactly this path.
- `test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart` — **new**; mirrors the lib path.
- `test/architecture/ad1_import_rule_test.dart` — existing gate; stays green (parser is outside `domain/`).

## Tasks & Acceptance

**Execution:**
- [x] `lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart` — new class exposing `Stream<CorrectionEvent> parse(Stream<String> textChunks)`; single-subscription output, all parse state local to the call (stateless object, reusable across corrections) — implements the whole matrix above.
- [x] `test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart` — unit tests covering every matrix row plus: all three registers in one chunk; interleaved multi-chunk register text; trailing newline after `SHORTER:` text tolerated. Plain `package:test`, no Flutter binding.

**Acceptance Criteria:**
- Given any chunking of the same text, when parsed, then the terminal event is identical and concatenated deltas per register match the unsplit run.
- Given a well-formed three-register response, when the stream closes, then `CorrectionCompleted.suggestions` maps `formal, casual, shorter` in enum order with trimmed text.
- Given any malformed input from the matrix, when detected, then exactly one `CorrectionFailed(malformedResponse)` ends the stream and no event follows it.
- Given the new files, when `dart test` runs without a Flutter binding, then all tests (including the AD-1 gate) pass.

## Spec Change Log

## Design Notes

- Core state machine is synchronous and pure (`chunk in → events out`), wrapped by a thin `async*` (AGENTS.md §2: decide pure, act thin). Within a register's line, text flushes as deltas immediately; after a newline, text is held only while it is still a prefix of the next expected tag, then either switches register or fails fast.
- Leading whitespace immediately after a tag's colon is skipped, not emitted as a delta; empty deltas are never emitted. `CorrectionCompleted` is authoritative (AD-3), so delta-level whitespace need not be byte-perfect.

## Verification

**Commands:**
- `export PATH="$PATH:/home/vscode/flutter/bin" && dart analyze` — expected: no issues.
- `export PATH="$PATH:/home/vscode/flutter/bin" && dart test` — expected: all tests pass, new suite included, no Flutter binding required.

## Suggested Review Order

**Stream contract (AD-3/AD-4 plumbing)**

- Entry point: the whole public surface — stateless object, one `parse()` per correction
  [`register_tagged_stream_parser.dart:19`](../../lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart#L19)

- The single `emit` funnel: terminal cancels input first, so nothing can follow it
  [`register_tagged_stream_parser.dart:30`](../../lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart#L30)

- `onDone` guard + post-`listen` re-check: hardening against sync-delivery inputs (review finding)
  [`register_tagged_stream_parser.dart:59`](../../lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart#L59)

- Pause/resume/cancel wired through to the input subscription (review finding)
  [`register_tagged_stream_parser.dart:78`](../../lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart#L78)

**Parse state machine (pure, synchronous)**

- Session state: per-register buffers, phase, and the held tag prefix that never leaks
  [`register_tagged_stream_parser.dart:110`](../../lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart#L110)

- The subtlest code: hold-while-prefix tag matching — one mechanism yields all fail-fast cases
  [`register_tagged_stream_parser.dart:169`](../../lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart#L169)

- Register-line streaming: post-colon whitespace skip, per-chunk deltas, terminator handling
  [`register_tagged_stream_parser.dart:206`](../../lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart#L206)

- End-of-stream verdict: trailing-newline tolerance vs missing-register failure
  [`register_tagged_stream_parser.dart:154`](../../lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart#L154)

- `CorrectionCompleted` assembly: trimmed, enum order, authoritative over deltas
  [`register_tagged_stream_parser.dart:288`](../../lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart#L288)

**Tests (CAP-4 / CAP-5)**

- Chunking-invariance fuzz: same events for every splitting, well-formed and malformed
  [`register_tagged_stream_parser_test.dart:124`](../../test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart#L124)

- Malformed matrix rows: fail-fast, message names the violated tag
  [`register_tagged_stream_parser_test.dart:235`](../../test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart#L235)

- Stream discipline: single-subscription, post-terminal silence, cancellation, pause propagation
  [`register_tagged_stream_parser_test.dart:313`](../../test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart#L313)

- Well-formed rows incl. CRLF, trim pinning, whitespace tolerance (mutation-review findings)
  [`register_tagged_stream_parser_test.dart:17`](../../test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart#L17)
