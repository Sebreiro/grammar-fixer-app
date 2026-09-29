---
phase: 02-daemon-truth-settings-panel-teardown-provider-spine
plan: 18
subsystem: correction-provider-composition
tags: [dart, flutter, provider, secret-service, settings, cancellation]
requires:
  - phase: 02-15
    provides: bounded OpenAI-compatible HTTP adapter and shared register parser
  - phase: 02-16
    provides: read-only keyring, environment, config key resolver
  - phase: 02-17
    provides: compatible provider Settings fields and source-only display
provides:
  - Config-selected compatible provider alongside the unchanged Claude default
  - Credential lookup at the adapter edge and source-only Settings status
  - Startup warning and unconfigured correction for unknown provider IDs
affects: [PROVIDER-02, PROVIDER-03, 02-architecture-reconciliation]
actuals:
  tokens: 3020
  tasks: 2
  commits: 2
commits: 2
plan_head_before: 5b9bc4604ae0e5cf7752defd9c3e572575e1c95b
tech-stack:
  added: []
  patterns: [registry selection at composition, per-call credential resolution, source-only settings injection]
key-files:
  created: []
  modified:
    - lib/src/infrastructure/correction/provider_registry.dart
    - lib/src/infrastructure/correction/openai_compatible/openai_compatible_correction_provider.dart
    - lib/src/infrastructure/correction/active_correction.dart
    - lib/src/infrastructure/system/daemon_startup.dart
    - lib/src/application/composition/daemon_graph.dart
    - lib/src/application/settings_controller.dart
    - lib/main.dart
    - test/infrastructure/correction/active_correction_test.dart
key-decisions:
  - Keep Claude and claude-sonnet-5 as the shipped default, with no default live HTTP destination.
  - Resolve the selected compatible provider credential per correction at its adapter edge; Settings receives only the winning source label.
  - Warn for an unknown provider ID and use UnconfiguredCorrectionProvider without selecting Claude.
requirements-completed: [PROVIDER-02]
requirements-pending-global: [PROVIDER-03]
coverage:
  - id: PROVIDER-02-composition
    description: A selected compatible preset uses one configured endpoint, paired prompt and model, and source-priority credential resolution.
    requirement: PROVIDER-02
    verification:
      - kind: integration
        ref: dart analyze --fatal-infos; existing Dart and Flutter phase suites
        status: pass
      - kind: other
        ref: source inspection of ProviderRegistry, DaemonStartup, DaemonGraph, and OpenAiCompatibleCorrectionProvider
        status: pass
    human_judgment: true
    rationale: No verified OpenAI API or local Ollama target was available for a live interoperability observation.
  - id: PROVIDER-03-unknown
    description: An unknown selected ID warns at startup and yields one providerUnavailable event without a fallback provider.
    requirement: PROVIDER-03
    verification:
      - kind: integration
        ref: test/infrastructure/correction/active_correction_test.dart
        status: pass
    human_judgment: true
    rationale: The code path is complete; Wave F must still record the architecture decision required by PROVIDER-03.
duration: 9min
completed: 2026-09-24
status: complete
---

# Phase 02 Plan 18: Provider Composition Summary

**A configured OpenAI-compatible preset now selects one HTTP adapter with a per-call credential, while the shipped Claude preset remains the default.**

## Performance

- **Started:** 2026-09-24T18:55:30Z
- **Completed:** 2026-09-24T19:04:17Z
- **Duration:** 9 minutes
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Registered the compatible adapter beside Claude. The selected provider and its prompt/model preset are resolved together at startup and after a config change; each correction snapshots the active pair. The default config still contains only Claude/`claude-sonnet-5` and no live Base URL.
- Injected the read-only Secret Service resolver into the compatible factory. It reads keyring, then `OPENAI_API_KEY`, then a hand-placed config key. The HTTP adapter receives the key only for its own call; Settings receives only the winning source label and keeps its plaintext warning for a config-file source.
- Kept incomplete endpoint/model failures inline on first correction. Unknown IDs log a startup warning, select `UnconfiguredCorrectionProvider`, and never route to Claude. The existing controller cancels prior streams on submit and Retry, retains an active run on panel hide, and joins cancellation on teardown; each HTTP run closes its own request and client on cancellation.

## Task Commits

1. **Task 1: Register the compatible adapter without changing the default** — `92344dc` (`feat`).
2. **Task 2: Wire secret resolution, cancellation and unknown-ID warning** — `d0fbf8a` (`feat`).

## Verification

- `dart analyze --fatal-infos`: passed after each task.
- Existing Dart suite: 982 passed, 2 existing skips. Existing Flutter suite: 165 passed, 7 existing skips.
- Source inspection confirms one selected registry factory, no fallback branch, no default live endpoint, a source-only Settings callback, destination validation and no redirects, bounded HTTP/SSE parsing, and per-call transport cancellation.
- Live interoperability with OpenAI API and local Ollama remains unobserved because this workspace has no verified target. D-17 preserves a user-authored config key during a later whole-file save; this is the approved exception to the Phase 2 SPEC's literal no-write criterion, so strict compliance is not claimed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical wiring] Connect the credential resolver at both composition entries**
- **Found during:** Task 2.
- **Issue:** Registering the factory alone left startup and later config changes without a `SecretStore` resolver, and Settings without its source-only callback.
- **Fix:** Passed one resolver through `DaemonStartup`, `main.dart`, and `DaemonGraph` into the selected factory and Settings controller. These composition files extended the plan's initial file list.
- **Verification:** Analyzer and existing phase suites passed.
- **Committed in:** `d0fbf8a`.

**2. [Rule 3 - Existing assertion drift] Update the unknown-ID log expectation**
- **Found during:** Task 2 phase suite.
- **Issue:** An existing test expected an error log although PROVIDER-03 now requires a startup warning.
- **Fix:** Changed only the assertion's level and reason; the same test still proves one `providerUnavailable` event.
- **Verification:** Focused test and existing phase suites passed.
- **Committed in:** `d0fbf8a`.

## Known Stubs

None in files changed by this plan.

## Issues Encountered

No verified live HTTP endpoint was available. The two compatibility targets remain an observation limit, not a claimed passing runtime check.

The SDK state counter began at plan 16 although 02-17 already had a summary. After 02-18, two additional SDK advances corrected the next-plan position to 19. PROVIDER-03 remains pending globally until Wave F records its architecture decision.

## User Setup Required

To use the compatible provider, select it in Settings, enter a Base URL and a model for the active preset, and optionally supply a key through Secret Service, `OPENAI_API_KEY`, or a hand-placed config field. Local Ollama may use no key.

## Next Phase Readiness

Wave F can record the unknown-ID architecture rule. Live OpenAI/Ollama behavior remains unobserved until a verified target exists.

## Self-Check: PASSED

All eight changed source/test files and this summary exist; both task commits are present, the measured task-commit count is two, and `git diff --check` is clean.
