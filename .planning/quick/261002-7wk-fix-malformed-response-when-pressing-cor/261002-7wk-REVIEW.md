---
quick_id: 261002-7wk
status: passed
review_mode: inline
---

# Code review

Reviewed shared prompt formatting, both provider call sites, pure HTTP request mapping, Settings guidance, README, and all added/updated regressions. No unresolved blocking finding.

- Required format is supplied only by the tagged infrastructure adapters. Domain Preset, CorrectionProvider, Suggestion, history schema, and provider selection remain intact.
- Prompt composition preserves every character of the user's saved instructions as a prefix. Config migration and watchers are unchanged; config/Settings integration observes updated text on the next HTTP request.
- OpenRouter controls are gated by parsed endpoint host equality, never by model name or a URL substring. Lookalike hosts and URL paths containing openrouter.ai do not receive vendor fields.
- OpenRouter optional thinking is disabled and its reasoning output excluded; existing decoding forwards only content. Dedicated regression includes reasoning, reasoning_content, and reasoning_details.
- No parser tolerance, guessed variants, fallback provider, automatic correction retry, stream replay, or changed cancellation lifecycle was introduced.
- Request limits and credential/request-content sanitization remain in the existing HTTP adapter. Pure string composition adds no network, persistence, or widget I/O.
- Held-open HTTP integration requires a partial SuggestionDelta before the server supplies the sentinel; a test reproduces the exact initial W error as one failure event. Sidecar coverage reads the actual serialized stdin request.

The initial new streaming regression referenced event.delta, which the real type calls textDelta. The focused run caught the compile error; corrected before final verification. No production behavior depended on it.

This review was performed inline, not by an independent agent. At the initial review, live model compliance was unobserved because no OpenRouter credential was available.

## Follow-up review: OpenRouter final usage frame

Reviewed source repair 466be28 against the observed Ministral curl stream and OpenRouter's documented accounting frame. No unresolved blocking finding. The exception to duplicate-stop rejection requires an object-valued usage payload; the existing delta validation still rejects nonempty content after stopping. Non-stop finish reasons, generic duplicates, malformed deltas, missing DONE, top-level provider errors, byte bounds and cancellation behavior remain covered. The strict tagged parser and domain interfaces are unchanged.

Both pure and loopback regressions reproduced the failure before repair; 41 focused tests and a clean analyzer passed afterward. A subsequent actual Ministral correction streamed all three registers and completed, with no failure log. This live result applies to the requested Ministral model; the original Nemotron model remains unobserved. The OpenRouter key stayed in memory and user config was unchanged.
