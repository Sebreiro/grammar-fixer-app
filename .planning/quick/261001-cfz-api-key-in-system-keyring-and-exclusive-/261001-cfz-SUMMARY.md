---
quick_id: 261001-cfz
status: complete
completed: 2026-10-01
---

# API key in system keyring and exclusive AI provider settings

Added a masked API-key field with an independent keyring save action and inline,
retryable failures. New keys never enter configuration, history or logs. The
Secret Service adapter creates or replaces app/provider-scoped keys, handles unlock
and creation prompts, and closes sessions and clients.

Settings now offer one provider radio group for Claude Agent SDK and URL-based
OpenAI-compatible use, preserving existing configured IDs. Only the selected
provider's presets and fields are shown. First-time URL setup creates a complete
prompt/model preset on save and retains Claude configuration. Switching configured
providers activates an existing complete preset through the config store.

## Commits

- `705e26a` — keyring port, Secret Service write flow, provider config/setup, graph wiring and tests.
- `e1f0ef4` — exclusive provider picker, conditional fields, masked key entry and UI tests.

## Validation

- `dart analyze --fatal-infos`: no issues.
- Dart domain/application/architecture/infrastructure/fake suites: 1,007 passed, 2 existing skips.
- Full Flutter UI/platform/composition suites: 188 passed, 7 existing skips.
- Final affected Flutter Settings/composition plus all integration suites: 112 passed.
- Keyring tests after final cleanup changes: 9 passed, including invalid prompt handling.
- Final API-field callback check: 5 widget tests passed.
- Fake-port smoke check after adding ProviderKeyWriter: 1 passed.
- Dart formatting and `git diff --check`: clean.

An initial broad Dart invocation included a Flutter-dependent integration file and
failed to load dart:ui. Corrected runner invocations above passed; no failures remain.

## Workflow notes

Discussion, focused research, plan checking, review and verification ran inline
per the skill's Codex spawn restriction. Backend setup helpers were grouped with
the persistence commit; the second commit owns presentation. ROADMAP and frozen
specs were left intact. No dependencies or additional AI providers were introduced.

## Observation limits

Real desktop keyring UI is unobserved. Automated checks use a private D-Bus Secret
Service and the real adapter, without touching any user's stored credentials.
