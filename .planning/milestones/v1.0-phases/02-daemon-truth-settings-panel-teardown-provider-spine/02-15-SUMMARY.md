---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 15
subsystem: correction-provider-transport
tags: [dart, http, sse, provider, privacy, cancellation]
requires:
  - phase: 02-14
    provides: cancellation and daemon teardown ownership
  - phase: 02-04
    provides: safe config diagnostics and the CONFIG-01 handoff
provides:
  - One shared register-tagged parser with the shipped Claude import path retained
  - A bounded per-call OpenAI-compatible Chat Completions SSE transport
  - Safe Claude sidecar logging that closes CONFIG-01
affects: [02-16, 02-17, 02-18, PROVIDER-02, CONFIG-01]
actuals:
  tokens: 12507
  tasks: 2
  commits: 4
commits: 4
plan_head_before: 5f2cb065aeb7affbe44e1a954756f296b7a0866d
tech-stack:
  added: []
  patterns: [per-call HttpClient ownership, complete-frame SSE decoding, shared tagged parser]
key-files:
  created:
    - lib/src/infrastructure/correction/shared/register_tagged_stream_parser.dart
    - lib/src/infrastructure/correction/openai_compatible/chat_completion_sse_decoder.dart
    - lib/src/infrastructure/correction/openai_compatible/openai_compatible_correction_provider.dart
  modified:
    - lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart
    - lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart
    - test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart
    - test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart
key-decisions:
  - Use one stateless tagged parser implementation for both adapters, retaining the old Claude import path as an export.
  - Require a stop finish reason and DONE frame before the HTTP stream closes its parser input.
  - Permit plaintext HTTP only for an explicitly configured loopback host; require HTTPS for remote hosts.
requirements-completed: [PROVIDER-02]
requirements-closed-additionally: [CONFIG-01]
requirements-pending-global: [PROVIDER-02]
coverage:
  - id: D1
    description: Claude and the new adapter share one tagged parser implementation with the existing suggestion shape.
    requirement: PROVIDER-02
    verification:
      - kind: integration
        ref: dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart
        status: pass
    human_judgment: false
  - id: D2
    description: A configured Chat Completions request owns its client, parser, deadline, bounded SSE decoding, and cancellation.
    requirement: PROVIDER-02
    verification:
      - kind: other
        ref: Source inspection of openai_compatible_correction_provider.dart and chat_completion_sse_decoder.dart; dart analyze --fatal-infos
        status: pass
    human_judgment: true
    rationale: Neither OpenAI nor local Ollama was available as a verified live endpoint; provider selection is wired in plan 02-18.
  - id: D3
    description: Claude sidecar stderr and caught error values cannot enter logger messages or context; CONFIG-01 is closed.
    requirement: CONFIG-01
    verification:
      - kind: integration
        ref: dart test --exclude-tags=live test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart test/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser_test.dart
        status: pass
      - kind: other
        ref: Global lib/ logger-context source scan
        status: pass
    human_judgment: false
duration: 17min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 15: Shared Parser and Chat Completions Transport Summary

**A fresh HTTP correction run now decodes bounded Chat Completions SSE into the shared register parser, while Claude sidecar logs disclose only safe statuses and error types.**

## Performance

- **Started:** 2026-09-24T17:35:45Z
- **Completed:** 2026-09-24T17:52:36Z
- **Duration:** 17 minutes
- **Tasks:** 2
- **Files changed:** 7

## Accomplishments

- Moved `RegisterTaggedStreamParser` to one shared source. The Claude path exports it for existing imports, and the Claude adapter imports the shared source directly.
- Added a per-correction `HttpClient`, request, timeout, SSE decoder, and parser session. The adapter sends only the current text and preset prompt/model to the explicit configured endpoint. It disables redirects, retains Dart TLS verification, rejects remote plaintext HTTP, bounds request/body/frame sizes, requires `finish_reason: stop` plus `[DONE]` and the tagged `END`, and aborts transport on cancellation.
- Removed raw Claude stderr and caught error values from logger output. The repository-wide logger scan found remaining caught errors represented by `runtimeType` rather than exception text. CONFIG-01 and WINDOWS entries 44/45 are closed.

## Task Commits

1. **Task 1: Share tagged parser and redact Claude logs** — `015aff0` (`refactor`).
2. **Task 2: Add per-call Chat Completions transport** — `8f7532d` (`feat`).
3. **Task 2 compatibility assertions** — `6a96f6d` (`test`).
4. **Task 2 SSE and backpressure fix** — `caf5f5d` (`fix`).

## Verification

- `dart analyze --fatal-infos` passed after each implementation step and on the final revision.
- The existing Dart gate passed on the final revision: 982 passed, 2 existing skips.
- The existing Flutter gate passed on the final revision: 165 passed, 7 existing skips.
- OpenAI API and local Ollama interoperability remain unobserved because no verified live endpoint was available. The adapter is not yet registered for config-driven selection; plan 02-18 owns that integration.
- D-17 preserves a hand-placed config key on later saves as an owner-approved exception to the Phase SPEC's literal no-write criterion. This plan neither changes config saving nor claims strict no-write compliance.

## Decisions Made

- Accept either a Base URL or a full Chat Completions URL, always derived from an explicit user setting. Only loopback HTTP is allowed; remote destinations require HTTPS.
- Keep the API key at the adapter edge as an optional constructor value. A missing key is allowed for local Ollama, while `api.openai.com` requires one before a request opens.
- Treat malformed SSE, non-stop termination, truncated streams, and non-200 responses as one of the four existing failure kinds with application-authored messages; no automatic retry or fallback is added.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Existing assertions required raw diagnostic text**
- **Found during:** Full Dart gate after Task 2.
- **Issue:** Two existing assertions expected a sidecar stderr body or raw stream exception in output, conflicting with the required privacy redaction.
- **Fix:** Updated those assertions in place to require a safe status and confirm the raw text is absent. No new test was added.
- **Files modified:** The two existing Claude provider/parser test files.
- **Commit:** `6a96f6d`; WINDOWS entry 48 fixed.

**2. [Rule 1 - Bug] Pause during connection setup and comment-only SSE frames**
- **Found during:** Task 2 source review after the first passing full gate.
- **Issue:** A consumer paused before HTTP connection completion could miss backpressure; comment-only frames accumulated toward the frame byte limit.
- **Fix:** Carried paused state through attachment and reset frame accounting on every blank-line delimiter.
- **Files modified:** The two new OpenAI-compatible adapter files.
- **Commit:** `caf5f5d`; WINDOWS entry 49 fixed.

## Issues Encountered

The first full Dart gate failed only the two legacy privacy assertions above. The affected suites and both full gates passed after correction. No live provider endpoint was available for interoperability observation.

## Next Phase Readiness

The transport is ready for secret resolution in plan 02-16 and config-driven registration in plan 02-18. PROVIDER-02 remains pending globally until those plans complete; this summary records only this plan's contribution.

## Self-Check: PASSED

- All five planned artifact paths and two updated existing test files exist.
- Commits `015aff0`, `8f7532d`, `6a96f6d`, and `caf5f5d` exist in history.

---
*Phase: 02-daemon-truth-settings-panel-teardown-provider-spine*
*Completed: 2026-09-24*
