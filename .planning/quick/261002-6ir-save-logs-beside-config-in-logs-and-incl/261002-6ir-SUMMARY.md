---
status: complete
quick_id: 261002-6ir
date: 2026-10-02
---

# Config-adjacent cyclic logging and detailed provider errors

- Logs use `${XDG_CONFIG_HOME:-~/.config}/hotkey-grammar-corrector/logs/grammmar-corrector.log`.
- One cyclic JSON file, default `logMaxBytes: 1048576`, minimum 1024 bytes. Before the next entry would exceed the limit, the same file is reset. Oversized entries become marked summaries. No archive files are created.
- The size limit persists in config and Settings; both apply changes live through the existing config listener.
- Existing stderr diagnostics continue. Startup diagnostics queue until the lock holder knows its validated limit. Secondary launches never open the cyclic file. All explicit exits drain and close it under the existing shutdown budget; failed disk writes degrade safely to stderr.
- Every modeled correction failure logs safe session/kind context. HTTP errors retain bounded response bodies, metadata, Retry-After and request-id headers, including OpenRouter 429 responses. HTTP 200 JSON and SSE errors also retain details.
- Credentials, draft/prompt text, structured payload fields, and decoded suggestion text are redacted. Malformed JSON diagnostics are marked as omitted when they cannot be safely traversed. No provider port, schema, fallback, or Retry behavior changes.

## Commits

- `c5744d0` — configurable cyclic file logging and live settings/config propagation.
- `03fe3a6` — detailed HTTP/stream diagnostics and correction-failure logging.

## Verification

- `dart analyze --fatal-infos`: clean.
- Configured headless Dart suite: 1073 passed, 2 existing skips.
- Configured Flutter UI/platform/composition suite: 201 passed, 7 existing skips.
- Updated graph suite: 27 passed, including live logging limit changes from settings and external config.
- Final HTTP/credential/SSE/redaction suite: 32 passed; fixtures prove detailed HTTP 429 logs reach a real file, streaming details survive, echoed suggestions are redacted, interrupted/stalled bodies preserve diagnostics, bounded captures cancel, and a broken logger cannot replace failure events.
- Targeted file logger/HTTP/composition-wiring tests: 64 passed, including disk failure, startup queueing, secondary launch behavior, UTF-8 limits, complete cyclic JSON lines, and shutdown flushing.
- `git diff --check`: clean. Dart formatting checked.

## Workflow

Discussion, focused official-documentation research, plan check, execution, review, and verification were completed sequentially inline via the skill adapter fallback. The user clarified filename and cyclic configurable limit during execution; the plan and context were updated and rechecked before implementing that steering. No native desktop or live OpenRouter request was required for these deterministic fixtures.
